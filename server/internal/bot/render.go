package bot

import (
	"fmt"
	"strings"

	"github.com/xensa/tally/internal/i18n"
	"github.com/xensa/tally/internal/model"
	"github.com/xensa/tally/internal/store"
)

// Reply renderers, deliberately pure: no Telegram client, no store, no clock.
// Everything the user actually reads is produced here, so the localized output
// — plural forms, money placement, seed-name rule — is testable as a string.

// renderSummary builds a /today, /week or /month reply. title is already
// localized by the caller, which is the only part that differs between them.
func renderSummary(p *i18n.Printer, currency, title string, sum store.Summary) string {
	var sb strings.Builder
	sb.WriteString(title)
	sb.WriteString("\n")
	if sum.Count == 0 {
		sb.WriteString(p.T("summary_empty"))
		return sb.String()
	}
	net := sum.Income - sum.Expenses
	fmt.Fprintf(&sb, "%s\n", p.Tf("summary_net", map[string]any{"Amount": p.MoneySigned(net, currency)}))
	fmt.Fprintf(&sb, "%s\n", p.Tf("summary_income", map[string]any{"Amount": p.Money(sum.Income, currency)}))
	fmt.Fprintf(&sb, "%s\n", p.Tf("summary_expenses", map[string]any{"Amount": p.Money(sum.Expenses, currency)}))
	fmt.Fprintf(&sb, "%s\n", p.N("tx_count", int(sum.Count), nil))
	if len(sum.TopExpenses) > 0 {
		sb.WriteString("\n" + p.T("summary_top") + "\n")
		top := sum.TopExpenses[0].Total
		for _, ct := range sum.TopExpenses {
			fmt.Fprintf(&sb, "%s — %s\n%s\n",
				label(p, ct.Category), p.Money(ct.Total, currency), bar(ct.Total, top))
		}
	}
	return strings.TrimRight(sb.String(), "\n")
}

// renderCategories lists both kinds with localized headers and display names.
func renderCategories(p *i18n.Printer, cats []model.Category) string {
	var exp, inc []string
	for _, c := range cats {
		if c.Kind == model.KindIncome {
			inc = append(inc, label(p, c))
		} else {
			exp = append(exp, label(p, c))
		}
	}
	empty := p.T("categories_empty")
	var sb strings.Builder
	sb.WriteString(p.T("categories_expense") + "\n")
	sb.WriteString(joinOr(exp, empty))
	sb.WriteString("\n\n" + p.T("categories_income") + "\n")
	sb.WriteString(joinOr(inc, empty))
	return sb.String()
}

// accountDisplayName applies the seed-name rule to an account: a seed account
// is shown translated only while the owner has not renamed it.
func accountDisplayName(p *i18n.Printer, a model.Account) string {
	if store.IsUnrenamedSeedAccount(a) {
		return p.SeedAccountName(a.Name)
	}
	return a.Name
}

func accountLabel(p *i18n.Printer, a model.Account) string {
	return a.Emoji + " " + accountDisplayName(p, a)
}

// renderAccounts lists each account with its balance, then the total across
// all of them — the "how much do I actually have" number.
//
// A balance is rendered with Money, not MoneySigned: a negative balance still
// shows its minus (a card carrying debt must never look like credit), but a
// positive one is just an amount — "+$125.50" would read as a change rather
// than as what the account holds.
func renderAccounts(p *i18n.Printer, currency string, balances []store.AccountBalance, def model.Account) string {
	var sb strings.Builder
	sb.WriteString(p.T("accounts_title") + "\n")
	if len(balances) == 0 {
		sb.WriteString(p.T("accounts_empty"))
		return sb.String()
	}
	var total int64
	for _, ab := range balances {
		total += ab.BalanceMinor
		fmt.Fprintf(&sb, "%s — %s\n", accountLabel(p, ab.Account), p.Money(ab.BalanceMinor, currency))
	}
	fmt.Fprintf(&sb, "\n%s", p.Tf("accounts_total", map[string]any{
		"Amount": p.Money(total, currency),
	}))
	if def.ID != "" {
		fmt.Fprintf(&sb, "\n\n%s", p.Tf("accounts_default_hint", map[string]any{
			"Account": accountDisplayName(p, def),
		}))
	}
	return sb.String()
}

// renderUndo confirms a removed entry. cat is nil when the category row has
// gone missing, which is survivable — the amount is the important part.
func renderUndo(p *i18n.Printer, currency string, t model.Transaction, cat *model.Category) string {
	catLabel := p.T("unknown_category")
	if cat != nil {
		catLabel = label(p, *cat)
	}
	reply := p.Tf("undo_removed", map[string]any{
		"Amount":   p.MoneySigned(signedMinor(t.Kind, t.AmountMinor), currency),
		"Category": catLabel,
	})
	if t.Note != "" {
		// The note is user data: appended verbatim, never translated.
		reply += " — " + t.Note
	}
	return reply
}

// renderEntrySaved is the contract's success reply:
//
//	✅ −250,00 ₽ • 🛒 Продукты — 3 450,00 за месяц
func renderEntrySaved(p *i18n.Printer, currency, kind string, amountMinor, monthTotal int64, cat model.Category) string {
	return p.Tf("entry_saved", map[string]any{
		"Amount":   p.MoneySigned(signedMinor(kind, amountMinor), currency),
		"Category": label(p, cat),
		"Total":    p.Money(monthTotal, currency),
	})
}

// joinOr joins lines with newlines, falling back to empty when there are none.
func joinOr(lines []string, empty string) string {
	if len(lines) == 0 {
		return empty
	}
	return strings.Join(lines, "\n")
}

// signedMinor turns a stored (always positive) amount into a signed one:
// expenses are negative, income positive.
func signedMinor(kind string, amountMinor int64) int64 {
	if kind == model.KindIncome {
		return amountMinor
	}
	return -amountMinor
}
