import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../backup/backup_service.dart';
import '../data/repositories/drift_finance_repository.dart';
import '../db/database.dart';
import 'main_pager.dart';

class HaushaltsplanerApp extends StatefulWidget {
  const HaushaltsplanerApp({super.key});

  @override
  State<HaushaltsplanerApp> createState() => _HaushaltsplanerAppState();
}

class _HaushaltsplanerAppState extends State<HaushaltsplanerApp> {
  late final AppDatabase db = AppDatabase();
  late final DriftFinanceRepository repository = DriftFinanceRepository(db);
  late final BackupService backupService = BackupService(db);

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
        canvasColor: bg,
        appBarTheme: AppBarTheme(
          backgroundColor: bg,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
      ),
      home: MainPager(repository: repository, backupService: backupService),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('de', 'DE'), Locale('en', 'US')],
      locale: const Locale('de', 'DE'),
    );
  }
}
