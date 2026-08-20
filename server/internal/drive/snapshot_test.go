package drive

import (
	"encoding/json"
	"reflect"
	"sort"
	"testing"

	"github.com/xensa/tally/internal/model"
	"github.com/xensa/tally/internal/store"
)

func ptr(v int64) *int64 { return &v }

func sampleState() store.Snapshot {
	return store.Snapshot{
		Accounts: []model.Account{
			{ID: store.DefaultAccountID, Name: "Cash", Kind: model.AccountCash, Emoji: "💵",
				Color: "#4CAF7D", SortOrder: 0, UpdatedAtMs: 1755000000000},
			{ID: "a1c7e2f0-0003-4a00-9000-000000000003", Name: "Savings", Kind: model.AccountSavings,
				Emoji: "🏦", Color: "#E8C95A", OpeningBalanceMinor: 1500000, SortOrder: 2,
				UpdatedAtMs: 1755000000000},
		},
		Categories: []model.Category{
			{ID: "c1a7e2f0-0001-4a00-9000-000000000001", Name: "Groceries", Emoji: "🛒",
				Color: "#4CAF7D", Kind: model.KindExpense, SortOrder: 0, UpdatedAtMs: 1755000000000},
			{ID: "bbbbbbbb-0000-4000-8000-000000000001", Name: "Books", Emoji: "📚",
				Color: "#112233", Kind: model.KindExpense, SortOrder: 42, UpdatedAtMs: 1787000000000,
				DeletedAtMs: ptr(1787000001000)},
		},
		Transactions: []model.Transaction{
			{ID: "11111111-1111-4111-8111-111111111111", Kind: model.KindExpense, AmountMinor: 25000,
				CategoryID: "c1a7e2f0-0001-4a00-9000-000000000001", AccountID: store.DefaultAccountID,
				Note:       "weekly stuff",
				OccurredAt: "2026-08-19T10:00:00Z", Source: model.SourceTelegram,
				CreatedAtMs: 1787000000000, UpdatedAtMs: 1787000000000},
			{ID: "22222222-2222-4222-8222-222222222222", Kind: model.KindIncome, AmountMinor: 5000000,
				CategoryID: "c1a7e2f0-0101-4a00-9000-000000000101", AccountID: store.DefaultAccountID,
				Note:       "",
				OccurredAt: "2026-08-01T06:00:00Z", Source: model.SourceApp,
				CreatedAtMs: 1786000000000, UpdatedAtMs: 1786500000000, DeletedAtMs: ptr(1786500000000)},
			// "send to savings": neither income nor expense, so it moves a
			// balance without touching a single monthly total.
			{ID: "33333333-3333-4333-8333-333333333333", Kind: model.KindTransfer, AmountMinor: 200000,
				CategoryID: "", AccountID: store.DefaultAccountID,
				ToAccountID: "a1c7e2f0-0003-4a00-9000-000000000003", Note: "rainy day",
				OccurredAt: "2026-08-20T08:00:00Z", Source: model.SourceApp,
				CreatedAtMs: 1787200000000, UpdatedAtMs: 1787200000000},
		},
		Settings: model.Settings{ID: model.SettingsID, Currency: "UZS", Language: "uz",
			DefaultAccountID: store.DefaultAccountID, UpdatedAtMs: 1787000000000},
	}
}

func TestSnapshotRoundTrip(t *testing.T) {
	in := NewSnapshot("b2c3d4e5-0000-4000-8000-000000000001", "Pixel 7", 1787160000000, sampleState())

	raw, err := in.Marshal()
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	out, err := ParseSnapshot(raw)
	if err != nil {
		t.Fatalf("ParseSnapshot: %v", err)
	}
	if !reflect.DeepEqual(in, out) {
		t.Fatalf("round trip changed the snapshot:\n in = %+v\nout = %+v", in, out)
	}
	// Tombstones must survive verbatim — losing one un-deletes a row on
	// every other peer.
	if out.Transactions[1].DeletedAtMs == nil || *out.Transactions[1].DeletedAtMs != 1786500000000 {
		t.Fatalf("transaction tombstone lost: %+v", out.Transactions[1])
	}
	if out.Categories[1].DeletedAtMs == nil {
		t.Fatal("category tombstone lost")
	}
	// …and a live row must NOT gain one.
	if out.Transactions[0].DeletedAtMs != nil {
		t.Fatal("live transaction gained a tombstone")
	}
}

// The top-level JSON shape is a binding contract with the Flutter app.
func TestSnapshotWireShape(t *testing.T) {
	raw, err := NewSnapshot("dev-1", "Pixel 7", 1787160000000, sampleState()).Marshal()
	if err != nil {
		t.Fatal(err)
	}
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		t.Fatal(err)
	}
	got := make([]string, 0, len(top))
	for k := range top {
		got = append(got, k)
	}
	sort.Strings(got)
	want := []string{"accounts", "categories", "device_id", "device_name", "schema", "settings", "transactions", "written_at_ms"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("snapshot keys = %v, want %v", got, want)
	}

	var row map[string]any
	var txs []map[string]any
	if err := json.Unmarshal(top["transactions"], &txs); err != nil {
		t.Fatal(err)
	}
	row = txs[0]
	for _, k := range []string{"id", "kind", "amount_minor", "category_id", "account_id",
		"to_account_id", "note", "occurred_at", "source", "created_at_ms", "updated_at_ms",
		"deleted_at_ms"} {
		if _, ok := row[k]; !ok {
			t.Fatalf("transaction JSON missing %q: %v", k, row)
		}
	}

	var cats []map[string]any
	if err := json.Unmarshal(top["categories"], &cats); err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"id", "name", "emoji", "color", "kind", "sort_order",
		"updated_at_ms", "deleted_at_ms"} {
		if _, ok := cats[0][k]; !ok {
			t.Fatalf("category JSON missing %q: %v", k, cats[0])
		}
	}

	var settings map[string]any
	if err := json.Unmarshal(top["settings"], &settings); err != nil {
		t.Fatal(err)
	}
	for _, k := range []string{"id", "currency", "language", "default_account_id", "updated_at_ms"} {
		if _, ok := settings[k]; !ok {
			t.Fatalf("settings JSON missing %q: %v", k, settings)
		}
	}
	if settings["language"] != "uz" {
		t.Fatalf("settings.language = %v, want uz", settings["language"])
	}

	var accounts []map[string]any
	if err := json.Unmarshal(top["accounts"], &accounts); err != nil {
		t.Fatal(err)
	}
	if len(accounts) == 0 {
		t.Fatal("snapshot carried no accounts")
	}
	for _, k := range []string{"id", "name", "kind", "emoji", "color",
		"opening_balance_minor", "sort_order", "updated_at_ms", "deleted_at_ms"} {
		if _, ok := accounts[0][k]; !ok {
			t.Fatalf("account JSON missing %q: %v", k, accounts[0])
		}
	}
}

func TestParseSnapshotRejectsForeignSchema(t *testing.T) {
	if _, err := ParseSnapshot([]byte(`{"schema":3,"device_id":"x"}`)); err == nil {
		t.Fatal("a schema from the future was accepted")
	}
	if _, err := ParseSnapshot([]byte(`{"schema":0,"device_id":"x"}`)); err == nil {
		t.Fatal("schema 0 was accepted")
	}
	if _, err := ParseSnapshot([]byte(`not json`)); err == nil {
		t.Fatal("garbage was accepted")
	}
	// Schema 1 predates accounts and must still be readable: a peer that has
	// not been updated yet keeps publishing it, and refusing to read it would
	// strand the owner's phone.
	if _, err := ParseSnapshot([]byte(`{"schema":1,"device_id":"x"}`)); err != nil {
		t.Fatalf("schema 1 was rejected: %v", err)
	}
}

func TestSnapshotBatchSanitizes(t *testing.T) {
	s := Snapshot{
		Schema: SnapshotSchema,
		Categories: []model.Category{
			{ID: "ok", Name: "Fine", Emoji: "✅", Color: "#001122", Kind: model.KindExpense, UpdatedAtMs: 10},
			{ID: "", Name: "No id", Emoji: "x", Color: "#001122", Kind: model.KindExpense, UpdatedAtMs: 10},
			{ID: "bad-color", Name: "X", Emoji: "x", Color: "red", Kind: model.KindExpense, UpdatedAtMs: 10},
			{ID: "bad-kind", Name: "X", Emoji: "x", Color: "#001122", Kind: "transfer", UpdatedAtMs: 10},
		},
		Transactions: []model.Transaction{
			// offset form must be normalized to the canonical UTC "Z" layout
			// the period queries string-compare against.
			{ID: "t-offset", Kind: model.KindExpense, AmountMinor: 100, CategoryID: "ok",
				OccurredAt: "2026-08-19T13:00:00+03:00", Source: model.SourceApp, UpdatedAtMs: 10},
			{ID: "t-zero", Kind: model.KindExpense, AmountMinor: 0, CategoryID: "ok",
				OccurredAt: "2026-08-19T10:00:00Z", Source: model.SourceApp, UpdatedAtMs: 10},
			{ID: "t-source", Kind: model.KindExpense, AmountMinor: 100, CategoryID: "ok",
				OccurredAt: "2026-08-19T10:00:00Z", Source: "carrier-pigeon", UpdatedAtMs: 10},
			{ID: "t-date", Kind: model.KindExpense, AmountMinor: 100, CategoryID: "ok",
				OccurredAt: "yesterday", Source: model.SourceApp, UpdatedAtMs: 10},
		},
		Settings: model.Settings{ID: model.SettingsID, Currency: "USD", Language: "ru", UpdatedAtMs: 10},
	}

	b, skipped := s.Batch()
	if len(b.Categories) != 1 || b.Categories[0].ID != "ok" {
		t.Fatalf("categories = %+v", b.Categories)
	}
	if len(b.Transactions) != 1 || b.Transactions[0].ID != "t-offset" {
		t.Fatalf("transactions = %+v", b.Transactions)
	}
	if got := b.Transactions[0].OccurredAt; got != "2026-08-19T10:00:00Z" {
		t.Fatalf("occurred_at = %q, want canonical UTC", got)
	}
	if len(b.Settings) != 1 || b.Settings[0].Language != "ru" {
		t.Fatalf("settings = %+v", b.Settings)
	}
	if len(skipped) != 6 {
		t.Fatalf("skipped %d rows, want 6: %v", len(skipped), skipped)
	}

	// A bad language or currency drops only the settings row.
	s.Settings.Language = "kl"
	if b, _ := s.Batch(); len(b.Settings) != 0 {
		t.Fatalf("bad language accepted: %+v", b.Settings)
	}
	s.Settings.Language = ""
	s.Settings.Currency = "dollars"
	if b, _ := s.Batch(); len(b.Settings) != 0 {
		t.Fatalf("bad currency accepted: %+v", b.Settings)
	}
	// "" (follow device locale) is a valid language.
	s.Settings.Currency = "USD"
	if b, _ := s.Batch(); len(b.Settings) != 1 {
		t.Fatal(`language "" was rejected`)
	}
}

func TestFileNameRoundTrip(t *testing.T) {
	const id = "b2c3d4e5-0000-4000-8000-000000000001"
	name := FileName(id)
	if name != "tally-"+id+".json" {
		t.Fatalf("FileName = %q", name)
	}
	got, ok := DeviceIDFromFileName(name)
	if !ok || got != id {
		t.Fatalf("DeviceIDFromFileName(%q) = %q %v", name, got, ok)
	}
	// Anything else in the folder must be ignored by the listing filter.
	for _, bad := range []string{"tally.json", "tally-.json", "notes.txt", "tally-x.txt", "my-tally-x.json"} {
		if _, ok := DeviceIDFromFileName(bad); ok {
			t.Fatalf("DeviceIDFromFileName(%q) accepted a foreign file", bad)
		}
	}
}

// Transfer-specific sanitizing. A peer file is hand-editable, so each of these
// is a shape the merge has to survive without corrupting a balance.
func TestSnapshotBatchSanitizesTransfers(t *testing.T) {
	const (
		cash    = "a1c7e2f0-0001-4a00-9000-000000000001"
		savings = "a1c7e2f0-0003-4a00-9000-000000000003"
		ghost   = "a1c7e2f0-0999-4a00-9000-000000000999"
	)
	base := func(id, kind, categoryID, from, to string) model.Transaction {
		return model.Transaction{
			ID: id, Kind: kind, AmountMinor: 1000, CategoryID: categoryID,
			AccountID: from, ToAccountID: to, OccurredAt: "2026-08-20T10:00:00Z",
			Source: model.SourceApp, UpdatedAtMs: 1787000000000,
		}
	}
	s := Snapshot{
		Schema: SnapshotSchema,
		Accounts: []model.Account{
			{ID: cash, Name: "Cash", Kind: model.AccountCash, Emoji: "💵",
				Color: "#4CAF7D", UpdatedAtMs: 1755000000000},
			{ID: savings, Name: "Savings", Kind: model.AccountSavings, Emoji: "🏦",
				Color: "#E8C95A", UpdatedAtMs: 1755000000000},
		},
		Transactions: []model.Transaction{
			base("ok-transfer", model.KindTransfer, "", cash, savings),
			base("no-destination", model.KindTransfer, "", cash, ""),
			base("self-transfer", model.KindTransfer, "", cash, cash),
			base("ghost-destination", model.KindTransfer, "", cash, ghost),
			// A stray destination on an expense is cleared, and the row kept.
			base("stray-destination", model.KindExpense, "c1a7e2f0-0001-4a00-9000-000000000001", cash, savings),
			// An expense with no category is still rejected; only transfers
			// are allowed to be category-less.
			base("no-category", model.KindExpense, "", cash, ""),
		},
	}

	batch, skipped := s.Batch()
	kept := map[string]model.Transaction{}
	for _, tx := range batch.Transactions {
		kept[tx.ID] = tx
	}

	for _, id := range []string{"no-destination", "self-transfer", "ghost-destination", "no-category"} {
		if _, ok := kept[id]; ok {
			t.Errorf("%s survived sanitizing", id)
		}
	}
	if len(skipped) != 4 {
		t.Errorf("skipped %d rows, want 4: %v", len(skipped), skipped)
	}

	good, ok := kept["ok-transfer"]
	if !ok {
		t.Fatal("a valid transfer was dropped")
	}
	if good.ToAccountID != savings || good.AccountID != cash || good.CategoryID != "" {
		t.Errorf("valid transfer was altered: %+v", good)
	}

	stray, ok := kept["stray-destination"]
	if !ok {
		t.Fatal("an expense was dropped over an ignored to_account_id")
	}
	if stray.ToAccountID != "" {
		t.Errorf("stray to_account_id survived on an expense: %q", stray.ToAccountID)
	}
}

// The sanitizer must not MANUFACTURE the row it refuses to accept.
//
// Regression: the unknown-account rewrite ran after the self-transfer check,
// so a transfer whose source account was absent from the snapshot and whose
// destination was the seed cash account got rewritten into cash -> cash — the
// exact shape the check exists to reject, waved through because the check had
// already run. Balances then credited it without ever debiting it.
func TestSnapshotBatchCannotManufactureASelfTransfer(t *testing.T) {
	s := Snapshot{
		Schema: SnapshotSchema,
		// Deliberately NO accounts array, so `known` holds only the default.
		Transactions: []model.Transaction{{
			ID: "ghost-source", Kind: model.KindTransfer, AmountMinor: 5000,
			AccountID:   "a1c7e2f0-0999-4a00-9000-000000000999", // unknown
			ToAccountID: store.DefaultAccountID,
			OccurredAt:  "2026-08-20T10:00:00Z", Source: model.SourceApp,
			UpdatedAtMs: 1787000000000,
		}},
	}

	batch, skipped := s.Batch()
	for _, tx := range batch.Transactions {
		if tx.AccountID == tx.ToAccountID {
			t.Fatalf("sanitizer produced a self-transfer: %+v", tx)
		}
	}
	if len(batch.Transactions) != 0 {
		t.Fatalf("kept %d transactions, want 0", len(batch.Transactions))
	}
	if len(skipped) == 0 {
		t.Fatal("the row was dropped without a word")
	}
}

// A transfer carrying a stray category_id keeps its row but loses the
// category: it is still a real movement of money, but it must not reach a
// category total — which is what the bot echoes after every entry.
func TestSnapshotBatchClearsCategoryOnTransfers(t *testing.T) {
	const savings = "a1c7e2f0-0003-4a00-9000-000000000003"
	s := Snapshot{
		Schema: SnapshotSchema,
		Accounts: []model.Account{{
			ID: savings, Name: "Savings", Kind: model.AccountSavings,
			Emoji: "🏦", Color: "#E8C95A", UpdatedAtMs: 1755000000000,
		}},
		Transactions: []model.Transaction{{
			ID: "stray-category", Kind: model.KindTransfer, AmountMinor: 5000,
			CategoryID:  "c1a7e2f0-0001-4a00-9000-000000000001",
			AccountID:   store.DefaultAccountID,
			ToAccountID: savings,
			OccurredAt:  "2026-08-20T10:00:00Z", Source: model.SourceApp,
			UpdatedAtMs: 1787000000000,
		}},
	}

	batch, _ := s.Batch()
	if len(batch.Transactions) != 1 {
		t.Fatalf("kept %d transactions, want 1", len(batch.Transactions))
	}
	if got := batch.Transactions[0].CategoryID; got != "" {
		t.Errorf("category_id = %q on a transfer, want it cleared", got)
	}
}

// One bad account row must not cost the peer its currency and language.
//
// Regression: an unknown default_account_id skipped the whole settings row,
// so a single malformed account elsewhere in the file could strand the bot
// answering in the wrong language.
func TestSnapshotBatchKeepsSettingsWhenDefaultAccountIsUnknown(t *testing.T) {
	s := Snapshot{
		Schema: SnapshotSchema,
		Settings: model.Settings{
			ID: model.SettingsID, Currency: "RUB", Language: "ru",
			DefaultAccountID: "a1c7e2f0-0999-4a00-9000-000000000999",
			UpdatedAtMs:      1787000000000,
		},
	}

	batch, skipped := s.Batch()
	if len(batch.Settings) != 1 {
		t.Fatalf("settings dropped over an unknown default account: %v", skipped)
	}
	got := batch.Settings[0]
	if got.Currency != "RUB" || got.Language != "ru" {
		t.Errorf("settings mangled: %+v", got)
	}
	// Cleared, not invented: empty means "unchanged" to the store, so the
	// account the owner actually picked locally survives the merge.
	if got.DefaultAccountID != "" {
		t.Errorf("default_account_id = %q, want it cleared", got.DefaultAccountID)
	}
}
