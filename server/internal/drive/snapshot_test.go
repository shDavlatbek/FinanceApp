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
		Categories: []model.Category{
			{ID: "c1a7e2f0-0001-4a00-9000-000000000001", Name: "Groceries", Emoji: "🛒",
				Color: "#4CAF7D", Kind: model.KindExpense, SortOrder: 0, UpdatedAtMs: 1755000000000},
			{ID: "bbbbbbbb-0000-4000-8000-000000000001", Name: "Books", Emoji: "📚",
				Color: "#112233", Kind: model.KindExpense, SortOrder: 42, UpdatedAtMs: 1787000000000,
				DeletedAtMs: ptr(1787000001000)},
		},
		Transactions: []model.Transaction{
			{ID: "11111111-1111-4111-8111-111111111111", Kind: model.KindExpense, AmountMinor: 25000,
				CategoryID: "c1a7e2f0-0001-4a00-9000-000000000001", Note: "weekly stuff",
				OccurredAt: "2026-08-19T10:00:00Z", Source: model.SourceTelegram,
				CreatedAtMs: 1787000000000, UpdatedAtMs: 1787000000000},
			{ID: "22222222-2222-4222-8222-222222222222", Kind: model.KindIncome, AmountMinor: 5000000,
				CategoryID: "c1a7e2f0-0101-4a00-9000-000000000101", Note: "",
				OccurredAt: "2026-08-01T06:00:00Z", Source: model.SourceApp,
				CreatedAtMs: 1786000000000, UpdatedAtMs: 1786500000000, DeletedAtMs: ptr(1786500000000)},
		},
		Settings: model.Settings{ID: model.SettingsID, Currency: "UZS", Language: "uz", UpdatedAtMs: 1787000000000},
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
	want := []string{"categories", "device_id", "device_name", "schema", "settings", "transactions", "written_at_ms"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("snapshot keys = %v, want %v", got, want)
	}

	var row map[string]any
	var txs []map[string]any
	if err := json.Unmarshal(top["transactions"], &txs); err != nil {
		t.Fatal(err)
	}
	row = txs[0]
	for _, k := range []string{"id", "kind", "amount_minor", "category_id", "note",
		"occurred_at", "source", "created_at_ms", "updated_at_ms", "deleted_at_ms"} {
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
	for _, k := range []string{"id", "currency", "language", "updated_at_ms"} {
		if _, ok := settings[k]; !ok {
			t.Fatalf("settings JSON missing %q: %v", k, settings)
		}
	}
	if settings["language"] != "uz" {
		t.Fatalf("settings.language = %v, want uz", settings["language"])
	}
}

func TestParseSnapshotRejectsForeignSchema(t *testing.T) {
	if _, err := ParseSnapshot([]byte(`{"schema":2,"device_id":"x"}`)); err == nil {
		t.Fatal("schema 2 was accepted")
	}
	if _, err := ParseSnapshot([]byte(`not json`)); err == nil {
		t.Fatal("garbage was accepted")
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
