import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of cleaning attachment files during a local data reset.
class AttachmentCleanupResult {
  const AttachmentCleanupResult({
    required this.deletedCount,
    required this.failedPaths,
  });

  final int deletedCount;
  final List<String> failedPaths;

  bool get hasFailures => failedPaths.isNotEmpty;
}

/// Deletes every regular file directly inside FinTrack's private attachment
/// folder. Subdirectories, links, and everything outside that folder are left
/// untouched, so a hostile or stale path can never widen the deletion scope.
class AttachmentCleanupService {
  AttachmentCleanupService({
    Future<Directory> Function()? supportDirectoryProvider,
    Future<void> Function(File file)? deleteFile,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _deleteFile = deleteFile ?? _defaultDelete;

  static Future<void> _defaultDelete(File file) => file.delete();

  final Future<Directory> Function() _supportDirectoryProvider;
  final Future<void> Function(File file) _deleteFile;

  Future<AttachmentCleanupResult> deleteOwnedAttachments() async {
    final Directory supportDirectory = await _supportDirectoryProvider();
    final String attachmentDirectoryPath = p.normalize(
      p.join(supportDirectory.path, 'attachments'),
    );
    final FileSystemEntityType type = await FileSystemEntity.type(
      attachmentDirectoryPath,
      followLinks: false,
    );
    if (type != FileSystemEntityType.directory) {
      return const AttachmentCleanupResult(
        deletedCount: 0,
        failedPaths: <String>[],
      );
    }

    final List<String> failedPaths = <String>[];
    int deletedCount = 0;
    await for (final FileSystemEntity entity
        in Directory(attachmentDirectoryPath).list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        await _deleteFile(entity);
        deletedCount++;
      } on Object {
        failedPaths.add(entity.path);
      }
    }

    return AttachmentCleanupResult(
      deletedCount: deletedCount,
      failedPaths: List<String>.unmodifiable(failedPaths),
    );
  }
}
