package drive

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/xensa/tally/internal/store"
)

// Cross-implementation guard: the Go and Dart peers must agree, byte for byte,
// on the snapshot wire format in docs/ARCHITECTURE.md.
//
// Both sides parse the SAME fixture and assert the same values. A field
// rename, a null-handling difference, or an int64 routed through a double on
// either side breaks one of these two tests — the only cheap way to catch sync
// divergence without live Google credentials. The Dart half lives in
// app/test/snapshot_interop_test.dart and reads the same file.

func fixtureFile(t *testing.T, name string) []byte {
	t.Helper()
	path := filepath.Join("..", "..", "..", "docs", "fixtures", name)
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading interop fixture: %v", err)
	}
	return b
}

func fixtureBytes(t *testing.T) []byte {
	t.Helper()
	return fixtureFile(t, "snapshot.example.json")
}

func TestInteropFixtureParses(t *testing.T) {
	snap, err := ParseSnapshot(fixtureBytes(t))
	if err != nil {
		t.Fatalf("ParseSnapshot: %v", err)
	}

	if snap.Schema != 3 {
		t.Errorf("schema = %d, want 3", snap.Schema)
	}
	if snap.DeviceID != "11111111-2222-4333-8444-555555555555" {
		t.Errorf("device_id = %q", snap.DeviceID)
	}
	if snap.DeviceName != "Fixture Device" {
		t.Errorf("device_name = %q", snap.DeviceName)
	}
	if snap.WrittenAtMs != 1787160000000 {
		t.Errorf("written_at_ms = %d", snap.WrittenAtMs)
	}
	if len(snap.Categories) != 4 {
		t.Fatalf("categories = %d, want 4", len(snap.Categories))
	}
	if len(snap.Transactions) != 6 {
		t.Fatalf("transactions = %d, want 6", len(snap.Transactions))
	}
	if len(snap.Accounts) != 4 {
		t.Fatalf("accounts = %d, want 4", len(snap.Accounts))
	}

	accs := map[string]int{}
	for i, a := range snap.Accounts {
		accs[a.ID] = i
	}

	cash := snap.Accounts[accs["a1c7e2f0-0001-4a00-9000-000000000001"]]
	if cash.Name != "Cash" || cash.Kind != "cash" || cash.Emoji != "💵" ||
		cash.Color != "#4CAF7D" || cash.OpeningBalanceMinor != 0 ||
		cash.SortOrder != 0 || cash.UpdatedAtMs != 1755000000000 || cash.DeletedAtMs != nil {
		t.Errorf("cash account decoded wrong: %+v", cash)
	}

	// A card carrying debt: an unsigned decode on either side would wrap this
	// into an enormous positive balance.
	if got := snap.Accounts[accs["a1c7e2f0-0002-4a00-9000-000000000002"]].OpeningBalanceMinor; got != -125000 {
		t.Errorf("negative opening balance = %d, want -125000", got)
	}

	// A renamed seed account keeps its literal name, and its opening balance
	// is past double precision.
	savings := snap.Accounts[accs["a1c7e2f0-0003-4a00-9000-000000000003"]]
	if savings.Name != "Жамғарма" || savings.Kind != "savings" {
		t.Errorf("renamed savings account decoded wrong: %+v", savings)
	}
	if savings.OpeningBalanceMinor != 9007199254740993 {
		t.Errorf("opening balance = %d, want 9007199254740993 (precision lost?)", savings.OpeningBalanceMinor)
	}

	// A closed account arrives as a tombstone, not as an absence.
	closed := snap.Accounts[accs["a1c7e2f0-0f01-4a00-9000-000000000f01"]]
	if closed.DeletedAtMs == nil || *closed.DeletedAtMs != 1787158600000 {
		t.Errorf("account tombstone = %v, want 1787158600000", closed.DeletedAtMs)
	}

	cats := map[string]int{}
	for i, c := range snap.Categories {
		cats[c.ID] = i
	}

	groceries := snap.Categories[cats["c1a7e2f0-0001-4a00-9000-000000000001"]]
	if groceries.Name != "Groceries" || groceries.Emoji != "🛒" ||
		groceries.Color != "#4CAF7D" || groceries.Kind != "expense" ||
		groceries.SortOrder != 0 || groceries.UpdatedAtMs != 1755000000000 {
		t.Errorf("groceries decoded wrong: %+v", groceries)
	}
	if groceries.DeletedAtMs != nil {
		t.Errorf("groceries deleted_at_ms = %v, want nil", *groceries.DeletedAtMs)
	}

	// A renamed seed category keeps its literal (non-English) name.
	if got := snap.Categories[cats["c1a7e2f0-0002-4a00-9000-000000000002"]].Name; got != "Кофейни" {
		t.Errorf("renamed category name = %q, want %q", got, "Кофейни")
	}

	// A deleted category arrives as a tombstone, not as an absence.
	fun := snap.Categories[cats["c1a7e2f0-0008-4a00-9000-000000000008"]]
	if fun.DeletedAtMs == nil || *fun.DeletedAtMs != 1787158500000 {
		t.Errorf("category tombstone = %v, want 1787158500000", fun.DeletedAtMs)
	}

	txs := map[string]int{}
	for i, tx := range snap.Transactions {
		txs[tx.ID] = i
	}

	shop := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000001"]]
	if shop.Kind != "expense" || shop.AmountMinor != 24850 ||
		shop.CategoryID != "c1a7e2f0-0001-4a00-9000-000000000001" ||
		shop.AccountID != "a1c7e2f0-0002-4a00-9000-000000000002" || shop.ToAccountID != "" ||
		shop.Note != "weekly shop" || shop.OccurredAt != "2026-08-19T09:30:00Z" ||
		shop.Source != "app" || shop.CreatedAtMs != 1787000000000 ||
		shop.UpdatedAtMs != 1787000000000 || shop.DeletedAtMs != nil {
		t.Errorf("transaction decoded wrong: %+v", shop)
	}

	if got := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000002"]]; got.Note != "" || got.Source != "telegram" {
		t.Errorf("bot-sourced transaction decoded wrong: %+v", got)
	}

	if got := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000003"]]; got.Kind != "income" ||
		got.Note != "августовская зарплата · oylik maosh" {
		t.Errorf("income transaction decoded wrong: %+v", got)
	}

	// Manual placement inside a day. The two hand-placed rows share a day and
	// the EARLIER one is placed first, so a peer that ignored sort_order and
	// sorted by time alone would show them the other way round.
	placedFirst := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000002"]]
	placedSecond := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000001"]]
	if placedFirst.SortOrder != 1 || placedSecond.SortOrder != 2 {
		t.Errorf("sort_order = %d/%d, want 1/2",
			placedFirst.SortOrder, placedSecond.SortOrder)
	}
	if placedFirst.OccurredAt >= placedSecond.OccurredAt {
		t.Errorf("the fixture no longer places the earlier row first: %s vs %s",
			placedFirst.OccurredAt, placedSecond.OccurredAt)
	}
	// Everything untouched by hand must decode as 0, not as some implicit index.
	if got := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000003"]].SortOrder; got != 0 {
		t.Errorf("unplaced row sort_order = %d, want 0", got)
	}

	// 2^53 + 1: if this ever went through a float64 it would come back as
	// 9007199254740992.
	if got := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000004"]].AmountMinor; got != 9007199254740993 {
		t.Errorf("large int64 = %d, want 9007199254740993 (precision lost?)", got)
	}

	del := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000005"]]
	if del.DeletedAtMs == nil || *del.DeletedAtMs != 1787157000000 {
		t.Errorf("transaction tombstone = %v, want 1787157000000", del.DeletedAtMs)
	}

	// "Send to savings": a transfer carries both accounts and no category.
	xfer := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000006"]]
	if xfer.Kind != "transfer" || xfer.AmountMinor != 500000 || xfer.CategoryID != "" ||
		xfer.AccountID != "a1c7e2f0-0002-4a00-9000-000000000002" ||
		xfer.ToAccountID != "a1c7e2f0-0003-4a00-9000-000000000003" ||
		xfer.Note != "oyiga jamgʻarma · в накопления" {
		t.Errorf("transfer decoded wrong: %+v", xfer)
	}
	if !xfer.IsTransfer() {
		t.Error("IsTransfer() = false on a transfer row")
	}

	if snap.Settings.ID != "settings" || snap.Settings.Currency != "UZS" ||
		snap.Settings.Language != "ru" || snap.Settings.UpdatedAtMs != 1787155000000 ||
		snap.Settings.DefaultAccountID != "a1c7e2f0-0002-4a00-9000-000000000002" {
		t.Errorf("settings decoded wrong: %+v", snap.Settings)
	}
}

func TestInteropFixtureRoundTrips(t *testing.T) {
	snap, err := ParseSnapshot(fixtureBytes(t))
	if err != nil {
		t.Fatalf("ParseSnapshot: %v", err)
	}

	encoded, err := snap.Marshal()
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}

	round, err := ParseSnapshot(encoded)
	if err != nil {
		t.Fatalf("re-parsing our own output: %v", err)
	}

	if len(round.Categories) != len(snap.Categories) ||
		len(round.Transactions) != len(snap.Transactions) ||
		len(round.Accounts) != len(snap.Accounts) {
		t.Fatalf("round trip changed row counts: %d/%d/%d vs %d/%d/%d",
			len(round.Accounts), len(round.Categories), len(round.Transactions),
			len(snap.Accounts), len(snap.Categories), len(snap.Transactions))
	}
	for i, want := range snap.Accounts {
		if got := round.Accounts[i]; got.OpeningBalanceMinor != want.OpeningBalanceMinor {
			t.Errorf("account %s opening balance changed: %d -> %d",
				want.ID, want.OpeningBalanceMinor, got.OpeningBalanceMinor)
		}
	}
	if round.Settings.Language != "ru" || round.Settings.Currency != "UZS" {
		t.Errorf("round trip lost settings: %+v", round.Settings)
	}

	for i, want := range snap.Transactions {
		got := round.Transactions[i]
		if got.AccountID != want.AccountID || got.ToAccountID != want.ToAccountID {
			t.Errorf("transaction %s changed accounts: %+v -> %+v", want.ID, want, got)
		}
		if got.SortOrder != want.SortOrder {
			t.Errorf("transaction %s: sort_order %d -> %d",
				want.ID, want.SortOrder, got.SortOrder)
		}
		if got.AmountMinor != want.AmountMinor || got.OccurredAt != want.OccurredAt {
			t.Errorf("transaction %s changed: %+v -> %+v", want.ID, want, got)
		}
		switch {
		case (got.DeletedAtMs == nil) != (want.DeletedAtMs == nil):
			t.Errorf("transaction %s tombstone nullness changed", want.ID)
		case got.DeletedAtMs != nil && *got.DeletedAtMs != *want.DeletedAtMs:
			t.Errorf("transaction %s tombstone value changed", want.ID)
		}
	}
}

// The fixture must also survive the sanitizing path that real peer files go
// through, since a peer's file is untrusted input.
func TestInteropFixtureSurvivesBatch(t *testing.T) {
	snap, err := ParseSnapshot(fixtureBytes(t))
	if err != nil {
		t.Fatalf("ParseSnapshot: %v", err)
	}

	batch, skipped := snap.Batch()
	if len(skipped) != 0 {
		t.Errorf("fixture rows rejected by Batch(): %v", skipped)
	}
	if len(batch.Categories) != 4 {
		t.Errorf("batch categories = %d, want 4", len(batch.Categories))
	}
	if len(batch.Transactions) != 6 {
		t.Errorf("batch transactions = %d, want 6", len(batch.Transactions))
	}
	if len(batch.Accounts) != 4 {
		t.Errorf("batch accounts = %d, want 4", len(batch.Accounts))
	}
}

// A peer that has not been updated yet keeps publishing schema 1. Refusing to
// read it would strand that device, so the pre-accounts fixture must still
// parse and sanitize — with every transaction booked to the default account,
// which is exactly where the local migration puts this peer's own old rows.
func TestInteropV1FixtureStillReadable(t *testing.T) {
	snap, err := ParseSnapshot(fixtureFile(t, "snapshot.v1.example.json"))
	if err != nil {
		t.Fatalf("ParseSnapshot on the v1 fixture: %v", err)
	}
	if snap.Schema != 1 {
		t.Fatalf("schema = %d, want 1", snap.Schema)
	}
	if len(snap.Accounts) != 0 {
		t.Fatalf("v1 fixture carried %d accounts", len(snap.Accounts))
	}

	batch, skipped := snap.Batch()
	if len(skipped) != 0 {
		t.Errorf("v1 fixture rows rejected by Batch(): %v", skipped)
	}
	if len(batch.Transactions) != 5 {
		t.Fatalf("batch transactions = %d, want 5", len(batch.Transactions))
	}
	for _, tx := range batch.Transactions {
		if tx.AccountID != store.DefaultAccountID {
			t.Errorf("transaction %s booked to %q, want the default account", tx.ID, tx.AccountID)
		}
		if tx.ToAccountID != "" {
			t.Errorf("transaction %s gained a destination account", tx.ID)
		}
	}
	// A v1 settings row names no default account, and Batch must leave it that
	// way rather than inventing one. Filling in "cash" here would make the old
	// peer look like it had actively chosen cash, and under last-write-wins a
	// stale snapshot from the un-upgraded device would then silently overwrite
	// an account the owner had picked in the app. Supplying the fallback is
	// the store's job, where "" is read as "unchanged" — see
	// TestMergeV1SettingsKeepsChosenDefaultAccount.
	if len(batch.Settings) != 1 {
		t.Fatalf("batch settings = %d, want 1", len(batch.Settings))
	}
	if batch.Settings[0].DefaultAccountID != "" {
		t.Errorf("v1 settings default_account_id = %q, want it left empty",
			batch.Settings[0].DefaultAccountID)
	}
}
