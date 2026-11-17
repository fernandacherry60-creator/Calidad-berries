import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EquipoNubeScreen extends StatefulWidget {
  const EquipoNubeScreen({super.key});
  @override
  State<EquipoNubeScreen> createState() => _EquipoNubeScreenState();
}
class _EquipoNubeScreenState extends State<EquipoNubeScreen> {
  List<Map<String, dynamic>> _equipo = [];
  bool _busy = false;
  String? _error;
  String? _codigo;
  @override
  void initState() { super.initState(); _cargar(); }
  Future<void> _cargar() async {
    try {
      final rows = await Supabase.instance.client.from('cb_profiles')
          .select('email,display_name,puesto,role,active').order('display_name');
      if (mounted) setState(() => _equipo = List<Map<String,dynamic>>.from(rows));
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo consultar el equipo: $e');
    }
  }
  Future<void> _invitar() async {
    setState(() { _busy = true; _error = null; });
    try {
      const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
      final rng = Random.secure();
      final code = List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw StateError('Inicia sesión');
      await Supabase.instance.client.from('cb_invitations').insert({
        'code': code, 'created_by': user.id,
        'expires_at': DateTime.now().toUtc().add(const Duration(days: 7)).toIso8601String(),
      });
      if (mounted) setState(() => _codigo = code);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo crear invitación: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Equipo en la nube'),
      actions: [IconButton(onPressed: _cargar, icon: const Icon(Icons.refresh))]),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('Invita trabajadores desde tu teléfono. Cada persona instala la app, confirma su correo y registra el código de acceso.'),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: _busy ? null : _invitar,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Crear invitación de trabajador')),
      if (_codigo != null) Card(child: ListTile(
        title: SelectableText(_codigo!, style: const TextStyle(fontSize: 22,fontWeight: FontWeight.bold)),
        subtitle: const Text('Vigente por 7 días, un solo uso. Comparte el código de forma privada.'),
        trailing: IconButton(icon: const Icon(Icons.copy), onPressed: () =>
          Clipboard.setData(ClipboardData(text: _codigo!))),
      )),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 20),
      Text('Personal registrado: ${_equipo.length}',
        style: Theme.of(context).textTheme.titleLarge),
      for (final p in _equipo) Card(child: ListTile(
        leading: Icon(p['role'] == 'admin' ? Icons.admin_panel_settings : Icons.person),
        title: Text(p['display_name']?.toString() ?? ''),
        subtitle: Text('${p['email']} · ${p['puesto']}'),
        trailing: Icon(p['active'] == true ? Icons.check_circle : Icons.block,
          color: p['active'] == true ? Colors.green : Colors.grey),
      )),
    ]),
  );
}
