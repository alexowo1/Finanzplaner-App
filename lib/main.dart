import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'db/database.dart';
import 'backup/backup_service.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  runApp(const HaushaltsplanerApp());
}

enum TxType { income, expense }
enum _DeleteCatPolicy { move, archive, deleteEntries }

class HaushaltsplanerApp extends StatefulWidget {
  const HaushaltsplanerApp({super.key});

  @override
  State<HaushaltsplanerApp> createState() => _HaushaltsplanerAppState();
}

class _HaushaltsplanerAppState extends State<HaushaltsplanerApp> {
  late final AppDatabase db = AppDatabase();

  @override
  void dispose() {
    db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFF0D9FF),
      brightness: Brightness.light,
    );

      const bg = Color(0xFFFFFFFF);

    return MaterialApp(
      title: 'Haushaltsplaner',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,

        scaffoldBackgroundColor: bg,
        canvasColor: bg, // hilft bei manchen Widgets

        appBarTheme: AppBarTheme(
          backgroundColor: bg, // damit AppBar farblich “mitgeht”
          foregroundColor: scheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
      ),
      home: HomeScreen(db: db),

      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('de', 'DE'),
        Locale('en', 'US'),
      ],
      locale: const Locale('de', 'DE'), // optional: erzwingt Deutsch/Montag
    );
  }
}

const List<String> _monthNames = [
  'Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
  'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'
];

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
  final AppDatabase db;
  const HomeScreen({super.key, required this.db});

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

  String? _pickedMonthLabel;   // z.B. "Dez 2025"
  String? _customRangeLabel;   // z.B. "Sep 2025 – Dez 2025"

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
    final name = _monthNames[monthStart.month - 1];
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
    final mon = _monthNames[m - 1];
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
    final endExclusive = DateTime(endMonthInclusive.year, endMonthInclusive.month + 1, 1);

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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
        ],
      ),
    );

    final name = ctrl.text.trim();
    if (ok != true || name.isEmpty) return null;

    await widget.db.createCategory(name);

    // braucht die DB-Helper-Funktion aus meinem letzten Vorschlag:
    // Future<CategoryEntry?> getActiveCategoryByName(String name)
    final created = await widget.db.getActiveCategoryByName(name);
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
    final endExclusive = DateTime(now.year, now.month + 1, 1); // bis inkl. aktueller Monat
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

  int _sumIncome(List<TxEntry> items) => items
      .where((t) => t.type == 'income')
      .fold(0, (sum, t) => sum + t.amountCents);

  int _sumExpense(List<TxEntry> items) => items
      .where((t) => t.type == 'expense')
      .fold(0, (sum, t) => sum + t.amountCents);

  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AddTransactionScreen(db: widget.db)),
    );
  }

  Future<void> _editOrDeleteDialog(TxEntry t) async {
    final action = await showDialog<_TxAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Buchung bearbeiten/löschen'),
        content: Text('${t.category} • ${_fmtDateDisplay(t.date)} • ${_fmtEuro(t.amountCents)}'),
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
          MaterialPageRoute(builder: (_) => AddTransactionScreen(db: widget.db, existing: t)),
        );
        break;
      case _TxAction.delete:
        await widget.db.softDelete(t.id);
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CategoryEntry>>(
      stream: widget.db.watchActiveCategories(),
      builder: (context, catSnap) {
        final cats = catSnap.data ?? const <CategoryEntry>[];
        final catById = {for (final c in cats) c.id: c.name};

        final stream = widget.db.watchActiveTransactionsInRange(
          startIsoInclusive: _startIsoInclusive,
          endIsoExclusive: _endIsoExclusive,
          categoryId: _categoryFilterId,
        );

        return StreamBuilder<List<TxEntry>>(
          stream: stream,
          builder: (context, snap) {
            final items = snap.data ?? const <TxEntry>[];
            final income = _sumIncome(items);
            final expense = _sumExpense(items);
            final balance = income - expense;
            final fabBg = Theme.of(context).floatingActionButtonTheme.backgroundColor
                ?? Theme.of(context).colorScheme.primaryContainer; // M3 Default für FAB
            final fabFg = Theme.of(context).floatingActionButtonTheme.foregroundColor
                ?? Theme.of(context).colorScheme.onPrimaryContainer;
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
                        maxWidth: maxDim+9,
                        maxHeight: maxDim+9,
                        child: Transform.translate(
                          offset: const Offset(4, 4), // nach unten verschieben
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: BoxConstraints.tightFor(width: maxDim+9, height: maxDim+9),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => CategoryManagerScreen(db: widget.db)),
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
                                  DropdownMenuItem(value: DateFilterKey.all, child: Text('Komplett')),
                                  DropdownMenuItem(value: DateFilterKey.thisMonth, child: Text('Dieser Monat')),
                                  DropdownMenuItem(value: DateFilterKey.lastMonth, child: Text('Letzter Monat')),
                                  DropdownMenuItem(value: DateFilterKey.last3, child: Text('Letzte 3 Monate')),
                                  DropdownMenuItem(value: DateFilterKey.last6, child: Text('Letzte 6 Monate')),
                                  DropdownMenuItem(value: DateFilterKey.last12, child: Text('Letzte 12 Monate')),
                                  DropdownMenuItem(value: DateFilterKey.ytd, child: Text('Dieses Jahr')),
                                  DropdownMenuItem(value: DateFilterKey.pickedMonth, child: Text('Monat auswählen…')),
                                  DropdownMenuItem(value: DateFilterKey.customRange, child: Text('Spanne auswählen…')),
                                ],
                                selectedItemBuilder: (context) => [
                                  const Text('Komplett'),
                                  const Text('Dieser Monat'),
                                  const Text('Letzter Monat'),
                                  const Text('Letzte 3 Monate'),
                                  const Text('Letzte 6 Monate'),
                                  const Text('Letzte 12 Monate'),
                                  const Text('Dieses Jahr'),
                                  Text(_pickedMonthLabel ?? 'Monat auswählen…', overflow: TextOverflow.ellipsis),
                                  Text(_customRangeLabel ?? 'Spanne auswählen…', overflow: TextOverflow.ellipsis),
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
                                value: cats.any((c) => c.id == _categoryFilterId) ? _categoryFilterId : null,
                                isDense: true,
                                onChanged: (v) async {
                                  final previous = _categoryFilterId;

                                  if (v == _addCategoryValue) {
                                    final newId = await _promptNewCategoryId();
                                    if (!mounted) return;
                                    setState(() {
                                      _categoryFilterId = newId ?? previous; // bei Abbruch alte Auswahl behalten
                                    });
                                    return;
                                  }

                                  setState(() => _categoryFilterId = v); // null = Alle, sonst Kategorie-ID
                                },
                                items: [
                                  const DropdownMenuItem<String?>(value: null, child: Text('Alle')),
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
                        ? const Center(child: Text('Keine Buchungen im gewählten Zeitraum.'))
                        : ListView.builder(
                      itemCount: items.length,
                      // separatorBuilder: (_, __) => const Divider(height: 0),
                      itemBuilder: (context, i) {
                        final t = items[i];
                        final sign = t.type == 'expense' ? '-' : '+';
                        final catName = (t.categoryId != null && catById.containsKey(t.categoryId))
                            ? catById[t.categoryId]!
                            : t.category;
                        final cs = Theme.of(context).colorScheme;
                        final isExpense = t.type == 'expense';

                        const incomeTileBg = Color(0xFFF2FBF4);  // sehr helles mint
                        const expenseTileBg = Color(0xFFFFF2F2); // sehr helles rosé

                        const incomeBg = Color(0xFFDFF5E3);  // mint pastell
                        const incomeFg = Color(0xFF1B5E20);  // dunkles grün

                        const expenseBg = Color(0xFFFFE1E1); // rosa pastell
                        const expenseFg = Color(0xFFB71C1C); // dunkles rot

                        final avatarBg = isExpense ? expenseBg : incomeBg;
                        final avatarFg = isExpense ? expenseFg : incomeFg;
                        final accent = isExpense ? cs.errorContainer : cs.tertiaryContainer;

                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 1, 12, 0),
                          child: Card(
                            color: isExpense ? expenseTileBg : incomeTileBg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22), // wie dein CardTheme
                            ),
                            clipBehavior: Clip.antiAlias, // <-- DAS ist der wichtige Teil
                            child: ListTile(
                              dense: true,
                              visualDensity: const VisualDensity(horizontal: 0, vertical: -2),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              subtitle: Text(
                                (t.note?.trim().isNotEmpty ?? false) ? t.note! : '—',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              trailing: Text(
                                '$sign ${_fmtEuro(t.amountCents)}',
                                style: Theme.of(context).textTheme.bodyLarge,
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

class AddTransactionScreen extends StatefulWidget {
  final AppDatabase db;
  final TxEntry? existing;
  const AddTransactionScreen({super.key, required this.db, this.existing});

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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
        ],
      ),
    );

    final name = ctrl.text.trim();
    if (ok != true || name.isEmpty) return null;

    await widget.db.createCategory(name);

    final created = await widget.db.getActiveCategoryByName(name);
    return created?.id;
  }

  Future<void> _save() async {
    final cents = _parseAmountToCents(_amountCtrl.text);
    if (cents == null || cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte einen gültigen Betrag eingeben (z.B. 12,34).')),
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

    final cat = await widget.db.getCategoryById(_selectedCategoryId!);
    final categoryName = cat?.name ?? 'Allgemein';

    await widget.db.upsertTransaction(
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
        '${_monthNames[_date.month - 1]} '
        '${_date.year}';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Neue Buchung' : 'Buchung bearbeiten'),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.check), tooltip: 'Speichern'),
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
          StreamBuilder<List<CategoryEntry>>(
            stream: widget.db.watchActiveCategories(),
            builder: (context, snap) {
              final cats = snap.data ?? const <CategoryEntry>[];

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
                          MaterialPageRoute(builder: (_) => CategoryManagerScreen(db: widget.db)),
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
                      ...cats.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
                      const DropdownMenuItem(
                        value: _addCategoryValue,
                        child: Text('+ Kategorie hinzufügen…'),
                      ),
                    ],
                    onChanged: (id) async {
                      if (id == null) return;

                      // Spezial-Eintrag: Dialog öffnen, danach echte Kategorie setzen
                      if (id == _addCategoryValue) {
                        final previous = _selectedCategoryId;   // falls Nutzer abbricht
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
                          MaterialPageRoute(builder: (_) => CategoryManagerScreen(db: widget.db)),
                        );
                        // nach Rückkehr neu bauen (falls Kategorien geändert wurden)
                        setState(() {});
                      },
                      icon: Icon(Symbols.folder_managed, fill: 1, color: Theme.of(context).colorScheme.primary),
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

class CategoryManagerScreen extends StatelessWidget {
  final AppDatabase db;
  const CategoryManagerScreen({super.key, required this.db});

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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok == true) {
      final res = await db.createCategory(ctrl.text);

      if (!context.mounted) return;
      final msg = switch (res) {
        CreateCategoryResult.created => 'Kategorie erstellt ✅',
        CreateCategoryResult.restored => 'Kategorie wiederhergestellt ✅',
        CreateCategoryResult.alreadyExists => 'Kategorie existiert bereits.',
        _ => 'Ungültiger Name.',
      };

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _edit(BuildContext context, CategoryEntry cat) async {
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
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok == true) {
      await db.renameCategory(cat.id, ctrl.text);
    }
  }

  Future<void> _delete(BuildContext context, CategoryEntry cat, List<CategoryEntry> allCats) async {
  final count = await db.countActiveTransactionsForCategory(cat.id);

  // Zielkategorien (nicht die zu löschende)
  final targets = allCats.where((c) => c.id != cat.id).toList();

  // Default target: "Allgemein" (oder erste verfügbare)
  final defaultTarget = targets.firstWhere(
  (c) => c.name.toLowerCase() == 'allgemein',
  orElse: () => targets.isNotEmpty ? targets.first : cat, // placeholder; wird unten abgefangen
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
              Text('„${cat.name}“ enthält $count Buchungen. Was soll damit passieren?'),
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
                      value: (moveTargetId != null && targets.any((c) => c.id == moveTargetId))
                      ? moveTargetId
                          : (targets.isNotEmpty ? targets.first.id : null),
                      items: targets
                          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
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
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Abbrechen')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Löschen')),
          ],
        );
      },
    ),
  );

  if (ok != true) return;

  await db.transaction(() async {
  // 1) Policy anwenden
    if (count > 0) {
      if (policy == _DeleteCatPolicy.deleteEntries) {
        await db.softDeleteActiveTransactionsForCategory(cat.id);
      } else if (policy == _DeleteCatPolicy.archive) {
        final archive = await db.ensureCategoryActiveByName('Archiv');
        await db.moveActiveTransactionsToCategory(
          fromCategoryId: cat.id,
          toCategoryId: archive.id,
          toCategoryNameSnapshot: archive.name,
        );
      } else {
        // move
        // Falls es keine Zielkategorie gab, stelle "Allgemein" sicher und nutze die.
        CategoryEntry target;
        if (moveTargetId == null) {
          target = await db.ensureCategoryActiveByName('Allgemein');
        } else {
          target = targets.firstWhere((c) => c.id == moveTargetId);
        }

        await db.moveActiveTransactionsToCategory(
          fromCategoryId: cat.id,
          toCategoryId: target.id,
          toCategoryNameSnapshot: target.name,
        );
      }
    }
    // 2) Kategorie selbst soft-deleten
    await db.softDeleteCategory(cat.id);
  });

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kategorie gelöscht ✅')),
    );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategorien'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              final backup = BackupService(db);

              if (v == 'export') {
                await backup.shareLatestBackup();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backup exportiert ✅')),
                );
              }

              if (v == 'import') {
                final ok = await backup.importJsonBackupFromPicker(replaceLocal: true);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ok ? 'Import abgeschlossen ✅' : 'Import abgebrochen/fehlgeschlagen ❌')),
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
      body: StreamBuilder<List<CategoryEntry>>(
        stream: db.watchActiveCategories(),
        builder: (context, snap) {
          final cats = (snap.data ?? const <CategoryEntry>[])
              .toList()
            ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          if (cats.isEmpty) {
            return const Center(child: Text('Noch keine Kategorien.\nTippe auf „Kategorie“ zum Hinzufügen. ✨'));
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12), // Platz für FAB
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final c = cats[i];
              final bg = _pastelByIndex(i, cats.length);
              final fg = _onPastel(bg);
              final letter = c.name.trim().isEmpty ? '?' : c.name.trim()[0].toUpperCase();

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Card(
                  color: bg,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    title: Text(
                      c.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: fg,
                      ),
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

