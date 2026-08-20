package i18n

import (
	"strconv"
	"strings"
	"time"

	"golang.org/x/text/language"
)

// minusSign is U+2212, the typographic minus used in every reply (matching the
// contract's example "✅ −250,00 ₽ • …"). It is not an ASCII hyphen.
const minusSign = "−"

// conventions are the per-locale number, money and date rules.
//
// Money placement keys off the SYMBOL CLASS, not just the locale: a glyph
// symbol ($ € ₽) follows the locale's own rule, while a word or an unknown ISO
// code always trails the amount — "12 345 600 soʻm" reads, "soʻm12,345,600"
// does not.
type conventions struct {
	group     string // thousands separator
	decimal   string // decimal separator
	symbolFmt string // %v = amount, %c = symbol; for glyph symbols
	wordFmt   string // same, for word/ISO-code symbols
	dateFmt   string // Go reference layout
	months    [12]string
}

// Go's time package ships no localized month names, so each locale carries a
// 12-entry table (docs/ARCHITECTURE.md § Internationalization). Russian and
// Uzbek names are nominative — they are only ever emitted standalone, as in
// "Август 2026", never inside a day-of-month phrase.
var localeConventions = map[language.Tag]conventions{
	language.English: {
		group: ",", decimal: ".", symbolFmt: "%c%v", wordFmt: "%v %c",
		dateFmt: "Jan 2, 2006",
		months: [12]string{"January", "February", "March", "April", "May", "June",
			"July", "August", "September", "October", "November", "December"},
	},
	language.Russian: {
		group: " ", decimal: ",", symbolFmt: "%v %c", wordFmt: "%v %c",
		dateFmt: "02.01.2006",
		months: [12]string{"Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
			"Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"},
	},
	language.Uzbek: {
		group: " ", decimal: ",", symbolFmt: "%v %c", wordFmt: "%v %c",
		dateFmt: "02.01.2006",
		months: [12]string{"Yanvar", "Fevral", "Mart", "Aprel", "May", "Iyun",
			"Iyul", "Avgust", "Sentabr", "Oktabr", "Noyabr", "Dekabr"},
	},
}

func conventionsFor(tag language.Tag) conventions {
	if c, ok := localeConventions[tag]; ok {
		return c
	}
	return localeConventions[language.English]
}

// currencyInfo describes how one ISO-4217 code is rendered.
type currencyInfo struct {
	exp    int               // decimal digits: 2 for USD, 0 for UZS/JPY/KRW
	symbol string            // default symbol
	word   bool              // symbol is a word, not a glyph → always trails
	alt    map[string]string // per-language symbol override, keyed by "ru"/"uz"/"en"
}

// currencies covers the codes a self-hoster is plausibly going to pick. The
// exponents match the Flutter app's decimalDigitsFor(), which drives how many
// minor units a typed amount becomes — the two must agree or the peers would
// disagree about what "250" means.
var currencies = map[string]currencyInfo{
	"USD": {exp: 2, symbol: "$"},
	"EUR": {exp: 2, symbol: "€"},
	"GBP": {exp: 2, symbol: "£"},
	"RUB": {exp: 2, symbol: "₽"},
	"UAH": {exp: 2, symbol: "₴"},
	"KZT": {exp: 2, symbol: "₸"},
	"TRY": {exp: 2, symbol: "₺"},
	"INR": {exp: 2, symbol: "₹"},
	"CNY": {exp: 2, symbol: "¥"},
	"UZS": {exp: 0, symbol: "soʻm", word: true, alt: map[string]string{"ru": "сум"}},
	"JPY": {exp: 0, symbol: "¥"},
	"KRW": {exp: 0, symbol: "₩"},
}

// lookupCurrency returns the rendering rules for code. An unknown code is
// rendered as itself with two decimals — never a silent wrong symbol.
func lookupCurrency(code string) currencyInfo {
	code = strings.ToUpper(strings.TrimSpace(code))
	if code == "" {
		code = "USD"
	}
	if c, ok := currencies[code]; ok {
		return c
	}
	return currencyInfo{exp: 2, symbol: code, word: true}
}

// CurrencyExp returns the number of decimal digits of an ISO-4217 code
// (2 for USD, 0 for UZS and JPY). It is the scale between a typed amount and
// the stored amount_minor.
func CurrencyExp(code string) int { return lookupCurrency(code).exp }

// Money formats integer minor units for an ISO-4217 code.
//
// The arithmetic is exact: minor units are split with string surgery, never
// converted to a float, so no rounding drift can reach a ledger.
//
//	en/USD  1234.56 → "$1,234.56"
//	ru/RUB  1234.56 → "1 234,56 ₽"
//	ru/UZS 12345600 → "12 345 600 сум"
func (p *Printer) Money(minor int64, code string) string {
	c := lookupCurrency(code)
	symbol := c.symbol
	if s, ok := c.alt[p.Lang()]; ok {
		symbol = s
	}

	neg := minor < 0
	digits := absDigits(minor)

	intPart, fracPart := digits, ""
	if c.exp > 0 {
		for len(digits) <= c.exp {
			digits = "0" + digits
		}
		intPart, fracPart = digits[:len(digits)-c.exp], digits[len(digits)-c.exp:]
	}

	amount := group(intPart, p.conv.group)
	if fracPart != "" {
		amount += p.conv.decimal + fracPart
	}

	layout := p.conv.symbolFmt
	if c.word {
		layout = p.conv.wordFmt
	}
	out := strings.NewReplacer("%v", amount, "%c", symbol).Replace(layout)
	if neg {
		out = minusSign + out
	}
	return out
}

// MoneySigned is Money with an explicit sign always present: "+" for zero and
// positive, "−" (U+2212) for negative. Used for transaction amounts and the
// period net, where the direction of the money is the point.
func (p *Printer) MoneySigned(minor int64, code string) string {
	s := p.Money(minor, code)
	if minor < 0 {
		return s // Money already prefixed the minus
	}
	return "+" + s
}

// Number formats an integer with this locale's group separator.
func (p *Printer) Number(n int64) string {
	s := group(absDigits(n), p.conv.group)
	if n < 0 {
		return minusSign + s
	}
	return s
}

// Date formats a date with this locale's numeric layout.
func (p *Printer) Date(t time.Time) string { return t.Format(p.conv.dateFmt) }

// MonthYear formats "August 2026" / "Август 2026" / "Avgust 2026" from the
// per-locale month table.
func (p *Printer) MonthYear(t time.Time) string {
	return p.conv.months[int(t.Month())-1] + " " + strconv.Itoa(t.Year())
}

// absDigits returns the decimal digits of |n|, correct for math.MinInt64
// (whose negation overflows, which is why this goes through strings).
func absDigits(n int64) string {
	s := strconv.FormatInt(n, 10)
	return strings.TrimPrefix(s, "-")
}

// group inserts sep every three digits from the right.
func group(s, sep string) string {
	if len(s) <= 3 || sep == "" {
		return s
	}
	var b strings.Builder
	lead := len(s) % 3
	if lead > 0 {
		b.WriteString(s[:lead])
	}
	for i := lead; i < len(s); i += 3 {
		if b.Len() > 0 {
			b.WriteString(sep)
		}
		b.WriteString(s[i : i+3])
	}
	return b.String()
}
