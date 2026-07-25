import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:uuid/uuid.dart';

import '../../backup/backup_service.dart';
import '../../core/constants/date_constants.dart';
import '../../data/models/finance_category.dart';
import '../../data/models/finance_transaction.dart';
import '../../data/repositories/finance_repository.dart';
import '../categories/category_manager_screen.dart';

enum TxType { income, expense }

class AddTransactionScreen extends StatefulWidget {
  final FinanceRepository repository;
  final BackupService backupService;
  final FinanceTransaction? existing;

  const AddTransactionScreen({
    super.key,
    required this.repository,
    required this.backupService,
    this.existing,
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  TxType _type = TxType.expense;
  final _amountCtrl = TextEditingController();
  String? _selectedCategoryId;
  final _noteCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  static const String _addCategoryValue = '__add_category__';

  final _uuid = Uuid();

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.existing?.categoryId;
    final e = widget.existing;
    if (e != null) {
      _type = e.type == 'income' ? TxType.income : TxType.expense;
      _amountCtrl.text = _centsToInput(e.amountCents);
      _noteCtrl.text = e.note ?? '';
      _date = _parseIsoDate(e.date);
    }
  }

  DateTime _parseIsoDate(String iso) {
    // "YYYY-MM-DD"
    final p = iso.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  String _centsToInput(int cents) {
    final euros = cents ~/ 100;
    final rest = (cents % 100).abs().toString().padLeft(2, '0');
    return '$euros,$rest';
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  int? _parseAmountToCents(String input) {
    final s = input.trim().replaceAll('.', ',');
    if (s.isEmpty) return null;
    final parts = s.split(',');
    if (parts.length > 2) return null;

    final euros = int.tryParse(parts[0]);
    if (euros == null) return null;

    int cents = 0;
    if (parts.length == 2) {
      final frac = parts[1];
      if (frac.length > 2) return null;
      final fracPadded = frac.padRight(2, '0');
      cents = int.tryParse(fracPadded) ?? -1;
      if (cents < 0) return null;
    }
    return euros * 100 + cents;
  }

  String _dateToIsoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  Future<String?> _promptNewCategoryId() async {
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

    final name = ctrl.text.trim();
    if (ok != true || name.isEmpty) return null;

    await widget.repository.createCategory(name);

    final created = await widget.repository.getActiveCategoryByName(name);
    return created?.id;
  }

  Future<void> _save() async {
    final cents = _parseAmountToCents(_amountCtrl.text);
    if (cents == null || cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte einen gültigen Betrag eingeben (z.B. 12,34).'),
        ),
      );
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final id = widget.existing?.id ?? _uuid.v4();

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte eine Kategorie auswählen.')),
      );
      return;
    }

    final cat = await widget.repository.getCategoryById(_selectedCategoryId!);
    final categoryName = cat?.name ?? 'Allgemein';

    await widget.repository.saveTransaction(
      id: id,
      type: _type == TxType.income ? 'income' : 'expense',
      amountCents: cents,
      date: _dateToIsoDate(_date),
      category: categoryName,
      categoryId: _selectedCategoryId,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      updatedAtMs: nowMs,
      deletedAtMs: null,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dateText =
        '${_date.day.toString().padLeft(2, '0')}. '
        '${monthNames[_date.month - 1]} '
        '${_date.year}';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? 'Neue Buchung' : 'Buchung bearbeiten',
        ),
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
            tooltip: 'Speichern',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<TxType>(
            segments: const [
              ButtonSegment(value: TxType.expense, label: Text('Ausgabe')),
              ButtonSegment(value: TxType.income, label: Text('Einnahme')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Betrag',
              hintText: 'z.B. 12,34',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          StreamBuilder<List<FinanceCategory>>(
            stream: widget.repository.watchActiveCategories(),
            builder: (context, snap) {
              final cats = snap.data ?? const <FinanceCategory>[];

              // Wenn noch nichts geladen ist:
              if (snap.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 56,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              // Wenn keine Kategorien existieren (sollte durch "Allgemein" selten sein):
              if (cats.isEmpty) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Keine Kategorien vorhanden.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CategoryManagerScreen(
                              repository: widget.repository,
                              backupService: widget.backupService,
                            ),
                          ),
                        );
                        setState(() {}); // Refresh
                      },
                      icon: const Icon(Icons.category),
                      label: const Text('Kategorien verwalten'),
                    ),
                  ],
                );
              }

              // Wenn keine Auswahl gesetzt ist (neue Buchung), nimm "Allgemein", sonst erste
              if (_selectedCategoryId == null) {
                final defaultCat = cats.firstWhere(
                  (c) => c.name.toLowerCase() == 'allgemein',
                  orElse: () => cats.first,
                );
                // setState erst nach dem Frame, sonst "setState during build"
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _selectedCategoryId == null) {
                    setState(() => _selectedCategoryId = defaultCat.id);
                  }
                });
              }

              final currentValue = cats.any((c) => c.id == _selectedCategoryId)
                  ? _selectedCategoryId
                  : null;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: currentValue,
                    items: [
                      ...cats.map(
                        (c) =>
                            DropdownMenuItem(value: c.id, child: Text(c.name)),
                      ),
                      const DropdownMenuItem(
                        value: _addCategoryValue,
                        child: Text('+ Kategorie hinzufügen…'),
                      ),
                    ],
                    onChanged: (id) async {
                      if (id == null) return;

                      // Spezial-Eintrag: Dialog öffnen, danach echte Kategorie setzen
                      if (id == _addCategoryValue) {
                        final previous =
                            _selectedCategoryId; // falls Nutzer abbricht
                        final newId = await _promptNewCategoryId();

                        if (!mounted) return;
                        setState(() {
                          _selectedCategoryId = newId ?? previous;
                        });
                        return;
                      }

                      // Normale Auswahl
                      setState(() => _selectedCategoryId = id);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Kategorie',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CategoryManagerScreen(
                              repository: widget.repository,
                              backupService: widget.backupService,
                            ),
                          ),
                        );
                        // nach Rückkehr neu bauen (falls Kategorien geändert wurden)
                        setState(() {});
                      },
                      icon: Icon(
                        Symbols.folder_managed,
                        fill: 1,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      label: const Text('Kategorien verwalten'),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notiz (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month),
            label: Text('Datum: $dateText'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Speichern'),
          ),
        ],
      ),
    );
  }
}
