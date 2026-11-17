import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ActivarDuenaScreen extends StatefulWidget {
  const ActivarDuenaScreen({super.key});
  @override
  State<ActivarDuenaScreen> createState() => _ActivarDuenaScreenState();
}
class _ActivarDuenaScreenState extends State<ActivarDuenaScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _mensaje;
  @override
  void dispose() { _password.dispose(); super.dispose(); }
  Future<void> _activar() async {
    if (_password.text.length < 8) {
      setState(() => _mensaje = 'Utiliza al menos 8 caracteres.');
      return;
    }
    setState(() { _busy = true; _mensaje = null; });
    try {
      await Supabase.instance.client.auth.signUp(
        email: 'fernanda.var.pre@gmail.com',
        password: _password.text,
        emailRedirectTo: 'calidadberriespro://auth-callback',
      );
      if (mounted) setState(() => _mensaje =
          'Revisa el correo de Fernanda y abre el enlace de confirmación en este teléfono. Luego inicia sesión.');
    } on AuthException catch (e) {
      if (mounted) setState(() => _mensaje = e.message);
    } catch (_) {
      if (mounted) setState(() => _mensaje = 'No se pudo solicitar la invitación.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Activar cuenta de la dueña')),
    body: SafeArea(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Icon(Icons.verified_user_outlined, size: 56),
        const SizedBox(height: 16),
        const Text('Fernanda.var.pre@gmail.com',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text('Crea tu contraseña y confirma el correo recibido. El enlace abrirá Calidad Berries Pro si está instalada.'),
        const SizedBox(height: 20),
        TextField(controller: _password, obscureText: true,
          decoration: const InputDecoration(labelText: 'Nueva contraseña')),
        const SizedBox(height: 16),
        FilledButton(onPressed: _busy ? null : _activar,
          child: Text(_busy ? 'Enviando...' : 'Enviar enlace de activación')),
        if (_mensaje != null) Padding(padding: const EdgeInsets.only(top: 16),
          child: Text(_mensaje!)),
      ]),
    )),
  );
}
