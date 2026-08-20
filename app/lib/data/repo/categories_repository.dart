import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

/// Categories repository: watch streams + mutations.
///
/// Every mutation sets `updated_at_ms = now` and `dirty = true`, then invokes
/// [onMutation].
class CategoriesRepository {
  CategoriesRepository(
    this._db, {
    this._onMutation,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final void Function()? _onMutation;
  final int Function() _now;
  static const _uuid = Uuid();

  // ---- reads -------------------------------------------------------------

  /// Non-archived categories ordered by `sort_order`, optionally filtered
  /// by [kind] ('income' | 'expense').
  Stream<List<Category>> watchActive({String? kind}) {
    final q = _db.select(_db.categories)
      ..where((c) => c.deletedAtMs.isNull())
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.name),
      ]);
    if (kind != null) {
      q.where((c) => c.kind.equals(kind));
    }
    return q.watch();
  }

  /// ALL categories, archived (tombstoned) ones included, ordered by
  /// `sort_order`. Archived categories must keep labeling the transactions
  /// that reference them; use [watchActive] for pickers instead.
  Stream<List<Category>> watchAll() {
    final q = _db.select(_db.categories)
      ..orderBy([
        (c) => OrderingTerm.asc(c.sortOrder),
        (c) => OrderingTerm.asc(c.name),
      ]);
    return q.watch();
  }

  /// One-shot variant of [watchActive].
  Future<List<Category>> activeByKind(String kind) {
    final q = _db.select(_db.categories)
      ..where((c) => c.deletedAtMs.isNull() & c.kind.equals(kind))
      ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]);
    return q.get();
  }

  Future<Category?> getById(String id) =>
      (_db.select(_db.categories)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  // ---- mutations ----------------------------------------------------------

  /// Creates (when [id] is null) or updates a category. New categories get
  /// `sort_order = max(sort_order of kind) + 1` unless [sortOrder] is given.
  /// Returns the written row.
  Future<Category> upsert({
    String? id,
    required String name,
    required String emoji,
    required String color,
    required String kind,
    int? sortOrder,
  }) async {
    final nowMs = _now();
    final existing = id == null ? null : await getById(id);
    final order = sortOrder ??
        existing?.sortOrder ??
        await _nextSortOrder(kind);
    final row = Category(
      id: id ?? _uuid.v4(),
      name: name,
      emoji: emoji,
      color: color,
      kind: kind,
      sortOrder: order,
      updatedAtMs: nowMs,
      deletedAtMs: existing?.deletedAtMs,
      dirty: true,
    );
    await _db.into(_db.categories).insertOnConflictUpdate(row);
    _onMutation?.call();
    return row;
  }

  /// Tombstone soft-delete (archives the category; transactions keep
  /// referencing it).
  Future<void> archive(String id) async {
    final nowMs = _now();
    await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        deletedAtMs: Value(nowMs),
        updatedAtMs: Value(nowMs),
        dirty: const Value(true),
      ),
    );
    _onMutation?.call();
  }

  /// Rewrites `sort_order` to the index of each id in [orderedIds]
  /// (a full ordering of the active categories of [kind]).
  Future<void> reorder({
    required String kind,
    required List<String> orderedIds,
  }) async {
    final nowMs = _now();
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.categories)
              ..where((c) => c.id.equals(orderedIds[i]) & c.kind.equals(kind)))
            .write(CategoriesCompanion(
          sortOrder: Value(i),
          updatedAtMs: Value(nowMs),
          dirty: const Value(true),
        ));
      }
    });
    _onMutation?.call();
  }

  Future<int> _nextSortOrder(String kind) async {
    final maxOrder = _db.categories.sortOrder.max();
    final q = _db.selectOnly(_db.categories)
      ..addColumns([maxOrder])
      ..where(_db.categories.kind.equals(kind));
    final row = await q.getSingleOrNull();
    final current = row?.read(maxOrder);
    return current == null ? 0 : current + 1;
  }
}
