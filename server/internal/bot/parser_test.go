package bot

import (
	"testing"

	"github.com/xensa/tally/internal/i18n"
	"github.com/xensa/tally/internal/model"
)

// expUSD is the decimal exponent of the default currency; most of the grammar
// is exponent-independent, so the table below uses it throughout.
const expUSD = 2

func TestParseMessage(t *testing.T) {
	tests := []struct {
		name    string
		text    string
		want    Parsed
		wantErr bool
	}{
		{
			name: "expense with category and note",
			text: "250 groceries weekly stuff",
			want: Parsed{AmountMinor: 25000, Kind: model.KindExpense, CategoryWord: "groceries", Note: "weekly stuff"},
		},
		{
			name: "dot decimals",
			text: "250.50 taxi",
			want: Parsed{AmountMinor: 25050, Kind: model.KindExpense, CategoryWord: "taxi"},
		},
		{
			name: "comma decimals",
			text: "250,50 taxi",
			want: Parsed{AmountMinor: 25050, Kind: model.KindExpense, CategoryWord: "taxi"},
		},
		{
			name: "single decimal digit means tenths",
			text: "250.5 taxi",
			want: Parsed{AmountMinor: 25050, Kind: model.KindExpense, CategoryWord: "taxi"},
		},
		{
			name: "income with plus prefix",
			text: "+50000 salary",
			want: Parsed{AmountMinor: 5000000, Kind: model.KindIncome, CategoryWord: "salary"},
		},
		{
			name: "amount only",
			text: "120",
			want: Parsed{AmountMinor: 12000, Kind: model.KindExpense},
		},
		{
			name: "income amount only with decimals",
			text: "+12.34",
			want: Parsed{AmountMinor: 1234, Kind: model.KindIncome},
		},
		{
			name: "multi word note",
			text: "9,99 subscriptions netflix monthly plan",
			want: Parsed{AmountMinor: 999, Kind: model.KindExpense, CategoryWord: "subscriptions", Note: "netflix monthly plan"},
		},
		{
			name: "cyrillic category word",
			text: "250 продукты на неделю",
			want: Parsed{AmountMinor: 25000, Kind: model.KindExpense, CategoryWord: "продукты", Note: "на неделю"},
		},
		{name: "zero rejected", text: "0 groceries", wantErr: true},
		{name: "zero with decimals rejected", text: "0.00 groceries", wantErr: true},
		{name: "negative rejected", text: "-50 groceries", wantErr: true},
		{name: "non numeric rejected", text: "abc groceries", wantErr: true},
		{name: "empty rejected", text: "   ", wantErr: true},
		{name: "three decimals rejected", text: "1.234 x", wantErr: true},
		{name: "double dot rejected", text: "1.2.3 x", wantErr: true},
		{name: "plus only rejected", text: "+ salary", wantErr: true},
		{name: "trailing dot rejected", text: "12. x", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ParseMessage(tt.text, expUSD)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("ParseMessage(%q) = %+v, want error", tt.text, got)
				}
				return
			}
			if err != nil {
				t.Fatalf("ParseMessage(%q) error: %v", tt.text, err)
			}
			if got != tt.want {
				t.Errorf("ParseMessage(%q) = %+v, want %+v", tt.text, got, tt.want)
			}
		})
	}
}

// TestParseMessageZeroDecimalCurrency: in a soʻm or yen ledger the minor unit
// IS the major unit, so "250" must store 250, not 25000 — the Flutter app
// scales typed amounts the same way, and the two peers share one database.
func TestParseMessageZeroDecimalCurrency(t *testing.T) {
	exp := i18n.CurrencyExp("UZS")
	if exp != 0 {
		t.Fatalf("CurrencyExp(UZS) = %d, want 0", exp)
	}
	tests := []struct {
		text    string
		want    int64
		wantErr bool
	}{
		{text: "250 oziq-ovqat", want: 250},
		{text: "+50000 maosh", want: 50000},
		{text: "12345600", want: 12345600},
		// A currency with no sub-unit has no decimals to type.
		{text: "250.50 taksi", wantErr: true},
		{text: "250,5 taksi", wantErr: true},
		{text: "0 taksi", wantErr: true},
	}
	for _, tt := range tests {
		got, err := ParseMessage(tt.text, exp)
		if tt.wantErr {
			if err == nil {
				t.Errorf("ParseMessage(%q, 0) = %+v, want error", tt.text, got)
			}
			continue
		}
		if err != nil {
			t.Fatalf("ParseMessage(%q, 0) error: %v", tt.text, err)
		}
		if got.AmountMinor != tt.want {
			t.Errorf("ParseMessage(%q, 0).AmountMinor = %d, want %d", tt.text, got.AmountMinor, tt.want)
		}
	}
}
