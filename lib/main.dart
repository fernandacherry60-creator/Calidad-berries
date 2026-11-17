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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseKey);
  final auth = AuthService();
  final sync = SyncService();
  await auth.init();
  await sync.init();
  runApp(CalidadBerriesApp(auth: auth, sync: sync));
}

class CalidadBerriesApp extends StatelessWidget {
  final AuthService auth;
  final SyncService sync;
  const CalidadBerriesApp({super.key, required this.auth, required this.sync});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: sync),
      ],
      child: MaterialApp(
        title: 'Calidad Berries',
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
