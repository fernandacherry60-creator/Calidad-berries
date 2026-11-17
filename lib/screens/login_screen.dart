import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import 'register_screen.dart';
import 'activar_duena_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _usuario = TextEditingController();
  final _password = TextEditingController();
  bool _ocultar = true;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _usuario.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final auth = context.read<AuthService>();
    final error = await auth.login(_usuario.text, _password.text);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error = error;
    });
    // Si requiere cambio de contrasena, el enrutador de main.dart
    // mostrara la pantalla dedicada.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 30),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Column(children: [
                      Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(Icons.spa_rounded,
                            size: 48, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      const Text('Calidad Berries',
                        style: TextStyle(fontSize: 27,
                          fontWeight: FontWeight.w800, color: Colors.white)),
                      const SizedBox(height: 6),
                      const Text('Control de calidad en tus manos',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 14)),
                    ]),
                  ),
                  const SizedBox(height: 28),
                  Text('Bienvenido de nuevo',
                    style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Ingresa con tu cuenta para continuar.',
                    style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: _usuario,
                    autofillHints: const [AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Correo',
                        prefixIcon: Icon(Icons.mail_outline)),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Escribe tu correo' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _ocultar,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _entrar(),
                    decoration: InputDecoration(
                      labelText: 'Contrasena',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _ocultar ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _ocultar = !_ocultar),
                        tooltip: _ocultar ? 'Mostrar' : 'Ocultar',
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Escribe tu contrasena' : null,
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_error!,
                          style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _cargando ? null : _entrar,
                    child: _cargando
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : const Row(mainAxisAlignment: MainAxisAlignment.center,
                            children: [Icon(Icons.login_rounded, size: 21),
                              SizedBox(width: 10), Text('Iniciar sesión')]),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen())),
                    child: const Text('Crear cuenta con codigo de ingreso'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ActivarDuenaScreen())),
                    child: const Text('Activar cuenta de la dueña'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Funciona sin internet: tus muestreos se guardan en el equipo y se envian al recuperar senal.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
