# Tally

A friction-free, self-hosted personal money tracker. Log an expense by messaging a Telegram bot — `250 groceries`, done — and see where your money went in a beautiful offline-first Flutter app. Your data syncs through **your own Google Drive**, in English, Russian or Uzbek.

**Why another tracker?** Every budget app dies the same death: logging is too much work, you stop after two weeks. Tally's answer is a Telegram bot that logs a transaction from one short message and *learns your shorthand*, plus a mobile app that works fully offline and syncs when it can.

## Features

- 🤖 **Telegram bot entry** — `250 groceries lunch` logs an expense; `+50000 salary` logs income; unknown words get a one-tap category picker and are remembered forever after
- 📊 `/today`, `/week`, `/month` summaries and `/undo` right in Telegram
- 📱 **Flutter app** (Android + iOS) — month overview, fast numpad entry, history with search, category donut & trend charts, category management
- ☁️ **Google Drive sync** — the app and the bot are peers that exchange snapshots in a `Tally` folder in your own Drive. No exposed ports, no public hostname, no TLS certificates. Your data sits in your Drive as readable JSON, which doubles as your backup.
- 🌍 **English · Русский · Oʻzbekcha** — the whole app and every bot reply. Pick the language in the app and the bot follows it.
- 🔌 **Offline-first** — the app is fully usable with no Drive connected at all
- 🏠 **Self-hosted** — one Go binary (bot + sync + SQLite) in one Docker container that only makes outbound calls

## Setup

### 1. Google Cloud (once, ~5 minutes)

Both the app and the bot sign in to *your* Google account using **one** OAuth client.

1. Create a project at [console.cloud.google.com](https://console.cloud.google.com) and enable the **Google Drive API**.
2. Configure the **OAuth consent screen**: External user type, add yourself as the user.
3. **Publish the consent screen ("In production").** This matters: while it is in *Testing*, Google issues refresh tokens that **expire after 7 days** and your sync will silently stop working a week later. Tally only asks for the `drive.file` scope, which is non-sensitive, so publishing needs **no verification review**.
4. Create an **OAuth client ID** of type **"TVs and Limited Input devices"**. Note the client ID and secret — both the server and the app use this same client.

Tally can only ever see the files it creates in your Drive. It cannot read anything else you own.

### 2. Server

1. Create a bot with [@BotFather](https://t.me/BotFather), copy the token.
2. Get your numeric Telegram user ID (e.g. from [@userinfobot](https://t.me/userinfobot)).
3. On your server:

```bash
git clone <this repo> tally && cd tally
cp .env.example .env        # fill in the Google client + Telegram values
docker compose run --rm tally auth   # one-time: open the URL, enter the code
docker compose up -d --build
```

4. Message your bot: `/start`, then try `250 groceries`.

### 3. App

```bash
cd app
flutter pub get
dart run build_runner build --delete-conflicting-outputs

# Standalone (no sync) — works immediately:
flutter run

# With Drive sync — compile in the same OAuth client the server uses:
flutter run \
  --dart-define=GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com \
  --dart-define=GOOGLE_CLIENT_SECRET=yyyy
```

The OAuth client is compiled in rather than typed at runtime, so no credentials sit in the repo. Use the same `--dart-define` flags with `flutter build apk`. A build without them still runs — it just shows "no Google OAuth client compiled in" instead of the Connect button.

To sync: **Settings → Connect Google Drive**, then open the shown URL, enter the code, and sign in with the same Google account the server uses. There is no Android or iOS OAuth configuration to do — no SHA-1 fingerprints, no `Info.plist` entries — because the app uses the same limited-input-device flow the server does.

## Configuration

| env var | required | meaning |
|---|---|---|
| `GOOGLE_CLIENT_ID` | yes | OAuth client ID ("TVs and Limited Input devices") |
| `GOOGLE_CLIENT_SECRET` | yes | that client's secret |
| `TELEGRAM_BOT_TOKEN` | for bot | from @BotFather; empty runs sync-only, no bot |
| `TELEGRAM_ALLOWED_USER_IDS` | for bot | comma-separated numeric IDs allowed to use the bot |
| `TOKEN_PATH` | no | refresh-token file, default `/data/google-token.json` |
| `DRIVE_FOLDER_NAME` | no | default `Tally` |
| `SYNC_INTERVAL_SECONDS` | no | how often the bot polls Drive, default `60` |
| `TZ` | no | your IANA timezone (e.g. `Asia/Tashkent`) — sets what the bot's `/today`, `/week` and `/month` mean. Defaults to UTC, so set it unless you live there. |
| `PORT` | no | health endpoint, default `8080` |
| `DB_PATH` | no | default `/data/tally.db` |
| `DEFAULT_CURRENCY` | no | ISO code, default `USD` |

## How sync works

Each peer — your phone, the bot server — owns exactly one file in the `Tally` folder, `tally-<device-id>.json`, and never writes to anyone else's. A sync pass downloads every other peer's snapshot, merges it with strict last-write-wins on `updated_at_ms` (deletes are tombstones, never hard deletes), then republishes its own. Because no two peers ever write the same file, there are no write conflicts, and because every snapshot is a full dump, a peer that has been offline for months converges in a single pass.

Full protocol in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Repository layout

```
app/      Flutter app (Riverpod + Drift + go_router + fl_chart + gen-l10n)
server/   Go: Telegram bot + Drive sync + SQLite
docs/     SPEC.md · ARCHITECTURE.md (binding contracts) · DESIGN.md · PLAN.md
```

## Roadmap

Per-category budgets with Telegram warnings ("groceries at 90%"), CSV export, recurring transactions, multi-currency.

## License

MIT
