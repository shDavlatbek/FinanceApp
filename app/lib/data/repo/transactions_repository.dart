import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../db/database.dart';

/// Transactions repository: watch streams + mutations.
///
/// Every mutation sets `updated_at_ms = now` and `dirty = true`, then invokes
/// [onMutation] (wired to the sync engine's debounced trigger).
/// The `sort_order` of a row nobody has dragged. Sorts ahead of every
/// hand-placed row, so a new entry lands at the top of its day.
const int unplacedSortOrder = 0;

/// Orders rows the way every list in the app shows them: newest day first,
/// then manual placement inside the day, then newest time first.
///
/// The within-day part cannot be done in SQL. Days are LOCAL, and SQLite has
/// no idea what this peer's UTC offset is, so grouping has to happen in Dart
/// and the ordering has to happen with it (docs/ARCHITECTURE.md v4).
List<Transaction> sortedForDisplay(List<Transaction> rows) {
  // Decorate with the day key once rather than parsing it inside the
  // comparator, which would re-parse O(n log n) times.
  final List<({String day, Transaction tx})> keyed = <({String day, Transaction tx})>[
    for (final Transaction tx in rows)
      (day: dayKeyFromOccurredAt(tx.occurredAt), tx: tx),
  ];
  keyed.sort((({String day, Transaction tx}) a, ({String day, Transaction tx}) b) {
    if (a.day != b.day) return b.day.compareTo(a.day);
    if (a.tx.sortOrder != b.tx.sortOrder) {
      return a.tx.sortOrder.compareTo(b.tx.sortOrder);
    }
    final int byTime = b.tx.occurredAt.compareTo(a.tx.occurredAt);
    if (byTime != 0) return byTime;
    return b.tx.createdAtMs.compareTo(a.tx.createdAtMs);
  });
  return <Transaction>[for (final k in keyed) k.tx];
}

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
    return q.watch().map(sortedForDisplay);
  }

  /// All non-deleted transactions in the local month of [month],
  /// newest first.
  Stream<List<Transaction>> watchMonth(DateTime month) =>
      watchFiltered(month: month);

  /// All non-deleted transactions on the local calendar day of [day],
  /// newest first — the day lens's counterpart to [watchMonth].
  Stream<List<Transaction>> watchDay(DateTime day) => watchFiltered(day: day);

  /// Every transaction in the inclusive local day range [from]..[to], newest
  /// first — the range lens's counterpart to [watchMonth].
  Stream<List<Transaction>> watchRange(DateTime from, DateTime to) {
    final r = normalizeRange(from, to);
    return watchFiltered(rangeFrom: r.from, rangeTo: r.to);
  }

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
    DateTime? rangeFrom,
    DateTime? rangeTo,
  }) {
    final q = _db.select(_db.transactions)
      ..where((t) => t.deletedAtMs.isNull());
    if (rangeFrom != null && rangeTo != null) {
      final bounds = rangeQueryBounds(rangeFrom, rangeTo);
      q.where((t) =>
          t.occurredAt.isBiggerOrEqualValue(bounds.start) &
          t.occurredAt.isSmallerThanValue(bounds.end));
    } else if (day != null) {
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
    return q.watch().map(sortedForDisplay);
  }

  /// Places [orderedIds] in exactly that order, numbering them `1..N`.
  ///
  /// Call it with every id of ONE local day: numbering is per-day, so mixing
  /// days would interleave them. Each row's `updated_at_ms` is bumped so the
  /// placement travels to the other peer under last-write-wins.
  Future<void> reorderDay(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    final int nowMs = _now();
    await _db.transaction(() async {
      for (int i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.transactions)
              ..where((t) => t.id.equals(orderedIds[i])))
            .write(TransactionsCompanion(
          sortOrder: Value(i + 1),
          updatedAtMs: Value(nowMs),
          dirty: const Value(true),
        ));
      }
    });
    _onMutation?.call();
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
      sortOrder: unplacedSortOrder,
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
      sortOrder: unplacedSortOrder,
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

  /// Lifts the tombstone off transaction [id] — the undo behind every
  /// swipe-to-delete.
  ///
  /// Clears the tombstone on the SAME row rather than inserting a copy.
  /// Re-inserting would mint a new id and rebuild the row from whichever
  /// fields the caller remembered to pass, which silently dropped
  /// `account_id`, `to_account_id` and `sort_order` — an undone transfer came
  /// back as a destination-less transfer, i.e. a row the peers' sanitizer
  /// throws away.
  Future<void> restore(String id) async {
    final nowMs = _now();
    await (_db.update(_db.transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deletedAtMs: const Value(null),
        updatedAtMs: Value(nowMs),
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
