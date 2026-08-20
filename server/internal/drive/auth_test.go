package drive

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"golang.org/x/oauth2"
)

// fakeGoogle stands in for oauth2.googleapis.com: the RFC 8628 device-code
// endpoint plus the token endpoint (device polling AND refreshes).
type fakeGoogle struct {
	srv *httptest.Server

	mu             sync.Mutex
	pendingPolls   int      // authorization_pending responses before success
	deviceCalls    int      // /device hits
	tokenCalls     int      // /token hits
	grantTypes     []string // grant_type of every /token hit
	sentSecrets    []string
	refreshTokens  []string // refresh_token sent on refresh requests
	nextRefreshTok string   // refresh_token to hand back on the next success
	nextAccessTok  string
}

func newFakeGoogle(t *testing.T) *fakeGoogle {
	t.Helper()
	f := &fakeGoogle{nextRefreshTok: "refresh-1", nextAccessTok: "access-1"}
	mux := http.NewServeMux()
	mux.HandleFunc("/device", func(w http.ResponseWriter, r *http.Request) {
		f.mu.Lock()
		f.deviceCalls++
		f.mu.Unlock()
		_ = r.ParseForm()
		if got := r.Form.Get("scope"); got != Scope {
			t.Errorf("device request scope = %q, want %q", got, Scope)
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"device_code":      "dev-code-abc",
			"user_code":        "WDJB-MJHT",
			"verification_url": "https://www.google.com/device",
			"expires_in":       300,
			"interval":         1,
		})
	})
	mux.HandleFunc("/token", func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		f.mu.Lock()
		f.tokenCalls++
		f.grantTypes = append(f.grantTypes, r.Form.Get("grant_type"))
		f.sentSecrets = append(f.sentSecrets, r.Form.Get("client_secret"))
		if rt := r.Form.Get("refresh_token"); rt != "" {
			f.refreshTokens = append(f.refreshTokens, rt)
		}
		pending := f.pendingPolls > 0
		if pending {
			f.pendingPolls--
		}
		access, refresh := f.nextAccessTok, f.nextRefreshTok
		f.mu.Unlock()

		if pending {
			writeJSON(w, http.StatusBadRequest, map[string]any{"error": "authorization_pending"})
			return
		}
		body := map[string]any{
			"access_token": access,
			"token_type":   "Bearer",
			"expires_in":   3600,
		}
		if refresh != "" {
			body["refresh_token"] = refresh
		}
		writeJSON(w, http.StatusOK, body)
	})
	f.srv = httptest.NewServer(mux)
	t.Cleanup(f.srv.Close)
	return f
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (f *fakeGoogle) config() *oauth2.Config {
	return &oauth2.Config{
		ClientID:     "client-id.apps.googleusercontent.com",
		ClientSecret: "client-secret",
		Scopes:       []string{Scope},
		Endpoint: oauth2.Endpoint{
			DeviceAuthURL: f.srv.URL + "/device",
			TokenURL:      f.srv.URL + "/token",
			AuthStyle:     oauth2.AuthStyleInParams,
		},
	}
}

func (f *fakeGoogle) stats() (device, token int, grants []string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.deviceCalls, f.tokenCalls, append([]string(nil), f.grantTypes...)
}

// The device flow must poll through authorization_pending and persist the
// resulting refresh token at TOKEN_PATH with mode 0600.
func TestAuthorizeDeviceFlowPersistsToken(t *testing.T) {
	f := newFakeGoogle(t)
	f.pendingPolls = 1

	dir := t.TempDir()
	path := filepath.Join(dir, "nested", "google-token.json")

	var gotURI, gotCode string
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	tok, err := Authorize(ctx, f.config(), path, func(uri, code string, _ time.Time) {
		gotURI, gotCode = uri, code
	})
	if err != nil {
		t.Fatalf("Authorize: %v", err)
	}
	if gotURI != "https://www.google.com/device" || gotCode != "WDJB-MJHT" {
		t.Fatalf("prompt got %q / %q", gotURI, gotCode)
	}
	if tok.RefreshToken != "refresh-1" || tok.AccessToken != "access-1" {
		t.Fatalf("token = %+v", tok)
	}

	device, tokenCalls, grants := f.stats()
	if device != 1 {
		t.Fatalf("device endpoint hit %d times, want 1", device)
	}
	if tokenCalls != 2 {
		t.Fatalf("token endpoint hit %d times, want 2 (one pending, one success)", tokenCalls)
	}
	for _, g := range grants {
		if g != "urn:ietf:params:oauth:grant-type:device_code" {
			t.Fatalf("grant_type = %q", g)
		}
	}
	f.mu.Lock()
	secrets := append([]string(nil), f.sentSecrets...)
	f.mu.Unlock()
	for _, s := range secrets {
		if s != "client-secret" {
			t.Fatalf("client_secret not sent on the device token exchange: %q", s)
		}
	}

	// Persisted, parseable, and readable back.
	onDisk, err := LoadToken(path)
	if err != nil {
		t.Fatalf("LoadToken: %v", err)
	}
	if onDisk.RefreshToken != "refresh-1" {
		t.Fatalf("persisted refresh token = %q", onDisk.RefreshToken)
	}
	if !HasToken(path) {
		t.Fatal("HasToken = false right after Authorize")
	}
	// No stray temp file left behind by the atomic write.
	if _, err := os.Stat(path + ".tmp"); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("temp token file left behind: %v", err)
	}
	if runtime.GOOS != "windows" { // Windows has no POSIX mode bits
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if perm := info.Mode().Perm(); perm != 0o600 {
			t.Fatalf("token file mode = %04o, want 0600", perm)
		}
	}
}

func TestAuthorizeRejectsMissingRefreshToken(t *testing.T) {
	f := newFakeGoogle(t)
	f.nextRefreshTok = "" // Google handed back an access token only

	path := filepath.Join(t.TempDir(), "token.json")
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	if _, err := Authorize(ctx, f.config(), path, nil); err == nil {
		t.Fatal("Authorize accepted a response with no refresh token")
	} else if !strings.Contains(err.Error(), "refresh token") {
		t.Fatalf("unhelpful error: %v", err)
	}
	if HasToken(path) {
		t.Fatal("a useless token was persisted anyway")
	}
}

// Google rotates refresh tokens; every rotation must land on disk, or sync
// dies once the old one is retired.
func TestTokenSourcePersistsRotatedRefreshToken(t *testing.T) {
	f := newFakeGoogle(t)
	path := filepath.Join(t.TempDir(), "token.json")

	// An already-expired access token forces a refresh on first use.
	if err := SaveToken(path, &oauth2.Token{
		AccessToken:  "stale-access",
		RefreshToken: "refresh-1",
		TokenType:    "Bearer",
		Expiry:       time.Now().Add(-time.Hour),
	}); err != nil {
		t.Fatal(err)
	}

	f.mu.Lock()
	f.nextAccessTok, f.nextRefreshTok = "access-2", "refresh-2"
	f.mu.Unlock()

	ctx := context.Background()
	ts, err := TokenSource(ctx, f.config(), path)
	if err != nil {
		t.Fatalf("TokenSource: %v", err)
	}
	tok, err := ts.Token()
	if err != nil {
		t.Fatalf("Token: %v", err)
	}
	if tok.AccessToken != "access-2" {
		t.Fatalf("access token = %q, want access-2", tok.AccessToken)
	}

	onDisk, err := LoadToken(path)
	if err != nil {
		t.Fatal(err)
	}
	if onDisk.RefreshToken != "refresh-2" {
		t.Fatalf("rotated refresh token not persisted: on disk %q, want refresh-2", onDisk.RefreshToken)
	}
	f.mu.Lock()
	sent := append([]string(nil), f.refreshTokens...)
	f.mu.Unlock()
	if len(sent) != 1 || sent[0] != "refresh-1" {
		t.Fatalf("refresh request sent %v, want [refresh-1]", sent)
	}

	// A second call reuses the cached access token: no extra refresh, and the
	// file must not be rewritten with a stale value.
	if _, err := ts.Token(); err != nil {
		t.Fatal(err)
	}
	if _, tokenCalls, _ := f.stats(); tokenCalls != 1 {
		t.Fatalf("token endpoint hit %d times, want 1 (the reuse source must cache)", tokenCalls)
	}
	onDisk, _ = LoadToken(path)
	if onDisk.RefreshToken != "refresh-2" {
		t.Fatalf("token file regressed to %q", onDisk.RefreshToken)
	}
}

// When Google keeps the same refresh token, the file must be left alone.
func TestTokenSourceKeepsUnrotatedToken(t *testing.T) {
	f := newFakeGoogle(t)
	path := filepath.Join(t.TempDir(), "token.json")
	if err := SaveToken(path, &oauth2.Token{
		AccessToken:  "stale",
		RefreshToken: "refresh-1",
		TokenType:    "Bearer",
		Expiry:       time.Now().Add(-time.Hour),
	}); err != nil {
		t.Fatal(err)
	}
	before, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}

	// Google's refresh responses normally omit refresh_token entirely.
	f.mu.Lock()
	f.nextRefreshTok = ""
	f.nextAccessTok = "access-2"
	f.mu.Unlock()

	ts, err := TokenSource(context.Background(), f.config(), path)
	if err != nil {
		t.Fatal(err)
	}
	tok, err := ts.Token()
	if err != nil {
		t.Fatal(err)
	}
	// oauth2 carries the old refresh token forward when the response omits it.
	if tok.RefreshToken != "refresh-1" {
		t.Fatalf("refresh token = %q, want refresh-1 carried forward", tok.RefreshToken)
	}
	after, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if !after.ModTime().Equal(before.ModTime()) {
		t.Fatal("token file was rewritten even though nothing rotated")
	}
	onDisk, _ := LoadToken(path)
	if onDisk.RefreshToken != "refresh-1" {
		t.Fatalf("token file corrupted: %q", onDisk.RefreshToken)
	}
}

func TestLoadTokenErrors(t *testing.T) {
	dir := t.TempDir()

	missing := filepath.Join(dir, "nope.json")
	if _, err := LoadToken(missing); !errors.Is(err, ErrNoToken) {
		t.Fatalf("missing file: err = %v, want ErrNoToken", err)
	}
	if HasToken(missing) {
		t.Fatal("HasToken lied about a missing file")
	}

	// Present but with no refresh token: unusable, so ErrNoToken as well —
	// the server must print "run `tally auth`", not fail later mid-sync.
	empty := filepath.Join(dir, "empty.json")
	if err := os.WriteFile(empty, []byte(`{"access_token":"a"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadToken(empty); !errors.Is(err, ErrNoToken) {
		t.Fatalf("refresh-token-less file: err = %v, want ErrNoToken", err)
	}

	garbage := filepath.Join(dir, "garbage.json")
	if err := os.WriteFile(garbage, []byte(`{`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadToken(garbage); err == nil || errors.Is(err, ErrNoToken) {
		t.Fatalf("garbage file: err = %v, want a parse error", err)
	}
}

func TestOAuthConfigUsesGoogleDeviceEndpoint(t *testing.T) {
	cfg := OAuthConfig("id", "secret")
	if cfg.Endpoint.DeviceAuthURL == "" {
		t.Fatal("google.Endpoint has no DeviceAuthURL")
	}
	if u, err := url.Parse(cfg.Endpoint.DeviceAuthURL); err != nil || u.Host != "oauth2.googleapis.com" {
		t.Fatalf("DeviceAuthURL = %q", cfg.Endpoint.DeviceAuthURL)
	}
	if len(cfg.Scopes) != 1 || cfg.Scopes[0] != "https://www.googleapis.com/auth/drive.file" {
		t.Fatalf("scopes = %v, want exactly drive.file", cfg.Scopes)
	}
}
