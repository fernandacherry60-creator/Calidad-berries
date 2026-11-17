import 'package:flutter/material.dart';

import '../../core/scoring.dart';
import '../../core/theme.dart';

/// Pantalla resumen del muestreo de anden (v1.5).
///
/// Pedido de la clienta (WhatsApp 12/ago): "antes de la ultima pagina de
/// anden necesito esta pagina justo asi como esta señalado". Replica su
/// tabla "ANDEN FRAMBUESA" del Excel calculadora_Calidad.xlsx:
/// encabezado con rancho/sector/variedad/cuadrilla y conteo, tabla de
/// defectos con tolerancia individual, frutos y % calculado, y los dos
/// renglones de veredicto:
/// - CONDICION 5%: RECHAZO si la suma supera 5%, si no PASO.
/// - APARIENCIA: PASO hasta 14.9%, REEMPAQUE de 15% a 15.5%, RECHAZO
///   desde 15.6% (banda cerrada por la clienta el 25/ago).
///
/// Se muestran siempre los 9 defectos con tolerancia (como en su tabla,
/// aunque esten en 0) y ademas cualquier otro defecto que si se haya
/// contado, para no ocultar informacion.
///
/// Al confirmar se regresa true y la pantalla anterior muestra el
/// dialogo final de siempre ("la ultima pagina").
class AndenResumenScreen extends StatelessWidget {
  final String cultivo;
  final String rancho;
  final String sector;
  final String variedad;
  final String presentacion;
  final String cuadrilla;

  /// v1.5: nombre de la embaladora, pedido de la clienta para que
  /// aparezca en la captura final.
  final String embaladora;
  final int totalFrutos;
  final int frutosLarva;
  final ResultadoScore resultado;

  const AndenResumenScreen({
    super.key,
    required this.cultivo,
    required this.rancho,
    required this.sector,
    required this.variedad,
    required this.presentacion,
    required this.cuadrilla,
    this.embaladora = '',
    required this.totalFrutos,
    required this.frutosLarva,
    required this.resultado,
  });

  /// Un defecto aparece en la tabla si tiene tolerancia individual
  /// (los 9 de la tabla de la clienta) o si se conto al menos 1 fruto.
  bool _visible(ResultadoDefecto r) =>
      r.defecto.tolerancia != null || r.conteo > 0;

  @override
  Widget build(BuildContext context) {
    final r = resultado;
    final condicion = r.detalle
        .where((d) => d.defecto.categoria == 'condicion' && _visible(d))
        .toList();
    final apariencia = r.detalle
        .where((d) => d.defecto.categoria == 'apariencia' && _visible(d))
        .toList();

    final colorCultivo =
        AppColors.cultivo[cultivo] ?? AppColors.berry;

    // Veredictos por seccion, igual que en la hoja de la clienta.
    // El de apariencia sale del MISMO helper que usa el motor, para que
    // esta pantalla no pueda decir una cosa y la calificacion otra.
    final condicionRechazo = r.pctCondicion > kUmbralCondicion + 1e-9;
    final verApar = veredictoApariencia(r.pctApariencia);

    return Scaffold(
      appBar: AppBar(title: const Text('Resumen del muestreo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // ---- Encabezado rosa, como la tabla de la clienta ----
                Container(
                  width: double.infinity,
                  color: colorCultivo.withOpacity(0.14),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'ANDÉN ${cultivo.toUpperCase()}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: colorCultivo,
                    ),
                  ),
                ),
                _FilaInfo('Rancho', rancho, 'Sector', sector),
                _FilaInfo('Variedad', variedad, 'Cuadrilla', cuadrilla),
                _FilaInfo('Presentación', presentacion, 'Conteo',
                    '$totalFrutos'),
                if (embaladora.isNotEmpty)
                  _FilaInfo('Embaladora', embaladora, '', ''),
                const Divider(height: 1),
                // ---- Condicion ----
                const _EncabezadoTabla('CONDICIÓN'),
                for (final d in condicion) _FilaDefecto(d),
                // ---- Apariencia ----
                const _EncabezadoTabla('APARIENCIA'),
                for (final d in apariencia) _FilaDefecto(d),
                const Divider(height: 1),
                // ---- Veredictos por seccion ----
                _FilaVeredicto(
                  etiqueta: 'CONDICIÓN 5%',
                  pct: r.pctCondicion,
                  veredicto: condicionRechazo ? 'RECHAZO' : 'PASO',
                ),
                _FilaVeredicto(
                  etiqueta: 'APARIENCIA 15-15.5%',
                  pct: r.pctApariencia,
                  veredicto: verApar,
                ),
              ],
            ),
          ),
          if (frutosLarva > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                frutosLarva == 1
                    ? 'Larva en 1 fruto: REEMPAQUE'
                    : 'Larva en $frutosLarva frutos: RECHAZO automático',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: frutosLarva == 1
                      ? AppColors.warn
                      : AppColors.danger,
                ),
              ),
            ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Apariencia: hasta 14.9% pasa, de 15% a 15.5% es reempaque '
              'y desde 15.6% es rechazo (regla del 25/ago).',
              style: TextStyle(
                  fontSize: 12, color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
      // BUG v1.4 CORREGIDO (la clienta: "eso esta mal y no me deja
      // guardarlo"): esta barra era un Row con el veredicto en un
      // Expanded y los dos botones al lado con ancho propio. En un
      // telefono angosto los botones se comian el ancho, al Expanded le
      // quedaban unos pocos pixeles y el texto "PASO" se partia UNA
      // LETRA POR LINEA; eso estiraba la barra hasta empujar los botones
      // fuera de la pantalla y ya no habia donde tocar Continuar.
      //
      // Ahora se apila: veredicto en su propia fila arriba y los botones
      // abajo repartidos a la mitad. Nada compite por el ancho, asi que
      // no puede volver a pasar por muy largo que sea el motivo.
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: AppColors.card,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Flexible por la misma razon del bug: aunque hoy
                  // "REEMPAQUE" quepa de sobra, ningun texto de esta
                  // barra vuelve a poder empujar a otro.
                  Flexible(
                    child: Text(
                      etiquetaDisposicion(r.disposicion),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: _colorDisposicion(r.disposicion),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${r.puntosTotal}/$kPuntosTotales pts',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.inkSoft),
                  ),
                ],
              ),
              if (r.motivo.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    r.motivo,
                    // Hasta dos lineas y con puntos suspensivos: un
                    // motivo largo nunca vuelve a estirar la barra.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
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
                      child: const Text('Continuar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _colorDisposicion(String d) => switch (nivelDisposicion(d)) {
        'ok' => AppColors.ok,
        'warn' => AppColors.warn,
        _ => AppColors.danger,
      };
}

/// Fila de dos pares etiqueta/valor del encabezado (Rancho|Sector, ...).
class _FilaInfo extends StatelessWidget {
  final String e1, v1, e2, v2;
  const _FilaInfo(this.e1, this.v1, this.e2, this.v2);

  @override
  Widget build(BuildContext context) {
    Widget celda(String e, String v) => Expanded(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '$e\n',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkSoft)),
                TextSpan(
                    text: v.isEmpty ? '-' : v,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    // Si el segundo par viene vacio (por ejemplo la fila de Embaladora,
    // que ocupa el ancho completo) se deja la celda en blanco en lugar
    // de pintar un guion suelto.
    return Row(children: [
      celda(e1, v1),
      if (e2.isEmpty) const Expanded(child: SizedBox()) else celda(e2, v2),
    ]);
  }
}

class _EncabezadoTabla extends StatelessWidget {
  final String titulo;
  const _EncabezadoTabla(this.titulo);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEDE9E0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(titulo,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(
              width: 52,
              child: Text('Tol %',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: AppColors.inkSoft))),
          const SizedBox(
              width: 56,
              child: Text('Frutos',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: AppColors.inkSoft))),
          const SizedBox(
              width: 56,
              child: Text('%',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: AppColors.inkSoft))),
        ],
      ),
    );
  }
}

class _FilaDefecto extends StatelessWidget {
  final ResultadoDefecto r;
  const _FilaDefecto(this.r);

  @override
  Widget build(BuildContext context) {
    final activo = r.conteo > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
          border: Border(
              bottom: BorderSide(color: AppColors.line, width: 0.6))),
      child: Row(
        children: [
          Expanded(
            child: Text(r.defecto.etiqueta,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        activo ? FontWeight.w700 : FontWeight.w500)),
          ),
          SizedBox(
            width: 52,
            child: Text(
              r.defecto.tolerancia == null
                  ? '-'
                  : (r.defecto.tolerancia! * 100).toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.inkSoft),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text('${r.conteo}',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        activo ? FontWeight.w800 : FontWeight.w500)),
          ),
          SizedBox(
            width: 56,
            child: Text('${(r.pct * 100).toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight:
                        activo ? FontWeight.w800 : FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _FilaVeredicto extends StatelessWidget {
  final String etiqueta;
  final double pct; // 0..1
  final String veredicto; // PASO | REEMPAQUE | RECHAZO
  const _FilaVeredicto({
    required this.etiqueta,
    required this.pct,
    required this.veredicto,
  });

  @override
  Widget build(BuildContext context) {
    final (color, fondo) = switch (veredicto) {
      'PASO' => (AppColors.ok, AppColors.okBg),
      'REEMPAQUE' => (AppColors.warn, AppColors.warnBg),
      _ => (AppColors.danger, AppColors.dangerBg),
    };
    return Container(
      color: const Color(0xFFE4DFD6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(etiqueta,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          SizedBox(
            width: 68,
            child: Text('${(pct * 100).toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 13.5)),
          ),
          const SizedBox(width: 10),
          Container(
            width: 104,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 5),
            decoration: BoxDecoration(
              color: fondo,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(veredicto,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: color)),
          ),
        ],
      ),
    );
  }
}
