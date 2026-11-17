import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/scoring.dart';
import '../core/theme.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import '../services/auth_service.dart';
import '../services/export_service.dart';
import '../widgets/common.dart';

/// Historial de muestreos.
/// Un inspector ve unicamente sus registros; un admin ve los de todos.
class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen>
    with SingleTickerProviderStateMixin {
  final _repo = MuestreoRepo();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  List<MuestreoAnden> _anden = [];
  List<MuestreoProceso> _proceso = [];
  bool _cargando = true;
  bool _exportando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final auth = context.read<AuthService>();
    final userId = auth.usuario!.veTodo ? null : auth.usuario!.id;
    final anden = await _repo.listarAnden(userId: userId);
    final proceso = await _repo.listarProceso(userId: userId);
    if (!mounted) return;
    setState(() {
      _anden = anden;
      _proceso = proceso;
      _cargando = false;
    });
  }

  Future<void> _exportarExcel() async {
    setState(() => _exportando = true);
    try {
      await ExportService().compartirExcel(anden: _anden, proceso: _proceso);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo generar el Excel.')));
      }
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final hayDatos = _anden.isNotEmpty || _proceso.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        actions: [
          _exportando
              ? const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              : IconButton(
                  tooltip: 'Exportar a Excel',
                  icon: const Icon(Icons.grid_on),
                  onPressed: hayDatos ? _exportarExcel : null,
                ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          tabs: const [Tab(text: 'Andenes'), Tab(text: 'Fruta proceso')],
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _anden.isEmpty
                    ? const _Vacio('Aun no hay muestreos de anden.')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _anden.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final m = _anden[i];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            '${m.rancho} - Sector ${m.sector}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${m.cultivo} - ${m.variedad} - Lic. ${m.licencia}\n'
                                          '${m.capturadoPor ?? ''}${(m.puestoCaptura ?? '').isNotEmpty ? ' (${m.puestoCaptura})' : ''}\n'
                                          '${fmt.format(m.fecha)}'
                                          '${m.syncStatus == 'pendiente' ? ' - pendiente de enviar' : ''}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      ChipSemaforo(
                                        texto: etiquetaDisposicion(
                                            m.disposicion),
                                        nivel: nivelDisposicion(
                                            m.disposicion),
                                      ),
                                      const SizedBox(height: 4),
                                      Text('${m.puntosTotal}/80 pts',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.inkSoft)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                _proceso.isEmpty
                    ? const _Vacio('Aun no hay muestreos de proceso.')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _proceso.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final m = _proceso[i];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(m.cultivo,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${fmt.format(m.fecha)}'
                                          '${m.syncStatus == 'pendiente' ? ' - pendiente de enviar' : ''}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ChipSemaforo(
                                    texto:
                                        'Empacable ${m.potencialEmpacable.toStringAsFixed(0)}%',
                                    nivel: m.potencialEmpacable >= 90
                                        ? 'ok'
                                        : (m.potencialEmpacable >= 80
                                            ? 'warn'
                                            : 'danger'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
    );
  }
}

class _Vacio extends StatelessWidget {
  final String texto;
  const _Vacio(this.texto);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined,
                size: 56, color: AppColors.inkSoft),
            const SizedBox(height: 12),
            Text(texto,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text('Captura tu primer muestreo desde el inicio.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
