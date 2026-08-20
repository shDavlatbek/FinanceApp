/// The Drive snapshot envelope (docs/ARCHITECTURE.md § Drive layout).
///
/// One file per peer, `tally-<device_id>.json`, uncompressed so the owner can
/// read their own data in the Drive UI. The payload is a **full dump** of that
/// peer's local state, tombstones included — which is what makes the merge
/// idempotent and self-healing.
///
/// ```json
/// {
///   "schema": 1,
///   "device_id": "b2c3…",
///   "device_name": "Pixel 7",
///   "written_at_ms": 1787160000000,
///   "categories":   [ Category… ],
///   "transactions": [ Transaction… ],
///   "settings":     Settings
/// }
/// ```
///
/// The local-only `dirty` flag is never serialized; decoded rows always carry
/// `dirty = false`.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants.dart';
import '../db/database.dart';

// ---- row <-> JSON (field names are the binding contract) -------------------

Map<String, Object?> transactionToJson(Transaction t) => <String, Object?>{
      'id': t.id,
      'kind': t.kind,
      'amount_minor': t.amountMinor,
      'category_id': t.categoryId,
      'note': t.note,
      'occurred_at': t.occurredAt,
      'source': t.source,
      'created_at_ms': t.createdAtMs,
      'updated_at_ms': t.updatedAtMs,
      'deleted_at_ms': t.deletedAtMs,
    };

Transaction transactionFromJson(Map<String, Object?> j) => Transaction(
      id: j['id']! as String,
      kind: j['kind']! as String,
      amountMinor: (j['amount_minor']! as num).toInt(),
      categoryId: j['category_id']! as String,
      note: (j['note'] as String?) ?? '',
      occurredAt: j['occurred_at']! as String,
      source: (j['source'] as String?) ?? TxSource.app,
      createdAtMs: (j['created_at_ms'] as num?)?.toInt() ??
          (j['updated_at_ms']! as num).toInt(),
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
      'updated_at_ms': s.updatedAtMs,
    };

SettingsRow settingsFromJson(Map<String, Object?> j) => SettingsRow(
      id: (j['id'] as String?) ?? settingsRowId,
      currency: (j['currency'] as String?) ?? defaultCurrency,
      language: (j['language'] as String?) ?? defaultLanguage,
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
    this.schema = snapshotSchemaVersion,
  });

  final int schema;
  final String deviceId;
  final String deviceName;
  final int writtenAtMs;
  final List<Category> categories;
  final List<Transaction> transactions;
  final SettingsRow? settings;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': schema,
        'device_id': deviceId,
        'device_name': deviceName,
        'written_at_ms': writtenAtMs,
        'categories': <Object?>[
          for (final Category c in categories) categoryToJson(c),
        ],
        'transactions': <Object?>[
          for (final Transaction t in transactions) transactionToJson(t),
        ],
        'settings': settings == null ? null : settingsToJson(settings!),
      };

  factory TallySnapshot.fromJson(Map<String, Object?> json) {
    final Object? schema = json['schema'];
    if (schema is! num) {
      throw const SnapshotFormatException('missing "schema"');
    }
    if (schema.toInt() > snapshotSchemaVersion) {
      throw SnapshotFormatException(
          'snapshot schema ${schema.toInt()} is newer than '
          '$snapshotSchemaVersion');
    }
    return TallySnapshot(
      schema: schema.toInt(),
      deviceId: (json['device_id'] as String?) ?? '',
      deviceName: (json['device_name'] as String?) ?? '',
      writtenAtMs: (json['written_at_ms'] as num?)?.toInt() ?? 0,
      categories: <Category>[
        for (final Object? c in (json['categories'] as List<Object?>?) ??
            const <Object?>[])
          categoryFromJson(c! as Map<String, Object?>),
      ],
      transactions: <Transaction>[
        for (final Object? t in (json['transactions'] as List<Object?>?) ??
            const <Object?>[])
          transactionFromJson(t! as Map<String, Object?>),
      ],
      settings: json['settings'] == null
          ? null
          : settingsFromJson(json['settings']! as Map<String, Object?>),
    );
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
    try {
      return TallySnapshot.fromJson(decoded);
    } on SnapshotFormatException {
      rethrow;
    } catch (e) {
      throw SnapshotFormatException('malformed row: $e');
    }
  }
}
