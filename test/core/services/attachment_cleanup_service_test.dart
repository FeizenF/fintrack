import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:fintrack/core/services/attachment_cleanup_service.dart';

void main() {
  late Directory supportDirectory;
  late Directory attachmentsDirectory;
  late AttachmentCleanupService service;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'fintrack-attachment-cleanup-',
    );
    attachmentsDirectory = Directory(
      p.join(supportDirectory.path, 'attachments'),
    );
    await attachmentsDirectory.create();
    service = AttachmentCleanupService(
      supportDirectoryProvider: () async => supportDirectory,
    );
  });

  tearDown(() async {
    await supportDirectory.delete(recursive: true);
  });

  test('deletes regular files in the owned attachment folder only', () async {
    final File firstFile = File(p.join(attachmentsDirectory.path, 'first.jpg'));
    final File secondFile = File(
      p.join(attachmentsDirectory.path, 'second.jpg'),
    );
    final File externalFile = File(
      p.join(supportDirectory.path, 'external.jpg'),
    );
    final File nestedFile = File(
      p.join(attachmentsDirectory.path, 'nested', 'nested.jpg'),
    );
    await firstFile.writeAsString('first');
    await secondFile.writeAsString('second');
    await externalFile.writeAsString('external');
    await nestedFile.parent.create();
    await nestedFile.writeAsString('nested');

    final AttachmentCleanupResult result =
        await service.deleteOwnedAttachments();

    expect(await firstFile.exists(), isFalse);
    expect(await secondFile.exists(), isFalse);
    expect(await externalFile.exists(), isTrue);
    expect(await nestedFile.exists(), isTrue);
    expect(result.deletedCount, 2);
    expect(result.failedPaths, isEmpty);
    expect(result.hasFailures, isFalse);
  });

  test('reports nothing to clean when attachment folder is absent', () async {
    await attachmentsDirectory.delete();

    final AttachmentCleanupResult result =
        await service.deleteOwnedAttachments();

    expect(result.deletedCount, 0);
    expect(result.failedPaths, isEmpty);
    expect(result.hasFailures, isFalse);
  });

  test('reports files that cannot be deleted without touching others', () async {
    final File lockedFile = File(
      p.join(attachmentsDirectory.path, 'locked.jpg'),
    );
    final File removableFile = File(
      p.join(attachmentsDirectory.path, 'removable.jpg'),
    );
    await lockedFile.writeAsString('locked');
    await removableFile.writeAsString('removable');
    service = AttachmentCleanupService(
      supportDirectoryProvider: () async => supportDirectory,
      deleteFile: (File file) async {
        if (p.equals(file.path, lockedFile.path)) {
          throw const FileSystemException('file is locked');
        }
        await file.delete();
      },
    );

    final AttachmentCleanupResult result =
        await service.deleteOwnedAttachments();

    expect(await lockedFile.exists(), isTrue);
    expect(await removableFile.exists(), isFalse);
    expect(result.deletedCount, 1);
    expect(result.failedPaths, <String>[lockedFile.path]);
    expect(result.hasFailures, isTrue);
  });

  test('keeps a directory symlink inside the attachment folder', () async {
    final Directory outsideDirectory = Directory(
      p.join(supportDirectory.path, 'outside'),
    );
    await outsideDirectory.create();
    final File outsideFile = File(p.join(outsideDirectory.path, 'keep.jpg'));
    await outsideFile.writeAsString('keep');
    final Link link = Link(p.join(attachmentsDirectory.path, 'linked'));
    try {
      await link.create(outsideDirectory.path);
    } on FileSystemException {
      // Windows requires developer mode or elevation for symlinks; the
      // directory-skip test already covers non-file entities.
      return;
    }

    final AttachmentCleanupResult result =
        await service.deleteOwnedAttachments();

    expect(await outsideFile.exists(), isTrue);
    expect(result.deletedCount, 0);
    expect(result.failedPaths, isEmpty);
  });
}
