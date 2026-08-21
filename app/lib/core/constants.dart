/// Fixed contract constants for Tally.
///
/// Seed category UUIDs and timestamps are part of the binding contract in
/// docs/ARCHITECTURE.md — both the app (standalone mode) and the server seed
/// identical rows so they merge cleanly on first sync. DO NOT change them.
library;

/// `updated_at_ms` for every seeded row (categories + accounts).
const int seedUpdatedAtMs = 1755000000000;

/// `updated_at_ms` the settings singleton is seeded with: "nobody has chosen
/// anything yet".
///
/// Deliberately NOT [seedUpdatedAtMs]. Settings is the one seeded row whose
/// contents differ per peer — the app seeds USD while the server seeds its
/// DEFAULT_CURRENCY — and under the contract's strict LWW ("ties keep the
/// local row") two identical timestamps freeze the row on both sides forever.
/// Zero loses to every real value in both directions, and rows with
/// `updated_at_ms == 0` are never published to peers.
const int settingsUnsetMs = 0;

/// Fixed id of the settings singleton row.
const String settingsRowId = 'settings';

/// Default currency (ISO-4217).
const String defaultCurrency = 'USD';

/// Default `settings.language`. `''` means "follow the device locale"; the
/// value is synced so the Telegram bot answers in the same language.
const String defaultLanguage = '';

/// Language codes the app and the bot both support. `''` = follow device.
const List<String> supportedLanguageCodes = ['', 'en', 'ru', 'uz'];

/// Transaction kinds. Categories only ever use [income] / [expense] —
/// [transfer] is a transaction-only kind.
abstract final class Kind {
  static const String income = 'income';
  static const String expense = 'expense';

  /// Money moved between two of the owner's OWN accounts. Never income, never
  /// spending: it must stay out of every total, breakdown and count.
  static const String transfer = 'transfer';

  /// Kinds a category may carry.
  static const List<String> categoryKinds = [income, expense];

  static bool isValidTransaction(String v) =>
      v == income || v == expense || v == transfer;

  static bool isValidCategory(String v) => v == income || v == expense;
}

/// Which lens Home and Stats are showing: one calendar day, or one month.
///
/// A per-device UI preference, persisted in the local meta table — unlike
/// `settings.language`, the bot has no use for which lens you last used.
enum PeriodMode {
  day,
  month,

  /// A custom `from`-`to` span of whole days, inclusive at both ends.
  range;

  static PeriodMode fromName(String? raw) => switch (raw) {
        'day' => PeriodMode.day,
        'range' => PeriodMode.range,
        _ => PeriodMode.month,
      };
}

/// Account kinds. Presentation and grouping only — every account holds money
/// the same way, which is what makes "send to savings" an ordinary transfer.
abstract final class AccountKind {
  static const String cash = 'cash';
  static const String bank = 'bank';
  static const String savings = 'savings';
  static const String investment = 'investment';

  static const List<String> all = [cash, bank, savings, investment];

  static bool isValid(String v) => all.contains(v);
}

/// Transaction sources.
abstract final class TxSource {
  static const String app = 'app';
  static const String telegram = 'telegram';
}

/// Keys of the local-only meta key-value table (docs/ARCHITECTURE.md).
/// None of these are ever serialized into a Drive snapshot.
abstract final class MetaKeys {
  /// Long-lived Google OAuth refresh token (rotated tokens overwrite it).
  static const String googleRefreshToken = 'google_refresh_token';

  /// Cached Drive id of the `Tally` folder.
  static const String driveFolderId = 'drive_folder_id';

  /// This peer's stable UUIDv4; part of its snapshot file name.
  static const String deviceId = 'device_id';

  /// Human-readable name shown in other peers' snapshots.
  static const String deviceName = 'device_name';

  /// JSON map of Drive file id -> last merged `md5Checksum`.
  static const String drivePeerMd5 = 'drive_peer_md5';

  /// Unix-ms of the last successful sync pass.
  static const String lastSyncMs = 'last_sync_ms';

  /// UI-owned theme preference (`'dark'` | `'light'` | `'system'`). Local-only
  /// like the rest: the theme is a per-device choice, unlike `settings.language`
  /// which is synced because the Telegram bot reads it.
  static const String uiThemeMode = 'ui_theme_mode';

  /// Home/Stats period lens (`'day'` | `'month'` | `'range'`). Local-only and
  /// per-device: which lens you last looked through is not data the bot has
  /// any use for.
  static const String uiPeriodMode = 'ui_period_mode';

  /// First and last day of the custom range lens, as `yyyy-MM-dd` day keys.
  /// Local-only, for the same reason as [uiPeriodMode].
  static const String uiRangeFrom = 'ui_range_from';
  static const String uiRangeTo = 'ui_range_to';
}

/// Google Drive sync constants (docs/ARCHITECTURE.md § Google Drive sync).
///
/// One OAuth client of type "TVs and Limited Input devices" is shared by the
/// app and the Go server; each peer runs its own device authorization for the
/// same Google account. Compile the values in with
/// `--dart-define=GOOGLE_CLIENT_ID=... --dart-define=GOOGLE_CLIENT_SECRET=...`.
abstract final class DriveOAuth {
  static const String clientId = String.fromEnvironment('GOOGLE_CLIENT_ID');
  static const String clientSecret =
      String.fromEnvironment('GOOGLE_CLIENT_SECRET');

  /// The single, non-sensitive scope. Never widen this.
  static const String scope = 'https://www.googleapis.com/auth/drive.file';

  static const String deviceCodeEndpoint =
      'https://oauth2.googleapis.com/device/code';
  static const String tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const String revokeEndpoint = 'https://oauth2.googleapis.com/revoke';

  static const String deviceCodeGrantType =
      'urn:ietf:params:oauth:grant-type:device_code';

  /// False when the app was built without the `--dart-define`s above.
  static bool get isAvailable => clientId.isNotEmpty && clientSecret.isNotEmpty;
}

/// Drive folder that holds every peer's snapshot, in the account's root.
const String driveFolderName = 'Tally';

/// Snapshot file naming: `tally-<device_id>.json`.
const String snapshotNamePrefix = 'tally-';
const String snapshotNameSuffix = '.json';
const String snapshotMimeType = 'application/json';

/// `schema` field of the snapshot envelope written by this build. Schema 2
/// added accounts, per-transaction account ids and the `transfer` kind;
/// schema 3 added `sort_order`.
const int snapshotSchemaVersion = 3;

/// Oldest snapshot schema this build still reads. A schema-1 file predates
/// accounts: it has no `accounts` array and its transactions have no
/// `account_id`, so they are booked to [defaultAccountId] — exactly where the
/// local migration puts this peer's own pre-accounts rows.
const int minReadableSnapshotSchema = 1;

/// Snapshot file name for a device id.
String snapshotFileName(String deviceId) =>
    '$snapshotNamePrefix$deviceId$snapshotNameSuffix';

/// One fixed seed category row.
class SeedCategory {
  const SeedCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.color,
    required this.kind,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String emoji;
  final String color;
  final String kind;
  final int sortOrder;
}

/// Seed categories — FIXED UUIDs, copied exactly from docs/ARCHITECTURE.md.
const List<SeedCategory> seedCategories = [
  SeedCategory(
    id: 'c1a7e2f0-0001-4a00-9000-000000000001',
    name: 'Groceries',
    emoji: '🛒',
    color: '#4CAF7D',
    kind: Kind.expense,
    sortOrder: 0,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0002-4a00-9000-000000000002',
    name: 'Cafe',
    emoji: '☕',
    color: '#E8935A',
    kind: Kind.expense,
    sortOrder: 1,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0003-4a00-9000-000000000003',
    name: 'Transport',
    emoji: '🚕',
    color: '#5A9BE8',
    kind: Kind.expense,
    sortOrder: 2,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0004-4a00-9000-000000000004',
    name: 'Home',
    emoji: '🏠',
    color: '#9B7DE8',
    kind: Kind.expense,
    sortOrder: 3,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0005-4a00-9000-000000000005',
    name: 'Utilities',
    emoji: '💡',
    color: '#E8C95A',
    kind: Kind.expense,
    sortOrder: 4,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0006-4a00-9000-000000000006',
    name: 'Health',
    emoji: '💊',
    color: '#E85A7A',
    kind: Kind.expense,
    sortOrder: 5,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0007-4a00-9000-000000000007',
    name: 'Shopping',
    emoji: '🛍️',
    color: '#D45AE8',
    kind: Kind.expense,
    sortOrder: 6,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0008-4a00-9000-000000000008',
    name: 'Fun',
    emoji: '🎮',
    color: '#5AE8D4',
    kind: Kind.expense,
    sortOrder: 7,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0009-4a00-9000-000000000009',
    name: 'Subscriptions',
    emoji: '📱',
    color: '#7A8BE8',
    kind: Kind.expense,
    sortOrder: 8,
  ),
  SeedCategory(
    id: 'c1a7e2f0-000a-4a00-9000-00000000000a',
    name: 'Travel',
    emoji: '✈️',
    color: '#5AC8E8',
    kind: Kind.expense,
    sortOrder: 9,
  ),
  SeedCategory(
    id: 'c1a7e2f0-000b-4a00-9000-00000000000b',
    name: 'Other',
    emoji: '📦',
    color: '#8E8E93',
    kind: Kind.expense,
    sortOrder: 10,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0101-4a00-9000-000000000101',
    name: 'Salary',
    emoji: '💼',
    color: '#4CAF7D',
    kind: Kind.income,
    sortOrder: 0,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0102-4a00-9000-000000000102',
    name: 'Freelance',
    emoji: '💻',
    color: '#5A9BE8',
    kind: Kind.income,
    sortOrder: 1,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0103-4a00-9000-000000000103',
    name: 'Gifts',
    emoji: '🎁',
    color: '#E8935A',
    kind: Kind.income,
    sortOrder: 2,
  ),
  SeedCategory(
    id: 'c1a7e2f0-0104-4a00-9000-000000000104',
    name: 'Other income',
    emoji: '➕',
    color: '#8E8E93',
    kind: Kind.income,
    sortOrder: 3,
  ),
];

/// One fixed seed account row.
class SeedAccount {
  const SeedAccount({
    required this.id,
    required this.name,
    required this.kind,
    required this.emoji,
    required this.color,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final String kind;
  final String emoji;
  final String color;
  final int sortOrder;
}

/// The seed cash account's fixed id.
///
/// Spelled separately from [defaultAccountId] because drift's generator drops
/// import prefixes when it inlines a column's `withDefault` constant: a column
/// named `defaultAccountId` would end up referring to ITSELF in the generated
/// table class. The tables reference this name; everything else reads better
/// as [defaultAccountId].
const String seedCashAccountId = 'a1c7e2f0-0001-4a00-9000-000000000001';

/// The account new entries book to until the owner picks another, and the
/// fallback a peer uses for any transaction that arrives without a usable
/// `account_id`. Byte-identical to `store.DefaultAccountID` on the server.
const String defaultAccountId = seedCashAccountId;

/// Seed accounts — FIXED UUIDs, copied exactly from docs/ARCHITECTURE.md and
/// byte-identical to `store.SeedAccounts` on the server. Savings and
/// investments are seeded rather than left to the user so that "send to
/// savings" works on a fresh install with no setup step.
const List<SeedAccount> seedAccounts = [
  SeedAccount(
    id: seedCashAccountId,
    name: 'Cash',
    kind: AccountKind.cash,
    emoji: '💵',
    color: '#4CAF7D',
    sortOrder: 0,
  ),
  SeedAccount(
    id: 'a1c7e2f0-0002-4a00-9000-000000000002',
    name: 'Card',
    kind: AccountKind.bank,
    emoji: '💳',
    color: '#5A9BE8',
    sortOrder: 1,
  ),
  SeedAccount(
    id: 'a1c7e2f0-0003-4a00-9000-000000000003',
    name: 'Savings',
    kind: AccountKind.savings,
    emoji: '🏦',
    color: '#E8C95A',
    sortOrder: 2,
  ),
  SeedAccount(
    id: 'a1c7e2f0-0004-4a00-9000-000000000004',
    name: 'Investments',
    kind: AccountKind.investment,
    emoji: '📈',
    color: '#9B7DE8',
    sortOrder: 3,
  ),
];
