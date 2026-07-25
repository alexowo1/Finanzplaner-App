import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/models/finance_transaction.dart';
import '../../data/repositories/finance_repository.dart';

class StatsScreen extends StatelessWidget {
  final FinanceRepository repository;
  const StatsScreen({super.key, required this.repository});

  String _iso(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  DateTime _monthStart(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _nextMonthStart(DateTime d) => DateTime(d.year, d.month + 1, 1);

  String _monthKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}';

  DateTime _parseIsoDate(String iso) {
    final p = iso.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  String _fmtEuro(int cents) {
    final abs = cents.abs();
    final euros = abs ~/ 100;
    final rest = abs % 100;
    final sign = cents < 0 ? '-' : '';
    return '$sign$euros,${rest.toString().padLeft(2, '0')} €';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final endExclusive = _nextMonthStart(now);
    final start6 = DateTime(endExclusive.year, endExclusive.month - 6, 1);

    final stream = repository.watchActiveTransactionsInRange(
      startIsoInclusive: _iso(start6),
      endIsoExclusive: _iso(endExclusive),
      categoryId: null,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiken')),
      body: StreamBuilder<List<FinanceTransaction>>(
        stream: stream,
        builder: (context, snap) {
          final items = snap.data ?? const <FinanceTransaction>[];
          if (items.isEmpty) {
            return const Center(
              child: Text('Noch keine Daten für Statistiken.'),
            );
          }

          // Months list (last 6 months incl current)
          final months = List.generate(6, (i) {
            final d = DateTime(
              endExclusive.year,
              endExclusive.month - (5 - i),
              1,
            );
            return d;
          });
          final incomeByMonth = {for (final m in months) _monthKey(m): 0};
          final expenseByMonth = {for (final m in months) _monthKey(m): 0};

          // Pie (current month) by category (expenses)
          final thisMonthStart = _monthStart(now);
          final thisMonthKey = _monthKey(thisMonthStart);
          final expenseByCategory = <String, int>{};

          for (final t in items) {
            final d = _parseIsoDate(t.date);
            final key = _monthKey(DateTime(d.year, d.month, 1));

            if (incomeByMonth.containsKey(key) ||
                expenseByMonth.containsKey(key)) {
              if (t.type == 'income') {
                incomeByMonth[key] = (incomeByMonth[key] ?? 0) + t.amountCents;
              } else {
                expenseByMonth[key] =
                    (expenseByMonth[key] ?? 0) + t.amountCents;
              }
            }

            // pie only for current month + expenses
            if (key == thisMonthKey && t.type == 'expense') {
              final cat = (t.categoryId != null && t.categoryId!.isNotEmpty)
                  ? t
                        .category // Snapshot-Name reicht hier
                  : t.category;
              expenseByCategory[cat] =
                  (expenseByCategory[cat] ?? 0) + t.amountCents;
            }
          }

          final monthIncome = incomeByMonth[thisMonthKey] ?? 0;
          final monthExpense = expenseByMonth[thisMonthKey] ?? 0;
          final monthBalance = monthIncome - monthExpense;

          final cs = Theme.of(context).colorScheme;

          // Build BarChart groups
          final barGroups = <BarChartGroupData>[];
          for (int i = 0; i < months.length; i++) {
            final k = _monthKey(months[i]);
            final inc = (incomeByMonth[k] ?? 0) / 100.0;
            final exp = (expenseByMonth[k] ?? 0) / 100.0;

            barGroups.add(
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: inc,
                    width: 7,
                    color: cs.tertiary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  BarChartRodData(
                    toY: exp,
                    width: 7,
                    color: cs.error,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
                barsSpace: 6,
              ),
            );
          }

          // Pie sections (Top 6 + "Andere")
          final entries = expenseByCategory.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));

          final top = entries.take(6).toList();
          final restSum = entries.skip(6).fold<int>(0, (s, e) => s + e.value);

          final pieColors = [
            cs.primaryContainer,
            cs.secondaryContainer,
            cs.tertiaryContainer,
            cs.errorContainer,
            cs.surfaceContainerHighest,
            cs.inversePrimary,
            cs.surfaceVariant,
          ];

          final pieSections = <PieChartSectionData>[];
          int colorIndex = 0;
          for (final e in top) {
            pieSections.add(
              PieChartSectionData(
                value: e.value.toDouble(),
                title: '',
                radius: 55,
                color: pieColors[colorIndex % pieColors.length],
              ),
            );
            colorIndex++;
          }
          if (restSum > 0) {
            pieSections.add(
              PieChartSectionData(
                value: restSum.toDouble(),
                title: '',
                radius: 55,
                color: cs.outlineVariant,
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Kpi(
                        label: 'Einnahmen (Monat)',
                        value: _fmtEuro(monthIncome),
                      ),
                      _Kpi(
                        label: 'Ausgaben (Monat)',
                        value: _fmtEuro(monthExpense),
                      ),
                      _Kpi(
                        label: 'Saldo (Monat)',
                        value: _fmtEuro(monthBalance),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Letzte 6 Monate',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 220,
                        child: BarChart(
                          BarChartData(
                            barGroups: barGroups,
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 44,
                                  getTitlesWidget: (value, meta) =>
                                      Text('${value.toInt()}€'),
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final i = value.toInt();
                                    if (i < 0 || i >= months.length)
                                      return const SizedBox.shrink();
                                    final m = months[i];
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Text('${m.month}.${m.year % 100}'),
                                    );
                                  },
                                ),
                              ),
                            ),
                            gridData: const FlGridData(show: true),
                            borderData: FlBorderData(show: false),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _LegendDot(color: cs.tertiary, label: 'Einnahmen'),
                          const SizedBox(width: 12),
                          _LegendDot(color: cs.error, label: 'Ausgaben'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ausgaben nach Kategorie (dieser Monat)',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 220,
                        child: PieChart(
                          PieChartData(
                            sections: pieSections,
                            centerSpaceRadius: 40,
                            sectionsSpace: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...top.map(
                        (e) => Text('• ${e.key}: ${_fmtEuro(e.value)}'),
                      ),
                      if (restSum > 0) Text('• Andere: ${_fmtEuro(restSum)}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28), // etwas Platz über dem Indicator
            ],
          );
        },
      ),
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

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
