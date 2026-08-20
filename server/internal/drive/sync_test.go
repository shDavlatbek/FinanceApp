package drive

import (
	"context"
	"net/http"
	"path/filepath"
	"testing"
	"time"

	"golang.org/x/oauth2"

	"github.com/xensa/tally/internal/model"
	"github.com/xensa/tally/internal/store"
)

// testToken is a stand-in for what `tally auth` would have written.
func testToken() *oauth2.Token {
	return &oauth2.Token{
		AccessToken:  "access",
		RefreshToken: "refresh",
		TokenType:    "Bearer",
		Expiry:       time.Now().Add(time.Hour),
	}
}

func testStore(t *testing.T) *store.Store {
	t.Helper()
	s, err := store.Open(filepath.Join(t.TempDir(), "tally.db"), "USD")
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

// newTestEngine wires an engine to the fake Drive, skipping the OAuth dance.
// The returned counter records how many times the engine built a client, so a
// test can assert that a rewritten token file forces a rebuild.
func newTestEngine(t *testing.T, st *store.Store, d *fakeDrive) (*Engine, *int) {
	t.Helper()
	e := NewEngine(st, Config{
		ClientID:     "id",
		ClientSecret: "secret",
		TokenPath:    filepath.Join(t.TempDir(), "token.json"),
		FolderName:   "Tally",
	})
	// Pretend `tally auth` already ran: write a token file so Sync's auth gate
	// passes, and build every client against the stub.
	if err := SaveToken(e.cfg.TokenPath, testToken()); err != nil {
		t.Fatal(err)
	}
	builds := 0
	e.newClient = func(ctx context.Context, _ oauth2.TokenSource) (*Client, error) {
		builds++
		return d.client(ctx, t), nil
	}
	return e, &builds
}

func TestSyncFirstPassCreatesFolderAndSnapshot(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)

	if err := e.Sync(ctx); err != nil {
		t.Fatalf("first sync: %v", err)
	}
	if got := e.State().Status; got != StatusIdle {
		t.Fatalf("status = %q, want idle", got)
	}
	if e.State().LastSyncMs == 0 {
		t.Fatal("last sync timestamp not recorded")
	}

	_, _, creates, updates, folders := d.counters()
	if folders != 1 {
		t.Fatalf("created %d folders, want 1", folders)
	}
	if creates != 1 || updates != 0 {
		t.Fatalf("uploads: %d create / %d update, want 1 / 0", creates, updates)
	}

	deviceID, _, err := e.identity()
	if err != nil {
		t.Fatal(err)
	}
	own := d.byName(FileName(deviceID))
	if own == nil {
		t.Fatalf("own snapshot %q was not uploaded", FileName(deviceID))
	}
	snap, err := ParseSnapshot(own.content)
	if err != nil {
		t.Fatalf("uploaded snapshot does not parse: %v", err)
	}
	if snap.DeviceID != deviceID || snap.Schema != SnapshotSchema || snap.WrittenAtMs == 0 {
		t.Fatalf("bad snapshot envelope: %+v", snap)
	}
	if len(snap.Categories) != len(store.SeedCategories) {
		t.Fatalf("snapshot carries %d categories, want %d", len(snap.Categories), len(store.SeedCategories))
	}
	if snap.Settings.Currency != "USD" {
		t.Fatalf("snapshot settings = %+v", snap.Settings)
	}

	// Folder id and own file id are cached for the next pass.
	if id, _ := st.MetaOr(store.MetaFolderID, ""); id == "" {
		t.Fatal("folder id not cached")
	}
	if id, _ := st.MetaOr(store.MetaOwnFileID, ""); id != own.id {
		t.Fatalf("own file id = %q, want %q", id, own.id)
	}

	// A second pass with nothing dirty must not re-upload or re-create.
	if err := e.Sync(ctx); err != nil {
		t.Fatalf("second sync: %v", err)
	}
	_, _, creates, updates, folders = d.counters()
	if creates != 1 || updates != 0 {
		t.Fatalf("idle pass uploaded: %d create / %d update", creates, updates)
	}
	if folders != 1 {
		t.Fatalf("idle pass re-created the folder (%d total)", folders)
	}
}

func TestSyncMergesPeerAndSkipsUnchangedFiles(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)

	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	folderID, _ := st.MetaOr(store.MetaFolderID, "")

	// A phone drops its snapshot into the folder.
	peerTx := model.Transaction{
		ID: "aaaaaaaa-0000-4000-8000-000000000001", Kind: model.KindExpense, AmountMinor: 25000,
		CategoryID: store.SeedCategories[0].ID, Note: "from the phone",
		OccurredAt: "2026-08-19T10:00:00Z", Source: model.SourceApp,
		CreatedAtMs: 1787000000000, UpdatedAtMs: 1787000000000,
	}
	peer := NewSnapshot("phone-device", "Pixel 7", 1787160000000, store.Snapshot{
		Transactions: []model.Transaction{peerTx},
		Settings:     model.Settings{ID: model.SettingsID, Currency: "RUB", Language: "ru", UpdatedAtMs: 1787160000000},
	})
	body, err := peer.Marshal()
	if err != nil {
		t.Fatal(err)
	}
	d.put(FileName("phone-device"), []string{folderID}, body)

	if err := e.Sync(ctx); err != nil {
		t.Fatalf("merge pass: %v", err)
	}
	local, err := st.FullState()
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, tr := range local.Transactions {
		if tr.ID == peerTx.ID {
			found = true
			if tr.Note != "from the phone" || tr.AmountMinor != 25000 {
				t.Fatalf("merged row is wrong: %+v", tr)
			}
		}
	}
	if !found {
		t.Fatal("peer transaction was not merged")
	}
	// settings.language is how the phone tells the bot which language to use.
	settings, err := st.Settings()
	if err != nil {
		t.Fatal(err)
	}
	if settings.Language != "ru" || settings.Currency != "RUB" {
		t.Fatalf("peer settings not merged: %+v", settings)
	}
	// Merged rows are not dirty, so we must not have republished.
	_, downloads, creates, updates, _ := d.counters()
	if downloads != 1 {
		t.Fatalf("downloaded %d times, want 1", downloads)
	}
	if creates != 1 || updates != 0 {
		t.Fatalf("merge pass republished: %d create / %d update", creates, updates)
	}

	// Third pass: the peer file is unchanged, so its md5 short-circuits the
	// download entirely.
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if _, downloads, _, _, _ = d.counters(); downloads != 1 {
		t.Fatalf("unchanged peer file was downloaded again (%d downloads)", downloads)
	}

	// Change the peer file: the new md5 forces a fresh download.
	peer.Transactions[0].Note = "edited on the phone"
	peer.Transactions[0].UpdatedAtMs = 1787200000000
	body, _ = peer.Marshal()
	d.put(FileName("phone-device"), []string{folderID}, body)
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if _, downloads, _, _, _ = d.counters(); downloads != 2 {
		t.Fatalf("changed peer file was not re-downloaded (%d downloads)", downloads)
	}
	local, _ = st.FullState()
	for _, tr := range local.Transactions {
		if tr.ID == peerTx.ID && tr.Note != "edited on the phone" {
			t.Fatalf("peer edit not applied: %+v", tr)
		}
	}
}

func TestSyncPublishesLocalWrites(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)

	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	deviceID, _, _ := e.identity()

	// A bot write marks the row dirty and schedules a sync.
	scheduled := make(chan struct{}, 4)
	st.SetWriteHook(func() { scheduled <- struct{}{} })
	tx := model.Transaction{
		ID: "bbbbbbbb-0000-4000-8000-000000000001", Kind: model.KindExpense, AmountMinor: 4200,
		CategoryID: store.SeedCategories[1].ID, Note: "coffee",
		OccurredAt: "2026-08-19T08:30:00Z", Source: model.SourceTelegram,
		CreatedAtMs: 1787300000000, UpdatedAtMs: 1787300000000,
	}
	if err := st.InsertTransaction(tx); err != nil {
		t.Fatal(err)
	}
	select {
	case <-scheduled:
	default:
		t.Fatal("bot write did not fire the sync trigger")
	}

	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	_, _, creates, updates, _ := d.counters()
	if creates != 1 || updates != 1 {
		t.Fatalf("publish: %d create / %d update, want 1 / 1", creates, updates)
	}
	own := d.byName(FileName(deviceID))
	snap, err := ParseSnapshot(own.content)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, tr := range snap.Transactions {
		if tr.ID == tx.ID {
			found = true
		}
	}
	if !found {
		t.Fatal("the bot's transaction never reached the published snapshot")
	}

	// Dirty is cleared, so the next pass is a no-op upload-wise.
	if dirty, _ := st.HasDirty(); dirty {
		t.Fatal("dirty flag not cleared after a successful publish")
	}
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if _, _, _, updates, _ = d.counters(); updates != 1 {
		t.Fatalf("clean pass re-uploaded (%d updates)", updates)
	}
}

// A tombstone written locally must reach the published snapshot, or peers
// resurrect the row on their next merge.
func TestSyncPublishesTombstones(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)

	tx := model.Transaction{
		ID: "cccccccc-0000-4000-8000-000000000001", Kind: model.KindExpense, AmountMinor: 100,
		CategoryID: store.SeedCategories[0].ID, OccurredAt: "2026-08-19T10:00:00Z",
		Source: model.SourceTelegram, CreatedAtMs: 1, UpdatedAtMs: 1,
	}
	if err := st.InsertTransaction(tx); err != nil {
		t.Fatal(err)
	}
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if err := st.SoftDeleteTransaction(tx.ID, 2000); err != nil {
		t.Fatal(err)
	}
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}

	deviceID, _, _ := e.identity()
	snap, err := ParseSnapshot(d.byName(FileName(deviceID)).content)
	if err != nil {
		t.Fatal(err)
	}
	for _, tr := range snap.Transactions {
		if tr.ID == tx.ID {
			if tr.DeletedAtMs == nil || *tr.DeletedAtMs != 2000 {
				t.Fatalf("tombstone missing from the published snapshot: %+v", tr)
			}
			return
		}
	}
	t.Fatal("tombstoned row dropped from the published snapshot")
}

// A hand-mangled peer file must not stop the pass: bad rows are skipped, the
// good ones still land.
func TestSyncSurvivesCorruptPeerFile(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	folderID, _ := st.MetaOr(store.MetaFolderID, "")

	d.put(FileName("broken"), []string{folderID}, []byte(`{ this is not json`))

	good := NewSnapshot("phone", "Pixel", 1787160000000, store.Snapshot{
		Transactions: []model.Transaction{
			{ID: "dddddddd-0000-4000-8000-000000000001", Kind: model.KindExpense, AmountMinor: 0,
				CategoryID: store.SeedCategories[0].ID, OccurredAt: "2026-08-19T10:00:00Z",
				Source: model.SourceApp, CreatedAtMs: 1, UpdatedAtMs: 1}, // amount 0 → dropped
			{ID: "dddddddd-0000-4000-8000-000000000002", Kind: model.KindExpense, AmountMinor: 700,
				CategoryID: store.SeedCategories[0].ID, OccurredAt: "2026-08-19T13:00:00+03:00",
				Source: model.SourceApp, CreatedAtMs: 1, UpdatedAtMs: 1}, // offset → normalized
		},
		Settings: model.Settings{ID: model.SettingsID, Currency: "USD", UpdatedAtMs: 1},
	})
	body, _ := good.Marshal()
	d.put(FileName("phone"), []string{folderID}, body)

	if err := e.Sync(ctx); err != nil {
		t.Fatalf("sync aborted on a corrupt peer file: %v", err)
	}
	local, _ := st.FullState()
	var ids []string
	for _, tr := range local.Transactions {
		ids = append(ids, tr.ID)
		if tr.ID == "dddddddd-0000-4000-8000-000000000002" && tr.OccurredAt != "2026-08-19T10:00:00Z" {
			t.Fatalf("occurred_at not normalized on merge: %q", tr.OccurredAt)
		}
	}
	for _, id := range ids {
		if id == "dddddddd-0000-4000-8000-000000000001" {
			t.Fatal("a zero-amount row was merged")
		}
	}
	if len(ids) != 1 {
		t.Fatalf("merged transactions = %v, want exactly the valid one", ids)
	}
}

// A stale cached folder id must be re-resolved rather than failing forever.
func TestSyncReresolvesDeletedFolder(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if err := st.SetMeta(store.MetaFolderID, "file-does-not-exist"); err != nil {
		t.Fatal(err)
	}
	if err := e.Sync(ctx); err != nil {
		t.Fatalf("sync with a stale folder id: %v", err)
	}
	id, _ := st.MetaOr(store.MetaFolderID, "")
	if id == "file-does-not-exist" || id == "" {
		t.Fatalf("stale folder id not replaced: %q", id)
	}
}

func TestSyncNotConfigured(t *testing.T) {
	st := testStore(t)

	// No client credentials at all.
	e := NewEngine(st, Config{TokenPath: filepath.Join(t.TempDir(), "token.json")})
	if e.IsConfigured() {
		t.Fatal("IsConfigured with no credentials")
	}
	if err := e.Sync(context.Background()); err != nil {
		t.Fatalf("Sync without credentials should be a no-op, got %v", err)
	}
	if got := e.State().Status; got != StatusNotConfigured {
		t.Fatalf("status = %q, want notConfigured", got)
	}

	// Credentials but no token: still notConfigured, still no error, so the
	// bot and the health endpoint keep running.
	e2 := NewEngine(st, Config{ClientID: "id", ClientSecret: "s", TokenPath: filepath.Join(t.TempDir(), "token.json")})
	if e2.IsConfigured() {
		t.Fatal("IsConfigured with no saved token")
	}
	if err := e2.Sync(context.Background()); err != nil {
		t.Fatalf("Sync without a token should be a no-op, got %v", err)
	}
	if got := e2.State().Status; got != StatusNotConfigured {
		t.Fatalf("status = %q, want notConfigured", got)
	}
	if e2.cfg.FolderName != "Tally" {
		t.Fatalf("default folder name = %q", e2.cfg.FolderName)
	}
}

// Retryable failures are surfaced as `offline`, not `error`.
func TestSyncOfflineOnServerError(t *testing.T) {
	fastBackoff(t)
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)

	d.failNext = func(*http.Request) (int, string) {
		return 503, `{"error":{"code":503,"message":"backend error"}}`
	}
	if err := e.Sync(ctx); err == nil {
		t.Fatal("sync succeeded against a failing Drive")
	}
	if got := e.State().Status; got != StatusOffline {
		t.Fatalf("status = %q, want offline", got)
	}
	if e.State().LastSyncMs != 0 {
		t.Fatal("a failed pass recorded a successful sync time")
	}

	// A 401 is a real error the user must act on.
	d.failNext = func(*http.Request) (int, string) {
		return 401, `{"error":{"code":401,"message":"Invalid Credentials"}}`
	}
	if err := e.Sync(ctx); err == nil {
		t.Fatal("sync succeeded with a revoked token")
	}
	state := e.State()
	if state.Status != StatusError {
		t.Fatalf("status = %q, want error", state.Status)
	}
	if state.Message == "" {
		t.Fatal("401 produced no message for the operator")
	}
}

func TestScheduleSyncCoalesces(t *testing.T) {
	st := testStore(t)
	e := NewEngine(st, Config{TokenPath: filepath.Join(t.TempDir(), "token.json")})
	for i := 0; i < 10; i++ {
		e.ScheduleSync() // must never block, however many writes land at once
	}
	select {
	case <-e.trigger:
	default:
		t.Fatal("ScheduleSync queued nothing")
	}
	select {
	case <-e.trigger:
		t.Fatal("ScheduleSync queued more than one pending pass")
	default:
	}
}

func TestRunDebouncesWritesAndStopsWithContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)

	done := make(chan struct{})
	go func() {
		defer close(done)
		e.Run(ctx, time.Hour) // ticker effectively disabled
	}()

	// Wait for the startup pass to publish the first snapshot.
	deadline := time.Now().Add(10 * time.Second)
	for {
		if _, _, creates, _, _ := d.counters(); creates == 1 {
			break
		}
		if time.Now().After(deadline) {
			cancel()
			t.Fatal("startup sync never ran")
		}
		time.Sleep(20 * time.Millisecond)
	}

	cancel()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("Run did not return after ctx was cancelled")
	}
}
