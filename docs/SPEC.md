# Tally — Product Spec

## Confirmed intent (interview 2026-08-19)

- **Outcome:** A friction-free personal money tracker the owner is still using 2 months from now — type `250 groceries` to a Telegram bot and it's logged in 3 seconds; a beautiful Flutter app shows where the money went.
- **User:** The owner, daily. Open-sourced afterward for self-hosters.
- **Why now:** Every tracker app tried before died from logging friction — the bot is the fix, not a gimmick.
- **Success:** Still logging every transaction at the 2-month mark; monthly income/expense + category breakdown answers "where did it go?" at a glance.
- **Constraint:** Bot self-hosted on the owner's VPS as one Docker Compose; Flutter app (Android/iOS from one codebase) that works fully offline; one main currency.
- **Out of scope:** bank sync, CSV import, multi-currency, budget limits/alerts, multi-user & app-store polish, monetization. Budgets with Telegram warnings are the headline next feature.

### Amended 2026-08-20 (v3)

- **Accounts, requested by the owner.** Money now sits somewhere — cash, a card, savings, investments — and "send to savings" / "send to investments" moves it between two of them. Modelled as a third transaction kind, `transfer`, which deliberately affects **no** income or expense total: putting money aside is not spending. Savings and investments are ordinary accounts rather than a separate goal system, so there is one money-movement path, not two.
- **Export and import, requested by the owner.** Moved out of the V2 parking lot below. A JSON backup is a full, loss-free restore; a CSV export covers spreadsheets. Import **merges under last-write-wins** rather than replacing, so it is idempotent and cannot destroy newer work — the file format is the Drive snapshot itself, so there is no second format to keep correct. This supersedes the "CSV import" and "bank statement import" exclusions only insofar as the app reads back **its own** export; parsing a bank's statement remains out of scope.
- **The bot's account surface stays minimal**: entries book to a default account chosen in the app, plus a `/accounts` balances command. Nothing may add a tap to the 3-second path.

### Amended 2026-08-19 (v2)

- **Sync moved to Google Drive.** The bespoke REST sync API is deleted. The app and the bot are peers that exchange snapshot files in the owner's own Drive (`drive.file` scope, one OAuth client, device flow on both ends). The VPS no longer needs an exposed port, a public hostname, or TLS — it only makes outbound calls. Data lives in the owner's Drive as readable JSON, which doubles as backup.
- **Trilingual: English, Russian, Uzbek.** The whole app UI plus every Telegram bot reply. The language chosen in the app syncs to the bot, so both speak the same language. Seed category names localize only until the user renames them.

## Non-negotiables

1. **3-second logging via Telegram.** `250 groceries` → done. Ambiguity resolved with one tap (inline keyboard), and the bot *learns* the alias so next time it's zero taps.
2. **Offline-first app.** The app never blocks on the network. No server configured → still a complete standalone tracker.
3. **Beautiful, animated UI.** Design quality is a feature (see DESIGN.md), not polish to defer.
4. **Self-hosting in one command.** `docker compose up -d` with a 5-minute README path from zero to working bot.

## V1 feature list

### Telegram bot
- Free-text entry (grammar in ARCHITECTURE.md), income via `+`, notes, alias learning
- `/today`, `/week`, `/month` summaries; `/undo`; `/categories`
- Allow-list auth; polite rejection for strangers

### Flutter app
- **Home:** current month at a glance — net/spent/income headline numbers, per-category spending bars, recent transactions; month switcher
- **Quick add:** numpad-first entry sheet (amount → category grid → optional note/date), income/expense toggle
- **History:** all transactions grouped by day, search by note, filter by category/kind; tap to edit, swipe to delete
- **Stats:** category donut + 6-month trend bars, per-month navigation
- **Categories:** add/edit/archive, emoji + color pickers, reorder
- **Accounts:** add/edit/archive, emoji + color pickers, opening balance, live balances, pick the bot's default account
- **Transfers:** move money between accounts from the entry sheet; excluded from every income/expense total
- **Backup:** export a JSON backup or a CSV, import a JSON backup (merge, newest wins)
- **Settings:** server URL + API token, connection test, sync status/last-synced, currency picker, standalone-mode notice
- Light + dark theme (dark default), offline indicator, pull-to-refresh sync

### Server
- Single Go binary: REST sync API + Telegram bot + SQLite
- Dockerfile + docker-compose.yml + `.env.example`
- Health endpoint for uptime checks

## V2 parking lot (do not build now)
Budgets per category with Telegram warnings ("groceries at 90%"), recurring transactions, multi-currency, bank statement import (parsing a *bank's* format, as opposed to reading back Tally's own export), widgets/watch, multi-user.

*Accounts/transfers and export/import left this list on 2026-08-20 — see the v3 amendment above.*
