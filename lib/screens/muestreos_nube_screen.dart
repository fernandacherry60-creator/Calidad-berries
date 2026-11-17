import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lectura de registros del equipo; Supabase RLS permite todos al admin
/// y únicamente los propios al trabajador.
class MuestreosNubeScreen extends StatefulWidget {
  const MuestreosNubeScreen({super.key});
  @override
  State<MuestreosNubeScreen> createState() => _MuestreosNubeScreenState();
}
class _MuestreosNubeScreenState extends State<MuestreosNubeScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  @override
  void initState() { super.initState(); _refresh(); }
  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final client = Supabase.instance.client;
      final tables = <String, String>{
        'muestreos_anden': 'Andén',
        'muestreos_proceso': 'Proceso',
        'semaforo': 'Semáforo',
      };
      final all = <Map<String,dynamic>>[];
      for (final e in tables.entries) {
        final rows = await client.from(e.key)
          .select('uuid,fecha,cultivo,usuario_nombre,usuario_email')
          .order('fecha', ascending: false).limit(100);
        for (final row in rows) {
          all.add({...row, 'tipo': e.value});
        }
      }
      all.sort((a,b) => (b['fecha']?.toString() ?? '')
        .compareTo(a['fecha']?.toString() ?? ''));
      if (mounted) setState(() => _items = all);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron consultar muestreos: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Muestreos en la nube'),
      actions: [IconButton(icon: const Icon(Icons.refresh),onPressed: _refresh)]),
    body: _loading ? const Center(child: CircularProgressIndicator())
      : _error != null ? Center(child: Padding(
        padding: const EdgeInsets.all(20), child: Text(_error!)))
      : _items.isEmpty ? const Center(child: Text('Todavía no hay muestreos sincronizados'))
      : ListView.builder(
        padding: const EdgeInsets.all(12), itemCount: _items.length,
        itemBuilder: (context,i) {
          final item = _items[i];
          return Card(child: ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text('${item['tipo']} · ${item['cultivo']}'),
            subtitle: Text('${item['usuario_nombre'] ?? item['usuario_email'] ?? 'Sin nombre'}\n${item['fecha']}'),
            isThreeLine: true,
          ));
        },
      ),
  );
}
