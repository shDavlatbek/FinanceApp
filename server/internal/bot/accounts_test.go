package bot

import (
	"strings"
	"testing"

	"github.com/xensa/tally/internal/model"
	"github.com/xensa/tally/internal/store"
	"golang.org/x/text/language"
)

var (
	cashAcct = model.Account{
		ID: store.DefaultAccountID, Name: "Cash", Kind: model.AccountCash, Emoji: "💵",
	}
	cardAcct = model.Account{
		ID: "a1c7e2f0-0002-4a00-9000-000000000002", Name: "Card", Kind: model.AccountBank, Emoji: "💳",
	}
	savingsAcct = model.Account{
		ID: "a1c7e2f0-0003-4a00-9000-000000000003", Name: "Savings", Kind: model.AccountSavings, Emoji: "🏦",
	}
)

// /accounts is the bot's whole account surface, so its reply is pinned in
// every language — including the seed-name rule and a negative balance.
func TestRenderAccounts(t *testing.T) {
	b := testBundle(t)
	balances := []store.AccountBalance{
		{Account: cashAcct, BalanceMinor: 12550},
		{Account: cardAcct, BalanceMinor: -40000},
		{Account: savingsAcct, BalanceMinor: 500000},
	}

	tests := []struct {
		tag      language.Tag
		currency string
		want     []string
	}{
		{language.English, "USD", []string{
			"🏦 Accounts", "💵 Cash — $125.50", "💳 Card — −$400.00",
			"🏦 Savings — $5,000.00", "Total: $4,725.50",
			"New entries go to Cash.",
		}},
		{language.Russian, "RUB", []string{
			"🏦 Счета", "💵 Наличные — 125,50 ₽", "💳 Карта — −400,00 ₽",
			"🏦 Накопления — 5 000,00 ₽", "Всего: 4 725,50 ₽",
		}},
		{language.Uzbek, "UZS", []string{
			"🏦 Hisoblar", "💵 Naqd pul — 12 550 soʻm", "💳 Karta — −40 000 soʻm",
			"🏦 Jamgʻarma — 500 000 soʻm",
		}},
	}

	for _, tt := range tests {
		t.Run(tt.tag.String(), func(t *testing.T) {
			got := renderAccounts(b.Printer(tt.tag), tt.currency, balances, cashAcct)
			for _, want := range tt.want {
				if !strings.Contains(got, want) {
					t.Errorf("reply missing %q:\n%s", want, got)
				}
			}
		})
	}
}

// A renamed account displays verbatim in every language, exactly as a renamed
// category does.
func TestRenderAccountsRespectsRename(t *testing.T) {
	b := testBundle(t)
	renamed := savingsAcct
	renamed.Name = "Ipoteka"

	got := renderAccounts(b.Printer(language.Russian), "RUB",
		[]store.AccountBalance{{Account: renamed, BalanceMinor: 1000}}, model.Account{})
	if !strings.Contains(got, "🏦 Ipoteka") {
		t.Errorf("renamed account was translated away:\n%s", got)
	}
	if strings.Contains(got, "Накопления") {
		t.Errorf("renamed account still showed the seed translation:\n%s", got)
	}
}

func TestRenderAccountsEmpty(t *testing.T) {
	b := testBundle(t)
	got := renderAccounts(b.Printer(language.English), "USD", nil, model.Account{})
	if !strings.Contains(got, "No accounts yet.") {
		t.Errorf("empty state missing:\n%s", got)
	}
	if strings.Contains(got, "Total:") {
		t.Errorf("empty account list still printed a total:\n%s", got)
	}
}

// With no default account resolved, the hint is simply left out rather than
// rendered with a blank name.
func TestRenderAccountsWithoutDefault(t *testing.T) {
	b := testBundle(t)
	got := renderAccounts(b.Printer(language.English), "USD",
		[]store.AccountBalance{{Account: cashAcct, BalanceMinor: 100}}, model.Account{})
	if strings.Contains(got, "New entries go to") {
		t.Errorf("hint rendered without a default account:\n%s", got)
	}
}

// Every seed account name must resolve in every language, or the app and the
// bot would disagree about what an unrenamed account is called.
func TestSeedAccountNamesTranslate(t *testing.T) {
	b := testBundle(t)
	for _, a := range store.SeedAccounts {
		for _, tag := range []language.Tag{language.English, language.Russian, language.Uzbek} {
			got := b.Printer(tag).SeedAccountName(a.Name)
			if got == "" {
				t.Errorf("%s/%s: empty translation", a.Name, tag)
			}
			if tag != language.English && got == a.Name && a.Name != "Card" {
				t.Errorf("%s/%s: untranslated (%q)", a.Name, tag, got)
			}
		}
	}
}
