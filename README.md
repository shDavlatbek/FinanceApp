# Tally

A friction-free, self-hosted personal money tracker. Log an expense by messaging a Telegram bot — `250 groceries`, done — and see where your money went in a beautiful offline-first Flutter app. Your data syncs through **your own Google Drive**, in English, Russian or Uzbek.

**Why another tracker?** Every budget app dies the same death: logging is too much work, you stop after two weeks. Tally's answer is a Telegram bot that logs a transaction from one short message and *learns your shorthand*, plus a mobile app that works fully offline and syncs when it can.

## Features

- 🤖 **Telegram bot entry** — `250 groceries lunch` logs an expense; `+50000 salary` logs income; unknown words get a one-tap category picker and are remembered forever after
- 📊 `/today`, `/week`, `/month` summaries, `/accounts` balances and `/undo` right in Telegram
- 📱 **Flutter app** (Android + iOS) — month overview, fast numpad entry, history with search, category donut & trend charts, category and account management, and a Day / Month / Range lens on every figure
- 🏦 **Accounts** — cash, cards, savings, investments, each with its own balance. "Send to savings" is a transfer between two of your accounts, and transfers never count as income or spending, so putting money aside doesn't look like losing it
- 💾 **Export & import** — write a JSON backup or a CSV for your spreadsheet, and restore a backup later. Import merges newest-wins, so running it twice changes nothing and it can never clobber newer entries
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

Rather than retyping those flags, put them in a file once:

```bash
cp drive.example.json drive.json   # then fill in your client id + secret
flutter run   --dart-define-from-file=drive.json
flutter build apk --release --dart-define-from-file=drive.json
```

`drive.json` is gitignored. The OAuth client is compiled in rather than typed at runtime, so no credentials sit in the repo — which also means **a build without the flags can never sync**: it shows "no Google OAuth client compiled in" where the Connect button would be, and works as a standalone tracker. If you flash an APK and Settings has no Connect button, this is why.

To sync: **Settings → Connect Google Drive**, then open the shown URL, enter the code, and sign in with the same Google account the server uses. There is no Android or iOS OAuth configuration to do — no SHA-1 fingerprints, no `Info.plist` entries — because the app uses the same limited-input-device flow the server does.

### 4. Signing a release build

Out of the box a release build is signed with the **debug** key: it installs and runs, but it cannot be published, and it cannot upgrade an install signed with any other key. Gradle prints a warning saying so. To sign properly, create a keystore once and point Gradle at it:

```bash
keytool -genkey -v -keystore ~/tally-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias tally

cat > app/android/key.properties <<'EOF'
storeFile=/home/you/tally-release.jks
storePassword=...
keyAlias=tally
keyPassword=...
EOF
```

`key.properties` and `*.jks` are gitignored — a signing key in a public repo lets anyone ship an update to your app. **Back the keystore up somewhere you will still have it in two years:** losing it means you can never update an installed copy again, only uninstall and reinstall.

Then:

```bash
# One APK per CPU architecture — ~25 MB each instead of one 65 MB fat APK
flutter build apk --release --split-per-abi --dart-define-from-file=drive.json

# Or an app bundle, if you are going anywhere near Play
flutter build appbundle --release --dart-define-from-file=drive.json
```

#### Build noise, and the one failure that is real

Two warnings are harmless and not about this app:

- **`A restricted method in java.lang.System has been called`** (four lines) — Gradle's own `native-platform` loads a native library, which JDK 24+ flags. It comes from the Gradle **launcher** JVM, so `android/gradle.properties` cannot silence it; `export GRADLE_OPTS=--enable-native-access=ALL-UNNAMED` does. (`gradle.properties` grants the same thing to the daemon, which matters once JEP 472 starts *blocking* rather than warning.)
- **`SDK XML version 4 ... only understands up to 3`** — your `cmdline-tools` is newer than the Android Gradle Plugin's SDK parser. Cosmetic, and it only appears when the SDK is re-scanned.

One thing that looks like noise but is not:

- **`Execution failed for task ':app:extractReleaseNativeSymbolTables'` / `NoSuchFileException: .../x86_64/libsqlite3.so.sym`** — this is stale build output, not a code problem. It happens when you build `--split-per-abi` in a tree that last built a fat APK: the symbol-table directory still holds the ABIs the split build is not producing, and Gradle 9 refuses to read a directory it cannot account for. `flutter clean` and rebuild; verified fix.

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

Per-category budgets with Telegram warnings ("groceries at 90%"), recurring transactions, multi-currency.

## License

MIT
