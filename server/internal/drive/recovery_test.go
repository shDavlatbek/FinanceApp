package drive

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"golang.org/x/oauth2"
	"google.golang.org/api/option"

	"github.com/xensa/tally/internal/model"
	"github.com/xensa/tally/internal/store"
)

// deadTokenEndpoint stands in for oauth2.googleapis.com refusing a refresh
// token, which is what a revoked grant — or one silently expired after 7 days
// because the consent screen was left "In testing" — actually looks like.
func deadTokenEndpoint(t *testing.T, status int, body map[string]any) *oauth2.Config {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/token", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, status, body)
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return &oauth2.Config{
		ClientID:     "id",
		ClientSecret: "secret",
		Scopes:       []string{Scope},
		Endpoint: oauth2.Endpoint{
			TokenURL:  srv.URL + "/token",
			AuthStyle: oauth2.AuthStyleInParams,
		},
	}
}

// expiredTokenFile writes a token whose access token is already stale, so the
// very next request forces a refresh against the endpoint above.
func expiredTokenFile(t *testing.T, refresh string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "token.json")
	if err := SaveToken(path, &oauth2.Token{
		AccessToken: "stale", RefreshToken: refresh, TokenType: "Bearer",
		Expiry: time.Now().Add(-time.Hour),
	}); err != nil {
		t.Fatal(err)
	}
	return path
}

// driveCallWith runs one Drive call through a token source built on cfg, and
// returns whatever error the stack produced.
func driveCallWith(t *testing.T, cfg *oauth2.Config, tokenPath string) error {
	t.Helper()
	ts, err := TokenSource(context.Background(), cfg, tokenPath)
	if err != nil {
		t.Fatal(err)
	}
	d := newFakeDrive(t)
	c, err := NewClient(context.Background(), ts, option.WithEndpoint(d.srv.URL+"/drive/v3/"))
	if err != nil {
		t.Fatal(err)
	}
	_, err = c.ListSnapshots(context.Background(), "folder")
	if err == nil {
		t.Fatal("the call succeeded even though the token endpoint refused the refresh")
	}
	return err
}

// A dead refresh token must surface as `error` with a re-auth instruction, not
// as the transient `offline`.
//
// It never reaches googleapi.CheckResponse: oauth2's Transport fails inside
// RoundTrip, so http.Client returns a *url.Error (which satisfies net.Error)
// wrapping *oauth2.RetrieveError, and Classify used to fall through to its
// net/url branch and call a permanently broken install a network blip forever.
func TestClassifyRevokedRefreshToken(t *testing.T) {
	cfg := deadTokenEndpoint(t, http.StatusBadRequest, map[string]any{
		"error":             "invalid_grant",
		"error_description": "Token has been expired or revoked.",
	})
	err := driveCallWith(t, cfg, expiredTokenFile(t, "revoked"))

	var re *oauth2.RetrieveError
	if !errors.As(err, &re) {
		t.Fatalf("test premise broken: %v is not a *oauth2.RetrieveError", err)
	}
	if !IsAuthError(err) {
		t.Fatal("IsAuthError = false for a refresh token Google rejected")
	}
	status, msg := Classify(err)
	if status != StatusError {
		t.Fatalf("Classify = %q, want %q: a dead refresh token is not transient", status, StatusError)
	}
	if !strings.Contains(msg, "tally auth") {
		t.Fatalf("message %q does not tell the owner to re-authorize", msg)
	}
}

// A token endpoint having a bad day is NOT a dead token: the saved refresh
// token may be perfectly good, so it must stay transient.
func TestClassifyTokenEndpointOutageStaysOffline(t *testing.T) {
	cfg := deadTokenEndpoint(t, http.StatusServiceUnavailable, map[string]any{"error": "server_error"})
	err := driveCallWith(t, cfg, expiredTokenFile(t, "fine"))

	if IsAuthError(err) {
		t.Fatal("a 503 from the token endpoint was reported as a revoked token")
	}
	if status, _ := Classify(err); status != StatusOffline {
		t.Fatalf("Classify = %q, want %q for a token-endpoint outage", status, StatusOffline)
	}
}

// The documented recovery is `docker compose run --rm tally auth`, which drops
// a fresh token into the shared /data volume while the server keeps running.
// The engine must pick it up on its next pass instead of holding a token
// source built from the dead file until someone restarts the container.
func TestEngineReloadsRewrittenTokenFile(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, builds := newTestEngine(t, st, d)

	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if *builds != 1 {
		t.Fatalf("built %d clients on the first pass, want 1", *builds)
	}
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if *builds != 1 {
		t.Fatalf("built %d clients; an unchanged token file must reuse the cached one", *builds)
	}

	// `tally auth` runs and writes a new refresh token.
	if err := SaveToken(e.cfg.TokenPath, &oauth2.Token{
		AccessToken: "fresh", RefreshToken: "refresh-2", TokenType: "Bearer",
		Expiry: time.Now().Add(time.Hour),
	}); err != nil {
		t.Fatal(err)
	}
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if *builds != 2 {
		t.Fatalf("built %d clients; the re-authorized token was never loaded, so `tally auth` "+
			"would not fix anything without a restart", *builds)
	}
	if e.clientToken != "refresh-2" {
		t.Fatalf("cached client is still bound to %q", e.clientToken)
	}
}

// An auth failure must also drop the cached client outright, so the next pass
// starts from whatever is on disk.
func TestEngineDropsClientOnAuthFailure(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, builds := newTestEngine(t, st, d)

	d.failNext = func(*http.Request) (int, string) {
		return 401, `{"error":{"code":401,"message":"Invalid Credentials"}}`
	}
	if err := e.Sync(ctx); err == nil {
		t.Fatal("sync succeeded against a 401")
	}
	if e.client != nil || e.clientToken != "" {
		t.Fatal("the cached client survived an auth failure")
	}
	d.failNext = nil
	if err := e.Sync(ctx); err != nil {
		t.Fatalf("recovery pass: %v", err)
	}
	if *builds != 2 {
		t.Fatalf("built %d clients, want 2 (one per pass around the auth failure)", *builds)
	}
	if got := e.State().Status; got != StatusIdle {
		t.Fatalf("status after recovery = %q, want idle", got)
	}
}

// A failed SaveToken must be retried on the next refresh. Advancing the
// in-memory "last written" marker before the write succeeded left the process
// running happily on a token that only ever existed in memory, while the file
// on disk held the refresh token Google had already retired — so the next
// restart stranded the VPS.
func TestTokenSourceRetriesAFailedSave(t *testing.T) {
	f := newFakeGoogle(t)
	f.mu.Lock()
	f.nextAccessTok, f.nextRefreshTok = "access-2", "refresh-2"
	f.mu.Unlock()

	// Break the save portably: a DIRECTORY where the token file belongs makes
	// the atomic write's final rename fail on every OS.
	path := filepath.Join(t.TempDir(), "token.json")
	if err := os.Mkdir(path, 0o700); err != nil {
		t.Fatal(err)
	}

	// Talk to persistingTokenSource directly; ReuseTokenSource sits above it
	// and is not what is under test here.
	stale := &oauth2.Token{AccessToken: "stale", RefreshToken: "refresh-1",
		TokenType: "Bearer", Expiry: time.Now().Add(-time.Hour)}
	p := &persistingTokenSource{
		src:  f.config().TokenSource(context.Background(), stale),
		path: path,
		last: "refresh-1",
	}

	tok, err := p.Token()
	if err != nil {
		t.Fatalf("a failed save must not fail the pass: %v", err)
	}
	if tok.RefreshToken != "refresh-2" {
		t.Fatalf("premise broken: Google returned %q, want the rotated refresh-2", tok.RefreshToken)
	}
	if _, err := LoadToken(path); err == nil {
		t.Fatal("premise broken: the save was supposed to fail")
	}

	// Whatever was wrong with the volume gets fixed; the very next call has to
	// retry the write instead of assuming it already happened.
	if err := os.Remove(path); err != nil {
		t.Fatal(err)
	}
	if _, err := p.Token(); err != nil {
		t.Fatal(err)
	}
	onDisk, err := LoadToken(path)
	if err != nil {
		t.Fatalf("rotated refresh token still not on disk (%v): the write is never retried, so a "+
			"restart would load a token Google has already retired", err)
	}
	if onDisk.RefreshToken != "refresh-2" {
		t.Fatalf("token file holds %q, want refresh-2", onDisk.RefreshToken)
	}
}

// Two peers running this same code can create one `Tally` folder each inside
// the same round trip. Whichever folder this peer ends up in must be a stable,
// peer-agnostic choice, or the two sit in separate folders forever, both
// reporting `idle`, converging on nothing.
func TestSyncConvergesOnDuplicateFolders(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)

	// The phone got there first and already published into its own folder.
	phoneFolder := d.putFolder("Tally")
	phone := NewSnapshot("phone-device", "Pixel 7", 1787160000000, store.Snapshot{
		Settings: model.Settings{ID: model.SettingsID, Currency: "USD", UpdatedAtMs: 1787160000000},
	})
	body, err := phone.Marshal()
	if err != nil {
		t.Fatal(err)
	}
	d.put(FileName("phone-device"), []string{phoneFolder}, body)

	// …and this peer had already cached a second, empty `Tally` of its own.
	ourFolder := d.putFolder("Tally")
	if err := st.SetMeta(store.MetaFolderID, ourFolder); err != nil {
		t.Fatal(err)
	}

	if err := e.Sync(ctx); err != nil {
		t.Fatalf("sync with duplicate folders: %v", err)
	}
	got, _ := st.MetaOr(store.MetaFolderID, "")
	if got != phoneFolder {
		t.Fatalf("adopted folder %q, want the one holding the peer snapshot (%q) — "+
			"the two peers would never see each other's files", got, phoneFolder)
	}
	deviceID, _, _ := e.identity()
	own := d.byName(FileName(deviceID))
	if own == nil || !contains(own.parents, phoneFolder) {
		t.Fatalf("our snapshot was not published into the shared folder: %+v", own)
	}
	if _, _, _, _, folders := d.counters(); folders != 0 {
		t.Fatalf("created %d folders when two already existed", folders)
	}
}

// With no peer files to go on, the tie-break must still be deterministic —
// both peers sort the candidate ids and take the lowest.
func TestSyncPicksLowestFolderIDWhenNoPeerFiles(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)

	a := d.putFolderWithID("folder-a", "Tally")
	d.putFolderWithID("folder-z", "Tally")
	if err := st.SetMeta(store.MetaFolderID, "folder-z"); err != nil {
		t.Fatal(err)
	}
	if err := e.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if got, _ := st.MetaOr(store.MetaFolderID, ""); got != a {
		t.Fatalf("adopted %q, want the lowest id %q", got, a)
	}
}

// The name query is authoritative, but an empty answer must never mint a
// second folder while a cached id still resolves: Drive's file list is
// eventually consistent.
func TestResolveFolderTrustsCachedIDWhenListingIsEmpty(t *testing.T) {
	ctx := context.Background()
	d := newFakeDrive(t)
	st := testStore(t)
	e, _ := newTestEngine(t, st, d)

	// A live folder that the name query cannot see (here: it is named
	// something else, standing in for a listing that has not caught up yet).
	hidden := d.putFolderWithID("hidden-folder", "Renamed")
	if err := st.SetMeta(store.MetaFolderID, hidden); err != nil {
		t.Fatal(err)
	}

	folder, err := e.resolveFolder(ctx, d.client(ctx, t), "tally-me.json")
	if err != nil {
		t.Fatal(err)
	}
	if folder != hidden {
		t.Fatalf("resolved %q, want the live cached folder %q — an empty listing must not "+
			"mint a second folder", folder, hidden)
	}
	if _, _, _, _, folders := d.counters(); folders != 0 {
		t.Fatalf("created %d folders despite a live cached id", folders)
	}
}
