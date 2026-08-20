/// In-memory fakes for the Drive sync tests: a Drive folder that never
/// touches the network, and a device-auth client that hands out canned tokens.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tally/data/drive/device_auth.dart';
import 'package:tally/data/drive/drive_client.dart';

/// One file inside [FakeDriveClient].
class FakeDriveFile {
  FakeDriveFile({
    required this.id,
    required this.name,
    required this.parentId,
    required this.bytes,
  });

  final String id;
  final String name;
  final String parentId;
  Uint8List bytes;

  /// Drive reports MD5 over the stored bytes; so does the fake.
  String get md5 => crypto.md5.convert(bytes).toString();

  String get text => utf8.decode(bytes);
}

/// A Drive folder in memory. Records every call so tests can assert on
/// downloads skipped, files created vs updated, etc.
class FakeDriveClient implements DriveClient {
  FakeDriveClient({this.accountLabel = 'A'});

  /// Distinguishes two "accounts" — folder ids are prefixed with it.
  final String accountLabel;

  final Map<String, String> folderIdsByName = <String, String>{};
  final Map<String, FakeDriveFile> filesById = <String, FakeDriveFile>{};

  /// Folders the user moved to the Drive trash. They keep their id (so
  /// `files.get` can still answer `trashed: true`) but disappear from every
  /// `trashed = false` query — exactly like the real API.
  final Set<String> trashedFolderIds = <String>{};

  final List<String> downloadedIds = <String>[];
  final List<String> listedFolderIds = <String>[];
  final List<String> checkedFolderIds = <String>[];
  final List<String> createdNames = <String>[];
  final List<String> updatedIds = <String>[];
  int closes = 0;
  int _seq = 0;

  /// When set, thrown by every operation — used to simulate an offline pass.
  Object? failWith;

  /// Fired just before an update/create writes, so a test can mutate the DB
  /// "while the upload is in flight".
  Future<void> Function()? onBeforeUpload;

  /// Drops a peer's snapshot straight into the folder.
  FakeDriveFile putPeerFile({
    required String folderId,
    required String name,
    required List<int> bytes,
  }) {
    final FakeDriveFile f = FakeDriveFile(
      id: '$accountLabel-file-${++_seq}',
      name: name,
      parentId: folderId,
      bytes: Uint8List.fromList(bytes),
    );
    filesById[f.id] = f;
    return f;
  }

  FakeDriveFile? fileNamed(String name, {String? inFolder}) {
    for (final FakeDriveFile f in filesById.values) {
      if (f.name != name) continue;
      if (inFolder != null && f.parentId != inFolder) continue;
      return f;
    }
    return null;
  }

  /// Moves a folder to the trash, the way the user would in the Drive UI.
  ///
  /// The id keeps resolving (so [folderExists] can report `trashed: true`),
  /// but the folder is invisible to the `trashed = false` name query and its
  /// children are hidden from every listing.
  void trashFolder(String folderId) {
    trashedFolderIds.add(folderId);
    folderIdsByName.removeWhere((_, String id) => id == folderId);
  }

  bool _folderIsLive(String folderId) =>
      folderIdsByName.containsValue(folderId) &&
      !trashedFolderIds.contains(folderId);

  void _maybeFail() {
    final Object? f = failWith;
    if (f != null) throw f;
  }

  @override
  Future<String> findOrCreateFolder(String name) async {
    _maybeFail();
    return folderIdsByName.putIfAbsent(
        name, () => '$accountLabel-folder-${++_seq}');
  }

  @override
  Future<bool> folderExists(String folderId) async {
    _maybeFail();
    checkedFolderIds.add(folderId);
    return _folderIsLive(folderId);
  }

  @override
  Future<List<DriveFileMeta>> listSnapshots(
    String folderId, {
    String namePrefix = 'tally-',
  }) async {
    _maybeFail();
    listedFolderIds.add(folderId);
    // Same as the real client: `files.list` NEVER 404s on a dead parent. A
    // trashed, deleted or foreign folder id simply matches nothing, because
    // the query filters `trashed = false` and a trashed folder's children are
    // trashed with it.
    if (!_folderIsLive(folderId)) return const <DriveFileMeta>[];
    return <DriveFileMeta>[
      for (final FakeDriveFile f in filesById.values)
        if (f.parentId == folderId && f.name.startsWith(namePrefix))
          DriveFileMeta(
            id: f.id,
            name: f.name,
            modifiedTime: DateTime.utc(2026, 8, 19),
            md5Checksum: f.md5,
          ),
    ];
  }

  @override
  Future<Uint8List> download(String fileId) async {
    _maybeFail();
    downloadedIds.add(fileId);
    final FakeDriveFile? f = filesById[fileId];
    if (f == null) {
      throw const DriveException(404, 'notFound', 'no such file');
    }
    return f.bytes;
  }

  @override
  Future<DriveFileMeta> create({
    required String folderId,
    required String name,
    required Uint8List bytes,
  }) async {
    _maybeFail();
    await onBeforeUpload?.call();
    createdNames.add(name);
    final FakeDriveFile f =
        putPeerFile(folderId: folderId, name: name, bytes: bytes);
    return DriveFileMeta(id: f.id, name: f.name, md5Checksum: f.md5);
  }

  @override
  Future<DriveFileMeta> update({
    required String fileId,
    required Uint8List bytes,
  }) async {
    _maybeFail();
    await onBeforeUpload?.call();
    updatedIds.add(fileId);
    final FakeDriveFile f = filesById[fileId]!;
    f.bytes = Uint8List.fromList(bytes);
    return DriveFileMeta(id: f.id, name: f.name, md5Checksum: f.md5);
  }

  @override
  void close() => closes++;
}

/// Device-auth client that never talks to Google.
class FakeDeviceAuth extends DeviceAuthClient {
  FakeDeviceAuth({
    this.accessToken = 'access-token',
    this.grantedRefreshToken = 'refresh-A',
    this.rotatedRefreshToken,
  }) : super(
          httpClient: MockClient(
              (http.Request _) async => http.Response('{}', 200)),
          clientId: 'test-client-id',
          clientSecret: 'test-client-secret',
        );

  final String accessToken;

  /// Handed back by [pollForTokens] — i.e. "the account you just connected".
  String grantedRefreshToken;

  /// When non-null, [refreshAccessToken] reports a rotated refresh token.
  String? rotatedRefreshToken;

  final List<String> refreshedWith = <String>[];
  final List<String> revoked = <String>[];
  int codeRequests = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<DeviceAuthPrompt> requestCode() async {
    codeRequests++;
    return DeviceAuthPrompt(
      deviceCode: 'device-code',
      userCode: 'ABCD-EFGH',
      verificationUrl: 'https://www.google.com/device',
      interval: const Duration(seconds: 5),
      expiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<DeviceTokens> pollForTokens(
    DeviceAuthPrompt prompt, {
    bool Function()? isCancelled,
    void Function(int attempt)? onAttempt,
  }) async {
    onAttempt?.call(1);
    return DeviceTokens(
      accessToken: accessToken,
      refreshToken: grantedRefreshToken,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<DeviceTokens> refreshAccessToken(String refreshToken) async {
    refreshedWith.add(refreshToken);
    return DeviceTokens(
      accessToken: accessToken,
      refreshToken: rotatedRefreshToken,
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
  }

  @override
  Future<void> revoke(String token) async => revoked.add(token);
}
