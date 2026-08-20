/// Cross-implementation guard: the Dart and Go peers must agree, byte for
/// byte, on the snapshot wire format in docs/ARCHITECTURE.md.
///
/// Both sides parse the SAME fixture, `docs/fixtures/snapshot.example.json`,
/// and assert the same values. A field rename, a null-handling difference, or
/// an int64 routed through a double on either side breaks one of these two
/// tests — which is the only cheap way to catch sync divergence without live
/// Google credentials. The Go half lives in
/// server/internal/drive/interop_test.go and reads the same file.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tally/data/drive/snapshot.dart';
import 'package:tally/data/providers.dart';

File _fixture() {
  // Tests run with CWD = the app package root.
  final f = File('../docs/fixtures/snapshot.example.json');
  if (!f.existsSync()) {
    fail('fixture not found at ${f.absolute.path}');
  }
  return f;
}

void main() {
  group('snapshot interop fixture', () {
    late TallySnapshot snap;

    setUpAll(() {
      snap = TallySnapshot.decode(_fixture().readAsBytesSync());
    });

    test('envelope fields decode', () {
      expect(snap.schema, 1);
      expect(snap.deviceId, '11111111-2222-4333-8444-555555555555');
      expect(snap.deviceName, 'Fixture Device');
      expect(snap.writtenAtMs, 1787160000000);
    });

    test('categories decode, tombstone included', () {
      expect(snap.categories, hasLength(4));

      final groceries = snap.categories.firstWhere(
        (Category c) => c.id == 'c1a7e2f0-0001-4a00-9000-000000000001',
      );
      expect(groceries.name, 'Groceries');
      expect(groceries.emoji, '🛒');
      expect(groceries.color, '#4CAF7D');
      expect(groceries.kind, 'expense');
      expect(groceries.sortOrder, 0);
      expect(groceries.updatedAtMs, 1755000000000);
      expect(groceries.deletedAtMs, isNull);

      // A renamed seed category keeps its literal name.
      final cafe = snap.categories.firstWhere(
        (Category c) => c.id == 'c1a7e2f0-0002-4a00-9000-000000000002',
      );
      expect(cafe.name, 'Кофейни');

      // A deleted category arrives as a tombstone, not as an absence.
      final fun = snap.categories.firstWhere(
        (Category c) => c.id == 'c1a7e2f0-0008-4a00-9000-000000000008',
      );
      expect(fun.deletedAtMs, 1787158500000);
    });

    test('transactions decode, including empty note and tombstone', () {
      expect(snap.transactions, hasLength(5));

      final shop = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000001',
      );
      expect(shop.kind, 'expense');
      expect(shop.amountMinor, 24850);
      expect(shop.categoryId, 'c1a7e2f0-0001-4a00-9000-000000000001');
      expect(shop.note, 'weekly shop');
      expect(shop.occurredAt, '2026-08-18T09:30:00Z');
      expect(shop.source, 'app');
      expect(shop.createdAtMs, 1787000000000);
      expect(shop.updatedAtMs, 1787000000000);
      expect(shop.deletedAtMs, isNull);

      final bot = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000002',
      );
      expect(bot.note, isEmpty);
      expect(bot.source, 'telegram');

      final salary = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000003',
      );
      expect(salary.kind, 'income');
      expect(salary.note, 'августовская зарплата · oylik maosh');

      final deleted = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000005',
      );
      expect(deleted.deletedAtMs, 1787157000000);
    });

    test('int64 beyond double precision survives decoding', () {
      final big = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000004',
      );
      // 2^53 + 1: if this ever went through a double it would come back
      // as 9007199254740992.
      expect(big.amountMinor, 9007199254740993);
    });

    test('settings decode, including the v2 language field', () {
      expect(snap.settings, isNotNull);
      expect(snap.settings!.id, 'settings');
      expect(snap.settings!.currency, 'UZS');
      expect(snap.settings!.language, 'ru');
      expect(snap.settings!.updatedAtMs, 1787155000000);
    });

    test('re-encoding produces a payload the fixture parser accepts', () {
      final reencoded = utf8.encode(jsonEncode(snap.toJson()));
      final round = TallySnapshot.decode(reencoded);

      expect(round.deviceId, snap.deviceId);
      expect(round.categories, hasLength(snap.categories.length));
      expect(round.transactions, hasLength(snap.transactions.length));
      expect(round.settings!.language, 'ru');
      expect(
        round.transactions
            .firstWhere(
              (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000004',
            )
            .amountMinor,
        9007199254740993,
      );
      expect(
        round.transactions
            .firstWhere(
              (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000005',
            )
            .deletedAtMs,
        1787157000000,
      );
    });
  });
}
