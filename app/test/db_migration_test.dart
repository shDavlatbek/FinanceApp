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

/// Exactly the tables drift generated for schemaVersion 2 — `settings` has
/// `language` but there is no `accounts` table and no account columns.
const List<String> _v2Schema = <String>[
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
    language TEXT NOT NULL DEFAULT '',
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

  test('a v2 database upgrades to v3, gaining accounts', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory(setup: (rawDb) {
      for (final String statement in _v2Schema) {
        rawDb.execute(statement);
      }
      rawDb.execute(
        "INSERT INTO categories VALUES ('$_groceriesId', 'Groceries', '🛒', "
        "'#4CAF7D', 'expense', 0, $seedUpdatedAtMs, NULL, 0)",
      );
      rawDb.execute(
        "INSERT INTO transactions VALUES ('tx-old', 'expense', 24850, "
        "'$_groceriesId', 'weekly shop', '2026-08-01T10:00:00Z', 'app', "
        '1755000001000, 1755000001000, NULL, 0)',
      );
      // A settings row still carrying the OLD seed timestamp: the placeholder
      // that could never move under strict LWW.
      rawDb.execute(
        "INSERT INTO settings VALUES ('settings', 'UZS', 'ru', "
        '$seedUpdatedAtMs, 0)',
      );
      rawDb.userVersion = 2;
    }));
    addTearDown(db.close);

    // The seed accounts arrive on upgrade, not just on a fresh install.
    final List<Account> accounts = await db.select(db.accounts).get();
    expect(accounts, hasLength(seedAccounts.length));
    expect(accounts.map((Account a) => a.id), contains(defaultAccountId));

    // The pre-accounts transaction keeps every byte and books to cash —
    // exactly what the server's migration independently decides, so the two
    // peers converge without either publishing anything.
    final Transaction tx = await db.select(db.transactions).getSingle();
    expect(tx.id, 'tx-old');
    expect(tx.amountMinor, 24850);
    expect(tx.note, 'weekly shop');
    expect(tx.accountId, defaultAccountId);
    expect(tx.toAccountId, isEmpty);
    expect(tx.updatedAtMs, 1755000001000); // NOT bumped
    expect(tx.dirty, isFalse); // and NOT republished

    final SettingsRow settings = await db.select(db.settings).getSingle();
    expect(settings.currency, 'UZS'); // preserved
    expect(settings.language, 'ru'); // preserved
    expect(settings.defaultAccountId, defaultAccountId);
    // The stuck placeholder is unstuck, so currency and language can finally
    // move between the peers instead of being frozen by a tie.
    expect(settings.updatedAtMs, settingsUnsetMs);

    // The widened `kind` accepts a transfer now.
    await db.into(db.transactions).insert(Transaction(
          id: 'tx-transfer',
          kind: Kind.transfer,
          amountMinor: 5000,
          categoryId: '',
          accountId: defaultAccountId,
          toAccountId: 'a1c7e2f0-0003-4a00-9000-000000000003',
          note: '',
          occurredAt: '2026-08-20T10:00:00Z',
          sortOrder: 0,
          source: TxSource.app,
          createdAtMs: 1755000002000,
          updatedAtMs: 1755000002000,
          deletedAtMs: null,
          dirty: true,
        ));
    expect(await db.select(db.transactions).get(), hasLength(2));

    // Manual order (v4) arrives on the same upgrade. Every pre-existing row
    // must read as "never placed by hand", so nothing visibly reorders when
    // the owner updates the app.
    final Transaction migrated = await (db.select(db.transactions)
          ..where((t) => t.id.equals('tx-old')))
        .getSingle();
    expect(migrated.sortOrder, 0);
    expect(migrated.occurredAt, '2026-08-01T10:00:00Z',
        reason: 'the upgrade must not touch when an entry happened');
  });

  test('a fresh database is created at v4 with accounts and manual order', () async {
    final AppDatabase db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final SettingsRow settings = await db.select(db.settings).getSingle();
    expect(settings.language, defaultLanguage);
    expect(settings.defaultAccountId, defaultAccountId);
    expect(db.schemaVersion, 4);

    // The seed accounts are part of the contract: savings and investments
    // must exist out of the box so "send to savings" works with no setup.
    final List<Account> accounts = await db.select(db.accounts).get();
    expect(accounts, hasLength(seedAccounts.length));
    expect(
      accounts.map((Account a) => a.id).toSet(),
      seedAccounts.map((SeedAccount a) => a.id).toSet(),
    );
    expect(accounts.every((Account a) => a.updatedAtMs == seedUpdatedAtMs),
        isTrue);
    // Both peers seed byte-identical accounts, so there is nothing to publish.
    expect(accounts.every((Account a) => a.dirty), isFalse);
  });
}

const String _groceriesId = 'c1a7e2f0-0001-4a00-9000-000000000001';
