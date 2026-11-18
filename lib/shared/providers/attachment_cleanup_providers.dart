import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/attachment_cleanup_service.dart';

final Provider<AttachmentCleanupService> attachmentCleanupServiceProvider =
    Provider<AttachmentCleanupService>((Ref ref) => AttachmentCleanupService());
