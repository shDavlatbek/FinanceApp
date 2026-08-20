// Tally server: Telegram bot + SQLite + Google Drive sync, one binary.
//
//	tally        run the bot, the Drive sync loop and the health endpoint
//	tally auth   run the Google device-authorization flow once, then exit
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
	// Embeds the IANA timezone database so TZ works even on an image without
	// tzdata installed. It is only consulted when the system database is
	// missing, so a container that does ship tzdata is unaffected.
	_ "time/tzdata"

	"github.com/xensa/tally/internal/api"
	"github.com/xensa/tally/internal/bot"
	"github.com/xensa/tally/internal/drive"
	"github.com/xensa/tally/internal/store"
)

const version = "2.0.0"

func main() {
	log.SetFlags(log.LstdFlags | log.LUTC)
	if len(os.Args) > 1 {
		if os.Args[1] != "auth" {
			log.Fatalf("unknown command %q (usage: tally [auth])", os.Args[1])
		}
		runAuth()
		return
	}
	runServer()
}

// ---------------------------------------------------------------------------
// tally auth
// ---------------------------------------------------------------------------

// runAuth performs the RFC 8628 device flow interactively and writes the
// refresh token to TOKEN_PATH. Meant to be run once:
//
//	docker compose run --rm tally auth
func runAuth() {
	cfg := driveConfig()
	if !cfg.Valid() {
		log.Fatal("GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET are required for `tally auth`")
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	oauthCfg := drive.OAuthConfig(cfg.ClientID, cfg.ClientSecret)
	if _, err := drive.Authorize(ctx, oauthCfg, cfg.TokenPath, drive.StdoutPrompt(os.Stdout)); err != nil {
		log.Fatalf("authorization failed: %v", err)
	}
	log.Printf("authorized — refresh token saved to %s", cfg.TokenPath)
	log.Print("reminder: the OAuth consent screen must be set to \"In production\"; " +
		"while it is in \"Testing\", Google expires refresh tokens after 7 days")
}

// ---------------------------------------------------------------------------
// tally (normal startup)
// ---------------------------------------------------------------------------

func runServer() {
	port := envDefault("PORT", "8080")
	dbPath := envDefault("DB_PATH", "/data/tally.db")
	configuredCurrency := envCurrency()
	currency := configuredCurrency
	if currency == "" {
		currency = "USD"
	}
	botToken := os.Getenv("TELEGRAM_BOT_TOKEN")
	allowedIDs, err := parseIDs(os.Getenv("TELEGRAM_ALLOWED_USER_IDS"))
	if err != nil {
		log.Fatalf("TELEGRAM_ALLOWED_USER_IDS: %v", err)
	}
	syncInterval := envDuration("SYNC_INTERVAL_SECONDS", drive.DefaultInterval)
	loc := envLocation()
	log.Printf("calendar: cutting /today, /week and /month on %s", loc)

	st, err := store.Open(dbPath, currency)
	if err != nil {
		log.Fatalf("open store at %s: %v", dbPath, err)
	}
	defer st.Close()

	// DEFAULT_CURRENCY has to be reconciled on every boot, not just seeded on
	// an empty database: an operator who edits it in .env and restarts would
	// otherwise get a silent no-op while the bot keeps using the old currency's
	// exponent and symbol. Applying it at "now" also carries it to the phone
	// through the normal LWW sync.
	switch applied, err := st.ApplyDefaultCurrency(configuredCurrency, time.Now().UTC().UnixMilli()); {
	case err != nil:
		log.Printf("warning: could not apply DEFAULT_CURRENCY=%s: %v", configuredCurrency, err)
	case applied:
		log.Printf("settings: DEFAULT_CURRENCY=%s applied and queued for sync to the app", configuredCurrency)
	}
	if s, err := st.Settings(); err == nil {
		log.Printf("settings: currency %s, language %q", s.Currency, s.Language)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// Google Drive sync. The server always starts, token or not: the bot and
	// the health endpoint must keep working while the owner gets around to
	// running `tally auth`.
	driveCfg := driveConfig()
	engine := drive.NewEngine(st, driveCfg)
	syncDone := make(chan struct{})
	switch {
	case !driveCfg.Valid():
		close(syncDone)
		log.Print("drive: GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET not set — sync disabled, running local-only")
	case !engine.IsConfigured():
		close(syncDone)
		log.Printf("drive: no refresh token at %s — sync disabled.", driveCfg.TokenPath)
		log.Print("drive: run `docker compose run --rm tally auth` once to connect Google Drive")
	default:
		// Every local (bot) write schedules a debounced publish.
		st.SetWriteHook(engine.ScheduleSync)
		go func() {
			defer close(syncDone)
			log.Printf("drive: syncing folder %q every %s", driveCfg.FolderName, syncInterval)
			engine.Run(ctx, syncInterval)
		}()
	}

	// Telegram bot (optional: empty token → sync-only mode).
	botDone := make(chan struct{})
	if botToken == "" {
		log.Print("TELEGRAM_BOT_TOKEN empty — running in sync-only mode (no bot)")
		close(botDone)
	} else {
		if len(allowedIDs) == 0 {
			log.Print("warning: TELEGRAM_ALLOWED_USER_IDS is empty — the bot will ignore everyone")
		}
		tb, err := bot.New(botToken, allowedIDs, st, loc)
		if err != nil {
			log.Fatalf("start telegram bot: %v", err)
		}
		go func() {
			defer close(botDone)
			log.Print("telegram bot: long polling started")
			tb.Run(ctx)
		}()
	}

	// Health server. It exists only for the container healthcheck; nothing is
	// accepted over HTTP any more, so compose need not publish this port.
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           api.New(version),
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		log.Printf("http: health endpoint on :%s/api/health", port)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("http: %v", err)
		}
	}()

	<-ctx.Done()
	log.Print("shutting down…")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Printf("http shutdown: %v", err)
	}
	for _, done := range []chan struct{}{botDone, syncDone} {
		select {
		case <-done:
		case <-shutdownCtx.Done():
		}
	}
	log.Print("bye")
}

func driveConfig() drive.Config {
	return drive.Config{
		ClientID:     os.Getenv("GOOGLE_CLIENT_ID"),
		ClientSecret: os.Getenv("GOOGLE_CLIENT_SECRET"),
		TokenPath:    envDefault("TOKEN_PATH", "/data/google-token.json"),
		FolderName:   envDefault("DRIVE_FOLDER_NAME", "Tally"),
	}
}

func envDefault(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

var currencyRe = regexp.MustCompile(`^[A-Z]{3}$`)

// envCurrency reads DEFAULT_CURRENCY, returning "" when the operator set none
// (which is not the same as setting it to USD: an explicitly configured value
// is written into the synced settings row, a missing one is not).
func envCurrency() string {
	raw := strings.ToUpper(strings.TrimSpace(os.Getenv("DEFAULT_CURRENCY")))
	if raw == "" {
		return ""
	}
	if !currencyRe.MatchString(raw) {
		log.Printf("DEFAULT_CURRENCY=%q is not a 3-letter ISO-4217 code — ignoring it", raw)
		return ""
	}
	return raw
}

// envLocation resolves the calendar the bot's /today, /week and /month
// boundaries are cut on, from TZ (the name Docker and every base image already
// use) or TIMEZONE. Default UTC, matching the previous behaviour.
//
// This exists because the Flutter app cuts the same periods at LOCAL midnight,
// so a bot pinned to UTC covers a different window than the phone's Home
// screen — by five hours in Uzbekistan, three in Russia.
func envLocation() *time.Location {
	for _, key := range []string{"TZ", "TIMEZONE"} {
		name := strings.TrimSpace(os.Getenv(key))
		if name == "" {
			continue
		}
		loc, err := time.LoadLocation(name)
		if err != nil {
			log.Printf("%s=%q is not a known IANA timezone (%v) — using UTC", key, name, err)
			return time.UTC
		}
		return loc
	}
	return time.UTC
}

// envDuration reads a whole-second duration, falling back to def on an empty
// or unparseable value (a typo must not silently disable the Drive poll).
func envDuration(key string, def time.Duration) time.Duration {
	raw := os.Getenv(key)
	if raw == "" {
		return def
	}
	n, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil || n <= 0 {
		log.Printf("%s=%q is not a positive number of seconds — using %s", key, raw, def)
		return def
	}
	return time.Duration(n) * time.Second
}

func parseIDs(s string) ([]int64, error) {
	var out []int64
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		id, err := strconv.ParseInt(part, 10, 64)
		if err != nil {
			return nil, err
		}
		out = append(out, id)
	}
	return out, nil
}
