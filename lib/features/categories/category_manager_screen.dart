import 'package:flutter/material.dart';

import '../../backup/backup_service.dart';
import '../../data/models/finance_category.dart';
import '../../data/repositories/finance_repository.dart';

enum _DeleteCatPolicy { move, archive, deleteEntries }

class CategoryManagerScreen extends StatelessWidget {
  final FinanceRepository repository;
  final BackupService backupService;

  const CategoryManagerScreen({
    super.key,
    required this.repository,
    required this.backupService,
  });

  static Color _pastelByIndex(int index, int count) {
    final n = count <= 0 ? 1 : count;
    final hue = (index * 360.0 / n) % 360.0;
    return HSLColor.fromAHSL(1.0, hue, 0.45, 0.88).toColor(); // pastell
  }

  static Color _onPastel(Color bg) =>
      bg.computeLuminance() > 0.6 ? Colors.black87 : Colors.white;

  Future<void> _add(BuildContext context) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kategorie hinzufügen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (ok == true) {
      final res = await repository.createCategory(ctrl.text);

      if (!context.mounted) return;
      final msg = switch (res) {
        CategoryCreationResult.created => 'Kategorie erstellt ✅',
        CategoryCreationResult.restored => 'Kategorie wiederhergestellt ✅',
        CategoryCreationResult.alreadyExists => 'Kategorie existiert bereits.',
        _ => 'Ungültiger Name.',
      };

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _edit(BuildContext context, FinanceCategory cat) async {
    final ctrl = TextEditingController(text: cat.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Kategorie umbenennen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await repository.renameCategory(cat.id, ctrl.text);
    }
  }

  Future<void> _delete(
    BuildContext context,
    FinanceCategory cat,
    List<FinanceCategory> allCats,
  ) async {
    final count = await repository.countActiveTransactionsForCategory(cat.id);

    // Zielkategorien (nicht die zu löschende)
    final targets = allCats.where((c) => c.id != cat.id).toList();

    // Default target: "Allgemein" (oder erste verfügbare)
    final defaultTarget = targets.firstWhere(
      (c) => c.name.toLowerCase() == 'allgemein',
      orElse: () => targets.isNotEmpty
          ? targets.first
          : cat, // placeholder; wird unten abgefangen
    );

    _DeleteCatPolicy policy = _DeleteCatPolicy.move;
    String? moveTargetId = targets.isNotEmpty ? defaultTarget.id : null;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocalState) {
          return AlertDialog(
            title: const Text('Kategorie löschen'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '„${cat.name}“ enthält $count Buchungen. Was soll damit passieren?',
                ),
                const SizedBox(height: 12),

                RadioListTile<_DeleteCatPolicy>(
                  value: _DeleteCatPolicy.move,
                  groupValue: policy,
                  onChanged: (v) => setLocalState(() => policy = v!),
                  title: const Text('Buchungen verschieben nach:'),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: IgnorePointer(
                    ignoring: policy != _DeleteCatPolicy.move,
                    child: Opacity(
                      opacity: policy == _DeleteCatPolicy.move ? 1 : 0.5,
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value:
                            (moveTargetId != null &&
                                targets.any((c) => c.id == moveTargetId))
                            ? moveTargetId
                            : (targets.isNotEmpty ? targets.first.id : null),
                        items: targets
                            .map(
                              (c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setLocalState(() => moveTargetId = v),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 8),
                RadioListTile<_DeleteCatPolicy>(
                  value: _DeleteCatPolicy.archive,
                  groupValue: policy,
                  onChanged: (v) => setLocalState(() => policy = v!),
                  title: const Text('Buchungen ins Archiv verschieben'),
                ),

                const SizedBox(height: 8),
                RadioListTile<_DeleteCatPolicy>(
                  value: _DeleteCatPolicy.deleteEntries,
                  groupValue: policy,
                  onChanged: (v) => setLocalState(() => policy = v!),
                  title: const Text('Buchungen ebenfalls löschen'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Abbrechen'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Löschen'),
              ),
            ],
          );
        },
      ),
    );

    if (ok != true) return;

    await repository.runInTransaction(() async {
      // 1) Policy anwenden
      if (count > 0) {
        if (policy == _DeleteCatPolicy.deleteEntries) {
          await repository.deleteActiveTransactionsForCategory(cat.id);
        } else if (policy == _DeleteCatPolicy.archive) {
          final archive = await repository.ensureCategoryActiveByName('Archiv');
          await repository.moveActiveTransactionsToCategory(
            fromCategoryId: cat.id,
            toCategoryId: archive.id,
            toCategoryNameSnapshot: archive.name,
          );
        } else {
          // move
          // Falls es keine Zielkategorie gab, stelle "Allgemein" sicher und nutze die.
          FinanceCategory target;
          if (moveTargetId == null) {
            target = await repository.ensureCategoryActiveByName('Allgemein');
          } else {
            target = targets.firstWhere((c) => c.id == moveTargetId);
          }

          await repository.moveActiveTransactionsToCategory(
            fromCategoryId: cat.id,
            toCategoryId: target.id,
            toCategoryNameSnapshot: target.name,
          );
        }
      }
      // 2) Kategorie selbst soft-deleten
      await repository.deleteCategory(cat.id);
    });

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Kategorie gelöscht ✅')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategorien'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final backup = backupService;

              if (v == 'export') {
                await backup.shareLatestBackup();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backup exportiert ✅')),
                );
              }

              if (v == 'import') {
                final ok = await backup.importJsonBackupFromPicker(
                  replaceLocal: true,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Import abgeschlossen ✅'
                          : 'Import abgebrochen/fehlgeschlagen ❌',
                    ),
                  ),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'export', child: Text('Backup exportieren')),
              PopupMenuItem(value: 'import', child: Text('Backup importieren')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Kategorie'),
      ),
      body: StreamBuilder<List<FinanceCategory>>(
        stream: repository.watchActiveCategories(),
        builder: (context, snap) {
          final cats = (snap.data ?? const <FinanceCategory>[]).toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
          if (cats.isEmpty) {
            return const Center(
              child: Text(
                'Noch keine Kategorien.\nTippe auf „Kategorie“ zum Hinzufügen. ✨',
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12), // Platz für FAB
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final c = cats[i];
              final bg = _pastelByIndex(i, cats.length);
              final fg = _onPastel(bg);
              final letter = c.name.trim().isEmpty
                  ? '?'
                  : c.name.trim()[0].toUpperCase();

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Card(
                  color: bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    title: Text(
                      c.name,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: fg),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Umbenennen',
                          onPressed: () => _edit(context, c),
                          icon: Icon(Icons.edit, color: fg),
                        ),
                        IconButton(
                          tooltip: 'Löschen',
                          onPressed: () => _delete(context, c, cats),
                          icon: Icon(Icons.delete, color: fg),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
