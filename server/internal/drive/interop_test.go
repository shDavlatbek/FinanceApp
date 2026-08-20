package drive

import (
	"os"
	"path/filepath"
	"testing"
)

// Cross-implementation guard: the Go and Dart peers must agree, byte for byte,
// on the snapshot wire format in docs/ARCHITECTURE.md.
//
// Both sides parse the SAME fixture and assert the same values. A field
// rename, a null-handling difference, or an int64 routed through a double on
// either side breaks one of these two tests — the only cheap way to catch sync
// divergence without live Google credentials. The Dart half lives in
// app/test/snapshot_interop_test.dart and reads the same file.

func fixtureBytes(t *testing.T) []byte {
	t.Helper()
	path := filepath.Join("..", "..", "..", "docs", "fixtures", "snapshot.example.json")
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading interop fixture: %v", err)
	}
	return b
}

func TestInteropFixtureParses(t *testing.T) {
	snap, err := ParseSnapshot(fixtureBytes(t))
	if err != nil {
		t.Fatalf("ParseSnapshot: %v", err)
	}

	if snap.Schema != 1 {
		t.Errorf("schema = %d, want 1", snap.Schema)
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
	if len(snap.Transactions) != 5 {
		t.Fatalf("transactions = %d, want 5", len(snap.Transactions))
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
		shop.Note != "weekly shop" || shop.OccurredAt != "2026-08-18T09:30:00Z" ||
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

	// 2^53 + 1: if this ever went through a float64 it would come back as
	// 9007199254740992.
	if got := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000004"]].AmountMinor; got != 9007199254740993 {
		t.Errorf("large int64 = %d, want 9007199254740993 (precision lost?)", got)
	}

	del := snap.Transactions[txs["aaaaaaaa-0000-4000-8000-000000000005"]]
	if del.DeletedAtMs == nil || *del.DeletedAtMs != 1787157000000 {
		t.Errorf("transaction tombstone = %v, want 1787157000000", del.DeletedAtMs)
	}

	if snap.Settings.ID != "settings" || snap.Settings.Currency != "UZS" ||
		snap.Settings.Language != "ru" || snap.Settings.UpdatedAtMs != 1787155000000 {
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
		len(round.Transactions) != len(snap.Transactions) {
		t.Fatalf("round trip changed row counts: %d/%d vs %d/%d",
			len(round.Categories), len(round.Transactions),
			len(snap.Categories), len(snap.Transactions))
	}
	if round.Settings.Language != "ru" || round.Settings.Currency != "UZS" {
		t.Errorf("round trip lost settings: %+v", round.Settings)
	}

	for i, want := range snap.Transactions {
		got := round.Transactions[i]
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
	if len(batch.Transactions) != 5 {
		t.Errorf("batch transactions = %d, want 5", len(batch.Transactions))
	}
}
