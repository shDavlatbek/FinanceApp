/// DriveSyncEngine against a real in-memory AppDatabase and a fake Drive
/// folder: the LWW merge (tombstones + ties), the dirty-clearing rule, the
/// md5 skip-cache, and the account-switch reset.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:tally/core/constants.dart';
import 'package:tally/data/db/database.dart';
import 'package:tally/data/drive/drive_client.dart';
import 'package:tally/data/drive/drive_sync_engine.dart';
import 'package:tally/data/drive/snapshot.dart';
import 'package:tally/data/repo/settings_repository.dart';
import 'package:tally/data/repo/transactions_repository.dart';

import 'support/fake_drive.dart';
import 'support/test_db.dart';

const String _groceriesId = 'c1a7e2f0-0001-4a00-9000-000000000001';
const String _salaryId = 'c1a7e2f0-0101-4a00-9000-000000000101';
const String _deviceId = 'device-a';
const String _selfName = 'tally-$_deviceId.json';
const String _peerName = 'tally-device-bot.json';

DriveSyncEngine _engine(
  AppDatabase db, {
  required FakeDriveClient drive,
  FakeDeviceAuth? auth,
  int Function()? now,
}) =>
    DriveSyncEngine(
      db,
      auth: auth ?? FakeDeviceAuth(),
      driveClientFactory: (_) => drive,
      now: now ?? (() => 1_800_000_000_000),
      newId: () => _deviceId,
      deviceName: () => 'Test Device',
    );

/// Puts the engine in the "already connected" state without a device flow.
Future<DriveSyncEngine> _connected(
  AppDatabase db, {
  required FakeDriveClient drive,
  FakeDeviceAuth? auth,
  int Function()? now,
  String refreshToken = 'refresh-A',
}) async {
  await db.setMeta(MetaKeys.googleRefreshToken, refreshToken);
  await db.setMeta(MetaKeys.deviceId, _deviceId);
  await db.setMeta(MetaKeys.deviceName, 'Test Device');
  final DriveSyncEngine engine =
      _engine(db, drive: drive, auth: auth, now: now);
  await engine.init();
  return engine;
}

/// A snapshot published by the "bot" peer, dropped straight into the folder.
FakeDriveFile _publishPeer(
  FakeDriveClient drive, {
  required String folderId,
  List<Category> categories = const <Category>[],
  List<Transaction> transactions = const <Transaction>[],
  SettingsRow? settings,
  String name = _peerName,
}) =>
    drive.putPeerFile(
      folderId: folderId,
      name: name,
      bytes: TallySnapshot(
        deviceId: 'device-bot',
        deviceName: 'Telegram bot',
        writtenAtMs: 1_700_000_000_000,
        categories: categories,
        transactions: transactions,
        settings: settings,
      ).encode(),
    );

void main() {
  late AppDatabase db;

  setUp(() {
    db = openTestDb();
  });

  tearDown(() async {
    await db.close();
  });

  // ---- seeding ------------------------------------------------------------

  group('seeding', () {
    test('creates the 15 fixed categories and the settings row', () async {
      final List<Category> cats = await db.select(db.categories).get();
      expect(cats, hasLength(15));
      expect(cats.map((Category c) => c.id),
          containsAll(seedCategories.map((SeedCategory s) => s.id)));
      final Category groceries =
          cats.singleWhere((Category c) => c.id == _groceriesId);
      expect(groceries.name, 'Groceries');
      expect(groceries.emoji, '🛒');
      expect(groceries.updatedAtMs, seedUpdatedAtMs);
      expect(cats.every((Category c) => !c.dirty), isTrue);

      final SettingsRow settings = await db.select(db.settings).getSingle();
      expect(settings.id, 'settings');
      expect(settings.currency, 'USD');
      expect(settings.language, ''); // follow the device locale
      expect(settings.defaultAccountId, defaultAccountId);
      // The settings singleton seeds at the "nobody chose anything" sentinel,
      // NOT at seedUpdatedAtMs. A fixed non-zero seed would tie with the
      // server's identical seed and freeze currency and language on both
      // peers forever under strict LWW.
      expect(settings.updatedAtMs, settingsUnsetMs);
      expect(settings.dirty, isFalse);
    });
  });

  // ---- configuration ------------------------------------------------------

  group('configuration', () {
    test('no refresh token -> syncNow is a no-op, status notConfigured',
        () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = _engine(db, drive: drive);
      await engine.init();
      expect(engine.status, isA<SyncNotConfigured>());
      expect(engine.isConfigured, isFalse);
      expect(await engine.syncNow(), isFalse);
      expect(drive.listedFolderIds, isEmpty);
      expect(await engine.connectionInfo(), isNull);
    });

    test('syncNow before init completes still syncs (cold-start trigger)',
        () async {
      await db.setMeta(MetaKeys.googleRefreshToken, 'refresh-A');
      final FakeDriveClient drive = FakeDriveClient();
      // Do NOT await init() — mirrors the provider's fire-and-forget usage
      // plus main.dart's post-frame syncNow().
      final DriveSyncEngine engine = _engine(db, drive: drive);
      expect(await engine.syncNow(), isTrue);
      expect(drive.listedFolderIds, hasLength(1));
      expect(engine.status, isA<SyncIdle>());
    });

    test('the first pass creates the folder, the device id and our file',
        () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      // Wipe the pre-seeded identity so the engine has to mint one.
      await db.deleteMeta(MetaKeys.deviceId);
      await db.deleteMeta(MetaKeys.deviceName);

      expect(await engine.syncNow(), isTrue);

      expect(await db.getMeta(MetaKeys.deviceId), _deviceId);
      expect(await db.getMeta(MetaKeys.deviceName), 'Test Device');
      expect(await db.getMeta(MetaKeys.driveFolderId), 'A-folder-1');
      // Never uploaded before -> publish even though nothing is dirty.
      expect(drive.createdNames, <String>[_selfName]);
      expect(await db.getMeta(MetaKeys.lastSyncMs), '1800000000000');
      expect(engine.lastSyncMs, 1800000000000);

      final DriveConnection? info = await engine.connectionInfo();
      expect(info!.folderName, driveFolderName);
      expect(info.folderId, 'A-folder-1');
      expect(info.snapshotFileName, _selfName);
      expect(info.deviceName, 'Test Device');
    });

    test('clearConfiguration() drops token, folder, md5 cache and last sync',
        () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      await engine.syncNow();
      expect(await db.getMeta(MetaKeys.driveFolderId), isNotNull);

      await engine.clearConfiguration();

      expect(await db.getMeta(MetaKeys.googleRefreshToken), isNull);
      expect(await db.getMeta(MetaKeys.driveFolderId), isNull);
      expect(await db.getMeta(MetaKeys.drivePeerMd5), isNull);
      expect(await db.getMeta(MetaKeys.lastSyncMs), isNull);
      // The device keeps its identity across reconnects.
      expect(await db.getMeta(MetaKeys.deviceId), _deviceId);
      expect(engine.lastSyncMs, isNull);
      expect(engine.status, isA<SyncNotConfigured>());
      expect(engine.isConfigured, isFalse);
    });

    test('disconnect() revokes the token, then clears everything', () async {
      final FakeDeviceAuth auth = FakeDeviceAuth();
      final DriveSyncEngine engine =
          await _connected(db, drive: FakeDriveClient(), auth: auth);
      await engine.disconnect();
      expect(auth.revoked, <String>['refresh-A']);
      expect(await db.getMeta(MetaKeys.googleRefreshToken), isNull);
      expect(engine.status, isA<SyncNotConfigured>());
    });

    test('a rotated refresh token is persisted', () async {
      final FakeDeviceAuth auth =
          FakeDeviceAuth(rotatedRefreshToken: 'refresh-A2');
      final DriveSyncEngine engine =
          await _connected(db, drive: FakeDriveClient(), auth: auth);
      expect(await engine.syncNow(), isTrue);
      expect(await db.getMeta(MetaKeys.googleRefreshToken), 'refresh-A2');
      expect(auth.refreshedWith, <String>['refresh-A']);
    });
  });

  // ---- merge --------------------------------------------------------------

  group('LWW merge', () {
    test('strictly-newer incoming rows win; ties and older rows lose',
        () async {
      final FakeDriveClient drive = FakeDriveClient();
      final String folderId = await drive.findOrCreateFolder(driveFolderName);
      await db.setMeta(MetaKeys.driveFolderId, folderId);

      final Category newer = Category(
        id: _groceriesId,
        name: 'Food',
        emoji: '🥦',
        color: '#00FF00',
        kind: Kind.expense,
        sortOrder: 0,
        updatedAtMs: seedUpdatedAtMs + 1,
        deletedAtMs: null,
        dirty: false,
      );
      final Transaction botTx = Transaction(
        id: 'aaaaaaaa-0000-4000-9000-000000000001',
        kind: Kind.expense,
        amountMinor: 900,
        categoryId: _groceriesId,
        accountId: defaultAccountId,
        toAccountId: '',
        note: 'from telegram',
        occurredAt: '2026-08-19T10:00:00Z',
        source: TxSource.telegram,
        createdAtMs: 5000,
        updatedAtMs: 5000,
        deletedAtMs: null,
        dirty: false,
      );
      final SettingsRow botSettings = SettingsRow(
        id: settingsRowId,
        currency: 'EUR',
        language: 'ru',
        defaultAccountId: defaultAccountId,
        updatedAtMs: seedUpdatedAtMs + 10,
        dirty: false,
      );

      final FakeDriveFile peer = _publishPeer(
        drive,
        folderId: folderId,
        categories: <Category>[newer],
        transactions: <Transaction>[botTx],
        settings: botSettings,
      );

      final DriveSyncEngine engine = await _connected(db, drive: drive);
      expect(await engine.syncNow(), isTrue);

      Category groceries = await (db.select(db.categories)
            ..where((c) => c.id.equals(_groceriesId)))
          .getSingle();
      expect(groceries.name, 'Food');
      expect(groceries.dirty, isFalse); // merged rows land clean

      final Transaction pulled = await (db.select(db.transactions)
            ..where((t) => t.id.equals(botTx.id)))
          .getSingle();
      expect(pulled.note, 'from telegram');
      expect(pulled.source, TxSource.telegram);
      expect(pulled.dirty, isFalse);

      SettingsRow settings = await db.select(db.settings).getSingle();
      expect(settings.currency, 'EUR');
      expect(settings.language, 'ru'); // the language field syncs

      // Second publish from the bot: one row with an EQUAL timestamp and one
      // strictly older. Both must be ignored (ties keep the local row).
      peer.bytes = TallySnapshot(
        deviceId: 'device-bot',
        deviceName: 'Telegram bot',
        writtenAtMs: 1_700_000_000_001,
        categories: <Category>[
          newer.copyWith(name: 'IGNORED-tie'), // same updated_at_ms
          newer.copyWith(
              name: 'IGNORED-older', updatedAtMs: seedUpdatedAtMs - 1),
        ],
        transactions: const <Transaction>[],
        settings: botSettings.copyWith(currency: 'GBP'), // equal ts -> ignored
      ).encode();

      expect(await engine.syncNow(), isTrue);
      groceries = await (db.select(db.categories)
            ..where((c) => c.id.equals(_groceriesId)))
          .getSingle();
      expect(groceries.name, 'Food');
      settings = await db.select(db.settings).getSingle();
      expect(settings.currency, 'EUR');
    });

    test('applies tombstones from a peer', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final String folderId = await drive.findOrCreateFolder(driveFolderName);
      await db.setMeta(MetaKeys.driveFolderId, folderId);

      final TransactionsRepository repo =
          TransactionsRepository(db, now: () => 1000);
      final Transaction tx = await repo.insert(
        kind: Kind.expense,
        amountMinor: 100,
        categoryId: _groceriesId,
      );

      _publishPeer(
        drive,
        folderId: folderId,
        transactions: <Transaction>[
          tx.copyWith(
            updatedAtMs: 2000,
            deletedAtMs: const Value(2000),
            dirty: false,
          ),
        ],
      );

      final DriveSyncEngine engine = await _connected(db, drive: drive);
      expect(await engine.syncNow(), isTrue);

      final Transaction after = await (db.select(db.transactions)
            ..where((t) => t.id.equals(tx.id)))
          .getSingle();
      expect(after.deletedAtMs, 2000);
      expect(after.updatedAtMs, 2000);
      expect(after.dirty, isFalse);
    });

    test('a corrupt peer file is skipped without failing the pass', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final String folderId = await drive.findOrCreateFolder(driveFolderName);
      await db.setMeta(MetaKeys.driveFolderId, folderId);
      drive.putPeerFile(
        folderId: folderId,
        name: 'tally-device-broken.json',
        bytes: <int>[0x7b, 0x21], // "{!"
      );

      final DriveSyncEngine engine = await _connected(db, drive: drive);
      expect(await engine.syncNow(), isTrue);
      expect(engine.status, isA<SyncIdle>());
      // Its md5 is NOT cached, so a fixed version is picked up next pass.
      expect(await db.getMeta(MetaKeys.drivePeerMd5), '{}');
    });
  });

  // ---- publish + dirty clearing ------------------------------------------

  group('publish and dirty clearing', () {
    test('publishes a full dump when a row is dirty, then clears dirty',
        () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      expect(await engine.syncNow(), isTrue); // first upload (create)

      final TransactionsRepository repo =
          TransactionsRepository(db, now: () => 1000);
      final Transaction tx = await repo.insert(
        kind: Kind.expense,
        amountMinor: 25000,
        categoryId: _groceriesId,
        accountId: defaultAccountId,
        note: 'weekly stuff',
      );
      expect(tx.dirty, isTrue);

      expect(await engine.syncNow(), isTrue);
      expect(drive.createdNames, <String>[_selfName]);
      expect(drive.updatedIds, hasLength(1)); // updated in place, by id

      final TallySnapshot published =
          TallySnapshot.decode(drive.fileNamed(_selfName)!.bytes);
      expect(published.deviceId, _deviceId);
      expect(published.deviceName, 'Test Device');
      expect(published.categories, hasLength(15)); // full dump, not a delta
      expect(published.transactions.map((Transaction t) => t.id), <String>[
        tx.id,
      ]);
      expect(published.settings!.currency, 'USD');

      final Transaction after = await (db.select(db.transactions)
            ..where((t) => t.id.equals(tx.id)))
          .getSingle();
      expect(after.dirty, isFalse);
      expect(after.updatedAtMs, 1000); // never bumped by sync
    });

    test('nothing dirty and already uploaded -> no upload at all', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      expect(await engine.syncNow(), isTrue);
      expect(drive.createdNames, hasLength(1));

      expect(await engine.syncNow(), isTrue);
      expect(drive.createdNames, hasLength(1));
      expect(drive.updatedIds, isEmpty);
    });

    test('a row edited mid-upload stays dirty for the next pass', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      await engine.syncNow(); // create our file first

      final Transaction tx = await TransactionsRepository(db, now: () => 1000)
          .insert(
        kind: Kind.expense,
        amountMinor: 100,
        categoryId: _groceriesId,
      );

      // The user edits the row while the snapshot is in flight.
      drive.onBeforeUpload = () async {
        drive.onBeforeUpload = null;
        await TransactionsRepository(db, now: () => 9999)
            .update(id: tx.id, amountMinor: 777);
      };

      expect(await engine.syncNow(), isTrue);

      final Transaction after = await (db.select(db.transactions)
            ..where((t) => t.id.equals(tx.id)))
          .getSingle();
      expect(after.amountMinor, 777);
      expect(after.updatedAtMs, 9999);
      expect(after.dirty, isTrue); // updated_at_ms moved -> not cleared
    });

    test('a settings write is published and cleared like any other row',
        () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      await engine.syncNow();

      await SettingsRepository(db, now: () => 4242).setLanguage('uz');
      expect((await db.select(db.settings).getSingle()).dirty, isTrue);

      expect(await engine.syncNow(), isTrue);
      final TallySnapshot published =
          TallySnapshot.decode(drive.fileNamed(_selfName)!.bytes);
      expect(published.settings!.language, 'uz');

      final SettingsRow after = await db.select(db.settings).getSingle();
      expect(after.dirty, isFalse);
      expect(after.updatedAtMs, 4242);
    });
  });

  // ---- md5 skip cache -----------------------------------------------------

  group('md5 skip cache', () {
    test('an unchanged peer is never downloaded twice', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final String folderId = await drive.findOrCreateFolder(driveFolderName);
      await db.setMeta(MetaKeys.driveFolderId, folderId);
      final FakeDriveFile peer = _publishPeer(
        drive,
        folderId: folderId,
        transactions: <Transaction>[
          Transaction(
            id: 'bbbbbbbb-0000-4000-9000-000000000001',
            kind: Kind.income,
            amountMinor: 500000,
            categoryId: _salaryId,
            accountId: defaultAccountId,
            toAccountId: '',
            note: 'salary',
            occurredAt: '2026-08-01T09:00:00Z',
            source: TxSource.telegram,
            createdAtMs: 3000,
            updatedAtMs: 3000,
            deletedAtMs: null,
            dirty: false,
          ),
        ],
      );

      final DriveSyncEngine engine = await _connected(db, drive: drive);

      expect(await engine.syncNow(), isTrue);
      expect(drive.downloadedIds, <String>[peer.id]);
      expect(await db.getMeta(MetaKeys.drivePeerMd5),
          '{"${peer.id}":"${peer.md5}"}');

      // Nothing changed on the peer -> the md5 matches -> zero downloads.
      expect(await engine.syncNow(), isTrue);
      expect(drive.downloadedIds, <String>[peer.id]);

      // The peer republishes -> new md5 -> downloaded again.
      peer.bytes = TallySnapshot(
        deviceId: 'device-bot',
        deviceName: 'Telegram bot',
        writtenAtMs: 1_700_000_000_002,
        categories: const <Category>[],
        transactions: <Transaction>[
          Transaction(
            id: 'bbbbbbbb-0000-4000-9000-000000000002',
            kind: Kind.expense,
            amountMinor: 1234,
            categoryId: _groceriesId,
            accountId: defaultAccountId,
            toAccountId: '',
            note: 'milk',
            occurredAt: '2026-08-20T09:00:00Z',
            source: TxSource.telegram,
            createdAtMs: 4000,
            updatedAtMs: 4000,
            deletedAtMs: null,
            dirty: false,
          ),
        ],
        settings: null,
      ).encode();

      expect(await engine.syncNow(), isTrue);
      expect(drive.downloadedIds, <String>[peer.id, peer.id]);
      expect(
        await (db.select(db.transactions)
              ..where((t) =>
                  t.id.equals('bbbbbbbb-0000-4000-9000-000000000002')))
            .getSingleOrNull(),
        isNotNull,
      );
    });

    test('our own file is never downloaded and never md5-cached', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      await engine.syncNow(); // creates tally-device-a.json
      await engine.syncNow();
      expect(drive.downloadedIds, isEmpty);
      expect(await db.getMeta(MetaKeys.drivePeerMd5), '{}');
    });

    test('a vanished peer drops out of the cache', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final String folderId = await drive.findOrCreateFolder(driveFolderName);
      await db.setMeta(MetaKeys.driveFolderId, folderId);
      final FakeDriveFile peer = _publishPeer(drive, folderId: folderId);

      final DriveSyncEngine engine = await _connected(db, drive: drive);
      await engine.syncNow();
      expect(await db.getMeta(MetaKeys.drivePeerMd5), contains(peer.id));

      drive.filesById.remove(peer.id);
      await engine.syncNow();
      expect(await db.getMeta(MetaKeys.drivePeerMd5), isNot(contains(peer.id)));
    });
  });

  // ---- account switch -----------------------------------------------------

  group('account switch', () {
    test(
        'connecting a DIFFERENT account resets sync state and re-marks rows '
        'dirty without bumping updated_at_ms', () async {
      final FakeDriveClient driveA = FakeDriveClient(accountLabel: 'A');
      final FakeDeviceAuth authA = FakeDeviceAuth();
      final DriveSyncEngine engineA =
          await _connected(db, drive: driveA, auth: authA);

      final Transaction tx = await TransactionsRepository(db, now: () => 1000)
          .insert(
        kind: Kind.expense,
        amountMinor: 4200,
        categoryId: _groceriesId,
      );
      expect(await engineA.syncNow(), isTrue);
      // Everything is clean and cached after a good pass against account A.
      expect(
        (await (db.select(db.transactions)..where((t) => t.id.equals(tx.id)))
                .getSingle())
            .dirty,
        isFalse,
      );
      expect(await db.getMeta(MetaKeys.driveFolderId), 'A-folder-1');
      expect(await db.getMeta(MetaKeys.lastSyncMs), isNotNull);
      engineA.dispose();

      // Now connect account B. Its Drive is unreachable, which freezes the
      // post-reset state so the test can inspect it.
      final FakeDriveClient driveB = FakeDriveClient(accountLabel: 'B')
        ..failWith = const DriveNetworkException('offline');
      final FakeDeviceAuth authB = FakeDeviceAuth()
        ..grantedRefreshToken = 'refresh-B';
      final DriveSyncEngine engineB = _engine(db, drive: driveB, auth: authB);
      await engineB.init();
      await engineB.completeAuthorization(await engineB.beginAuthorization());

      expect(await db.getMeta(MetaKeys.googleRefreshToken), 'refresh-B');
      // Sync state for account A is gone.
      expect(await db.getMeta(MetaKeys.driveFolderId), isNull);
      expect(await db.getMeta(MetaKeys.drivePeerMd5), isNull);
      expect(await db.getMeta(MetaKeys.lastSyncMs), isNull);
      expect(engineB.lastSyncMs, isNull);
      expect(engineB.status, isA<SyncOffline>());

      // Every row is dirty again, and no timestamp moved — the new peers'
      // LWW merge then decides fairly.
      final Transaction after = await (db.select(db.transactions)
            ..where((t) => t.id.equals(tx.id)))
          .getSingle();
      expect(after.dirty, isTrue);
      expect(after.updatedAtMs, 1000);
      final List<Category> cats = await db.select(db.categories).get();
      expect(cats, hasLength(15));
      expect(cats.every((Category c) => c.dirty), isTrue);
      expect(cats.every((Category c) => c.updatedAtMs == seedUpdatedAtMs),
          isTrue);
      expect((await db.select(db.settings).getSingle()).dirty, isTrue);
      expect((await db.select(db.settings).getSingle()).updatedAtMs,
          settingsUnsetMs);
      engineB.dispose();
    });

    test('re-authorizing the SAME account keeps the sync state', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final FakeDeviceAuth auth = FakeDeviceAuth();
      final DriveSyncEngine engine =
          await _connected(db, drive: drive, auth: auth);
      expect(await engine.syncNow(), isTrue);
      expect(drive.createdNames, hasLength(1));
      final String? folderId = await db.getMeta(MetaKeys.driveFolderId);

      // Same refresh token comes back -> no reset, nothing re-published.
      await engine.completeAuthorization(await engine.beginAuthorization());

      expect(await db.getMeta(MetaKeys.driveFolderId), folderId);
      expect(drive.createdNames, hasLength(1));
      expect(drive.updatedIds, isEmpty);
      final List<Category> cats = await db.select(db.categories).get();
      expect(cats.every((Category c) => !c.dirty), isTrue);
    });

    test('a cached folder id that no longer exists is re-resolved, and a '
        'DIFFERENT folder resets the sync state', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);

      final Transaction tx = await TransactionsRepository(db, now: () => 1000)
          .insert(
        kind: Kind.expense,
        amountMinor: 999,
        categoryId: _groceriesId,
      );
      expect(await engine.syncNow(), isTrue);
      expect(await db.getMeta(MetaKeys.driveFolderId), 'A-folder-1');
      expect(
        (await (db.select(db.transactions)..where((t) => t.id.equals(tx.id)))
                .getSingle())
            .dirty,
        isFalse,
      );
      expect(drive.updatedIds, isEmpty);

      // The user deleted the Tally folder from Drive for good: the cached id
      // resolves to nothing and find-or-create mints a different one.
      drive.filesById.clear();
      drive.folderIdsByName.clear();

      expect(await engine.syncNow(), isTrue);

      final String? folderId = await db.getMeta(MetaKeys.driveFolderId);
      expect(folderId, isNotNull);
      expect(folderId, isNot('A-folder-1'));

      // The fresh folder got a full re-publish (create, not update)...
      expect(drive.createdNames, <String>[_selfName, _selfName]);
      final TallySnapshot published =
          TallySnapshot.decode(drive.fileNamed(_selfName)!.bytes);
      expect(published.transactions.map((Transaction t) => t.id),
          contains(tx.id));
      expect(published.categories, hasLength(15));

      // ...and the reset left every updated_at_ms alone.
      final Transaction after = await (db.select(db.transactions)
            ..where((t) => t.id.equals(tx.id)))
          .getSingle();
      expect(after.updatedAtMs, 1000);
      expect(after.dirty, isFalse); // cleared again by the successful publish
    });

    test('a TRASHED folder is detected even though listing it still '
        'answers 200 with an empty list', () async {
      // Regression: folder liveness used to be inferred from `files.list`,
      // which never 404s — a `'<dead id>' in parents` query just matches
      // nothing. The app therefore kept publishing into the trashed folder
      // (reporting "Connected") while the Go peer, whose folder query filters
      // `trashed = false`, created a brand-new Tally folder.
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      expect(await engine.syncNow(), isTrue);
      expect(await db.getMeta(MetaKeys.driveFolderId), 'A-folder-1');
      expect(drive.createdNames, <String>[_selfName]);

      // The user drags Tally into the Drive trash.
      drive.trashFolder('A-folder-1');
      // Sanity: the fake behaves like the real API — no 404, just nothing.
      expect(await drive.listSnapshots('A-folder-1'), isEmpty);

      expect(await engine.syncNow(), isTrue);

      final String? folderId = await db.getMeta(MetaKeys.driveFolderId);
      expect(folderId, isNotNull);
      expect(folderId, isNot('A-folder-1'),
          reason: 'the dead folder id must be dropped, not reused');
      expect(drive.checkedFolderIds, contains('A-folder-1'));
      // Our snapshot was re-created inside the live folder, not the trash.
      expect(drive.createdNames, <String>[_selfName, _selfName]);
      expect(drive.fileNamed(_selfName, inFolder: folderId), isNotNull);
      expect(drive.listedFolderIds.last, folderId);
    });
  });

  // ---- coalescing ---------------------------------------------------------

  group('coalescing', () {
    test('a call made while a pass is in flight reports that pass\'s result, '
        'not a failure', () async {
      // Regression: the coalescing branch returned false immediately, so
      // tapping "Sync now" within 3 s of a local write showed "Sync failed"
      // while the status row said "Connected".
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);

      Future<bool>? queued;
      drive.onBeforeUpload = () async {
        drive.onBeforeUpload = null;
        queued = engine.syncNow(); // lands mid-pass -> coalesces
      };

      expect(await engine.syncNow(), isTrue);
      expect(queued, isNotNull);
      expect(await queued!, isTrue);
      expect(engine.status, isA<SyncIdle>());
      // The queued call really ran a second pass rather than returning early.
      expect(drive.listedFolderIds, hasLength(2));
    });

    test('a coalesced call reports the failure when the pass fails', () async {
      final FakeDriveClient drive = FakeDriveClient();
      final DriveSyncEngine engine = await _connected(db, drive: drive);

      Future<bool>? queued;
      drive.onBeforeUpload = () async {
        drive.onBeforeUpload = null;
        queued = engine.syncNow();
        drive.failWith = const DriveNetworkException('lost the connection');
      };

      expect(await engine.syncNow(), isFalse);
      expect(await queued!, isFalse);
      expect(engine.status, isA<SyncOffline>());
    });
  });

  // ---- status -------------------------------------------------------------

  group('status', () {
    test('the stream replays the current value', () async {
      final DriveSyncEngine engine =
          await _connected(db, drive: FakeDriveClient());
      expect(await engine.statusStream.first, isA<SyncIdle>());
      engine.dispose();
    });

    test('a network failure reports offline, not error', () async {
      final FakeDriveClient drive = FakeDriveClient()
        ..failWith = const DriveNetworkException('no route to host');
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      expect(await engine.syncNow(), isFalse);
      expect(engine.status, isA<SyncOffline>());
      expect(await db.getMeta(MetaKeys.lastSyncMs), isNull);
    });

    test('a revoked token asks the user to reconnect', () async {
      final FakeDriveClient drive = FakeDriveClient()
        ..failWith = const DriveException(401, 'authError', 'invalid creds');
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      expect(await engine.syncNow(), isFalse);
      expect(engine.status, isA<SyncError>());
      expect((engine.status as SyncError).message,
          contains('connect Drive again'));
    });

    test('a full Drive is a hard error', () async {
      final FakeDriveClient drive = FakeDriveClient()
        ..failWith =
            const DriveException(403, 'storageQuotaExceeded', 'no space');
      final DriveSyncEngine engine = await _connected(db, drive: drive);
      expect(await engine.syncNow(), isFalse);
      expect((engine.status as SyncError).message, 'Google Drive is full');
    });
  });

  // ---- repositories still mark rows dirty ---------------------------------

  test('mutations mark rows dirty and bump updated_at_ms', () async {
    final Transaction tx =
        await TransactionsRepository(db, now: () => 111).insert(
      kind: Kind.income,
      amountMinor: 5000000,
      categoryId: _salaryId,
    );
    expect(tx.dirty, isTrue);
    expect(tx.updatedAtMs, 111);

    await TransactionsRepository(db, now: () => 222).softDelete(tx.id);
    final Transaction after = await (db.select(db.transactions)
          ..where((t) => t.id.equals(tx.id)))
        .getSingle();
    expect(after.deletedAtMs, 222);
    expect(after.updatedAtMs, 222);
    expect(after.dirty, isTrue);
  });

  test('setLanguage only accepts contract codes', () async {
    final SettingsRepository repo = SettingsRepository(db, now: () => 10);
    await repo.setLanguage('ru');
    expect(await repo.getLanguage(), 'ru');
    await repo.setLanguage('de'); // unsupported -> follow the device locale
    expect(await repo.getLanguage(), '');
    await repo.setCurrency('eur');
    expect(await repo.getCurrency(), 'EUR');
    expect(await repo.getLanguage(), ''); // currency write kept language
  });
}
