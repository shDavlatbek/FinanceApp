package i18n

import "strings"

// seedAccountNameKeys maps a seed account's CANONICAL ENGLISH name to its
// catalog id, mirroring seedNameKeys for categories.
//
// Keying on the name rather than the UUID keeps the fixed ids in exactly one
// place (internal/store), and the canonical name is what
// store.IsUnrenamedSeedAccount has just proven the row still carries. The
// values mirror the Flutter app's seedAccount* ARB keys one-for-one.
var seedAccountNameKeys = map[string]string{
	"Cash":        "acc_cash",
	"Card":        "acc_card",
	"Savings":     "acc_savings",
	"Investments": "acc_investments",
}

// SeedAccountNameKey returns the catalog id for a canonical English seed
// account name.
func SeedAccountNameKey(canonical string) (string, bool) {
	key, ok := seedAccountNameKeys[canonical]
	return key, ok
}

// SeedAccountName localizes the canonical English name of an UNRENAMED seed
// account, by the same rule the contract sets for categories: once the owner
// renames it, the literal new name shows in every language.
//
// A name that is not a seed name comes back unchanged, so this is safe to
// call on any account.
func (p *Printer) SeedAccountName(canonical string) string {
	key, ok := seedAccountNameKeys[canonical]
	if !ok {
		return canonical
	}
	if s := p.Tf(key, nil); s != "" && s != key {
		return s
	}
	return canonical
}

// SeedAccountNameVariants returns the localized forms of a canonical seed
// account name in every supported language, excluding the canonical name
// itself and any duplicates (Uzbek "Karta" and English "Card" differ, but
// several others coincide).
func (b *Bundle) SeedAccountNameVariants(canonical string) []string {
	if _, ok := seedAccountNameKeys[canonical]; !ok {
		return nil
	}
	seen := map[string]bool{strings.ToLower(canonical): true}
	var out []string
	for _, tag := range Supported {
		name := b.Printer(tag).SeedAccountName(canonical)
		lower := strings.ToLower(name)
		if name == "" || seen[lower] {
			continue
		}
		seen[lower] = true
		out = append(out, name)
	}
	return out
}
