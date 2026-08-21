/// A file the app hands to the platform, and one it reads back.
///
/// Deliberately just bytes + a name + a mime type: the export/import LOGIC
/// (snapshot serialization, CSV writing, sanitize, merge) must be testable
/// without a file picker, a platform channel or a real filesystem.
library;

import 'dart:typed_data';

/// Bytes destined for a file the owner chooses a location for.
class BackupFile {
  const BackupFile({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

/// A file the owner picked, on its way into [BackupService.importSnapshot].
class PickedBackupFile {
  const PickedBackupFile({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;
}

/// Saving and picking, abstracted away from `file_picker` so that everything
/// above it stays unit-testable and the plugin is touched in exactly one file.
abstract class BackupFileTransport {
  /// Writes [file] wherever the owner chooses. Returns false when they
  /// cancel — a cancel is a normal outcome, not an error.
  Future<bool> save(BackupFile file);

  /// Picks one file to import, or null when the owner cancels.
  Future<PickedBackupFile?> pick();
}
