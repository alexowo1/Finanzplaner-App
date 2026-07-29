import 'package:flutter/foundation.dart';

abstract final class PocketBaseConfig {
  static const String _configuredBaseUrl = String.fromEnvironment(
    'POCKETBASE_URL',
  );

  static const String _nativeDefaultBaseUrl =
      'https://pocketbase-t150.tail0ab1e9.ts.net';

  static const String usersCollection = 'users';
  static const String categoriesCollection = 'categories';
  static const String transactionsCollection = 'transactions';

  static String get baseUrl {
    final String resolvedUrl;

    if (_configuredBaseUrl.isNotEmpty) {
      resolvedUrl = _configuredBaseUrl;
    } else if (kIsWeb && kReleaseMode) {
      // Die später auf dem Server gehostete Web-App verwendet
      // denselben Origin wie PocketBase.
      resolvedUrl = Uri.base.origin;
    } else {
      // Native App und lokale Webentwicklung verwenden
      // direkt die Tailscale-Adresse.
      resolvedUrl = _nativeDefaultBaseUrl;
    }

    return resolvedUrl.replaceFirst(RegExp(r'/+$'), '');
  }
}
