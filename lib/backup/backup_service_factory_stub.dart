import '../db/database.dart';
import 'backup_service.dart';

BackupService createPlatformBackupService(AppDatabase db) {
  throw UnsupportedError(
    'Lokale Backups werden auf dieser Plattform nicht unterstützt.',
  );
}
