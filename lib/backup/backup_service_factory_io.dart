import '../db/database.dart';
import 'backup_service.dart';
import 'native_backup_service.dart';

BackupService createPlatformBackupService(AppDatabase db) {
  return NativeBackupService(db);
}
