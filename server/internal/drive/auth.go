// Package drive implements the Google Drive sync transport: RFC 8628 device
// authorization, refresh-token persistence, a thin Drive v3 client and the
// snapshot merge engine described in docs/ARCHITECTURE.md.
//
// Both peers (this server and the Flutter app) authenticate as the SAME
// Google user with the SAME OAuth client ("TVs and Limited Input devices")
// and the single scope drive.file. Service accounts cannot be used: they own
// no storage quota, so every upload would fail with 403 storageQuotaExceeded.
package drive

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"path/filepath"
	"sync"
	"time"

	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"google.golang.org/api/drive/v3"
)

// Scope is the one scope both peers request. It is non-sensitive, so a
// self-hoster can publish their consent screen without a verification review.
const Scope = drive.DriveFileScope

// ErrNoToken is returned when TOKEN_PATH holds no usable refresh token.
var ErrNoToken = errors.New("drive: no saved token — run `tally auth`")

// OAuthConfig builds the shared installed-app OAuth config. google.Endpoint
// already carries DeviceAuthURL, so no URL is hardcoded here.
func OAuthConfig(clientID, clientSecret string) *oauth2.Config {
	return &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		Endpoint:     google.Endpoint,
		Scopes:       []string{Scope},
	}
}

// Prompt is called once with the verification URL and user code the human
// has to type on another device.
type Prompt func(verificationURI, userCode string, expiry time.Time)

// StdoutPrompt prints the device-flow instructions to w.
func StdoutPrompt(w io.Writer) Prompt {
	return func(uri, code string, expiry time.Time) {
		fmt.Fprintf(w, "\n  Open %s\n  Enter code: %s\n", uri, code)
		if !expiry.IsZero() {
			fmt.Fprintf(w, "  (the code expires at %s)\n", expiry.Local().Format(time.RFC1123))
		}
		fmt.Fprintln(w, "\n  Waiting for you to approve…")
	}
}

// Authorize runs the device flow to completion and persists the resulting
// token (refresh token included) at tokenPath with mode 0600.
//
// oauth2's DeviceAccessToken already implements RFC 8628 correctly: it honours
// the server-supplied interval, adds 5 s on slow_down, keeps polling on
// authorization_pending and returns on access_denied / expired_token.
func Authorize(ctx context.Context, cfg *oauth2.Config, tokenPath string, prompt Prompt) (*oauth2.Token, error) {
	da, err := cfg.DeviceAuth(ctx)
	if err != nil {
		return nil, fmt.Errorf("device authorization: %w", err)
	}
	if prompt != nil {
		prompt(da.VerificationURI, da.UserCode, da.Expiry)
	}
	tok, err := cfg.DeviceAccessToken(ctx, da)
	if err != nil {
		return nil, fmt.Errorf("device token exchange: %w", err)
	}
	if tok.RefreshToken == "" {
		return nil, errors.New("drive: Google returned no refresh token")
	}
	if err := SaveToken(tokenPath, tok); err != nil {
		return nil, err
	}
	return tok, nil
}

// SaveToken writes the token as JSON with mode 0600, creating the parent
// directory if needed. The write is atomic (temp file + rename) so a crash
// mid-write can never leave a truncated token behind.
func SaveToken(path string, t *oauth2.Token) error {
	b, err := json.MarshalIndent(t, "", "  ")
	if err != nil {
		return err
	}
	if dir := filepath.Dir(path); dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return fmt.Errorf("create token dir: %w", err)
		}
	}
	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o600); err != nil {
		return fmt.Errorf("write token: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		os.Remove(tmp)
		return fmt.Errorf("install token: %w", err)
	}
	// Rename preserves the temp file's mode on POSIX, but be explicit: an
	// existing file replaced by rename keeps the *new* inode's permissions.
	if err := os.Chmod(path, 0o600); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("chmod token: %w", err)
	}
	return nil
}

// LoadToken reads the token file. A missing or empty-refresh-token file
// yields ErrNoToken.
func LoadToken(path string) (*oauth2.Token, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, ErrNoToken
		}
		return nil, fmt.Errorf("read token %s: %w", path, err)
	}
	var t oauth2.Token
	if err := json.Unmarshal(b, &t); err != nil {
		return nil, fmt.Errorf("parse token %s: %w", path, err)
	}
	if t.RefreshToken == "" {
		return nil, ErrNoToken
	}
	return &t, nil
}

// HasToken reports whether a usable refresh token is on disk.
func HasToken(path string) bool {
	_, err := LoadToken(path)
	return err == nil
}

// persistingTokenSource re-saves the token file whenever Google rotates the
// refresh token, which it does periodically. Without this the server would
// keep using a refresh token Google has already retired and sync would die.
type persistingTokenSource struct {
	src  oauth2.TokenSource
	path string

	mu   sync.Mutex
	last string
}

func (p *persistingTokenSource) Token() (*oauth2.Token, error) {
	t, err := p.src.Token()
	if err != nil {
		return nil, err
	}
	if t.RefreshToken == "" {
		return t, nil
	}
	// The lock is held across the save so p.last can only ever advance to a
	// value that actually reached the disk.
	p.mu.Lock()
	defer p.mu.Unlock()
	if t.RefreshToken == p.last {
		return t, nil
	}
	if err := SaveToken(p.path, t); err != nil {
		// Not fatal for this pass — the access token in hand still works — but
		// it WILL break after the old refresh token is retired, and after a
		// restart the VPS would load a dead token. p.last deliberately stays
		// where it is so the very next Token() call retries the write.
		log.Printf("drive: could not persist rotated refresh token to %s: %v "+
			"(retrying on the next refresh; if this keeps failing, fix the volume "+
			"permissions or the server will need `tally auth` again after a restart)",
			p.path, err)
		return t, nil
	}
	p.last = t.RefreshToken
	return t, nil
}

// TokenSource returns an auto-refreshing token source that persists rotated
// refresh tokens back to tokenPath.
func TokenSource(ctx context.Context, cfg *oauth2.Config, tokenPath string) (oauth2.TokenSource, error) {
	tok, err := LoadToken(tokenPath)
	if err != nil {
		return nil, err
	}
	return TokenSourceFor(ctx, cfg, tokenPath, tok), nil
}

// TokenSourceFor is TokenSource for a token that has already been loaded, so a
// caller that needs to inspect the file first does not have to read it twice.
func TokenSourceFor(ctx context.Context, cfg *oauth2.Config, tokenPath string, tok *oauth2.Token) oauth2.TokenSource {
	p := &persistingTokenSource{
		src:  cfg.TokenSource(ctx, tok),
		path: tokenPath,
		last: tok.RefreshToken,
	}
	return oauth2.ReuseTokenSource(nil, p)
}
