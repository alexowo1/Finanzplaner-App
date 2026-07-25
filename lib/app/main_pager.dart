import 'package:flutter/material.dart';

import '../backup/backup_service.dart';
import '../data/repositories/finance_repository.dart';
import '../features/home/home_screen.dart';
import '../features/stats/stats_screen.dart';

class MainPager extends StatefulWidget {
  final FinanceRepository repository;
  final BackupService backupService;

  const MainPager({
    super.key,
    required this.repository,
    required this.backupService,
  });

  @override
  State<MainPager> createState() => _MainPagerState();
}

class _MainPagerState extends State<MainPager> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _go(int i) async {
    await _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Stack(
      children: [
        PageView(
          controller: _controller,
          onPageChanged: (i) => setState(() => _index = i),
          children: [
            HomeScreen(
              repository: widget.repository,
              backupService: widget.backupService,
            ),
            StatsScreen(repository: widget.repository),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _IndicatorBar(
                  active: _index == 0,
                  activeColor: cs.primary,
                  inactiveColor: cs.outlineVariant.withOpacity(0.6),
                  onTap: () => _go(0),
                ),
                const SizedBox(width: 10),
                _IndicatorBar(
                  active: _index == 1,
                  activeColor: cs.primary,
                  inactiveColor: cs.outlineVariant.withOpacity(0.6),
                  onTap: () => _go(1),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _IndicatorBar extends StatelessWidget {
  final bool active;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _IndicatorBar({
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: active ? 34 : 22,
        height: 5,
        decoration: BoxDecoration(
          color: active ? activeColor : inactiveColor,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}
