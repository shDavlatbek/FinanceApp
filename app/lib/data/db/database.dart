import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Transactions, Categories, Settings, Meta])
class AppDatabase extends _$AppDatabase {
  /// Test-friendly constructor: inject any [QueryExecutor]
  /// (e.g. `NativeDatabase.memory()`).
  AppDatabase(super.e);

  /// Production constructor: opens the on-device database via drift_flutter.
  AppDatabase.open() : super(driftDatabase(name: 'tally'));

  /// v2 (2026-08-19): `settings.language` added; the REST sync meta keys
  /// (server_url / api_token / last_seq) are dropped in favour of the Drive
  /// keys. No user data is touched.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _seed();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Additive: TEXT NOT NULL DEFAULT '' — existing rows keep their
            // data and get "follow the device locale".
            await m.addColumn(settings, settings.language);
            // The bespoke REST sync transport is gone; its cursor and
            // credentials are meaningless now. Drive re-syncs from scratch.
            await (delete(meta)
                  ..where((r) => r.key.isIn(const [
                        'server_url',
                        'api_token',
                        'last_seq',
                        'last_sync_ms',
                      ])))
                .go();
            // Every row must be re-published to Drive once; updated_at_ms is
            // deliberately NOT bumped so LWW stays fair against the bot.
            await update(categories)
                .write(const CategoriesCompanion(dirty: Value(true)));
            await update(transactions)
                .write(const TransactionsCompanion(dirty: Value(true)));
            await update(settings)
                .write(const SettingsCompanion(dirty: Value(true)));
          }
        },
      );

  /// Seeds the FIXED contract categories and the settings singleton so a
  /// standalone app merges cleanly with a server on first sync.
  Future<void> _seed() async {
    await batch((b) {
      b.insertAll(
        categories,
        [
          for (final c in seedCategories)
            CategoriesCompanion.insert(
              id: c.id,
              name: c.name,
              emoji: c.emoji,
              color: c.color,
              kind: c.kind,
              sortOrder: Value(c.sortOrder),
              updatedAtMs: seedUpdatedAtMs,
              dirty: const Value(false),
            ),
        ],
        mode: InsertMode.insertOrIgnore,
      );
      b.insert(
        settings,
        SettingsCompanion.insert(
          id: settingsRowId,
          currency: defaultCurrency,
          language: const Value(defaultLanguage),
          updatedAtMs: seedUpdatedAtMs,
          dirty: const Value(false),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  // ---- meta key-value helpers -------------------------------------------

  Future<String?> getMeta(String key) async {
    final row = await (select(meta)..where((m) => m.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> setMeta(String key, String value) =>
      into(meta).insertOnConflictUpdate(MetaCompanion.insert(
        key: key,
        value: value,
      ));

  Future<void> deleteMeta(String key) =>
      (delete(meta)..where((m) => m.key.equals(key))).go();

  Stream<String?> watchMeta(String key) =>
      (select(meta)..where((m) => m.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);
}
