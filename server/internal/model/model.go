// Package model holds the shared data structures whose JSON tags are the
// binding wire contract (see docs/ARCHITECTURE.md). They are serialized
// verbatim into the Google Drive snapshot files exchanged between peers.
package model

// Kind values for transactions and categories.
const (
	KindIncome  = "income"
	KindExpense = "expense"
)

// Source values for transactions.
const (
	SourceApp      = "app"
	SourceTelegram = "telegram"
)

// SettingsID is the fixed id of the singleton settings row.
const SettingsID = "settings"

// Transaction mirrors the `transaction` table of the contract.
type Transaction struct {
	ID          string `json:"id"`
	Kind        string `json:"kind"`
	AmountMinor int64  `json:"amount_minor"`
	CategoryID  string `json:"category_id"`
	Note        string `json:"note"`
	OccurredAt  string `json:"occurred_at"`
	Source      string `json:"source"`
	CreatedAtMs int64  `json:"created_at_ms"`
	UpdatedAtMs int64  `json:"updated_at_ms"`
	DeletedAtMs *int64 `json:"deleted_at_ms"`
}

// Category mirrors the `category` table of the contract.
type Category struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Emoji       string `json:"emoji"`
	Color       string `json:"color"`
	Kind        string `json:"kind"`
	SortOrder   int    `json:"sort_order"`
	UpdatedAtMs int64  `json:"updated_at_ms"`
	DeletedAtMs *int64 `json:"deleted_at_ms"`
}

// Settings mirrors the singleton `settings` row of the contract.
//
// Language is synced deliberately: it is how the phone tells the Telegram bot
// which language to reply in. "" means "follow the device/Telegram locale".
type Settings struct {
	ID          string `json:"id"`
	Currency    string `json:"currency"`
	Language    string `json:"language"`
	UpdatedAtMs int64  `json:"updated_at_ms"`
}

// Language values allowed in Settings.Language ("" = follow device locale).
const (
	LangAuto     = ""
	LangEnglish  = "en"
	LangRussian  = "ru"
	LangUzbek    = "uz"
	CanonicalUTC = "2006-01-02T15:04:05Z" // canonical occurred_at layout
)

// SupportedLanguages lists the values Settings.Language may take besides "".
var SupportedLanguages = []string{LangEnglish, LangRussian, LangUzbek}

// ValidLanguage reports whether v is an acceptable Settings.Language value.
func ValidLanguage(v string) bool {
	if v == LangAuto {
		return true
	}
	for _, l := range SupportedLanguages {
		if l == v {
			return true
		}
	}
	return false
}
