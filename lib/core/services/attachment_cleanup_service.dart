import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Result of cleaning attachment files referenced by reset transactions.
class AttachmentCleanupResult {
  const AttachmentCleanupResult({
    required this.deletedCount,
    required this.retainedCount,
    required this.failedPaths,
  });

  final int deletedCount;
  final int retainedCount;
  final List<String> failedPaths;

  bool get hasIncompleteCleanup => retainedCount > 0 || failedPaths.isNotEmpty;
}

/// Deletes only direct regular files in FinTrack's private attachment folder.
/// Paths outside that folder, nested paths, links, and directories are retained.
class AttachmentCleanupService {
  AttachmentCleanupService({
    Future<Directory> Function()? supportDirectoryProvider,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectoryProvider;

  Future<AttachmentCleanupResult> deleteOwnedAttachments(
    Iterable<String?> paths,
  ) async {
    final Directory supportDirectory = await _supportDirectoryProvider();
    final String attachmentDirectoryPath = p.normalize(
      p.join(supportDirectory.path, 'attachments'),
    );
    final Set<String> uniquePaths = paths
        .whereType<String>()
        .where((String path) => path.isNotEmpty)
        .toSet();
    final List<String> failedPaths = <String>[];
    int deletedCount = 0;
    int retainedCount = 0;

    if (await FileSystemEntity.type(
          attachmentDirectoryPath,
          followLinks: false,
        ) !=
        FileSystemEntityType.directory) {
      return AttachmentCleanupResult(
        deletedCount: 0,
        retainedCount: uniquePaths.length,
        failedPaths: const <String>[],
      );
    }

    for (final String path in uniquePaths) {
      if (!p.isAbsolute(path)) {
        retainedCount++;
        continue;
      }
      final String normalizedPath = p.normalize(path);
      if (!p.equals(p.dirname(normalizedPath), attachmentDirectoryPath) ||
          p.basename(normalizedPath).isEmpty) {
        retainedCount++;
        continue;
      }
      final FileSystemEntityType type = await FileSystemEntity.type(
        normalizedPath,
        followLinks: false,
      );
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.file) {
        retainedCount++;
        continue;
      }
      try {
        await File(normalizedPath).delete();
        deletedCount++;
      } on Object {
        failedPaths.add(path);
      }
    }

    return AttachmentCleanupResult(
      deletedCount: deletedCount,
      retainedCount: retainedCount,
      failedPaths: List<String>.unmodifiable(failedPaths),
    );
  }
}
