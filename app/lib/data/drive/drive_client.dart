/// Drive v3 access for the snapshot sync, behind a small interface the tests
/// can fake.
///
/// Only the five operations the protocol needs: find-or-create the `Tally`
/// folder, list `tally-*.json`, download bytes, create, update-content-by-id.
/// Everything is scoped to `drive.file`.
library;

import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:math';
import 'dart:typed_data';

import 'package:async/async.dart' show collectBytes;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;

import '../../core/constants.dart';

const String _folderMime = 'application/vnd.google-apps.folder';

/// Metadata for one file in the Drive folder — exactly the
/// `files(id,name,modifiedTime,md5Checksum)` projection the protocol asks for.
class DriveFileMeta {
  const DriveFileMeta({
    required this.id,
    required this.name,
    this.modifiedTime,
    this.md5Checksum,
  });

  final String id;
  final String name;
  final DateTime? modifiedTime;

  /// Drive's MD5 over the stored bytes. Used purely to skip re-downloading a
  /// peer whose file has not changed; never for ordering (see ARCHITECTURE:
  /// LWW is decided by the in-payload `updated_at_ms`).
  final String? md5Checksum;

  @override
  String toString() => 'DriveFileMeta($name, $id, md5=$md5Checksum)';
}

/// A non-2xx response from Drive, already classified.
class DriveException implements Exception {
  const DriveException(this.status, this.reason, this.message);

  final int? status;

  /// Drive's machine-readable reason (`storageQuotaExceeded`,
  /// `rateLimitExceeded`, …) when the body carried one.
  final String? reason;
  final String message;

  /// Refresh token revoked / access token dead — surface to the user as
  /// "reconnect", not as a transient failure.
  bool get isAuthError => status == 401;

  /// The cached file or folder id is gone; re-resolve and retry.
  bool get isNotFound => status == 404;

  /// Drive is full (or a service account tried to own a file). Fatal.
  bool get isQuotaExceeded => reason == 'storageQuotaExceeded';

  bool get isRetryable {
    final int? s = status;
    if (s == 429) return true;
    if (s != null && s >= 500 && s < 600) return true;
    return s == 403 &&
        (reason == 'rateLimitExceeded' || reason == 'userRateLimitExceeded');
  }

  @override
  String toString() =>
      'DriveException(${status ?? '?'}${reason == null ? '' : '/$reason'}): '
      '$message';
}

/// No route to Drive: offline, DNS failure, TLS reset, timeout.
class DriveNetworkException implements Exception {
  const DriveNetworkException(this.message);

  final String message;

  @override
  String toString() => 'DriveNetworkException: $message';
}

/// The Drive operations the sync engine needs.
abstract class DriveClient {
  /// Finds the folder named [name] in the account root, creating it if absent.
  Future<String> findOrCreateFolder(String name);

  /// True when [folderId] still points at a live folder.
  ///
  /// False when Drive answers 404 (deleted / never ours) **or** reports
  /// `trashed: true` — in both cases the cached id is dead and must be
  /// re-resolved. Every other failure propagates.
  ///
  /// This exists because folder liveness cannot be inferred from
  /// [listSnapshots]: `files.list` with a `'<id>' in parents` query answers
  /// HTTP 200 with an empty `files` array for a dead parent, so a trashed
  /// `Tally` folder would otherwise look exactly like an empty live one and
  /// the app would keep writing into it forever.
  Future<bool> folderExists(String folderId);

  /// Lists snapshot files in [folderId], newest metadata first is irrelevant —
  /// order is not significant. Requests only id/name/modifiedTime/md5Checksum.
  Future<List<DriveFileMeta>> listSnapshots(
    String folderId, {
    String namePrefix = snapshotNamePrefix,
  });

  /// Downloads a file's raw bytes.
  Future<Uint8List> download(String fileId);

  /// Creates a new JSON file with content.
  Future<DriveFileMeta> create({
    required String folderId,
    required String name,
    required Uint8List bytes,
  });

  /// Replaces an existing file's content by id.
  Future<DriveFileMeta> update({
    required String fileId,
    required Uint8List bytes,
  });

  /// Releases the underlying HTTP client.
  void close();
}

/// Builds a [DriveClient] for a freshly minted access token. Swapped out in
/// tests for a fake that never touches the network.
typedef DriveClientFactory = DriveClient Function(String accessToken);

/// The real thing: `googleapis` Drive v3 over a `googleapis_auth`
/// authenticated client, with transient-error retry baked in.
///
/// 401 is deliberately *not* retried here — the engine owns the refresh token
/// and re-runs the pass with a new access token.
class GoogleDriveClient implements DriveClient {
  GoogleDriveClient(
    this._api, {
    this._onClose,
    this._maxAttempts = 5,
    this._baseBackoff = const Duration(milliseconds: 500),
    this._backoffCap = const Duration(seconds: 32),
    this._timeout = const Duration(seconds: 30),
    Future<void> Function(Duration)? sleep,
    Random? random,
  })  : _sleep = sleep ?? Future<void>.delayed,
        _random = random ?? Random();

  /// Wraps a bearer access token in an authenticated client
  /// (`googleapis_auth.authenticatedClient`). The token's real lifetime is
  /// irrelevant: the engine mints a fresh one for every pass and rebuilds
  /// the client on 401.
  factory GoogleDriveClient.withAccessToken(
    String accessToken, {
    http.Client? baseClient,
    DateTime? expiresAt,
  }) {
    final http.Client inner = baseClient ?? http.Client();
    final auth.AccessCredentials credentials = auth.AccessCredentials(
      auth.AccessToken(
        'Bearer',
        accessToken,
        (expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)))
            .toUtc(),
      ),
      null,
      const <String>[DriveOAuth.scope],
    );
    final auth.AuthClient client =
        auth.authenticatedClient(inner, credentials, closeUnderlyingClient: false);
    return GoogleDriveClient(
      drive.DriveApi(client),
      onClose: () {
        client.close();
        inner.close();
      },
    );
  }

  final drive.DriveApi _api;
  final void Function()? _onClose;
  final int _maxAttempts;
  final Duration _baseBackoff;
  final Duration _backoffCap;
  final Duration _timeout;
  final Future<void> Function(Duration) _sleep;
  final Random _random;

  /// Drive query escaping: backslash first, then apostrophe.
  static String escapeQuery(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  @override
  Future<String> findOrCreateFolder(String name) async {
    final drive.FileList found = await _run(() => _api.files.list(
          q: "name = '${escapeQuery(name)}' "
              "and mimeType = '$_folderMime' "
              'and trashed = false '
              "and 'root' in parents",
          spaces: 'drive',
          pageSize: 10,
          $fields: 'files(id,name)',
        ));
    final List<drive.File> hits = found.files ?? const <drive.File>[];
    for (final drive.File f in hits) {
      if (f.id != null) return f.id!;
    }
    final drive.File created = await _run(() => _api.files.create(
          drive.File()
            ..name = name
            ..mimeType = _folderMime
            ..parents = <String>['root'],
          $fields: 'id',
        ));
    final String? id = created.id;
    if (id == null) {
      throw const DriveException(null, null, 'Drive created a folder with no id');
    }
    return id;
  }

  @override
  Future<bool> folderExists(String folderId) async {
    try {
      final Object result =
          await _run(() => _api.files.get(folderId, $fields: 'id,trashed'));
      if (result is! drive.File) return false;
      return result.trashed != true;
    } on DriveException catch (e) {
      if (e.isNotFound) return false;
      rethrow;
    }
  }

  @override
  Future<List<DriveFileMeta>> listSnapshots(
    String folderId, {
    String namePrefix = snapshotNamePrefix,
  }) async {
    final List<DriveFileMeta> out = <DriveFileMeta>[];
    String? pageToken;
    do {
      final drive.FileList page = await _run(() => _api.files.list(
            q: "'${escapeQuery(folderId)}' in parents "
                "and name contains '${escapeQuery(namePrefix)}' "
                'and trashed = false',
            spaces: 'drive',
            orderBy: 'name',
            pageSize: 100,
            pageToken: pageToken,
            $fields: 'nextPageToken,files(id,name,modifiedTime,md5Checksum)',
          ));
      for (final drive.File f in page.files ?? const <drive.File>[]) {
        final String? id = f.id;
        final String? name = f.name;
        if (id == null || name == null) continue;
        if (!name.startsWith(namePrefix)) continue;
        out.add(DriveFileMeta(
          id: id,
          name: name,
          modifiedTime: f.modifiedTime,
          md5Checksum: f.md5Checksum,
        ));
      }
      pageToken = page.nextPageToken;
    } while (pageToken != null);
    return out;
  }

  @override
  Future<Uint8List> download(String fileId) async {
    return _run(() async {
      final Object result = await _api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      if (result is! drive.Media) {
        throw const DriveException(
            null, null, 'Drive returned metadata instead of file bytes');
      }
      return collectBytes(result.stream);
    });
  }

  @override
  Future<DriveFileMeta> create({
    required String folderId,
    required String name,
    required Uint8List bytes,
  }) async {
    final drive.File created = await _run(() => _api.files.create(
          drive.File()
            ..name = name
            ..mimeType = snapshotMimeType
            ..parents = <String>[folderId],
          uploadMedia: _media(bytes),
          $fields: 'id,name,modifiedTime,md5Checksum',
        ));
    return _metaOf(created, fallbackName: name);
  }

  @override
  Future<DriveFileMeta> update({
    required String fileId,
    required Uint8List bytes,
  }) async {
    final drive.File updated = await _run(() => _api.files.update(
          drive.File()..mimeType = snapshotMimeType,
          fileId,
          uploadMedia: _media(bytes),
          $fields: 'id,name,modifiedTime,md5Checksum',
        ));
    return _metaOf(updated, fallbackId: fileId);
  }

  @override
  void close() => _onClose?.call();

  // ---- internals ----------------------------------------------------------

  drive.Media _media(Uint8List bytes) => drive.Media(
        Stream<List<int>>.value(bytes),
        bytes.length,
        contentType: snapshotMimeType,
      );

  DriveFileMeta _metaOf(
    drive.File f, {
    String? fallbackId,
    String? fallbackName,
  }) =>
      DriveFileMeta(
        id: f.id ?? fallbackId ?? '',
        name: f.name ?? fallbackName ?? '',
        modifiedTime: f.modifiedTime,
        md5Checksum: f.md5Checksum,
      );

  /// Runs [op], translating Drive/HTTP failures into [DriveException] /
  /// [DriveNetworkException] and retrying the transient ones with full-jitter
  /// exponential backoff (capped at [_backoffCap]).
  Future<T> _run<T>(Future<T> Function() op) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await op().timeout(_timeout);
      } on drive.DetailedApiRequestError catch (e) {
        final DriveException mapped =
            DriveException(e.status, _reasonOf(e), e.message ?? 'Drive error');
        if (!mapped.isRetryable || attempt >= _maxAttempts) throw mapped;
        await _sleep(_backoff(attempt));
      } on DriveException {
        rethrow;
      } on TimeoutException {
        if (attempt >= _maxAttempts) {
          throw const DriveNetworkException('Drive request timed out');
        }
        await _sleep(_backoff(attempt));
      } on SocketException catch (e) {
        if (attempt >= _maxAttempts) {
          throw DriveNetworkException(e.message);
        }
        await _sleep(_backoff(attempt));
      } on http.ClientException catch (e) {
        if (attempt >= _maxAttempts) {
          throw DriveNetworkException(e.message);
        }
        await _sleep(_backoff(attempt));
      }
    }
  }

  Duration _backoff(int attempt) {
    final int expMs = _baseBackoff.inMilliseconds * (1 << (attempt - 1));
    final int cappedMs = expMs.clamp(1, _backoffCap.inMilliseconds);
    return Duration(milliseconds: _random.nextInt(cappedMs) + 1);
  }

  static String? _reasonOf(drive.DetailedApiRequestError e) {
    final Object? error = e.jsonResponse?['error'];
    if (error is Map && error['errors'] is List) {
      final List<Object?> list = error['errors'] as List<Object?>;
      if (list.isNotEmpty && list.first is Map) {
        return (list.first as Map)['reason'] as String?;
      }
    }
    return null;
  }
}
