import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:typed_data';

import '../db/database.dart';

class BackupService {
  final AppDatabase db;
  BackupService(this.db);

  Future<File> exportJsonBackup() async {
    final cats = await db.select(db.categories).get();
    final txs  = await db.select(db.transactions).get();

    final payload = {
      "version": 1,
      "exportedAtMs": DateTime.now().millisecondsSinceEpoch,
      "categories": cats.map((c) => {
        "id": c.id,
        "name": c.name,
        "updatedAtMs": c.updatedAtMs,
        "deletedAtMs": c.deletedAtMs,
      }).toList(),
      "transactions": txs.map((t) => {
        "id": t.id,
        "type": t.type,
        "amountCents": t.amountCents,
        "date": t.date,
        "category": t.category,
        "categoryId": t.categoryId,
        "note": t.note,
        "updatedAtMs": t.updatedAtMs,
        "deletedAtMs": t.deletedAtMs,
      }).toList(),
    };

    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/haushaltsplaner-backup-$ts.json');

    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
    return file;
  }

  Future<void> shareLatestBackup() async {
    final file = await exportJsonBackup();
    await Share.shareXFiles([XFile(file.path)], text: 'Haushaltsplaner Backup (JSON)');
  }

  Future<bool> importJsonBackupFromPicker({bool replaceLocal = true}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
        withReadStream: true,
      );
      if (result == null || result.files.isEmpty) return false;

      final file = result.files.single;

      // Bytes robust holen (Android 13/14/15/16 kann bytes/path unterschiedlich liefern)
      Uint8List bytes;
      if (file.bytes != null) {
        bytes = file.bytes!;
      } else if (file.readStream != null) {
        final builder = BytesBuilder();
        await for (final chunk in file.readStream!) {
          builder.add(chunk);
        }
        bytes = builder.takeBytes();
      } else if (file.path != null) {
        bytes = await File(file.path!).readAsBytes();
      } else {
        throw Exception('Konnte Datei nicht lesen (kein bytes/readStream/path).');
      }

      final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final categories = (data["categories"] as List<dynamic>).cast<Map<String, dynamic>>();
      final transactions = (data["transactions"] as List<dynamic>).cast<Map<String, dynamic>>();

      await db.transaction(() async {
        if (replaceLocal) {
          // Wichtig: erst Transactions löschen, dann Categories
          await (db.delete(db.transactions)).go();
          await (db.delete(db.categories)).go();
        }

        for (final c in categories) {
          await db.upsertCategory(
            id: c["id"] as String,
            name: c["name"] as String,
            updatedAtMs: c["updatedAtMs"] as int,
            deletedAtMs: c["deletedAtMs"] as int?,
          );
        }

        for (final t in transactions) {
          await db.upsertTransaction(
            id: t["id"] as String,
            type: t["type"] as String,
            amountCents: t["amountCents"] as int,
            date: t["date"] as String,
            category: t["category"] as String,
            categoryId: t["categoryId"] as String?,
            note: t["note"] as String?,
            updatedAtMs: t["updatedAtMs"] as int,
            deletedAtMs: t["deletedAtMs"] as int?,
          );
        }
      });

      return true;
    } catch (e) {
      // Log für Android Studio Console
      // ignore: avoid_print
      print('IMPORT FAILED: $e');
      return false;
    }
  }
}