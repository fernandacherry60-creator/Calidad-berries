import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../data/repositories.dart';
import 'equipo_nube_screen.dart';

/// Catálogos locales. Las cuentas e invitaciones viven exclusivamente en Supabase.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}
class _AdminScreenState extends State<AdminScreen> {
  final _catalogos = CatalogoRepo();
  Future<void> _nuevoRancho() async {
    final nombre = TextEditingController();
    await _dialogoSimple('Nuevo rancho', [
      TextField(
          controller: nombre,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Nombre del rancho')),
    ], () async {
      if (nombre.text.trim().isEmpty) return;
      await _catalogos.agregarRancho(nombre.text);
    });
  }

  Future<void> _nuevaVariedad() async {
    String cultivo = kCultivos.first;
    final nombre = TextEditingController();
    await _dialogoSimple('Nueva variedad', [
      DropdownButtonFormField<String>(
        value: cultivo,
        decoration: const InputDecoration(labelText: 'Cultivo'),
        items: [
          for (final c in kCultivos) DropdownMenuItem(value: c, child: Text(c))
        ],
        onChanged: (v) => cultivo = v ?? cultivo,
      ),
      const SizedBox(height: 12),
      TextField(
          controller: nombre,
          decoration: const InputDecoration(labelText: 'Nombre de variedad')),
    ], () async {
      if (nombre.text.trim().isEmpty) return;
      await _catalogos.agregarVariedad(cultivo, nombre.text);
    });
  }

  Future<void> _dialogoSimple(String titulo, List<Widget> campos,
      Future<void> Function() onGuardar) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: campos),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 20)),
            onPressed: () async {
              await onGuardar();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Administración')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Card(child: ListTile(
        leading: const Icon(Icons.cloud_outlined),
        title: const Text('Trabajadores en la nube'),
        subtitle: const Text('Crear invitaciones y consultar el equipo'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const EquipoNubeScreen())),
      )),
      const SizedBox(height: 16),
      Text('Catálogos de este dispositivo',
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 8),
      const Text('Los cambios de catálogos aquí todavía son locales; no se comparten entre teléfonos.'),
      Card(child: Column(children: [
        ListTile(
          leading: const Icon(Icons.agriculture_outlined),
          title: const Text('Agregar rancho'),
          trailing: const Icon(Icons.add),
          onTap: _nuevoRancho,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.spa_outlined),
          title: const Text('Agregar variedad'),
          trailing: const Icon(Icons.add),
          onTap: _nuevaVariedad,
        ),
      ])),
    ]),
  );
}
