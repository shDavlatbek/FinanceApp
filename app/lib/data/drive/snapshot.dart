/// The Drive snapshot envelope (docs/ARCHITECTURE.md § Drive layout).
///
/// One file per peer, `tally-<device_id>.json`, uncompressed so the owner can
/// read their own data in the Drive UI. The payload is a **full dump** of that
/// peer's local state, tombstones included — which is what makes the merge
/// idempotent and self-healing.
///
/// ```json
/// {
///   "schema": 2,
///   "device_id": "b2c3…",
///   "device_name": "Pixel 7",
///   "written_at_ms": 1787160000000,
///   "accounts":     [ Account… ],
///   "categories":   [ Category… ],
///   "transactions": [ Transaction… ],
///   "settings":     Settings
/// }
/// ```
///
/// Schema 2 added `accounts`. This build WRITES 2 and READS 1 and 2: a peer
/// that has not been updated yet keeps publishing 1, and refusing to read it
/// would strand that device. A schema-1 file carries no accounts and no
/// `account_id`, so its rows are booked to the seed cash account — exactly
/// where the local v3 migration puts this peer's own pre-accounts rows.
///
/// The local-only `dirty` flag is never serialized; decoded rows always carry
/// `dirty = false`.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants.dart';
import '../db/database.dart';
import '../repo/transactions_repository.dart' show unplacedSortOrder;

// ---- row <-> JSON (field names are the binding contract) -------------------

Map<String, Object?> transactionToJson(Transaction t) => <String, Object?>{
      'id': t.id,
      'kind': t.kind,
      'amount_minor': t.amountMinor,
      'category_id': t.categoryId,
      'account_id': t.accountId,
      'to_account_id': t.toAccountId,
      'note': t.note,
      'occurred_at': t.occurredAt,
      'sort_order': t.sortOrder,
      'source': t.source,
      'created_at_ms': t.createdAtMs,
      'updated_at_ms': t.updatedAtMs,
      'deleted_at_ms': t.deletedAtMs,
    };

Transaction transactionFromJson(Map<String, Object?> j) {
  final String kind = j['kind']! as String;
  // A schema-1 peer, or a hand-edit that dropped the field, leaves the entry
  // account-less. Booking it to the default account matches what the local
  // migration did to this peer's own pre-accounts rows, so both sides agree
  // without a round trip. Losing an entry would be worse than misfiling one.
  final String accountId = switch (j['account_id']) {
    final String a when a.isNotEmpty => a,
    _ => defaultAccountId,
  };
  // Only a transfer has a destination; carrying one anywhere else would
  // quietly double-count in every balance.
  final String toAccountId = kind == Kind.transfer
      ? ((j['to_account_id'] as String?) ?? '')
      : '';
  return Transaction(
      id: j['id']! as String,
      kind: kind,
      amountMinor: (j['amount_minor']! as num).toInt(),
      categoryId: j['category_id']! as String,
      accountId: accountId,
      toAccountId: toAccountId,
      note: (j['note'] as String?) ?? '',
      occurredAt: j['occurred_at']! as String,
      // Absent on a schema-2 peer, and a hand-edited negative would sort ahead
      // of the unplaced rows and invert a day — both mean "never placed".
      sortOrder: () {
        final int v = (j['sort_order'] as num?)?.toInt() ?? unplacedSortOrder;
        return v < 0 ? unplacedSortOrder : v;
      }(),
      source: (j['source'] as String?) ?? TxSource.app,
      createdAtMs: (j['created_at_ms'] as num?)?.toInt() ??
          (j['updated_at_ms']! as num).toInt(),
      updatedAtMs: (j['updated_at_ms']! as num).toInt(),
      deletedAtMs: (j['deleted_at_ms'] as num?)?.toInt(),
      dirty: false,
  );
}

Map<String, Object?> accountToJson(Account a) => <String, Object?>{
      'id': a.id,
      'name': a.name,
      'kind': a.kind,
      'emoji': a.emoji,
      'color': a.color,
      'opening_balance_minor': a.openingBalanceMinor,
      'sort_order': a.sortOrder,
      'updated_at_ms': a.updatedAtMs,
      'deleted_at_ms': a.deletedAtMs,
    };

Account accountFromJson(Map<String, Object?> j) => Account(
      id: j['id']! as String,
      name: j['name']! as String,
      kind: (j['kind'] as String?) ?? AccountKind.cash,
      emoji: (j['emoji'] as String?) ?? '',
      color: (j['color'] as String?) ?? '#8E8E93',
      // Signed: a card carrying debt is legitimately negative.
      openingBalanceMinor:
          (j['opening_balance_minor'] as num?)?.toInt() ?? 0,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      updatedAtMs: (j['updated_at_ms']! as num).toInt(),
      deletedAtMs: (j['deleted_at_ms'] as num?)?.toInt(),
      dirty: false,
    );

Map<String, Object?> categoryToJson(Category c) => <String, Object?>{
      'id': c.id,
      'name': c.name,
      'emoji': c.emoji,
      'color': c.color,
      'kind': c.kind,
      'sort_order': c.sortOrder,
      'updated_at_ms': c.updatedAtMs,
      'deleted_at_ms': c.deletedAtMs,
    };

Category categoryFromJson(Map<String, Object?> j) => Category(
      id: j['id']! as String,
      name: j['name']! as String,
      emoji: (j['emoji'] as String?) ?? '',
      color: (j['color'] as String?) ?? '#8E8E93',
      kind: j['kind']! as String,
      sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      updatedAtMs: (j['updated_at_ms']! as num).toInt(),
      deletedAtMs: (j['deleted_at_ms'] as num?)?.toInt(),
      dirty: false,
    );

Map<String, Object?> settingsToJson(SettingsRow s) => <String, Object?>{
      'id': s.id,
      'currency': s.currency,
      'language': s.language,
      'default_account_id': s.defaultAccountId,
      'updated_at_ms': s.updatedAtMs,
    };

/// Decodes a peer settings row.
///
/// `default_account_id` decodes to `''` when the peer predates accounts. That
/// EMPTY IS LOAD-BEARING and means "unchanged": the merge keeps whatever this
/// peer already had. Substituting the seed account here would make the old
/// peer look like it had actively chosen cash, and under last-write-wins a
/// stale snapshot from the un-upgraded device would then silently overwrite an
/// account the owner had picked in the app.
SettingsRow settingsFromJson(Map<String, Object?> j) => SettingsRow(
      id: (j['id'] as String?) ?? settingsRowId,
      currency: (j['currency'] as String?) ?? defaultCurrency,
      language: (j['language'] as String?) ?? defaultLanguage,
      defaultAccountId: (j['default_account_id'] as String?) ?? '',
      updatedAtMs: (j['updated_at_ms']! as num).toInt(),
      dirty: false,
    );

// ---- envelope --------------------------------------------------------------

/// Thrown when a snapshot file cannot be parsed (corrupt, truncated, or from
/// an incompatible future schema). The sync engine skips that peer instead of
/// failing the whole pass.
class SnapshotFormatException implements Exception {
  const SnapshotFormatException(this.message);

  final String message;

  @override
  String toString() => 'SnapshotFormatException: $message';
}

/// One peer's full published state.
class TallySnapshot {
  const TallySnapshot({
    required this.deviceId,
    required this.deviceName,
    required this.writtenAtMs,
    required this.categories,
    required this.transactions,
    required this.settings,
    this.accounts = const <Account>[],
    this.schema = snapshotSchemaVersion,
    this.skipped = const <String>[],
  });

  final int schema;

  /// Rows dropped by the sanitizer, with a reason each. A peer file is
  /// hand-editable, so one bad row must NOT cost the whole snapshot: the sync
  /// engine logs these and merges everything else, exactly as the Go peer
  /// does. Never serialized.
  final List<String> skipped;
  final String deviceId;
  final String deviceName;
  final int writtenAtMs;
  final List<Account> accounts;
  final List<Category> categories;
  final List<Transaction> transactions;
  final SettingsRow? settings;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': schema,
        'device_id': deviceId,
        'device_name': deviceName,
        'written_at_ms': writtenAtMs,
        'accounts': <Object?>[
          for (final Account a in accounts) accountToJson(a),
        ],
        'categories': <Object?>[
          for (final Category c in categories) categoryToJson(c),
        ],
        'transactions': <Object?>[
          for (final Transaction t in transactions) transactionToJson(t),
        ],
        'settings': settings == null ? null : settingsToJson(settings!),
      };

  /// Parses and SANITIZES a peer snapshot.
  ///
  /// Envelope problems (not JSON, no schema, an unreadable schema) throw,
  /// because there is nothing to salvage. Individual bad ROWS do not: they are
  /// dropped, the reason is recorded in [skipped], and everything else merges.
  ///
  /// That asymmetry is the contract's ("Peer snapshot files are untrusted
  /// input — sanitize, don't assume"). The owner can hand-edit these files in
  /// the Drive UI, and one stray comma must not silently cost them every other
  /// row in the file. The Go peer applies exactly these rules in
  /// `Snapshot.Batch`; the two must not drift apart.
  factory TallySnapshot.fromJson(Map<String, Object?> json) {
    final Object? schema = json['schema'];
    if (schema is! num) {
      throw const SnapshotFormatException('missing "schema"');
    }
    if (schema.toInt() > snapshotSchemaVersion ||
        schema.toInt() < minReadableSnapshotSchema) {
      throw SnapshotFormatException(
          'snapshot schema ${schema.toInt()} is outside the readable range '
          '$minReadableSnapshotSchema..$snapshotSchemaVersion');
    }

    final List<String> skipped = <String>[];
    List<Map<String, Object?>> rows(String key) => <Map<String, Object?>>[
          for (final Object? r
              in (json[key] as List<Object?>?) ?? const <Object?>[])
            if (r is Map<String, Object?>) r,
        ];

    // Accounts a transaction may legally point at. A schema-1 peer sends none,
    // so the default account — seeded identically on every peer — stands in.
    final Set<String> known = <String>{defaultAccountId};

    final List<Account> accounts = <Account>[];
    for (final Map<String, Object?> raw in rows('accounts')) {
      final String id = (raw['id'] as String?) ?? '';
      try {
        final Account a = accountFromJson(raw);
        final String? bad = _rejectAccount(a);
        if (bad != null) {
          skipped.add('account $id: $bad');
          continue;
        }
        known.add(a.id);
        accounts.add(a);
      } catch (e) {
        skipped.add('account $id: $e');
      }
    }

    final List<Category> categories = <Category>[];
    for (final Map<String, Object?> raw in rows('categories')) {
      final String id = (raw['id'] as String?) ?? '';
      try {
        final Category c = categoryFromJson(raw);
        final String? bad = _rejectCategory(c);
        if (bad != null) {
          skipped.add('category $id: $bad');
          continue;
        }
        categories.add(c);
      } catch (e) {
        skipped.add('category $id: $e');
      }
    }

    final List<Transaction> transactions = <Transaction>[];
    for (final Map<String, Object?> raw in rows('transactions')) {
      final String id = (raw['id'] as String?) ?? '';
      try {
        final Transaction? t = _sanitizeTransaction(raw, known, skipped);
        if (t != null) transactions.add(t);
      } catch (e) {
        skipped.add('transaction $id: $e');
      }
    }

    SettingsRow? settings;
    final Object? rawSettings = json['settings'];
    if (rawSettings is Map<String, Object?>) {
      try {
        final SettingsRow row = settingsFromJson(rawSettings);
        // An unknown default account is CLEARED, not a reason to drop the row:
        // empty means "unchanged" downstream, so the local choice survives,
        // whereas dropping would throw away this peer's currency and language
        // over an unrelated bad account row.
        settings = (row.defaultAccountId.isNotEmpty &&
                !known.contains(row.defaultAccountId))
            ? row.copyWith(defaultAccountId: '')
            : row;
        if (settings != row) {
          skipped.add('settings: unknown default_account_id '
              '${row.defaultAccountId}, left unchanged');
        }
      } catch (e) {
        skipped.add('settings: $e');
      }
    }

    return TallySnapshot(
      schema: schema.toInt(),
      deviceId: (json['device_id'] as String?) ?? '',
      deviceName: (json['device_name'] as String?) ?? '',
      writtenAtMs: (json['written_at_ms'] as num?)?.toInt() ?? 0,
      accounts: accounts,
      categories: categories,
      transactions: transactions,
      settings: settings,
      skipped: skipped,
    );
  }

  static final RegExp _colorRe = RegExp(r'^#[0-9A-Fa-f]{6}$');

  static String? _rejectAccount(Account a) {
    if (a.id.isEmpty) return 'empty id';
    if (a.name.isEmpty) return 'empty name';
    if (!_colorRe.hasMatch(a.color)) return 'bad color ${a.color}';
    if (!AccountKind.isValid(a.kind)) return 'bad kind ${a.kind}';
    if (a.updatedAtMs <= 0) return 'updated_at_ms must be > 0';
    return null;
  }

  static String? _rejectCategory(Category c) {
    if (c.id.isEmpty) return 'empty id';
    if (c.name.isEmpty) return 'empty name';
    if (!_colorRe.hasMatch(c.color)) return 'bad color ${c.color}';
    if (!Kind.isValidCategory(c.kind)) return 'bad kind ${c.kind}';
    if (c.updatedAtMs <= 0) return 'updated_at_ms must be > 0';
    return null;
  }

  /// Mirrors the Go sanitizer's transaction rules, in the same ORDER.
  ///
  /// Resolving the source account BEFORE the transfer rules is load-bearing:
  /// rewriting afterwards would let a transfer with an unknown source and a
  /// destination of cash become cash -> cash, the exact row the self-transfer
  /// check exists to reject.
  static Transaction? _sanitizeTransaction(
    Map<String, Object?> raw,
    Set<String> known,
    List<String> skipped,
  ) {
    Transaction t = transactionFromJson(raw);
    void drop(String why) => skipped.add('transaction ${t.id}: $why');

    if (t.id.isEmpty) {
      skipped.add('transaction with empty id');
      return null;
    }
    if (!Kind.isValidTransaction(t.kind)) {
      drop('bad kind ${t.kind}');
      return null;
    }
    if (t.amountMinor <= 0) {
      drop('amount_minor must be > 0, got ${t.amountMinor}');
      return null;
    }
    if (t.source != TxSource.app && t.source != TxSource.telegram) {
      drop('bad source ${t.source}');
      return null;
    }
    if (t.updatedAtMs <= 0) {
      drop('updated_at_ms must be > 0');
      return null;
    }

    // Losing an entry is worse than misfiling one, so an unknown or absent
    // account books to the default rather than dropping the row.
    if (!known.contains(t.accountId)) {
      if (t.accountId.isNotEmpty) {
        drop('unknown account_id ${t.accountId}, booked to the default '
            'account');
      }
      t = t.copyWith(accountId: defaultAccountId);
    }

    if (t.kind == Kind.transfer) {
      // A transfer never carries a category. Clearing a stray one keeps the
      // row — it is still a real movement of money — while stopping it from
      // reaching a category breakdown.
      t = t.copyWith(categoryId: '');
      if (t.toAccountId.isEmpty) {
        drop('transfer without to_account_id');
        return null;
      }
      if (!known.contains(t.toAccountId)) {
        drop('transfer to unknown account ${t.toAccountId}');
        return null;
      }
      if (t.toAccountId == t.accountId) {
        drop('transfer to the same account');
        return null;
      }
    } else if (t.categoryId.isEmpty) {
      drop('empty category_id');
      return null;
    }

    // Validated, NOT rewritten. Dart's toIso8601String() would re-emit this
    // as "...T09:30:00.000Z" where the Go peer wrote "...T09:30:00Z", so
    // normalizing here would mutate a peer's rows on every merge and make the
    // two implementations disagree byte-for-byte. Period queries compare
    // against fraction-free bounds precisely so both spellings sort correctly
    // (see occurredAtQueryBound).
    if (DateTime.tryParse(t.occurredAt) == null) {
      drop('occurred_at is not RFC3339: ${t.occurredAt}');
      return null;
    }
    return t;
  }

  /// UTF-8 JSON bytes, exactly what gets uploaded to Drive.
  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Parses bytes downloaded from Drive.
  /// Throws [SnapshotFormatException] on anything unusable.
  static TallySnapshot decode(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } catch (e) {
      throw SnapshotFormatException('not valid UTF-8 JSON: $e');
    }
    if (decoded is! Map<String, Object?>) {
      throw const SnapshotFormatException('top level is not a JSON object');
    }
    // NOT wrapped in a catch-all that turns any row problem into a whole-file
    // rejection: fromJson sanitizes per row and reports what it dropped.
    return TallySnapshot.fromJson(decoded);
  }
}
