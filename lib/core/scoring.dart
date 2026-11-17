import 'constants.dart';

/// Motor de calificacion del muestreo de anden (sistema Driscoll's).
///
/// REGLAS VIGENTES (v1.5, WhatsApp de la clienta del 25/ago + Excel
/// "calculadora_Calidad.xlsx", hoja ANDEN):
///
/// Porcentajes (sumatorios por categoria):
/// - % Condicion  = suma de % de los 7 defectos de condicion.
/// - % Apariencia = suma de % de los defectos de apariencia.
///
/// Puntos (total sobre 80, SIN CAMBIO desde v1.0):
/// - Condicion vale 50 puntos si su suma no supera el 5%.
/// - Apariencia vale hasta 30: solo Verde y Quebrada dan puntos
///   (15 c/u). Formula deducida y verificada contra 14 reportes
///   oficiales: puntos = 15 - parte entera del % del defecto.
///
/// Disposicion (v1.5 - la clienta cerro la banda el 25/ago: "del 14.9%
/// para abajo pasa, del 15% al 15.5% justo es reempaque y del 15.6%
/// para arriba es rechazo"):
/// - RECHAZO      si % Condicion > 5%
///                o % Apariencia >= 15.6%
///                o 2+ frutos con larva
///                o puntos totales < 60.
/// - REEMPAQUE    si % Apariencia entre 15.0% y 15.5%
///                o exactamente 1 fruto con larva.
/// - PASO         en caso contrario.
///
/// POR QUE SE COMPARA EN DECIMAS Y NO EN FRACCIONES: la clienta razona
/// en decimas de porcentaje (14.9 / 15.5 / 15.6) y es exactamente lo que
/// ve en pantalla, que se imprime con un decimal. Comparar 0.155 contra
/// 0.156 en punto flotante obligaba a arrastrar un epsilon en cada
/// comparacion y aun asi podia discrepar de lo que el usuario leia. Al
/// redondear a decimas y comparar enteros, lo que se decide es
/// literalmente lo que se muestra.
///
/// CAMBIO DE LLAVE INTERNA (v1.5): hasta v1.4 el reempaque se guardaba
/// como 'PRE-RECHAZO' para no partir el historico. Como el APK todavia
/// no estaba en produccion y los registros de prueba se borran, se
/// aprovecho para guardar ya 'REEMPAQUE'. [esReempaque] sigue
/// reconociendo la llave vieja, asi que cualquier registro anterior que
/// sobreviva se sigue contando y mostrando bien.
const double kUmbralCondicion = 0.05;

/// Umbrales de apariencia en DECIMAS DE PORCENTAJE (150 = 15.0%).
/// Clienta, 25/ago: <=14.9% pasa, 15.0%-15.5% reempaque, >=15.6% rechazo.
const int kAparReempaqueDecimas = 150; // 15.0%
const int kAparRechazoDecimas = 156; // 15.6%

/// Los mismos umbrales como fraccion (0..1), solo para mostrarlos en
/// pantalla. Las DECISIONES usan las decimas de arriba.
const double kUmbralAparReempaque = kAparReempaqueDecimas / 1000;
const double kUmbralAparRechazo = kAparRechazoDecimas / 1000;

/// Convierte una fraccion (0..1) a decimas de porcentaje redondeadas,
/// que es la misma cifra que el usuario ve en pantalla con un decimal.
/// 0.15 -> 150; 13/87 = 0.14942... -> 149; 31/200 = 0.155 -> 155.
int decimasDePct(double pct01) => (pct01 * 1000).round();

/// Veredicto de la seccion de apariencia: 'PASO' | 'REEMPAQUE' |
/// 'RECHAZO'. Vive aqui para que la pantalla de captura, la de resumen
/// y el motor no puedan discrepar entre si.
String veredictoApariencia(double pctApariencia) {
  final d = decimasDePct(pctApariencia);
  if (d >= kAparRechazoDecimas) return 'RECHAZO';
  if (d >= kAparReempaqueDecimas) return 'REEMPAQUE';
  return 'PASO';
}

/// Tolerancia numerica para comparar sumas de porcentajes en punto
/// flotante (10/100 + 5/100 puede dar 0.15000000000000002). Se sigue
/// usando en condicion y en el % de proceso; la apariencia ya no la
/// necesita porque compara decimas enteras.
const double _eps = 1e-9;

const int kPuntosMinimos = 60;
const int kPuntosCondicion = 50;
const int kPuntosTotales = 80;

/// Llave que se guarda en la base para el reempaque (v1.5 en adelante).
const String kDispReempaqueInterno = 'REEMPAQUE';

/// Llave que usaban v1.2-v1.4. Se sigue reconociendo en todos lados para
/// que un registro viejo se cuente y se pinte igual que uno nuevo.
const String kDispReempaqueLegado = 'PRE-RECHAZO';

/// True si la disposicion es reempaque, sin importar con que version se
/// haya guardado. USAR SIEMPRE ESTO en lugar de comparar contra el texto
/// a mano: es lo que evita que un cambio de llave vacie los conteos del
/// dashboard y del Excel en silencio.
bool esReempaque(String disposicion) =>
    disposicion == kDispReempaqueInterno ||
    disposicion == kDispReempaqueLegado;

/// Texto que ve el usuario para cada disposicion.
String etiquetaDisposicion(String disposicion) =>
    esReempaque(disposicion) ? 'REEMPAQUE' : disposicion;

/// Nivel de semaforo ('ok' | 'warn' | 'danger') de una disposicion.
/// Centralizado para que las cuatro pantallas que lo pintaban por su
/// cuenta no se desincronicen.
String nivelDisposicion(String disposicion) => disposicion == 'PASO'
    ? 'ok'
    : (esReempaque(disposicion) ? 'warn' : 'danger');

class ResultadoDefecto {
  final DefectoAnden defecto;
  final int conteo;
  final double pct; // 0..1
  final int puntos;
  const ResultadoDefecto({
    required this.defecto,
    required this.conteo,
    required this.pct,
    required this.puntos,
  });
}

class ResultadoScore {
  final List<ResultadoDefecto> detalle;
  final double pctCondicion; // 0..1
  final double pctApariencia; // 0..1
  final int puntosCondicion; // 0 o 50
  final int puntosApariencia; // 0..30
  final int puntosTotal; // 0..80
  final String disposicion; // PASO | PRE-RECHAZO (=REEMPAQUE) | RECHAZO
  final String motivo; // explicacion corta de la disposicion
  const ResultadoScore({
    required this.detalle,
    required this.pctCondicion,
    required this.pctApariencia,
    required this.puntosCondicion,
    required this.puntosApariencia,
    required this.puntosTotal,
    required this.disposicion,
    required this.motivo,
  });
}

/// Puntos por defecto individual (hoy solo Verde y Quebrada).
/// Verificado contra reportes: 0% -> 15, 1.5% -> 14, 3.4% -> 12,
/// 6.9% -> 9, 10.3% -> 5, etc.
int _puntosDefecto(DefectoAnden d, double pct) {
  if (d.puntosMax == 0) return 0;
  final puntos = d.puntosMax - (pct * 100).floor();
  return puntos.clamp(0, d.puntosMax);
}

ResultadoScore calcularScoreAnden({
  required Map<String, int> conteos,
  required int totalFrutos,
  int frutosLarva = 0,
}) {
  final detalle = <ResultadoDefecto>[];
  double pctCond = 0, pctApar = 0;
  var puntosApar = 0;

  for (final d in kDefectosAnden) {
    final conteo = conteos[d.nombre] ?? 0;
    final pct = totalFrutos > 0 ? conteo / totalFrutos : 0.0;
    final puntos = _puntosDefecto(d, pct);
    detalle.add(ResultadoDefecto(
        defecto: d, conteo: conteo, pct: pct, puntos: puntos));
    if (d.categoria == 'condicion') {
      pctCond += pct;
    } else {
      pctApar += pct;
      puntosApar += puntos;
    }
  }

  final condicionPasa = pctCond <= kUmbralCondicion + _eps;
  final puntosCond = condicionPasa ? kPuntosCondicion : 0;
  final total = puntosCond + puntosApar;

  final veredictoApar = veredictoApariencia(pctApar);

  String disposicion;
  String motivo;
  if (!condicionPasa) {
    disposicion = 'RECHAZO';
    motivo = 'Condición supera 5%';
  } else if (veredictoApar == 'RECHAZO') {
    disposicion = 'RECHAZO';
    motivo = 'Apariencia en 15.6% o más';
  } else if (frutosLarva >= 2) {
    disposicion = 'RECHAZO';
    motivo = 'Larva en 2 o más frutos';
  } else if (total < kPuntosMinimos) {
    disposicion = 'RECHAZO';
    motivo = 'Menos de $kPuntosMinimos puntos';
  } else if (veredictoApar == 'REEMPAQUE') {
    disposicion = kDispReempaqueInterno;
    motivo = 'Apariencia entre 15% y 15.5%';
  } else if (frutosLarva == 1) {
    disposicion = kDispReempaqueInterno;
    motivo = 'Larva en 1 fruto';
  } else {
    disposicion = 'PASO';
    motivo = '';
  }

  return ResultadoScore(
    detalle: detalle,
    pctCondicion: pctCond,
    pctApariencia: pctApar,
    puntosCondicion: puntosCond,
    puntosApariencia: puntosApar,
    puntosTotal: total,
    disposicion: disposicion,
    motivo: motivo,
  );
}

/// ---------------- FRUTA PROCESO ----------------
class ResultadoProceso {
  /// % acumulado por area de enfoque. v1.5: se sigue calculando y
  /// guardando (sirve para reportes por area y para el Excel), pero en
  /// pantalla ya no se pinta con barras ni semaforo: la clienta lo
  /// quiere solo como referencia, no como metrica evaluada.
  final Map<String, double> porArea;

  /// Suma de TODOS los defectos (0..100).
  final double totalDefectos;

  /// v1.5: suma de Verde + Quebrada + Mal formada + Extra chico (0..100).
  /// Se SOLAPA con [totalDefectos]: esos cuatro cuentan en ambas.
  final double potencialEmpacable;
  const ResultadoProceso({
    required this.porArea,
    required this.totalDefectos,
    required this.potencialEmpacable,
  });
}

/// v1.5: el potencial empacable es la SUMA de los porcentajes de los
/// cuatro defectos recuperables ([kDefectosPotencialEmpacable]), no el
/// complemento del total de defectos. Ver la nota en constants.dart.
ResultadoProceso calcularProceso(Map<String, double> pctPorDefecto) {
  final porArea = {for (final a in kAreasEnfoque) a: 0.0};
  double total = 0;
  for (final d in kDefectosProceso) {
    final v = pctPorDefecto[d.nombre] ?? 0;
    porArea[d.area] = (porArea[d.area] ?? 0) + v;
    total += v;
  }
  double empacable = 0;
  for (final llave in kDefectosPotencialEmpacable) {
    empacable += pctPorDefecto[llave] ?? 0;
  }
  return ResultadoProceso(
    porArea: porArea,
    totalDefectos: total.clamp(0, 100).toDouble(),
    potencialEmpacable: empacable.clamp(0, 100).toDouble(),
  );
}

/// Porcentaje de proceso (v1.4, hoja PROCESO del Excel de la clienta):
/// cajas y taras se convierten a kilos (caja = 2.23 kg, tara = 2.6 kg)
/// y el % de proceso es kilos de taras sobre kilos totales.
/// Semaforo de la clienta: verde si es 8% o menos, rojo arriba de 8%.
class ResultadoPctProceso {
  final double kgCajas;
  final double kgTaras;
  final double kgTotal;

  /// 0..100. null cuando aun no hay kilos capturados.
  final double? pct;
  const ResultadoPctProceso({
    required this.kgCajas,
    required this.kgTaras,
    required this.kgTotal,
    required this.pct,
  });

  bool get excede => (pct ?? 0) > kUmbralPctProceso + _eps;
}

ResultadoPctProceso calcularPctProceso({
  required int cajas,
  required int taras,
}) {
  final kgCajas = cajas * kKgPorCaja;
  final kgTaras = taras * kKgPorTara;
  final kgTotal = kgCajas + kgTaras;
  return ResultadoPctProceso(
    kgCajas: kgCajas,
    kgTaras: kgTaras,
    kgTotal: kgTotal,
    pct: kgTotal > 0 ? kgTaras / kgTotal * 100 : null,
  );
}
