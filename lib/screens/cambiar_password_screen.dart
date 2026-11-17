import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';

/// Cambio de contrasena obligatorio (primer inicio del admin).
/// Pantalla completa con validaciones y errores visibles.
class CambiarPasswordScreen extends StatefulWidget {
  const CambiarPasswordScreen({super.key});

  @override
  State<CambiarPasswordScreen> createState() => _CambiarPasswordScreenState();
}

class _CambiarPasswordScreenState extends State<CambiarPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _nueva = TextEditingController();
  final _confirmar = TextEditingController();
  bool _ocultar = true;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _nueva.dispose();
    _confirmar.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    // No se pide la contrasena actual: a esta pantalla solo se llega tras un
    // login valido (contrasena de fabrica o temporal del administrador).
    final error = await context
        .read<AuthService>()
        .definirPasswordObligatoria(_nueva.text);
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error = error;
    });
    // Si error == null, AuthService notifica y el enrutador de main.dart
    // pasa automaticamente al inicio.
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
                  const Icon(Icons.lock_reset,
                      size: 56, color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text('Cambia tu contrasena',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Por seguridad, debes definir una contrasena propia antes de continuar.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _nueva,
                    obscureText: _ocultar,
                    decoration: InputDecoration(
                      labelText: 'Nueva contrasena (min. 8 caracteres)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_ocultar
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _ocultar = !_ocultar),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 8)
                        ? 'Minimo 8 caracteres'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmar,
                    obscureText: _ocultar,
                    onFieldSubmitted: (_) => _guardar(),
                    decoration: const InputDecoration(
                      labelText: 'Confirmar contrasena',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) => v != _nueva.text
                        ? 'Las contrasenas no coinciden'
                        : null,
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
                    onPressed: _cargando ? null : _guardar,
                    child: _cargando
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white))
                        : const Text('Guardar y continuar'),
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
