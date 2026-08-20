// Package model holds the shared data structures whose JSON tags are the
// binding wire contract (see docs/ARCHITECTURE.md). They are serialized
// verbatim into the Google Drive snapshot files exchanged between peers.
package model

// Kind values for transactions. Categories only ever use income/expense —
// KindTransfer is a transaction-only kind (see Transaction.ToAccountID).
const (
	KindIncome   = "income"
	KindExpense  = "expense"
	KindTransfer = "transfer"
)

// Account kinds. The kind is presentation and grouping only: every account
// holds money the same way, so "send to savings" is an ordinary transfer.
const (
	AccountCash       = "cash"
	AccountBank       = "bank"
	AccountSavings    = "savings"
	AccountInvestment = "investment"
)

// Source values for transactions.
const (
	SourceApp      = "app"
	SourceTelegram = "telegram"
)

// SettingsID is the fixed id of the singleton settings row.
const SettingsID = "settings"

// Transaction mirrors the `transaction` table of the contract.
//
// AccountID is the account the money moves OUT of for an expense and INTO for
// an income. For a transfer it is the SOURCE and ToAccountID the destination;
// ToAccountID is empty for every other kind.
//
// CategoryID is empty for transfers: moving your own money between your own
// accounts is not spending, so it has no category and never lands in an
// income or expense total.
type Transaction struct {
	ID          string `json:"id"`
	Kind        string `json:"kind"`
	AmountMinor int64  `json:"amount_minor"`
	CategoryID  string `json:"category_id"`
	AccountID   string `json:"account_id"`
	ToAccountID string `json:"to_account_id"`
	Note        string `json:"note"`
	OccurredAt  string `json:"occurred_at"`
	Source      string `json:"source"`
	CreatedAtMs int64  `json:"created_at_ms"`
	UpdatedAtMs int64  `json:"updated_at_ms"`
	DeletedAtMs *int64 `json:"deleted_at_ms"`
}

// IsTransfer reports whether t moves money between two of the owner's own
// accounts rather than in or out of their net worth.
func (t Transaction) IsTransfer() bool { return t.Kind == KindTransfer }

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

// Account mirrors the `account` table of the contract: a place money sits —
// cash, a card, a savings pot, an investment pot.
//
// OpeningBalanceMinor is what the account already held before the user
// started tracking it, so a balance is opening + everything logged since. It
// may be negative (a credit card in debt).
type Account struct {
	ID                  string `json:"id"`
	Name                string `json:"name"`
	Kind                string `json:"kind"`
	Emoji               string `json:"emoji"`
	Color               string `json:"color"`
	OpeningBalanceMinor int64  `json:"opening_balance_minor"`
	SortOrder           int    `json:"sort_order"`
	UpdatedAtMs         int64  `json:"updated_at_ms"`
	DeletedAtMs         *int64 `json:"deleted_at_ms"`
}

// Settings mirrors the singleton `settings` row of the contract.
//
// Language is synced deliberately: it is how the phone tells the Telegram bot
// which language to reply in. "" means "follow the device/Telegram locale".
//
// DefaultAccountID is likewise synced: it is the account the bot books its
// entries to, chosen in the app, so that 3-second logging never has to ask.
type Settings struct {
	ID               string `json:"id"`
	Currency         string `json:"currency"`
	Language         string `json:"language"`
	DefaultAccountID string `json:"default_account_id"`
	UpdatedAtMs      int64  `json:"updated_at_ms"`
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

// AccountKinds lists the values Account.Kind may take.
var AccountKinds = []string{AccountCash, AccountBank, AccountSavings, AccountInvestment}

// ValidAccountKind reports whether v is an acceptable Account.Kind value.
func ValidAccountKind(v string) bool {
	for _, k := range AccountKinds {
		if k == v {
			return true
		}
	}
	return false
}

// ValidTransactionKind reports whether v is an acceptable Transaction.Kind.
func ValidTransactionKind(v string) bool {
	return v == KindIncome || v == KindExpense || v == KindTransfer
}

// ValidCategoryKind reports whether v is an acceptable Category.Kind. Unlike
// transactions, a category is never a transfer.
func ValidCategoryKind(v string) bool {
	return v == KindIncome || v == KindExpense
}
