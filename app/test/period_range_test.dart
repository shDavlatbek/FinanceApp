/// The custom from-to range lens: inclusive day boundaries, range-scoped
/// totals and breakdowns, trend bucketing, and the DateRange value type.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tally/core/constants.dart';
import 'package:tally/core/dates.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/providers.dart' show DateRange;
import 'package:tally/data/repo/summaries_repository.dart';
import 'package:tally/data/repo/transactions_repository.dart';

import 'support/test_db.dart';

const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';
const String _salary = 'c1a7e2f0-0101-4a00-9000-000000000101';

void main() {
  // rangeLabel goes through DateFormat, which needs its locale data loaded.
  setUpAll(() => initializeDateFormatting());

  late AppDatabase db;
  late TransactionsRepository txs;
  late SummariesRepository summaries;

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

  Future<void> earn(int amount, DateTime at) => txs.insert(
        kind: Kind.income,
        amountMinor: amount,
        categoryId: _salary,
        occurredAt: at,
      );

  group('range boundaries', () {
    test('both ends of the range are included in full', () async {
      final DateTime from = DateTime(2026, 8, 10);
      final DateTime to = DateTime(2026, 8, 12);

      // One second before the range, and the last second inside it.
      await spend(100, DateTime(2026, 8, 9, 23, 59, 59));
      await spend(200, DateTime(2026, 8, 10, 0, 0, 0));
      await spend(300, DateTime(2026, 8, 11, 12));
      await spend(400, DateTime(2026, 8, 12, 23, 59, 59));
      await spend(500, DateTime(2026, 8, 13, 0, 0, 0));

      final PeriodTotals totals =
          await summaries.watchRangeTotals(from, to).first;
      expect(totals.expenseMinor, 200 + 300 + 400);
    });

    test('a backwards range is normalized, not empty', () async {
      await spend(700, DateTime(2026, 8, 11, 9));
      final PeriodTotals totals = await summaries
          .watchRangeTotals(DateTime(2026, 8, 12), DateTime(2026, 8, 10))
          .first;
      expect(totals.expenseMinor, 700);
    });

    test('a single-day range behaves like the day lens', () async {
      await spend(250, DateTime(2026, 8, 11, 9));
      await spend(999, DateTime(2026, 8, 12, 9));
      final PeriodTotals totals = await summaries
          .watchRangeTotals(DateTime(2026, 8, 11), DateTime(2026, 8, 11))
          .first;
      expect(totals.expenseMinor, 250);
    });

    test('transfers stay out of range totals', () async {
      await earn(5000, DateTime(2026, 8, 11, 8));
      await spend(1000, DateTime(2026, 8, 11, 9));
      await txs.insertTransfer(
        amountMinor: 400000,
        fromAccountId: 'a1c7e2f0-0001-4a00-9000-000000000001',
        toAccountId: 'a1c7e2f0-0002-4a00-9000-000000000002',
        occurredAt: DateTime(2026, 8, 11, 10),
      );

      final PeriodTotals totals = await summaries
          .watchRangeTotals(DateTime(2026, 8, 10), DateTime(2026, 8, 12))
          .first;
      expect(totals.incomeMinor, 5000);
      expect(totals.expenseMinor, 1000);
      expect(totals.netMinor, 4000);
    });
  });

  group('range lists and breakdowns', () {
    test('the transaction list covers exactly the range', () async {
      await spend(100, DateTime(2026, 8, 9, 12));
      await spend(200, DateTime(2026, 8, 10, 12));
      await spend(300, DateTime(2026, 8, 12, 12));
      await spend(400, DateTime(2026, 8, 13, 12));

      final List<Transaction> list = await txs
          .watchRange(DateTime(2026, 8, 10), DateTime(2026, 8, 12))
          .first;
      expect(list.map((Transaction t) => t.amountMinor).toSet(), {200, 300});
    });

    test('category totals are range-scoped', () async {
      await spend(1000, DateTime(2026, 8, 10, 12));
      await spend(2000, DateTime(2026, 8, 11, 12));
      await spend(9999, DateTime(2026, 9, 1, 12));

      final List<CategoryTotal> totals = await summaries
          .watchRangeCategoryTotals(DateTime(2026, 8, 10), DateTime(2026, 8, 11))
          .first;
      expect(totals, hasLength(1));
      expect(totals.first.totalMinor, 3000);
    });
  });

  group('trend bucketing', () {
    test('a short range buckets by day, one bucket per day', () async {
      await spend(500, DateTime(2026, 8, 11, 12));
      final List<PeriodTotals> buckets = await summaries
          .watchRangeBuckets(DateTime(2026, 8, 10), DateTime(2026, 8, 14))
          .first;
      expect(buckets, hasLength(5));
      expect(buckets.first.start, DateTime(2026, 8, 10));
      expect(buckets.last.start, DateTime(2026, 8, 14));
      expect(buckets[1].expenseMinor, 500);
      expect(buckets[0].expenseMinor, 0);
    });

    test('a long range buckets by month instead', () async {
      await spend(700, DateTime(2026, 6, 15, 12));
      await spend(800, DateTime(2026, 8, 2, 12));

      final List<PeriodTotals> buckets = await summaries
          .watchRangeBuckets(DateTime(2026, 6, 1), DateTime(2026, 8, 31))
          .first;
      // Three months, not 92 days.
      expect(buckets, hasLength(3));
      expect(buckets.map((PeriodTotals b) => b.start.month), [6, 7, 8]);
      expect(buckets.first.expenseMinor, 700);
      expect(buckets.last.expenseMinor, 800);
    });

    test('the daily/monthly switch matches what the query did', () {
      expect(
        rangeBucketsAreDaily(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
        isTrue,
      );
      expect(
        rangeBucketsAreDaily(DateTime(2026, 8, 1), DateTime(2026, 9, 1)),
        isFalse,
      );
    });
  });

  group('DateRange', () {
    test('normalizes a backwards span and counts days inclusively', () {
      final DateRange r = DateRange(DateTime(2026, 8, 20), DateTime(2026, 8, 14));
      expect(r.from, DateTime(2026, 8, 14));
      expect(r.to, DateTime(2026, 8, 20));
      expect(r.dayCount, 7);
      expect(DateRange(DateTime(2026, 8, 14), DateTime(2026, 8, 14)).dayCount, 1);
    });

    test('lastDays counts the anchor day itself', () {
      final DateRange r =
          DateRange.lastDays(7, now: DateTime(2026, 8, 20, 15, 30));
      expect(r.from, DateTime(2026, 8, 14));
      expect(r.to, DateTime(2026, 8, 20));
      expect(r.dayCount, 7);
    });

    test('shifting pages by the span length without changing it', () {
      final DateRange week =
          DateRange(DateTime(2026, 8, 14), DateTime(2026, 8, 20));
      final DateRange previous = week.shifted(-1);
      expect(previous.from, DateTime(2026, 8, 7));
      expect(previous.to, DateTime(2026, 8, 13));
      expect(previous.dayCount, week.dayCount);
      // Paging back and forward returns to where it started.
      expect(previous.shifted(1), week);
    });

    test('a range crossing a DST-style month edge still counts whole days', () {
      final DateRange r =
          DateRange(DateTime(2026, 3, 28), DateTime(2026, 4, 2));
      expect(r.dayCount, 6);
      expect(daysInRange(r.from, r.to), 6);
    });
  });

  group('range labels', () {
    test('a single day reads as that day', () {
      expect(
        rangeLabel(DateTime(2026, 8, 19), DateTime(2026, 8, 19), locale: 'en'),
        'Aug 19',
      );
    });

    test('the compact form drops the repeated month', () {
      expect(
        rangeLabel(DateTime(2026, 8, 1), DateTime(2026, 8, 20), locale: 'en'),
        '1 – Aug 20',
      );
    });

    test('the full form always names both ends', () {
      expect(
        rangeLabel(DateTime(2026, 8, 1), DateTime(2026, 8, 20),
            locale: 'en', compact: false),
        'Aug 1 – Aug 20',
      );
    });

    test('a cross-month range names both ends either way', () {
      expect(
        rangeLabel(DateTime(2026, 8, 28), DateTime(2026, 9, 3), locale: 'en'),
        'Aug 28 – Sep 3',
      );
    });
  });

  group('PeriodMode', () {
    test('range round-trips through the persisted name', () {
      expect(PeriodMode.fromName('range'), PeriodMode.range);
      expect(PeriodMode.fromName(PeriodMode.range.name), PeriodMode.range);
    });

    test('an unknown or missing value still falls back to month', () {
      expect(PeriodMode.fromName(null), PeriodMode.month);
      expect(PeriodMode.fromName('week'), PeriodMode.month);
    });
  });
}
