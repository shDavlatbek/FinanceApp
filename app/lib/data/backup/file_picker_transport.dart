/// The one place `file_picker` is touched.
///
/// Everything else in `data/backup/` deals in bytes, so the plugin — and the
/// platform behaviour that comes with it — is confined to this file. Tests
/// substitute a fake [BackupFileTransport] and never load a platform channel.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'backup_file.dart';

class FilePickerBackupTransport implements BackupFileTransport {
  const FilePickerBackupTransport();

  @override
  Future<bool> save(BackupFile file) async {
    // Passing `bytes` is what makes this actually write the file, rather than
    // handing back a location we would then have to open ourselves — which on
    // Android would mean a storage permission the app otherwise never needs.
    final Uri? saved = await FilePicker.saveFile(
      fileName: file.fileName,
      bytes: file.bytes,
      mimeType: file.mimeType,
    );
    // Null is a cancel, which is a normal outcome and not an error.
    return saved != null;
  }

  @override
  Future<PickedBackupFile?> pick() async {
    final PlatformFile? picked = await FilePicker.pickFile(
      // `custom` + a single extension on purpose: import only reads snapshot
      // JSON. Offering every file type invites picking the CSV, which is an
      // export-only format and cannot restore anything.
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
    );
    if (picked == null) return null;
    final Uint8List bytes = await picked.readAsBytes();
    return PickedBackupFile(fileName: picked.name, bytes: bytes);
  }
}
