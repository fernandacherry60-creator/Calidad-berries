/// Catalogos de negocio.
///
/// FUENTE: tabla oficial del cliente (foto WhatsApp) + 14 reportes de
/// calidad Driscoll's de referencia. Todo lo ajustable vive aqui.
///
/// IMPORTANTE (v1.3): cada defecto tiene dos textos:
/// - [nombre]: llave interna ESTABLE, sin acentos. Es la que se guarda en
///   defectos_json (SQLite y Supabase). NUNCA cambiarla: los registros
///   historicos la usan y cambiarla partiria las estadisticas en dos.
/// - [etiqueta]: texto que ve el usuario, con enie y acentos correctos.
///   Esta si puede ajustarse libremente.
library;

/// Solo frambuesa por ahora. Arandano se activara mas adelante junto con
/// su propia tabla de defectos.
const List<String> kCultivos = ['Frambuesa'];

/// Puestos (informativo: identifica quien capturo cada muestreo).
const List<String> kPuestos = [
  'Encargado de rancho',
  'Supervisor',
  'Gerente',
];

/// Cajas que corresponden a un canasto muestreado (regla de la clienta:
/// "por cada 24 cajas es 1 canasto muestreado"). El campo sigue siendo
/// editable por si el inspector necesita corregirlo.
const int kCajasPorCanasto = 24;

/// Canastos que corresponden a N cajas recibidas.
///
/// v1.5 (clienta, 25/ago): "24=1, 48=2, 62=3, cada 24 cajas es 1
/// muestreo en automatico". Se redondea HACIA ARRIBA: cada grupo de 24
/// cajas O FRACCION lleva su canasto (62 cajas -> 3, no 2). Hasta v1.4
/// se dividia hacia abajo, que daba 2 con 62 cajas.
int canastosPorCajas(int cajas) {
  if (cajas <= 0) return 0;
  final canastos = (cajas + kCajasPorCanasto - 1) ~/ kCajasPorCanasto;
  return canastos.clamp(1, 9999);
}

/// ------------------------- ANDEN -------------------------
class DefectoAnden {
  /// Llave interna estable (se guarda en defectos_json). NO cambiar.
  final String nombre;

  /// Texto visible para el usuario, con acentos.
  final String etiqueta;

  final String categoria; // 'condicion' | 'apariencia'
  /// Tolerancia individual informativa (fraccion). null = sin tolerancia
  /// individual, solo suma al % de su categoria.
  final double? tolerancia;

  /// Puntos maximos que otorga individualmente (solo Verde y Quebrada
  /// segun los reportes oficiales; el resto no da puntos).
  final int puntosMax;
  const DefectoAnden(this.nombre, this.etiqueta, this.categoria,
      {this.tolerancia, this.puntosMax = 0});
}

/// Tabla oficial del cliente.
const List<DefectoAnden> kDefectosAnden = [
  // ---- Condicion (suman; si el total supera 5% es rechazo) ----
  DefectoAnden('Podrido', 'Podrido', 'condicion', tolerancia: 0.035),
  DefectoAnden('Humedo Sangrante', 'Húmedo Sangrante', 'condicion',
      tolerancia: 0.05),
  DefectoAnden('Colapsada / Blanda', 'Colapsada / Blanda', 'condicion',
      tolerancia: 0.08),
  DefectoAnden('Fumagina', 'Fumagina', 'condicion', tolerancia: 0.035),
  DefectoAnden('Roya', 'Roya', 'condicion', tolerancia: 0.035),
  DefectoAnden('Sobre Maduro', 'Sobre Maduro', 'condicion',
      tolerancia: 0.035), // confirmado por el cliente: 3.5% (antes 0%)
  DefectoAnden('Cenicilla', 'Cenicilla', 'condicion', tolerancia: 0.035),
  // ---- Apariencia (suman; v1.4: 15% = reempaque, >15% = rechazo) ----
  DefectoAnden('Verde', 'Verde', 'apariencia',
      tolerancia: 0.15, puntosMax: 15),
  DefectoAnden('Quebrada', 'Quebrada', 'apariencia',
      tolerancia: 0.10, puntosMax: 15),
  DefectoAnden('Picada de pajaro', 'Picada de pájaro', 'apariencia'),
  DefectoAnden('Suciedad', 'Suciedad', 'apariencia'),
  DefectoAnden('Quemadura de sol', 'Quemadura de sol', 'apariencia'),
  DefectoAnden('Dano de viento', 'Daño de viento', 'apariencia'),
  DefectoAnden('Residuo de aplicacion', 'Residuo de aplicación', 'apariencia'),
  DefectoAnden('Dano de chinche', 'Daño de chinche', 'apariencia'),
  DefectoAnden('Dano de trips', 'Daño de trips', 'apariencia'),
  DefectoAnden('Pelicula blanca', 'Película blanca', 'apariencia'),
  DefectoAnden('Avejigada', 'Avejigada', 'apariencia'),
  DefectoAnden('Malformada', 'Malformada', 'apariencia'),
  DefectoAnden('Extra chica', 'Extra chica', 'apariencia'),
];

/// Etiqueta visible de un defecto de anden a partir de su llave interna.
/// Si la llave no esta en el catalogo (registro viejo con un defecto que
/// ya no existe), se muestra la llave tal cual: nunca se pierde informacion.
String etiquetaDefectoAnden(String nombre) {
  for (final d in kDefectosAnden) {
    if (d.nombre == nombre) return d.etiqueta;
  }
  return nombre;
}

/// Ranchos oficiales (tabla del cliente). El sector se escribe manual.
const List<String> kRanchos = [
  'ALEGRE 1',
  'ALEGRE 3',
  'ALEGRE 4',
  'NOGAL',
  'DERRAMADERO',
  'BLANCO',
  'CATARINA',
];

/// Variedades oficiales de frambuesa.
const List<String> kVariedades = ['MYA', 'MARILYN', 'FRYDA'];

/// Presentaciones oficiales con sus pesos requeridos por clamshell
/// (tabla "Pesos requeridos en frambuesa" - Grupo Ojo Zarco).
/// Si el peso capturado es menor al minimo: RECHAZO previo a la
/// inspeccion por bajo peso (igual que Driscoll's).
class Presentacion {
  final String nombre;
  final int pesoMinG;
  final int pesoMaxG;
  final double pesoMinOz;
  final double pesoMaxOz;
  const Presentacion(this.nombre, this.pesoMinG, this.pesoMaxG,
      this.pesoMinOz, this.pesoMaxOz);
}

const List<Presentacion> kPresentaciones = [
  Presentacion('4.4 oz (Pollitos)', 160, 164, 5.6, 5.8),
  Presentacion('6 oz', 198, 202, 6.9, 7.0),
  Presentacion('8 oz (Corazon)', 279, 282, 9.7, 9.9),
  Presentacion('9 oz', 322, 325, 11.3, 11.5),
  Presentacion('12 oz', 396, 400, 13.9, 14.1),
  Presentacion('18 oz', 574, 578, 19.4, 19.5),
];

Presentacion? presentacionPorNombre(String nombre) {
  for (final p in kPresentaciones) {
    if (p.nombre == nombre) return p;
  }
  return null;
}

/// --------------------- FRUTA PROCESO ---------------------
///
/// v1.4: LISTA DEFINITIVA de la clienta (Excel calculadora_Calidad.xlsx,
/// hoja PROCESO, 12/ago): 25 defectos en 4 areas de enfoque (Cosecha,
/// Agronomia, Actividades, Inocuidad). Donde el defecto ya existia en
/// v1.2/v1.3 se CONSERVA su llave interna historica y solo cambia la
/// etiqueta visible y/o el area, para que las estadisticas de registros
/// viejos no se partan en dos.
class DefectoProceso {
  /// Llave interna estable (se guarda en defectos_json). NO cambiar.
  final String nombre;

  /// Texto visible para el usuario, con acentos.
  final String etiqueta;

  final String area;
  const DefectoProceso(this.nombre, this.etiqueta, this.area);
}

/// Llaves internas de las areas (asi se guardan en la base local y en
/// Supabase: area_agronomia, area_poscosecha, etc.).
///
/// v1.4: 'Poscosecha' ya no tiene defectos en el catalogo nuevo de la
/// clienta, pero se conserva aqui porque (a) la columna area_poscosecha
/// existe en SQLite y Supabase y (b) los registros v1.2/v1.3 la usan.
/// Los muestreos nuevos simplemente guardan 0 en esa area.
const List<String> kAreasEnfoque = [
  'Agronomia',
  'Poscosecha',
  'Cosecha',
  'Actividades',
  'Inocuidad',
];

/// Areas que si tienen defectos en el catalogo vigente (las que se
/// muestran al capturar). Derivada, no editar a mano.
List<String> get kAreasActivas => kAreasEnfoque
    .where((a) => kDefectosProceso.any((d) => d.area == a))
    .toList();

/// Etiqueta visible de cada area de enfoque.
const Map<String, String> kEtiquetaArea = {
  'Agronomia': 'Agronomía',
  'Poscosecha': 'Poscosecha',
  'Cosecha': 'Cosecha',
  'Actividades': 'Actividades',
  'Inocuidad': 'Inocuidad',
};

/// Conversion de unidades a kilos para el porcentaje de proceso
/// (hoja PROCESO del Excel de la clienta: D4 = cajas*2.23,
/// D5 = taras*2.6). CONFIRMAR con la clienta si estos factores son
/// fijos o dependen de la presentacion.
const double kKgPorCaja = 2.23;
const double kKgPorTara = 2.6;

/// Umbral del semaforo del porcentaje de proceso (nota del Excel:
/// "MENOS AL 8% EN VERDE / MAYOR AL 8% EN ROJO").
const double kUmbralPctProceso = 8.0;

/// --------- POTENCIAL EMPACABLE (v1.5) ---------
///
/// CAMBIO DE REGLA (clienta, 25/ago): "en el de potencial empacable
/// entra las siguientes frutas: verde, quebrada, mal formada, extra
/// chico; estos porcentajes se suman y nos da un % de fruta con
/// potencial empacable".
///
/// Hasta v1.4 el potencial empacable era el COMPLEMENTO del total de
/// defectos (100 - total). Desde v1.5 es la SUMA de los porcentajes de
/// estos cuatro defectos: fruta que tiene defecto pero es recuperable.
/// Ya no es el complemento de nada: es una metrica independiente que se
/// SOLAPA con el total de defectos (estos 4 suman en ambas).
///
/// Son llaves internas de [kDefectosProceso]: no cambiarlas aqui sin
/// cambiarlas alla. Si la clienta agrega un quinto defecto, se agrega
/// su llave a esta lista y no hay que tocar nada mas.
const List<String> kDefectosPotencialEmpacable = [
  'Verde',
  'Quebrada',
  'Mal formada',
  'Extra chico',
];

/// Semaforo del potencial empacable (clienta, 25/ago: "un 10% en verde,
/// un 15% en amarillo y 20% para arriba en rojo").
///
/// OJO: va AL REVES que el semaforo de v1.4. Antes un potencial alto era
/// bueno (era fruta sana); ahora es fruta con defecto, asi que mientras
/// mas alto, peor.
///
/// Sus tres numeros dejan un hueco entre 10 y 15 que nadie definio: aqui
/// se resuelve como "verde por debajo de 15". Si algun dia dice que
/// pasando de 10 ya quiere ambar, basta cambiar [kPotencialEmpacableWarn]
/// a 10.0.
const double kPotencialEmpacableWarn = 15.0;
const double kPotencialEmpacableDanger = 20.0;

/// Nivel de semaforo ('ok' | 'warn' | 'danger') del potencial empacable.
String nivelPotencialEmpacable(double pct) => pct >= kPotencialEmpacableDanger
    ? 'danger'
    : (pct >= kPotencialEmpacableWarn ? 'warn' : 'ok');

/// Catalogo vigente (orden de la hoja PROCESO de la clienta).
const List<DefectoProceso> kDefectosProceso = [
  // ---- Cosecha ----
  DefectoProceso('Pudricion / Hongo', 'Podrición / hongo', 'Cosecha'),
  DefectoProceso('Sangrante', 'Exudación / Sangrante', 'Cosecha'),
  DefectoProceso('Colapsada', 'Colapsada / blanda', 'Cosecha'),
  DefectoProceso('Sobre maduro', 'Sobre maduro', 'Cosecha'),
  DefectoProceso('Verde', 'Verde', 'Cosecha'),
  DefectoProceso('Quebrada', 'Quebrada', 'Cosecha'),
  DefectoProceso('Insectos / larva', 'Insecto / larva', 'Cosecha'),
  // ---- Agronomia ----
  DefectoProceso('Fumagina', 'Fumagina', 'Agronomia'),
  DefectoProceso('Roya', 'Roya', 'Agronomia'),
  DefectoProceso('Cenicilla', 'Cenicilla', 'Agronomia'),
  DefectoProceso('Avejigada', 'Avejigada', 'Agronomia'),
  DefectoProceso('Mal formada', 'Malformada', 'Agronomia'),
  DefectoProceso('Extra chico', 'Extra chica', 'Agronomia'),
  DefectoProceso('Bicolor', 'Bicolor', 'Agronomia'),
  DefectoProceso(
      'Residuo de aplicacion', 'Residuo de aplicación', 'Agronomia'),
  DefectoProceso('Dano por chinche', 'Daño de chinche', 'Agronomia'),
  DefectoProceso('Dano de trips', 'Daño de trips', 'Agronomia'),
  DefectoProceso('Pelicula blanca', 'Película blanca', 'Agronomia'),
  DefectoProceso('Desgranada', 'Desgranada', 'Agronomia'),
  // ---- Actividades ----
  DefectoProceso('Picado de ave', 'Picada de pájaro', 'Actividades'),
  DefectoProceso('Quemadura de sol', 'Quemadura de sol', 'Actividades'),
  DefectoProceso('Dano por viento', 'Daño de viento', 'Actividades'),
  DefectoProceso('Dano mecanico', 'Daño mecánico', 'Actividades'),
  // ---- Inocuidad ----
  DefectoProceso('Suciedad', 'Suciedad', 'Inocuidad'),
  DefectoProceso('Materia extrana', 'Materia extraña', 'Inocuidad'),
];

/// Etiqueta visible de un defecto de proceso a partir de su llave
/// interna. Registros viejos con defectos que ya no estan en el
/// catalogo (por ejemplo 'Regresion' o 'Punta dura' de v1.2/v1.3)
/// muestran su llave tal cual: nunca se pierde informacion.
String etiquetaDefectoProceso(String nombre) {
  for (final d in kDefectosProceso) {
    if (d.nombre == nombre) return d.etiqueta;
  }
  return nombre;
}
