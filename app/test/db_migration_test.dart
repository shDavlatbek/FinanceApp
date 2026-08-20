/// Schema v1 -> v2 upgrade: `settings.language` is added, the dead REST-sync
/// meta keys are dropped, every row is re-marked dirty for the first Drive
/// publish — and not a byte of user data is lost.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/constants.dart';
import 'package:tally/data/db/database.dart';

/// Exactly the tables drift generated for schemaVersion 1 — note that
/// `settings` has no `language` column.
const List<String> _v1Schema = <String>[
  '''
  CREATE TABLE transactions (
    id TEXT NOT NULL,
    kind TEXT NOT NULL,
    amount_minor INTEGER NOT NULL,
    category_id TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    occurred_at TEXT NOT NULL,
    source TEXT NOT NULL DEFAULT 'app',
    created_at_ms INTEGER NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    deleted_at_ms INTEGER NULL,
    dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1)),
    PRIMARY KEY (id)
  )''',
  '''
  CREATE TABLE categories (
    id TEXT NOT NULL,
    name TEXT NOT NULL,
    emoji TEXT NOT NULL,
    color TEXT NOT NULL,
    kind TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    updated_at_ms INTEGER NOT NULL,
    deleted_at_ms INTEGER NULL,
    dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1)),
    PRIMARY KEY (id)
  )''',
  '''
  CREATE TABLE settings (
    id TEXT NOT NULL,
    currency TEXT NOT NULL,
    updated_at_ms INTEGER NOT NULL,
    dirty INTEGER NOT NULL DEFAULT 0 CHECK (dirty IN (0, 1)),
    PRIMARY KEY (id)
  )''',
  '''
  CREATE TABLE meta (
    key TEXT NOT NULL,
    value TEXT NOT NULL,
    PRIMARY KEY (key)
  )''',
];

void main() {
  test('a v1 database upgrades to v2 without losing user data', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory(setup: (rawDb) {
      for (final String statement in _v1Schema) {
        rawDb.execute(statement);
      }
      // A user who had been running v1 for a while.
      rawDb.execute(
        "INSERT INTO categories VALUES ('$_groceriesId', 'Groceries', '🛒', "
        "'#4CAF7D', 'expense', 0, $seedUpdatedAtMs, NULL, 0)",
      );
      rawDb.execute(
        "INSERT INTO categories VALUES ('user-cat', 'Cats', '🐈', '#FFAA00', "
        "'expense', 11, 1755000009999, NULL, 0)",
      );
      rawDb.execute(
        "INSERT INTO transactions VALUES ('tx-1', 'expense', 25000, "
        "'$_groceriesId', 'weekly stuff', '2026-08-01T10:00:00Z', 'app', "
        '1755000001000, 1755000001000, NULL, 0)',
      );
      rawDb.execute(
        "INSERT INTO settings VALUES ('settings', 'EUR', 1755000002000, 0)",
      );
      rawDb.execute("INSERT INTO meta VALUES ('server_url', 'https://old')");
      rawDb.execute("INSERT INTO meta VALUES ('api_token', 'secret')");
      rawDb.execute("INSERT INTO meta VALUES ('last_seq', '99')");
      rawDb.execute("INSERT INTO meta VALUES ('last_sync_ms', '12345')");
      rawDb.execute("INSERT INTO meta VALUES ('ui_theme_mode', 'light')");
      rawDb.userVersion = 1;
    }));
    addTearDown(db.close);

    // Opening runs the migration.
    final List<Transaction> txs = await db.select(db.transactions).get();
    expect(txs, hasLength(1));
    expect(txs.single.id, 'tx-1');
    expect(txs.single.note, 'weekly stuff');
    expect(txs.single.amountMinor, 25000);
    expect(txs.single.updatedAtMs, 1755000001000); // NOT bumped
    expect(txs.single.dirty, isTrue); // re-marked for the first Drive publish

    final List<Category> cats = await db.select(db.categories).get();
    expect(cats.map((Category c) => c.id), containsAll(<String>[
      _groceriesId,
      'user-cat',
    ]));
    final Category renamed = cats.singleWhere((Category c) => c.id == 'user-cat');
    expect(renamed.name, 'Cats');
    expect(renamed.updatedAtMs, 1755000009999);
    expect(cats.every((Category c) => c.dirty), isTrue);

    // The new column exists and defaults to "follow the device locale".
    final SettingsRow settings = await db.select(db.settings).getSingle();
    expect(settings.currency, 'EUR'); // preserved
    expect(settings.language, defaultLanguage);
    expect(settings.updatedAtMs, 1755000002000);
    expect(settings.dirty, isTrue);

    // The bespoke REST transport's meta keys are gone…
    expect(await db.getMeta('server_url'), isNull);
    expect(await db.getMeta('api_token'), isNull);
    expect(await db.getMeta('last_seq'), isNull);
    expect(await db.getMeta(MetaKeys.lastSyncMs), isNull);
    // …while UI-owned keys survive.
    expect(await db.getMeta('ui_theme_mode'), 'light');

    // And a language write works against the migrated schema.
    await db.into(db.settings).insertOnConflictUpdate(
          settings.copyWith(language: 'uz', updatedAtMs: 1755000003000),
        );
    expect((await db.select(db.settings).getSingle()).language, 'uz');
  });

  test('a fresh database is created at v2 with the language column', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final SettingsRow settings = await db.select(db.settings).getSingle();
    expect(settings.language, defaultLanguage);
    expect(db.schemaVersion, 2);
  });
}

const String _groceriesId = 'c1a7e2f0-0001-4a00-9000-000000000001';
