# Tally — build status

v2 is **built and verified**: Google Drive sync replaces the REST API, and the app plus the bot speak English, Russian and Uzbek. This file records what was actually tested, as opposed to claimed, and what is still unproven.

## Verified on 2026-08-20

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

1. Do the live Google + Telegram pass above — it is the only remaining unknown of substance.
2. First git commit: the repo is initialized but has **no commits yet**.
3. Then budgets with Telegram warnings, per `SPEC.md`.
