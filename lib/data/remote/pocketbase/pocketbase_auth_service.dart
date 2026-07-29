import 'package:pocketbase/pocketbase.dart';

import 'pocketbase_config.dart';

class PocketBaseAuthService {
  PocketBaseAuthService(this._client);

  final PocketBase _client;

  PocketBase get client => _client;

  bool get isAuthenticated => _client.authStore.isValid;

  String? get currentUserId => _client.authStore.record?.id;

  String? get currentUserEmail =>
      _client.authStore.record?.get<String>('email');

  Stream<AuthStoreEvent> get authChanges => _client.authStore.onChange;

  Future<void> checkConnection() async {
    await _client.health.check();
  }

  Future<void> signIn({required String email, required String password}) async {
    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail.isEmpty || password.isEmpty) {
      throw ArgumentError(
        'E-Mail-Adresse und Passwort dürfen nicht leer sein.',
      );
    }

    await _client
        .collection(PocketBaseConfig.usersCollection)
        .authWithPassword(normalizedEmail, password);
  }

  Future<bool> refreshSession() async {
    if (!_client.authStore.isValid) {
      _client.authStore.clear();
      return false;
    }

    try {
      await _client.collection(PocketBaseConfig.usersCollection).authRefresh();

      return true;
    } on ClientException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        _client.authStore.clear();
        return false;
      }

      // Bei ausgeschaltetem Server oder Netzwerkproblemen bleibt das
      // vorhandene Token erhalten.
      rethrow;
    }
  }

  void signOut() {
    _client.authStore.clear();
  }

  void close() {
    _client.close();
  }
}
