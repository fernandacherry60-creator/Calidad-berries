import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/scoring.dart';
import '../../core/theme.dart';

/// Pantalla resumen de fruta proceso (v1.5).
///
/// Cambios del 25/ago pedidos por la clienta:
/// - Fuera el renglon de kilos debajo del porcentaje de proceso: "que no
///   lo lleve, solo nos de el porcentaje".
/// - Potencial empacable = suma de verde + quebrada + malformada +
///   extra chica, con semaforo verde/ambar/rojo en 15% y 20%.
///
/// Pedido de la clienta (WhatsApp 12/ago): "la tabla de la derecha seria
/// la pantalla donde filtre solo los defectos que se encontraron y
/// aparesca los datos asi como esta en la imagen". Replica su tabla
/// "MUESTREO DE PROCESO" del Excel: fecha, rancho, cajas, taras y
/// porcentaje de proceso arriba, y abajo SOLO los defectos con conteo,
/// con cantidad y %, cerrando con la fila de frutos totales.
///
/// Al confirmar se regresa true y la pantalla anterior guarda.
class ProcesoResumenScreen extends StatelessWidget {
  final String cultivo;
  final String rancho;
  final DateTime fecha;
  final int? cajas;
  final int? taras;
  final ResultadoPctProceso pctProceso;
  final int frutosMuestra;
  final Map<String, int> conteos; // nombre -> frutos contados
  final Map<String, double> pct; // nombre -> % (0..100)
  final ResultadoProceso resultado;

  const ProcesoResumenScreen({
    super.key,
    required this.cultivo,
    required this.rancho,
    required this.fecha,
    required this.cajas,
    required this.taras,
    required this.pctProceso,
    required this.frutosMuestra,
    required this.conteos,
    required this.pct,
    required this.resultado,
  });

  @override
  Widget build(BuildContext context) {
    // Solo los defectos que se encontraron, en el orden del catalogo.
    final encontrados = [
      for (final d in kDefectosProceso)
        if ((conteos[d.nombre] ?? 0) > 0) d
    ];
    final totalConteos =
        conteos.values.fold<int>(0, (a, b) => a + b);
    final colorCultivo =
        AppColors.cultivo[cultivo] ?? AppColors.berry;
    final pctP = pctProceso.pct;

    return Scaffold(
      appBar: AppBar(title: const Text('Resumen del muestreo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  color: colorCultivo.withOpacity(0.14),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'MUESTREO DE PROCESO',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: colorCultivo,
                    ),
                  ),
                ),
                _FilaDato('Fecha',
                    DateFormat('dd/MM/yyyy').format(fecha)),
                _FilaDato('Rancho', rancho.isEmpty ? '-' : rancho),
                _FilaDato('Cajas', cajas == null ? '-' : '$cajas'),
                _FilaDato('Taras', taras == null ? '-' : '$taras'),
                Container(
                  color: pctP == null
                      ? AppColors.surface
                      : (pctProceso.excede
                          ? AppColors.dangerBg
                          : AppColors.okBg),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 9),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text('PORCENTAJE DE PROCESO',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13)),
                      ),
                      Text(
                        pctP == null
                            ? '-'
                            : '${pctP.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: pctP == null
                              ? AppColors.inkSoft
                              : (pctProceso.excede
                                  ? AppColors.danger
                                  : AppColors.ok),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // ---- Tabla de defectos encontrados ----
                Container(
                  color: const Color(0xFFEDE9E0),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  child: const Row(
                    children: [
                      Expanded(
                          child: Text('DEFECTOS',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13))),
                      SizedBox(
                          width: 74,
                          child: Text('Cantidad',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: AppColors.inkSoft))),
                      SizedBox(
                          width: 62,
                          child: Text('%',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: AppColors.inkSoft))),
                    ],
                  ),
                ),
                if (encontrados.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Sin defectos encontrados en la muestra.',
                        style: TextStyle(color: AppColors.inkSoft)),
                  ),
                for (final d in encontrados)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: const BoxDecoration(
                        border: Border(
                            bottom: BorderSide(
                                color: AppColors.line, width: 0.6))),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(d.etiqueta,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700))),
                        SizedBox(
                            width: 74,
                            child: Text('${conteos[d.nombre]}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800))),
                        SizedBox(
                            width: 62,
                            child: Text(
                                '${(pct[d.nombre] ?? 0).toStringAsFixed(1)}%',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800))),
                      ],
                    ),
                  ),
                // ---- Fila de totales, como en la hoja de la clienta ----
                Container(
                  color: const Color(0xFFE4DFD6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      const Expanded(
                          child: Text('FRUTOS TOTALES',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13))),
                      SizedBox(
                          width: 74,
                          child: Text('$totalConteos de $frutosMuestra',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13))),
                      SizedBox(
                          width: 62,
                          child: Text(
                              '${resultado.totalDefectos.toStringAsFixed(1)}%',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13))),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                              child: Text('Potencial empacable',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13))),
                          Text(
                            '${resultado.potencialEmpacable.toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              color: switch (nivelPotencialEmpacable(
                                  resultado.potencialEmpacable)) {
                                'ok' => AppColors.ok,
                                'warn' => AppColors.warn,
                                _ => AppColors.danger,
                              },
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.only(top: 3),
                        child: Text(
                          'Verde + quebrada + malformada + extra chica.',
                          style: TextStyle(
                              fontSize: 11.5, color: AppColors.inkSoft),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Revisar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilaDato extends StatelessWidget {
  final String etiqueta;
  final String valor;
  const _FilaDato(this.etiqueta, this.valor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(color: AppColors.line, width: 0.6))),
      child: Row(
        children: [
          Expanded(
              child: Text(etiqueta,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.inkSoft))),
          Text(valor,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13.5)),
        ],
      ),
    );
  }
}
