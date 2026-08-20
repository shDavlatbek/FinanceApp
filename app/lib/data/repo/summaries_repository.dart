import 'package:drift/drift.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../db/database.dart';

/// Income/expense totals for one local month. Amounts in minor units.
class MonthTotals {
  const MonthTotals({
    required this.month,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  /// First day of the local month these totals cover.
  final DateTime month;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;

  static MonthTotals empty(DateTime month) =>
      MonthTotals(month: monthStart(month), incomeMinor: 0, expenseMinor: 0);
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

  /// Income / expense / net totals for the local month of [month].
  Stream<MonthTotals> watchMonthTotals(DateTime month) {
    final bounds = monthQueryBounds(month);
    final q = _db.customSelect(
      'SELECT kind, COALESCE(SUM(amount_minor), 0) AS total '
      'FROM transactions '
      'WHERE deleted_at_ms IS NULL AND occurred_at >= ? AND occurred_at < ? '
      'GROUP BY kind',
      variables: [
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
        if (row.read<String>('kind') == Kind.income) {
          income = total;
        } else {
          expense = total;
        }
      }
      return MonthTotals(
        month: monthStart(month),
        incomeMinor: income,
        expenseMinor: expense,
      );
    });
  }

  /// Per-category totals of [kind] for the local month of [month],
  /// largest first. Only categories with at least one transaction appear.
  Stream<List<CategoryTotal>> watchCategoryTotals(
    DateTime month, {
    String kind = Kind.expense,
  }) {
    final bounds = monthQueryBounds(month);
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

  /// Totals for the last 6 local months ending at [anchorMonth]
  /// (oldest first, always 6 entries, zero-filled).
  Stream<List<MonthTotals>> watchLastSixMonths(DateTime anchorMonth) {
    final months = [
      for (var i = 5; i >= 0; i--) addMonths(monthStart(anchorMonth), -i),
    ];
    final start = occurredAtQueryBound(months.first);
    final end = occurredAtQueryBound(nextMonthStart(anchorMonth));
    final q = _db.customSelect(
      'SELECT occurred_at, kind, amount_minor FROM transactions '
      'WHERE deleted_at_ms IS NULL AND occurred_at >= ? AND occurred_at < ?',
      variables: [Variable.withString(start), Variable.withString(end)],
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
          MonthTotals(
            month: m,
            incomeMinor: income[monthKey(m)] ?? 0,
            expenseMinor: expense[monthKey(m)] ?? 0,
          ),
      ];
    });
  }
}
