package store

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/xensa/tally/internal/model"
)

const (
	accCash    = DefaultAccountID
	accCard    = "a1c7e2f0-0002-4a00-9000-000000000002"
	accSavings = "a1c7e2f0-0003-4a00-9000-000000000003"
	catFood    = "c1a7e2f0-0001-4a00-9000-000000000001"
	catSalary  = "c1a7e2f0-0101-4a00-9000-000000000101"
)

// tx books an income/expense; transfer books a move between two accounts.
func tx(id, kind string, amount int64, categoryID, accountID, toAccountID, occurredAt string) model.Transaction {
	return model.Transaction{
		ID: id, Kind: kind, AmountMinor: amount,
		CategoryID: categoryID, AccountID: accountID, ToAccountID: toAccountID,
		OccurredAt: occurredAt, Source: model.SourceApp,
		CreatedAtMs: 1787000000000, UpdatedAtMs: 1787000000000,
	}
}

func TestSeedAccountsOnEmptyDB(t *testing.T) {
	s := openTestStore(t)

	accounts, err := s.ListAccounts()
	if err != nil {
		t.Fatalf("ListAccounts: %v", err)
	}
	if len(accounts) != len(SeedAccounts) {
		t.Fatalf("seeded %d accounts, want %d", len(accounts), len(SeedAccounts))
	}
	byID := map[string]model.Account{}
	for _, a := range accounts {
		byID[a.ID] = a
	}
	cash, ok := byID[accCash]
	if !ok || cash.Name != "Cash" || cash.Kind != model.AccountCash ||
		cash.Emoji != "💵" || cash.UpdatedAtMs != SeedUpdatedAtMs {
		t.Fatalf("bad Cash seed: %+v", cash)
	}
	// Savings and investments are the point of the feature; they must exist
	// out of the box so "send to savings" works on a fresh install.
	if a := byID[accSavings]; a.Kind != model.AccountSavings {
		t.Errorf("savings seed kind = %q", a.Kind)
	}
	if a := byID["a1c7e2f0-0004-4a00-9000-000000000004"]; a.Kind != model.AccountInvestment {
		t.Errorf("investment seed kind = %q", a.Kind)
	}

	st, err := s.Settings()
	if err != nil {
		t.Fatal(err)
	}
	if st.DefaultAccountID != DefaultAccountID {
		t.Errorf("seeded default_account_id = %q, want %q", st.DefaultAccountID, DefaultAccountID)
	}

	// Both peers seed byte-identical accounts, so there is nothing to publish.
	dirty, err := s.HasDirty()
	if err != nil {
		t.Fatal(err)
	}
	if dirty {
		t.Error("a freshly seeded database reports dirty rows")
	}
}

// A balance is opening + income - expenses + transfers in - transfers out,
// with deleted rows excluded.
func TestAccountBalances(t *testing.T) {
	s := openTestStore(t)

	// Give the card a debt to start from, so a negative opening is exercised.
	card, err := s.GetAccount(accCard)
	if err != nil {
		t.Fatal(err)
	}
	card.OpeningBalanceMinor = -50000
	card.UpdatedAtMs = 1787000000001
	if err := s.InsertAccount(card); err != nil {
		t.Fatal(err)
	}

	for _, e := range []model.Transaction{
		tx("t1", model.KindIncome, 300000, catSalary, accCard, "", "2026-08-01T00:00:00Z"),
		tx("t2", model.KindExpense, 25000, catFood, accCard, "", "2026-08-02T00:00:00Z"),
		tx("t3", model.KindExpense, 5000, catFood, accCash, "", "2026-08-03T00:00:00Z"),
		// "Send to savings": leaves the card, lands in savings.
		tx("t4", model.KindTransfer, 100000, "", accCard, accSavings, "2026-08-04T00:00:00Z"),
	} {
		if err := s.InsertTransaction(e); err != nil {
			t.Fatalf("insert %s: %v", e.ID, err)
		}
	}

	// A deleted transfer must stop moving money.
	ghost := tx("t5", model.KindTransfer, 999999, "", accCard, accSavings, "2026-08-05T00:00:00Z")
	if err := s.InsertTransaction(ghost); err != nil {
		t.Fatal(err)
	}
	if err := s.SoftDeleteTransaction("t5", 1787000009000); err != nil {
		t.Fatal(err)
	}

	balances, err := s.AccountBalances()
	if err != nil {
		t.Fatalf("AccountBalances: %v", err)
	}
	got := map[string]int64{}
	for _, ab := range balances {
		got[ab.Account.ID] = ab.BalanceMinor
	}

	// -50000 opening + 300000 income - 25000 expense - 100000 transferred out
	if want := int64(125000); got[accCard] != want {
		t.Errorf("card balance = %d, want %d", got[accCard], want)
	}
	if want := int64(-5000); got[accCash] != want {
		t.Errorf("cash balance = %d, want %d", got[accCash], want)
	}
	if want := int64(100000); got[accSavings] != want {
		t.Errorf("savings balance = %d, want %d", got[accSavings], want)
	}
	if want := int64(0); got["a1c7e2f0-0004-4a00-9000-000000000004"] != want {
		t.Errorf("untouched investment balance = %d, want %d",
			got["a1c7e2f0-0004-4a00-9000-000000000004"], want)
	}
}

// The whole point of modelling savings as a transfer: moving your own money
// is neither income nor spending, so no monthly total may move.
func TestTransfersStayOutOfSummaries(t *testing.T) {
	s := openTestStore(t)

	from := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	to := from.AddDate(0, 1, 0)

	if err := s.InsertTransaction(
		tx("s1", model.KindExpense, 25000, catFood, accCash, "", "2026-08-02T00:00:00Z")); err != nil {
		t.Fatal(err)
	}
	before, err := s.PeriodSummary(from, to)
	if err != nil {
		t.Fatal(err)
	}

	if err := s.InsertTransaction(
		tx("s2", model.KindTransfer, 700000, "", accCash, accSavings, "2026-08-03T00:00:00Z")); err != nil {
		t.Fatal(err)
	}
	after, err := s.PeriodSummary(from, to)
	if err != nil {
		t.Fatal(err)
	}

	if after.Income != before.Income || after.Expenses != before.Expenses {
		t.Errorf("a transfer moved the totals: %+v -> %+v", before, after)
	}
	if after.Count != before.Count {
		t.Errorf("a transfer was counted as an entry: %d -> %d", before.Count, after.Count)
	}
	if after.Expenses != 25000 {
		t.Errorf("expenses = %d, want 25000", after.Expenses)
	}
}

// /undo reports "amount • category", so it must never land on a transfer.
func TestLastTransactionSkipsTransfers(t *testing.T) {
	s := openTestStore(t)

	spend := tx("u1", model.KindExpense, 25000, catFood, accCash, "", "2026-08-02T00:00:00Z")
	spend.CreatedAtMs = 1787000000000
	if err := s.InsertTransaction(spend); err != nil {
		t.Fatal(err)
	}
	move := tx("u2", model.KindTransfer, 700000, "", accCash, accSavings, "2026-08-03T00:00:00Z")
	move.CreatedAtMs = 1787000005000 // strictly newer
	if err := s.InsertTransaction(move); err != nil {
		t.Fatal(err)
	}

	last, err := s.LastTransaction()
	if err != nil {
		t.Fatalf("LastTransaction: %v", err)
	}
	if last.ID != "u1" {
		t.Errorf("LastTransaction = %s, want the expense u1", last.ID)
	}
}

// Archiving the account the bot books to must not leave it writing into a
// hole: DefaultAccount falls back to a live account.
func TestDefaultAccountFallsBackWhenArchived(t *testing.T) {
	s := openTestStore(t)

	a, err := s.DefaultAccount()
	if err != nil {
		t.Fatal(err)
	}
	if a.ID != DefaultAccountID {
		t.Fatalf("default account = %s, want %s", a.ID, DefaultAccountID)
	}

	if err := s.SoftDeleteAccount(DefaultAccountID, 1787000010000); err != nil {
		t.Fatal(err)
	}
	a, err = s.DefaultAccount()
	if err != nil {
		t.Fatalf("DefaultAccount after archiving: %v", err)
	}
	if a.ID == DefaultAccountID {
		t.Error("DefaultAccount returned an archived account")
	}
	if a.DeletedAtMs != nil {
		t.Errorf("DefaultAccount returned a tombstone: %+v", a)
	}
}

// A peer that predates accounts sends settings with no default_account_id.
// Read literally that is "clear it", which would strip an account the owner
// deliberately picked in the app. Empty must mean "unchanged".
func TestMergeV1SettingsKeepsChosenDefaultAccount(t *testing.T) {
	s := openTestStore(t)

	chosen := model.Settings{
		ID: model.SettingsID, Currency: "USD", Language: "en",
		DefaultAccountID: accSavings, UpdatedAtMs: 1787000000000,
	}
	if err := s.SetSettings(chosen); err != nil {
		t.Fatal(err)
	}

	// The old peer's row is NEWER, so it wins last-write-wins outright.
	if _, err := s.MergeRemote(Batch{Settings: []model.Settings{{
		ID: model.SettingsID, Currency: "EUR", Language: "ru", UpdatedAtMs: 1787000005000,
	}}}); err != nil {
		t.Fatal(err)
	}

	st, err := s.Settings()
	if err != nil {
		t.Fatal(err)
	}
	if st.Currency != "EUR" || st.Language != "ru" {
		t.Errorf("the newer peer row did not win: %+v", st)
	}
	if st.DefaultAccountID != accSavings {
		t.Errorf("default_account_id = %q, want the chosen %q (a pre-accounts peer cleared it)",
			st.DefaultAccountID, accSavings)
	}
}

// Accounts take part in the dirty/publish cycle like every other table.
func TestAccountDirtyLifecycle(t *testing.T) {
	s := openTestStore(t)

	if err := s.InsertAccount(model.Account{
		ID: "aaaa1111-0000-4000-8000-000000000001", Name: "Crypto",
		Kind: model.AccountInvestment, Emoji: "🪙", Color: "#112233",
		SortOrder: 7, UpdatedAtMs: 1787000000000,
	}); err != nil {
		t.Fatal(err)
	}
	dirty, err := s.HasDirty()
	if err != nil {
		t.Fatal(err)
	}
	if !dirty {
		t.Fatal("a locally created account was not marked dirty")
	}

	snap, err := s.FullState()
	if err != nil {
		t.Fatal(err)
	}
	if err := s.ClearDirty(snap); err != nil {
		t.Fatal(err)
	}
	dirty, err = s.HasDirty()
	if err != nil {
		t.Fatal(err)
	}
	if dirty {
		t.Error("publishing the snapshot left the account dirty")
	}

	// A merged peer account is not dirty — it came from the peer.
	if _, err := s.MergeRemote(Batch{Accounts: []model.Account{{
		ID: "aaaa1111-0000-4000-8000-000000000002", Name: "Broker",
		Kind: model.AccountInvestment, Emoji: "📈", Color: "#445566",
		SortOrder: 8, UpdatedAtMs: 1787000001000,
	}}}); err != nil {
		t.Fatal(err)
	}
	dirty, err = s.HasDirty()
	if err != nil {
		t.Fatal(err)
	}
	if dirty {
		t.Error("a merged remote account was marked dirty")
	}
}

// Opening a database created before accounts existed must rebuild the
// transactions table (SQLite cannot widen the CHECK on `kind` in place),
// book every existing row to the default account, and keep the data.
func TestMigrateFromPreAccountsSchema(t *testing.T) {
	path := filepath.Join(t.TempDir(), "v2.db")
	s, err := Open(path, "USD")
	if err != nil {
		t.Fatal(err)
	}
	// Rewind to the pre-accounts shape: no accounts table, no account columns,
	// and the old two-value CHECK on kind.
	for _, stmt := range []string{
		`DROP TABLE accounts`,
		`ALTER TABLE settings DROP COLUMN default_account_id`,
		`ALTER TABLE transactions RENAME TO transactions_new`,
		`CREATE TABLE transactions (
			id            TEXT PRIMARY KEY,
			kind          TEXT NOT NULL CHECK (kind IN ('income','expense')),
			amount_minor  INTEGER NOT NULL,
			category_id   TEXT NOT NULL,
			note          TEXT NOT NULL DEFAULT '',
			occurred_at   TEXT NOT NULL,
			source        TEXT NOT NULL CHECK (source IN ('app','telegram')),
			created_at_ms INTEGER NOT NULL,
			updated_at_ms INTEGER NOT NULL,
			deleted_at_ms INTEGER,
			server_seq    INTEGER NOT NULL,
			dirty         INTEGER NOT NULL DEFAULT 0
		)`,
		`DROP TABLE transactions_new`,
		`INSERT INTO transactions (id, kind, amount_minor, category_id, note, occurred_at,
		                           source, created_at_ms, updated_at_ms, deleted_at_ms, server_seq, dirty)
		 VALUES ('old-1','expense',24850,'` + catFood + `','weekly shop','2026-08-18T09:30:00Z',
		         'app',1787000000000,1787000000000,NULL,1,0)`,
	} {
		if _, err := s.db.Exec(stmt); err != nil {
			t.Fatalf("%s: %v", stmt, err)
		}
	}
	s.Close()

	s2, err := Open(path, "USD")
	if err != nil {
		t.Fatalf("reopen after pre-accounts downgrade: %v", err)
	}
	defer s2.Close()

	snap, err := s2.FullState()
	if err != nil {
		t.Fatalf("FullState after migration: %v", err)
	}
	if len(snap.Transactions) != 1 {
		t.Fatalf("migration lost transactions: %d", len(snap.Transactions))
	}
	old := snap.Transactions[0]
	if old.ID != "old-1" || old.AmountMinor != 24850 || old.Note != "weekly shop" {
		t.Errorf("migration mangled the row: %+v", old)
	}
	if old.AccountID != DefaultAccountID {
		t.Errorf("migrated account_id = %q, want the default account", old.AccountID)
	}
	if old.ToAccountID != "" {
		t.Errorf("migrated to_account_id = %q, want empty", old.ToAccountID)
	}

	if len(snap.Accounts) != len(SeedAccounts) {
		t.Errorf("migration seeded %d accounts, want %d", len(snap.Accounts), len(SeedAccounts))
	}
	st, err := s2.Settings()
	if err != nil {
		t.Fatal(err)
	}
	if st.DefaultAccountID != DefaultAccountID {
		t.Errorf("migrated default_account_id = %q, want %q", st.DefaultAccountID, DefaultAccountID)
	}

	// The widened CHECK is the reason for the rebuild: transfers must insert.
	if err := s2.InsertTransaction(
		tx("new-1", model.KindTransfer, 5000, "", accCash, accSavings, "2026-08-20T00:00:00Z")); err != nil {
		t.Fatalf("inserting a transfer after migration: %v", err)
	}

	// The rebuild drops the table's indexes with it; they must come back.
	var n int
	if err := s2.db.QueryRow(
		`SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='transactions'
		   AND name='idx_transactions_occurred_at'`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Error("idx_transactions_occurred_at was not recreated after the rebuild")
	}
}

// A self-transfer must never invent money.
//
// Regression: the balance query used a single CASE whose first matching arm
// won, so for a row with account_id == to_account_id the credit arm matched
// and the debit arm was never reached — the balance grew by the full amount
// out of nothing. The sanitizer rejects such rows, but a balance formula must
// not depend on an upstream check to stay arithmetically sound.
func TestSelfTransferCannotInventMoney(t *testing.T) {
	s := openTestStore(t)

	// Inserted through the LWW path directly, bypassing the sanitizer, which
	// is exactly how a hand-edited peer file would arrive before the fix.
	if err := s.InsertTransaction(
		tx("self", model.KindTransfer, 250000, "", accCash, accCash, "2026-08-20T00:00:00Z")); err != nil {
		t.Fatal(err)
	}

	balances, err := s.AccountBalances()
	if err != nil {
		t.Fatal(err)
	}
	for _, ab := range balances {
		if ab.Account.ID == accCash && ab.BalanceMinor != 0 {
			t.Fatalf("cash balance = %d, want 0: a self-transfer created money",
				ab.BalanceMinor)
		}
	}
}

// The bot echoes a category's month total after every single entry, so a
// transfer must never reach it — including one that arrived carrying a stray
// category_id from a hand-edited peer file.
func TestCategoryPeriodTotalIgnoresTransfers(t *testing.T) {
	s := openTestStore(t)
	from := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	to := from.AddDate(0, 1, 0)

	if err := s.InsertTransaction(
		tx("spend", model.KindExpense, 25000, catFood, accCash, "", "2026-08-02T00:00:00Z")); err != nil {
		t.Fatal(err)
	}
	if err := s.InsertTransaction(
		tx("moved", model.KindTransfer, 900000, catFood, accCash, accSavings, "2026-08-03T00:00:00Z")); err != nil {
		t.Fatal(err)
	}

	total, err := s.CategoryPeriodTotal(catFood, from, to)
	if err != nil {
		t.Fatal(err)
	}
	if total != 25000 {
		t.Fatalf("category total = %d, want 25000 (a transfer was counted)", total)
	}
}
