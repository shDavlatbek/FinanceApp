import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../db/database.dart';

/// Income/expense totals for one period (a local day or a local month).
/// Amounts in minor units.
///
/// Transfers contribute to NOTHING here. Moving money between two of the
/// owner's own accounts is neither income nor spending, so a transfer must
/// leave every figure on this class exactly where it was — otherwise putting
/// money aside would read as losing it.
class PeriodTotals {
  const PeriodTotals({
    required this.start,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  /// First instant of the period these totals cover (a day or a month start).
  final DateTime start;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;

  static PeriodTotals empty(DateTime start) =>
      PeriodTotals(start: start, incomeMinor: 0, expenseMinor: 0);
}

/// A category with its total for some period. Amount in minor units.
class CategoryTotal {
  const CategoryTotal({required this.category, required this.totalMinor});

  final Category category;
  final int totalMinor;
}

/// Read-only aggregate queries used by Home and Stats.
class SummariesRepository {
  SummariesRepository(this._db);

  final AppDatabase _db;

  /// Income / expense / net totals between the two `occurred_at` bounds.
  ///
  /// The `kind IN ('income','expense')` filter is the load-bearing bit: it
  /// keeps transfers out. Reading a `kind` that is neither and bucketing it as
  /// expense — the obvious else-branch — would make every "send to savings"
  /// look like a purchase.
  Stream<PeriodTotals> _watchTotalsBetween(
    DateTime start,
    ({String start, String end}) bounds,
  ) {
    final q = _db.customSelect(
      'SELECT kind, COALESCE(SUM(amount_minor), 0) AS total '
      'FROM transactions '
      'WHERE deleted_at_ms IS NULL AND kind IN (?, ?) '
      'AND occurred_at >= ? AND occurred_at < ? '
      'GROUP BY kind',
      variables: [
        Variable.withString(Kind.income),
        Variable.withString(Kind.expense),
        Variable.withString(bounds.start),
        Variable.withString(bounds.end),
      ],
      readsFrom: {_db.transactions},
    );
    return q.watch().map((rows) {
      var income = 0;
      var expense = 0;
      for (final row in rows) {
        final total = row.read<int>('total');
        switch (row.read<String>('kind')) {
          case Kind.income:
            income = total;
          case Kind.expense:
            expense = total;
        }
      }
      return PeriodTotals(
        start: start,
        incomeMinor: income,
        expenseMinor: expense,
      );
    });
  }

  /// Income / expense / net totals for the local month of [month].
  Stream<PeriodTotals> watchMonthTotals(DateTime month) =>
      _watchTotalsBetween(monthStart(month), monthQueryBounds(month));

  /// Income / expense / net totals for the local calendar day of [day].
  Stream<PeriodTotals> watchDayTotals(DateTime day) =>
      _watchTotalsBetween(dayStart(day), dayQueryBounds(day));

  /// Per-category totals of [kind] between the given bounds, largest first.
  /// Only categories with at least one transaction appear.
  ///
  /// [kind] is always 'income' or 'expense', so transfers — which carry no
  /// category at all — can never appear in a breakdown.
  Stream<List<CategoryTotal>> _watchCategoryTotalsBetween(
    ({String start, String end}) bounds, {
    required String kind,
  }) {
    final q = _db.customSelect(
      'SELECT category_id, COALESCE(SUM(amount_minor), 0) AS total '
      'FROM transactions '
      'WHERE deleted_at_ms IS NULL AND kind = ? '
      'AND occurred_at >= ? AND occurred_at < ? '
      'GROUP BY category_id',
      variables: [
        Variable.withString(kind),
        Variable.withString(bounds.start),
        Variable.withString(bounds.end),
      ],
      readsFrom: {_db.transactions, _db.categories},
    );
    return q.watch().asyncMap((rows) async {
      final totals = <String, int>{
        for (final row in rows)
          row.read<String>('category_id'): row.read<int>('total'),
      };
      if (totals.isEmpty) return const <CategoryTotal>[];
      final cats = await (_db.select(_db.categories)
            ..where((c) => c.id.isIn(totals.keys)))
          .get();
      final result = [
        for (final c in cats)
          CategoryTotal(category: c, totalMinor: totals[c.id] ?? 0),
      ]..sort((a, b) => b.totalMinor.compareTo(a.totalMinor));
      return result;
    });
  }

  /// Per-category totals of [kind] for the local month of [month].
  Stream<List<CategoryTotal>> watchCategoryTotals(
    DateTime month, {
    String kind = Kind.expense,
  }) =>
      _watchCategoryTotalsBetween(monthQueryBounds(month), kind: kind);

  /// Per-category totals of [kind] for the local calendar day of [day].
  Stream<List<CategoryTotal>> watchDayCategoryTotals(
    DateTime day, {
    String kind = Kind.expense,
  }) =>
      _watchCategoryTotalsBetween(dayQueryBounds(day), kind: kind);

  /// Totals for the last 6 local months ending at [anchorMonth]
  /// (oldest first, always 6 entries, zero-filled).
  Stream<List<PeriodTotals>> watchLastSixMonths(DateTime anchorMonth) {
    final months = [
      for (var i = 5; i >= 0; i--) addMonths(monthStart(anchorMonth), -i),
    ];
    final start = occurredAtQueryBound(months.first);
    final end = occurredAtQueryBound(nextMonthStart(anchorMonth));
    final q = _db.customSelect(
      'SELECT occurred_at, kind, amount_minor FROM transactions '
      'WHERE deleted_at_ms IS NULL AND kind IN (?, ?) '
      'AND occurred_at >= ? AND occurred_at < ?',
      variables: [
        Variable.withString(Kind.income),
        Variable.withString(Kind.expense),
        Variable.withString(start),
        Variable.withString(end),
      ],
      readsFrom: {_db.transactions},
    );
    return q.watch().map((rows) {
      final income = <String, int>{};
      final expense = <String, int>{};
      for (final row in rows) {
        final key = monthKey(occurredAtToLocal(row.read<String>('occurred_at')));
        final amount = row.read<int>('amount_minor');
        if (row.read<String>('kind') == Kind.income) {
          income[key] = (income[key] ?? 0) + amount;
        } else {
          expense[key] = (expense[key] ?? 0) + amount;
        }
      }
      return [
        for (final m in months)
          PeriodTotals(
            start: m,
            incomeMinor: income[monthKey(m)] ?? 0,
            expenseMinor: expense[monthKey(m)] ?? 0,
          ),
      ];
    });
  }

  /// Totals for the last [days] local days ending at [anchorDay]
  /// (oldest first, always [days] entries, zero-filled) — the day lens's
  /// trend, matching [watchLastSixMonths].
  Stream<List<PeriodTotals>> watchLastDays(DateTime anchorDay,
      {int days = 14}) {
    final list = [
      for (var i = days - 1; i >= 0; i--) addDays(dayStart(anchorDay), -i),
    ];
    final start = occurredAtQueryBound(list.first);
    final end = occurredAtQueryBound(nextDayStart(anchorDay));
    final q = _db.customSelect(
      'SELECT occurred_at, kind, amount_minor FROM transactions '
      'WHERE deleted_at_ms IS NULL AND kind IN (?, ?) '
      'AND occurred_at >= ? AND occurred_at < ?',
      variables: [
        Variable.withString(Kind.income),
        Variable.withString(Kind.expense),
        Variable.withString(start),
        Variable.withString(end),
      ],
      readsFrom: {_db.transactions},
    );
    return q.watch().map((rows) {
      final income = <String, int>{};
      final expense = <String, int>{};
      for (final row in rows) {
        final key = dayKey(occurredAtToLocal(row.read<String>('occurred_at')));
        final amount = row.read<int>('amount_minor');
        if (row.read<String>('kind') == Kind.income) {
          income[key] = (income[key] ?? 0) + amount;
        } else {
          expense[key] = (expense[key] ?? 0) + amount;
        }
      }
      return [
        for (final d in list)
          PeriodTotals(
            start: d,
            incomeMinor: income[dayKey(d)] ?? 0,
            expenseMinor: expense[dayKey(d)] ?? 0,
          ),
      ];
    });
  }
}
