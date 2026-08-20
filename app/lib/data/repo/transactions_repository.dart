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

  /// All non-deleted transactions on the local calendar day of [day],
  /// newest first — the day lens's counterpart to [watchMonth].
  Stream<List<Transaction>> watchDay(DateTime day) => watchFiltered(day: day);

  /// Filtered list for History: optional note substring search
  /// (case-insensitive), category, kind, and month filters. Newest first.
  /// Passing both [month] and [day] is a caller error: [day] wins, because a
  /// day is the narrower lens.
  Stream<List<Transaction>> watchFiltered({
    String? noteQuery,
    String? categoryId,
    String? kind,
    DateTime? month,
    DateTime? day,
  }) {
    final q = _db.select(_db.transactions)
      ..where((t) => t.deletedAtMs.isNull());
    if (day != null) {
      final bounds = dayQueryBounds(day);
      q.where((t) =>
          t.occurredAt.isBiggerOrEqualValue(bounds.start) &
          t.occurredAt.isSmallerThanValue(bounds.end));
    } else if (month != null) {
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
    String accountId = defaultAccountId,
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
      accountId: accountId,
      toAccountId: '',
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

  /// Records a transfer: money moved between two of the owner's OWN accounts.
  ///
  /// One row, never a matched expense/income pair — a pair could half-arrive,
  /// be edited out of balance, or be half-deleted under last-write-wins.
  /// [categoryId] is deliberately empty: moving your own money is not
  /// spending, so it has no category and lands in no total.
  ///
  /// Throws [ArgumentError] when the two accounts are the same (a no-op that
  /// would still show up in history as money moving) or the amount is not
  /// positive — the sign is implied by the direction, never by the amount.
  Future<Transaction> insertTransfer({
    required int amountMinor,
    required String fromAccountId,
    required String toAccountId,
    String note = '',
    DateTime? occurredAt,
    String source = TxSource.app,
  }) async {
    if (fromAccountId == toAccountId) {
      throw ArgumentError.value(
          toAccountId, 'toAccountId', 'cannot transfer to the same account');
    }
    if (amountMinor <= 0) {
      throw ArgumentError.value(
          amountMinor, 'amountMinor', 'must be greater than zero');
    }
    final nowMs = _now();
    final row = Transaction(
      id: _uuid.v4(),
      kind: Kind.transfer,
      amountMinor: amountMinor,
      categoryId: '',
      accountId: fromAccountId,
      toAccountId: toAccountId,
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
    String? accountId,
    String? toAccountId,
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
        accountId: accountId == null ? const Value.absent() : Value(accountId),
        toAccountId:
            toAccountId == null ? const Value.absent() : Value(toAccountId),
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
