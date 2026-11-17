import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';

/// Registro de cuenta. Requiere un codigo de ingreso vigente (de un solo
/// uso) generado por el administrador: sin codigo, nadie entra.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _codigo = TextEditingController();
  String? _puesto;
  bool _ocultar = true;
  bool _cargando = false;
  String? _error;

  @override
  void dispose() {
    _nombre.dispose();
    _email.dispose();
    _password.dispose();
    _codigo.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _cargando = true;
      _error = null;
    });
    final error = await context.read<AuthService>().registrar(
          nombre: _nombre.text,
          email: _email.text,
          password: _password.text,
          codigo: _codigo.text,
          puesto: _puesto ?? '',
        );
    if (!mounted) return;
    setState(() {
      _cargando = false;
      _error = error;
    });
    if (error == null) {
      // Sesion iniciada; el enrutador de main.dart mostrara el inicio.
      Navigator.popUntil(context, (r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.okBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Necesitas un codigo de ingreso proporcionado por el administrador. Cada codigo sirve una sola vez.',
                    style: TextStyle(
                        color: AppColors.ok, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _codigo,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                      labelText: 'Codigo de ingreso',
                      prefixIcon: Icon(Icons.vpn_key_outlined)),
                  validator: (v) => (v == null || v.trim().length < 6)
                      ? 'Escribe el codigo de 6 caracteres'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: 'Nombre completo',
                      prefixIcon: Icon(Icons.person_outline)),
                  validator: (v) => (v == null || v.trim().length < 3)
                      ? 'Escribe tu nombre'
                      : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _puesto,
                  decoration: const InputDecoration(
                      labelText: 'Puesto',
                      prefixIcon: Icon(Icons.badge_outlined)),
                  items: [
                    for (final pu in kPuestos)
                      DropdownMenuItem(value: pu, child: Text(pu))
                  ],
                  onChanged: (v) => setState(() => _puesto = v),
                  validator: (v) =>
                      v == null ? 'Selecciona tu puesto' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(
                      labelText: 'Correo',
                      prefixIcon: Icon(Icons.mail_outline)),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Escribe tu correo';
                    }
                    if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.]+$')
                        .hasMatch(v.trim())) {
                      return 'El correo no es valido';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  obscureText: _ocultar,
                  decoration: InputDecoration(
                    labelText: 'Contrasena (min. 8 caracteres)',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _ocultar ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _ocultar = !_ocultar),
                      tooltip: _ocultar ? 'Mostrar' : 'Ocultar',
                    ),
                  ),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'Minimo 8 caracteres'
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
                  onPressed: _cargando ? null : _crear,
                  child: _cargando
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Crear cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
