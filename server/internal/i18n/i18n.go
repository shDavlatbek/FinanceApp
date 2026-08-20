// Package i18n localizes every user-facing Telegram bot string into English,
// Russian and Uzbek (docs/ARCHITECTURE.md § Internationalization).
//
// Catalogs are TOML files embedded at build time (locales/{en,ru,uz}.toml) so a
// translator can contribute without touching Go. Plural forms come from
// go-i18n's CLDR rules: Russian carries the full one/few/many/other set,
// English and Uzbek one/other.
//
// Money and dates are formatted by hand (see money.go). golang.org/x/text is
// pinned to CLDR 32 and places the ruble symbol before the amount
// ("₽ 1 234,56" instead of "1 234,56 ₽"), so it is never used for user-facing
// money here.
//
// Nothing in this package returns an error at reply time: a missing catalog key
// falls back to English and then to the raw message id, because a translation
// gap must never cost the user their 3-second logging.
package i18n

import (
	"embed"
	"fmt"

	"github.com/BurntSushi/toml"
	goi18n "github.com/nicksnyder/go-i18n/v2/i18n"
	"golang.org/x/text/language"
)

//go:embed locales/*.toml
var localeFS embed.FS

// Supported lists the bot's languages. English is the source catalog and the
// fallback for everything else.
var Supported = []language.Tag{language.English, language.Russian, language.Uzbek}

// Bundle holds the parsed catalogs. It is immutable after New and safe for
// concurrent use.
type Bundle struct {
	b        *goi18n.Bundle
	printers map[language.Tag]*Printer
}

// New parses the embedded catalogs.
func New() (*Bundle, error) {
	gb := goi18n.NewBundle(language.English)
	gb.RegisterUnmarshalFunc("toml", toml.Unmarshal)
	for _, tag := range Supported {
		if _, err := gb.LoadMessageFileFS(localeFS, "locales/"+tag.String()+".toml"); err != nil {
			return nil, fmt.Errorf("i18n: load %s catalog: %w", tag, err)
		}
	}
	b := &Bundle{b: gb, printers: make(map[language.Tag]*Printer, len(Supported))}
	// Printers are stateless once built, so build them all up front and hand
	// out shared pointers instead of allocating a localizer per bot update.
	for _, tag := range Supported {
		b.printers[tag] = &Printer{
			loc:  goi18n.NewLocalizer(gb, tag.String()),
			tag:  tag,
			conv: conventionsFor(tag),
		}
	}
	return b, nil
}

// MustNew is New for package-level initialization; the catalogs are embedded,
// so a failure is a build-time mistake, not a runtime condition.
func MustNew() *Bundle {
	b, err := New()
	if err != nil {
		panic(err)
	}
	return b
}

// Normalize maps a locale code onto a supported tag by BASE LANGUAGE ONLY,
// with an explicit switch.
//
// This deliberately avoids language.NewMatcher: measured against [en ru uz] the
// matcher sends Kazakh to Russian with confidence High, and — worse — sends
// uz-Cyrl to Russian, so an Uzbek user would be answered in Russian. See
// docs/ARCHITECTURE.md § Bot language resolution.
func Normalize(code string) language.Tag {
	if code == "" {
		return language.English
	}
	t, err := language.Parse(code)
	if err != nil {
		return language.English
	}
	base, _ := t.Base()
	switch base.String() {
	case "ru":
		return language.Russian
	case "uz":
		// Covers uz, uz-Latn, uz-Cyrl and uz-UZ — all served the uz catalog.
		return language.Uzbek
	case "en":
		return language.English
	}
	return language.English
}

// Resolve implements the contract's bot language resolution order:
//
//	settings.language (if non-empty) → Telegram user.language_code → English
//
// settingsLang is the synced Settings.Language ("" = follow the Telegram
// locale); telegramCode is models.User.LanguageCode, which the Bot API marks
// optional and therefore may be empty.
func Resolve(settingsLang, telegramCode string) language.Tag {
	if settingsLang != "" {
		return Normalize(settingsLang)
	}
	return Normalize(telegramCode)
}

// Printer renders messages, money and dates in one language.
type Printer struct {
	loc  *goi18n.Localizer
	tag  language.Tag
	conv conventions
}

// Printer returns the printer for an already-normalized tag. Unsupported tags
// fall back to English.
func (b *Bundle) Printer(tag language.Tag) *Printer {
	if p, ok := b.printers[tag]; ok {
		return p
	}
	return b.printers[language.English]
}

// For resolves the language per the contract and returns its printer.
func (b *Bundle) For(settingsLang, telegramCode string) *Printer {
	return b.Printer(Resolve(settingsLang, telegramCode))
}

// Tag returns the printer's language tag.
func (p *Printer) Tag() language.Tag { return p.tag }

// Lang returns the printer's language code ("en", "ru" or "uz").
func (p *Printer) Lang() string { return p.tag.String() }

// T renders a message with no template data.
func (p *Printer) T(id string) string { return p.Tf(id, nil) }

// Tf renders a message with template data.
//
// go-i18n already falls back to the English catalog when a key is missing from
// this language's file, but it reports that as an error while still returning
// the English text — so a non-empty result is always preferred over the error.
// Only a key missing from English too degrades to the raw id.
func (p *Printer) Tf(id string, data map[string]any) string {
	s, err := p.loc.Localize(&goi18n.LocalizeConfig{MessageID: id, TemplateData: data})
	if s == "" && err != nil {
		return id
	}
	return s
}

// N renders a pluralized message. count picks the CLDR plural form and is also
// exposed to the template as {{.Count}}, pre-formatted with this locale's
// group separator so Russian gets "1 234", not "1234".
func (p *Printer) N(id string, count int, data map[string]any) string {
	merged := make(map[string]any, len(data)+1)
	for k, v := range data {
		merged[k] = v
	}
	merged["Count"] = p.Number(int64(count))
	s, err := p.loc.Localize(&goi18n.LocalizeConfig{
		MessageID:    id,
		PluralCount:  count,
		TemplateData: merged,
	})
	if s == "" && err != nil {
		return id
	}
	return s
}
