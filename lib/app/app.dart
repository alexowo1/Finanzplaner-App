import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart';

import '../backup/backup_service.dart';
import '../backup/backup_service_factory.dart';
import '../data/repositories/drift_finance_repository.dart';
import '../db/database.dart';
import 'main_pager.dart';

import '../data/remote/pocketbase/pocketbase_auth_service.dart';
import '../features/auth/login_screen.dart';

import 'dart:async';

import '../data/remote/pocketbase/pocketbase_finance_repository.dart';

class HaushaltsplanerApp extends StatefulWidget {
  const HaushaltsplanerApp({required this.pocketBaseAuthService, super.key});

  final PocketBaseAuthService pocketBaseAuthService;

  @override
  State<HaushaltsplanerApp> createState() => _HaushaltsplanerAppState();
}

class _HaushaltsplanerAppState extends State<HaushaltsplanerApp> {
  late final AppDatabase db = AppDatabase();
  late final DriftFinanceRepository repository = DriftFinanceRepository(db);
  late final BackupService backupService = createBackupService(db);
  late final Future<bool> _serverCheck;
  PocketBaseAuthService get pocketBaseAuthService =>
      widget.pocketBaseAuthService;

  @override
  void initState() {
    super.initState();
    _serverCheck = _checkServerConnection();
  }

  Future<bool> _checkServerConnection() async {
    try {
      await pocketBaseAuthService.checkConnection();

      debugPrint(
        'Server erreichbar: '
        '${pocketBaseAuthService.client.baseURL}',
      );

      if (pocketBaseAuthService.isAuthenticated) {
        final sessionIsValid = await pocketBaseAuthService.refreshSession();

        debugPrint(
          sessionIsValid
              ? 'Gespeicherte Anmeldung ist gültig.'
              : 'Gespeicherte Anmeldung ist nicht mehr gültig.',
        );
      }

      return true;
    } catch (error) {
      debugPrint('Server derzeit nicht erreichbar: $error');

      return false;
    }
  }

  @override
  void dispose() {
    pocketBaseAuthService.close();
    if (!kIsWeb) {
      db.close();
    }
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
      //home: MainPager(repository: repository, backupService: backupService),
      home: kIsWeb
          ? _ServerStatusScreen(
              serverCheck: _serverCheck,
              authService: pocketBaseAuthService,
            )
          : MainPager(repository: repository, backupService: backupService),
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

class _ServerStatusScreen extends StatelessWidget {
  const _ServerStatusScreen({
    required this.serverCheck,
    required this.authService,
  });

  final Future<bool> serverCheck;
  final PocketBaseAuthService authService;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: serverCheck,
      builder: (context, serverSnapshot) {
        if (serverSnapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Serververbindung wird geprüft …'),
                ],
              ),
            ),
          );
        }

        final serverReachable = serverSnapshot.data ?? false;

        if (!serverReachable) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined, size: 48),
                  SizedBox(height: 16),
                  Text('Server derzeit nicht erreichbar'),
                  SizedBox(height: 8),
                  Text('Prüfe Tailscale und den Serverstatus.'),
                ],
              ),
            ),
          );
        }

        return StreamBuilder<Object>(
          stream: authService.authChanges,
          builder: (context, authSnapshot) {
            if (!authService.isAuthenticated) {
              return LoginScreen(authService: authService);
            }

            return _AuthenticatedWebHome(authService: authService);
          },
        );
      },
    );
  }
}

class _AuthenticatedWebHome extends StatefulWidget {
  const _AuthenticatedWebHome({required this.authService});

  final PocketBaseAuthService authService;

  @override
  State<_AuthenticatedWebHome> createState() => _AuthenticatedWebHomeState();
}

class _AuthenticatedWebHomeState extends State<_AuthenticatedWebHome> {
  late final Future<PocketBaseFinanceRepository> _repositoryFuture;

  PocketBaseFinanceRepository? _repository;

  @override
  void initState() {
    super.initState();
    _repositoryFuture = _createRepository();
  }

  Future<PocketBaseFinanceRepository> _createRepository() async {
    final repository = await PocketBaseFinanceRepository.create(
      widget.authService.client,
    );

    if (!mounted) {
      await repository.dispose();
    } else {
      _repository = repository;
    }

    return repository;
  }

  @override
  void dispose() {
    final repository = _repository;

    if (repository != null) {
      unawaited(repository.dispose());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PocketBaseFinanceRepository>(
      future: _repositoryFuture,
      builder: (context, repositorySnapshot) {
        if (repositorySnapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (repositorySnapshot.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Haushaltsplaner'),
              actions: [
                TextButton.icon(
                  onPressed: widget.authService.signOut,
                  icon: const Icon(Icons.logout),
                  label: const Text('Abmelden'),
                ),
              ],
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Serverdaten konnten nicht geladen werden:\n'
                  '${repositorySnapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final repository = repositorySnapshot.requireData;

        return MainPager(
          repository: repository,
          backupService: null,
          onSignOut: widget.authService.signOut,
        );
      },
    );
  }
}
