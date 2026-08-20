import 'package:drift/drift.dart';

// Prefixed for readability; the column defaults reference `seedCashAccountId`
// rather than `defaultAccountId` because drift's generator inlines the
// constant WITHOUT the prefix, and a column named `defaultAccountId` would
// then resolve to itself inside the generated table class.
import '../../core/constants.dart' as contract;

/// Mirrors the `transaction` contract table (docs/ARCHITECTURE.md) plus a
/// local-only `dirty` flag (never sent to the server).
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get kind => text()(); // 'income' | 'expense' | 'transfer'
  IntColumn get amountMinor => integer()(); // > 0, sign implied by kind
  /// FK -> category. EMPTY for a transfer: moving your own money between your
  /// own accounts is not spending, so it has no category.
  TextColumn get categoryId => text()();

  /// FK -> account. Money leaves it on an expense, arrives on an income, and
  /// is the SOURCE of a transfer.
  TextColumn get accountId =>
      text().withDefault(const Constant(contract.seedCashAccountId))();

  /// FK -> account. The DESTINATION of a transfer; empty for every other kind.
  TextColumn get toAccountId => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get occurredAt => text()(); // RFC3339 UTC, carries time of day

  /// Manual placement inside the local day; 0 = never placed by hand, which
  /// falls back to newest-first time order. Synced (docs/ARCHITECTURE.md v4).
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
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

  /// FK -> account: where the Telegram bot books its entries. Synced, because
  /// the bot must never have to ask which account a message belongs to.
  /// EMPTY means "unchanged", never "cleared" — a peer predating accounts
  /// sends the field absent.
  TextColumn get defaultAccountId =>
      text().withDefault(const Constant(contract.seedCashAccountId))();
  IntColumn get updatedAtMs => integer()();
  BoolColumn get dirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirrors the `account` contract table plus local-only `dirty`: a place money
/// sits — cash, a card, a savings pot, an investment pot.
class Accounts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()(); // 'cash' | 'bank' | 'savings' | 'investment'
  TextColumn get emoji => text()();
  TextColumn get color => text()(); // '#RRGGBB'

  /// What the account already held before tracking started. MAY BE NEGATIVE —
  /// a credit card carrying debt.
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get updatedAtMs => integer()();
  IntColumn get deletedAtMs => integer().nullable()();
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
