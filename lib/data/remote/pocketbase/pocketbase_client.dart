import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_config.dart';

const String _authStorageKey = 'pocketbase_auth';

Future<PocketBase> createPocketBaseClient() async {
  final storage = FlutterSecureStorage();

  final initialAuth = await storage.read(key: _authStorageKey);

  final authStore = AsyncAuthStore(
    initial: initialAuth,
    save: (String data) {
      return storage.write(key: _authStorageKey, value: data);
    },
    clear: () {
      return storage.delete(key: _authStorageKey);
    },
  );

  return PocketBase(
    PocketBaseConfig.baseUrl,
    authStore: authStore,
    lang: 'de-DE',
    reuseHTTPClient: true,
  );
}
