import 'package:fl_chart/fl_chart.dart';
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

/// Resumen con graficas.
/// Filtros: rango (hoy / 7 dias / 30 dias) y campo (predio).
/// - Andenes: tarimas por dia apiladas por disposicion + tasa de rechazo.
/// - Proceso: potencial empacable promedio por dia.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _repo = MuestreoRepo();
  List<MuestreoAnden> _anden = [];
  List<MuestreoProceso> _proceso = [];
  List<String> _predios = ['Todos'];
  String _predio = 'Todos';
  int _dias = 7; // 1 = hoy, 7, 30
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
    final predios = {'Todos', ...anden.map((m) => m.rancho)};
    if (!mounted) return;
    setState(() {
      _anden = anden;
      _proceso = proceso;
      _predios = predios.toList();
      _cargando = false;
    });
  }

  DateTime get _desde {
    final hoy = DateTime.now();
    final inicioHoy = DateTime(hoy.year, hoy.month, hoy.day);
    return _dias == 1
        ? inicioHoy
        : inicioHoy.subtract(Duration(days: _dias - 1));
  }

  List<MuestreoAnden> get _andenFiltrado => _anden
      .where((m) =>
          !m.fecha.isBefore(_desde) &&
          (_predio == 'Todos' || m.rancho == _predio))
      .toList();

  List<MuestreoProceso> get _procesoFiltrado =>
      _proceso.where((m) => !m.fecha.isBefore(_desde)).toList();


  Future<void> _exportarExcel() async {
    setState(() => _exportando = true);
    try {
      await ExportService()
          .compartirExcel(anden: _andenFiltrado, proceso: _procesoFiltrado);
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
  Widget build(BuildContext context) {
    final anden = _andenFiltrado;
    final reempaques =
        anden.where((m) => esReempaque(m.disposicion)).length;
    final rechazos = anden.where((m) => m.disposicion == 'RECHAZO').length;
    final tasaRechazo =
        anden.isEmpty ? 0.0 : rechazos / anden.length * 100;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resumen'),
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
                  onPressed:
                      (_andenFiltrado.isEmpty && _procesoFiltrado.isEmpty)
                          ? null
                          : _exportarExcel,
                ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Filtros
                  Row(
                    children: [
                      Expanded(
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 1, label: Text('Hoy')),
                            ButtonSegment(value: 7, label: Text('7 dias')),
                            ButtonSegment(value: 30, label: Text('30 dias')),
                          ],
                          selected: {_dias},
                          onSelectionChanged: (s) =>
                              setState(() => _dias = s.first),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _predio,
                    decoration: const InputDecoration(
                        labelText: 'Rancho',
                        prefixIcon: Icon(Icons.landscape_outlined)),
                    items: [
                      for (final p in _predios)
                        DropdownMenuItem(value: p, child: Text(p))
                    ],
                    onChanged: (v) =>
                        setState(() => _predio = v ?? 'Todos'),
                  ),

                  const TituloSeccion('Andenes'),
                  Row(
                    children: [
                      _Kpi(
                          titulo: 'Tarimas',
                          valor: '${anden.length}',
                          color: AppColors.primary),
                      const SizedBox(width: 10),
                      _Kpi(
                          titulo: 'Rechazo',
                          valor: '${tasaRechazo.toStringAsFixed(0)}%',
                          color: tasaRechazo > 15
                              ? AppColors.danger
                              : (tasaRechazo > 5
                                  ? AppColors.warn
                                  : AppColors.ok)),
                      const SizedBox(width: 10),
                      _Kpi(
                          titulo: 'Reempaque',
                          valor: '$reempaques',
                          color: AppColors.warn),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (anden.isEmpty)
                    const _SinDatos()
                  else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 18, 18, 10),
                        child: SizedBox(
                          height: 220,
                          child: _GraficaAnden(muestreos: anden, dias: _dias),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _Leyenda(color: AppColors.ok, texto: 'Paso'),
                        SizedBox(width: 14),
                        _Leyenda(color: AppColors.warn, texto: 'Reempaque'),
                        SizedBox(width: 14),
                        _Leyenda(color: AppColors.danger, texto: 'Rechazo'),
                      ],
                    ),
                  ],

                  const TituloSeccion('Fruta proceso'),
                  if (_procesoFiltrado.isEmpty)
                    const _SinDatos()
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 18, 18, 10),
                        child: SizedBox(
                          height: 200,
                          child: _GraficaProceso(
                              muestreos: _procesoFiltrado, dias: _dias),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  if (_procesoFiltrado.isNotEmpty)
                    Center(
                      child: Text(
                        'Potencial empacable promedio por dia (%)',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String titulo;
  final String valor;
  final Color color;
  const _Kpi({required this.titulo, required this.valor, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(valor,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: color)),
              const SizedBox(height: 2),
              Text(titulo,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.inkSoft)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Leyenda extends StatelessWidget {
  final Color color;
  final String texto;
  const _Leyenda({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 12,
            height: 12,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(texto,
            style:
                const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
      ],
    );
  }
}

class _SinDatos extends StatelessWidget {
  const _SinDatos();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('Sin muestreos en este periodo.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ),
    );
  }
}

/// Barras apiladas por dia: aceptado / reempaque / rechazo.
class _GraficaAnden extends StatelessWidget {
  final List<MuestreoAnden> muestreos;
  final int dias;
  const _GraficaAnden({required this.muestreos, required this.dias});

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final fmt = DateFormat('dd/MM');
    final n = dias == 1 ? 1 : dias;
    final grupos = <BarChartGroupData>[];
    var maxY = 1.0;

    for (var i = 0; i < n; i++) {
      final dia = DateTime(hoy.year, hoy.month, hoy.day)
          .subtract(Duration(days: n - 1 - i));
      final delDia = muestreos.where((m) =>
          m.fecha.year == dia.year &&
          m.fecha.month == dia.month &&
          m.fecha.day == dia.day);
      final a = delDia
          .where((m) => m.disposicion == 'PASO')
          .length
          .toDouble();
      final re = delDia
          .where((m) => esReempaque(m.disposicion))
          .length
          .toDouble();
      final r = delDia
          .where((m) => m.disposicion == 'RECHAZO')
          .length
          .toDouble();
      final total = a + re + r;
      if (total > maxY) maxY = total;
      grupos.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(
          toY: total,
          width: n > 10 ? 8 : 18,
          borderRadius: BorderRadius.circular(3),
          rodStackItems: [
            BarChartRodStackItem(0, a, AppColors.ok),
            BarChartRodStackItem(a, a + re, AppColors.warn),
            BarChartRodStackItem(a + re, total, AppColors.danger),
          ],
        ),
      ]));
    }

    return BarChart(
      BarChartData(
        maxY: (maxY + 1).ceilToDouble(),
        barGroups: grupos,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              interval: 1,
              getTitlesWidget: (v, meta) {
                if (v != v.roundToDouble()) return const SizedBox.shrink();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text('${v.toInt()}',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.inkSoft)),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final paso = (n / 6).ceil().clamp(1, 30);
                final i = v.toInt();
                // Solo 1 de cada `paso` fechas, para que nunca se encimen.
                // Anclado a hoy: el dia mas reciente siempre lleva etiqueta.
                if ((n - 1 - i) % paso != 0) {
                  return const SizedBox.shrink();
                }
                final dia = DateTime(hoy.year, hoy.month, hoy.day)
                    .subtract(Duration(days: n - 1 - i));
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(fmt.format(dia),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.inkSoft)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Linea de potencial empacable promedio por dia.
class _GraficaProceso extends StatelessWidget {
  final List<MuestreoProceso> muestreos;
  final int dias;
  const _GraficaProceso({required this.muestreos, required this.dias});

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final fmt = DateFormat('dd/MM');
    final n = dias == 1 ? 1 : dias;
    final puntos = <FlSpot>[];

    for (var i = 0; i < n; i++) {
      final dia = DateTime(hoy.year, hoy.month, hoy.day)
          .subtract(Duration(days: n - 1 - i));
      final delDia = muestreos
          .where((m) =>
              m.fecha.year == dia.year &&
              m.fecha.month == dia.month &&
              m.fecha.day == dia.day)
          .toList();
      if (delDia.isEmpty) continue;
      final prom = delDia
              .map((m) => m.potencialEmpacable)
              .reduce((a, b) => a + b) /
          delDia.length;
      puntos.add(FlSpot(i.toDouble(), prom));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: const FlGridData(show: true, horizontalInterval: 25),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: puntos,
            isCurved: false,
            color: AppColors.primary,
            barWidth: 3,
            dotData: const FlDotData(show: true),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: 25,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text('${v.toInt()}',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.inkSoft)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final paso = (n / 6).ceil().clamp(1, 30);
                final i = v.toInt();
                // Anclado a hoy: el dia mas reciente siempre lleva etiqueta.
                if ((n - 1 - i) % paso != 0) {
                  return const SizedBox.shrink();
                }
                final dia = DateTime(hoy.year, hoy.month, hoy.day)
                    .subtract(Duration(days: n - 1 - i));
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(fmt.format(dia),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.inkSoft)),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
