import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/backup_service.dart';
import 'database_providers.dart';

final FutureProvider<BackupService> backupServiceProvider =
    FutureProvider<BackupService>((Ref ref) async {
      return BackupService(database: await ref.watch(appDatabaseProvider.future));
    });
