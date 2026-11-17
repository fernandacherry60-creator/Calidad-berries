import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'screens/cambiar_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'services/remote_config_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseKey);
  final auth = AuthService();
  final sync = SyncService();
  final remoteConfig = RemoteConfigService();
  await auth.init();
  await sync.init();
  await remoteConfig.init();
  if (auth.autenticado) {
    unawaited(sync.sincronizar());
  }
  auth.addListener(() {
    if (auth.autenticado) {
      sync.sincronizar();
      unawaited(remoteConfig.refresh());
    }
  });
  runApp(CalidadBerriesApp(auth: auth, sync: sync, remoteConfig: remoteConfig));
}

class CalidadBerriesApp extends StatelessWidget {
  final AuthService auth;
  final SyncService sync;
  final RemoteConfigService remoteConfig;
  const CalidadBerriesApp({super.key, required this.auth, required this.sync, required this.remoteConfig});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: sync),
        ChangeNotifierProvider.value(value: remoteConfig),
      ],
      child: MaterialApp(
        title: 'Calidad Berries Pro',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Consumer<AuthService>(
          builder: (_, a, __) {
            if (!a.autenticado) return const LoginScreen();
            if (a.requiereCambioPassword) {
              return const CambiarPasswordScreen();
            }
            return const HomeScreen();
          },
        ),
      ),
    );
  }
}
