import '../db/database.dart';
import 'backup_service.dart';
import 'backup_service_factory_stub.dart'
    if (dart.library.io) 'backup_service_factory_io.dart';

BackupService createBackupService(AppDatabase db) {
  return createPlatformBackupService(db);
}
