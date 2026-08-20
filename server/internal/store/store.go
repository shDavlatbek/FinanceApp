// Package store implements the SQLite persistence layer (modernc.org/sqlite,
// no CGO): schema migration, seed data, strict last-write-wins merge, the
// full-state dump the Drive snapshot is built from, the local-only `dirty`
// flag, summaries, the bot alias table and a key/value meta table used for
// Drive sync bookkeeping. See docs/ARCHITECTURE.md.
package store

import (
	"database/sql"
	"errors"
	"fmt"
	"sync"
	"time"

	_ "modernc.org/sqlite"

	"github.com/xensa/tally/internal/model"
)

// SeedUpdatedAtMs is the fixed updated_at_ms of all seed categories
// (contract). Both peers seed byte-identical category rows, so a tie under
// strict LWW is exactly right: nothing needs to propagate.
const SeedUpdatedAtMs = 1755000000000

// SettingsUnsetMs is the updated_at_ms the settings singleton is seeded with:
// "nobody has chosen anything yet".
//
// It is deliberately NOT SeedUpdatedAtMs. The settings row is the one seeded
// row whose contents differ between peers — the server seeds it from
// DEFAULT_CURRENCY while the app seeds USD — and under the contract's strict
// LWW ("ties keep the local row") two identical timestamps would freeze the
// row on both sides forever: a server on UZS (exponent 0) storing a typed
// "250" as 250 minor units while the app renders it as $2.50, a silent 100x
// divergence that no amount of syncing could ever repair.
//
// 0 loses to every real value in either direction, so the first genuine
// choice from either peer wins. It is also below the snapshot validator's
// `updated_at_ms > 0` bar, so a peer never even sees a placeholder row.
const SettingsUnsetMs = 0

// Meta keys used by the Drive sync engine (local only, never synced).
const (
	MetaDeviceID   = "device_id"
	MetaDeviceName = "device_name"
	MetaFolderID   = "drive_folder_id"
	MetaPeerMD5    = "drive_peer_md5"
	MetaOwnFileID  = "drive_own_file_id"
	MetaLastSyncMs = "last_sync_ms"
	// MetaDefaultCurrency records the DEFAULT_CURRENCY the operator last
	// configured, so a change to it can be told apart from a currency the user
	// picked in the app.
	MetaDefaultCurrency = "default_currency_env"
)

// ErrNotFound is returned by lookups that match no row.
var ErrNotFound = errors.New("not found")

// SeedCategories are the FIXED-UUID categories both app and server seed on
// first run so they merge cleanly on first sync (contract).
var SeedCategories = []model.Category{
	{ID: "c1a7e2f0-0001-4a00-9000-000000000001", Name: "Groceries", Emoji: "🛒", Color: "#4CAF7D", Kind: model.KindExpense, SortOrder: 0, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0002-4a00-9000-000000000002", Name: "Cafe", Emoji: "☕", Color: "#E8935A", Kind: model.KindExpense, SortOrder: 1, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0003-4a00-9000-000000000003", Name: "Transport", Emoji: "🚕", Color: "#5A9BE8", Kind: model.KindExpense, SortOrder: 2, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0004-4a00-9000-000000000004", Name: "Home", Emoji: "🏠", Color: "#9B7DE8", Kind: model.KindExpense, SortOrder: 3, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0005-4a00-9000-000000000005", Name: "Utilities", Emoji: "💡", Color: "#E8C95A", Kind: model.KindExpense, SortOrder: 4, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0006-4a00-9000-000000000006", Name: "Health", Emoji: "💊", Color: "#E85A7A", Kind: model.KindExpense, SortOrder: 5, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0007-4a00-9000-000000000007", Name: "Shopping", Emoji: "🛍️", Color: "#D45AE8", Kind: model.KindExpense, SortOrder: 6, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0008-4a00-9000-000000000008", Name: "Fun", Emoji: "🎮", Color: "#5AE8D4", Kind: model.KindExpense, SortOrder: 7, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0009-4a00-9000-000000000009", Name: "Subscriptions", Emoji: "📱", Color: "#7A8BE8", Kind: model.KindExpense, SortOrder: 8, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-000a-4a00-9000-00000000000a", Name: "Travel", Emoji: "✈️", Color: "#5AC8E8", Kind: model.KindExpense, SortOrder: 9, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-000b-4a00-9000-00000000000b", Name: "Other", Emoji: "📦", Color: "#8E8E93", Kind: model.KindExpense, SortOrder: 10, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0101-4a00-9000-000000000101", Name: "Salary", Emoji: "💼", Color: "#4CAF7D", Kind: model.KindIncome, SortOrder: 0, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0102-4a00-9000-000000000102", Name: "Freelance", Emoji: "💻", Color: "#5A9BE8", Kind: model.KindIncome, SortOrder: 1, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0103-4a00-9000-000000000103", Name: "Gifts", Emoji: "🎁", Color: "#E8935A", Kind: model.KindIncome, SortOrder: 2, UpdatedAtMs: SeedUpdatedAtMs},
	{ID: "c1a7e2f0-0104-4a00-9000-000000000104", Name: "Other income", Emoji: "➕", Color: "#8E8E93", Kind: model.KindIncome, SortOrder: 3, UpdatedAtMs: SeedUpdatedAtMs},
}

// seedNames indexes SeedCategories by id for the display-name rule below.
var seedNames = func() map[string]string {
	m := make(map[string]string, len(SeedCategories))
	for _, c := range SeedCategories {
		m[c.ID] = c.Name
	}
	return m
}()

// SeedCategoryName returns the canonical English name of a seed category id.
func SeedCategoryName(id string) (string, bool) {
	n, ok := seedNames[id]
	return n, ok
}

// IsUnrenamedSeed implements the contract's seed-name localization rule: a
// seed category is localized for display ONLY while its stored name is still
// the canonical English one. Once the user renames it, the literal new name
// shows verbatim in every language.
//
//	displayName(c) = IsUnrenamedSeed(c) ? localized(c.ID) : c.Name
func IsUnrenamedSeed(c model.Category) bool {
	canonical, ok := seedNames[c.ID]
	return ok && c.Name == canonical
}

// Store wraps the SQLite database.
type Store struct {
	db *sql.DB

	hookMu    sync.RWMutex
	writeHook func()
}

// Open opens (creating if needed) the database at path, migrates the schema
// and seeds the fixed categories and the settings row on an empty DB.
func Open(path, defaultCurrency string) (*Store, error) {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}
	// A single connection serializes writers (SQLite allows one writer) and
	// makes the PRAGMAs below stick for the whole lifetime.
	db.SetMaxOpenConns(1)
	for _, pragma := range []string{
		"PRAGMA journal_mode=WAL",
		"PRAGMA busy_timeout=5000",
		"PRAGMA foreign_keys=ON",
	} {
		if _, err := db.Exec(pragma); err != nil {
			db.Close()
			return nil, fmt.Errorf("%s: %w", pragma, err)
		}
	}
	s := &Store{db: db}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, err
	}
	if err := s.seed(defaultCurrency); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

// Close closes the underlying database.
func (s *Store) Close() error { return s.db.Close() }

// SetWriteHook installs a callback fired after every successful *local* write
// (bot inserts, undo, settings changes). The Drive sync engine uses it to
// schedule its 3 s-debounced publish. It is never fired for merges of remote
// rows, which would otherwise ping-pong between peers.
func (s *Store) SetWriteHook(fn func()) {
	s.hookMu.Lock()
	s.writeHook = fn
	s.hookMu.Unlock()
}

func (s *Store) fireWriteHook() {
	s.hookMu.RLock()
	fn := s.writeHook
	s.hookMu.RUnlock()
	if fn != nil {
		fn()
	}
}

func (s *Store) migrate() error {
	const schema = `
CREATE TABLE IF NOT EXISTS meta (
	k TEXT PRIMARY KEY,
	v TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS categories (
	id            TEXT PRIMARY KEY,
	name          TEXT NOT NULL,
	emoji         TEXT NOT NULL,
	color         TEXT NOT NULL,
	kind          TEXT NOT NULL CHECK (kind IN ('income','expense')),
	sort_order    INTEGER NOT NULL,
	updated_at_ms INTEGER NOT NULL,
	deleted_at_ms INTEGER,
	server_seq    INTEGER NOT NULL,
	dirty         INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_categories_server_seq ON categories(server_seq);
CREATE TABLE IF NOT EXISTS transactions (
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
);
CREATE INDEX IF NOT EXISTS idx_transactions_server_seq ON transactions(server_seq);
CREATE INDEX IF NOT EXISTS idx_transactions_occurred_at ON transactions(occurred_at);
CREATE TABLE IF NOT EXISTS settings (
	id            TEXT PRIMARY KEY,
	currency      TEXT NOT NULL,
	language      TEXT NOT NULL DEFAULT '',
	updated_at_ms INTEGER NOT NULL,
	server_seq    INTEGER NOT NULL,
	dirty         INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS aliases (
	word        TEXT PRIMARY KEY,
	category_id TEXT NOT NULL
);
INSERT INTO meta (k, v) VALUES ('last_seq', '0') ON CONFLICT(k) DO NOTHING;
`
	if _, err := s.db.Exec(schema); err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	// v1 → v2 upgrades: add the columns CREATE TABLE IF NOT EXISTS skipped on
	// a pre-existing database. Snapshots are full dumps, so the initial
	// dirty=0 costs nothing: the first Drive publish uploads everything.
	for _, col := range []struct{ table, name, ddl string }{
		{"settings", "language", "ALTER TABLE settings ADD COLUMN language TEXT NOT NULL DEFAULT ''"},
		{"categories", "dirty", "ALTER TABLE categories ADD COLUMN dirty INTEGER NOT NULL DEFAULT 0"},
		{"transactions", "dirty", "ALTER TABLE transactions ADD COLUMN dirty INTEGER NOT NULL DEFAULT 0"},
		{"settings", "dirty", "ALTER TABLE settings ADD COLUMN dirty INTEGER NOT NULL DEFAULT 0"},
	} {
		has, err := s.hasColumn(col.table, col.name)
		if err != nil {
			return err
		}
		if !has {
			if _, err := s.db.Exec(col.ddl); err != nil {
				return fmt.Errorf("migrate %s.%s: %w", col.table, col.name, err)
			}
		}
	}
	// Unstick a settings row still carrying the old seed timestamp. Earlier
	// builds seeded the singleton at SeedUpdatedAtMs — the very value the app
	// seeds — so under strict LWW ("ties keep the local row") it could never
	// move in either direction. Only the untouched placeholder matches: any
	// real edit, on either peer, carries a wall-clock timestamp.
	if _, err := s.db.Exec(
		`UPDATE settings SET updated_at_ms = ? WHERE id = ? AND updated_at_ms = ?`,
		int64(SettingsUnsetMs), model.SettingsID, int64(SeedUpdatedAtMs)); err != nil {
		return fmt.Errorf("migrate settings placeholder: %w", err)
	}
	return nil
}

func (s *Store) hasColumn(table, column string) (bool, error) {
	rows, err := s.db.Query(`SELECT name FROM pragma_table_info(?)`, table)
	if err != nil {
		return false, fmt.Errorf("table_info %s: %w", table, err)
	}
	defer rows.Close()
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return false, err
		}
		if name == column {
			return true, rows.Err()
		}
	}
	return false, rows.Err()
}

func (s *Store) seed(defaultCurrency string) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var n int
	if err := tx.QueryRow(`SELECT COUNT(*) FROM categories`).Scan(&n); err != nil {
		return err
	}
	if n == 0 {
		for _, c := range SeedCategories {
			seq, err := nextSeq(tx)
			if err != nil {
				return err
			}
			if _, err := tx.Exec(
				`INSERT INTO categories (id, name, emoji, color, kind, sort_order, updated_at_ms, deleted_at_ms, server_seq, dirty)
				 VALUES (?,?,?,?,?,?,?,NULL,?,0)`,
				c.ID, c.Name, c.Emoji, c.Color, c.Kind, c.SortOrder, c.UpdatedAtMs, seq,
			); err != nil {
				return err
			}
		}
	}
	if err := tx.QueryRow(`SELECT COUNT(*) FROM settings`).Scan(&n); err != nil {
		return err
	}
	if n == 0 {
		seq, err := nextSeq(tx)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(
			`INSERT INTO settings (id, currency, language, updated_at_ms, server_seq, dirty) VALUES (?,?,'',?,?,0)`,
			model.SettingsID, defaultCurrency, int64(SettingsUnsetMs), seq,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// nextSeq increments and returns the global last_seq inside tx, so the seq
// bump is atomic with the write that consumes it. server_seq is purely local
// bookkeeping now (it orders rows and breaks ties in LastTransaction); the
// peer-visible contract is the Drive snapshot.
func nextSeq(tx *sql.Tx) (int64, error) {
	var seq int64
	if err := tx.QueryRow(`SELECT CAST(v AS INTEGER) FROM meta WHERE k = 'last_seq'`).Scan(&seq); err != nil {
		return 0, fmt.Errorf("read last_seq: %w", err)
	}
	seq++
	if _, err := tx.Exec(`UPDATE meta SET v = ? WHERE k = 'last_seq'`, seq); err != nil {
		return 0, fmt.Errorf("bump last_seq: %w", err)
	}
	return seq, nil
}

// CurrentSeq returns the current global last_seq.
func (s *Store) CurrentSeq() (int64, error) {
	var seq int64
	err := s.db.QueryRow(`SELECT CAST(v AS INTEGER) FROM meta WHERE k = 'last_seq'`).Scan(&seq)
	return seq, err
}

// ---------------------------------------------------------------------------
// meta key/value (Drive sync bookkeeping)
// ---------------------------------------------------------------------------

// Meta reads a meta value. Missing keys return ("", false, nil).
func (s *Store) Meta(key string) (string, bool, error) {
	var v string
	err := s.db.QueryRow(`SELECT v FROM meta WHERE k = ?`, key).Scan(&v)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return v, true, nil
}

// MetaOr reads a meta value, returning def when the key is absent.
func (s *Store) MetaOr(key, def string) (string, error) {
	v, ok, err := s.Meta(key)
	if err != nil || !ok {
		return def, err
	}
	return v, nil
}

// SetMeta writes (or replaces) a meta value.
func (s *Store) SetMeta(key, value string) error {
	_, err := s.db.Exec(
		`INSERT INTO meta (k, v) VALUES (?, ?) ON CONFLICT(k) DO UPDATE SET v = excluded.v`,
		key, value)
	return err
}

// ---------------------------------------------------------------------------
// merge (remote → local) and full-state dump (local → snapshot)
// ---------------------------------------------------------------------------

// Batch is a set of rows arriving from a peer's Drive snapshot. Several
// settings rows may be present (one per peer file); LWW picks the newest.
type Batch struct {
	Categories   []model.Category
	Transactions []model.Transaction
	Settings     []model.Settings
}

// Empty reports whether the batch carries no rows at all.
func (b Batch) Empty() bool {
	return len(b.Categories) == 0 && len(b.Transactions) == 0 && len(b.Settings) == 0
}

// Snapshot is a complete dump of this peer's local state, tombstones
// included — exactly what gets serialized into the peer's Drive file.
type Snapshot struct {
	Categories   []model.Category
	Transactions []model.Transaction
	Settings     model.Settings
}

// MergeRemote applies a batch of peer rows in ONE transaction using strict
// last-write-wins: an incoming row is applied iff it does not exist locally
// OR incoming.updated_at_ms > local.updated_at_ms (ties keep the local row).
// Merged rows are written with dirty = 0 — they came from a peer, so this
// peer has nothing new to publish about them. Returns the number of rows
// actually applied.
func (s *Store) MergeRemote(b Batch) (int, error) {
	tx, err := s.db.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	applied := 0
	for _, c := range b.Categories {
		n, err := applyCategory(tx, c, false)
		if err != nil {
			return 0, err
		}
		applied += n
	}
	for _, t := range b.Transactions {
		n, err := applyTransaction(tx, t, false)
		if err != nil {
			return 0, err
		}
		applied += n
	}
	for _, st := range b.Settings {
		n, err := applySettings(tx, st, false)
		if err != nil {
			return 0, err
		}
		applied += n
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return applied, nil
}

// FullState returns every row this peer holds, tombstones included, plus the
// singleton settings row. It is the source of the Drive snapshot.
func (s *Store) FullState() (Snapshot, error) {
	var snap Snapshot
	snap.Categories = []model.Category{}
	snap.Transactions = []model.Transaction{}

	tx, err := s.db.Begin()
	if err != nil {
		return snap, err
	}
	defer tx.Rollback()

	rows, err := tx.Query(
		`SELECT id, name, emoji, color, kind, sort_order, updated_at_ms, deleted_at_ms
		 FROM categories ORDER BY kind, sort_order, id`)
	if err != nil {
		return snap, err
	}
	for rows.Next() {
		var c model.Category
		var del sql.NullInt64
		if err := rows.Scan(&c.ID, &c.Name, &c.Emoji, &c.Color, &c.Kind, &c.SortOrder, &c.UpdatedAtMs, &del); err != nil {
			rows.Close()
			return snap, err
		}
		if del.Valid {
			c.DeletedAtMs = &del.Int64
		}
		snap.Categories = append(snap.Categories, c)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return snap, err
	}

	trows, err := tx.Query(
		`SELECT id, kind, amount_minor, category_id, note, occurred_at, source, created_at_ms, updated_at_ms, deleted_at_ms
		 FROM transactions ORDER BY occurred_at, id`)
	if err != nil {
		return snap, err
	}
	for trows.Next() {
		var t model.Transaction
		var del sql.NullInt64
		if err := trows.Scan(&t.ID, &t.Kind, &t.AmountMinor, &t.CategoryID, &t.Note, &t.OccurredAt,
			&t.Source, &t.CreatedAtMs, &t.UpdatedAtMs, &del); err != nil {
			trows.Close()
			return snap, err
		}
		if del.Valid {
			t.DeletedAtMs = &del.Int64
		}
		snap.Transactions = append(snap.Transactions, t)
	}
	trows.Close()
	if err := trows.Err(); err != nil {
		return snap, err
	}

	err = tx.QueryRow(`SELECT id, currency, language, updated_at_ms FROM settings WHERE id = ?`, model.SettingsID).
		Scan(&snap.Settings.ID, &snap.Settings.Currency, &snap.Settings.Language, &snap.Settings.UpdatedAtMs)
	if err != nil {
		return snap, err
	}
	return snap, tx.Commit()
}

// HasDirty reports whether any local row still needs publishing.
func (s *Store) HasDirty() (bool, error) {
	var n int
	err := s.db.QueryRow(`
		SELECT (SELECT COUNT(*) FROM categories   WHERE dirty = 1)
		     + (SELECT COUNT(*) FROM transactions WHERE dirty = 1)
		     + (SELECT COUNT(*) FROM settings     WHERE dirty = 1)`).Scan(&n)
	return n > 0, err
}

// ClearDirty clears the dirty flag on exactly the rows that were serialized
// into snap AND whose updated_at_ms is still what it was then. Rows edited
// while the upload was in flight keep dirty = 1 and go out on the next pass.
func (s *Store) ClearDirty(snap Snapshot) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	for _, c := range snap.Categories {
		if _, err := tx.Exec(
			`UPDATE categories SET dirty = 0 WHERE id = ? AND updated_at_ms = ?`, c.ID, c.UpdatedAtMs); err != nil {
			return err
		}
	}
	for _, t := range snap.Transactions {
		if _, err := tx.Exec(
			`UPDATE transactions SET dirty = 0 WHERE id = ? AND updated_at_ms = ?`, t.ID, t.UpdatedAtMs); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(
		`UPDATE settings SET dirty = 0 WHERE id = ? AND updated_at_ms = ?`,
		snap.Settings.ID, snap.Settings.UpdatedAtMs); err != nil {
		return err
	}
	return tx.Commit()
}

// wins reports whether an incoming row with incomingMs should replace the
// existing row (or be inserted). It returns (apply, isInsert).
func wins(tx *sql.Tx, table, id string, incomingMs int64) (bool, bool, error) {
	var existingMs int64
	err := tx.QueryRow(`SELECT updated_at_ms FROM `+table+` WHERE id = ?`, id).Scan(&existingMs)
	if errors.Is(err, sql.ErrNoRows) {
		return true, true, nil
	}
	if err != nil {
		return false, false, err
	}
	return incomingMs > existingMs, false, nil
}

func dirtyInt(dirty bool) int {
	if dirty {
		return 1
	}
	return 0
}

func applyCategory(tx *sql.Tx, c model.Category, dirty bool) (int, error) {
	apply, insert, err := wins(tx, "categories", c.ID, c.UpdatedAtMs)
	if err != nil || !apply {
		return 0, err
	}
	seq, err := nextSeq(tx)
	if err != nil {
		return 0, err
	}
	d := dirtyInt(dirty)
	if insert {
		_, err = tx.Exec(
			`INSERT INTO categories (id, name, emoji, color, kind, sort_order, updated_at_ms, deleted_at_ms, server_seq, dirty)
			 VALUES (?,?,?,?,?,?,?,?,?,?)`,
			c.ID, c.Name, c.Emoji, c.Color, c.Kind, c.SortOrder, c.UpdatedAtMs, c.DeletedAtMs, seq, d)
	} else {
		_, err = tx.Exec(
			`UPDATE categories SET name=?, emoji=?, color=?, kind=?, sort_order=?, updated_at_ms=?, deleted_at_ms=?, server_seq=?, dirty=?
			 WHERE id=?`,
			c.Name, c.Emoji, c.Color, c.Kind, c.SortOrder, c.UpdatedAtMs, c.DeletedAtMs, seq, d, c.ID)
	}
	if err != nil {
		return 0, err
	}
	return 1, nil
}

func applyTransaction(tx *sql.Tx, t model.Transaction, dirty bool) (int, error) {
	apply, insert, err := wins(tx, "transactions", t.ID, t.UpdatedAtMs)
	if err != nil || !apply {
		return 0, err
	}
	seq, err := nextSeq(tx)
	if err != nil {
		return 0, err
	}
	d := dirtyInt(dirty)
	if insert {
		_, err = tx.Exec(
			`INSERT INTO transactions (id, kind, amount_minor, category_id, note, occurred_at, source, created_at_ms, updated_at_ms, deleted_at_ms, server_seq, dirty)
			 VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`,
			t.ID, t.Kind, t.AmountMinor, t.CategoryID, t.Note, t.OccurredAt, t.Source, t.CreatedAtMs, t.UpdatedAtMs, t.DeletedAtMs, seq, d)
	} else {
		_, err = tx.Exec(
			`UPDATE transactions SET kind=?, amount_minor=?, category_id=?, note=?, occurred_at=?, source=?, created_at_ms=?, updated_at_ms=?, deleted_at_ms=?, server_seq=?, dirty=?
			 WHERE id=?`,
			t.Kind, t.AmountMinor, t.CategoryID, t.Note, t.OccurredAt, t.Source, t.CreatedAtMs, t.UpdatedAtMs, t.DeletedAtMs, seq, d, t.ID)
	}
	if err != nil {
		return 0, err
	}
	return 1, nil
}

func applySettings(tx *sql.Tx, st model.Settings, dirty bool) (int, error) {
	st.ID = model.SettingsID
	apply, insert, err := wins(tx, "settings", st.ID, st.UpdatedAtMs)
	if err != nil || !apply {
		return 0, err
	}
	seq, err := nextSeq(tx)
	if err != nil {
		return 0, err
	}
	d := dirtyInt(dirty)
	if insert {
		_, err = tx.Exec(`INSERT INTO settings (id, currency, language, updated_at_ms, server_seq, dirty) VALUES (?,?,?,?,?,?)`,
			st.ID, st.Currency, st.Language, st.UpdatedAtMs, seq, d)
	} else {
		_, err = tx.Exec(`UPDATE settings SET currency=?, language=?, updated_at_ms=?, server_seq=?, dirty=? WHERE id=?`,
			st.Currency, st.Language, st.UpdatedAtMs, seq, d, st.ID)
	}
	if err != nil {
		return 0, err
	}
	return 1, nil
}

// ---------------------------------------------------------------------------
// local writes (bot) — these mark rows dirty and fire the write hook
// ---------------------------------------------------------------------------

// InsertTransaction inserts a bot/server-originated transaction through the
// LWW path, marking it dirty so the next Drive pass publishes it.
func (s *Store) InsertTransaction(t model.Transaction) error {
	return s.applyLocal(func(tx *sql.Tx) error {
		_, err := applyTransaction(tx, t, true)
		return err
	})
}

// InsertCategory inserts a new category through the LWW path (dirty).
func (s *Store) InsertCategory(c model.Category) error {
	return s.applyLocal(func(tx *sql.Tx) error {
		_, err := applyCategory(tx, c, true)
		return err
	})
}

// SetSettings writes the singleton settings row locally (dirty), through the
// same LWW guard so a stale write cannot clobber a newer peer value.
func (s *Store) SetSettings(st model.Settings) error {
	return s.applyLocal(func(tx *sql.Tx) error {
		_, err := applySettings(tx, st, true)
		return err
	})
}

// ApplyDefaultCurrency reconciles the operator's DEFAULT_CURRENCY with the
// synced settings row, and reports whether it wrote anything.
//
// Without it DEFAULT_CURRENCY is applied only by seed(), i.e. only on an empty
// database, so editing it in .env and restarting is a silent no-op forever
// after first boot — the bot keeps parsing and rendering amounts with the old
// currency's exponent and symbol, and nothing says so.
//
// The last configured value is remembered in meta, so:
//
//   - a value the operator has just set or changed is applied at
//     time.Now(), which under LWW also propagates it to the phone;
//   - an unchanged value is left alone, so a currency the user later picks in
//     the app is not clobbered on every restart by a stale .env line.
//
// currency must already be validated; callers pass "" when the operator set
// no DEFAULT_CURRENCY at all, which is always a no-op.
func (s *Store) ApplyDefaultCurrency(currency string, nowMs int64) (bool, error) {
	if currency == "" {
		return false, nil
	}
	previous, err := s.MetaOr(MetaDefaultCurrency, "")
	if err != nil {
		return false, err
	}
	if previous == currency {
		return false, nil
	}
	current, err := s.Settings()
	if err != nil {
		return false, err
	}
	wrote := false
	if current.Currency != currency {
		if nowMs <= current.UpdatedAtMs {
			// A peer's clock ran ahead of ours; the operator's explicit
			// configuration must still win the LWW comparison.
			nowMs = current.UpdatedAtMs + 1
		}
		current.Currency = currency
		current.UpdatedAtMs = nowMs
		if err := s.SetSettings(current); err != nil {
			return false, err
		}
		wrote = true
	}
	return wrote, s.SetMeta(MetaDefaultCurrency, currency)
}

// SoftDeleteTransaction tombstones a transaction (bumps updated_at_ms and
// marks it dirty so the tombstone reaches the peers).
func (s *Store) SoftDeleteTransaction(id string, nowMs int64) error {
	err := s.applyLocal(func(tx *sql.Tx) error {
		seq, err := nextSeq(tx)
		if err != nil {
			return err
		}
		res, err := tx.Exec(
			`UPDATE transactions SET deleted_at_ms = ?, updated_at_ms = ?, server_seq = ?, dirty = 1 WHERE id = ?`,
			nowMs, nowMs, seq, id)
		if err != nil {
			return err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			return ErrNotFound
		}
		return nil
	})
	return err
}

func (s *Store) applyLocal(fn func(*sql.Tx) error) error {
	tx, err := s.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err := fn(tx); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return err
	}
	s.fireWriteHook()
	return nil
}

// ---------------------------------------------------------------------------
// queries
// ---------------------------------------------------------------------------

// Settings returns the singleton settings row.
func (s *Store) Settings() (model.Settings, error) {
	var st model.Settings
	err := s.db.QueryRow(`SELECT id, currency, language, updated_at_ms FROM settings WHERE id = ?`, model.SettingsID).
		Scan(&st.ID, &st.Currency, &st.Language, &st.UpdatedAtMs)
	if errors.Is(err, sql.ErrNoRows) {
		return st, ErrNotFound
	}
	return st, err
}

// ListCategories returns non-deleted categories, optionally filtered by
// kind (empty kind = all), ordered by kind then sort_order.
func (s *Store) ListCategories(kind string) ([]model.Category, error) {
	q := `SELECT id, name, emoji, color, kind, sort_order, updated_at_ms, deleted_at_ms
	      FROM categories WHERE deleted_at_ms IS NULL`
	args := []any{}
	if kind != "" {
		q += ` AND kind = ?`
		args = append(args, kind)
	}
	// 'expense' < 'income' alphabetically, so ASC lists expenses first.
	q += ` ORDER BY kind ASC, sort_order, name`
	rows, err := s.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []model.Category
	for rows.Next() {
		var c model.Category
		var del sql.NullInt64
		if err := rows.Scan(&c.ID, &c.Name, &c.Emoji, &c.Color, &c.Kind, &c.SortOrder, &c.UpdatedAtMs, &del); err != nil {
			return nil, err
		}
		if del.Valid {
			c.DeletedAtMs = &del.Int64
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

// GetCategory returns a category by id (deleted or not).
func (s *Store) GetCategory(id string) (model.Category, error) {
	var c model.Category
	var del sql.NullInt64
	err := s.db.QueryRow(
		`SELECT id, name, emoji, color, kind, sort_order, updated_at_ms, deleted_at_ms FROM categories WHERE id = ?`, id).
		Scan(&c.ID, &c.Name, &c.Emoji, &c.Color, &c.Kind, &c.SortOrder, &c.UpdatedAtMs, &del)
	if errors.Is(err, sql.ErrNoRows) {
		return c, ErrNotFound
	}
	if del.Valid {
		c.DeletedAtMs = &del.Int64
	}
	return c, err
}

// MaxSortOrder returns the max sort_order among non-deleted categories of a kind.
func (s *Store) MaxSortOrder(kind string) (int, error) {
	var n sql.NullInt64
	err := s.db.QueryRow(`SELECT MAX(sort_order) FROM categories WHERE deleted_at_ms IS NULL AND kind = ?`, kind).Scan(&n)
	if err != nil {
		return 0, err
	}
	return int(n.Int64), nil
}

// CategoryTotal describes one category's total within a period.
type CategoryTotal struct {
	Category model.Category
	Total    int64
}

// Summary holds aggregates for a period.
type Summary struct {
	Income      int64
	Expenses    int64
	Count       int64           // non-deleted transactions in the period
	TopExpenses []CategoryTotal // top-5 expense categories by amount, desc
}

// PeriodSummary aggregates non-deleted transactions with
// from <= occurred_at < to (RFC3339 UTC strings).
func (s *Store) PeriodSummary(from, to time.Time) (Summary, error) {
	var sum Summary
	fromS, toS := isoUTC(from), isoUTC(to)
	err := s.db.QueryRow(
		`SELECT
			COALESCE(SUM(CASE WHEN kind = 'income' THEN amount_minor ELSE 0 END), 0),
			COALESCE(SUM(CASE WHEN kind = 'expense' THEN amount_minor ELSE 0 END), 0),
			COUNT(*)
		 FROM transactions
		 WHERE deleted_at_ms IS NULL AND occurred_at >= ? AND occurred_at < ?`,
		fromS, toS).Scan(&sum.Income, &sum.Expenses, &sum.Count)
	if err != nil {
		return sum, err
	}
	rows, err := s.db.Query(
		`SELECT c.id, c.name, c.emoji, c.color, c.kind, c.sort_order, c.updated_at_ms, SUM(t.amount_minor) AS total
		 FROM transactions t
		 JOIN categories c ON c.id = t.category_id
		 WHERE t.deleted_at_ms IS NULL AND t.kind = 'expense'
		   AND t.occurred_at >= ? AND t.occurred_at < ?
		 GROUP BY c.id
		 ORDER BY total DESC
		 LIMIT 5`, fromS, toS)
	if err != nil {
		return sum, err
	}
	defer rows.Close()
	for rows.Next() {
		var ct CategoryTotal
		if err := rows.Scan(&ct.Category.ID, &ct.Category.Name, &ct.Category.Emoji, &ct.Category.Color,
			&ct.Category.Kind, &ct.Category.SortOrder, &ct.Category.UpdatedAtMs, &ct.Total); err != nil {
			return sum, err
		}
		sum.TopExpenses = append(sum.TopExpenses, ct)
	}
	return sum, rows.Err()
}

// CategoryPeriodTotal sums non-deleted transactions of one category with
// from <= occurred_at < to.
func (s *Store) CategoryPeriodTotal(categoryID string, from, to time.Time) (int64, error) {
	var total int64
	err := s.db.QueryRow(
		`SELECT COALESCE(SUM(amount_minor), 0) FROM transactions
		 WHERE deleted_at_ms IS NULL AND category_id = ? AND occurred_at >= ? AND occurred_at < ?`,
		categoryID, isoUTC(from), isoUTC(to)).Scan(&total)
	return total, err
}

// LastTransaction returns the most recent non-deleted transaction (any
// source), by created_at_ms then server_seq.
func (s *Store) LastTransaction() (model.Transaction, error) {
	var t model.Transaction
	var del sql.NullInt64
	err := s.db.QueryRow(
		`SELECT id, kind, amount_minor, category_id, note, occurred_at, source, created_at_ms, updated_at_ms, deleted_at_ms
		 FROM transactions WHERE deleted_at_ms IS NULL
		 ORDER BY created_at_ms DESC, server_seq DESC LIMIT 1`).
		Scan(&t.ID, &t.Kind, &t.AmountMinor, &t.CategoryID, &t.Note, &t.OccurredAt, &t.Source, &t.CreatedAtMs, &t.UpdatedAtMs, &del)
	if errors.Is(err, sql.ErrNoRows) {
		return t, ErrNotFound
	}
	if del.Valid {
		t.DeletedAtMs = &del.Int64
	}
	return t, err
}

// GetAlias resolves a lowercase word to a category id.
func (s *Store) GetAlias(word string) (string, bool, error) {
	var id string
	err := s.db.QueryRow(`SELECT category_id FROM aliases WHERE word = ?`, word).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return "", false, nil
	}
	if err != nil {
		return "", false, err
	}
	return id, true, nil
}

// SetAlias stores (or replaces) word → category id. Aliases are bot-local
// learning state and are never synced.
func (s *Store) SetAlias(word, categoryID string) error {
	_, err := s.db.Exec(
		`INSERT INTO aliases (word, category_id) VALUES (?, ?)
		 ON CONFLICT(word) DO UPDATE SET category_id = excluded.category_id`,
		word, categoryID)
	return err
}

// isoUTC formats t as the canonical RFC3339 UTC string used in occurred_at.
func isoUTC(t time.Time) string {
	return t.UTC().Format(model.CanonicalUTC)
}
