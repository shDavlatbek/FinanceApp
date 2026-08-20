package store

import (
	"path/filepath"
	"testing"
	"time"

	"github.com/xensa/tally/internal/model"
)

func openTestStore(t *testing.T) *Store {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "tally.db"), "USD")
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func ptr(v int64) *int64 { return &v }

func TestSeedOnEmptyDB(t *testing.T) {
	s := openTestStore(t)

	snap, err := s.FullState()
	if err != nil {
		t.Fatalf("FullState: %v", err)
	}
	if len(snap.Categories) != len(SeedCategories) {
		t.Fatalf("seeded %d categories, want %d", len(snap.Categories), len(SeedCategories))
	}
	if len(snap.Transactions) != 0 {
		t.Fatalf("seeded %d transactions, want 0", len(snap.Transactions))
	}
	// The settings singleton is seeded "unset" (0), NOT at SeedUpdatedAtMs: it
	// is the one seeded row whose contents differ per peer (DEFAULT_CURRENCY
	// here, USD in the app), and matching timestamps would deadlock it under
	// strict LWW forever. See TestSettingsSeedNeverBlocksAPeerValue.
	if snap.Settings.Currency != "USD" || snap.Settings.ID != model.SettingsID ||
		snap.Settings.UpdatedAtMs != SettingsUnsetMs {
		t.Fatalf("bad seeded settings: %+v", snap.Settings)
	}
	// language defaults to "" — follow the device/Telegram locale.
	if snap.Settings.Language != "" {
		t.Fatalf("seeded language = %q, want \"\"", snap.Settings.Language)
	}

	byID := map[string]model.Category{}
	for _, c := range snap.Categories {
		byID[c.ID] = c
	}
	g, ok := byID["c1a7e2f0-0001-4a00-9000-000000000001"]
	if !ok || g.Name != "Groceries" || g.Emoji != "🛒" || g.Color != "#4CAF7D" ||
		g.Kind != "expense" || g.UpdatedAtMs != SeedUpdatedAtMs {
		t.Fatalf("bad Groceries seed: %+v", g)
	}

	// Nothing is dirty on a fresh seed: both peers seed identical rows.
	dirty, err := s.HasDirty()
	if err != nil {
		t.Fatal(err)
	}
	if dirty {
		t.Fatal("fresh seed marked dirty")
	}

	// Reopening must not re-seed or bump seq.
	path := filepath.Join(t.TempDir(), "reopen.db")
	s2, err := Open(path, "EUR")
	if err != nil {
		t.Fatal(err)
	}
	seq1, _ := s2.CurrentSeq()
	s2.Close()
	s3, err := Open(path, "EUR")
	if err != nil {
		t.Fatal(err)
	}
	defer s3.Close()
	seq2, _ := s3.CurrentSeq()
	if seq1 != seq2 {
		t.Fatalf("reopen changed seq: %d → %d", seq1, seq2)
	}
}

func TestMergeRemoteLWW(t *testing.T) {
	s := openTestStore(t)

	tx1 := model.Transaction{
		ID: "11111111-1111-4111-8111-111111111111", Kind: "expense", AmountMinor: 25000,
		CategoryID: "c1a7e2f0-0001-4a00-9000-000000000001", Note: "first",
		OccurredAt: "2026-08-19T10:00:00Z", Source: "app",
		CreatedAtMs: 1000, UpdatedAtMs: 1000,
	}
	applied, err := s.MergeRemote(Batch{Transactions: []model.Transaction{tx1}})
	if err != nil {
		t.Fatal(err)
	}
	if applied != 1 {
		t.Fatalf("insert applied = %d, want 1", applied)
	}
	// A merged row is not dirty: it came from a peer, we owe nothing.
	if dirty, _ := s.HasDirty(); dirty {
		t.Fatal("merged row marked dirty")
	}

	// Older update must be ignored.
	older := tx1
	older.Note = "older"
	older.UpdatedAtMs = 500
	if applied, err = s.MergeRemote(Batch{Transactions: []model.Transaction{older}}); err != nil {
		t.Fatal(err)
	} else if applied != 0 {
		t.Fatalf("older row applied = %d, want 0", applied)
	}

	// Tie (equal updated_at_ms) must keep the LOCAL row.
	tie := tx1
	tie.Note = "tie"
	if applied, err = s.MergeRemote(Batch{Transactions: []model.Transaction{tie}}); err != nil {
		t.Fatal(err)
	} else if applied != 0 {
		t.Fatalf("tie applied = %d, want 0 (ties keep the local row)", applied)
	}
	snap, _ := s.FullState()
	if got := findTx(t, snap, tx1.ID).Note; got != "first" {
		t.Fatalf("LWW lost: note = %q, want %q", got, "first")
	}

	// Newer update wins.
	newer := tx1
	newer.Note = "newer"
	newer.UpdatedAtMs = 2000
	if applied, err = s.MergeRemote(Batch{Transactions: []model.Transaction{newer}}); err != nil {
		t.Fatal(err)
	} else if applied != 1 {
		t.Fatalf("newer row applied = %d, want 1", applied)
	}
	snap, _ = s.FullState()
	if got := findTx(t, snap, tx1.ID); got.Note != "newer" || got.UpdatedAtMs != 2000 {
		t.Fatalf("newer row not applied: %+v", got)
	}

	// Tombstone flows through and survives in the full dump.
	dead := newer
	dead.UpdatedAtMs = 3000
	dead.DeletedAtMs = ptr(3000)
	if _, err = s.MergeRemote(Batch{Transactions: []model.Transaction{dead}}); err != nil {
		t.Fatal(err)
	}
	snap, _ = s.FullState()
	got := findTx(t, snap, tx1.ID)
	if got.DeletedAtMs == nil || *got.DeletedAtMs != 3000 {
		t.Fatalf("tombstone not stored: %+v", got)
	}

	// A resurrection older than the tombstone must NOT win.
	resurrect := newer
	resurrect.Note = "back from the dead"
	resurrect.UpdatedAtMs = 2500
	if applied, err = s.MergeRemote(Batch{Transactions: []model.Transaction{resurrect}}); err != nil {
		t.Fatal(err)
	} else if applied != 0 {
		t.Fatal("stale row resurrected a tombstone")
	}
	snap, _ = s.FullState()
	if findTx(t, snap, tx1.ID).DeletedAtMs == nil {
		t.Fatal("tombstone was cleared by a stale row")
	}

	// A NEWER edit legitimately resurrects it (the user un-deleted it).
	revive := newer
	revive.Note = "revived"
	revive.UpdatedAtMs = 4000
	revive.DeletedAtMs = nil
	if _, err = s.MergeRemote(Batch{Transactions: []model.Transaction{revive}}); err != nil {
		t.Fatal(err)
	}
	snap, _ = s.FullState()
	if findTx(t, snap, tx1.ID).DeletedAtMs != nil {
		t.Fatal("newer un-delete did not clear the tombstone")
	}

	// Categories: tie keeps local, newer wins, tombstone applies.
	cat := model.Category{
		ID: "bbbbbbbb-0000-4000-8000-000000000001", Name: "Books", Emoji: "📚",
		Color: "#112233", Kind: "expense", SortOrder: 42, UpdatedAtMs: 5000,
	}
	if _, err = s.MergeRemote(Batch{Categories: []model.Category{cat}}); err != nil {
		t.Fatal(err)
	}
	tieCat := cat
	tieCat.Name = "Tie"
	if applied, _ := s.MergeRemote(Batch{Categories: []model.Category{tieCat}}); applied != 0 {
		t.Fatal("category tie overwrote the local row")
	}
	deadCat := cat
	deadCat.UpdatedAtMs = 6000
	deadCat.DeletedAtMs = ptr(6000)
	if _, err = s.MergeRemote(Batch{Categories: []model.Category{deadCat}}); err != nil {
		t.Fatal(err)
	}
	if c, err := s.GetCategory(cat.ID); err != nil || c.DeletedAtMs == nil {
		t.Fatalf("category tombstone not applied: %+v %v", c, err)
	}
	// A tombstoned category disappears from the live list but stays in the dump.
	for _, c := range mustList(t, s, "") {
		if c.ID == cat.ID {
			t.Fatal("tombstoned category still listed")
		}
	}
	snap, _ = s.FullState()
	if !hasCategory(snap, cat.ID) {
		t.Fatal("tombstoned category missing from the full dump")
	}

	// Settings LWW, including the new language field. Several peers may each
	// carry a settings row in one batch; the newest must win regardless of
	// the order they appear in.
	if _, err = s.MergeRemote(Batch{Settings: []model.Settings{
		{ID: model.SettingsID, Currency: "RUB", Language: "ru", UpdatedAtMs: SeedUpdatedAtMs + 20},
		{ID: model.SettingsID, Currency: "EUR", Language: "en", UpdatedAtMs: SeedUpdatedAtMs + 10},
	}}); err != nil {
		t.Fatal(err)
	}
	st, err := s.Settings()
	if err != nil {
		t.Fatal(err)
	}
	if st.Currency != "RUB" || st.Language != "ru" {
		t.Fatalf("settings LWW picked the wrong row: %+v", st)
	}
	// An older settings row must not clobber it.
	if _, err = s.MergeRemote(Batch{Settings: []model.Settings{
		{ID: model.SettingsID, Currency: "GBP", Language: "uz", UpdatedAtMs: SeedUpdatedAtMs},
	}}); err != nil {
		t.Fatal(err)
	}
	st, _ = s.Settings()
	if st.Currency != "RUB" || st.Language != "ru" {
		t.Fatalf("older settings overwrote newer: %+v", st)
	}
}

// Merging the same batch twice must change nothing the second time.
func TestMergeIsIdempotent(t *testing.T) {
	s := openTestStore(t)
	batch := Batch{
		Categories: []model.Category{{
			ID: "bbbbbbbb-0000-4000-8000-000000000002", Name: "Pets", Emoji: "🐈",
			Color: "#445566", Kind: "expense", SortOrder: 7, UpdatedAtMs: 5000,
		}},
		Transactions: []model.Transaction{{
			ID: "22222222-2222-4222-8222-222222222222", Kind: "expense", AmountMinor: 900,
			CategoryID: "bbbbbbbb-0000-4000-8000-000000000002", OccurredAt: "2026-08-19T10:00:00Z",
			Source: "app", CreatedAtMs: 5000, UpdatedAtMs: 5000,
		}},
		Settings: []model.Settings{{ID: model.SettingsID, Currency: "USD", Language: "uz", UpdatedAtMs: SeedUpdatedAtMs + 5}},
	}
	first, err := s.MergeRemote(batch)
	if err != nil {
		t.Fatal(err)
	}
	if first != 3 {
		t.Fatalf("first merge applied %d rows, want 3", first)
	}
	second, err := s.MergeRemote(batch)
	if err != nil {
		t.Fatal(err)
	}
	if second != 0 {
		t.Fatalf("re-merging the same batch applied %d rows, want 0", second)
	}
}

func TestDirtyLifecycle(t *testing.T) {
	s := openTestStore(t)

	hookCalls := 0
	s.SetWriteHook(func() { hookCalls++ })

	tx := model.Transaction{
		ID: "33333333-3333-4333-8333-333333333333", Kind: "expense", AmountMinor: 500,
		CategoryID: SeedCategories[0].ID, OccurredAt: "2026-08-19T10:00:00Z",
		Source: "telegram", CreatedAtMs: 1000, UpdatedAtMs: 1000,
	}
	if err := s.InsertTransaction(tx); err != nil {
		t.Fatal(err)
	}
	if hookCalls != 1 {
		t.Fatalf("write hook fired %d times, want 1", hookCalls)
	}
	dirty, err := s.HasDirty()
	if err != nil {
		t.Fatal(err)
	}
	if !dirty {
		t.Fatal("local insert did not mark the row dirty")
	}

	// Serialize a snapshot, then race a local edit against the "upload".
	snap, err := s.FullState()
	if err != nil {
		t.Fatal(err)
	}
	edited := tx
	edited.Note = "edited mid-sync"
	edited.UpdatedAtMs = 2000
	if err := s.InsertTransaction(edited); err != nil {
		t.Fatal(err)
	}
	if err := s.ClearDirty(snap); err != nil {
		t.Fatal(err)
	}
	dirty, err = s.HasDirty()
	if err != nil {
		t.Fatal(err)
	}
	if !dirty {
		t.Fatal("a row edited mid-sync was wrongly cleared")
	}

	// Clearing against a snapshot that DOES match the current state works.
	snap2, err := s.FullState()
	if err != nil {
		t.Fatal(err)
	}
	if err := s.ClearDirty(snap2); err != nil {
		t.Fatal(err)
	}
	dirty, err = s.HasDirty()
	if err != nil {
		t.Fatal(err)
	}
	if dirty {
		t.Fatal("ClearDirty left rows dirty")
	}

	// Undo tombstones and re-dirties.
	if err := s.SoftDeleteTransaction(tx.ID, 3000); err != nil {
		t.Fatal(err)
	}
	if dirty, _ = s.HasDirty(); !dirty {
		t.Fatal("soft delete did not mark the row dirty")
	}

	// Merging a remote row never fires the local write hook (it would
	// ping-pong an upload back at the peer we just heard from).
	before := hookCalls
	if _, err := s.MergeRemote(Batch{Transactions: []model.Transaction{{
		ID: "44444444-4444-4444-8444-444444444444", Kind: "income", AmountMinor: 10,
		CategoryID: SeedCategories[0].ID, OccurredAt: "2026-08-19T10:00:00Z",
		Source: "app", CreatedAtMs: 1, UpdatedAtMs: 1,
	}}}); err != nil {
		t.Fatal(err)
	}
	if hookCalls != before {
		t.Fatalf("MergeRemote fired the write hook %d time(s)", hookCalls-before)
	}
}

func TestMetaKV(t *testing.T) {
	s := openTestStore(t)

	if v, ok, err := s.Meta(MetaDeviceID); err != nil || ok || v != "" {
		t.Fatalf("Meta on a missing key = %q %v %v", v, ok, err)
	}
	if v, err := s.MetaOr(MetaFolderID, "fallback"); err != nil || v != "fallback" {
		t.Fatalf("MetaOr = %q %v", v, err)
	}
	if err := s.SetMeta(MetaFolderID, "folder-1"); err != nil {
		t.Fatal(err)
	}
	if err := s.SetMeta(MetaFolderID, "folder-2"); err != nil { // overwrite
		t.Fatal(err)
	}
	v, ok, err := s.Meta(MetaFolderID)
	if err != nil || !ok || v != "folder-2" {
		t.Fatalf("Meta = %q %v %v", v, ok, err)
	}
}

func TestSummariesUndoAliases(t *testing.T) {
	s := openTestStore(t)
	groceries := "c1a7e2f0-0001-4a00-9000-000000000001"
	cafe := "c1a7e2f0-0002-4a00-9000-000000000002"
	salaryCat := "c1a7e2f0-0101-4a00-9000-000000000101"

	mk := func(id string, kind string, minor int64, catID, occurred string, createdMs int64) model.Transaction {
		return model.Transaction{
			ID: id, Kind: kind, AmountMinor: minor, CategoryID: catID,
			OccurredAt: occurred, Source: "telegram", CreatedAtMs: createdMs, UpdatedAtMs: createdMs,
		}
	}
	rows := []model.Transaction{
		mk("00000000-0000-4000-8000-000000000001", "expense", 25000, groceries, "2026-08-10T09:00:00Z", 1),
		mk("00000000-0000-4000-8000-000000000002", "expense", 12000, groceries, "2026-08-11T09:00:00Z", 2),
		mk("00000000-0000-4000-8000-000000000003", "expense", 5000, cafe, "2026-08-11T10:00:00Z", 3),
		mk("00000000-0000-4000-8000-000000000004", "income", 100000, salaryCat, "2026-08-12T09:00:00Z", 4),
		// outside the window:
		mk("00000000-0000-4000-8000-000000000005", "expense", 99900, groceries, "2026-07-31T23:59:59Z", 5),
	}
	if _, err := s.MergeRemote(Batch{Transactions: rows}); err != nil {
		t.Fatal(err)
	}

	from := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	sum, err := s.PeriodSummary(from, to)
	if err != nil {
		t.Fatal(err)
	}
	if sum.Income != 100000 || sum.Expenses != 42000 {
		t.Fatalf("summary = income %d expenses %d, want 100000 / 42000", sum.Income, sum.Expenses)
	}
	// Count feeds the bot's localized "N transactions" line, so it must cover
	// both kinds and stop at the window boundary.
	if sum.Count != 4 {
		t.Fatalf("summary count = %d, want 4", sum.Count)
	}
	if len(sum.TopExpenses) != 2 || sum.TopExpenses[0].Category.ID != groceries || sum.TopExpenses[0].Total != 37000 ||
		sum.TopExpenses[1].Category.ID != cafe || sum.TopExpenses[1].Total != 5000 {
		t.Fatalf("top expenses wrong: %+v", sum.TopExpenses)
	}

	total, err := s.CategoryPeriodTotal(groceries, from, to)
	if err != nil {
		t.Fatal(err)
	}
	if total != 37000 {
		t.Fatalf("category total = %d, want 37000", total)
	}

	// Undo: last by created_at_ms is id …005; soft delete removes it from summaries.
	last, err := s.LastTransaction()
	if err != nil {
		t.Fatal(err)
	}
	if last.ID != "00000000-0000-4000-8000-000000000005" {
		t.Fatalf("last tx = %s", last.ID)
	}
	if err := s.SoftDeleteTransaction(last.ID, 9999); err != nil {
		t.Fatal(err)
	}
	last2, err := s.LastTransaction()
	if err != nil {
		t.Fatal(err)
	}
	if last2.ID != "00000000-0000-4000-8000-000000000004" {
		t.Fatalf("after undo last tx = %s", last2.ID)
	}
	julyFrom := time.Date(2026, 7, 1, 0, 0, 0, 0, time.UTC)
	julySum, err := s.PeriodSummary(julyFrom, from)
	if err != nil {
		t.Fatal(err)
	}
	if julySum.Expenses != 0 || julySum.Count != 0 {
		t.Fatalf("soft-deleted tx still counted: %+v", julySum)
	}

	// Aliases.
	if _, ok, _ := s.GetAlias("atb"); ok {
		t.Fatal("alias should not exist yet")
	}
	if err := s.SetAlias("atb", groceries); err != nil {
		t.Fatal(err)
	}
	id, ok, err := s.GetAlias("atb")
	if err != nil || !ok || id != groceries {
		t.Fatalf("GetAlias = %q %v %v", id, ok, err)
	}
	if err := s.SetAlias("atb", cafe); err != nil { // overwrite
		t.Fatal(err)
	}
	id, _, _ = s.GetAlias("atb")
	if id != cafe {
		t.Fatalf("alias overwrite failed: %q", id)
	}
}

// A v1 database (no language / dirty columns) must migrate in place.
func TestMigrateFromV1Schema(t *testing.T) {
	path := filepath.Join(t.TempDir(), "v1.db")
	s, err := Open(path, "USD")
	if err != nil {
		t.Fatal(err)
	}
	// Simulate the v1 shape by dropping the v2 columns.
	for _, stmt := range []string{
		`ALTER TABLE settings DROP COLUMN language`,
		`ALTER TABLE settings DROP COLUMN dirty`,
		`ALTER TABLE categories DROP COLUMN dirty`,
		`ALTER TABLE transactions DROP COLUMN dirty`,
	} {
		if _, err := s.db.Exec(stmt); err != nil {
			t.Fatalf("%s: %v", stmt, err)
		}
	}
	s.Close()

	s2, err := Open(path, "USD")
	if err != nil {
		t.Fatalf("reopen after v1 downgrade: %v", err)
	}
	defer s2.Close()
	st, err := s2.Settings()
	if err != nil {
		t.Fatal(err)
	}
	if st.Language != "" {
		t.Fatalf("migrated language = %q, want \"\"", st.Language)
	}
	if _, err := s2.HasDirty(); err != nil {
		t.Fatalf("dirty column missing after migration: %v", err)
	}
}

// The seed-name localization rule: localize only while the stored name is
// still the canonical English one.
func TestSeedNameRule(t *testing.T) {
	groceries := SeedCategories[0]
	if name, ok := SeedCategoryName(groceries.ID); !ok || name != "Groceries" {
		t.Fatalf("SeedCategoryName = %q %v", name, ok)
	}
	if _, ok := SeedCategoryName("bbbbbbbb-0000-4000-8000-000000000001"); ok {
		t.Fatal("a non-seed id was reported as a seed")
	}
	if !IsUnrenamedSeed(groceries) {
		t.Fatal("an untouched seed is not localizable")
	}
	renamed := groceries
	renamed.Name = "Продукты"
	if IsUnrenamedSeed(renamed) {
		t.Fatal("a renamed seed would still be localized, overwriting the user's name")
	}
	if IsUnrenamedSeed(model.Category{ID: "bbbbbbbb-0000-4000-8000-000000000001", Name: "Books"}) {
		t.Fatal("a user-created category was treated as a seed")
	}
}

func findTx(t *testing.T, snap Snapshot, id string) model.Transaction {
	t.Helper()
	for _, tr := range snap.Transactions {
		if tr.ID == id {
			return tr
		}
	}
	t.Fatalf("transaction %s not in snapshot", id)
	return model.Transaction{}
}

func hasCategory(snap Snapshot, id string) bool {
	for _, c := range snap.Categories {
		if c.ID == id {
			return true
		}
	}
	return false
}

func mustList(t *testing.T, s *Store, kind string) []model.Category {
	t.Helper()
	cats, err := s.ListCategories(kind)
	if err != nil {
		t.Fatal(err)
	}
	return cats
}
