import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/scoring.dart';
import '../data/models.dart';

/// Exportacion a Excel (.xlsx) real, generado en el telefono sin internet.
///
/// El archivo contiene 3 hojas:
/// - Resumen:       KPIs por dia (tarimas, paso/reempaque/rechazo, % de
///                  rechazo, puntos promedio) y potencial empacable promedio.
/// - Andenes:       detalle completo de cada muestreo de anden.
/// - Fruta proceso: detalle de cada muestreo de proceso con sus areas.
///
/// v1.5: la columna 'Potencial empacable' ya NO es 100 - defectos; es
/// la suma de Verde + Quebrada + Mal formada + Extra chico (ver
/// kDefectosPotencialEmpacable). Las columnas por area se conservan.
///
/// Se comparte con la hoja nativa de Android (WhatsApp, correo, Drive...).
class ExportService {
  final _fmtDia = DateFormat('dd/MM/yyyy');
  final _fmtHora = DateFormat('dd/MM/yyyy HH:mm');

  Future<void> compartirExcel({
    required List<MuestreoAnden> anden,
    required List<MuestreoProceso> proceso,
  }) async {
    final excel = Excel.createExcel();
    final negrita = CellStyle(bold: true);

    _hojaResumen(excel['Resumen'], anden, proceso, negrita);
    _hojaAndenes(excel['Andenes'], anden, negrita);
    _hojaProceso(excel['Fruta proceso'], proceso, negrita);
    excel.delete('Sheet1');
    excel.setDefaultSheet('Resumen');

    final bytes = excel.save();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final nombre =
        'calidad_berries_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.xlsx';
    final archivo = File('${dir.path}/$nombre');
    await archivo.writeAsBytes(bytes, flush: true);

    await Share.shareXFiles(
      [XFile(archivo.path)],
      subject: 'Reporte de calidad de berries',
      text: 'Reporte de calidad de berries (Excel).',
    );
  }

  // ---------------- Hoja: Resumen ----------------
  void _hojaResumen(Sheet h, List<MuestreoAnden> anden,
      List<MuestreoProceso> proceso, CellStyle negrita) {
    _fila(h, ['REPORTE DE CALIDAD DE BERRIES'], negrita: negrita);
    _fila(h, ['Generado: ${_fmtHora.format(DateTime.now())}']);
    _fila(h, []);

    // ---- Andenes por dia ----
    _fila(h, ['ANDENES - RESUMEN POR DIA'], negrita: negrita);
    _fila(
        h,
        [
          'Fecha',
          'Tarimas',
          'Paso',
          'Reempaque',
          'Rechazo',
          '% Rechazo',
          'Puntos prom.'
        ],
        negrita: negrita);

    final porDia = <DateTime, List<MuestreoAnden>>{};
    for (final m in anden) {
      final d = DateTime(m.fecha.year, m.fecha.month, m.fecha.day);
      porDia.putIfAbsent(d, () => []).add(m);
    }
    final dias = porDia.keys.toList()..sort();
    var tTar = 0, tPaso = 0, tPre = 0, tRec = 0;
    for (final d in dias) {
      final del = porDia[d]!;
      final paso = del.where((m) => m.disposicion == 'PASO').length;
      final pre = del.where((m) => esReempaque(m.disposicion)).length;
      final rec = del.where((m) => m.disposicion == 'RECHAZO').length;
      final prom =
          del.map((m) => m.puntosTotal).reduce((a, b) => a + b) / del.length;
      tTar += del.length;
      tPaso += paso;
      tPre += pre;
      tRec += rec;
      _fila(h, [
        _fmtDia.format(d),
        del.length,
        paso,
        pre,
        rec,
        _pct(rec / del.length * 100),
        _num1(prom),
      ]);
    }
    if (dias.isNotEmpty) {
      _fila(
          h,
          [
            'TOTAL',
            tTar,
            tPaso,
            tPre,
            tRec,
            _pct(tTar == 0 ? 0 : tRec / tTar * 100),
            ''
          ],
          negrita: negrita);
    } else {
      _fila(h, ['Sin muestreos de anden en el periodo.']);
    }

    // ---- Proceso por dia ----
    _fila(h, []);
    _fila(h, ['FRUTA PROCESO - RESUMEN POR DIA'], negrita: negrita);
    _fila(h, ['Fecha', 'Muestreos', 'Potencial empacable prom. (%)'],
        negrita: negrita);

    final porDiaP = <DateTime, List<MuestreoProceso>>{};
    for (final m in proceso) {
      final d = DateTime(m.fecha.year, m.fecha.month, m.fecha.day);
      porDiaP.putIfAbsent(d, () => []).add(m);
    }
    final diasP = porDiaP.keys.toList()..sort();
    for (final d in diasP) {
      final del = porDiaP[d]!;
      final prom =
          del.map((m) => m.potencialEmpacable).reduce((a, b) => a + b) /
              del.length;
      _fila(h, [_fmtDia.format(d), del.length, _num1(prom)]);
    }
    if (diasP.isEmpty) {
      _fila(h, ['Sin muestreos de proceso en el periodo.']);
    }

    for (var c = 0; c < 7; c++) {
      h.setColumnWidth(c, c == 0 ? 14 : 12);
    }
  }

  // ---------------- Hoja: Andenes (detalle) ----------------
  void _hojaAndenes(Sheet h, List<MuestreoAnden> anden, CellStyle negrita) {
    _fila(
        h,
        [
          'Fecha',
          'Rancho',
          'Sector',
          'Cultivo',
          'Variedad',
          'Presentación',
          'Cuadrilla',
          'Licencia',
          'Evaluador',
          'Embaladora',
          'Cajas',
          'Canastos',
          'Frutos muestra',
          'Brix',
          'Peso',
          'Frutos larva',
          '% Condición',
          '% Apariencia',
          'Pts condición',
          'Pts apariencia',
          'Pts total',
          'Disposición',
          'Motivo',
          'Capturado por',
          'Puesto',
        ],
        negrita: negrita);

    final orden = [...anden]..sort((a, b) => a.fecha.compareTo(b.fecha));
    for (final m in orden) {
      _fila(h, [
        _fmtHora.format(m.fecha),
        m.rancho,
        m.sector,
        m.cultivo,
        m.variedad,
        m.presentacion,
        m.cuadrilla,
        m.licencia,
        m.evaluador,
        m.embaladora,
        m.cajasRecibidas,
        m.canastos,
        m.frutaMuestra,
        m.gradosBrix == null ? '' : _num1(m.gradosBrix!),
        m.peso == null ? '' : _num1(m.peso!),
        m.frutosLarva,
        _num1(m.pctCondicion * 100),
        _num1(m.pctApariencia * 100),
        m.puntosCondicion,
        m.puntosApariencia,
        m.puntosTotal,
        etiquetaDisposicion(m.disposicion),
        m.motivo,
        m.capturadoPor ?? '',
        m.puestoCaptura ?? '',
      ]);
    }
    h.setColumnWidth(0, 17);
    for (var c = 1; c < 25; c++) {
      h.setColumnWidth(c, 13);
    }
  }

  // ---------------- Hoja: Fruta proceso (detalle) ----------------
  void _hojaProceso(Sheet h, List<MuestreoProceso> proceso, CellStyle negrita) {
    _fila(
        h,
        [
          'Fecha',
          'Cultivo',
          'Rancho',
          'Cajas',
          'Taras',
          '% Proceso',
          'Frutos muestra',
          'Agronomía (%)',
          'Poscosecha (%)',
          'Cosecha (%)',
          'Actividades (%)',
          'Inocuidad (%)',
          'Total defectos (%)',
          'Potencial empacable (%)',
        ],
        negrita: negrita);

    final orden = [...proceso]..sort((a, b) => a.fecha.compareTo(b.fecha));
    for (final m in orden) {
      _fila(h, [
        _fmtHora.format(m.fecha),
        m.cultivo,
        m.rancho,
        m.cajas ?? '',
        m.taras ?? '',
        m.pctProceso == null ? '' : _num1(m.pctProceso!),
        m.frutosMuestra ?? '',
        _num1(m.porArea['Agronomia'] ?? 0),
        _num1(m.porArea['Poscosecha'] ?? 0),
        _num1(m.porArea['Cosecha'] ?? 0),
        _num1(m.porArea['Actividades'] ?? 0),
        _num1(m.porArea['Inocuidad'] ?? 0),
        _num1(m.totalDefectos),
        _num1(m.potencialEmpacable),
      ]);
    }
    h.setColumnWidth(0, 17);
    for (var c = 1; c < 14; c++) {
      h.setColumnWidth(c, 16);
    }
  }

  // ---------------- Utilitarios ----------------
  /// Agrega una fila. Acepta String, int y double; aplica negrita opcional.
  void _fila(Sheet h, List<Object> valores, {CellStyle? negrita}) {
    final fila = h.maxRows;
    h.appendRow([
      for (final v in valores)
        switch (v) {
          final int n => IntCellValue(n),
          final double n => DoubleCellValue(n),
          _ => TextCellValue(v.toString()),
        }
    ]);
    if (negrita != null) {
      for (var c = 0; c < valores.length; c++) {
        h
            .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: fila))
            .cellStyle = negrita;
      }
    }
  }

  double _num1(num v) => double.parse(v.toStringAsFixed(1));
  double _pct(num v) => double.parse(v.toStringAsFixed(1));
}
