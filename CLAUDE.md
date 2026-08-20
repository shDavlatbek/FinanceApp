# Tally — working notes for agents

Self-hosted personal budget tracker: a Telegram bot for fast logging, an offline-first Flutter app, and a single Go binary. The two sync through the owner's **Google Drive** — there is no client/server API between them. Trilingual: English, Russian, Uzbek.

## Read before changing anything

- `docs/SPEC.md` — confirmed intent and scope. Parked features are not to be built.
- `docs/ARCHITECTURE.md` — **binding contract**: data model, fixed seed UUIDs, the Drive sync protocol and snapshot JSON, OAuth device flow, i18n rules, env vars. If code and this doc disagree, the doc wins — fix the code.
- `docs/DESIGN.md` — **binding** UI direction. Design quality is a requirement here, not deferred polish.
- `docs/PLAN.md` — where the build stands and what is still unverified.

## Layout

```
app/      Flutter (Riverpod, Drift, go_router, fl_chart, gen-l10n) — usable with no Drive connected
server/   Go: Telegram bot + Drive sync + SQLite, one binary, one container
docs/     spec, contracts, design, plan, fixtures/
```

## Verification

```bash
cd server && go vet ./... && go build ./... && go test -count=1 ./...
cd app && flutter analyze && flutter test          # analyze must report zero issues
```

Container: `docker compose up -d --build` (needs a `.env`), then `curl localhost:8080/api/health`.

Screens (visual check): `cd app && flutter test --dart-define=CAPTURE=true --update-goldens test/capture_screens_test.dart` → PNGs in `app/test/shots/` (gitignored). Skipped in normal runs on purpose — font rasterization differs per machine, so pixel-diffing them in CI would fail for no useful reason.

## Conventions

- Money is **integer minor units** everywhere. Never floats. Never format money with `golang.org/x/text/currency` — it is pinned to CLDR 32 and misplaces the ruble symbol.
- **The two peers must agree on each currency's exponent.** It is the scale between a typed amount and the stored `amount_minor`, so a mismatch makes the same transaction read 100x apart on the two ends. The tables are `kCurrencyExponents` in `app/lib/core/money.dart` and `currencies` in `server/internal/i18n/money.go`; `app/test/currency_parity_test.dart` diffs them. Do not trust `intl` here — it reports two decimals for UZS, which is exactly the disagreement that test now prevents.
- Sync merge is **strict** last-write-wins on `updated_at_ms`; ties keep the local row. Deletes are tombstones, never hard deletes.
- Each peer writes **only its own** snapshot file. Never write another peer's file — single-writer-per-file is what makes the design conflict-free.
- The seed category **and seed account** UUIDs are fixed constants duplicated in `server/internal/store` and `app/lib/core/constants.dart` and must stay byte-identical.
- **Display order is `sort_order` then time, inside one local day.** `sort_order = 0` means "never placed by hand" and falls back to newest-first time order; dragging a day renumbers that day `1..N`. Because days are LOCAL and SQLite does not know the peer's offset, the within-day sort happens in Dart (`sortedForDisplay`) after grouping, never in SQL. `sort_order` is display-only — the bot carries it and writes 0.
- **Transfers are not spending.** `kind = "transfer"` must stay out of every income total, expense total, category breakdown and transaction count, on both peers. A transfer is one row with two account ids — never a matched expense/income pair, which could half-arrive or be half-deleted under LWW.
- **A backup file is a snapshot file.** Export/import reuses the Drive snapshot format, parser, sanitizer and merge; import is a last-write-wins merge, so it is idempotent and cannot clobber newer rows. Do not introduce a second backup format.
- **The snapshot wire format is shared between two languages.** `docs/fixtures/snapshot.example.json` is parsed by both `server/internal/drive/interop_test.go` and `app/test/snapshot_interop_test.dart`. Change the format in the contract first, then update the fixture, then both sides. `docs/fixtures/snapshot.v1.example.json` pins the pre-accounts schema both sides must still read — never "update" it to the current schema, that is the whole point of it.
- Peer snapshot files are **untrusted input** — the owner can hand-edit them in the Drive UI. Sanitize, don't assume.
- i18n: nothing user-facing may be hardcoded. App strings live in `app/lib/l10n/arb/`, bot strings in `server/internal/i18n/locales/`. Russian needs one/few/many/other plurals. Never enable `use-escaping` in `l10n.yaml` — Uzbek is full of apostrophes.
- The app must never block on the network and must stay fully functional with no Drive connected.
