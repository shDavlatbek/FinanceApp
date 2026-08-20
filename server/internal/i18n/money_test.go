package i18n

import (
	"math"
	"testing"
	"time"

	"golang.org/x/text/language"
)

func TestMoney(t *testing.T) {
	b := testBundle(t)
	tests := []struct {
		name  string
		tag   language.Tag
		minor int64
		code  string
		want  string
	}{
		// Symbol placement is per locale: prefix in English, suffix in the
		// other two. x/text/currency gets the Russian case wrong ("₽ 1 234,56"),
		// which is why this is hand-rolled.
		{"en usd", language.English, 123456, "USD", "$1,234.56"},
		{"ru rub", language.Russian, 123456, "RUB", "1 234,56 ₽"},
		{"uz usd", language.Uzbek, 123456, "USD", "1 234,56 $"},
		{"en eur", language.English, 123456, "EUR", "€1,234.56"},

		{"en sub-unit", language.English, 5, "USD", "$0.05"},
		{"ru sub-unit", language.Russian, 5, "RUB", "0,05 ₽"},
		{"en whole", language.English, 100, "USD", "$1.00"},
		{"en millions", language.English, 123456789, "USD", "$1,234,567.89"},
		{"ru millions", language.Russian, 123456789, "RUB", "1 234 567,89 ₽"},

		// Zero-decimal currencies: the minor unit IS the major unit, so no
		// decimal separator may appear at all.
		{"en uzs", language.English, 12345600, "UZS", "12,345,600 soʻm"},
		{"ru uzs", language.Russian, 12345600, "UZS", "12 345 600 сум"},
		{"uz uzs", language.Uzbek, 12345600, "UZS", "12 345 600 soʻm"},
		{"en jpy", language.English, 1234, "JPY", "¥1,234"},
		{"ru jpy", language.Russian, 1234, "JPY", "1 234 ¥"},
		{"en krw small", language.English, 5, "KRW", "₩5"},

		// A word-class symbol always trails, even in English, because
		// "soʻm12,345,600" does not read.
		{"unknown code trails", language.English, 123456, "XYZ", "1,234.56 XYZ"},
		{"lowercase code normalized", language.English, 123456, "usd", "$1,234.56"},
		{"empty code defaults to usd", language.English, 123456, "", "$1,234.56"},

		// Money keeps a minus but adds no plus; MoneySigned does the sign work.
		{"en negative", language.English, -123456, "USD", "−$1,234.56"},
		{"ru negative", language.Russian, -50000, "RUB", "−500,00 ₽"},
		{"zero", language.English, 0, "USD", "$0.00"},
		{"zero-decimal zero", language.English, 0, "JPY", "¥0"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := b.Printer(tt.tag).Money(tt.minor, tt.code); got != tt.want {
				t.Errorf("Money(%d, %q) in %s = %q, want %q", tt.minor, tt.code, tt.tag, got, tt.want)
			}
		})
	}
}

func TestMoneySigned(t *testing.T) {
	b := testBundle(t)
	tests := []struct {
		tag   language.Tag
		minor int64
		code  string
		want  string
	}{
		{language.English, 25000, "USD", "+$250.00"},
		{language.English, -25000, "USD", "−$250.00"},
		{language.Russian, -25000, "RUB", "−250,00 ₽"},
		{language.Russian, 5000000, "RUB", "+50 000,00 ₽"},
		{language.Uzbek, -250000, "UZS", "−250 000 soʻm"},
		{language.English, 0, "USD", "+$0.00"},
	}
	for _, tt := range tests {
		if got := b.Printer(tt.tag).MoneySigned(tt.minor, tt.code); got != tt.want {
			t.Errorf("MoneySigned(%d, %q) in %s = %q, want %q", tt.minor, tt.code, tt.tag, got, tt.want)
		}
	}
}

// TestMoneyExtremes: the formatter must never overflow. Negating math.MinInt64
// wraps, so the sign is stripped from the decimal string instead.
func TestMoneyExtremes(t *testing.T) {
	p := testBundle(t).Printer(language.English)
	if got, want := p.Money(math.MaxInt64, "USD"), "$92,233,720,368,547,758.07"; got != want {
		t.Errorf("Money(MaxInt64) = %q, want %q", got, want)
	}
	if got, want := p.Money(math.MinInt64, "USD"), "−$92,233,720,368,547,758.08"; got != want {
		t.Errorf("Money(MinInt64) = %q, want %q", got, want)
	}
}

func TestCurrencyExp(t *testing.T) {
	tests := []struct {
		code string
		want int
	}{
		{"USD", 2}, {"RUB", 2}, {"EUR", 2},
		{"UZS", 0}, {"JPY", 0}, {"KRW", 0},
		{"uzs", 0},
		{"", 2},     // default currency
		{"NOPE", 2}, // unknown codes assume the common case
		{"  USD  ", 2},
	}
	for _, tt := range tests {
		if got := CurrencyExp(tt.code); got != tt.want {
			t.Errorf("CurrencyExp(%q) = %d, want %d", tt.code, got, tt.want)
		}
	}
}

func TestNumber(t *testing.T) {
	b := testBundle(t)
	tests := []struct {
		tag  language.Tag
		n    int64
		want string
	}{
		{language.English, 0, "0"},
		{language.English, 999, "999"},
		{language.English, 1234567, "1,234,567"},
		{language.Russian, 1234567, "1 234 567"},
		{language.Uzbek, 1234567, "1 234 567"},
		{language.Russian, -1234, "−1 234"},
	}
	for _, tt := range tests {
		if got := b.Printer(tt.tag).Number(tt.n); got != tt.want {
			t.Errorf("Number(%d) in %s = %q, want %q", tt.n, tt.tag, got, tt.want)
		}
	}
}

func TestDateAndMonthYear(t *testing.T) {
	b := testBundle(t)
	day := time.Date(2026, time.August, 20, 13, 45, 0, 0, time.UTC)
	tests := []struct {
		tag                 language.Tag
		wantDate, wantMonth string
	}{
		{language.English, "Aug 20, 2026", "August 2026"},
		{language.Russian, "20.08.2026", "Август 2026"},
		{language.Uzbek, "20.08.2026", "Avgust 2026"},
	}
	for _, tt := range tests {
		p := b.Printer(tt.tag)
		if got := p.Date(day); got != tt.wantDate {
			t.Errorf("Date in %s = %q, want %q", tt.tag, got, tt.wantDate)
		}
		if got := p.MonthYear(day); got != tt.wantMonth {
			t.Errorf("MonthYear in %s = %q, want %q", tt.tag, got, tt.wantMonth)
		}
	}
}

// TestMonthTablesAreComplete: Go's stdlib has no localized month names, so each
// locale carries a 12-entry table — an empty slot would print a blank header.
func TestMonthTablesAreComplete(t *testing.T) {
	for _, tag := range Supported {
		conv := conventionsFor(tag)
		for i, name := range conv.months {
			if name == "" {
				t.Errorf("%s month table slot %d is empty", tag, i+1)
			}
		}
	}
}
