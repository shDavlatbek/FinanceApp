/// Manual placement inside a day, and the time-of-day ordering it overrides.
///
/// The rule (docs/ARCHITECTURE.md v4): newest day first, then `sort_order`
/// ascending inside the day, then newest time first. `sort_order == 0` means
/// "never placed by hand", so an untouched day is pure time order and a new
/// entry lands at the top of a day that has been hand-ordered.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/constants.dart';
import 'package:tally/core/dates.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/repo/transactions_repository.dart';

import 'support/test_db.dart';

const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';

void main() {
  late AppDatabase db;
  late TransactionsRepository txs;

  setUp(() {
    db = openTestDb();
    txs = TransactionsRepository(db);
  });
  tearDown(() => db.close());

  Future<Transaction> spend(int amount, DateTime at) => txs.insert(
        kind: Kind.expense,
        amountMinor: amount,
        categoryId: _groceries,
        occurredAt: at,
      );

  Future<List<String>> notesInOrder() async {
    final List<Transaction> rows = await txs.watchFiltered().first;
    return <String>[for (final Transaction t in rows) '${t.amountMinor}'];
  }

  group('default ordering', () {
    test('an untouched day is newest-time first', () async {
      await spend(100, DateTime(2026, 8, 19, 9));
      await spend(200, DateTime(2026, 8, 19, 17));
      await spend(300, DateTime(2026, 8, 19, 13));

      expect(await notesInOrder(), <String>['200', '300', '100']);
    });

    test('new rows are unplaced, not implicitly numbered', () async {
      final Transaction t = await spend(100, DateTime(2026, 8, 19, 9));
      expect(t.sortOrder, unplacedSortOrder);
      expect(unplacedSortOrder, 0);
    });

    test('days stay newest-first regardless of placement', () async {
      await spend(100, DateTime(2026, 8, 18, 9));
      final Transaction later = await spend(200, DateTime(2026, 8, 19, 9));
      // Place the newer day's only row at the back of its own day.
      await txs.reorderDay(<String>[later.id]);

      // The older day must still come second: sort_order never competes
      // across days.
      expect(await notesInOrder(), <String>['200', '100']);
    });
  });

  group('manual placement', () {
    test('placing a day overrides its time order', () async {
      final Transaction morning = await spend(100, DateTime(2026, 8, 19, 9));
      final Transaction evening = await spend(200, DateTime(2026, 8, 19, 21));
      // Time order is evening, morning. Ask for the reverse.
      await txs.reorderDay(<String>[morning.id, evening.id]);

      expect(await notesInOrder(), <String>['100', '200']);
    });

    test('placement is numbered 1..N and marks rows for sync', () async {
      final Transaction a = await spend(100, DateTime(2026, 8, 19, 9));
      final Transaction b = await spend(200, DateTime(2026, 8, 19, 21));
      await txs.reorderDay(<String>[b.id, a.id]);

      final Transaction rb = (await txs.getById(b.id))!;
      final Transaction ra = (await txs.getById(a.id))!;
      expect(rb.sortOrder, 1);
      expect(ra.sortOrder, 2);
      // The placement has to travel to the other peer.
      expect(rb.dirty, isTrue);
      expect(ra.dirty, isTrue);
      expect(rb.updatedAtMs, greaterThanOrEqualTo(b.updatedAtMs));
    });

    test('a new entry lands on top of a hand-ordered day', () async {
      final Transaction a = await spend(100, DateTime(2026, 8, 19, 9));
      final Transaction b = await spend(200, DateTime(2026, 8, 19, 21));
      await txs.reorderDay(<String>[a.id, b.id]);

      // Logged at midday — between the two by time, but unplaced.
      await spend(300, DateTime(2026, 8, 19, 13));
      expect(await notesInOrder(), <String>['300', '100', '200']);
    });

    test('re-placing a day renumbers it and settles', () async {
      final Transaction a = await spend(100, DateTime(2026, 8, 19, 9));
      final Transaction b = await spend(200, DateTime(2026, 8, 19, 21));
      final Transaction c = await spend(300, DateTime(2026, 8, 19, 13));

      await txs.reorderDay(<String>[a.id, b.id, c.id]);
      expect(await notesInOrder(), <String>['100', '200', '300']);

      await txs.reorderDay(<String>[c.id, a.id, b.id]);
      expect(await notesInOrder(), <String>['300', '100', '200']);
    });

    test('reordering nothing is a no-op, not a crash', () async {
      await spend(100, DateTime(2026, 8, 19, 9));
      await txs.reorderDay(const <String>[]);
      expect(await notesInOrder(), <String>['100']);
    });
  });

  group('sortedForDisplay', () {
    Transaction row(String id, String occurredAt, int sortOrder) => Transaction(
          id: id,
          kind: Kind.expense,
          amountMinor: 100,
          categoryId: _groceries,
          accountId: seedCashAccountId,
          toAccountId: '',
          note: '',
          occurredAt: occurredAt,
          sortOrder: sortOrder,
          source: TxSource.app,
          createdAtMs: 1,
          updatedAtMs: 1,
          deletedAtMs: null,
          dirty: false,
        );

    test('is stable and total across days and placements', () {
      final List<Transaction> ordered = sortedForDisplay(<Transaction>[
        row('old-unplaced', '2026-08-18T12:00:00Z', 0),
        row('new-placed-2', '2026-08-19T05:00:00Z', 2),
        row('new-unplaced', '2026-08-19T23:00:00Z', 0),
        row('new-placed-1', '2026-08-19T06:00:00Z', 1),
      ]);
      expect(
        <String>[for (final Transaction t in ordered) t.id],
        <String>['new-unplaced', 'new-placed-1', 'new-placed-2', 'old-unplaced'],
      );
    });

    test('breaks a full tie by creation, never arbitrarily', () {
      final Transaction older = row('older', '2026-08-19T12:00:00Z', 0);
      final Transaction newer = Transaction(
        id: 'newer',
        kind: Kind.expense,
        amountMinor: 100,
        categoryId: _groceries,
        accountId: seedCashAccountId,
        toAccountId: '',
        note: '',
        occurredAt: '2026-08-19T12:00:00Z',
        sortOrder: 0,
        source: TxSource.app,
        createdAtMs: 2,
        updatedAtMs: 2,
        deletedAtMs: null,
        dirty: false,
      );
      expect(
        <String>[for (final t in sortedForDisplay(<Transaction>[older, newer])) t.id],
        <String>['newer', 'older'],
      );
    });

    test('groups by LOCAL day, which is what the UI groups by', () {
      // Both instants are the same UTC day but may straddle a local midnight;
      // whatever the host offset, the grouping the sort uses must agree with
      // dayKeyFromOccurredAt, which the History screen uses.
      final List<Transaction> rows = <Transaction>[
        row('a', '2026-08-19T01:00:00Z', 0),
        row('b', '2026-08-19T23:00:00Z', 0),
      ];
      final List<Transaction> ordered = sortedForDisplay(rows);
      final String firstDay = dayKeyFromOccurredAt(ordered.first.occurredAt);
      final String lastDay = dayKeyFromOccurredAt(ordered.last.occurredAt);
      expect(firstDay.compareTo(lastDay), greaterThanOrEqualTo(0),
          reason: 'days must come out newest-first');
    });
  });
}
