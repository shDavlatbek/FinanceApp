# Tally — Architecture & Contracts

This document is the **binding contract** between the Flutter app and the Go server (which runs the Telegram bot). Do not deviate from field names, types, or semantics defined here.

> **v2 (2026-08-19)** — the bespoke REST sync API is gone. Both peers now sync through **Google Drive**. The app and the bot are equal peers; neither talks to the other directly.

## System overview

```
        ┌──────────── your Google Drive ────────────┐
        │  Tally/                                    │
        │    tally-<deviceA>.json   (phone snapshot) │
        │    tally-<deviceB>.json   (bot snapshot)   │
        └────────▲────────────────────────▲──────────┘
                 │ drive.file             │ drive.file
        ┌────────┴────────┐      ┌────────┴─────────────┐
        │  Flutter app    │      │  Go server           │
        │  Drift/SQLite   │      │  SQLite + Telegram   │
        │  offline-first  │      │  bot, headless       │
        └─────────────────┘      └──────────────────────┘
```

- **Local-first**: each peer's SQLite is the source of truth for its own UI. Every write lands locally first; Drive sync is opportunistic. The app is fully functional with **no Drive connected** (standalone mode).
- **Single writer per file**: a peer only ever writes its own snapshot file, so two peers can never conflict on one file. Convergence comes from every peer reading every other peer's file and merging.
- **Single user**: one Google account, one OAuth client, one Telegram allow-list.
- **One currency**, amounts stored as **integer minor units**.

## Data model

All rows carry a client-generated UUIDv4 `id`, `updated_at_ms` (int64, unix ms), and nullable `deleted_at_ms` (tombstone soft-delete; tombstones are never purged). Each peer also keeps a local-only `dirty` flag, which is never serialized to Drive.

### transaction
| field | type | notes |
|---|---|---|
| id | string uuid | |
| kind | `"income"` \| `"expense"` | |
| amount_minor | int64 > 0 | minor units, always positive; sign implied by kind |
| category_id | string uuid | FK → category |
| note | string | may be empty |
| occurred_at | string RFC3339 UTC | canonical `…Z` form; normalize on write |
| source | `"app"` \| `"telegram"` | |
| created_at_ms | int64 | |
| updated_at_ms | int64 | |
| deleted_at_ms | int64 \| null | |

### category
| field | type | notes |
|---|---|---|
| id | string uuid | |
| name | string | canonical name; see **Seed category naming** |
| emoji | string | single emoji used as icon |
| color | string | `#RRGGBB` |
| kind | `"income"` \| `"expense"` | |
| sort_order | int | |
| updated_at_ms | int64 | |
| deleted_at_ms | int64 \| null | |

### settings (singleton, id = `"settings"`)
| field | type | notes |
|---|---|---|
| id | `"settings"` | fixed |
| currency | string ISO-4217 | default `"USD"` |
| language | `""` \| `"en"` \| `"ru"` \| `"uz"` | **NEW in v2.** `""` = follow the device/Telegram locale |
| updated_at_ms | int64 | |

`language` is synced deliberately: it is how the phone tells the Telegram bot which language to reply in.

### Seed categories — FIXED UUIDs

Both peers seed these **identical** rows on first run so they merge cleanly on first sync. `updated_at_ms` for seeded **categories** is fixed at `1755000000000`.

The seeded **settings** row is the exception: it is written with `updated_at_ms = 0`. A fixed non-zero seed would tie with the other peer's identical seed, and under strict LWW a tie keeps the local row — so neither peer could ever accept the other's currency or language until something else edited the row. Zero loses to every real value in both directions, and rows with `updated_at_ms == 0` are never published to peers.

| id | name | emoji | color | kind | sort |
|---|---|---|---|---|---|
| `c1a7e2f0-0001-4a00-9000-000000000001` | Groceries | 🛒 | #4CAF7D | expense | 0 |
| `c1a7e2f0-0002-4a00-9000-000000000002` | Cafe | ☕ | #E8935A | expense | 1 |
| `c1a7e2f0-0003-4a00-9000-000000000003` | Transport | 🚕 | #5A9BE8 | expense | 2 |
| `c1a7e2f0-0004-4a00-9000-000000000004` | Home | 🏠 | #9B7DE8 | expense | 3 |
| `c1a7e2f0-0005-4a00-9000-000000000005` | Utilities | 💡 | #E8C95A | expense | 4 |
| `c1a7e2f0-0006-4a00-9000-000000000006` | Health | 💊 | #E85A7A | expense | 5 |
| `c1a7e2f0-0007-4a00-9000-000000000007` | Shopping | 🛍️ | #D45AE8 | expense | 6 |
| `c1a7e2f0-0008-4a00-9000-000000000008` | Fun | 🎮 | #5AE8D4 | expense | 7 |
| `c1a7e2f0-0009-4a00-9000-000000000009` | Subscriptions | 📱 | #7A8BE8 | expense | 8 |
| `c1a7e2f0-000a-4a00-9000-00000000000a` | Travel | ✈️ | #5AC8E8 | expense | 9 |
| `c1a7e2f0-000b-4a00-9000-00000000000b` | Other | 📦 | #8E8E93 | expense | 10 |
| `c1a7e2f0-0101-4a00-9000-000000000101` | Salary | 💼 | #4CAF7D | income | 0 |
| `c1a7e2f0-0102-4a00-9000-000000000102` | Freelance | 💻 | #5A9BE8 | income | 1 |
| `c1a7e2f0-0103-4a00-9000-000000000103` | Gifts | 🎁 | #E8935A | income | 2 |
| `c1a7e2f0-0104-4a00-9000-000000000104` | Other income | ➕ | #8E8E93 | income | 3 |

### Seed category naming (i18n)

Category `name` is user data and stays **canonical English** in the database. For display, a peer localizes a seed category **only while the user has not renamed it**:

```
displayName(c) = (isSeedId(c.id) && c.name == canonicalSeedName(c.id))
                   ? localized(seedNameKey(c.id))
                   : c.name
```

Renaming a category in the UI writes the literal new name, and from then on it displays verbatim in every language. Both the app and the bot implement this rule identically.

## Google Drive sync

### Auth — one OAuth client, device flow, on both peers

Both the app and the server authenticate as **the same Google user**, using **the same OAuth client ID** (Google Cloud console type: **"TVs and Limited Input devices"**) and the single scope:

```
https://www.googleapis.com/auth/drive.file
```

Rationale, all load-bearing:

- **Service accounts are impossible here.** Google: *"Service accounts don't have storage quota and can't own any files. Instead, they must upload files and folders into shared drives, or use OAuth 2.0 to upload items on behalf of a human user."* Shared drives are Workspace-only, so a self-hoster on a free Gmail account cannot use one. Any service-account design returns `403 storageQuotaExceeded` on first upload.
- **`drive.file` is a non-sensitive scope**, so a self-hoster can publish their consent screen without going through Google verification. Every broader Drive scope is *restricted* and would force each self-hoster through a verification review.
- **`drive.file` grants per-file access to "files created or opened by the app".** Whether "the app" means the client ID or the Cloud project is **not documented**. Using one client ID for both peers makes the question moot — same client + same user is unambiguously the same app. It also removes all Android/iOS native OAuth configuration: no SHA-1 registration (which would otherwise differ for every self-hoster's signing key), no `Info.plist` entries, and no `google_sign_in` dependency.
- **The device flow is the only headless-capable flow.** The OOB copy-paste flow was fully disabled in 2023, and the loopback flow needs a browser on the same host, which a VPS does not have. `drive.file` is one of the six scopes the device flow supports.

Device authorization (identical on both peers):

1. `POST https://oauth2.googleapis.com/device/code` with `client_id`, `scope` → `device_code`, `user_code`, `verification_url`, `interval`, `expires_in`.
2. Show the user `verification_url` + `user_code`.
3. Poll `POST https://oauth2.googleapis.com/token` with `grant_type=urn:ietf:params:oauth:grant-type:device_code`, `device_code`, `client_id`, `client_secret`. Honour `authorization_pending` (keep waiting) and `slow_down` (add 5 s to the interval). Fail on `access_denied` / `expired_token`.
4. Persist the returned **refresh token**. The app stores it in its local meta table; the server writes it to `TOKEN_PATH` with mode 0600.
5. Refresh tokens rotate: whenever a refresh returns a new refresh token, persist it.

The client secret ships in both peers. That is expected for installed apps — Google does not treat installed-app secrets as confidential, and each self-hoster uses their own client anyway.

**README must state:** the OAuth consent screen has to be set to **"In production"**. While it is in "Testing", Google issues refresh tokens that **expire after 7 days**, and sync silently dies a week after setup. Because `drive.file` is non-sensitive, publishing needs no verification review.

### Drive layout

A folder named `Tally` in the account's Drive root (`'root' in parents`), found by name query and created if absent. Each peer caches the resolved folder id locally.

One snapshot file per peer, named `tally-<device_id>.json`, mime `application/json`, stored uncompressed so the user can read their own data in the Drive UI.

```json
{
  "schema": 1,
  "device_id": "b2c3…",
  "device_name": "Pixel 7",
  "written_at_ms": 1787160000000,
  "categories":   [ Category… ],
  "transactions": [ Transaction… ],
  "settings":     Settings
}
```

The snapshot is a **full dump of that peer's current local state**, tombstones included. Publishing everything (rather than a delta) keeps the merge trivially idempotent and self-healing: a peer that has been offline for months still converges in one pass, and a lost snapshot file costs nothing because every other peer republishes what it knows.

### Sync algorithm

One `syncNow()` pass:

1. **Ensure auth.** No refresh token → status `notConfigured`, stop.
2. **Resolve folder id** (cached; re-resolve if the cached id 404s).
3. **List** `tally-*.json` in the folder, requesting `files(id,name,modifiedTime,md5Checksum)`.
4. **Download** every file except this peer's own, skipping any whose `md5Checksum` equals the one recorded locally for that file id.
5. **Merge** all downloaded rows into the local DB in a single transaction, using **strict last-write-wins**: an incoming row is applied iff it does not exist locally OR `incoming.updated_at_ms > local.updated_at_ms`. Ties keep the local row. Merged rows are written with `dirty = false`.
6. **Publish** this peer's own snapshot if any local row is dirty, or if the snapshot has never been uploaded. Create the file if absent, else update its content by id.
7. **Clear dirty** only on rows whose `updated_at_ms` is unchanged since the snapshot was serialized (rows edited mid-sync stay dirty for the next pass).
8. **Persist** the per-file md5 map and the last-success timestamp.

Merge is commutative and idempotent, so pass order between peers never matters.

Triggers — app: launch, resume, after each local write (3 s debounce), pull-to-refresh, manual button. Server: startup, after each bot write (3 s debounce), and a **poll every `SYNC_INTERVAL_SECONDS`** (default 60). The poll is not optional: with no server API, polling is the only way the bot notices transactions entered on the phone.

### Errors and retry

Retry on `429`, `500`, `502`, `503`, `504`, and on a `403` whose reason is `rateLimitExceeded` / `userRateLimitExceeded`. Never retry `400`, `401`, `404`, or `403 storageQuotaExceeded`. Exponential backoff with jitter, capped around 32 s. Treat `401` as "refresh token revoked → re-authorize", surfaced to the user, not as a transient failure.

Status model (unchanged, so the existing UI keeps working): `notConfigured | idle | syncing | offline | error(message)`.

## Telegram bot

Unchanged in behaviour, plus localization. It writes to the server's local SQLite and lets the Drive sync carry entries to the phone.

### Message grammar
```
250 groceries weekly stuff     → expense 250.00, category≈Groceries, note "weekly stuff"
250.50 taxi                    → decimals via . or ,
+50000 salary                  → leading + means income
120                            → amount only → inline keyboard to pick category
```
- Amount: first token; `+` prefix → income; `.` or `,` decimal separator; reject ≤ 0 or non-numeric with a localized hint.
- Category resolution order: alias table → exact name → name prefix → fuzzy (Levenshtein ≤ 2), matched against non-deleted categories of that kind. Matching considers **both** the canonical English name and the localized display name in every supported language, so `продукты` and `groceries` both hit Groceries.
- No confident match → inline keyboard of that kind's categories (localized labels) plus a "new category" button; the picked word is saved to the alias table.
- Rest of the message → note.
- Success reply: localized, e.g. `✅ −250,00 ₽ • 🛒 Продукты — 3 450,00 за месяц`.

### Commands
`/start`, `/today`, `/week`, `/month`, `/undo`, `/categories` — all output localized.

### Bot language resolution

```
settings.language (if non-empty)  →  Telegram user.language_code  →  English
```

Normalize the Telegram code by **base language only, with an explicit switch** (`ru`→ru, `uz`→uz including `uz-Cyrl`, `en`→en, everything else → en). Do **not** use `language.NewMatcher`: it silently maps Kazakh to Russian and, worse, maps `uz-Cyrl` to Russian.

## Internationalization

Languages: **English (source), Russian, Uzbek**. Locale tags are plain `en`, `ru`, `uz` — no script or region suffixes. Uzbek is Latin script; `flutter_localizations` and `intl` both ship `uz` data.

### App

- `flutter gen-l10n` with ARB files at `lib/l10n/arb/app_{en,ru,uz}.arb`, `template-arb-file: app_en.arb`, `generate: true` in pubspec, `nullable-getter: false`.
- **Do not enable `use-escaping`** — Uzbek text is full of apostrophes (`Oʻzbekcha`, `so'm`) and escaping turns them into breakage.
- `AppLocalizations.localizationsDelegates` already includes the Material/Cupertino/Widgets global delegates; wire `supportedLocales: AppLocalizations.supportedLocales` into `MaterialApp.router`.
- Russian needs the full CLDR plural set (`one`/`few`/`many`/`other`); Uzbek and English need `one`/`other`.
- The chosen locale drives money and date formatting: pass the locale explicitly to `NumberFormat`/`DateFormat` rather than relying on the ambient default.
- Language preference lives in the **synced** `settings.language` (not local meta), because the bot reads it. `""` means follow the device locale.

### Bot

- `go-i18n/v2` with embedded TOML catalogs at `internal/i18n/locales/{en,ru,uz}.toml`, so a translator can contribute without touching Go.
- Money is formatted by hand from integer minor units with per-locale separators and symbol placement. `golang.org/x/text`'s currency formatter is pinned to CLDR 32 and places the ruble symbol wrongly (`₽ 1 234,56` instead of `1 234,56 ₽`), and its number printer defaults to scientific notation — do not use it for user-facing money.
- Dates use per-locale `time` layouts; Go's stdlib has no localized month names, so any month-name output uses a small per-locale table.

## Go server layout

```
server/
  main.go                    env, db, drive sync loop, bot, health server; `tally auth` subcommand
  internal/store/            sqlite (modernc), schema+migration, LWW apply, queries
  internal/drive/            device-flow auth, token persistence, Drive v3 client, snapshot sync
  internal/i18n/             go-i18n bundle, locales/*.toml, money/date formatting
  internal/api/              health endpoint ONLY (for the container healthcheck)
  internal/bot/              telegram long-poll bot, parser, matcher, localized formatting
  internal/model/            shared structs + JSON tags exactly as above
  Dockerfile
```

Env vars:

| var | required | meaning |
|---|---|---|
| `GOOGLE_CLIENT_ID` | yes | OAuth client ("TVs and Limited Input devices") |
| `GOOGLE_CLIENT_SECRET` | yes | same client's secret |
| `TOKEN_PATH` | no | refresh-token file, default `/data/google-token.json` |
| `DRIVE_FOLDER_NAME` | no | default `Tally` |
| `SYNC_INTERVAL_SECONDS` | no | Drive poll interval, default `60` |
| `TELEGRAM_BOT_TOKEN` | for bot | empty → sync-only mode, no bot |
| `TELEGRAM_ALLOWED_USER_IDS` | for bot | comma-separated numeric ids |
| `PORT` | no | health server, default `8080` |
| `DB_PATH` | no | default `/data/tally.db` |
| `DEFAULT_CURRENCY` | no | default `USD`; applied on change, so it never clobbers a currency picked in the app |
| `TZ` | no | IANA zone (e.g. `Asia/Tashkent`) used for the bot's `/today` `/week` `/month` boundaries, default UTC. Falls back to `TIMEZONE`. Without it, "today" means UTC today, which is wrong for anyone not on UTC. |

`tally auth` runs the device flow interactively (`docker compose run --rm tally auth`) and writes the token file. The server refuses to start syncing without it, but still runs the bot and health endpoint, logging a clear "run `tally auth`" message.

## Flutter app layout

```
app/lib/
  main.dart
  l10n/arb/app_{en,ru,uz}.arb
  core/                      theme, money, dates, constants, seed-name localization
  data/db/                   drift tables + database (+ meta key/value)
  data/repo/                 transactions, categories, settings, summaries
  data/drive/                device-flow auth client, Drive REST client, DriveSyncEngine
  features/…                 home, entry, history, stats, categories, settings, shell, common
```

Meta keys (local only, never synced): `google_refresh_token`, `drive_folder_id`, `device_id`, `device_name`, `drive_peer_md5` (JSON map of file id → md5), `last_sync_ms`, `ui_theme_mode`.

The Drive engine keeps the existing public surface — `syncNow()`, `scheduleSync()`, `statusStream`, `lastSyncMsStream`, `isConfigured` — so the rest of the app is unaffected by the transport change.
