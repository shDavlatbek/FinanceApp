import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../db/database.dart';

/// Transactions repository: watch streams + mutations.
///
/// Every mutation sets `updated_at_ms = now` and `dirty = true`, then invokes
/// [onMutation] (wired to the sync engine's debounced trigger).
class TransactionsRepository {
  TransactionsRepository(
    this._db, {
    this._onMutation,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final void Function()? _onMutation;
  final int Function() _now;
  static const _uuid = Uuid();

  // ---- reads -------------------------------------------------------------

  /// Most recent [limit] non-deleted transactions, newest first.
  Stream<List<Transaction>> watchRecent({int limit = 5}) {
    final q = _db.select(_db.transactions)
      ..where((t) => t.deletedAtMs.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.occurredAt),
        (t) => OrderingTerm.desc(t.createdAtMs),
      ])
      ..limit(limit);
    return q.watch();
  }

  /// All non-deleted transactions in the local month of [month],
  /// newest first.
  Stream<List<Transaction>> watchMonth(DateTime month) =>
      watchFiltered(month: month);

  /// Filtered list for History: optional note substring search
  /// (case-insensitive), category, kind, and month filters. Newest first.
  Stream<List<Transaction>> watchFiltered({
    String? noteQuery,
    String? categoryId,
    String? kind,
    DateTime? month,
  }) {
    final q = _db.select(_db.transactions)
      ..where((t) => t.deletedAtMs.isNull());
    if (month != null) {
      final bounds = monthQueryBounds(month);
      q.where((t) =>
          t.occurredAt.isBiggerOrEqualValue(bounds.start) &
          t.occurredAt.isSmallerThanValue(bounds.end));
    }
    if (categoryId != null) {
      q.where((t) => t.categoryId.equals(categoryId));
    }
    if (kind != null) {
      q.where((t) => t.kind.equals(kind));
    }
    final query = noteQuery?.trim().toLowerCase();
    if (query != null && query.isNotEmpty) {
      q.where((t) => t.note.lower().like('%$query%'));
    }
    q.orderBy([
      (t) => OrderingTerm.desc(t.occurredAt),
      (t) => OrderingTerm.desc(t.createdAtMs),
    ]);
    return q.watch();
  }

  Future<Transaction?> getById(String id) =>
      (_db.select(_db.transactions)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  // ---- mutations ----------------------------------------------------------

  /// Inserts a new transaction and returns the created row.
  /// [occurredAt] defaults to now; stored as RFC3339 UTC.
  Future<Transaction> insert({
    required String kind,
    required int amountMinor,
    required String categoryId,
    String note = '',
    DateTime? occurredAt,
    String source = TxSource.app,
  }) async {
    final nowMs = _now();
    final row = Transaction(
      id: _uuid.v4(),
      kind: kind,
      amountMinor: amountMinor,
      categoryId: categoryId,
      note: note,
      occurredAt: toOccurredAt(occurredAt ?? DateTime.now()),
      source: source,
      createdAtMs: nowMs,
      updatedAtMs: nowMs,
      deletedAtMs: null,
      dirty: true,
    );
    await _db.into(_db.transactions).insert(row);
    _onMutation?.call();
    return row;
  }

  /// Updates the given fields of transaction [id]; unspecified fields are
  /// left unchanged.
  Future<void> update({
    required String id,
    String? kind,
    int? amountMinor,
    String? categoryId,
    String? note,
    DateTime? occurredAt,
  }) async {
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        kind: kind == null ? const Value.absent() : Value(kind),
        amountMinor:
            amountMinor == null ? const Value.absent() : Value(amountMinor),
        categoryId:
            categoryId == null ? const Value.absent() : Value(categoryId),
        note: note == null ? const Value.absent() : Value(note),
        occurredAt: occurredAt == null
            ? const Value.absent()
            : Value(toOccurredAt(occurredAt)),
        updatedAtMs: Value(_now()),
        dirty: const Value(true),
      ),
    );
    _onMutation?.call();
  }

  /// Tombstone soft-delete (sets `deleted_at_ms`; the row is kept forever).
  Future<void> softDelete(String id) async {
    final nowMs = _now();
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAtMs: Value(nowMs),
        updatedAtMs: Value(nowMs),
        dirty: const Value(true),
      ),
    );
    _onMutation?.call();
  }
}
