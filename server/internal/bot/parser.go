package bot

import (
	"errors"
	"math"
	"strconv"
	"strings"

	"github.com/xensa/tally/internal/model"
)

// ErrBadAmount signals a first token that is not a valid positive amount.
var ErrBadAmount = errors.New("bad amount")

// Parsed is the result of parsing a free-text entry message.
type Parsed struct {
	AmountMinor  int64  // always > 0
	Kind         string // "income" | "expense"
	CategoryWord string // second token, may be empty
	Note         string // remaining tokens joined, may be empty
}

// ParseMessage parses the free-text grammar:
//
//	250 groceries weekly stuff   → expense 250.00, word "groceries", note "weekly stuff"
//	250.50 taxi                  → decimals via . or ,
//	+50000 salary                → leading + means income
//	120                          → amount only
//
// exp is the active currency's decimal exponent (2 for USD, 0 for UZS and JPY),
// i.e. how many minor units one major unit is worth. It has to be a parameter:
// the Flutter app scales typed amounts by the same exponent, so a bot that
// always assumed 2 would store 100× the intended amount in a soʻm ledger.
func ParseMessage(text string, exp int) (Parsed, error) {
	fields := strings.Fields(text)
	if len(fields) == 0 {
		return Parsed{}, ErrBadAmount
	}
	tok := fields[0]
	kind := model.KindExpense
	if strings.HasPrefix(tok, "+") {
		kind = model.KindIncome
		tok = tok[1:]
	}
	minor, err := parseAmountMinor(tok, exp)
	if err != nil {
		return Parsed{}, err
	}
	p := Parsed{AmountMinor: minor, Kind: kind}
	if len(fields) > 1 {
		p.CategoryWord = fields[1]
	}
	if len(fields) > 2 {
		p.Note = strings.Join(fields[2:], " ")
	}
	return p, nil
}

// parseAmountMinor converts "250", "250.5", "250,50" to minor units at the
// given exponent. Rejects zero, negatives, non-numeric input and more decimals
// than the currency has (any decimals at all for a zero-decimal currency).
func parseAmountMinor(tok string, exp int) (int64, error) {
	if exp < 0 || exp > 4 {
		exp = 2
	}
	scale := pow10(exp)
	tok = strings.ReplaceAll(tok, ",", ".")
	if tok == "" {
		return 0, ErrBadAmount
	}
	wholeS, fracS, hasFrac := strings.Cut(tok, ".")
	if wholeS == "" || strings.ContainsAny(wholeS, "+-") {
		return 0, ErrBadAmount
	}
	whole, err := strconv.ParseInt(wholeS, 10, 64)
	if err != nil || whole < 0 {
		return 0, ErrBadAmount
	}
	var frac int64
	if hasFrac {
		if len(fracS) < 1 || len(fracS) > exp {
			return 0, ErrBadAmount
		}
		frac, err = strconv.ParseInt(fracS, 10, 64)
		if err != nil || frac < 0 {
			return 0, ErrBadAmount
		}
		// "250.5" at exp 2 means 250.50, not 250.05.
		for i := len(fracS); i < exp; i++ {
			frac *= 10
		}
	}
	if whole > (math.MaxInt64-frac)/scale {
		return 0, ErrBadAmount
	}
	minor := whole*scale + frac
	if minor <= 0 {
		return 0, ErrBadAmount
	}
	return minor, nil
}

func pow10(n int) int64 {
	v := int64(1)
	for i := 0; i < n; i++ {
		v *= 10
	}
	return v
}
