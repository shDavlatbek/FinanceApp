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

// SnapshotSchema is the version stamped into every snapshot file written by
// this build. Schema 2 added accounts, per-transaction account ids and the
// 'transfer' kind.
const SnapshotSchema = 2

// MinReadableSchema is the oldest snapshot this build still understands. A
// schema-1 file predates accounts: it carries no `accounts` array and its
// transactions have no account_id, so Batch books them to the default account
// exactly as the local migration does.
const MinReadableSchema = 1

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
	Accounts     []model.Account     `json:"accounts"`
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
		Accounts:     s.Accounts,
		Categories:   s.Categories,
		Transactions: s.Transactions,
		Settings:     s.Settings,
	}
	if snap.Accounts == nil {
		snap.Accounts = []model.Account{}
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
	if s.Schema < MinReadableSchema || s.Schema > SnapshotSchema {
		return s, fmt.Errorf("parse snapshot: unsupported schema %d (want %d..%d)",
			s.Schema, MinReadableSchema, SnapshotSchema)
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

	// Accounts a transaction may legally point at. A schema-1 peer sends none,
	// so the default account — seeded identically on every peer — stands in.
	known := map[string]bool{store.DefaultAccountID: true}

	for _, a := range s.Accounts {
		switch {
		case a.ID == "":
			skipped = append(skipped, "account with empty id")
		case a.Name == "":
			skipped = append(skipped, "account "+a.ID+": empty name")
		case !colorRe.MatchString(a.Color):
			skipped = append(skipped, "account "+a.ID+": bad color "+a.Color)
		case !model.ValidAccountKind(a.Kind):
			skipped = append(skipped, "account "+a.ID+": bad kind "+a.Kind)
		case a.UpdatedAtMs <= 0:
			skipped = append(skipped, "account "+a.ID+": updated_at_ms must be > 0")
		default:
			known[a.ID] = true
			b.Accounts = append(b.Accounts, a)
		}
	}

	for _, c := range s.Categories {
		switch {
		case c.ID == "":
			skipped = append(skipped, "category with empty id")
		case c.Name == "":
			skipped = append(skipped, "category "+c.ID+": empty name")
		case !colorRe.MatchString(c.Color):
			skipped = append(skipped, "category "+c.ID+": bad color "+c.Color)
		case !model.ValidCategoryKind(c.Kind):
			skipped = append(skipped, "category "+c.ID+": bad kind "+c.Kind)
		case c.UpdatedAtMs <= 0:
			skipped = append(skipped, "category "+c.ID+": updated_at_ms must be > 0")
		default:
			b.Categories = append(b.Categories, c)
		}
	}

	for _, t := range s.Transactions {
		// Structural checks first — the ones no rewrite below can affect.
		switch {
		case t.ID == "":
			skipped = append(skipped, "transaction with empty id")
			continue
		case !model.ValidTransactionKind(t.Kind):
			skipped = append(skipped, "transaction "+t.ID+": bad kind "+t.Kind)
			continue
		case t.AmountMinor <= 0:
			skipped = append(skipped, fmt.Sprintf("transaction %s: amount_minor must be > 0, got %d", t.ID, t.AmountMinor))
			continue
		case t.Source != model.SourceApp && t.Source != model.SourceTelegram:
			skipped = append(skipped, "transaction "+t.ID+": bad source "+t.Source)
			continue
		case t.UpdatedAtMs <= 0:
			skipped = append(skipped, "transaction "+t.ID+": updated_at_ms must be > 0")
			continue
		}

		// Resolve the source account BEFORE the transfer rules below.
		//
		// A schema-1 peer, or a hand-edit that dropped the field, leaves the
		// entry account-less. Booking it to the default account matches what the
		// local migration did to this peer's own pre-accounts rows, so both sides
		// agree without a round trip: losing an entry is worse than misfiling one.
		//
		// The ORDER is load-bearing. Rewriting after the self-transfer check
		// would let a transfer with an unknown source and a destination of cash
		// be rewritten into cash -> cash: precisely the row that check exists to
		// reject, waved through because the check had already run.
		if t.AccountID == "" || !known[t.AccountID] {
			if t.AccountID != "" {
				skipped = append(skipped, "transaction "+t.ID+": unknown account_id "+t.AccountID+", booked to the default account")
			}
			t.AccountID = store.DefaultAccountID
		}

		if t.Kind == model.KindTransfer {
			// A transfer never carries a category. Clearing a stray one keeps the
			// row — it is still a real movement of money — while stopping it from
			// reaching a category total, which is what the bot echoes after every
			// single entry.
			t.CategoryID = ""
			switch {
			case t.ToAccountID == "":
				skipped = append(skipped, "transaction "+t.ID+": transfer without to_account_id")
				continue
			case !known[t.ToAccountID]:
				skipped = append(skipped, "transaction "+t.ID+": transfer to unknown account "+t.ToAccountID)
				continue
			case t.ToAccountID == t.AccountID:
				// Nets to zero, yet still shows in history as money moving.
				skipped = append(skipped, "transaction "+t.ID+": transfer to the same account")
				continue
			}
		} else {
			// Only a transfer has a destination. A stray to_account_id elsewhere
			// is cleared rather than treated as fatal: the balance rule only reads
			// the field on a transfer, so the row is still perfectly good data,
			// and dropping a real expense over an ignored field is the worse bug.
			t.ToAccountID = ""
			if t.CategoryID == "" {
				skipped = append(skipped, "transaction "+t.ID+": empty category_id")
				continue
			}
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
		// An unknown default account is CLEARED, not a reason to drop the row.
		// Empty already means "unchanged" downstream, so the local choice
		// survives — whereas skipping would throw away this peer's currency and
		// language too, stranding the bot in the wrong language over an
		// unrelated bad account row.
		if st.DefaultAccountID != "" && !known[st.DefaultAccountID] {
			skipped = append(skipped, "settings: unknown default_account_id "+st.DefaultAccountID+", left unchanged")
			st.DefaultAccountID = ""
		}
		b.Settings = append(b.Settings, st)
	}

	return b, skipped
}
