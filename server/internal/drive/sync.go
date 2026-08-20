package drive

import (
	"context"
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/url"
	"os"
	"strconv"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"google.golang.org/api/googleapi"

	"github.com/xensa/tally/internal/store"
)

// Status mirrors the app's sync status model so both peers speak the same
// language in logs and UI.
type Status string

const (
	StatusNotConfigured Status = "notConfigured"
	StatusIdle          Status = "idle"
	StatusSyncing       Status = "syncing"
	StatusOffline       Status = "offline"
	StatusError         Status = "error"
)

// DebounceDelay is how long a write waits before triggering a sync, so a
// burst of bot writes produces one upload.
const DebounceDelay = 3 * time.Second

// DefaultInterval is the poll period when SYNC_INTERVAL_SECONDS is unset.
// Polling is not optional: with no server API it is the only way the bot
// notices transactions entered on the phone.
const DefaultInterval = 60 * time.Second

// Config is everything the engine needs from the environment.
type Config struct {
	ClientID     string
	ClientSecret string
	TokenPath    string
	FolderName   string
}

// Valid reports whether the OAuth client credentials are present at all.
func (c Config) Valid() bool { return c.ClientID != "" && c.ClientSecret != "" }

// State is a snapshot of the engine's observable state.
type State struct {
	Status     Status
	Message    string
	LastSyncMs int64
}

// Engine implements the sync algorithm of docs/ARCHITECTURE.md against the
// local store. Its public surface mirrors the app's Drive engine:
// Sync / ScheduleSync / State / IsConfigured.
type Engine struct {
	st    *store.Store
	cfg   Config
	oauth *oauth2.Config

	syncMu sync.Mutex // serializes whole sync passes, and guards the fields below
	client *Client
	// clientToken is the refresh token e.client was built from. `tally auth`
	// writes a fresh token into the shared volume while the server keeps
	// running, so the cached client has to be rebuilt when the file changes —
	// otherwise the documented recovery does nothing until a restart.
	clientToken string
	// newClient builds the Drive client. Tests replace it to point at a stub;
	// nil means the real Drive service.
	newClient func(context.Context, oauth2.TokenSource) (*Client, error)

	mu         sync.Mutex
	status     Status
	message    string
	lastSyncMs int64

	trigger chan struct{}
}

// NewEngine builds the engine. It performs no I/O.
func NewEngine(st *store.Store, cfg Config) *Engine {
	if cfg.FolderName == "" {
		cfg.FolderName = "Tally"
	}
	e := &Engine{
		st:      st,
		cfg:     cfg,
		trigger: make(chan struct{}, 1),
		status:  StatusNotConfigured,
	}
	if cfg.Valid() {
		e.oauth = OAuthConfig(cfg.ClientID, cfg.ClientSecret)
	}
	if e.IsConfigured() {
		e.status = StatusIdle
	}
	if ms, err := st.MetaOr(store.MetaLastSyncMs, "0"); err == nil {
		e.lastSyncMs, _ = strconv.ParseInt(ms, 10, 64)
	}
	return e
}

// IsConfigured reports whether the engine has both OAuth credentials and a
// saved refresh token.
func (e *Engine) IsConfigured() bool {
	return e.cfg.Valid() && HasToken(e.cfg.TokenPath)
}

// State returns the current status snapshot.
func (e *Engine) State() State {
	e.mu.Lock()
	defer e.mu.Unlock()
	return State{Status: e.status, Message: e.message, LastSyncMs: e.lastSyncMs}
}

func (e *Engine) setStatus(s Status, msg string) {
	e.mu.Lock()
	e.status, e.message = s, msg
	e.mu.Unlock()
}

func (e *Engine) setLastSync(ms int64) {
	e.mu.Lock()
	e.lastSyncMs = ms
	e.mu.Unlock()
}

// ScheduleSync asks for a sync soon. It never blocks: the trigger channel
// holds at most one pending request, which Run debounces by DebounceDelay.
func (e *Engine) ScheduleSync() {
	select {
	case e.trigger <- struct{}{}:
	default:
	}
}

// Run drives the engine until ctx is cancelled: one pass at startup, then a
// pass every interval, plus a DebounceDelay-delayed pass after each local
// write signalled through ScheduleSync.
func (e *Engine) Run(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = DefaultInterval
	}
	if err := e.Sync(ctx); err != nil && !errors.Is(err, context.Canceled) {
		log.Printf("drive: startup sync: %v", err)
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	// A stopped timer with a drained channel: armed only while a debounce is
	// pending, so the select below has nothing to fire otherwise.
	debounce := time.NewTimer(time.Hour)
	if !debounce.Stop() {
		<-debounce.C
	}
	defer debounce.Stop()
	pending := false

	for {
		select {
		case <-ctx.Done():
			return
		case <-e.trigger:
			if pending && !debounce.Stop() {
				select {
				case <-debounce.C:
				default:
				}
			}
			debounce.Reset(DebounceDelay)
			pending = true
		case <-debounce.C:
			pending = false
			if err := e.Sync(ctx); err != nil && !errors.Is(err, context.Canceled) {
				log.Printf("drive: sync after write: %v", err)
			}
		case <-ticker.C:
			if err := e.Sync(ctx); err != nil && !errors.Is(err, context.Canceled) {
				log.Printf("drive: periodic sync: %v", err)
			}
		}
	}
}

// Sync runs one full pass of the algorithm in docs/ARCHITECTURE.md. Passes
// never overlap.
func (e *Engine) Sync(ctx context.Context) error {
	e.syncMu.Lock()
	defer e.syncMu.Unlock()

	// 1. Ensure auth.
	if !e.cfg.Valid() {
		e.setStatus(StatusNotConfigured, "GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET not set")
		return nil
	}
	if !HasToken(e.cfg.TokenPath) {
		e.setStatus(StatusNotConfigured, "no refresh token — run `tally auth`")
		return nil
	}
	e.setStatus(StatusSyncing, "")

	err := e.syncOnce(ctx)
	if err == nil {
		now := time.Now().UTC().UnixMilli()
		e.setLastSync(now)
		if err := e.st.SetMeta(store.MetaLastSyncMs, strconv.FormatInt(now, 10)); err != nil {
			log.Printf("drive: persist last_sync_ms: %v", err)
		}
		e.setStatus(StatusIdle, "")
		return nil
	}
	if IsAuthError(err) {
		// Drop the cached client so the next pass reloads TOKEN_PATH: the fix
		// we are about to tell the owner about (`tally auth`) writes a new
		// token into the same volume while this process keeps running.
		e.client, e.clientToken = nil, ""
	}
	status, msg := Classify(err)
	e.setStatus(status, msg)
	return err
}

// Classify maps a sync failure onto the status model. Anything the network
// might fix on its own is `offline`; everything else is a real `error` the
// user has to see.
func Classify(err error) (Status, string) {
	switch {
	case err == nil:
		return StatusIdle, ""
	case errors.Is(err, context.Canceled), errors.Is(err, context.DeadlineExceeded):
		return StatusOffline, err.Error()
	case IsAuthError(err):
		return StatusError, "Google rejected the saved token — re-run " +
			"`docker compose run --rm tally auth` (the new token is picked up on the " +
			"next pass; restart the server if sync stays broken)"
	case Retryable(err):
		// The backoff budget ran out; the next pass tries again.
		return StatusOffline, err.Error()
	}
	var ae *googleapi.Error
	if errors.As(err, &ae) {
		return StatusError, err.Error()
	}
	var nerr net.Error
	var uerr *url.Error
	if errors.As(err, &nerr) || errors.As(err, &uerr) {
		return StatusOffline, err.Error()
	}
	return StatusError, err.Error()
}

func (e *Engine) syncOnce(ctx context.Context) error {
	client, err := e.ensureClient(ctx)
	if err != nil {
		return err
	}
	deviceID, deviceName, err := e.identity()
	if err != nil {
		return err
	}
	ownName := FileName(deviceID)

	// 2. Resolve folder id (by name; the cached id backstops an empty answer).
	folderID, err := e.resolveFolder(ctx, client, ownName)
	if err != nil {
		return err
	}

	// 3. List tally-*.json.
	files, err := client.ListSnapshots(ctx, folderID)
	if err != nil {
		if IsNotFound(err) {
			// The cached folder vanished between the check and the list.
			if err := e.st.SetMeta(store.MetaFolderID, ""); err != nil {
				log.Printf("drive: clear cached folder id: %v", err)
			}
		}
		return err
	}

	md5s, err := e.loadMD5Map()
	if err != nil {
		return err
	}

	// 4. Download every peer file whose md5 changed since last time.
	var batch store.Batch
	var own *FileInfo
	seen := make(map[string]struct{}, len(files))
	for i := range files {
		f := files[i]
		if f.Name == ownName {
			own = &files[i]
			continue
		}
		seen[f.ID] = struct{}{}
		if f.MD5 != "" && md5s[f.ID] == f.MD5 {
			continue // unchanged since the last pass
		}
		body, err := client.Download(ctx, f.ID)
		if err != nil {
			if IsNotFound(err) {
				// Deleted between list and download; next pass will re-list.
				continue
			}
			return err
		}
		snap, err := ParseSnapshot(body)
		if err != nil {
			log.Printf("drive: skipping %s: %v", f.Name, err)
			continue
		}
		rows, skipped := snap.Batch()
		for _, s := range skipped {
			log.Printf("drive: %s: skipped %s", f.Name, s)
		}
		batch.Categories = append(batch.Categories, rows.Categories...)
		batch.Transactions = append(batch.Transactions, rows.Transactions...)
		batch.Settings = append(batch.Settings, rows.Settings...)
		md5s[f.ID] = f.MD5
	}
	// Forget md5s of peer files that are gone, so the map cannot grow forever.
	for id := range md5s {
		if _, ok := seen[id]; !ok {
			delete(md5s, id)
		}
	}

	// 5. Merge everything in one transaction, strict LWW, dirty = 0.
	if !batch.Empty() {
		applied, err := e.st.MergeRemote(batch)
		if err != nil {
			return fmt.Errorf("merge peer rows: %w", err)
		}
		if applied > 0 {
			log.Printf("drive: merged %d row(s) from %d peer file(s)", applied, len(files)-boolInt(own != nil))
		}
	}

	// 6. Publish our own snapshot when anything local is dirty or we have
	//    never uploaded one.
	dirty, err := e.st.HasDirty()
	if err != nil {
		return err
	}
	if dirty || own == nil {
		local, err := e.st.FullState()
		if err != nil {
			return err
		}
		snap := NewSnapshot(deviceID, deviceName, time.Now().UTC().UnixMilli(), local)
		body, err := snap.Marshal()
		if err != nil {
			return err
		}
		var info FileInfo
		if own == nil {
			info, err = client.Create(ctx, folderID, ownName, body)
		} else {
			info, err = client.Update(ctx, own.ID, body)
			if IsNotFound(err) {
				info, err = client.Create(ctx, folderID, ownName, body)
			}
		}
		if err != nil {
			return err
		}
		if err := e.st.SetMeta(store.MetaOwnFileID, info.ID); err != nil {
			log.Printf("drive: persist own file id: %v", err)
		}
		// 7. Clear dirty only where updated_at_ms is unchanged since we
		//    serialized — rows edited mid-upload stay dirty for the next pass.
		if err := e.st.ClearDirty(local); err != nil {
			return fmt.Errorf("clear dirty: %w", err)
		}
	}

	// 8. Persist the per-file md5 map.
	return e.saveMD5Map(md5s)
}

func boolInt(b bool) int {
	if b {
		return 1
	}
	return 0
}

// ensureClient returns the cached Drive client, rebuilding it whenever the
// token file has changed underneath us. Caching it forever would mean the
// documented recovery — `docker compose run --rm tally auth`, which drops a
// fresh token into the shared /data volume — had no effect on a long-running
// server until someone restarted the container.
func (e *Engine) ensureClient(ctx context.Context) (*Client, error) {
	tok, err := LoadToken(e.cfg.TokenPath)
	if err != nil {
		return nil, err
	}
	if e.client != nil && e.clientToken == tok.RefreshToken {
		return e.client, nil
	}
	if e.client != nil {
		log.Printf("drive: %s holds a new refresh token — rebuilding the Drive client", e.cfg.TokenPath)
	}
	// context.WithoutCancel: the client outlives any single sync pass; each
	// call still passes its own request context.
	clientCtx := context.WithoutCancel(ctx)
	ts := TokenSourceFor(clientCtx, e.oauth, e.cfg.TokenPath, tok)
	build := e.newClient
	if build == nil {
		build = func(ctx context.Context, ts oauth2.TokenSource) (*Client, error) { return NewClient(ctx, ts) }
	}
	c, err := build(clientCtx, ts)
	if err != nil {
		return nil, err
	}
	e.client, e.clientToken = c, tok.RefreshToken
	return c, nil
}

// resolveFolder resolves the sync folder BY NAME on every pass — one list
// call, the same cost as verifying a cached id with files.get, and it is what
// lets a peer recover from a duplicate-folder split instead of caching its own
// folder forever. The cached id is only consulted when the name query comes
// back empty, because Drive's file list is eventually consistent and a blank
// answer must never mint a second folder.
func (e *Engine) resolveFolder(ctx context.Context, client *Client, ownName string) (string, error) {
	cached, err := e.st.MetaOr(store.MetaFolderID, "")
	if err != nil {
		return "", err
	}

	ids, err := client.FindFolders(ctx, e.cfg.FolderName)
	if err != nil {
		return "", err
	}
	if len(ids) == 0 {
		if cached != "" {
			ok, err := client.FolderExists(ctx, cached)
			if err != nil {
				return "", err
			}
			if ok {
				return cached, nil
			}
		}
		created, err := client.CreateFolder(ctx, e.cfg.FolderName)
		if err != nil {
			return "", err
		}
		// Re-check before adopting it: the other peer's very first sync may
		// have created its own folder inside this same round trip.
		ids, err = client.FindFolders(ctx, e.cfg.FolderName)
		if err != nil || len(ids) == 0 {
			ids = []string{created}
		}
	}

	id, err := e.pickFolder(ctx, client, ids, ownName)
	if err != nil {
		return "", err
	}
	if id != cached {
		if cached != "" {
			log.Printf("drive: sync folder %q resolved to %s (was %s)", e.cfg.FolderName, id, cached)
		}
		if err := e.st.SetMeta(store.MetaFolderID, id); err != nil {
			return "", err
		}
	}
	return id, nil
}

// pickFolder resolves a duplicate-folder split deterministically. It prefers
// the folder that already holds another peer's snapshot — so this peer joins
// the phone rather than dragging it — and falls back to the lowest id, which
// every peer sorts identically. Either way the choice is stable across passes,
// so the peers converge instead of each sitting in its own folder forever.
func (e *Engine) pickFolder(ctx context.Context, client *Client, ids []string, ownName string) (string, error) {
	if len(ids) == 1 {
		return ids[0], nil
	}
	log.Printf("drive: WARNING: %d folders named %q in the Drive root (%v) — two peers created one each; "+
		"joining the one that already holds a peer snapshot, then delete the empty one in the Drive UI",
		len(ids), e.cfg.FolderName, ids)
	best, bestPeers := ids[0], -1
	for _, id := range ids {
		files, err := client.ListSnapshots(ctx, id)
		if err != nil {
			return "", err
		}
		peers := 0
		for _, f := range files {
			if f.Name != ownName {
				peers++
			}
		}
		if peers > bestPeers { // strict: ties keep the lowest id
			best, bestPeers = id, peers
		}
	}
	return best, nil
}

// identity returns this peer's stable device id and human-readable name,
// generating and persisting them on first use.
func (e *Engine) identity() (id, name string, err error) {
	id, err = e.st.MetaOr(store.MetaDeviceID, "")
	if err != nil {
		return "", "", err
	}
	if id == "" {
		id = newUUID()
		if err := e.st.SetMeta(store.MetaDeviceID, id); err != nil {
			return "", "", err
		}
	}
	name, err = e.st.MetaOr(store.MetaDeviceName, "")
	if err != nil {
		return "", "", err
	}
	if name == "" {
		name = defaultDeviceName()
		if err := e.st.SetMeta(store.MetaDeviceName, name); err != nil {
			return "", "", err
		}
	}
	return id, name, nil
}

func defaultDeviceName() string {
	if h, err := os.Hostname(); err == nil && h != "" {
		return "Tally server (" + h + ")"
	}
	return "Tally server"
}

func (e *Engine) loadMD5Map() (map[string]string, error) {
	raw, err := e.st.MetaOr(store.MetaPeerMD5, "")
	if err != nil {
		return nil, err
	}
	m := map[string]string{}
	if raw == "" {
		return m, nil
	}
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		// Corrupted cache is not fatal: re-download everything once.
		log.Printf("drive: peer md5 cache unreadable, rebuilding: %v", err)
		return map[string]string{}, nil
	}
	return m, nil
}

func (e *Engine) saveMD5Map(m map[string]string) error {
	b, err := json.Marshal(m)
	if err != nil {
		return err
	}
	return e.st.SetMeta(store.MetaPeerMD5, string(b))
}

// newUUID returns a random RFC 4122 version-4 UUID string.
func newUUID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err) // crypto/rand never fails on supported platforms
	}
	b[6] = (b[6] & 0x0f) | 0x40 // version 4
	b[8] = (b[8] & 0x3f) | 0x80 // variant 10
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}
