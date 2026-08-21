import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';

/// An account paired with its current balance, in minor units.
class AccountBalance {
  const AccountBalance({required this.account, required this.balanceMinor});

  final Account account;
  final int balanceMinor;
}

/// Accounts repository: watch streams + mutations.
///
/// Balances are DERIVED, never stored. There is no running-total column to
/// drift out of step with the rows, and an edit to any transaction is
/// reflected the moment the query re-runs.
class AccountsRepository {
  AccountsRepository(
    this._db, {
    this._onMutation,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final void Function()? _onMutation;
  final int Function() _now;
  static const _uuid = Uuid();

  // ---- reads --------------------------------------------------------------

  /// Non-deleted accounts, ordered by sort order then name.
  Stream<List<Account>> watchActive() {
    final q = _db.select(_db.accounts)
      ..where((a) => a.deletedAtMs.isNull())
      ..orderBy([
        (a) => OrderingTerm.asc(a.sortOrder),
        (a) => OrderingTerm.asc(a.name),
      ]);
    return q.watch();
  }

  /// ALL accounts, archived included — id lookups must keep resolving accounts
  /// that historical transactions still reference. Archiving a wallet must
  /// never blank out the entries booked to it.
  Stream<List<Account>> watchAll() {
    final q = _db.select(_db.accounts)
      ..orderBy([
        (a) => OrderingTerm.asc(a.sortOrder),
        (a) => OrderingTerm.asc(a.name),
      ]);
    return q.watch();
  }

  Future<Account?> getById(String id) =>
      (_db.select(_db.accounts)..where((a) => a.id.equals(id)))
          .getSingleOrNull();

  /// Every non-deleted account with its balance:
  ///
  ///     opening + income booked to it - expenses booked to it
  ///             + transfers into it   - transfers out of it
  ///
  /// over non-deleted transactions only. This is the same rule the Go peer
  /// implements in `store.AccountBalances`; the two must not drift apart.
  ///
  /// The four arms are SUMMED, not a first-match CASE. With a single CASE a
  /// self-transfer (account_id == to_account_id, which only a hand-edited peer
  /// file can produce) would match the credit arm, never reach the debit arm
  /// and INVENT money out of nothing. Added independently it nets to zero, so
  /// the balance stays right even for a row the sanitizer should have caught.
  Stream<List<AccountBalance>> watchBalances() {
    final q = _db.customSelect(
      'SELECT a.id AS id, '
      '       a.opening_balance_minor + COALESCE(( '
      '         SELECT SUM( '
      "             CASE WHEN t.kind = 'income'   AND t.account_id    = a.id THEN  t.amount_minor ELSE 0 END "
      "           + CASE WHEN t.kind = 'expense'  AND t.account_id    = a.id THEN -t.amount_minor ELSE 0 END "
      "           + CASE WHEN t.kind = 'transfer' AND t.to_account_id = a.id THEN  t.amount_minor ELSE 0 END "
      "           + CASE WHEN t.kind = 'transfer' AND t.account_id    = a.id THEN -t.amount_minor ELSE 0 END) "
      '         FROM transactions t '
      '         WHERE t.deleted_at_ms IS NULL '
      '           AND (t.account_id = a.id OR t.to_account_id = a.id) '
      '       ), 0) AS balance '
      'FROM accounts a '
      'WHERE a.deleted_at_ms IS NULL '
      'ORDER BY a.sort_order, a.name',
      readsFrom: {_db.accounts, _db.transactions},
    );
    return q.watch().asyncMap((rows) async {
      if (rows.isEmpty) return const <AccountBalance>[];
      final balances = <String, int>{
        for (final row in rows) row.read<String>('id'): row.read<int>('balance'),
      };
      final accounts = await (_db.select(_db.accounts)
            ..where((a) => a.id.isIn(balances.keys))
            ..orderBy([
              (a) => OrderingTerm.asc(a.sortOrder),
              (a) => OrderingTerm.asc(a.name),
            ]))
          .get();
      return [
        for (final a in accounts)
          AccountBalance(account: a, balanceMinor: balances[a.id] ?? 0),
      ];
    });
  }

  // ---- mutations ----------------------------------------------------------

  /// Creates an account and returns the created row.
  Future<Account> insert({
    required String name,
    required String kind,
    required String emoji,
    required String color,
    int openingBalanceMinor = 0,
    int? sortOrder,
  }) async {
    final nowMs = _now();
    final int order = sortOrder ??
        ((await (_db.selectOnly(_db.accounts)
                      ..addColumns([_db.accounts.sortOrder.max()])
                      ..where(_db.accounts.deletedAtMs.isNull()))
                    .map((r) => r.read(_db.accounts.sortOrder.max()))
                    .getSingleOrNull() ??
                -1) +
            1);
    final row = Account(
      id: _uuid.v4(),
      name: name,
      kind: kind,
      emoji: emoji,
      color: color,
      openingBalanceMinor: openingBalanceMinor,
      sortOrder: order,
      updatedAtMs: nowMs,
      deletedAtMs: null,
      dirty: true,
    );
    await _db.into(_db.accounts).insert(row);
    _onMutation?.call();
    return row;
  }

  /// Updates the given fields of account [id]; unspecified fields are left
  /// unchanged.
  Future<void> update({
    required String id,
    String? name,
    String? kind,
    String? emoji,
    String? color,
    int? openingBalanceMinor,
    int? sortOrder,
  }) async {
    await (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        name: name == null ? const Value.absent() : Value(name),
        kind: kind == null ? const Value.absent() : Value(kind),
        emoji: emoji == null ? const Value.absent() : Value(emoji),
        color: color == null ? const Value.absent() : Value(color),
        openingBalanceMinor: openingBalanceMinor == null
            ? const Value.absent()
            : Value(openingBalanceMinor),
        sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
        updatedAtMs: Value(_now()),
        dirty: const Value(true),
      ),
    );
    _onMutation?.call();
  }

  /// Tombstone soft-delete. Transactions booked to the account keep pointing
  /// at it: history must not lose entries because a wallet was closed.
  Future<void> archive(String id) async {
    final nowMs = _now();
    await (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        deletedAtMs: Value(nowMs),
        updatedAtMs: Value(nowMs),
        dirty: const Value(true),
      ),
    );
    _onMutation?.call();
  }

  /// Rewrites `sort_order` to each id's index in [orderedIds] (a full
  /// ordering of the live accounts). Every touched row is bumped and marked
  /// dirty so the order travels to the other peer under last-write-wins.
  Future<void> reorder(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    final int nowMs = _now();
    await _db.transaction(() async {
      for (int i = 0; i < orderedIds.length; i++) {
        await (_db.update(_db.accounts)
              ..where((a) => a.id.equals(orderedIds[i])))
            .write(AccountsCompanion(
          sortOrder: Value(i),
          updatedAtMs: Value(nowMs),
          dirty: const Value(true),
        ));
      }
    });
    _onMutation?.call();
  }

  /// Lifts the tombstone off an archived account.
  ///
  /// Archiving is the only destructive action on this screen and it is one
  /// tap, so it has to be reversible. Clearing the tombstone on the SAME row
  /// (rather than inserting a fresh account) keeps the id, so every
  /// transaction booked to it stays attached.
  Future<void> unarchive(String id) async {
    final int nowMs = _now();
    await (_db.update(_db.accounts)..where((a) => a.id.equals(id))).write(
      AccountsCompanion(
        deletedAtMs: const Value(null),
        updatedAtMs: Value(nowMs),
        dirty: const Value(true),
      ),
    );
    _onMutation?.call();
  }

  /// Resolves the account new entries should book to: the synced
  /// `settings.default_account_id` when it still names a live account,
  /// otherwise the first live account. Never returns an archived account, so
  /// archiving the default cannot leave writes going into a hole.
  Future<Account?> resolveDefault(String? configuredId) async {
    if (configuredId != null && configuredId.isNotEmpty) {
      final Account? a = await getById(configuredId);
      if (a != null && a.deletedAtMs == null) return a;
    }
    final live = await (_db.select(_db.accounts)
          ..where((a) => a.deletedAtMs.isNull())
          ..orderBy([
            (a) => OrderingTerm.asc(a.sortOrder),
            (a) => OrderingTerm.asc(a.name),
          ])
          ..limit(1))
        .getSingleOrNull();
    return live;
  }
}
