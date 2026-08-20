/// Google Drive snapshot sync (docs/ARCHITECTURE.md § Sync algorithm).
///
/// The app and the Go server are equal peers. Each owns exactly one file in
/// the shared `Tally` Drive folder — `tally-<device_id>.json` — and only ever
/// writes that one, so two peers can never conflict on a single file.
/// Convergence comes from every peer reading every other peer's file and
/// merging with strict last-write-wins.
///
/// The public surface is deliberately identical to the old REST engine
/// (`syncNow` / `scheduleSync` / `statusStream` / `lastSyncMsStream` /
/// `isConfigured` / `status` + the SyncStatus classes) so nothing above
/// `lib/data/` had to change for the transport swap.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, SocketException;

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../db/database.dart';
import 'device_auth.dart';
import 'drive_client.dart';
import 'snapshot.dart';

// ---- status ----------------------------------------------------------------

sealed class SyncStatus {
  const SyncStatus();
}

/// No Google account connected — sync is a no-op (standalone mode).
class SyncNotConfigured extends SyncStatus {
  const SyncNotConfigured();
}

/// Connected and quiet; last sync (if any) succeeded.
class SyncIdle extends SyncStatus {
  const SyncIdle();
}

/// A sync pass is in flight.
class SyncSyncing extends SyncStatus {
  const SyncSyncing();
}

/// Last attempt failed at the network level (no connectivity / Drive
/// unreachable). Local data is safe; will retry on the next trigger.
class SyncOffline extends SyncStatus {
  const SyncOffline();
}

/// Machine-readable reasons a sync pass failed, so the UI can translate the
/// status instead of showing the English [SyncError.message] verbatim.
abstract final class SyncErrorCode {
  /// The refresh token was revoked; the user must authorize again.
  static const String authRevoked = 'auth_revoked';

  /// Drive answered 401; the access grant is gone.
  static const String authExpired = 'auth_expired';

  /// Drive answered 403 storageQuotaExceeded.
  static const String driveFull = 'drive_full';

  /// Any other Drive API error — [SyncError.message] carries Google's text.
  static const String drive = 'drive';

  /// Anything unexpected — [SyncError.message] is the raw exception string.
  static const String unknown = 'unknown';
}

/// Last attempt failed for a non-network reason (revoked token, Drive full…).
///
/// [message] stays the English fallback (and what the tests assert on);
/// [code] is what the UI switches on to render a translated line.
class SyncError extends SyncStatus {
  const SyncError(this.message, {this.code = SyncErrorCode.unknown});

  final String message;
  final String code;
}

// ---- connection summary ----------------------------------------------------

/// What the Settings screen shows once a Drive account is connected.
class DriveConnection {
  const DriveConnection({
    required this.folderName,
    required this.folderId,
    required this.deviceId,
    required this.deviceName,
    required this.snapshotFileName,
  });

  final String folderName;

  /// Null until the first successful pass resolved (or created) the folder.
  final String? folderId;
  final String deviceId;
  final String deviceName;

  /// This peer's file inside the folder, e.g. `tally-b2c3….json`.
  final String snapshotFileName;
}

/// This device's stable identity inside the Drive folder.
class DeviceIdentity {
  const DeviceIdentity(this.id, this.name);

  final String id;
  final String name;
}

/// A sensible per-platform default for `device_name`.
String defaultDeviceName() {
  if (Platform.isAndroid) return 'Android phone';
  if (Platform.isIOS) return 'iPhone';
  if (Platform.isMacOS) return 'Mac';
  if (Platform.isWindows) return 'Windows PC';
  if (Platform.isLinux) return 'Linux';
  return 'Tally app';
}

// ---- engine ------------------------------------------------------------------

/// Orchestrates Drive sync between the local Drift DB and the peers' snapshots.
///
/// Triggers: [syncNow] (launch / resume / pull-to-refresh / manual button) and
/// [scheduleSync] (3 s debounce, called by repositories after every write).
/// Both are no-ops until a Google account is connected.
class DriveSyncEngine {
  DriveSyncEngine(
    this._db, {
    DeviceAuthClient? auth,
    DriveClientFactory? driveClientFactory,
    this._folderName = driveFolderName,
    this._debounce = const Duration(seconds: 3),
    int Function()? now,
    String Function()? newId,
    String Function()? deviceName,
  })  : _auth = auth ?? DeviceAuthClient(),
        _driveClientFactory =
            driveClientFactory ?? GoogleDriveClient.withAccessToken,
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
        _newId = newId ?? (() => const Uuid().v4()),
        _deviceName = deviceName ?? defaultDeviceName;

  final AppDatabase _db;
  final DeviceAuthClient _auth;
  final DriveClientFactory _driveClientFactory;
  final String _folderName;
  final Duration _debounce;
  final int Function() _now;
  final String Function() _newId;
  final String Function() _deviceName;

  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncNotConfigured();
  Timer? _debounceTimer;

  /// Completes with the result of the pass (or the queued follow-up pass)
  /// currently in flight; null when nothing is running. Coalescing callers
  /// await it instead of being told `false`.
  Completer<bool>? _inFlight;
  bool _runAgain = false;
  bool _authCancelled = false;
  int? _lastSyncMs;
  Future<void>? _initFuture;

  /// Current status (sync value; see [statusStream] for updates).
  SyncStatus get status => _status;

  /// Broadcast stream that immediately replays the current status to every
  /// new listener, then emits every change.
  Stream<SyncStatus> get statusStream async* {
    yield _status;
    yield* _statusController.stream;
  }

  /// Unix-ms of the last successful sync, or null if never synced.
  int? get lastSyncMs => _lastSyncMs;

  /// Reactive last-successful-sync timestamp (backed by the meta table).
  Stream<int?> get lastSyncMsStream => _db
      .watchMeta(MetaKeys.lastSyncMs)
      .map((String? v) => v == null ? null : int.tryParse(v));

  /// True once a Google account is connected (a refresh token is stored).
  bool get isConfigured => _status is! SyncNotConfigured;

  /// False when the build carries no OAuth client — the UI must then explain
  /// that this build cannot connect to Drive instead of offering the button.
  bool get canAuthorize => _auth.isAvailable;

  void _setStatus(SyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Loads the stored token + last sync time and sets the initial status.
  /// Memoized: safe to call any number of times; every sync trigger awaits it
  /// so a cold-start [syncNow] can never race the lazy meta load.
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    final String? token = await _db.getMeta(MetaKeys.googleRefreshToken);
    final String? last = await _db.getMeta(MetaKeys.lastSyncMs);
    _lastSyncMs = last == null ? null : int.tryParse(last);
    _setStatus(token != null && token.isNotEmpty
        ? const SyncIdle()
        : const SyncNotConfigured());
  }

  // ---- authorization ------------------------------------------------------

  /// Step 1 of the device flow: asks Google for a user code.
  ///
  /// The returned [DeviceAuthPrompt] carries the verification URL and the
  /// short code the UI must display; hand the same object straight back to
  /// [completeAuthorization].
  ///
  /// Throws [DeviceAuthException] (network, or `client_not_configured`).
  Future<DeviceAuthPrompt> beginAuthorization() async {
    await init();
    _authCancelled = false;
    return _auth.requestCode();
  }

  /// Steps 3–5: polls until the user approves at the verification URL, stores
  /// the refresh token, then runs a first sync.
  ///
  /// Connecting a DIFFERENT Google account (a refresh token that is not the
  /// one already stored) resets the sync state first: the cached folder id and
  /// peer md5 map are dropped and every local row is re-marked dirty so the
  /// new account gets a full snapshot. `updated_at_ms` is deliberately NOT
  /// bumped — the peers' LWW merge then decides fairly.
  ///
  /// Throws [DeviceAuthException] on denial, expiry, cancellation or network
  /// failure. [onAttempt] fires once per poll for live progress.
  Future<void> completeAuthorization(
    DeviceAuthPrompt prompt, {
    void Function(int attempt)? onAttempt,
  }) async {
    await init();
    final DeviceTokens tokens = await _auth.pollForTokens(
      prompt,
      isCancelled: () => _authCancelled,
      onAttempt: onAttempt,
    );
    final String? refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const DeviceAuthException(
        'invalid_response',
        'Google did not return a refresh token — check that the OAuth client '
            'is of type "TVs and Limited Input devices".',
      );
    }

    final String? previous = await _db.getMeta(MetaKeys.googleRefreshToken);
    if (previous != null && previous.isNotEmpty && previous != refreshToken) {
      await _resetSyncState(dropFolderId: true);
    }
    await _db.setMeta(MetaKeys.googleRefreshToken, refreshToken);
    await _ensureDevice();
    _setStatus(const SyncIdle());
    await syncNow();
  }

  /// Aborts an in-flight [completeAuthorization] poll.
  void cancelAuthorization() => _authCancelled = true;

  /// Summary for the Settings screen, or null in standalone mode.
  Future<DriveConnection?> connectionInfo() async {
    await init();
    final String? token = await _db.getMeta(MetaKeys.googleRefreshToken);
    if (token == null || token.isEmpty) return null;
    final DeviceIdentity device = await _ensureDevice();
    return DriveConnection(
      folderName: _folderName,
      folderId: await _db.getMeta(MetaKeys.driveFolderId),
      deviceId: device.id,
      deviceName: device.name,
      snapshotFileName: snapshotFileName(device.id),
    );
  }

  /// Disconnects the Google account: best-effort token revocation, then
  /// [clearConfiguration]. The app returns to standalone mode with all local
  /// data intact.
  Future<void> disconnect() async {
    final String? token = await _db.getMeta(MetaKeys.googleRefreshToken);
    if (token != null && token.isNotEmpty) {
      await _auth.revoke(token);
    }
    await clearConfiguration();
  }

  /// Drops the Drive configuration without touching the network: refresh
  /// token, cached folder id, peer md5 cache and last-sync timestamp all go.
  /// `device_id` / `device_name` survive — this device keeps its identity.
  Future<void> clearConfiguration() async {
    await _db.deleteMeta(MetaKeys.googleRefreshToken);
    await _db.deleteMeta(MetaKeys.driveFolderId);
    await _db.deleteMeta(MetaKeys.drivePeerMd5);
    await _db.deleteMeta(MetaKeys.lastSyncMs);
    _lastSyncMs = null;
    _setStatus(const SyncNotConfigured());
  }

  // ---- triggers -----------------------------------------------------------

  /// Debounced sync trigger — call after every local write.
  ///
  /// No configuration guard here: [syncNow] awaits [init] and decides, so a
  /// write that lands before the initial meta load still syncs.
  void scheduleSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      unawaited(syncNow());
    });
  }

  /// Runs one full sync pass now. Returns true on success.
  ///
  /// No-op (false) when not configured. Concurrent calls coalesce: a call
  /// while a pass is in flight queues exactly one follow-up run and then
  /// awaits **that** run's result, so a caller never sees `false` for work
  /// that is merely queued (the manual "Sync now" button would otherwise
  /// report a failure whenever the 3 s post-write debounce beat it to it).
  /// Awaits [init] first so the app-start trigger works even when it fires
  /// before the initial (lazy) meta load has finished.
  Future<bool> syncNow() async {
    await init();
    if (!isConfigured) return false;
    final Completer<bool>? inFlight = _inFlight;
    if (inFlight != null) {
      _runAgain = true;
      return inFlight.future;
    }
    final Completer<bool> completer = Completer<bool>();
    _inFlight = completer;
    bool ok = false;
    try {
      ok = await _syncOnce();
      while (_runAgain) {
        _runAgain = false;
        ok = await _syncOnce();
      }
    } finally {
      _runAgain = false;
      _inFlight = null;
      completer.complete(ok);
    }
    return ok;
  }

  void dispose() {
    _debounceTimer?.cancel();
    _statusController.close();
    _auth.close();
  }

  // ---- the 8-step pass ----------------------------------------------------

  Future<bool> _syncOnce() async {
    // 1. Ensure auth.
    final String? refreshToken = await _db.getMeta(MetaKeys.googleRefreshToken);
    if (refreshToken == null || refreshToken.isEmpty) {
      _setStatus(const SyncNotConfigured());
      return false;
    }
    _setStatus(const SyncSyncing());

    DriveClient? client;
    try {
      final DeviceIdentity device = await _ensureDevice();
      final DeviceTokens tokens = await _auth.refreshAccessToken(refreshToken);
      final String? rotated = tokens.refreshToken;
      if (rotated != null && rotated.isNotEmpty && rotated != refreshToken) {
        // Refresh tokens rotate; persist the new one immediately.
        await _db.setMeta(MetaKeys.googleRefreshToken, rotated);
      }
      client = _driveClientFactory(tokens.accessToken);

      // 2 + 3. Resolve the folder (cached, re-resolved on 404) and list it.
      final (String folderId, List<DriveFileMeta> files) =
          await _resolveAndList(client);

      // 4. Download every peer file except our own, skipping unchanged md5s.
      final String selfName = snapshotFileName(device.id);
      final Map<String, String> knownMd5 = await _readMd5Cache();
      final Map<String, String> nextMd5 = <String, String>{};
      final List<TallySnapshot> incoming = <TallySnapshot>[];
      DriveFileMeta? selfFile;

      for (final DriveFileMeta f in files) {
        if (f.name == selfName) {
          selfFile = f;
          continue;
        }
        final String? md5 = f.md5Checksum;
        if (md5 != null && knownMd5[f.id] == md5) {
          nextMd5[f.id] = md5; // unchanged since last merge — skip download
          continue;
        }
        final List<int> bytes = await client.download(f.id);
        try {
          incoming.add(TallySnapshot.decode(bytes));
          if (md5 != null) nextMd5[f.id] = md5;
        } on SnapshotFormatException {
          // Corrupt or future-schema peer: skip it and do NOT cache its md5,
          // so a later fixed version is picked up.
        }
      }

      // 5. Merge everything atomically with strict LWW.
      if (incoming.isNotEmpty) await _merge(incoming);

      // 6. Publish our own snapshot when anything local is dirty, or when we
      //    have never uploaded it.
      final _LocalState local = await _readLocalState();
      final bool needsPublish = local.hasDirty || selfFile == null;
      if (needsPublish) {
        final TallySnapshot snapshot = TallySnapshot(
          deviceId: device.id,
          deviceName: device.name,
          writtenAtMs: _now(),
          categories: local.categories,
          transactions: local.transactions,
          settings: local.settings,
        );
        final bytes = snapshot.encode();
        if (selfFile == null) {
          await client.create(
            folderId: folderId,
            name: selfName,
            bytes: bytes,
          );
        } else {
          await client.update(fileId: selfFile.id, bytes: bytes);
        }

        // 7. Clear dirty ONLY on rows whose updated_at_ms is unchanged since
        //    the snapshot was serialized (rows edited mid-sync stay dirty).
        await _clearDirty(local);
      }

      // 8. Persist the per-file md5 map and the last-success timestamp.
      await _writeMd5Cache(nextMd5);
      final int nowMs = _now();
      await _db.setMeta(MetaKeys.lastSyncMs, nowMs.toString());
      _lastSyncMs = nowMs;

      _setStatus(const SyncIdle());
      return true;
    } on DriveException catch (e) {
      _setStatus(SyncError(_driveMessage(e), code: _driveCode(e)));
      return false;
    } on DriveNetworkException {
      _setStatus(const SyncOffline());
      return false;
    } on DeviceAuthException catch (e) {
      if (e.code == 'network') {
        _setStatus(const SyncOffline());
      } else if (e.needsReauthorization) {
        _setStatus(const SyncError(
          'Google access was revoked — connect Drive again',
          code: SyncErrorCode.authRevoked,
        ));
      } else {
        _setStatus(SyncError(e.message));
      }
      return false;
    } on TimeoutException {
      _setStatus(const SyncOffline());
      return false;
    } on SocketException {
      _setStatus(const SyncOffline());
      return false;
    } on http.ClientException {
      _setStatus(const SyncOffline());
      return false;
    } catch (e) {
      _setStatus(SyncError(e.toString()));
      return false;
    } finally {
      client?.close();
    }
  }

  /// English fallback text for [SyncError.message]. For the generic case it is
  /// Google's own message *without* a prefix, so the UI can wrap it in a
  /// translated "Drive error: …" frame without doubling it up.
  String _driveMessage(DriveException e) {
    if (e.isAuthError) return 'Google access expired — connect Drive again';
    if (e.isQuotaExceeded) return 'Google Drive is full';
    return e.message;
  }

  String _driveCode(DriveException e) {
    if (e.isAuthError) return SyncErrorCode.authExpired;
    if (e.isQuotaExceeded) return SyncErrorCode.driveFull;
    return SyncErrorCode.drive;
  }

  /// Steps 2 + 3. Uses the cached folder id when there is one, re-resolves by
  /// name when that id is dead, and — when the resolved folder differs from
  /// the cached one (a different Drive account, or a deleted-and-recreated
  /// folder) — resets the sync state so the new folder gets a full snapshot.
  ///
  /// Liveness is checked with an explicit `files.get` ([DriveClient.folderExists])
  /// and NOT inferred from the listing: Drive answers a `'<id>' in parents`
  /// query for a trashed, deleted or foreign parent with HTTP 200 and an empty
  /// `files` array, never a 404. Trusting the listing would leave this peer
  /// writing into a dead folder forever while the Go peer, whose folder query
  /// filters `trashed = false`, mints a fresh `Tally` folder — both reporting
  /// "Connected" while syncing to different places.
  Future<(String, List<DriveFileMeta>)> _resolveAndList(
      DriveClient client) async {
    final String? cached = await _db.getMeta(MetaKeys.driveFolderId);
    if (cached != null && cached.isNotEmpty) {
      if (await client.folderExists(cached)) {
        try {
          return (cached, await client.listSnapshots(cached));
        } on DriveException catch (e) {
          if (!e.isNotFound) rethrow;
        }
      }
    }
    final String resolved = await client.findOrCreateFolder(_folderName);
    if (cached != null && cached.isNotEmpty && cached != resolved) {
      await _resetSyncState();
    }
    await _db.setMeta(MetaKeys.driveFolderId, resolved);
    return (resolved, await client.listSnapshots(resolved));
  }

  /// Step 5 — strict last-write-wins: an incoming row is applied iff it does
  /// not exist locally OR `incoming.updated_at_ms > local.updated_at_ms`.
  /// Ties keep the local row. Merged rows land with `dirty = false`.
  Future<void> _merge(List<TallySnapshot> snapshots) async {
    await _db.transaction(() async {
      for (final TallySnapshot s in snapshots) {
        for (final Category incoming in s.categories) {
          final Category? existing = await (_db.select(_db.categories)
                ..where((c) => c.id.equals(incoming.id)))
              .getSingleOrNull();
          if (existing == null || incoming.updatedAtMs > existing.updatedAtMs) {
            await _db.into(_db.categories).insertOnConflictUpdate(incoming);
          }
        }
        for (final Transaction incoming in s.transactions) {
          final Transaction? existing = await (_db.select(_db.transactions)
                ..where((t) => t.id.equals(incoming.id)))
              .getSingleOrNull();
          if (existing == null || incoming.updatedAtMs > existing.updatedAtMs) {
            await _db.into(_db.transactions).insertOnConflictUpdate(incoming);
          }
        }
        final SettingsRow? incomingSettings = s.settings;
        if (incomingSettings != null) {
          final SettingsRow? existing = await (_db.select(_db.settings)
                ..where((r) => r.id.equals(incomingSettings.id)))
              .getSingleOrNull();
          if (existing == null ||
              incomingSettings.updatedAtMs > existing.updatedAtMs) {
            await _db
                .into(_db.settings)
                .insertOnConflictUpdate(incomingSettings);
          }
        }
      }
    });
  }

  Future<_LocalState> _readLocalState() async {
    final List<Category> categories = await _db.select(_db.categories).get();
    final List<Transaction> transactions =
        await _db.select(_db.transactions).get();
    final SettingsRow? settings = await (_db.select(_db.settings)
          ..where((r) => r.id.equals(settingsRowId)))
        .getSingleOrNull();
    return _LocalState(categories, transactions, settings);
  }

  /// Step 7 — clears `dirty` on exactly the rows that were serialized, and
  /// only while their `updated_at_ms` still matches.
  Future<void> _clearDirty(_LocalState local) async {
    await _db.transaction(() async {
      for (final Category c in local.categories) {
        if (!c.dirty) continue;
        await (_db.update(_db.categories)
              ..where((r) =>
                  r.id.equals(c.id) & r.updatedAtMs.equals(c.updatedAtMs)))
            .write(const CategoriesCompanion(dirty: Value(false)));
      }
      for (final Transaction t in local.transactions) {
        if (!t.dirty) continue;
        await (_db.update(_db.transactions)
              ..where((r) =>
                  r.id.equals(t.id) & r.updatedAtMs.equals(t.updatedAtMs)))
            .write(const TransactionsCompanion(dirty: Value(false)));
      }
      final SettingsRow? s = local.settings;
      if (s != null && s.dirty) {
        await (_db.update(_db.settings)
              ..where((r) =>
                  r.id.equals(s.id) & r.updatedAtMs.equals(s.updatedAtMs)))
            .write(const SettingsCompanion(dirty: Value(false)));
      }
    });
  }

  /// Forgets everything learned about the previous Drive folder and re-marks
  /// every row dirty. `updated_at_ms` is deliberately NOT bumped: the rows are
  /// republished as-is and the peers' LWW merge decides fairly.
  Future<void> _resetSyncState({bool dropFolderId = false}) async {
    await _db.transaction(() async {
      if (dropFolderId) await _db.deleteMeta(MetaKeys.driveFolderId);
      await _db.deleteMeta(MetaKeys.drivePeerMd5);
      await _db.deleteMeta(MetaKeys.lastSyncMs);
      await _db
          .update(_db.categories)
          .write(const CategoriesCompanion(dirty: Value(true)));
      await _db
          .update(_db.transactions)
          .write(const TransactionsCompanion(dirty: Value(true)));
      await _db
          .update(_db.settings)
          .write(const SettingsCompanion(dirty: Value(true)));
    });
    _lastSyncMs = null;
  }

  // ---- meta helpers -------------------------------------------------------

  /// Reads (or lazily creates) this device's id and name.
  Future<DeviceIdentity> _ensureDevice() async {
    String? id = await _db.getMeta(MetaKeys.deviceId);
    if (id == null || id.isEmpty) {
      id = _newId();
      await _db.setMeta(MetaKeys.deviceId, id);
    }
    String? name = await _db.getMeta(MetaKeys.deviceName);
    if (name == null || name.isEmpty) {
      name = _deviceName();
      await _db.setMeta(MetaKeys.deviceName, name);
    }
    return DeviceIdentity(id, name);
  }

  Future<Map<String, String>> _readMd5Cache() async {
    final String? raw = await _db.getMeta(MetaKeys.drivePeerMd5);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return <String, String>{
        for (final MapEntry<Object?, Object?> e in decoded.entries)
          if (e.key is String && e.value is String)
            e.key! as String: e.value! as String,
      };
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _writeMd5Cache(Map<String, String> md5s) =>
      _db.setMeta(MetaKeys.drivePeerMd5, jsonEncode(md5s));
}

class _LocalState {
  const _LocalState(this.categories, this.transactions, this.settings);

  final List<Category> categories;
  final List<Transaction> transactions;
  final SettingsRow? settings;

  bool get hasDirty =>
      categories.any((Category c) => c.dirty) ||
      transactions.any((Transaction t) => t.dirty) ||
      (settings?.dirty ?? false);
}
