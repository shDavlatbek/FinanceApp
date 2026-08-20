/// The Day / Month lens: day-scoped totals, breakdowns and transaction lists,
/// and the calendar-day boundaries they hinge on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/constants.dart';
import 'package:tally/core/dates.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/repo/summaries_repository.dart';
import 'package:tally/data/repo/transactions_repository.dart';

import 'support/test_db.dart';

const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';
const String _salary = 'c1a7e2f0-0101-4a00-9000-000000000101';

void main() {
  late AppDatabase db;
  late TransactionsRepository txs;
  late SummariesRepository summaries;

  // A fixed local day well inside a month, so "yesterday" and "tomorrow"
  // never cross a month boundary and confuse the assertions.
  final DateTime day = DateTime(2026, 8, 19);

  setUp(() {
    db = openTestDb();
    txs = TransactionsRepository(db);
    summaries = SummariesRepository(db);
  });
  tearDown(() => db.close());

  Future<void> spend(int amount, DateTime at) => txs.insert(
        kind: Kind.expense,
        amountMinor: amount,
        categoryId: _groceries,
        occurredAt: at,
      );

  group('day boundaries', () {
    test('a day holds midnight through 23:59:59 and nothing either side',
        () async {
      await spend(100, DateTime(2026, 8, 19, 0, 0, 0)); // first instant
      await spend(200, DateTime(2026, 8, 19, 23, 59, 59)); // last instant
      await spend(400, DateTime(2026, 8, 18, 23, 59, 59)); // the day before
      await spend(800, DateTime(2026, 8, 20, 0, 0, 0)); // the day after

      final PeriodTotals totals = await summaries.watchDayTotals(day).first;
      expect(totals.expenseMinor, 300);
      expect(totals.start, dayStart(day));

      final PeriodTotals before =
          await summaries.watchDayTotals(addDays(day, -1)).first;
      expect(before.expenseMinor, 400);
      final PeriodTotals after =
          await summaries.watchDayTotals(addDays(day, 1)).first;
      expect(after.expenseMinor, 800);
    });

    test('the month total is the sum of its days', () async {
      await spend(100, DateTime(2026, 8, 19, 9));
      await spend(200, DateTime(2026, 8, 20, 9));
      await spend(400, DateTime(2026, 7, 31, 9)); // previous month

      final PeriodTotals month = await summaries.watchMonthTotals(day).first;
      expect(month.expenseMinor, 300);
    });

    test('income and expenses are kept apart in the day lens', () async {
      await spend(2500, DateTime(2026, 8, 19, 9));
      await txs.insert(
        kind: Kind.income,
        amountMinor: 90000,
        categoryId: _salary,
        occurredAt: DateTime(2026, 8, 19, 10),
      );

      final PeriodTotals totals = await summaries.watchDayTotals(day).first;
      expect(totals.expenseMinor, 2500);
      expect(totals.incomeMinor, 90000);
      expect(totals.netMinor, 87500);
    });
  });

  group('day lists and breakdowns', () {
    test('watchDay returns only that day, newest first', () async {
      await spend(100, DateTime(2026, 8, 19, 9));
      await spend(200, DateTime(2026, 8, 19, 18));
      await spend(400, DateTime(2026, 8, 18, 9));

      final List<Transaction> list = await txs.watchDay(day).first;
      expect(list, hasLength(2));
      expect(list.first.amountMinor, 200); // newest first
      expect(list.last.amountMinor, 100);
    });

    test('the day breakdown covers only that day', () async {
      await spend(100, DateTime(2026, 8, 19, 9));
      await spend(9999, DateTime(2026, 8, 18, 9));

      final List<CategoryTotal> cats =
          await summaries.watchDayCategoryTotals(day).first;
      expect(cats, hasLength(1));
      expect(cats.single.category.id, _groceries);
      expect(cats.single.totalMinor, 100);
    });
  });

  group('day trend', () {
    test('is zero-filled and ends on the anchor day', () async {
      await spend(500, DateTime(2026, 8, 19, 9));
      await spend(700, DateTime(2026, 8, 17, 9));

      final List<PeriodTotals> trend =
          await summaries.watchLastDays(day, days: 5).first;
      expect(trend, hasLength(5));
      // Oldest first, ending on the anchor.
      expect(trend.first.start, dayStart(addDays(day, -4)));
      expect(trend.last.start, dayStart(day));
      expect(trend.last.expenseMinor, 500);
      expect(
        trend
            .firstWhere(
                (PeriodTotals p) => isSameDay(p.start, addDays(day, -2)))
            .expenseMinor,
        700,
      );
      // Days with nothing logged are present as zeros, not missing.
      expect(
        trend
            .firstWhere(
                (PeriodTotals p) => isSameDay(p.start, addDays(day, -1)))
            .expenseMinor,
        0,
      );
    });
  });

  group('date helpers', () {
    test('addDays and nextDayStart land on local midnight', () {
      expect(nextDayStart(DateTime(2026, 8, 19, 17, 30)), DateTime(2026, 8, 20));
      expect(addDays(DateTime(2026, 8, 31), 1), DateTime(2026, 9, 1));
      expect(addDays(DateTime(2026, 1, 1), -1), DateTime(2025, 12, 31));
      // Leap day, because February is where naive date maths goes wrong.
      expect(addDays(DateTime(2028, 2, 28), 1), DateTime(2028, 2, 29));
    });

    test('isSameDay ignores the clock', () {
      expect(
        isSameDay(DateTime(2026, 8, 19, 0, 0), DateTime(2026, 8, 19, 23, 59)),
        isTrue,
      );
      expect(
        isSameDay(DateTime(2026, 8, 19, 23, 59), DateTime(2026, 8, 20, 0, 0)),
        isFalse,
      );
    });

    test('day bounds are half-open, so no instant is counted twice', () {
      final bounds = dayQueryBounds(day);
      expect(bounds.start, occurredAtQueryBound(dayStart(day)));
      expect(bounds.end, occurredAtQueryBound(nextDayStart(day)));
      expect(bounds.start.compareTo(bounds.end) < 0, isTrue);
    });
  });

  group('PeriodMode', () {
    test('parses its persisted name and defaults to month', () {
      expect(PeriodMode.fromName('day'), PeriodMode.day);
      expect(PeriodMode.fromName('month'), PeriodMode.month);
      expect(PeriodMode.fromName(null), PeriodMode.month);
      expect(PeriodMode.fromName('nonsense'), PeriodMode.month);
    });
  });
}
