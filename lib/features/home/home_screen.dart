import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../backup/backup_service.dart';
import '../../core/constants/date_constants.dart';
import '../../data/models/finance_category.dart';
import '../../data/models/finance_transaction.dart';
import '../../data/repositories/finance_repository.dart';
import '../categories/category_manager_screen.dart';
import '../transactions/add_transaction_screen.dart';

enum DateFilterKey {
  all,
  thisMonth,
  lastMonth,
  last3,
  last6,
  last12,
  ytd,
  pickedMonth,
  customRange,
}

enum _TxAction { cancel, edit, delete }

class HomeScreen extends StatefulWidget {
  final FinanceRepository repository;
  final BackupService? backupService;

  const HomeScreen({super.key, required this.repository, this.backupService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateFilterKey _key = DateFilterKey.all;
  String? _categoryFilterId; // null = alle
  static const String _addCategoryValue = '__add_category__';

  // wenn null/null => "Komplett"
  String? _startIsoInclusive;
  String? _endIsoExclusive;

  String? _pickedMonthLabel; // z.B. "Dez 2025"
  String? _customRangeLabel; // z.B. "Sep 2025 – Dez 2025"

  String _fmtEuro(int cents) {
    final sign = cents < 0 ? '-' : '';
    final abs = cents.abs();
    final euros = abs ~/ 100;
    final rest = abs % 100;
    return '$sign$euros,${rest.toString().padLeft(2, '0')} €';
  }

  String _isoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1, 1);

  String _fmtMonth(DateTime monthStart) {
    final name = monthNames[monthStart.month - 1];
    return '$name ${monthStart.year}';
  }

  String _fmtDateDisplay(String iso) {
    // erwartet "YYYY-MM-DD"
    final p = iso.split('-');
    if (p.length != 3) return iso; // fallback
    final y = int.tryParse(p[0]);
    final m = int.tryParse(p[1]);
    final d = int.tryParse(p[2]);
    if (y == null || m == null || d == null || m < 1 || m > 12) return iso;
    final dd = d.toString().padLeft(2, '0');
    final mon = monthNames[m - 1];
    return '$dd. $mon $y';
  }

  void _setAll() {
    setState(() {
      _key = DateFilterKey.all;
      _startIsoInclusive = null;
      _endIsoExclusive = null;
    });
  }

  void _setRangeByMonthStart(DateTime startMonth, DateTime endMonthInclusive) {
    final start = DateTime(startMonth.year, startMonth.month, 1);
    final endExclusive = DateTime(
      endMonthInclusive.year,
      endMonthInclusive.month + 1,
      1,
    );

    setState(() {
      _startIsoInclusive = _isoDate(start);
      _endIsoExclusive = _isoDate(endExclusive);
    });
  }

  void _setThisMonth() {
    final now = DateTime.now();
    final start = _monthStart(now);
    final endInc = start; // gleicher Monat, weil endExclusive = nextMonthStart
    setState(() => _key = DateFilterKey.thisMonth);
    _setRangeByMonthStart(start, endInc);
  }

  void _setLastMonth() {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month - 1, 1);
    setState(() => _key = DateFilterKey.lastMonth);
    _setRangeByMonthStart(last, last);
  }

  void _setLastNMonths(int n) {
    // "Letzte N Monate" inkl. aktuellem Monat
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final start = DateTime(thisMonth.year, thisMonth.month - (n - 1), 1);

    setState(() {
      _key = switch (n) {
        3 => DateFilterKey.last3,
        6 => DateFilterKey.last6,
        12 => DateFilterKey.last12,
        _ => _key,
      };
      _startIsoInclusive = _isoDate(start);
      _endIsoExclusive = _isoDate(_nextMonthStart(thisMonth));
    });
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

    // braucht die DB-Helper-Funktion aus meinem letzten Vorschlag:
    final created = await widget.repository.getActiveCategoryByName(name);
    return created?.id;
  }

  Future<DateTime?> _pickAnyDate({required DateTime initial}) {
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
  }

  Future<void> _pickMonth() async {
    final picked = await _pickAnyDate(initial: DateTime.now());
    if (picked == null) return;

    final month = DateTime(picked.year, picked.month, 1);

    setState(() {
      _key = DateFilterKey.pickedMonth;
      _pickedMonthLabel = _fmtMonth(month);
      _startIsoInclusive = _isoDate(month);
      _endIsoExclusive = _isoDate(_nextMonthStart(month));
    });
  }

  Future<void> _pickCustomRange() async {
    final startPick = await _pickAnyDate(initial: DateTime.now());
    if (startPick == null) return;

    final endPick = await _pickAnyDate(initial: startPick);
    if (endPick == null) return;

    var a = DateTime(startPick.year, startPick.month, 1);
    var b = DateTime(endPick.year, endPick.month, 1);

    // falls Nutzer "rückwärts" auswählt, tauschen wir
    if (b.isBefore(a)) {
      final tmp = a;
      a = b;
      b = tmp;
    }

    setState(() {
      _key = DateFilterKey.customRange;
      _customRangeLabel = '${_fmtMonth(a)} – ${_fmtMonth(b)}';
      _startIsoInclusive = _isoDate(a);
      _endIsoExclusive = _isoDate(DateTime(b.year, b.month + 1, 1));
    });
  }

  void _setYtd() {
    final now = DateTime.now();
    final start = DateTime(now.year, 1, 1);
    final endExclusive = DateTime(
      now.year,
      now.month + 1,
      1,
    ); // bis inkl. aktueller Monat
    setState(() {
      _key = DateFilterKey.ytd;
      _startIsoInclusive = _isoDate(start);
      _endIsoExclusive = _isoDate(endExclusive);
    });
  }

  Future<void> _onFilterChanged(DateFilterKey? key) async {
    if (key == null) return;

    switch (key) {
      case DateFilterKey.all:
        _setAll();
        break;
      case DateFilterKey.thisMonth:
        _setThisMonth();
        break;
      case DateFilterKey.lastMonth:
        _setLastMonth();
        break;
      case DateFilterKey.last3:
        _setLastNMonths(3);
        break;
      case DateFilterKey.last6:
        _setLastNMonths(6);
        break;
      case DateFilterKey.last12:
        _setLastNMonths(12);
        break;
      case DateFilterKey.ytd:
        _setYtd();
        break;
      case DateFilterKey.pickedMonth:
        await _pickMonth();
        break;
      case DateFilterKey.customRange:
        await _pickCustomRange();
        break;
    }
  }

  int _sumIncome(List<FinanceTransaction> items) => items
      .where((t) => t.type == 'income')
      .fold(0, (sum, t) => sum + t.amountCents);

  int _sumExpense(List<FinanceTransaction> items) => items
      .where((t) => t.type == 'expense')
      .fold(0, (sum, t) => sum + t.amountCents);

  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          repository: widget.repository,
          backupService: widget.backupService,
        ),
      ),
    );
  }

  Future<void> _editOrDeleteDialog(FinanceTransaction t) async {
    final action = await showDialog<_TxAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Buchung bearbeiten/löschen'),
        content: Text(
          '${t.category} • ${_fmtDateDisplay(t.date)} • ${_fmtEuro(t.amountCents)}',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, _TxAction.edit),
            child: const Text('Bearbeiten'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _TxAction.delete),
            child: const Text('Löschen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, _TxAction.cancel),
            child: const Text('Abbrechen'),
          ),
        ],
      ),
    );

    switch (action) {
      case _TxAction.edit:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AddTransactionScreen(
              repository: widget.repository,
              backupService: widget.backupService,
              existing: t,
            ),
          ),
        );
        break;
      case _TxAction.delete:
        await widget.repository.deleteTransaction(t.id);
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinanceCategory>>(
      stream: widget.repository.watchActiveCategories(),
      builder: (context, catSnap) {
        final cats = catSnap.data ?? const <FinanceCategory>[];
        final catById = {for (final c in cats) c.id: c.name};

        final stream = widget.repository.watchActiveTransactionsInRange(
          startIsoInclusive: _startIsoInclusive,
          endIsoExclusive: _endIsoExclusive,
          categoryId: _categoryFilterId,
        );

        return StreamBuilder<List<FinanceTransaction>>(
          stream: stream,
          builder: (context, snap) {
            final items = snap.data ?? const <FinanceTransaction>[];
            final income = _sumIncome(items);
            final expense = _sumExpense(items);
            final balance = income - expense;
            final fabBg =
                Theme.of(context).floatingActionButtonTheme.backgroundColor ??
                Theme.of(
                  context,
                ).colorScheme.primaryContainer; // M3 Default für FAB
            final fabFg =
                Theme.of(context).floatingActionButtonTheme.foregroundColor ??
                Theme.of(context).colorScheme.onPrimaryContainer;
            final double maxDim = 50;

            return Scaffold(
              appBar: AppBar(
                title: const _BebiAppBarTitle(),
                clipBehavior: Clip.none,
                actions: [
                  SizedBox(
                    width: 86, // größere Action-Box
                    child: Align(
                      child: OverflowBox(
                        maxWidth: maxDim + 9,
                        maxHeight: maxDim + 9,
                        child: Transform.translate(
                          offset: const Offset(4, 4), // nach unten verschieben
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints.tightFor(
                              width: maxDim + 9,
                              height: maxDim + 9,
                            ),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CategoryManagerScreen(
                                    repository: widget.repository,
                                    backupService: widget.backupService,
                                  ),
                                ),
                              );
                            },
                            tooltip: 'Kategorien verwalten',
                            icon: Image.asset(
                              'icons/cat_settings_icon_snoopy_light_no_bg_3.png',
                              width: maxDim,
                              height: maxDim,
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              floatingActionButton: FloatingActionButton(
                onPressed: _openAdd,
                child: const Icon(Icons.add),
              ),
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.titleMedium!,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Zeitraum:'),
                            const SizedBox(width: 12),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<DateFilterKey>(
                                value: _key,
                                isDense: true,
                                alignment: Alignment.centerLeft,
                                onChanged: (v) => _onFilterChanged(v),
                                items: const [
                                  DropdownMenuItem(
                                    value: DateFilterKey.all,
                                    child: Text('Komplett'),
                                  ),
                                  DropdownMenuItem(
                                    value: DateFilterKey.thisMonth,
                                    child: Text('Dieser Monat'),
                                  ),
                                  DropdownMenuItem(
                                    value: DateFilterKey.lastMonth,
                                    child: Text('Letzter Monat'),
                                  ),
                                  DropdownMenuItem(
                                    value: DateFilterKey.last3,
                                    child: Text('Letzte 3 Monate'),
                                  ),
                                  DropdownMenuItem(
                                    value: DateFilterKey.last6,
                                    child: Text('Letzte 6 Monate'),
                                  ),
                                  DropdownMenuItem(
                                    value: DateFilterKey.last12,
                                    child: Text('Letzte 12 Monate'),
                                  ),
                                  DropdownMenuItem(
                                    value: DateFilterKey.ytd,
                                    child: Text('Dieses Jahr'),
                                  ),
                                  DropdownMenuItem(
                                    value: DateFilterKey.pickedMonth,
                                    child: Text('Monat auswählen…'),
                                  ),
                                  DropdownMenuItem(
                                    value: DateFilterKey.customRange,
                                    child: Text('Spanne auswählen…'),
                                  ),
                                ],
                                selectedItemBuilder: (context) => [
                                  const Text('Komplett'),
                                  const Text('Dieser Monat'),
                                  const Text('Letzter Monat'),
                                  const Text('Letzte 3 Monate'),
                                  const Text('Letzte 6 Monate'),
                                  const Text('Letzte 12 Monate'),
                                  const Text('Dieses Jahr'),
                                  Text(
                                    _pickedMonthLabel ?? 'Monat auswählen…',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    _customRangeLabel ?? 'Spanne auswählen…',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: DefaultTextStyle.merge(
                        style: Theme.of(context).textTheme.titleMedium!,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Kategorie:'),
                            const SizedBox(width: 12),
                            DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                value:
                                    cats.any((c) => c.id == _categoryFilterId)
                                    ? _categoryFilterId
                                    : null,
                                isDense: true,
                                onChanged: (v) async {
                                  final previous = _categoryFilterId;

                                  if (v == _addCategoryValue) {
                                    final newId = await _promptNewCategoryId();
                                    if (!mounted) return;
                                    setState(() {
                                      _categoryFilterId =
                                          newId ??
                                          previous; // bei Abbruch alte Auswahl behalten
                                    });
                                    return;
                                  }

                                  setState(
                                    () => _categoryFilterId = v,
                                  ); // null = Alle, sonst Kategorie-ID
                                },
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Alle'),
                                  ),
                                  ...cats.map(
                                    (c) => DropdownMenuItem<String?>(
                                      value: c.id,
                                      child: Text(c.name),
                                    ),
                                  ),
                                  const DropdownMenuItem<String?>(
                                    value: _addCategoryValue,
                                    child: Text('+ Kategorie hinzufügen…'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Theme.of(context).colorScheme.primaryContainer,
                            Theme.of(context).colorScheme.tertiaryContainer,
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _Kpi(label: 'Einnahmen', value: _fmtEuro(income)),
                            _Kpi(label: 'Ausgaben', value: _fmtEuro(expense)),
                            _Kpi(label: 'Saldo', value: _fmtEuro(balance)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 0),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text(
                              'Keine Buchungen im gewählten Zeitraum.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: items.length,
                            // separatorBuilder: (_, __) => const Divider(height: 0),
                            itemBuilder: (context, i) {
                              final t = items[i];
                              final sign = t.type == 'expense' ? '-' : '+';
                              final catName =
                                  (t.categoryId != null &&
                                      catById.containsKey(t.categoryId))
                                  ? catById[t.categoryId]!
                                  : t.category;
                              final cs = Theme.of(context).colorScheme;
                              final isExpense = t.type == 'expense';

                              const incomeTileBg = Color(
                                0xFFF2FBF4,
                              ); // sehr helles mint
                              const expenseTileBg = Color(
                                0xFFFFF2F2,
                              ); // sehr helles rosé

                              const incomeBg = Color(
                                0xFFDFF5E3,
                              ); // mint pastell
                              const incomeFg = Color(
                                0xFF1B5E20,
                              ); // dunkles grün

                              const expenseBg = Color(
                                0xFFFFE1E1,
                              ); // rosa pastell
                              const expenseFg = Color(
                                0xFFB71C1C,
                              ); // dunkles rot

                              final avatarBg = isExpense ? expenseBg : incomeBg;
                              final avatarFg = isExpense ? expenseFg : incomeFg;
                              final accent = isExpense
                                  ? cs.errorContainer
                                  : cs.tertiaryContainer;

                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  1,
                                  12,
                                  0,
                                ),
                                child: Card(
                                  color: isExpense
                                      ? expenseTileBg
                                      : incomeTileBg,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      22,
                                    ), // wie dein CardTheme
                                  ),
                                  clipBehavior: Clip
                                      .antiAlias, // <-- DAS ist der wichtige Teil
                                  child: ListTile(
                                    dense: true,
                                    visualDensity: const VisualDensity(
                                      horizontal: 0,
                                      vertical: -2,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    onLongPress: () => _editOrDeleteDialog(t),
                                    leading: CircleAvatar(
                                      radius: 12,
                                      backgroundColor: avatarBg,
                                      child: Icon(
                                        isExpense ? Icons.remove : Icons.add,
                                        size: 18,
                                        color: avatarFg,
                                      ),
                                    ),
                                    title: Text(
                                      '$catName  •  ${_fmtDateDisplay(t.date)}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    subtitle: Text(
                                      (t.note?.trim().isNotEmpty ?? false)
                                          ? t.note!
                                          : '—',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                    trailing: Text(
                                      '$sign ${_fmtEuro(t.amountCents)}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  const _Kpi({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _BebiAppBarTitle extends StatelessWidget {
  const _BebiAppBarTitle();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: 0.3,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8FF6E),
              Color(0xFF93FF7D),
              Color(0xFF7FA6FF),
              Color(0xFFFF7FC8),
            ],
          ).createShader(bounds),
          child: Text(
            'HAUSHALTSPLANER',
            style: style?.copyWith(color: Colors.white),
          ),
        ),

        const SizedBox(width: 6),
        const Text('💸🤍'),
      ],
    );
  }
}
