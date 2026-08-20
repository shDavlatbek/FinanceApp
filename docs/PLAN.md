# Tally — build status

## v3 (accounts + transfers + day lens) — app and server both built

Requested by the owner on 2026-08-20: accounts (cash / card / savings /
investments), "send to savings" / "send to investments" as transfers,
export/import to a file, and a Day / Month lens for inspecting daily spending.

### Verified on 2026-08-20 (run directly against the tree)

| check | result |
|---|---|
| `go vet ./...` · `go build ./...` · `go test -count=1 ./...` | clean |
| `flutter analyze` | **0 issues** |
| `flutter test` | **187 pass**, 4 skipped (capture harness) |
| snapshot interop fixture, Go side | parse, round trip, sanitizing path, schema-1 fallback |
| snapshot interop fixture, Dart side | same fixture, same expected values, plus the v1 fixture |
| v2 → v3 drift migration | rows keep their data, book to cash, `transfer` inserts |
| pre-accounts SQLite migration (Go) | transactions table rebuilt, indexes recreated |

### Bugs found by adversarial review and fixed

A 30-agent review pass over the Go/Dart integration produced 45 candidate
findings; each was independently verified by a skeptic before being acted on,
which refuted most of them as stale (the reviewers were reading a tree that was
being edited underneath them). The ones that survived were real:

- **Drive sync never merged peer accounts.** `Snapshot.Batch()` parsed and
  sanitized them, `MergeRemote` knew how to apply them, and the single line
  carrying them between the two was missing. Nothing failed loudly: the settings
  row naming a new account merged fine, `DefaultAccount()` silently fell back to
  cash, and the bot booked every entry to the wrong account forever. Regression
  test `TestSyncMergesPeerAccounts` fails without the fix.
- **The sanitizer could manufacture the row it rejects.** The unknown-account
  rewrite ran *after* the self-transfer check, so a transfer with a missing
  source and a cash destination became `cash -> cash`.
- **A self-transfer invented money.** The balance query used one first-match
  `CASE`, so the credit arm matched and the debit arm was never reached. Now
  four summed terms, which net to zero.
- **`CategoryPeriodTotal` counted transfers**, and it feeds the reply the owner
  reads after every single entry.
- **One bad account row cost the peer its currency and language**, because an
  unknown `default_account_id` skipped the whole settings row.
- **The Dart peer discarded an entire snapshot over one malformed row**, where
  Go skips just that row — so a single stray comma typed in the Drive UI would
  have silently frozen sync while still reporting "synced".
- **The Dart peer seeded `settings.updated_at_ms` at `1755000000000`** instead
  of the `0` sentinel, so a fresh app silently overwrote the server's
  `DEFAULT_CURRENCY` — a 100x misread on a 0-decimal currency like UZS. Fixed
  with a migration that unsticks existing installs, mirroring the server's.
- **Transfers leaked into the display layer**: history day subtotals subtracted
  them as spending, and a transfer rendered as a green `+` labelled
  "Uncategorized".

### Not done

- **Accounts screen** (add / edit / archive / reorder, opening balance) and the
  **transfer flow in the entry sheet**. The data layer, sync, balances and
  rendering are all in place and tested; what is missing is the UI to create a
  transfer from the app. Transfers arriving from a peer are handled correctly.
- **Export / import screens.** The format, semantics and merge rule are settled
  in the contract (a backup file IS a snapshot file, import is a last-write-wins
  merge) and the whole parse/sanitize/merge path they reuse is built and tested;
  the file-picker UI and CSV writer are not.
- **No real Google Drive round trip has ever happened**, and the Telegram bot
  has never talked to Telegram. Both are still tested only against in-memory
  fakes.
- Release APK: `app/android/app/build.gradle.kts` still signs release with the
  **debug** key (`// TODO: Add your own signing config`). Needs a keystore
  before an APK means anything.

## v2 — verified 2026-08-20

v2 is **built and verified**: Google Drive sync replaces the REST API, and the app plus the bot speak English, Russian and Uzbek. This file records what was actually tested, as opposed to claimed, and what is still unproven.


Every check below was run directly against the tree, not taken from an agent's report.

| check | result |
|---|---|
| `go vet ./...` · `go build ./...` · `go test -count=1 ./...` | clean; api, bot, drive, i18n, store all pass |
| `flutter analyze` | **0 issues** |
| `flutter test` | **139 pass**, 2 skipped (capture harness) |
| snapshot interop fixture, Go side | 3/3 — parse, round trip, sanitizing path |
| snapshot interop fixture, Dart side | 6/6 — same fixture, same expected values |
| `docker build ./server` | builds with the new Drive/OAuth dependencies |
| `docker compose up -d` | container **healthy**; `TZ=Asia/Tashkent` honoured in the logs |
| `GET /api/health` | `{"status":"ok","version":"2.0.0"}` |
| `POST /api/sync` | **404** — the old API is genuinely gone |
| `tally auth` without credentials | fails with an actionable message |
| startup without a token / bot token | degrades to local-only and sync-only with clear logs |
| screens rendered and eyeballed | Home dark/light, entry sheet, History, Stats, Settings, plus Home + Settings in Russian and Home in Uzbek |

**The interop fixture is the load-bearing new test.** `docs/fixtures/snapshot.example.json` is parsed by both implementations, which is the only way to catch wire-format drift between the Go and Dart peers without live Google credentials. It deliberately includes tombstones, a null vs set `deleted_at_ms`, Cyrillic and Latin-Uzbek text, a 0-decimal currency, and an int64 past double precision (2^53+1) that would silently corrupt if either side ever routed amounts through a float.

## Bugs found and fixed during this round

Eleven defects were found by adversarial review and fixed, each with a regression test. The ones worth remembering:

- **A revoked refresh token was reported as "offline"**, so the VPS would have retried forever instead of telling the owner to re-run `tally auth`.
- **The settings row could never sync between peers.** Both seeded it with the same fixed timestamp, and under strict LWW a tie keeps the local row — so currency and language were frozen on both sides forever. Fixed with a `0` sentinel that loses to every real value, plus a migration that unsticks existing installs.
- **A duplicate `Tally` folder would have split the peers permanently and silently.** Folder resolution now re-resolves by name each pass and breaks a split deterministically.
- **The app's cached Drive folder id could never be invalidated**, because listing a dead folder returns an empty page rather than a 404 — the existing test only passed because the fake threw 404 where the real API does not.
- **`docker compose run --rm tally auth` needed a restart to take effect**; the client is now rebuilt when the token file changes.
- **Bot period boundaries were computed in UTC**, so `/today` was wrong for anyone not on UTC. Hence the new `TZ` variable.
- **One transient network blip aborted the whole device-flow authorization.**

Earlier round, still standing: the tab-ghosting fix in `app/lib/features/shell/app_shell.dart` (TickerMode must sit below the fade animations), guarded by `leaving a tab takes its branch offstage`.

## Not verified

- **No real Google Drive round trip has ever happened.** Both sides are tested against in-memory fakes of the Drive API, and the wire format is pinned by the shared fixture, but no live credentials were used. First real test: create the OAuth client, `docker compose run --rm tally auth`, then connect the app and watch a transaction cross.
- **The Telegram bot has never talked to Telegram.** Parser, matcher, catalogs and formatting are unit-tested; no real bot token has been used.
- **Uzbek okina rendering.** `Koʻngilochar` uses U+02BB, which Manrope lacks; it shows as a box in the test captures. Android should supply it by font fallback — worth a 10-second look on a real device.
- Release APK (`--release`, R8/signing) — only debug was built.
- The "System" theme chip ellipsizes in Russian ("Как в си…"). Cosmetic, and it degrades gracefully.

## Next steps

1. **Commit `app/lib/data/`** — nothing else on the app side can move until it is in the repo.
2. Finish the Flutter half of v3 (see the blocked list above), then re-run `flutter analyze` and `flutter test`.
3. Do the live Google + Telegram pass — still the only remaining unknown of substance.
4. Then budgets with Telegram warnings, per `SPEC.md`.
