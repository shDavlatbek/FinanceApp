package bot

import (
	"strings"
	"testing"

	"github.com/xensa/tally/internal/model"
	"github.com/xensa/tally/internal/store"
	"golang.org/x/text/language"
)

var (
	groceriesCat = model.Category{
		ID: "c1a7e2f0-0001-4a00-9000-000000000001", Name: "Groceries",
		Emoji: "🛒", Kind: model.KindExpense,
	}
	cafeCat = model.Category{
		ID: "c1a7e2f0-0002-4a00-9000-000000000002", Name: "Cafe",
		Emoji: "☕", Kind: model.KindExpense,
	}
)

// TestRenderEntrySaved pins the contract's success reply, in every language.
func TestRenderEntrySaved(t *testing.T) {
	b := testBundle(t)
	tests := []struct {
		tag      language.Tag
		currency string
		want     string
	}{
		{language.Russian, "RUB", "✅ −250,00 ₽ • 🛒 Продукты — 3 450,00 ₽ за месяц"},
		{language.English, "USD", "✅ −$250.00 • 🛒 Groceries — $3,450.00 this month"},
		// Same stored minor units, different exponent: a soʻm ledger has no
		// sub-unit, so 25000 minor is 25 000 soʻm, not 250,00.
		{language.Uzbek, "UZS", "✅ −25 000 soʻm • 🛒 Oziq-ovqat — oy boshidan 345 000 soʻm"},
	}
	for _, tt := range tests {
		t.Run(tt.tag.String(), func(t *testing.T) {
			got := renderEntrySaved(b.Printer(tt.tag), tt.currency,
				model.KindExpense, 25000, 345000, groceriesCat)
			if got != tt.want {
				t.Errorf("renderEntrySaved =\n%q\nwant\n%q", got, tt.want)
			}
		})
	}
}

func TestRenderEntrySavedIncomeIsSigned(t *testing.T) {
	p := testBundle(t).Printer(language.Russian)
	salary := model.Category{
		ID: "c1a7e2f0-0101-4a00-9000-000000000101", Name: "Salary",
		Emoji: "💼", Kind: model.KindIncome,
	}
	got := renderEntrySaved(p, "RUB", model.KindIncome, 5000000, 5000000, salary)
	want := "✅ +50 000,00 ₽ • 💼 Зарплата — 50 000,00 ₽ за месяц"
	if got != want {
		t.Errorf("renderEntrySaved(income) = %q, want %q", got, want)
	}
}

// TestRenderSummaryRussianPlurals is the plural requirement in its real
// setting: the count line of a /today, /week or /month reply.
func TestRenderSummaryRussianPlurals(t *testing.T) {
	p := testBundle(t).Printer(language.Russian)
	tests := []struct {
		count int64
		want  string
	}{
		{1, "1 операция"},
		{2, "2 операции"},
		{5, "5 операций"},
		{21, "21 операция"},
		{22, "22 операции"},
		{111, "111 операций"},
	}
	for _, tt := range tests {
		sum := store.Summary{Income: 0, Expenses: 25000, Count: tt.count}
		got := renderSummary(p, "RUB", "📊 Сегодня · 20.08.2026", sum)
		if !strings.Contains(got, tt.want) {
			t.Errorf("renderSummary(count=%d) =\n%s\nmissing %q", tt.count, got, tt.want)
		}
	}
}

func TestRenderSummary(t *testing.T) {
	b := testBundle(t)
	sum := store.Summary{
		Income:   1000000,
		Expenses: 345000,
		Count:    3,
		TopExpenses: []store.CategoryTotal{
			{Category: groceriesCat, Total: 245000},
			{Category: cafeCat, Total: 100000},
		},
	}

	ru := renderSummary(b.Printer(language.Russian), "RUB", "📊 Август 2026", sum)
	wantRU := strings.Join([]string{
		"📊 Август 2026",
		"Итого: +6 550,00 ₽",
		"Доходы: 10 000,00 ₽",
		"Расходы: 3 450,00 ₽",
		"3 операции",
		"",
		"Больше всего потрачено:",
		"🛒 Продукты — 2 450,00 ₽",
		"██████████",
		"☕ Кафе — 1 000,00 ₽",
		"████",
	}, "\n")
	if ru != wantRU {
		t.Errorf("ru summary =\n%s\n\nwant\n%s", ru, wantRU)
	}

	en := renderSummary(b.Printer(language.English), "USD", "📊 August 2026", sum)
	for _, want := range []string{
		"Net: +$6,550.00", "Income: $10,000.00", "Expenses: $3,450.00",
		"3 transactions", "Top spending:", "🛒 Groceries — $2,450.00",
	} {
		if !strings.Contains(en, want) {
			t.Errorf("en summary is missing %q:\n%s", want, en)
		}
	}

	uz := renderSummary(b.Printer(language.Uzbek), "UZS", "📊 Avgust 2026", sum)
	for _, want := range []string{
		"Sof: +655 000 soʻm", "Daromad: 1 000 000 soʻm", "3 ta amaliyot",
		"Eng koʻp xarajat:", "🛒 Oziq-ovqat — 245 000 soʻm",
	} {
		if !strings.Contains(uz, want) {
			t.Errorf("uz summary is missing %q:\n%s", want, uz)
		}
	}
}

func TestRenderSummaryEmpty(t *testing.T) {
	b := testBundle(t)
	tests := []struct {
		tag  language.Tag
		want string
	}{
		{language.English, "📊 Today · Aug 20, 2026\nNo transactions yet."},
		{language.Russian, "📊 Today · Aug 20, 2026\nПока нет операций."},
		{language.Uzbek, "📊 Today · Aug 20, 2026\nHozircha amaliyotlar yoʻq."},
	}
	for _, tt := range tests {
		got := renderSummary(b.Printer(tt.tag), "USD", "📊 Today · Aug 20, 2026", store.Summary{})
		if got != tt.want {
			t.Errorf("%s empty summary = %q, want %q", tt.tag, got, tt.want)
		}
	}
}

func TestRenderUndo(t *testing.T) {
	b := testBundle(t)
	tx := model.Transaction{
		Kind: model.KindExpense, AmountMinor: 25000,
		CategoryID: groceriesCat.ID, Note: "на неделю",
	}

	got := renderUndo(b.Printer(language.Russian), "RUB", tx, &groceriesCat)
	want := "↩️ Удалено: −250,00 ₽ • 🛒 Продукты — на неделю"
	if got != want {
		t.Errorf("ru undo = %q, want %q", got, want)
	}

	// A missing category row must not break the confirmation.
	noNote := tx
	noNote.Note = ""
	got = renderUndo(b.Printer(language.Uzbek), "UZS", noNote, nil)
	want = "↩️ Oʻchirildi: −25 000 soʻm • (nomaʼlum turkum)"
	if got != want {
		t.Errorf("uz undo (unknown category) = %q, want %q", got, want)
	}
}

func TestRenderCategories(t *testing.T) {
	b := testBundle(t)
	renamed := model.Category{ID: cafeCat.ID, Name: "Coffee shop", Emoji: "☕", Kind: model.KindExpense}
	salary := model.Category{
		ID: "c1a7e2f0-0101-4a00-9000-000000000101", Name: "Salary",
		Emoji: "💼", Kind: model.KindIncome,
	}

	got := renderCategories(b.Printer(language.Russian), []model.Category{groceriesCat, renamed, salary})
	want := strings.Join([]string{
		"Категории расходов:",
		"🛒 Продукты",
		"☕ Coffee shop", // renamed seed: verbatim in every language
		"",
		"Категории доходов:",
		"💼 Зарплата",
	}, "\n")
	if got != want {
		t.Errorf("ru categories =\n%s\n\nwant\n%s", got, want)
	}
}

func TestRenderCategoriesEmptyKind(t *testing.T) {
	got := renderCategories(testBundle(t).Printer(language.English), []model.Category{groceriesCat})
	want := "Expense categories:\n🛒 Groceries\n\nIncome categories:\nNo categories yet."
	if got != want {
		t.Errorf("categories with no income kind = %q, want %q", got, want)
	}
}

func TestBar(t *testing.T) {
	tests := []struct {
		value, max int64
		want       string
	}{
		{0, 100, ""},
		{100, 100, "██████████"},
		{50, 100, "█████"},
		{1, 1000, "█"}, // never disappears entirely
		{100, 0, ""},
	}
	for _, tt := range tests {
		if got := bar(tt.value, tt.max); got != tt.want {
			t.Errorf("bar(%d, %d) = %q, want %q", tt.value, tt.max, got, tt.want)
		}
	}
}
