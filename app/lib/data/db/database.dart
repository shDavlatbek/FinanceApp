import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../core/constants.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [Transactions, Categories, Accounts, Settings, Meta])
class AppDatabase extends _$AppDatabase {
  /// Test-friendly constructor: inject any [QueryExecutor]
  /// (e.g. `NativeDatabase.memory()`).
  AppDatabase(super.e);

  /// Production constructor: opens the on-device database via drift_flutter.
  AppDatabase.open() : super(driftDatabase(name: 'tally'));

  /// v2 (2026-08-19): `settings.language` added; the REST sync meta keys
  /// (server_url / api_token / last_seq) are dropped in favour of the Drive
  /// keys. No user data is touched.
  ///
  /// v3 (2026-08-20): accounts. New `accounts` table, `transactions.account_id`
  /// / `to_account_id`, `settings.default_account_id`, and the `transfer`
  /// transaction kind. Every pre-existing transaction books to the seed cash
  /// account — exactly what the server's own migration does, so the two peers
  /// reach the same answer without either having to publish anything.
  @override
  int get schemaVersion => 4;

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
          if (from < 3) {
            await m.createTable(accounts);
            await m.addColumn(transactions, transactions.accountId);
            await m.addColumn(transactions, transactions.toAccountId);
            await m.addColumn(settings, settings.defaultAccountId);
            await _seedAccounts();
            // Existing rows predate accounts. The column default already books
            // them to cash; this makes it explicit and covers any row written
            // by a build where the default differed. updated_at_ms is NOT
            // bumped and the rows are NOT marked dirty: gaining an account_id
            // is not an edit the peers need to hear about, and the server's
            // migration independently reaches the same answer.
            await (update(transactions)
                  ..where((t) => t.accountId.equals('')))
                .write(const TransactionsCompanion(
                    accountId: Value(defaultAccountId)));
            await (update(settings)
                  ..where((r) => r.defaultAccountId.equals('')))
                .write(const SettingsCompanion(
                    defaultAccountId: Value(defaultAccountId)));
            // Unstick a settings row still carrying the old seed timestamp.
            // Earlier builds seeded the singleton at seedUpdatedAtMs — the very
            // value the SERVER used to seed — so under strict LWW ("ties keep
            // the local row") currency and language could never move in either
            // direction. Only the untouched placeholder matches: any real edit,
            // on either peer, carries a wall-clock timestamp. The server ships
            // the mirror image of this migration.
            await (update(settings)
                  ..where((r) => r.updatedAtMs.equals(seedUpdatedAtMs)))
                .write(const SettingsCompanion(
                    updatedAtMs: Value(settingsUnsetMs)));
          }
          if (from < 4) {
            // Manual ordering. Everything existing keeps 0, which is exactly
            // "never placed by hand" — so nothing visibly reorders on upgrade.
            await m.addColumn(transactions, transactions.sortOrder);
          }
        },
      );

  /// Seeds the FIXED contract accounts so a standalone app merges cleanly
  /// with a server on first sync. Split out of [_seed] because the v3
  /// migration needs it on databases that were seeded before accounts existed.
  Future<void> _seedAccounts() async {
    await batch((b) {
      b.insertAll(
        accounts,
        [
          for (final a in seedAccounts)
            AccountsCompanion.insert(
              id: a.id,
              name: a.name,
              kind: a.kind,
              emoji: a.emoji,
              color: a.color,
              sortOrder: Value(a.sortOrder),
              updatedAtMs: seedUpdatedAtMs,
              dirty: const Value(false),
            ),
        ],
        // insertOrIgnore, so an account the owner archived (tombstoned) is
        // never resurrected by a later migration re-running this.
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Seeds the FIXED contract categories and accounts plus the settings
  /// singleton so a standalone app merges cleanly with a server on first sync.
  Future<void> _seed() async {
    await _seedAccounts();
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
          defaultAccountId: const Value(defaultAccountId),
          // settingsUnsetMs (0), NOT seedUpdatedAtMs: see the constant's doc.
          // A fixed non-zero seed would tie with the server's identical seed
          // and, under strict LWW, freeze currency and language on both peers
          // forever — a server on UZS (exponent 0) would keep storing a typed
          // "250" as 250 minor units while the app rendered it as 2.50 dollars.
          updatedAtMs: settingsUnsetMs,
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
