import 'package:flutter/material.dart';

import 'app/app.dart';
import 'data/remote/pocketbase/pocketbase_auth_service.dart';
import 'data/remote/pocketbase/pocketbase_client.dart';

export 'app/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final pocketBaseClient = await createPocketBaseClient();

  final pocketBaseAuthService = PocketBaseAuthService(pocketBaseClient);

  runApp(HaushaltsplanerApp(pocketBaseAuthService: pocketBaseAuthService));
}
