abstract interface class BackupService {
  Future<void> shareLatestBackup();

  Future<bool> importJsonBackupFromPicker({bool replaceLocal = true});
}
