import 'dart:convert';

class AppUser {
  final int id;
  final String email;
  final String displayName;

  /// Puesto de la persona (Encargado de rancho, Supervisor, Gerente).
  /// Es informativo: identifica quien capturo cada muestreo.
  final String puesto;

  /// Nivel de acceso: 'admin' (ve todo, genera codigos, catalogos) o
  /// 'usuario' (captura y ve solo sus registros).
  final String role;
  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.puesto,
    required this.role,
  });
  bool get esAdmin => role == 'admin';
  bool get veTodo => esAdmin;

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: m['id'] as int,
        email: m['email'] as String,
        displayName: m['display_name'] as String,
        puesto: (m['puesto'] as String?) ?? '',
        role: m['role'] as String,
      );
}

class MuestreoAnden {
  final int? id;
  final String uuid;
  final int userId;
  final String cultivo;
  final String rancho;
  final String sector; // se escribe manual
  final String variedad;
  final String presentacion;
  final String cuadrilla;
  final int cajasRecibidas;
  final int canastos; // canastos muestrados
  final int frutaMuestra; // frutos totales inspeccionados
  final String licencia;
  final double? gradosBrix;
  final double? peso;
  final int frutosLarva;

  /// Nombre del evaluador (se precarga con el usuario logueado, pero es
  /// editable).
  final String evaluador;

  /// v1.5: nombre de la EMBALADORA. La clienta pidio el 25/ago cambiar
  /// el campo "Muestreados" de v1.3 (que nunca significo nada) por el
  /// nombre de quien embalo.
  ///
  /// La COLUMNA de la base (SQLite y Supabase) se sigue llamando
  /// 'muestreados' a proposito: renombrarla obligaria a una migracion en
  /// los dos lados y a romper el sync de cualquier APK viejo instalado,
  /// sin ganar nada. Aqui en Dart si se llama por su nombre real.
  final String embaladora;
  final Map<String, int> defectos;
  final List<String> fotos;
  final double pctCondicion; // 0..1
  final double pctApariencia; // 0..1
  final int puntosCondicion;
  final int puntosApariencia;
  final int puntosTotal; // sobre 80
  final String disposicion; // PASO | REEMPAQUE | RECHAZO
  final String motivo;
  final DateTime fecha;
  final String syncStatus;

  /// Solo lectura, llenados por JOIN con users al listar.
  final String? capturadoPor;
  final String? puestoCaptura;

  const MuestreoAnden({
    this.id,
    required this.uuid,
    required this.userId,
    required this.cultivo,
    required this.rancho,
    required this.sector,
    required this.variedad,
    required this.presentacion,
    required this.cuadrilla,
    required this.cajasRecibidas,
    required this.canastos,
    required this.frutaMuestra,
    required this.licencia,
    this.gradosBrix,
    this.peso,
    required this.frutosLarva,
    this.evaluador = '',
    this.embaladora = '',
    required this.defectos,
    this.fotos = const [],
    required this.pctCondicion,
    required this.pctApariencia,
    required this.puntosCondicion,
    required this.puntosApariencia,
    required this.puntosTotal,
    required this.disposicion,
    this.motivo = '',
    required this.fecha,
    this.syncStatus = 'pendiente',
    this.capturadoPor,
    this.puestoCaptura,
  });

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'user_id': userId,
        'cultivo': cultivo,
        'rancho': rancho,
        'sector': sector,
        'variedad': variedad,
        'presentacion': presentacion,
        'cuadrilla': cuadrilla,
        'cajas_recibidas': cajasRecibidas,
        'canastos': canastos,
        'fruta_muestra': frutaMuestra,
        'licencia': licencia,
        'grados_brix': gradosBrix,
        'peso': peso,
        'frutos_larva': frutosLarva,
        'evaluador': evaluador,
        'muestreados': embaladora,
        'defectos_json': jsonEncode(defectos),
        'fotos_json': jsonEncode(fotos),
        'pct_condicion': pctCondicion,
        'pct_apariencia': pctApariencia,
        'puntos_condicion': puntosCondicion,
        'puntos_apariencia': puntosApariencia,
        'puntos_total': puntosTotal,
        'disposicion': disposicion,
        'motivo': motivo,
        'fecha': fecha.toIso8601String(),
        'sync_status': syncStatus,
      };

  factory MuestreoAnden.fromMap(Map<String, Object?> m) => MuestreoAnden(
        id: m['id'] as int?,
        uuid: m['uuid'] as String,
        userId: m['user_id'] as int,
        cultivo: m['cultivo'] as String,
        rancho: m['rancho'] as String,
        sector: m['sector'] as String,
        variedad: m['variedad'] as String,
        presentacion: m['presentacion'] as String,
        cuadrilla: m['cuadrilla'] as String,
        cajasRecibidas: m['cajas_recibidas'] as int,
        canastos: m['canastos'] as int,
        frutaMuestra: m['fruta_muestra'] as int,
        licencia: m['licencia'] as String,
        gradosBrix: (m['grados_brix'] as num?)?.toDouble(),
        peso: (m['peso'] as num?)?.toDouble(),
        frutosLarva: m['frutos_larva'] as int,
        evaluador: (m['evaluador'] as String?) ?? '',
        embaladora: (m['muestreados'] as String?) ?? '',
        defectos: (jsonDecode(m['defectos_json'] as String) as Map)
            .map((k, v) => MapEntry(k as String, v as int)),
        fotos: (jsonDecode((m['fotos_json'] as String?) ?? '[]') as List)
            .cast<String>(),
        pctCondicion: (m['pct_condicion'] as num).toDouble(),
        pctApariencia: (m['pct_apariencia'] as num).toDouble(),
        puntosCondicion: m['puntos_condicion'] as int,
        puntosApariencia: m['puntos_apariencia'] as int,
        puntosTotal: m['puntos_total'] as int,
        disposicion: m['disposicion'] as String,
        motivo: (m['motivo'] as String?) ?? '',
        fecha: DateTime.parse(m['fecha'] as String),
        syncStatus: m['sync_status'] as String,
        capturadoPor: m['capturado_por'] as String?,
        puestoCaptura: m['puesto_captura'] as String?,
      );
}

class MuestreoProceso {
  final int? id;
  final String uuid;
  final int userId;
  final String cultivo;

  /// v1.3: frutos totales de la muestra (por defecto 100). Los registros
  /// anteriores a v1.3 no lo tienen (null): en esa epoca se capturaba el
  /// % directamente.
  final int? frutosMuestra;

  /// v1.4 (Excel de la clienta, hoja PROCESO): rancho del muestreo y
  /// porcentaje de proceso a partir de cajas y taras. Los registros
  /// anteriores a v1.4 tienen rancho vacio y cajas/taras/pct null.
  final String rancho;
  final int? cajas;
  final int? taras;
  final double? pctProceso; // 0..100
  final Map<String, double> defectos; // nombre -> %
  final Map<String, double> porArea;
  final double totalDefectos;
  final double potencialEmpacable;
  final DateTime fecha;
  final String syncStatus;

  const MuestreoProceso({
    this.id,
    required this.uuid,
    required this.userId,
    required this.cultivo,
    this.frutosMuestra,
    this.rancho = '',
    this.cajas,
    this.taras,
    this.pctProceso,
    required this.defectos,
    required this.porArea,
    required this.totalDefectos,
    required this.potencialEmpacable,
    required this.fecha,
    this.syncStatus = 'pendiente',
  });

  Map<String, Object?> toMap() => {
        'uuid': uuid,
        'user_id': userId,
        'cultivo': cultivo,
        'frutos_muestra': frutosMuestra,
        'rancho': rancho,
        'cajas': cajas,
        'taras': taras,
        'pct_proceso': pctProceso,
        'defectos_json': jsonEncode(defectos),
        'area_agronomia': porArea['Agronomia'] ?? 0,
        'area_poscosecha': porArea['Poscosecha'] ?? 0,
        'area_cosecha': porArea['Cosecha'] ?? 0,
        'area_actividades': porArea['Actividades'] ?? 0,
        'area_inocuidad': porArea['Inocuidad'] ?? 0,
        'total_defectos': totalDefectos,
        'potencial_empacable': potencialEmpacable,
        'fecha': fecha.toIso8601String(),
        'sync_status': syncStatus,
      };

  factory MuestreoProceso.fromMap(Map<String, Object?> m) => MuestreoProceso(
        id: m['id'] as int?,
        uuid: m['uuid'] as String,
        userId: m['user_id'] as int,
        cultivo: m['cultivo'] as String,
        frutosMuestra: m['frutos_muestra'] as int?,
        rancho: (m['rancho'] as String?) ?? '',
        cajas: m['cajas'] as int?,
        taras: m['taras'] as int?,
        pctProceso: (m['pct_proceso'] as num?)?.toDouble(),
        defectos: (jsonDecode(m['defectos_json'] as String) as Map)
            .map((k, v) => MapEntry(k as String, (v as num).toDouble())),
        porArea: {
          'Agronomia': (m['area_agronomia'] as num).toDouble(),
          'Poscosecha': (m['area_poscosecha'] as num).toDouble(),
          'Cosecha': (m['area_cosecha'] as num).toDouble(),
          'Actividades': (m['area_actividades'] as num).toDouble(),
          'Inocuidad': (m['area_inocuidad'] as num).toDouble(),
        },
        totalDefectos: (m['total_defectos'] as num).toDouble(),
        potencialEmpacable: (m['potencial_empacable'] as num).toDouble(),
        fecha: DateTime.parse(m['fecha'] as String),
        syncStatus: m['sync_status'] as String,
      );
}
