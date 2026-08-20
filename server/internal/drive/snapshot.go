package drive

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/xensa/tally/internal/model"
	"github.com/xensa/tally/internal/store"
)

// SnapshotSchema is the version stamped into every snapshot file.
const SnapshotSchema = 1

// FilePrefix / FileSuffix bracket a peer snapshot file name:
// tally-<device_id>.json.
const (
	FilePrefix = "tally-"
	FileSuffix = ".json"
	FileMime   = "application/json"
)

// Snapshot is the exact JSON shape stored in each peer's Drive file
// (docs/ARCHITECTURE.md). It is a FULL dump of that peer's local state,
// tombstones included, which is what makes the merge idempotent and
// self-healing.
type Snapshot struct {
	Schema       int                 `json:"schema"`
	DeviceID     string              `json:"device_id"`
	DeviceName   string              `json:"device_name"`
	WrittenAtMs  int64               `json:"written_at_ms"`
	Categories   []model.Category    `json:"categories"`
	Transactions []model.Transaction `json:"transactions"`
	Settings     model.Settings      `json:"settings"`
}

// FileName returns the snapshot file name for a device id.
func FileName(deviceID string) string { return FilePrefix + deviceID + FileSuffix }

// DeviceIDFromFileName extracts the device id from a snapshot file name.
func DeviceIDFromFileName(name string) (string, bool) {
	if !strings.HasPrefix(name, FilePrefix) || !strings.HasSuffix(name, FileSuffix) {
		return "", false
	}
	id := name[len(FilePrefix) : len(name)-len(FileSuffix)]
	if id == "" {
		return "", false
	}
	return id, true
}

// NewSnapshot builds a snapshot from a full local state dump.
func NewSnapshot(deviceID, deviceName string, writtenAtMs int64, s store.Snapshot) Snapshot {
	snap := Snapshot{
		Schema:       SnapshotSchema,
		DeviceID:     deviceID,
		DeviceName:   deviceName,
		WrittenAtMs:  writtenAtMs,
		Categories:   s.Categories,
		Transactions: s.Transactions,
		Settings:     s.Settings,
	}
	if snap.Categories == nil {
		snap.Categories = []model.Category{}
	}
	if snap.Transactions == nil {
		snap.Transactions = []model.Transaction{}
	}
	return snap
}

// Marshal serializes the snapshot. It is stored uncompressed and indented so
// the owner can read their own data straight out of the Drive UI.
func (s Snapshot) Marshal() ([]byte, error) {
	return json.MarshalIndent(s, "", "  ")
}

// ParseSnapshot decodes a peer snapshot file.
func ParseSnapshot(b []byte) (Snapshot, error) {
	var s Snapshot
	if err := json.Unmarshal(b, &s); err != nil {
		return s, fmt.Errorf("parse snapshot: %w", err)
	}
	if s.Schema != SnapshotSchema {
		return s, fmt.Errorf("parse snapshot: unsupported schema %d (want %d)", s.Schema, SnapshotSchema)
	}
	return s, nil
}

var (
	colorRe    = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)
	currencyRe = regexp.MustCompile(`^[A-Z]{3}$`)
)

// Batch converts a peer snapshot into a merge batch, dropping rows that
// would violate the local schema and normalizing occurred_at to the
// canonical UTC "Z" form the period queries string-compare against.
//
// A peer file is untrusted input: it may have been hand-edited in the Drive
// UI. One bad row must not abort the whole merge (the peer would be stuck
// forever), so bad rows are skipped and reported.
func (s Snapshot) Batch() (store.Batch, []string) {
	var b store.Batch
	var skipped []string

	for _, c := range s.Categories {
		switch {
		case c.ID == "":
			skipped = append(skipped, "category with empty id")
		case c.Name == "":
			skipped = append(skipped, "category "+c.ID+": empty name")
		case !colorRe.MatchString(c.Color):
			skipped = append(skipped, "category "+c.ID+": bad color "+c.Color)
		case c.Kind != model.KindIncome && c.Kind != model.KindExpense:
			skipped = append(skipped, "category "+c.ID+": bad kind "+c.Kind)
		case c.UpdatedAtMs <= 0:
			skipped = append(skipped, "category "+c.ID+": updated_at_ms must be > 0")
		default:
			b.Categories = append(b.Categories, c)
		}
	}

	for _, t := range s.Transactions {
		switch {
		case t.ID == "":
			skipped = append(skipped, "transaction with empty id")
			continue
		case t.Kind != model.KindIncome && t.Kind != model.KindExpense:
			skipped = append(skipped, "transaction "+t.ID+": bad kind "+t.Kind)
			continue
		case t.AmountMinor <= 0:
			skipped = append(skipped, fmt.Sprintf("transaction %s: amount_minor must be > 0, got %d", t.ID, t.AmountMinor))
			continue
		case t.CategoryID == "":
			skipped = append(skipped, "transaction "+t.ID+": empty category_id")
			continue
		case t.Source != model.SourceApp && t.Source != model.SourceTelegram:
			skipped = append(skipped, "transaction "+t.ID+": bad source "+t.Source)
			continue
		case t.UpdatedAtMs <= 0:
			skipped = append(skipped, "transaction "+t.ID+": updated_at_ms must be > 0")
			continue
		}
		ts, err := time.Parse(time.RFC3339, t.OccurredAt)
		if err != nil {
			skipped = append(skipped, "transaction "+t.ID+": occurred_at is not RFC3339: "+t.OccurredAt)
			continue
		}
		t.OccurredAt = ts.UTC().Format(model.CanonicalUTC)
		b.Transactions = append(b.Transactions, t)
	}

	st := s.Settings
	switch {
	case st.UpdatedAtMs <= 0:
		// A snapshot without settings simply carries none.
	case !currencyRe.MatchString(st.Currency):
		skipped = append(skipped, "settings: bad currency "+st.Currency)
	case !model.ValidLanguage(st.Language):
		skipped = append(skipped, "settings: bad language "+st.Language)
	default:
		st.ID = model.SettingsID
		b.Settings = append(b.Settings, st)
	}

	return b, skipped
}
