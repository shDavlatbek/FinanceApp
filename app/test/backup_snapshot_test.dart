/// JSON backup: export is a snapshot, import is a last-write-wins merge
/// (docs/ARCHITECTURE.md § Export and import).
///
/// Every property asserted here is a promise the settings screen makes to the
/// owner before they tap Import: nothing newer is lost, importing twice does
/// nothing, and a deletion made before the backup is not undone by it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:tally/core/constants.dart';
import 'package:tally/data/backup/backup_service.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/drive/snapshot.dart';
import 'package:tally/data/drive/snapshot_merge.dart';
import 'package:tally/data/repo/accounts_repository.dart';
import 'package:tally/data/repo/settings_repository.dart';
import 'package:tally/data/repo/transactions_repository.dart';

import 'support/test_db.dart';

const String _cash = 'a1c7e2f0-0001-4a00-9000-000000000001';
const String _savings = 'a1c7e2f0-0003-4a00-9000-000000000003';
const String _groceries = 'c1a7e2f0-0001-4a00-9000-000000000001';

void main() {
  late AppDatabase source;
  late BackupService sourceBackup;

  setUp(() {
    source = openTestDb();
    sourceBackup = BackupService(
      source,
      clock: () => DateTime(2026, 8, 21, 14, 25, 30),
    );
  });
  tearDown(() => source.close());

  /// A second, independent peer — a fresh install importing the file.
  ({AppDatabase db, BackupService backup}) newPeer() {
    final AppDatabase db = openTestDb();
    addTearDown(db.close);
    return (db: db, backup: BackupService(db));
  }

  test('the file name and mime follow the contract', () async {
    final file = await sourceBackup.buildSnapshotBackup();
    expect(file.fileName, 'tally-backup-20260821-142530.json');
    expect(file.mimeType, 'application/json');
  });

  test('the export IS a snapshot — same envelope, same schema', () async {
    final file = await sourceBackup.buildSnapshotBackup();
    final Map<String, Object?> json =
        jsonDecode(utf8.decode(file.bytes)) as Map<String, Object?>;
    expect(json['schema'], snapshotSchemaVersion);
    // Full dump: the seeds are all there, which is what makes the merge
    // self-healing rather than a diff that can go stale.
    expect((json['accounts']! as List<Object?>), hasLength(4));
    expect((json['categories']! as List<Object?>), hasLength(15));
    expect(json['settings'], isA<Map<String, Object?>>());
    // Parsing it back through the peer parser must work: one format, one
    // parser, or the "backup file is a snapshot file" claim is not true.
    expect(() => TallySnapshot.decode(file.bytes), returnsNormally);
  });

  test('a full round trip restores transactions onto a fresh peer', () async {
    final TransactionsRepository txs = TransactionsRepository(source);
    await txs.insert(
      kind: Kind.expense,
      amountMinor: 24850,
      categoryId: _groceries,
      accountId: _cash,
      note: 'weekly shop',
    );
    await txs.insertTransfer(
      amountMinor: 500000,
      fromAccountId: _cash,
      toAccountId: _savings,
      note: 'rainy day',
    );
    await AccountsRepository(source).insert(
      name: 'Brokerage',
      kind: AccountKind.investment,
      emoji: '📈',
      color: '#9B7DE8',
      openingBalanceMinor: -50000,
    );

    final file = await sourceBackup.buildSnapshotBackup();
    final peer = newPeer();
    final SnapshotMergeResult result =
        await peer.backup.importSnapshot(file.bytes);

    expect(result.transactions, 2);
    expect(result.accounts, 1, reason: 'only the new account is newer');
    expect(result.skipped, isEmpty);

    final List<Transaction> restored =
        await peer.db.select(peer.db.transactions).get();
    expect(restored, hasLength(2));
    final Transaction transfer =
        restored.firstWhere((t) => t.kind == Kind.transfer);
    // A transfer survives as ONE row with both account ids — never split into
    // a pair that could half-arrive.
    expect(transfer.accountId, _cash);
    expect(transfer.toAccountId, _savings);
    expect(transfer.categoryId, isEmpty);

    // A negative opening balance is signed data, not a validation failure.
    final Account brokerage = (await peer.db.select(peer.db.accounts).get())
        .firstWhere((a) => a.name == 'Brokerage');
    expect(brokerage.openingBalanceMinor, -50000);
  });

  test('importing the same file twice changes nothing the second time',
      () async {
    await TransactionsRepository(source).insert(
      kind: Kind.expense,
      amountMinor: 100,
      categoryId: _groceries,
    );
    final file = await sourceBackup.buildSnapshotBackup();
    final peer = newPeer();

    final SnapshotMergeResult first =
        await peer.backup.importSnapshot(file.bytes);
    expect(first.transactions, 1);

    final SnapshotMergeResult second =
        await peer.backup.importSnapshot(file.bytes);
    expect(second.isEmpty, isTrue,
        reason: 'a tie keeps the local row, so a re-import is a no-op');
    expect(await peer.db.select(peer.db.transactions).get(), hasLength(1));
  });

  test('an older backup cannot clobber newer local work', () async {
    final TransactionsRepository sourceTxs = TransactionsRepository(source);
    final Transaction old = await sourceTxs.insert(
      kind: Kind.expense,
      amountMinor: 100,
      categoryId: _groceries,
      note: 'as backed up',
    );
    final file = await sourceBackup.buildSnapshotBackup();

    // The peer has the same row, edited later.
    final peer = newPeer();
    await peer.backup.importSnapshot(file.bytes);
    await (peer.db.update(peer.db.transactions)
          ..where((t) => t.id.equals(old.id)))
        .write(TransactionsCompanion(
      note: const Value('edited afterwards'),
      amountMinor: const Value(999),
      updatedAtMs: Value(old.updatedAtMs + 60000),
    ));

    final SnapshotMergeResult result =
        await peer.backup.importSnapshot(file.bytes);

    expect(result.transactions, 0);
    final Transaction kept = (await peer.db.select(peer.db.transactions).get())
        .firstWhere((t) => t.id == old.id);
    expect(kept.note, 'edited afterwards');
    expect(kept.amountMinor, 999);
  });

  test('a tombstone in the file propagates instead of resurrecting the row',
      () async {
    final TransactionsRepository sourceTxs = TransactionsRepository(source);
    final Transaction doomed = await sourceTxs.insert(
      kind: Kind.expense,
      amountMinor: 100,
      categoryId: _groceries,
      note: 'deleted before the backup',
    );
    await sourceTxs.softDelete(doomed.id);

    final file = await sourceBackup.buildSnapshotBackup();
    final peer = newPeer();
    await peer.backup.importSnapshot(file.bytes);

    final Transaction? row = await (peer.db.select(peer.db.transactions)
          ..where((t) => t.id.equals(doomed.id)))
        .getSingleOrNull();
    expect(row, isNotNull, reason: 'tombstones are kept forever, never purged');
    expect(row!.deletedAtMs, isNotNull,
        reason: 'a deletion made before the backup must be honoured');
  });

  test('the importing peer keeps its own device identity', () async {
    await source.setMeta(MetaKeys.deviceId, 'source-device');
    await source.setMeta(MetaKeys.deviceName, 'Source phone');
    final file = await sourceBackup.buildSnapshotBackup();
    // The file says which device made it…
    expect(utf8.decode(file.bytes), contains('source-device'));

    final peer = newPeer();
    await peer.db.setMeta(MetaKeys.deviceId, 'peer-device');
    await peer.backup.importSnapshot(file.bytes);

    // …and importing it never adopts that identity, or two devices would
    // publish to the same Drive file and stop being single-writer.
    expect(await peer.db.getMeta(MetaKeys.deviceId), 'peer-device');
  });

  test('imported rows are marked dirty so they reach Drive', () async {
    // A restored row exists in no peer's Drive file. Without the dirty flag
    // the restore would live on this device only, and the next sync would
    // report success while publishing nothing.
    await TransactionsRepository(source).insert(
      kind: Kind.expense,
      amountMinor: 100,
      categoryId: _groceries,
    );
    final file = await sourceBackup.buildSnapshotBackup();
    final peer = newPeer();
    await peer.backup.importSnapshot(file.bytes);

    final List<Transaction> rows =
        await peer.db.select(peer.db.transactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.dirty, isTrue);
  });

  test('a merge over Drive does NOT mark rows dirty', () async {
    // The mirror image of the test above, on the same shared merge: a row that
    // arrived over Drive is already published by the peer that wrote it, so
    // republishing it would be pure churn.
    await TransactionsRepository(source).insert(
      kind: Kind.expense,
      amountMinor: 100,
      categoryId: _groceries,
    );
    final file = await sourceBackup.buildSnapshotBackup();
    final peer = newPeer();
    await mergeSnapshots(
      peer.db,
      <TallySnapshot>[TallySnapshot.decode(file.bytes)],
    );

    final List<Transaction> rows =
        await peer.db.select(peer.db.transactions).get();
    expect(rows.single.dirty, isFalse);
  });

  test('a currency chosen in the backup wins over an untouched seed', () async {
    await SettingsRepository(source).setCurrency('UZS');
    final file = await sourceBackup.buildSnapshotBackup();
    final peer = newPeer();
    final SnapshotMergeResult result =
        await peer.backup.importSnapshot(file.bytes);

    expect(result.settings, isTrue);
    expect(await SettingsRepository(peer.db).getCurrency(), 'UZS');
  });

  test('one malformed row is skipped, the rest of the file still lands',
      () async {
    // The owner can hand-edit these files in the Drive UI. Losing every other
    // row over one stray value would look exactly like a sync that silently
    // stopped working.
    await TransactionsRepository(source).insert(
      kind: Kind.expense,
      amountMinor: 100,
      categoryId: _groceries,
      note: 'good row',
    );
    final file = await sourceBackup.buildSnapshotBackup();
    final Map<String, Object?> json =
        jsonDecode(utf8.decode(file.bytes)) as Map<String, Object?>;
    (json['transactions']! as List<Object?>).add(<String, Object?>{
      'id': 'broken',
      'kind': 'expense',
      'amount_minor': -5, // must be > 0
      'category_id': _groceries,
      'occurred_at': '2026-08-20T10:00:00Z',
      'updated_at_ms': 1787000000000,
    });

    final peer = newPeer();
    final SnapshotMergeResult result = await peer.backup.importSnapshot(
      Uint8List.fromList(utf8.encode(jsonEncode(json))),
    );

    expect(result.transactions, 1);
    expect(result.skipped, hasLength(1));
    expect(result.skipped.single, contains('amount_minor'));
  });

  test('an unreadable file throws BackupImportException, not a raw parse error',
      () async {
    final peer = newPeer();
    await expectLater(
      peer.backup.importSnapshot(utf8.encode('not json at all')),
      throwsA(isA<BackupImportException>()),
    );
    await expectLater(
      peer.backup.importSnapshot(utf8.encode('{"device_id":"x"}')),
      throwsA(isA<BackupImportException>().having(
        (e) => e.message,
        'message',
        contains('schema'),
      )),
    );
  });

  test('a snapshot lifted out of the Drive folder restores just as well',
      () async {
    // The contract's claim, tested against the shared interop fixture rather
    // than a file this code wrote — the fixture is what pins the wire format
    // across the Go and Dart peers.
    final Uint8List bytes = Uint8List.fromList(
      File('../docs/fixtures/snapshot.example.json').readAsBytesSync(),
    );
    final peer = newPeer();
    final SnapshotMergeResult result =
        await peer.backup.importSnapshot(bytes);
    expect(result.rows, greaterThan(0));
  });
}
