package i18n

import (
	"testing"

	"github.com/BurntSushi/toml"
	"golang.org/x/text/language"
)

func testBundle(t *testing.T) *Bundle {
	t.Helper()
	b, err := New()
	if err != nil {
		t.Fatalf("New(): %v", err)
	}
	return b
}

// TestNormalize pins the explicit base-language switch the contract mandates.
// language.NewMatcher gets three of these wrong — it maps kk to Russian with
// confidence High and uz-Cyrl to Russian too — which is why it is not used.
func TestNormalize(t *testing.T) {
	tests := []struct {
		code string
		want language.Tag
	}{
		{"ru", language.Russian},
		{"ru-RU", language.Russian},
		{"uz", language.Uzbek},
		{"uz-Latn", language.Uzbek},
		{"uz-Cyrl", language.Uzbek}, // must NOT become Russian
		{"uz-Cyrl-UZ", language.Uzbek},
		{"kk", language.English}, // Kazakh is not Russian
		{"de", language.English},
		{"", language.English},
		{"en", language.English},
		{"en-GB", language.English},
		{"not a tag", language.English},
	}
	for _, tt := range tests {
		if got := Normalize(tt.code); got != tt.want {
			t.Errorf("Normalize(%q) = %s, want %s", tt.code, got, tt.want)
		}
	}
}

// TestResolve covers the contract's order:
// settings.language → Telegram user.language_code → English.
func TestResolve(t *testing.T) {
	tests := []struct {
		name     string
		settings string
		telegram string
		want     language.Tag
	}{
		{"settings wins over telegram", "ru", "en", language.Russian},
		{"settings wins for uzbek", "uz", "ru", language.Uzbek},
		{"empty settings falls back to telegram", "", "ru", language.Russian},
		{"empty settings, uz-Cyrl telegram", "", "uz-Cyrl", language.Uzbek},
		{"empty settings, kazakh telegram", "", "kk", language.English},
		{"both empty", "", "", language.English},
		{"unsupported settings value degrades to english", "fr", "ru", language.English},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := Resolve(tt.settings, tt.telegram); got != tt.want {
				t.Errorf("Resolve(%q, %q) = %s, want %s", tt.settings, tt.telegram, got, tt.want)
			}
		})
	}
}

// TestRussianPlurals is the one that matters: ru needs one/few/many, and the
// boundaries (21 is one, 22 is few, 111 is many) are exactly what hand-rolled
// plural code gets wrong.
func TestRussianPlurals(t *testing.T) {
	p := testBundle(t).Printer(language.Russian)
	tests := []struct {
		n    int
		want string
	}{
		{0, "0 операций"},   // many
		{1, "1 операция"},   // one
		{2, "2 операции"},   // few
		{5, "5 операций"},   // many
		{11, "11 операций"}, // many (the i%100==11 exception to "one")
		{21, "21 операция"}, // one
		{22, "22 операции"}, // few
		{25, "25 операций"}, // many
		{111, "111 операций"},
		{121, "121 операция"},
	}
	for _, tt := range tests {
		if got := p.N("tx_count", tt.n, nil); got != tt.want {
			t.Errorf("ru tx_count(%d) = %q, want %q", tt.n, got, tt.want)
		}
	}
}

func TestEnglishAndUzbekPlurals(t *testing.T) {
	b := testBundle(t)
	en := b.Printer(language.English)
	uz := b.Printer(language.Uzbek)
	tests := []struct {
		n              int
		wantEn, wantUz string
	}{
		{0, "0 transactions", "0 ta amaliyot"},
		{1, "1 transaction", "1 ta amaliyot"},
		{2, "2 transactions", "2 ta amaliyot"},
		{21, "21 transactions", "21 ta amaliyot"},
	}
	for _, tt := range tests {
		if got := en.N("tx_count", tt.n, nil); got != tt.wantEn {
			t.Errorf("en tx_count(%d) = %q, want %q", tt.n, got, tt.wantEn)
		}
		if got := uz.N("tx_count", tt.n, nil); got != tt.wantUz {
			t.Errorf("uz tx_count(%d) = %q, want %q", tt.n, got, tt.wantUz)
		}
	}
}

// TestPluralCountUsesLocaleGrouping: {{.Count}} is pre-formatted, so a Russian
// reply says "1 234", not "1234" — while the plural form still keys off 1234.
func TestPluralCountUsesLocaleGrouping(t *testing.T) {
	b := testBundle(t)
	if got, want := b.Printer(language.Russian).N("tx_count", 1234, nil), "1 234 операции"; got != want {
		t.Errorf("ru tx_count(1234) = %q, want %q", got, want)
	}
	if got, want := b.Printer(language.English).N("tx_count", 1234, nil), "1,234 transactions"; got != want {
		t.Errorf("en tx_count(1234) = %q, want %q", got, want)
	}
}

// TestMissingKeyNeverFails: a translation gap must degrade, never break a
// reply. An id absent from every catalog comes back as the id itself.
func TestMissingKeyNeverFails(t *testing.T) {
	b := testBundle(t)
	for _, tag := range Supported {
		p := b.Printer(tag)
		if got := p.T("no_such_message_id"); got != "no_such_message_id" {
			t.Errorf("%s T(missing) = %q, want the id back", tag, got)
		}
		if got := p.N("no_such_plural_id", 3, nil); got != "no_such_plural_id" {
			t.Errorf("%s N(missing) = %q, want the id back", tag, got)
		}
		if got := p.Tf("no_such_message_id", map[string]any{"X": 1}); got == "" {
			t.Errorf("%s Tf(missing) returned empty", tag)
		}
	}
}

func TestTemplateData(t *testing.T) {
	b := testBundle(t)
	got := b.Printer(language.Russian).Tf("pick_category", map[string]any{"Amount": "−250,00 ₽"})
	want := "Выберите категорию для −250,00 ₽:"
	if got != want {
		t.Errorf("ru pick_category = %q, want %q", got, want)
	}
}

func TestPrinterFallsBackToEnglishForUnsupportedTag(t *testing.T) {
	b := testBundle(t)
	if got := b.Printer(language.German).Lang(); got != "en" {
		t.Errorf("Printer(de).Lang() = %q, want %q", got, "en")
	}
}

// ---------------------------------------------------------------------------
// catalog integrity
// ---------------------------------------------------------------------------

// rawCatalog parses one locale file into id -> plural form -> text.
func rawCatalog(t *testing.T, lang string) map[string]map[string]string {
	t.Helper()
	data, err := localeFS.ReadFile("locales/" + lang + ".toml")
	if err != nil {
		t.Fatalf("read %s catalog: %v", lang, err)
	}
	var raw map[string]map[string]string
	if err := toml.Unmarshal(data, &raw); err != nil {
		t.Fatalf("parse %s catalog: %v", lang, err)
	}
	return raw
}

// TestCatalogsAreComplete keeps translators honest: identical id sets in all
// three files, "other" everywhere, and the full CLDR plural set in Russian for
// every message English marks as plural.
func TestCatalogsAreComplete(t *testing.T) {
	en := rawCatalog(t, "en")
	ru := rawCatalog(t, "ru")
	uz := rawCatalog(t, "uz")

	if len(en) == 0 {
		t.Fatal("English catalog is empty")
	}
	t.Logf("catalog size: %d ids x %d languages", len(en), len(Supported))

	for _, other := range []struct {
		lang string
		cat  map[string]map[string]string
	}{{"ru", ru}, {"uz", uz}} {
		for id := range en {
			if _, ok := other.cat[id]; !ok {
				t.Errorf("%s.toml is missing id %q", other.lang, id)
			}
		}
		for id := range other.cat {
			if _, ok := en[id]; !ok {
				t.Errorf("%s.toml has id %q that en.toml does not", other.lang, id)
			}
		}
	}

	for lang, cat := range map[string]map[string]map[string]string{"en": en, "ru": ru, "uz": uz} {
		for id, forms := range cat {
			if forms["other"] == "" {
				t.Errorf("%s.toml: %q has no \"other\" form", lang, id)
			}
		}
	}

	// Plural ids: whatever English marks with "one" needs the full CLDR set in
	// Russian (one/few/many/other) and one/other in Uzbek.
	for id, forms := range en {
		if _, plural := forms["one"]; !plural {
			continue
		}
		for _, form := range []string{"one", "few", "many", "other"} {
			if ru[id][form] == "" {
				t.Errorf("ru.toml: plural %q is missing the %q form", id, form)
			}
		}
		for _, form := range []string{"one", "other"} {
			if uz[id][form] == "" {
				t.Errorf("uz.toml: plural %q is missing the %q form", id, form)
			}
		}
	}
}

// TestEverySeedCategoryIsTranslated guards the seed-name rule's data: all 15
// canonical names need a catalog entry in all three languages, or a Russian
// user would see an English category name in the keyboard.
func TestEverySeedCategoryIsTranslated(t *testing.T) {
	b := testBundle(t)
	en := rawCatalog(t, "en")
	if len(seedNameKeys) != 15 {
		t.Fatalf("seedNameKeys has %d entries, want the contract's 15", len(seedNameKeys))
	}
	for canonical, key := range seedNameKeys {
		if _, ok := en[key]; !ok {
			t.Errorf("catalog has no entry %q for seed category %q", key, canonical)
		}
		for _, tag := range Supported {
			got := b.Printer(tag).SeedName(canonical)
			if got == "" || got == key {
				t.Errorf("SeedName(%q) in %s = %q", canonical, tag, got)
			}
		}
	}
}

func TestSeedName(t *testing.T) {
	b := testBundle(t)
	tests := []struct {
		tag       language.Tag
		canonical string
		want      string
	}{
		{language.English, "Groceries", "Groceries"},
		{language.Russian, "Groceries", "Продукты"},
		{language.Uzbek, "Groceries", "Oziq-ovqat"},
		{language.Russian, "Other income", "Прочий доход"},
		{language.Uzbek, "Fun", "Koʻngilochar"},
		// A user category name is not a seed name: returned verbatim.
		{language.Russian, "Books", "Books"},
	}
	for _, tt := range tests {
		if got := b.Printer(tt.tag).SeedName(tt.canonical); got != tt.want {
			t.Errorf("%s SeedName(%q) = %q, want %q", tt.tag, tt.canonical, got, tt.want)
		}
	}
}

func TestSeedNameVariants(t *testing.T) {
	b := testBundle(t)

	got := b.SeedNameVariants("Groceries")
	want := map[string]bool{"Продукты": true, "Oziq-ovqat": true}
	if len(got) != len(want) {
		t.Fatalf("SeedNameVariants(Groceries) = %v, want %d entries", got, len(want))
	}
	for _, name := range got {
		if !want[name] {
			t.Errorf("SeedNameVariants(Groceries) returned unexpected %q", name)
		}
	}

	// The canonical name and duplicate translations are dropped: Uzbek
	// "Transport" is the English word, so only the Russian form remains.
	if got := b.SeedNameVariants("Transport"); len(got) != 1 || got[0] != "Транспорт" {
		t.Errorf("SeedNameVariants(Transport) = %v, want [Транспорт]", got)
	}

	if got := b.SeedNameVariants("Books"); got != nil {
		t.Errorf("SeedNameVariants(non-seed) = %v, want nil", got)
	}
}
