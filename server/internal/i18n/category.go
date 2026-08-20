package i18n

import "strings"

// seedNameKeys maps a seed category's CANONICAL ENGLISH name to its catalog id.
//
// Keying on the name rather than the UUID keeps the fixed ids in exactly one
// place (internal/store), and the canonical name is what store.IsUnrenamedSeed
// has just proven the row still carries. The values mirror the Flutter app's
// seedCategory* ARB keys one-for-one.
var seedNameKeys = map[string]string{
	"Groceries":     "cat_groceries",
	"Cafe":          "cat_cafe",
	"Transport":     "cat_transport",
	"Home":          "cat_home",
	"Utilities":     "cat_utilities",
	"Health":        "cat_health",
	"Shopping":      "cat_shopping",
	"Fun":           "cat_fun",
	"Subscriptions": "cat_subscriptions",
	"Travel":        "cat_travel",
	"Other":         "cat_other",
	"Salary":        "cat_salary",
	"Freelance":     "cat_freelance",
	"Gifts":         "cat_gifts",
	"Other income":  "cat_other_income",
}

// SeedNameKey returns the catalog id for a canonical English seed name.
func SeedNameKey(canonical string) (string, bool) {
	key, ok := seedNameKeys[canonical]
	return key, ok
}

// SeedName localizes the canonical English name of an UNRENAMED seed category
// (docs/ARCHITECTURE.md § Seed category naming). The caller decides whether the
// rule applies — store.IsUnrenamedSeed — because a renamed category must show
// its literal new name in every language.
//
// A name that is not a seed name comes back unchanged, so this is safe to call
// on any category.
func (p *Printer) SeedName(canonical string) string {
	key, ok := seedNameKeys[canonical]
	if !ok {
		return canonical
	}
	if s := p.Tf(key, nil); s != "" && s != key {
		return s
	}
	return canonical
}

// SeedNameVariants returns the localized forms of a canonical seed name in every
// supported language, excluding the canonical name itself and any duplicates
// (Uzbek "Transport" is the English word, for instance).
//
// The bot feeds these to its category matcher so a typed "продукты" resolves to
// Groceries no matter which language the reply will be written in.
func (b *Bundle) SeedNameVariants(canonical string) []string {
	if _, ok := seedNameKeys[canonical]; !ok {
		return nil
	}
	seen := map[string]bool{strings.ToLower(canonical): true}
	var out []string
	for _, tag := range Supported {
		name := b.Printer(tag).SeedName(canonical)
		lower := strings.ToLower(name)
		if name == "" || seen[lower] {
			continue
		}
		seen[lower] = true
		out = append(out, name)
	}
	return out
}
