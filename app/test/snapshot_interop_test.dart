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
import 'package:tally/data/repo/transactions_repository.dart'
    show sortedForDisplay;

File _fixture([String name = 'snapshot.example.json']) {
  // Tests run with CWD = the app package root.
  final f = File('../docs/fixtures/$name');
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
      expect(snap.schema, 3);
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

    test('accounts decode, including a rename, a debt and a tombstone', () {
      expect(snap.accounts, hasLength(4));

      final cash = snap.accounts.firstWhere(
        (Account a) => a.id == 'a1c7e2f0-0001-4a00-9000-000000000001',
      );
      expect(cash.name, 'Cash');
      expect(cash.kind, 'cash');
      expect(cash.emoji, '💵');
      expect(cash.color, '#4CAF7D');
      expect(cash.openingBalanceMinor, 0);
      expect(cash.sortOrder, 0);
      expect(cash.updatedAtMs, 1755000000000);
      expect(cash.deletedAtMs, isNull);

      // A card carrying debt. An unsigned decode would wrap this into an
      // enormous positive balance.
      final card = snap.accounts.firstWhere(
        (Account a) => a.id == 'a1c7e2f0-0002-4a00-9000-000000000002',
      );
      expect(card.openingBalanceMinor, -125000);

      // A renamed seed account keeps its literal name, and its opening
      // balance is past double precision.
      final savings = snap.accounts.firstWhere(
        (Account a) => a.id == 'a1c7e2f0-0003-4a00-9000-000000000003',
      );
      expect(savings.name, 'Жамғарма');
      expect(savings.kind, 'savings');
      expect(savings.openingBalanceMinor, 9007199254740993);

      // A closed account arrives as a tombstone, not as an absence.
      final closed = snap.accounts.firstWhere(
        (Account a) => a.id == 'a1c7e2f0-0f01-4a00-9000-000000000f01',
      );
      expect(closed.deletedAtMs, 1787158600000);
    });

    test('transfers decode with both accounts and no category', () {
      final xfer = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000006',
      );
      expect(xfer.kind, 'transfer');
      expect(xfer.amountMinor, 500000);
      // A transfer is not spending, so it carries no category at all.
      expect(xfer.categoryId, isEmpty);
      expect(xfer.accountId, 'a1c7e2f0-0002-4a00-9000-000000000002');
      expect(xfer.toAccountId, 'a1c7e2f0-0003-4a00-9000-000000000003');
      expect(xfer.note, 'oyiga jamgʻarma · в накопления');
    });

    test('transactions decode, including empty note and tombstone', () {
      expect(snap.transactions, hasLength(6));

      final shop = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000001',
      );
      expect(shop.kind, 'expense');
      expect(shop.amountMinor, 24850);
      expect(shop.categoryId, 'c1a7e2f0-0001-4a00-9000-000000000001');
      expect(shop.accountId, 'a1c7e2f0-0002-4a00-9000-000000000002');
      expect(shop.toAccountId, isEmpty);
      expect(shop.note, 'weekly shop');
      expect(shop.occurredAt, '2026-08-19T09:30:00Z');
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

    test('manual placement decodes, and beats time inside a day', () {
      // The two hand-placed rows share a day and the EARLIER one is placed
      // first, so a peer that ignored sort_order and sorted by time alone
      // would show them the other way round.
      final placedFirst = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000002',
      );
      final placedSecond = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000001',
      );
      expect(placedFirst.sortOrder, 1);
      expect(placedSecond.sortOrder, 2);
      expect(placedFirst.occurredAt.compareTo(placedSecond.occurredAt),
          lessThan(0),
          reason: 'the fixture must place the earlier row first');

      // Everything untouched by hand decodes as 0, not as an implicit index.
      final untouched = snap.transactions.firstWhere(
        (Transaction t) => t.id == 'aaaaaaaa-0000-4000-8000-000000000003',
      );
      expect(untouched.sortOrder, 0);

      // And the ordering rule actually puts them in that order.
      final ordered = sortedForDisplay(<Transaction>[placedSecond, placedFirst]);
      expect(ordered.first.id, placedFirst.id);
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
      expect(snap.settings!.defaultAccountId,
          'a1c7e2f0-0002-4a00-9000-000000000002');
      expect(snap.settings!.updatedAtMs, 1787155000000);
    });

    test('re-encoding produces a payload the fixture parser accepts', () {
      final reencoded = utf8.encode(jsonEncode(snap.toJson()));
      final round = TallySnapshot.decode(reencoded);

      expect(round.deviceId, snap.deviceId);
      expect(round.accounts, hasLength(snap.accounts.length));
      expect(round.categories, hasLength(snap.categories.length));
      expect(round.transactions, hasLength(snap.transactions.length));
      expect(round.settings!.language, 'ru');
      // A negative opening balance and one past double precision must both
      // survive a round trip untouched.
      expect(
        round.accounts
            .firstWhere(
              (Account a) => a.id == 'a1c7e2f0-0002-4a00-9000-000000000002',
            )
            .openingBalanceMinor,
        -125000,
      );
      expect(
        round.accounts
            .firstWhere(
              (Account a) => a.id == 'a1c7e2f0-0003-4a00-9000-000000000003',
            )
            .openingBalanceMinor,
        9007199254740993,
      );
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

  // A peer that has not been updated yet keeps publishing schema 1. Refusing
  // to read it would strand that device, so the pre-accounts fixture must
  // still parse — with every transaction booked to the default account, which
  // is exactly where the local v3 migration puts this peer's own old rows.
  group('schema 1 fixture stays readable', () {
    late TallySnapshot v1;

    setUpAll(() {
      v1 = TallySnapshot.decode(
          _fixture('snapshot.v1.example.json').readAsBytesSync());
    });

    test('parses and carries no accounts', () {
      expect(v1.schema, 1);
      expect(v1.accounts, isEmpty);
      expect(v1.transactions, hasLength(5));
    });

    test('account-less transactions book to the default account', () {
      for (final Transaction t in v1.transactions) {
        expect(t.accountId, defaultAccountId,
            reason: '${t.id} should fall back to the seed cash account');
        expect(t.toAccountId, isEmpty);
      }
    });

    test('a v1 settings row leaves default_account_id EMPTY', () {
      // Empty is load-bearing here: it means "unchanged". Substituting the
      // seed account would make the old peer look like it had actively chosen
      // cash, and under last-write-wins a stale snapshot from the un-upgraded
      // device would then overwrite an account the owner picked in the app.
      expect(v1.settings, isNotNull);
      expect(v1.settings!.defaultAccountId, isEmpty);
    });
  });
}
