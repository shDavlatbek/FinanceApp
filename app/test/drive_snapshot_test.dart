/// Snapshot envelope: exact JSON shape from docs/ARCHITECTURE.md, plus a
/// full encode -> decode round trip including tombstones and empty notes.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/constants.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/drive/snapshot.dart';

Category _category({
  String id = 'c1a7e2f0-0001-4a00-9000-000000000001',
  String name = 'Groceries',
  int updatedAtMs = seedUpdatedAtMs,
  int? deletedAtMs,
  bool dirty = false,
}) =>
    Category(
      id: id,
      name: name,
      emoji: '🛒',
      color: '#4CAF7D',
      kind: Kind.expense,
      sortOrder: 0,
      updatedAtMs: updatedAtMs,
      deletedAtMs: deletedAtMs,
      dirty: dirty,
    );

Transaction _transaction({
  String id = 'aaaaaaaa-0000-4000-9000-000000000001',
  String note = 'weekly stuff',
  int updatedAtMs = 5000,
  int? deletedAtMs,
  bool dirty = false,
  String kind = Kind.expense,
  String categoryId = 'c1a7e2f0-0001-4a00-9000-000000000001',
  String accountId = defaultAccountId,
  String toAccountId = '',
}) =>
    Transaction(
      id: id,
      kind: kind,
      amountMinor: 25000,
      categoryId: categoryId,
      accountId: accountId,
      toAccountId: toAccountId,
      note: note,
      occurredAt: '2026-08-19T10:00:00Z',
      source: TxSource.telegram,
      createdAtMs: 4000,
      updatedAtMs: updatedAtMs,
      deletedAtMs: deletedAtMs,
      dirty: dirty,
    );

void main() {
  group('snapshot JSON', () {
    test('envelope carries exactly the contract fields', () {
      final TallySnapshot snapshot = TallySnapshot(
        deviceId: 'b2c3',
        deviceName: 'Pixel 7',
        writtenAtMs: 1787160000000,
        categories: <Category>[_category()],
        transactions: <Transaction>[_transaction()],
        settings: SettingsRow(
          id: settingsRowId,
          currency: 'EUR',
          language: 'ru',
          defaultAccountId: defaultAccountId,
          updatedAtMs: 7000,
          dirty: true,
        ),
      );

      final Map<String, Object?> json = snapshot.toJson();
      expect(json.keys, <String>[
        'schema',
        'device_id',
        'device_name',
        'written_at_ms',
        'accounts',
        'categories',
        'transactions',
        'settings',
      ]);
      expect(json['schema'], snapshotSchemaVersion);
      expect(json['device_id'], 'b2c3');
      expect(json['device_name'], 'Pixel 7');
      expect(json['written_at_ms'], 1787160000000);

      final Map<String, Object?> cat =
          (json['categories']! as List<Object?>).single! as Map<String, Object?>;
      expect(cat.keys, <String>[
        'id',
        'name',
        'emoji',
        'color',
        'kind',
        'sort_order',
        'updated_at_ms',
        'deleted_at_ms',
      ]);

      final Map<String, Object?> tx = (json['transactions']! as List<Object?>)
          .single! as Map<String, Object?>;
      expect(tx.keys, <String>[
        'id',
        'kind',
        'amount_minor',
        'category_id',
        'account_id',
        'to_account_id',
        'note',
        'occurred_at',
        'source',
        'created_at_ms',
        'updated_at_ms',
        'deleted_at_ms',
      ]);

      final Map<String, Object?> settings =
          json['settings']! as Map<String, Object?>;
      expect(settings, <String, Object?>{
        'id': 'settings',
        'currency': 'EUR',
        'language': 'ru',
        'default_account_id': defaultAccountId,
        'updated_at_ms': 7000,
      });

      // The local-only dirty flag never leaves the device.
      expect(jsonEncode(json), isNot(contains('dirty')));
    });

    test('round-trips tombstones, empty notes and a null settings row', () {
      final TallySnapshot original = TallySnapshot(
        deviceId: 'device-a',
        deviceName: 'Windows PC',
        writtenAtMs: 1787160000123,
        categories: <Category>[
          _category(dirty: true),
          _category(
            id: 'c1a7e2f0-000b-4a00-9000-00000000000b',
            name: 'Other',
            updatedAtMs: 9000,
            deletedAtMs: 9000, // archived category tombstone
          ),
        ],
        transactions: <Transaction>[
          _transaction(note: '', dirty: true),
          _transaction(
            id: 'aaaaaaaa-0000-4000-9000-000000000002',
            updatedAtMs: 6000,
            deletedAtMs: 6000, // deleted transaction tombstone
          ),
        ],
        settings: null,
      );

      final TallySnapshot decoded = TallySnapshot.decode(original.encode());

      expect(decoded.schema, snapshotSchemaVersion);
      expect(decoded.deviceId, 'device-a');
      expect(decoded.deviceName, 'Windows PC');
      expect(decoded.writtenAtMs, 1787160000123);
      expect(decoded.settings, isNull);

      // Rows come back identical except that dirty is always cleared.
      expect(decoded.categories, hasLength(2));
      expect(decoded.categories.first,
          original.categories.first.copyWith(dirty: false));
      expect(decoded.categories[1].deletedAtMs, 9000);

      expect(decoded.transactions, hasLength(2));
      expect(decoded.transactions.first.note, '');
      expect(decoded.transactions.first.dirty, isFalse);
      expect(decoded.transactions[1].deletedAtMs, 6000);
      expect(decoded.transactions[1].updatedAtMs, 6000);

      // Re-encoding is stable.
      expect(decoded.encode(), original.encode());
    });

    test('a decoded settings row defaults language to ""', () {
      final SettingsRow row = settingsFromJson(<String, Object?>{
        'id': 'settings',
        'currency': 'USD',
        'updated_at_ms': 1,
      });
      expect(row.language, defaultLanguage);
      expect(row.dirty, isFalse);
    });

    test('rejects garbage, a missing schema and a future schema', () {
      expect(() => TallySnapshot.decode(utf8.encode('not json')),
          throwsA(isA<SnapshotFormatException>()));
      expect(() => TallySnapshot.decode(utf8.encode('[1,2,3]')),
          throwsA(isA<SnapshotFormatException>()));
      expect(() => TallySnapshot.decode(utf8.encode('{"device_id":"x"}')),
          throwsA(isA<SnapshotFormatException>()));
      expect(
        () => TallySnapshot.decode(utf8.encode(jsonEncode(<String, Object?>{
          'schema': snapshotSchemaVersion + 1,
          'categories': <Object?>[],
          'transactions': <Object?>[],
        }))),
        throwsA(isA<SnapshotFormatException>()),
      );
    });

    // A peer file is hand-editable, so one bad ROW must not cost the whole
    // file. The envelope still throws; rows are skipped and reported, exactly
    // as the Go peer does.
    test('skips a malformed row instead of discarding the whole snapshot', () {
      final TallySnapshot snap =
          TallySnapshot.decode(utf8.encode(jsonEncode(<String, Object?>{
        'schema': snapshotSchemaVersion,
        'categories': <Object?>[
          <String, Object?>{'id': 'x'}, // missing name/kind/updated_at_ms
          categoryToJson(_category()),
        ],
        'transactions': <Object?>[transactionToJson(_transaction())],
      })));

      // The good rows survived...
      expect(snap.categories, hasLength(1));
      expect(snap.transactions, hasLength(1));
      // ...and the bad one was reported rather than silently dropped.
      expect(snap.skipped, hasLength(1));
      expect(snap.skipped.single, contains('category'));
    });

    test('file name follows tally-<device_id>.json', () {
      expect(snapshotFileName('b2c3'), 'tally-b2c3.json');
    });
  });
}
