package bot

import (
	"testing"

	"github.com/xensa/tally/internal/i18n"
	"github.com/xensa/tally/internal/model"
	"github.com/xensa/tally/internal/store"
	"golang.org/x/text/language"
)

func testBundle(t *testing.T) *i18n.Bundle {
	t.Helper()
	b, err := i18n.New()
	if err != nil {
		t.Fatalf("i18n.New(): %v", err)
	}
	return b
}

// seedCategoriesOfKind returns the real contract seed rows, so the matcher is
// exercised against the same names a fresh install actually has.
func seedCategoriesOfKind(kind string) []model.Category {
	var out []model.Category
	for _, c := range store.SeedCategories {
		if c.Kind == kind {
			out = append(out, c)
		}
	}
	return out
}

func TestMatchCategory(t *testing.T) {
	cats := []model.Category{
		{ID: "1", Name: "Groceries", Kind: model.KindExpense},
		{ID: "2", Name: "Cafe", Kind: model.KindExpense},
		{ID: "3", Name: "Transport", Kind: model.KindExpense},
		{ID: "4", Name: "Travel", Kind: model.KindExpense},
		{ID: "5", Name: "Home", Kind: model.KindExpense},
	}
	// Non-seed ids: these carry only their stored name, which isolates the
	// matching algorithm from the localization layer.
	cands := candidates(testBundle(t), cats)
	tests := []struct {
		word   string
		wantID string // "" = no confident match
	}{
		{"groceries", "1"}, // exact
		{"GROCERIES", "1"}, // exact, case-insensitive
		{"groc", "1"},      // unique prefix
		{"cafe", "2"},      // exact
		{"tra", ""},        // ambiguous prefix: Transport vs Travel
		{"groseries", "1"}, // fuzzy distance 1
		{"grocerys", "1"},  // fuzzy distance 2
		{"cofe", "2"},      // fuzzy distance 1
		{"xyzzy", ""},      // nothing close
		{"", ""},           // empty
		{"hom", "5"},       // unique prefix
		{"homee", "5"},     // fuzzy distance 1
	}
	for _, tt := range tests {
		got := matchCategory(tt.word, cands)
		gotID := ""
		if got != nil {
			gotID = got.ID
		}
		if gotID != tt.wantID {
			t.Errorf("matchCategory(%q) = %q, want %q", tt.word, gotID, tt.wantID)
		}
	}
}

// TestMatchCategoryLocalizedNames is the contract requirement: matching
// considers the canonical English name AND the localized name in every
// supported language, so "продукты" and "groceries" both hit Groceries — no
// matter which language the bot happens to be replying in.
func TestMatchCategoryLocalizedNames(t *testing.T) {
	bundle := testBundle(t)
	expense := candidates(bundle, seedCategoriesOfKind(model.KindExpense))
	income := candidates(bundle, seedCategoriesOfKind(model.KindIncome))

	const (
		groceries = "c1a7e2f0-0001-4a00-9000-000000000001"
		cafe      = "c1a7e2f0-0002-4a00-9000-000000000002"
		health    = "c1a7e2f0-0006-4a00-9000-000000000006"
		fun       = "c1a7e2f0-0008-4a00-9000-000000000008"
		travel    = "c1a7e2f0-000a-4a00-9000-00000000000a"
		salary    = "c1a7e2f0-0101-4a00-9000-000000000101"
		gifts     = "c1a7e2f0-0103-4a00-9000-000000000103"
	)

	expenseTests := []struct {
		word   string
		wantID string
		why    string
	}{
		{"groceries", groceries, "canonical English"},
		{"продукты", groceries, "Russian exact"},
		{"Продукты", groceries, "Russian exact, capitalized"},
		{"продукт", groceries, "Russian prefix"},
		{"oziq-ovqat", groceries, "Uzbek exact"},
		{"кафе", cafe, "Russian exact"},
		{"кофе", cafe, "Russian fuzzy, distance 1"},
		{"здоровье", health, "Russian exact"},
		{"sogʻliq", health, "Uzbek exact"},
		{"развлечения", fun, "Russian exact"},
		{"путешествия", travel, "Russian exact"},
		{"sayohat", travel, "Uzbek exact"},
	}
	for _, tt := range expenseTests {
		got := matchCategory(tt.word, expense)
		gotID := ""
		if got != nil {
			gotID = got.ID
		}
		if gotID != tt.wantID {
			t.Errorf("matchCategory(%q) [%s] = %q, want %q", tt.word, tt.why, gotID, tt.wantID)
		}
	}

	incomeTests := []struct{ word, wantID string }{
		{"salary", salary},
		{"зарплата", salary},
		{"maosh", salary},
		{"подарки", gifts},
		{"sovgʻalar", gifts},
	}
	for _, tt := range incomeTests {
		got := matchCategory(tt.word, income)
		gotID := ""
		if got != nil {
			gotID = got.ID
		}
		if gotID != tt.wantID {
			t.Errorf("matchCategory(%q) [income] = %q, want %q", tt.word, gotID, tt.wantID)
		}
	}
}

// TestMatchCategoryRenamedSeedIsNotLocalized: once the user renames a seed
// category it is user data, so only its literal name matches — the old
// translations must stop resolving to it.
func TestMatchCategoryRenamedSeedIsNotLocalized(t *testing.T) {
	renamed := model.Category{
		ID:   "c1a7e2f0-0001-4a00-9000-000000000001",
		Name: "Supermarket", // no longer the canonical "Groceries"
		Kind: model.KindExpense,
	}
	cands := candidates(testBundle(t), []model.Category{renamed})
	if got := matchCategory("supermarket", cands); got == nil || got.ID != renamed.ID {
		t.Errorf("matchCategory(supermarket) = %v, want the renamed category", got)
	}
	if got := matchCategory("продукты", cands); got != nil {
		t.Errorf("matchCategory(продукты) = %v, want no match on a renamed seed", got)
	}
}

func TestCandidatesNames(t *testing.T) {
	bundle := testBundle(t)

	seed := model.Category{
		ID:   "c1a7e2f0-0001-4a00-9000-000000000001",
		Name: "Groceries",
		Kind: model.KindExpense,
	}
	got := candidates(bundle, []model.Category{seed})[0].Names
	want := []string{"Groceries", "Продукты", "Oziq-ovqat"}
	if len(got) != len(want) {
		t.Fatalf("candidates names = %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("candidates names[%d] = %q, want %q", i, got[i], want[i])
		}
	}

	user := model.Category{ID: "user-1", Name: "Books", Kind: model.KindExpense}
	if got := candidates(bundle, []model.Category{user})[0].Names; len(got) != 1 || got[0] != "Books" {
		t.Errorf("user category names = %v, want [Books]", got)
	}
}

// TestDisplayName pins the seed-name rule the bot shares with the app.
func TestDisplayName(t *testing.T) {
	bundle := testBundle(t)
	ru := bundle.Printer(language.Russian)
	uz := bundle.Printer(language.Uzbek)
	en := bundle.Printer(language.English)

	seed := model.Category{
		ID: "c1a7e2f0-0001-4a00-9000-000000000001", Name: "Groceries",
		Emoji: "🛒", Kind: model.KindExpense,
	}
	if got, want := displayName(ru, seed), "Продукты"; got != want {
		t.Errorf("displayName(ru, seed) = %q, want %q", got, want)
	}
	if got, want := displayName(uz, seed), "Oziq-ovqat"; got != want {
		t.Errorf("displayName(uz, seed) = %q, want %q", got, want)
	}
	if got, want := displayName(en, seed), "Groceries"; got != want {
		t.Errorf("displayName(en, seed) = %q, want %q", got, want)
	}
	if got, want := label(ru, seed), "🛒 Продукты"; got != want {
		t.Errorf("label(ru, seed) = %q, want %q", got, want)
	}

	renamed := seed
	renamed.Name = "Supermarket"
	for _, p := range []*i18n.Printer{en, ru, uz} {
		if got := displayName(p, renamed); got != "Supermarket" {
			t.Errorf("displayName(%s, renamed) = %q, want %q", p.Lang(), got, "Supermarket")
		}
	}

	user := model.Category{ID: "user-1", Name: "Книги", Kind: model.KindExpense}
	if got := displayName(en, user); got != "Книги" {
		t.Errorf("displayName(en, user category) = %q, want %q", got, "Книги")
	}
}

func TestLevenshtein(t *testing.T) {
	tests := []struct {
		a, b string
		want int
	}{
		{"", "", 0},
		{"a", "", 1},
		{"", "abc", 3},
		{"kitten", "sitting", 3},
		{"cafe", "cofe", 1},
		{"groceries", "grocery", 3},
		{"groceries", "grocerys", 2},
		{"кафе", "кофе", 1}, // rune-wise, not byte-wise
	}
	for _, tt := range tests {
		if got := levenshtein(tt.a, tt.b); got != tt.want {
			t.Errorf("levenshtein(%q, %q) = %d, want %d", tt.a, tt.b, got, tt.want)
		}
	}
}
