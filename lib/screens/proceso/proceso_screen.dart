import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/scoring.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/repositories.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/common.dart';
import 'proceso_resumen_screen.dart';

/// Muestreo de fruta proceso.
///
/// v1.5 (WhatsApp de la clienta del 25/ago):
/// - Las areas de enfoque van AL FINAL de la pantalla y sin barras ni
///   semaforo: "es solo para identificar las areas", no una metrica
///   evaluada. El % se muestra como referencia, en texto plano.
/// - Potencial empacable = suma de Verde + Quebrada + Mal formada +
///   Extra chico (ya no es 100 - total de defectos).
///
/// v1.4 (Excel calculadora_Calidad.xlsx de la clienta, hoja PROCESO, y
/// WhatsApp del 12/ago):
/// - Datos del muestreo: fecha (automatica) y rancho (lista compartida).
/// - Porcentaje de proceso: cajas y taras convertidas a kilos
///   (caja = 2.23 kg, tara = 2.6 kg); % = kg taras / kg totales, con
///   semaforo verde hasta 8% y rojo arriba de 8%.
/// - Catalogo definitivo de 25 defectos en 4 areas de enfoque,
///   agrupados por area en la captura (columna izquierda de su hoja).
/// - Al guardar se muestra primero la pantalla resumen que filtra solo
///   los defectos encontrados (tabla derecha de su hoja).
///
/// Compatibilidad: en la base (local y Supabase) se sigue guardando el
/// % por defecto en defectos_json, igual que en v1.2/v1.3. Cajas,
/// taras, rancho y pct_proceso van en columnas nuevas (null/vacio en
/// registros viejos).
class ProcesoScreen extends StatefulWidget {
  final String cultivo;
  const ProcesoScreen({super.key, required this.cultivo});

  @override
  State<ProcesoScreen> createState() => _ProcesoScreenState();
}

class _ProcesoScreenState extends State<ProcesoScreen> {
  final _repo = MuestreoRepo();
  final _catalogo = CatalogoRepo();
  final Map<String, int> _conteos = {};
  final _frutos = TextEditingController(text: '100');
  final _cajas = TextEditingController();
  final _taras = TextEditingController();
  List<String> _ranchos = [];
  String? _rancho;
  bool _guardando = false;
  final DateTime _fecha = DateTime.now();

  @override
  void initState() {
    super.initState();
    _cargarRanchos();
  }

  Future<void> _cargarRanchos() async {
    final ranchos = await _catalogo.ranchos();
    if (!mounted) return;
    setState(() => _ranchos = ranchos);
  }

  int get _totalFrutos => int.tryParse(_frutos.text) ?? 0;
  int get _totalConteos => _conteos.values.fold<int>(0, (a, b) => a + b);
  int get _nCajas => int.tryParse(_cajas.text) ?? 0;
  int get _nTaras => int.tryParse(_taras.text) ?? 0;

  ResultadoPctProceso get _pctProceso =>
      calcularPctProceso(cajas: _nCajas, taras: _nTaras);

  /// % por defecto (0..100) calculado del conteo sobre la muestra.
  Map<String, double> get _pct {
    final total = _totalFrutos;
    if (total <= 0) return const {};
    return {
      for (final e in _conteos.entries)
        if (e.value > 0) e.key: e.value / total * 100,
    };
  }

  ResultadoProceso get _r => calcularProceso(_pct);

  void _aviso(String mensaje) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _guardar() async {
    if (_rancho == null || _rancho!.isEmpty) {
      _aviso('Selecciona el rancho');
      return;
    }
    if (_totalFrutos <= 0) {
      _aviso('Indica los frutos totales de la muestra');
      return;
    }
    if (_totalConteos > _totalFrutos) {
      _aviso('Los frutos con defecto superan el total de la muestra');
      return;
    }
    final r = _r;
    final pctP = _pctProceso;

    // v1.4: pantalla resumen (solo defectos encontrados) antes de
    // guardar, como la tabla derecha de la hoja de la clienta.
    final confirmado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ProcesoResumenScreen(
          cultivo: widget.cultivo,
          rancho: _rancho!,
          fecha: _fecha,
          cajas: _nCajas > 0 ? _nCajas : null,
          taras: _nTaras > 0 ? _nTaras : null,
          pctProceso: pctP,
          frutosMuestra: _totalFrutos,
          conteos: Map.of(_conteos)..removeWhere((_, v) => v == 0),
          pct: _pct,
          resultado: r,
        ),
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _guardando = true);
    final auth = context.read<AuthService>();
    final sync = context.read<SyncService>();
    final ahora = DateTime.now();
    await _repo.guardarProceso(MuestreoProceso(
      uuid: '${auth.usuario!.id}-${ahora.microsecondsSinceEpoch}',
      userId: auth.usuario!.id,
      cultivo: widget.cultivo,
      frutosMuestra: _totalFrutos,
      rancho: _rancho!,
      cajas: _nCajas > 0 ? _nCajas : null,
      taras: _nTaras > 0 ? _nTaras : null,
      pctProceso: pctP.pct,
      defectos: _pct,
      porArea: r.porArea,
      totalDefectos: r.totalDefectos,
      potencialEmpacable: r.potencialEmpacable,
      fecha: ahora,
    ));
    await sync.refrescarPendientes();
    if (sync.conectado) await sync.sincronizar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sync.conectado
            ? 'Muestreo guardado y enviado'
            : 'Muestreo guardado en el equipo (sin conexión)')));
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _frutos.dispose();
    _cajas.dispose();
    _taras.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _r;
    final pct = _pct;
    final pctP = _pctProceso;
    return Scaffold(
      appBar: AppBar(title: Text('Fruta proceso - ${widget.cultivo}')),
      body: Column(
        children: [
          const BannerConexion(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              children: [
                const TituloSeccion('Datos del muestreo'),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration:
                            const InputDecoration(labelText: 'Fecha'),
                        child: Text(
                          DateFormat('dd/MM/yyyy').format(_fecha),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        // Deprecacion de 'value' conocida: se deja igual
                        // que en el resto de la app a proposito.
                        value: _rancho,
                        decoration:
                            const InputDecoration(labelText: 'Rancho'),
                        items: [
                          for (final r in _ranchos)
                            DropdownMenuItem(value: r, child: Text(r)),
                        ],
                        onChanged: (v) => setState(() => _rancho = v),
                      ),
                    ),
                  ],
                ),
                const TituloSeccion('Porcentaje de proceso'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cajas,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: InputDecoration(
                            labelText: 'Cajas',
                            helperText:
                                '${kKgPorCaja.toStringAsFixed(2)} kg c/u'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _taras,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: InputDecoration(
                            labelText: 'Taras',
                            helperText:
                                '${kKgPorTara.toStringAsFixed(1)} kg c/u'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: pctP.pct == null
                        ? AppColors.card
                        : (pctP.excede
                            ? AppColors.dangerBg
                            : AppColors.okBg),
                    border: Border.all(color: AppColors.line),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          pctP.pct == null
                              ? 'Captura cajas y taras para calcular el % de proceso'
                              : '${pctP.kgCajas.toStringAsFixed(1)} kg cajas + '
                                  '${pctP.kgTaras.toStringAsFixed(1)} kg taras = '
                                  '${pctP.kgTotal.toStringAsFixed(1)} kg',
                          style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkSoft),
                        ),
                      ),
                      if (pctP.pct != null)
                        Text(
                          '${pctP.pct!.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: pctP.excede
                                ? AppColors.danger
                                : AppColors.ok,
                          ),
                        ),
                    ],
                  ),
                ),
                if (pctP.pct != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5, left: 4),
                    child: Text(
                      'Verde hasta ${kUmbralPctProceso.toStringAsFixed(0)}%; '
                      'rojo arriba de ${kUmbralPctProceso.toStringAsFixed(0)}%.',
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.inkSoft),
                    ),
                  ),
                const TituloSeccion('Muestra'),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _frutos,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: const InputDecoration(
                            labelText: 'Frutos totales',
                            helperText: 'Muestra estándar: 100 frutos'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: _totalConteos > _totalFrutos
                              ? AppColors.dangerBg
                              : AppColors.okBg,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Con defecto: $_totalConteos',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _totalConteos > _totalFrutos
                                ? AppColors.danger
                                : AppColors.ok,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_totalConteos > _totalFrutos)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Los frutos con defecto superan el total de la muestra',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger),
                    ),
                  ),
                // v1.4: defectos agrupados por area de enfoque, como la
                // columna izquierda de la hoja de la clienta.
                for (final area in kAreasActivas) ...[
                  TituloSeccion(
                      'Defectos - ${kEtiquetaArea[area] ?? area}'),
                  for (final d in kDefectosProceso)
                    if (d.area == area)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ContadorDefecto(
                              label: d.etiqueta,
                              valor: _conteos[d.nombre] ?? 0,
                              onChanged: (v) => setState(
                                  () => _conteos[d.nombre] = v),
                            ),
                            if ((_conteos[d.nombre] ?? 0) > 0)
                              Padding(
                                padding: const EdgeInsets.only(
                                    left: 4, top: 3),
                                child: Text(
                                  _totalFrutos > 0
                                      ? '${(pct[d.nombre] ?? 0).toStringAsFixed(1)}% de la muestra'
                                      : 'Indica los frutos totales para calcular el %',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.inkSoft),
                                ),
                              ),
                          ],
                        ),
                      ),
                ],
                // v1.5: las areas van AL FINAL y sin barras. Total de
                // defectos y potencial empacable si conservan semaforo:
                // esos si son metricas que la clienta evalua.
                const TituloSeccion('Áreas de enfoque'),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Referencia: a qué área corresponde cada '
                            'defecto contado.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.inkSoft),
                          ),
                        ),
                        for (final a in kAreasActivas)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                    child: Text(kEtiquetaArea[a] ?? a,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600))),
                                Text(
                                  '${(r.porArea[a] ?? 0).toStringAsFixed(1)} %',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.inkSoft),
                                ),
                              ],
                            ),
                          ),
                        const Divider(height: 22),
                        Row(
                          children: [
                            const Expanded(
                                child: Text('Total de defectos',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800))),
                            ChipSemaforo(
                              texto:
                                  '${r.totalDefectos.toStringAsFixed(1)} %',
                              nivel: r.totalDefectos >= 20
                                  ? 'danger'
                                  : (r.totalDefectos >= 10 ? 'warn' : 'ok'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Expanded(
                                child: Text('Potencial empacable',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800))),
                            ChipSemaforo(
                              texto:
                                  '${r.potencialEmpacable.toStringAsFixed(1)} %',
                              nivel: nivelPotencialEmpacable(
                                  r.potencialEmpacable),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'Verde + quebrada + malformada + extra chica. '
                            'Verde hasta 15%, ámbar 15-20%, rojo 20% o más.',
                            style: TextStyle(
                                fontSize: 11.5, color: AppColors.inkSoft),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _guardando ? null : _guardar,
                  child: _guardando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Colors.white))
                      : const Text('Revisar y guardar'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
