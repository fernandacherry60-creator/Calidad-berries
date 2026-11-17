import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme.dart';
import '../services/auth_service.dart';
import '../widgets/common.dart';
import 'admin_screen.dart';
import 'equipo_nube_screen.dart';
import 'dashboard_screen.dart';
import 'anden/anden_form_screen.dart';
import 'calculadora_screen.dart';
import 'historial_screen.dart';
import 'proceso/proceso_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final nombre = auth.usuario?.displayName ?? '';
    final esAdmin = auth.usuario?.esAdmin == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(auth.usuario?.esAdmin == true ? 'Panel de administración' : 'Panel de trabajador'),
        actions: [
          IconButton(
            tooltip: 'Resumen',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const DashboardScreen())),
          ),
          IconButton(
            tooltip: 'Historial',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HistorialScreen())),
          ),
          if (auth.usuario?.esAdmin ?? false)
            IconButton(
              tooltip: 'Administracion',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EquipoNubeScreen())),
            ),
          IconButton(
            tooltip: 'Cerrar sesion',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              final salir = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Cerrar sesion'),
                  content: const Text('Tus datos guardados no se pierden.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20)),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Salir')),
                  ],
                ),
              );
              if (salir == true && context.mounted) {
                await context.read<AuthService>().logout();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const BannerConexion(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(esAdmin ? 'ADMINISTRACIÓN' : 'MI JORNADA',
                          style: const TextStyle(color: Colors.white70,
                            fontSize: 12, fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        Text('Hola, $nombre', style: const TextStyle(
                          color: Colors.white, fontSize: 24,
                          fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(esAdmin
                          ? 'Gestiona tu equipo y controla la calidad.'
                          : 'Registra y revisa tus muestreos.',
                          style: const TextStyle(color: Colors.white)),
                      ],
                    )),
                    const SizedBox(width: 12),
                    Icon(esAdmin ? Icons.admin_panel_settings_rounded
                      : Icons.spa_rounded, size: 48, color: Colors.white70),
                  ]),
                ),
                const SizedBox(height: 20),
                Text('Accesos rápidos',
                  style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 20),
                if (auth.usuario?.esAdmin == true) ...[
                  _ModuloCard(
                    icono: Icons.cloud_outlined,
                    color: AppColors.blue,
                    titulo: 'Equipo en la nube',
                    descripcion: 'Invitar trabajadores y consultar sus cuentas.',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const EquipoNubeScreen())),
                  ),
                  const SizedBox(height: 14),
                  _ModuloCard(
                    icono: Icons.manage_accounts_outlined,
                    color: AppColors.berry,
                    titulo: 'Catálogos locales',
                    descripcion: 'Configurar ranchos y variedades en este teléfono.',
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AdminScreen())),
                  ),
                  const SizedBox(height: 14),
                ],
                _ModuloCard(
                  icono: Icons.local_shipping_outlined,
                  color: AppColors.primaryLight,
                  titulo: 'Andenes',
                  descripcion:
                      'Muestreo en recepcion: score de condicion y apariencia, disposicion de la tarima.',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const AndenFormScreen(cultivo: 'Frambuesa'))),
                ),
                const SizedBox(height: 14),
                _ModuloCard(
                  icono: Icons.science_outlined,
                  color: AppColors.blue,
                  titulo: 'Fruta proceso',
                  descripcion:
                      'Conteo de frutos por defecto, áreas de enfoque y potencial empacable.',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              const ProcesoScreen(cultivo: 'Frambuesa'))),
                ),
                const SizedBox(height: 14),
                _ModuloCard(
                  icono: Icons.calculate_outlined,
                  color: AppColors.orange,
                  titulo: 'Calculadora de defectos',
                  descripcion:
                      'Simula un muestreo: porcentajes, puntos y disposición al instante, sin guardar registros.',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const CalculadoraScreen())),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _ModuloCard extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String titulo;
  final String descripcion;
  final VoidCallback onTap;
  const _ModuloCard({
    required this.icono,
    required this.color,
    required this.titulo,
    required this.descripcion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icono, size: 30, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(descripcion,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.arrow_circle_right_rounded, color: color, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
