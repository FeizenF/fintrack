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

  test('deletes direct files from owned attachment directory only', () async {
    final File ownedFile = File(p.join(attachmentsDirectory.path, 'owned.jpg'));
    final File externalFile = File(
      p.join(supportDirectory.path, 'external.jpg'),
    );
    final File nestedFile = File(
      p.join(attachmentsDirectory.path, 'nested', 'nested.jpg'),
    );
    await ownedFile.writeAsString('owned');
    await externalFile.writeAsString('external');
    await nestedFile.parent.create();
    await nestedFile.writeAsString('nested');

    final AttachmentCleanupResult result = await service.deleteOwnedAttachments(
      <String?>[
        ownedFile.path,
        externalFile.path,
        nestedFile.path,
        externalFile.path,
        null,
      ],
    );

    expect(await ownedFile.exists(), isFalse);
    expect(await externalFile.exists(), isTrue);
    expect(await nestedFile.exists(), isTrue);
    expect(result.deletedCount, 1);
    expect(result.retainedCount, 2);
    expect(result.failedPaths, isEmpty);
    expect(result.hasIncompleteCleanup, isTrue);
  });

  test('ignores missing files and reports retained directory paths', () async {
    final Directory childDirectory = Directory(
      p.join(attachmentsDirectory.path, 'folder'),
    );
    await childDirectory.create();

    final AttachmentCleanupResult result = await service.deleteOwnedAttachments(
      <String?>[
        p.join(attachmentsDirectory.path, 'missing.jpg'),
        childDirectory.path,
      ],
    );

    expect(await childDirectory.exists(), isTrue);
    expect(result.deletedCount, 0);
    expect(result.retainedCount, 1);
    expect(result.failedPaths, isEmpty);
  });

  test('reports every path as retained when attachment folder is absent', () async {
    await attachmentsDirectory.delete();

    final AttachmentCleanupResult result = await service.deleteOwnedAttachments(
      <String?>[
        p.join(attachmentsDirectory.path, 'one.jpg'),
        p.join(attachmentsDirectory.path, 'two.jpg'),
      ],
    );

    expect(result.deletedCount, 0);
    expect(result.retainedCount, 2);
    expect(result.failedPaths, isEmpty);
    expect(result.hasIncompleteCleanup, isTrue);
  });

  test('treats relative paths as retained', () async {
    final File relativeTarget = File(
      p.join(attachmentsDirectory.path, 'relative.jpg'),
    );
    await relativeTarget.writeAsString('kept');

    final AttachmentCleanupResult result = await service.deleteOwnedAttachments(
      <String?>[p.join('attachments', 'relative.jpg')],
    );

    expect(await relativeTarget.exists(), isTrue);
    expect(result.deletedCount, 0);
    expect(result.retainedCount, 1);
    expect(result.hasIncompleteCleanup, isTrue);
  });
}
