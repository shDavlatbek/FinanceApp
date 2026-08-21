/// Export and import (docs/ARCHITECTURE.md § Export and import).
///
/// Both directions reuse the **Drive snapshot format, unchanged** — a backup
/// file IS a peer snapshot. Export serializes the same full-state dump the
/// Drive publisher builds; import runs the same parse -> sanitize -> merge
/// path a peer file goes through. One wire format, one parser, one sanitizer,
/// one merge rule, all of them already pinned by the shared interop fixture.
///
/// The CSV export is the other direction only: CSV cannot carry tombstones or
/// settings, so it is not a restore path and must never be offered as one.
///
/// This class deals in BYTES, never in files. Choosing a location, prompting
/// the owner and touching the filesystem all live behind
/// [BackupFileTransport], which keeps every rule above unit-testable.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants.dart';
import '../../core/dates.dart';
import '../../core/money.dart';
import '../db/database.dart';
import '../drive/snapshot.dart';
import '../drive/snapshot_merge.dart';
import '../repo/transactions_repository.dart' show sortedForDisplay;
import 'backup_file.dart';
import 'csv.dart';

/// Column header of the CSV export, in contract order.
const List<String> kCsvHeader = <String>[
  'date',
  'kind',
  'amount',
  'currency',
  'category',
  'account',
  'to_account',
  'note',
];

/// Formats minor units as the CSV `amount` column: a plain decimal with a `.`
/// separator, no grouping, scaled by the currency's exponent.
///
/// Deliberately built from integer arithmetic rather than `NumberFormat`. The
/// column has to be parseable by a spreadsheet formula no matter which
/// language the app is in, and a localized money string would write `1 234,50`
/// in Russian — three columns and a wrong number as far as a CSV reader is
/// concerned.
String csvAmount(int amountMinor, String currencyCode) {
  final int digits = decimalDigitsFor(currencyCode);
  final String sign = amountMinor < 0 ? '-' : '';
  final int magnitude = amountMinor.abs();
  if (digits == 0) return '$sign$magnitude';
  final int per = minorUnitsPerMajor(currencyCode);
  final int whole = magnitude ~/ per;
  final int frac = magnitude % per;
  return '$sign$whole.${frac.toString().padLeft(digits, '0')}';
}

/// Thrown when an imported file is not a usable snapshot. Wraps
/// [SnapshotFormatException] so callers do not have to know which layer failed.
class BackupImportException implements Exception {
  const BackupImportException(this.message);

  final String message;

  @override
  String toString() => 'BackupImportException: $message';
}

class BackupService {
  BackupService(
    this._db, {
    this._onMutation,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final void Function()? _onMutation;
  final DateTime Function() _clock;

  // ---- JSON backup — the restore path -------------------------------------

  /// Serializes the full local state as a snapshot file.
  ///
  /// Carries this device's identity, exactly like the file published to Drive,
  /// so a backup says which device made it. On the way back in that identity
  /// is ignored — the importing peer never adopts the exporter's.
  Future<BackupFile> buildSnapshotBackup() async {
    final LocalSnapshotState local = await readLocalSnapshotState(_db);
    final TallySnapshot snapshot = TallySnapshot(
      deviceId: await _db.getMeta(MetaKeys.deviceId) ?? '',
      deviceName: await _db.getMeta(MetaKeys.deviceName) ?? '',
      writtenAtMs: _clock().millisecondsSinceEpoch,
      accounts: local.accounts,
      categories: local.categories,
      transactions: local.transactions,
      settings: local.settings,
    );
    return BackupFile(
      fileName: 'tally-backup-${fileStamp(_clock())}.json',
      mimeType: snapshotMimeType,
      bytes: snapshot.encode(),
    );
  }

  /// Imports a snapshot file as a **merge under strict last-write-wins**,
  /// identical to a sync pass.
  ///
  /// Consequences, all of them wanted: importing the same file twice changes
  /// nothing the second time, importing a backup into a populated app cannot
  /// destroy newer work, and tombstones in the file propagate rather than
  /// resurrecting rows deleted before the backup was taken.
  ///
  /// Rows that land are marked dirty so this peer republishes them: a restored
  /// row exists in no peer's Drive file, and without that flag the restore
  /// would live only on this device.
  Future<SnapshotMergeResult> importSnapshot(List<int> bytes) async {
    final TallySnapshot snapshot;
    try {
      snapshot = TallySnapshot.decode(bytes);
    } on SnapshotFormatException catch (e) {
      throw BackupImportException(e.message);
    }
    final SnapshotMergeResult result = await mergeSnapshots(
      _db,
      <TallySnapshot>[snapshot],
      markDirty: true,
    );
    if (!result.isEmpty) _onMutation?.call();
    return result;
  }

  // ---- CSV export — the spreadsheet path ----------------------------------

  /// Writes non-deleted transactions as RFC 4180 CSV, UTF-8 with a BOM.
  ///
  /// The category and account **rows** are loaded here, from the database, and
  /// only their naming is delegated: [localizeCategory] and [localizeAccount]
  /// receive an `(id, name)` pair and apply the seed-name rule for the current
  /// UI language, which needs a `BuildContext` this layer must not grow.
  ///
  /// Loading the rows rather than accepting a caller-supplied lookup map is
  /// deliberate. The obvious version — hand in `categoriesByIdProvider` —
  /// silently exported empty name columns, because that provider is derived
  /// from a stream nothing on the Settings screen subscribes to, so reading it
  /// cold yields an empty map. The database is always warm.
  ///
  /// Rows come out in the app's own display order — newest day first, then the
  /// owner's manual placement inside the day. Matching what History shows is
  /// what makes the file recognizable; a spreadsheet is a view of the ledger,
  /// not a different ledger.
  Future<BackupFile> buildCsvExport({
    required String currency,
    required String Function(String id, String name) localizeCategory,
    required String Function(String id, String name) localizeAccount,
  }) async {
    final List<Transaction> rows = sortedForDisplay(
      await (_db.select(_db.transactions)
            ..where((t) => t.deletedAtMs.isNull()))
          .get(),
    );
    // Archived rows included: a transaction booked to a closed wallet must
    // still name it, exactly as it does on screen.
    final Map<String, String> categoryNames = <String, String>{
      for (final Category c in await _db.select(_db.categories).get())
        c.id: localizeCategory(c.id, c.name),
    };
    final Map<String, String> accountNames = <String, String>{
      for (final Account a in await _db.select(_db.accounts).get())
        a.id: localizeAccount(a.id, a.name),
    };

    final List<List<String>> table = <List<String>>[
      kCsvHeader,
      for (final Transaction t in rows)
        <String>[
          utcDayKeyFromOccurredAt(t.occurredAt),
          // The RAW kind, never a translation, so a spreadsheet formula can
          // filter on it.
          t.kind,
          csvAmount(t.amountMinor, currency),
          currency,
          // A transfer has no category, and nothing else has a destination.
          // An id nothing resolves — only a hand-edited peer file produces
          // one — leaves the cell empty rather than leaking a raw UUID into a
          // human-facing column.
          t.kind == Kind.transfer ? '' : (categoryNames[t.categoryId] ?? ''),
          accountNames[t.accountId] ?? '',
          t.kind == Kind.transfer ? (accountNames[t.toAccountId] ?? '') : '',
          t.note,
        ],
    ];

    return BackupFile(
      fileName: 'tally-${fileStamp(_clock())}.csv',
      mimeType: 'text/csv',
      bytes: Uint8List.fromList(utf8.encode(csvDocument(table))),
    );
  }
}
