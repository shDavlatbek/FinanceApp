import 'package:drift/drift.dart';

/// Mirrors the `transaction` contract table (docs/ARCHITECTURE.md) plus a
/// local-only `dirty` flag (never sent to the server).
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // 'income' | 'expense'
  IntColumn get amountMinor => integer()(); // > 0, sign implied by kind
  TextColumn get categoryId => text()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get occurredAt => text()(); // RFC3339 UTC
  TextColumn get source => text().withDefault(const Constant('app'))();
  IntColumn get createdAtMs => integer()();
  IntColumn get updatedAtMs => integer()();
  IntColumn get deletedAtMs => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirrors the `category` contract table plus local-only `dirty`.
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get emoji => text()();
  TextColumn get color => text()(); // '#RRGGBB'
  TextColumn get kind => text()(); // 'income' | 'expense'
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get updatedAtMs => integer()();
  IntColumn get deletedAtMs => integer().nullable()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirrors the `settings` singleton contract table plus local-only `dirty`.
@DataClassName('SettingsRow')
class Settings extends Table {
  TextColumn get id => text()(); // always 'settings'
  TextColumn get currency => text()(); // ISO-4217
  /// '' | 'en' | 'ru' | 'uz' — '' follows the device/Telegram locale.
  /// Synced deliberately: it is how the phone tells the bot which language
  /// to reply in.
  TextColumn get language => text().withDefault(const Constant(''))();
  IntColumn get updatedAtMs => integer()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local-only key-value store — every key is declared in `MetaKeys`
/// (core/constants.dart): google_refresh_token, drive_folder_id, device_id,
/// device_name, drive_peer_md5, last_sync_ms, ui_theme_mode. None of these is
/// ever serialized into a Drive snapshot.
@DataClassName('MetaRow')
class Meta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
