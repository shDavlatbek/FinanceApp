# Tally — Architecture & Contracts

This document is the **binding contract** between the Flutter app and the Go server (which runs the Telegram bot). Do not deviate from field names, types, or semantics defined here.

> **v2 (2026-08-19)** — the bespoke REST sync API is gone. Both peers now sync through **Google Drive**. The app and the bot are equal peers; neither talks to the other directly.
>
> **v3 (2026-08-20)** — **accounts**. Money now sits somewhere: cash, a card, savings, investments. Every transaction names the account it moves through, and a third transaction kind, `transfer`, moves money between two of the owner's own accounts without touching any income or expense total. Snapshot schema goes to **2**. Also adds file **export/import**, which reuses the snapshot format rather than inventing a second one.

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
- **Every transaction belongs to an account.** Balances are derived, never stored: an account's balance is its opening balance plus everything logged against it. There is no running-total column to drift out of step with the rows.

## Data model

All rows carry a client-generated UUIDv4 `id`, `updated_at_ms` (int64, unix ms), and nullable `deleted_at_ms` (tombstone soft-delete; tombstones are never purged). Each peer also keeps a local-only `dirty` flag, which is never serialized to Drive.

### transaction
| field | type | notes |
|---|---|---|
| id | string uuid | |
| kind | `"income"` \| `"expense"` \| `"transfer"` | |
| amount_minor | int64 > 0 | minor units, always positive; sign implied by kind |
| category_id | string uuid | FK → category. **Empty for a transfer** |
| account_id | string uuid | FK → account. Money leaves it on an expense, arrives on an income, and is the **source** of a transfer |
| to_account_id | string uuid | FK → account. The **destination** of a transfer; **empty for every other kind** |
| note | string | may be empty |
| occurred_at | string RFC3339 UTC | canonical `…Z` form; normalize on write |
| source | `"app"` \| `"telegram"` | |
| created_at_ms | int64 | |
| updated_at_ms | int64 | |
| deleted_at_ms | int64 \| null | |

**Transfers are not spending.** `income` and `expense` totals, the category breakdown and the transaction count all ignore `kind = "transfer"` on both peers. Moving 500 000 from a card into savings must leave the month's "spent" figure exactly where it was — otherwise saving money would look like losing it, which is the one thing this feature must never do.

A transfer is a **single row**, not a matched pair of an expense and an income. One row cannot half-arrive under last-write-wins, cannot be edited into an unbalanced state, and cannot be half-deleted; a pair could do all three.

### account
| field | type | notes |
|---|---|---|
| id | string uuid | |
| name | string | canonical name; see **Seed account naming** |
| kind | `"cash"` \| `"bank"` \| `"savings"` \| `"investment"` | presentation and grouping only — every account holds money the same way |
| emoji | string | single emoji used as icon |
| color | string | `#RRGGBB` |
| opening_balance_minor | int64 | what the account already held before tracking started. **May be negative** (a card in debt) |
| sort_order | int | |
| updated_at_ms | int64 | |
| deleted_at_ms | int64 \| null | |

`kind` carries no arithmetic: savings and investments are ordinary accounts, so "send to savings" is just a transfer into one. Keeping the behaviour identical is what makes the feature small — there is no second money-movement path to keep in step with the first.

A **balance is derived**, on both peers, by exactly this rule:

```
balance(a) = a.opening_balance_minor
           + Σ amount_minor  where kind = 'income'   and account_id    = a.id
           - Σ amount_minor  where kind = 'expense'  and account_id    = a.id
           + Σ amount_minor  where kind = 'transfer' and to_account_id = a.id
           - Σ amount_minor  where kind = 'transfer' and account_id    = a.id
```

summed over non-deleted transactions only. Archiving an account tombstones it but leaves its transactions pointing at it: history must not lose entries because a wallet was closed.

Investment gains are **not** a separate concept. A rise in value is logged as income into the investment account; a fall, as an expense out of it. That reuses categories, summaries and the bot unchanged rather than adding a valuation model nothing else understands.

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
| default_account_id | string uuid | **NEW in v3.** FK → account; the account the bot books to |
| updated_at_ms | int64 | |

`language` is synced deliberately: it is how the phone tells the Telegram bot which language to reply in.

`default_account_id` is synced for the same reason: the bot must not ask which account a message belongs to — that would cost the 3-second promise — so the choice is made once in the app and travels to the bot.

An **empty** `default_account_id` means "unchanged", never "cleared". A peer that predates v3 sends the field absent, and reading that literally would strip an account the owner had deliberately picked; the merge therefore keeps the local value, falling back to the seed cash account only when there is no local value at all. If the named account has since been archived, a peer resolves the default to its first live account rather than writing into a hole.

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

### Seed accounts — FIXED UUIDs

Seeded on first run by both peers, with `updated_at_ms` fixed at `1755000000000`, exactly like the seed categories. `opening_balance_minor` seeds to `0` on all four.

| id | name | emoji | color | kind | sort |
|---|---|---|---|---|---|
| `a1c7e2f0-0001-4a00-9000-000000000001` | Cash | 💵 | #4CAF7D | cash | 0 |
| `a1c7e2f0-0002-4a00-9000-000000000002` | Card | 💳 | #5A9BE8 | bank | 1 |
| `a1c7e2f0-0003-4a00-9000-000000000003` | Savings | 🏦 | #E8C95A | savings | 2 |
| `a1c7e2f0-0004-4a00-9000-000000000004` | Investments | 📈 | #9B7DE8 | investment | 3 |

**Cash is the default account**: `settings.default_account_id` seeds to `a1c7e2f0-0001-4a00-9000-000000000001`, and it is where a peer books any transaction that arrives without a usable `account_id`.

Savings and investments are seeded rather than left to the user because "send to savings" has to work on a fresh install without a setup step.

### Seed account naming (i18n)

Identical to the category rule below. The bot's catalog keys are `acc_*`; the app's ARB keys are `seedAccount*` (`seedAccountCash`, `seedAccountCard`, `seedAccountSavings`, `seedAccountInvestments`). Both peers must localize the same rows to the same names, or the phone and the bot will call one seed account two different things:

```
displayName(a) = (isSeedAccountId(a.id) && a.name == canonicalSeedAccountName(a.id))
                   ? localized(seedAccountNameKey(a.id))
                   : a.name
```

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
  "schema": 2,
  "device_id": "b2c3…",
  "device_name": "Pixel 7",
  "written_at_ms": 1787160000000,
  "accounts":     [ Account… ],
  "categories":   [ Category… ],
  "transactions": [ Transaction… ],
  "settings":     Settings
}
```

**Schema 2 adds `accounts`.** A peer writes schema 2 and reads schema 1 and 2, because an un-upgraded device keeps publishing schema 1 and refusing to read it would strand it. A schema-1 snapshot carries no `accounts` array and no `account_id` on its transactions; the reader books every such row to the seed cash account, which is exactly where that peer's own migration puts its pre-accounts rows, so both sides reach the same answer without a round trip. Upgrade both peers: an un-upgraded reader rejects schema 2 outright.

Sanitizing rules specific to accounts, applied to every peer file because it is untrusted input:

- an account with an empty id or name, a malformed `color`, a `kind` outside the four, or `updated_at_ms <= 0` is skipped;
- a transfer with no `to_account_id`, with `to_account_id == account_id`, or naming an account not present in that snapshot is skipped — a self-transfer nets to zero yet still shows money moving, and is only ever a hand-edit mistake;
- `to_account_id` set on an income or an expense is **cleared**, not skipped: the balance rule only reads that field on a transfer, so the row is still good data and dropping a real expense over an ignored field would be the worse bug;
- a `category_id` set on a **transfer** is likewise cleared, not fatal — the row is a real movement of money, it simply must not reach a category total;
- an unknown or absent `account_id` is rewritten to the seed cash account rather than dropping the transaction, because losing an entry is worse than misfiling one;
- an unknown `default_account_id` on the settings row is **cleared** (which already means "unchanged"), never a reason to drop the row — otherwise one bad account row elsewhere in the file would cost the peer its currency and language too.

**Order is load-bearing.** The `account_id` rewrite runs **before** the transfer rules. The other way round, a transfer whose source account is missing and whose destination is the seed cash account gets rewritten into `cash -> cash`: precisely the self-transfer the rules reject, waved through because the check had already run.

**Both peers sanitize per ROW, never per file.** A malformed row is dropped and reported; only an unreadable *envelope* (not JSON, no `schema`, a schema outside the readable range) rejects the whole file. The owner can hand-edit these files in the Drive UI, and one stray comma must not silently cost them every other row.

**`occurred_at` is validated on read, normalized on write.** A reader checks that it parses and otherwise leaves the bytes alone: Dart's `toIso8601String()` emits `…T09:30:00.000Z` where Go writes `…T09:30:00Z`, so re-normalizing on read would have each peer rewrite the other's rows on every merge. Period queries compare against fraction-free bounds precisely so both spellings sort correctly.

A **balance is computed as four independent summed terms**, never a single first-match `CASE`. With one `CASE`, a self-transfer would match the credit arm, never reach the debit arm, and invent money out of nothing. Summed, it nets to zero — so the arithmetic stays sound even for a row the sanitizer should have caught.

The snapshot is a **full dump of that peer's current local state**, tombstones included. Publishing everything (rather than a delta) keeps the merge trivially idempotent and self-healing: a peer that has been offline for months still converges in one pass, and a lost snapshot file costs nothing because every other peer republishes what it knows.

### Sync algorithm

One `syncNow()` pass:

1. **Ensure auth.** No refresh token → status `notConfigured`, stop.
2. **Resolve folder id** (cached; re-resolve if the cached id 404s).
3. **List** `tally-*.json` in the folder, requesting `files(id,name,modifiedTime,md5Checksum)`.
4. **Download** every file except this peer's own, skipping any whose `md5Checksum` equals the one recorded locally for that file id.
5. **Merge** all downloaded rows into the local DB in a single transaction, accounts first (so a transaction never lands in a pass before the account it names), using **strict last-write-wins**: an incoming row is applied iff it does not exist locally OR `incoming.updated_at_ms > local.updated_at_ms`. Ties keep the local row. Merged rows are written with `dirty = false`.
6. **Publish** this peer's own snapshot if any local row is dirty, or if the snapshot has never been uploaded. Create the file if absent, else update its content by id.
7. **Clear dirty** only on rows whose `updated_at_ms` is unchanged since the snapshot was serialized (rows edited mid-sync stay dirty for the next pass).
8. **Persist** the per-file md5 map and the last-success timestamp.

Merge is commutative and idempotent, so pass order between peers never matters.

Triggers — app: launch, resume, after each local write (3 s debounce), pull-to-refresh, manual button. Server: startup, after each bot write (3 s debounce), and a **poll every `SYNC_INTERVAL_SECONDS`** (default 60). The poll is not optional: with no server API, polling is the only way the bot notices transactions entered on the phone.

### Errors and retry

Retry on `429`, `500`, `502`, `503`, `504`, and on a `403` whose reason is `rateLimitExceeded` / `userRateLimitExceeded`. Never retry `400`, `401`, `404`, or `403 storageQuotaExceeded`. Exponential backoff with jitter, capped around 32 s. Treat `401` as "refresh token revoked → re-authorize", surfaced to the user, not as a transient failure.

Status model (unchanged, so the existing UI keeps working): `notConfigured | idle | syncing | offline | error(message)`.

## Export and import

The app can write its data to a file and read one back. Both directions reuse the **snapshot format above, unchanged** — a backup file *is* a peer snapshot. That is the whole design:

- export serializes the same full-state dump the Drive publisher already builds;
- import runs the same `ParseSnapshot` → sanitize → `MergeRemote` path a peer file goes through.

So there is one wire format, one parser, one sanitizer and one merge rule to keep correct, all of them already pinned by the shared interop fixture. A second bespoke backup format would be a second thing to get wrong.

### JSON backup — the restore path

File name `tally-backup-<YYYYMMDD-HHMMSS>.json`, mime `application/json`, uncompressed.

Import is a **merge under strict last-write-wins**, identical to a sync pass: a row in the file is applied iff it is unknown locally or its `updated_at_ms` is newer, and ties keep the local row. Consequences, all of them wanted:

- importing the same file twice changes nothing the second time (**idempotent**);
- importing a backup into a populated app cannot silently destroy newer work;
- tombstones in the file propagate, so a deletion made before the backup is honoured rather than resurrecting the row;
- the file's own `device_id` is ignored on import — the importing peer keeps its identity and never adopts the exporter's.

Because the format is a snapshot, a file lifted straight out of the Drive folder restores exactly as well as one the app exported.

### CSV export — the spreadsheet path

Export only. CSV cannot carry tombstones or settings, so it is not a restore path and must never be offered as one.

File name `tally-<YYYYMMDD-HHMMSS>.csv`, RFC 4180, UTF-8 **with a BOM** (without it Excel mis-decodes Cyrillic and Uzbek), `\r\n` line endings, comma-separated. Non-deleted transactions only, newest first.

```csv
date,kind,amount,currency,category,account,to_account,note
2026-08-18,expense,248.50,USD,Groceries,Card,,weekly shop
2026-08-20,transfer,5000.00,USD,,Card,Savings,rainy day
```

- `date` is the `occurred_at` calendar date in UTC, `YYYY-MM-DD`.
- `amount` is **always** a plain decimal with a `.` separator, no grouping, scaled by the currency's exponent — machine-parseable regardless of UI language. It is never the localized money string.
- `kind` is the raw `income` / `expense` / `transfer`, not a translation, so a spreadsheet formula can filter on it.
- `category`, `account` and `to_account` are **display names** in the current UI language (the seed-name rule applies); `category` is empty for a transfer and `to_account` is empty for everything else.

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
`/start`, `/today`, `/week`, `/month`, `/undo`, `/categories`, `/accounts` — all output localized.

`/accounts` lists every account with its balance, then the total across all of them, then which account new bot entries land in. Balances render with the plain money formatter, so a negative balance keeps its minus but a positive one is not prefixed with `+` — a balance is an amount, not a change.

The bot's account surface stops there **by design**. It never asks which account a message belongs to: it books to `settings.default_account_id`, chosen once in the app. Adding a per-message account prompt would put a tap back into the one path that must stay at one message.

`/undo` skips transfers. It reports what it removed as "amount • category", and a transfer has no category; undoing one is done in the app, where both of its accounts can be shown.

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
  data/repo/                 transactions, categories, accounts, settings, summaries
  data/drive/                device-flow auth client, Drive REST client, DriveSyncEngine
  data/backup/               snapshot export/import (JSON) and CSV export
  features/…                 home, entry, history, stats, categories, accounts, settings, shell, common
```

Meta keys (local only, never synced): `google_refresh_token`, `drive_folder_id`, `device_id`, `device_name`, `drive_peer_md5` (JSON map of file id → md5), `last_sync_ms`, `ui_theme_mode`.

The Drive engine keeps the existing public surface — `syncNow()`, `scheduleSync()`, `statusStream`, `lastSyncMsStream`, `isConfigured` — so the rest of the app is unaffected by the transport change.
