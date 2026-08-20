/// Fixed contract constants for Tally.
///
/// Seed category UUIDs and timestamps are part of the binding contract in
/// docs/ARCHITECTURE.md — both the app (standalone mode) and the server seed
/// identical rows so they merge cleanly on first sync. DO NOT change them.
library;

/// `updated_at_ms` for every seeded row (categories + settings).
const int seedUpdatedAtMs = 1755000000000;

/// Fixed id of the settings singleton row.
const String settingsRowId = 'settings';

/// Default currency (ISO-4217).
const String defaultCurrency = 'USD';

/// Default `settings.language`. `''` means "follow the device locale"; the
/// value is synced so the Telegram bot answers in the same language.
const String defaultLanguage = '';

/// Language codes the app and the bot both support. `''` = follow device.
const List<String> supportedLanguageCodes = ['', 'en', 'ru', 'uz'];

/// Transaction / category kinds.
abstract final class Kind {
  static const String income = 'income';
  static const String expense = 'expense';
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

/// `schema` field of the snapshot envelope.
const int snapshotSchemaVersion = 1;

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
