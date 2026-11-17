import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import '../services/auth_service.dart';
import '../widgets/common.dart';

/// Administracion (solo rol admin): alta de usuarios y de catalogos.
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _catalogos = CatalogoRepo();
  List<AppUser> _usuarios = [];
  String _rolCodigo = 'usuario';
  String? _ultimoCodigo;

  /// Administrador con la sesion abierta (no puede restablecerse a si mismo).
  AppUser? _yo;

  /// Restablece la contrasena de una persona de ESTE telefono y muestra la
  /// temporal para dictarsela. Al entrar, la app la obliga a definir la suya.
  Future<void> _resetearPassword(AppUser u) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restablecer contrasena'),
        content: Text(
            'Se generara una contrasena temporal para ${u.displayName}. '
            'La contrasena actual dejara de funcionar y al entrar tendra que '
            'crear una nueva.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 20)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restablecer'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    final temporal =
        await context.read<AuthService>().resetearPassword(u.id);
    if (!mounted) return;
    if (temporal == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo restablecer la contrasena')));
      return;
    }
    await _mostrarTemporal(u, temporal);
  }

  Future<void> _mostrarTemporal(AppUser u, String temporal) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Contrasena temporal'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Entregasela a ${u.displayName}. Al iniciar sesion con '
                  'ella, la app le pedira crear su propia contrasena.'),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.okBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(temporal,
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: AppColors.ok)),
                    ),
                    IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy, color: AppColors.ok),
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: temporal));
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Anotala antes de cerrar: no se vuelve a mostrar.',
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 20)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  Future<void> _generarCodigo() async {
    final code =
        await context.read<AuthService>().generarCodigo(_rolCodigo);
    if (!mounted) return;
    setState(() => _ultimoCodigo = code);
  }

  @override
  void initState() {
    super.initState();
    _yo = context.read<AuthService>().usuario;
    _cargar();
  }

  Future<void> _cargar() async {
    final u = await context.read<AuthService>().listarUsuarios();
    if (!mounted) return;
    setState(() => _usuarios = u);
  }

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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Administracion')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const TituloSeccion('Usuarios'),
          Card(
            child: Column(
              children: [
                for (final u in _usuarios)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      child: Icon(
                          u.esAdmin
                              ? Icons.admin_panel_settings
                              : Icons.person,
                          color: AppColors.primary),
                    ),
                    title: Text(u.displayName,
                        style:
                            const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                        '${u.email}\n${u.puesto}${u.esAdmin ? ' - Acceso admin' : ''}'),
                    isThreeLine: true,
                    trailing: u.id == _yo?.id
                        ? null
                        : IconButton(
                            tooltip: 'Restablecer contrasena',
                            icon: const Icon(Icons.lock_reset,
                                color: AppColors.primary),
                            onPressed: () => _resetearPassword(u),
                          ),
                  ),

              ],
            ),
          ),
          const TituloSeccion('Codigos de ingreso'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Genera un codigo y compartelo con la persona autorizada. Cada codigo sirve una sola vez. Al registrarse, la persona elige su puesto (encargado, supervisor o gerente).',
                    style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _rolCodigo,
                          decoration: const InputDecoration(
                              labelText: 'Nivel de acceso'),
                          items: const [
                            DropdownMenuItem(
                                value: 'usuario', child: Text('Usuario')),
                            DropdownMenuItem(
                                value: 'admin', child: Text('Administrador')),
                          ],
                          onChanged: (v) => setState(
                              () => _rolCodigo = v ?? 'usuario'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 120,
                        child: ElevatedButton(
                          onPressed: _generarCodigo,
                          child: const Text('Generar'),
                        ),
                      ),
                    ],
                  ),
                  if (_ultimoCodigo != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.okBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: SelectableText(_ultimoCodigo!,
                                style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 4,
                                    color: AppColors.ok)),
                          ),
                          IconButton(
                            tooltip: 'Copiar',
                            icon: const Icon(Icons.copy,
                                color: AppColors.ok),
                            onPressed: () async {
                              await Clipboard.setData(
                                  ClipboardData(text: _ultimoCodigo!));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Codigo copiado')));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const TituloSeccion('Catalogos'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading:
                      const Icon(Icons.agriculture_outlined, color: AppColors.primary),
                  title: const Text('Agregar rancho'),
                  trailing: const Icon(Icons.add),
                  onTap: _nuevoRancho,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.spa_outlined, color: AppColors.primary),
                  title: const Text('Agregar variedad'),
                  trailing: const Icon(Icons.add),
                  onTap: _nuevaVariedad,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
