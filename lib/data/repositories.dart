import 'database.dart';
import 'models.dart';

class CatalogoRepo {
  Future<List<String>> ranchos() async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query('ranchos', orderBy: 'nombre');
    return rows.map((r) => r['nombre'] as String).toList();
  }

  Future<List<String>> variedades(String cultivo) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query('variedades',
        where: 'cultivo = ?', whereArgs: [cultivo], orderBy: 'nombre');
    return rows.map((r) => r['nombre'] as String).toList();
  }

  Future<void> agregarRancho(String nombre) async {
    final d = await AppDatabase.instance.db;
    await d.insert('ranchos', {'nombre': nombre.trim().toUpperCase()});
  }

  Future<void> agregarVariedad(String cultivo, String nombre) async {
    final d = await AppDatabase.instance.db;
    await d.insert('variedades',
        {'cultivo': cultivo, 'nombre': nombre.trim().toUpperCase()});
  }
}

class MuestreoRepo {
  Future<void> guardarAnden(MuestreoAnden m) async {
    final d = await AppDatabase.instance.db;
    await d.insert('muestreos_anden', m.toMap());
  }

  Future<void> guardarProceso(MuestreoProceso m) async {
    final d = await AppDatabase.instance.db;
    await d.insert('muestreos_proceso', m.toMap());
  }

  Future<void> guardarSemaforo({
    required String uuid,
    required int userId,
    required String cultivo,
    required String categoria,
    required String nivel,
    String? nota,
  }) async {
    final d = await AppDatabase.instance.db;
    await d.insert('semaforo', {
      'uuid': uuid,
      'user_id': userId,
      'cultivo': cultivo,
      'categoria': categoria,
      'nivel': nivel,
      'nota': nota,
      'fecha': DateTime.now().toIso8601String(),
    });
  }

  /// Un usuario ve solo lo suyo; un admin ve todo (userId null).
  /// El JOIN trae nombre y puesto de quien capturo cada muestreo.
  Future<List<MuestreoAnden>> listarAnden({int? userId}) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.rawQuery('''
      SELECT m.*, u.display_name AS capturado_por, u.puesto AS puesto_captura
      FROM muestreos_anden m
      JOIN users u ON u.id = m.user_id
      ${userId != null ? 'WHERE m.user_id = ?' : ''}
      ORDER BY m.fecha DESC
      LIMIT 500''', userId != null ? [userId] : []);
    return rows.map(MuestreoAnden.fromMap).toList();
  }

  Future<List<MuestreoProceso>> listarProceso({int? userId}) async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query(
      'muestreos_proceso',
      where: userId != null ? 'user_id = ?' : null,
      whereArgs: userId != null ? [userId] : null,
      orderBy: 'fecha DESC',
      limit: 500,
    );
    return rows.map(MuestreoProceso.fromMap).toList();
  }

  Future<int> pendientesDeSync() async {
    final d = await AppDatabase.instance.db;
    var total = 0;
    for (final t in ['muestreos_anden', 'muestreos_proceso', 'semaforo']) {
      final r = await d.rawQuery(
          'SELECT COUNT(*) c FROM $t WHERE sync_status = ?', ['pendiente']);
      total += (r.first['c'] as int?) ?? 0;
    }
    return total;
  }

  Future<String> exportarAndenCsv({int? userId}) async {
    final lista = await listarAnden(userId: userId);
    final sb = StringBuffer(
        'fecha,cultivo,rancho,sector,variedad,presentacion,cuadrilla,licencia,'
        'evaluador,embaladora,'
        'cajas_recibidas,canastos_muestrados,frutos_totales,brix,peso,'
        'frutos_larva,pct_condicion,pct_apariencia,puntos_condicion,'
        'puntos_apariencia,puntos_total,disposicion,motivo,fotos,'
        'capturado_por,puesto\n');
    for (final m in lista) {
      sb.writeln([
        m.fecha.toIso8601String(),
        m.cultivo,
        _csv(m.rancho),
        _csv(m.sector),
        _csv(m.variedad),
        _csv(m.presentacion),
        _csv(m.cuadrilla),
        _csv(m.licencia),
        _csv(m.evaluador),
        _csv(m.embaladora),
        m.cajasRecibidas,
        m.canastos,
        m.frutaMuestra,
        m.gradosBrix ?? '',
        m.peso ?? '',
        m.frutosLarva,
        (m.pctCondicion * 100).toStringAsFixed(1),
        (m.pctApariencia * 100).toStringAsFixed(1),
        m.puntosCondicion,
        m.puntosApariencia,
        m.puntosTotal,
        m.disposicion,
        _csv(m.motivo),
        m.fotos.length,
        _csv(m.capturadoPor ?? ''),
        _csv(m.puestoCaptura ?? ''),
      ].join(','));
    }
    return sb.toString();
  }

  String _csv(String v) =>
      v.contains(',') || v.contains('"') ? '"${v.replaceAll('"', '""')}"' : v;
}
