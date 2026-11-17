import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/database.dart';

/// Sincronizacion offline-first con Supabase.
///
/// Todo se guarda primero en SQLite con sync_status = 'pendiente'.
/// Este servicio escucha la conectividad y, al detectar red (o al abrir la
/// app con red), sube los registros pendientes y los marca 'sincronizado'.
///
/// Idempotencia: el uuid generado en el celular es la llave primaria en
/// Supabase. Se usa INSERT simple (la llave publishable solo tiene permiso
/// de INSERT, sin SELECT, asi que upsert no es viable) y si el servidor
/// responde 23505 (uuid duplicado) significa que un intento anterior si
/// llego: se marca sincronizado. Un reintento nunca duplica registros.
///
/// v1.3/v1.4: el payload incluye las columnas nuevas (evaluador,
/// muestreados, rancho, cajas, taras, pct_proceso,
/// frutos_muestra). Esas columnas DEBEN existir en Supabase antes de usar
/// esta version de la app (ver migracion_supabase_v1.3.sql); si faltan,
/// el insert falla y los registros quedan pendientes hasta agregarlas.
class SyncService extends ChangeNotifier {
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  StreamSubscription<AuthState>? _authSub;

  bool conectado = false;
  bool sincronizando = false;
  int pendientes = 0;

  /// Cache local de identidad de usuarios para no consultar SQLite por
  /// cada registro subido.
  final _usuarios = <int, Map<String, String>>{};

  bool _hayRed(List<ConnectivityResult> estados) =>
      estados.isNotEmpty && !estados.contains(ConnectivityResult.none);

  Future<void> init() async {
    final estados = await _connectivity.checkConnectivity();
    conectado = _hayRed(estados);
    _sub = _connectivity.onConnectivityChanged.listen((estados) {
      final antes = conectado;
      conectado = _hayRed(estados);
      notifyListeners();
      if (!antes && conectado) {
        unawaited(sincronizar());
      }
    });
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.tokenRefreshed) {
        if (conectado) unawaited(sincronizar());
      }
    });
    await refrescarPendientes();
    // Al abrir la app con red, subir lo que haya quedado pendiente.
    if (conectado && pendientes > 0) {
      unawaited(sincronizar());
    }
  }

  Future<void> refrescarPendientes() async {
    final d = await AppDatabase.instance.db;
    var total = 0;
    for (final t in ['muestreos_anden', 'muestreos_proceso', 'semaforo']) {
      final r = await d.rawQuery(
          'SELECT COUNT(*) c FROM $t WHERE sync_status = ?', ['pendiente']);
      total += (r.first['c'] as int?) ?? 0;
    }
    pendientes = total;
    notifyListeners();
  }

  Future<void> sincronizar() async {
    // La nube nueva exige una sesión Supabase válida y un perfil activo.
    // Sin ella, conservar todos los registros en SQLite como pendientes.
    if (!conectado || sincronizando ||
        Supabase.instance.client.auth.currentUser == null) return;
    sincronizando = true;
    notifyListeners();
    try {
      final d = await AppDatabase.instance.db;
      for (final tabla in ['muestreos_anden', 'muestreos_proceso', 'semaforo']) {
        final rows = await d.query(tabla,
            where: 'sync_status = ?', whereArgs: ['pendiente'], limit: 100);
        for (final row in rows) {
          final ok = await _subirRegistro(tabla, row);
          if (ok) {
            await d.update(tabla, {'sync_status': 'sincronizado'},
                where: 'id = ?', whereArgs: [row['id']]);
          }
        }
      }
    } finally {
      sincronizando = false;
      await refrescarPendientes();
    }
  }

  /// Sube un registro a Supabase. Devuelve true solo si el servidor lo
  /// acepto; ante cualquier fallo el registro permanece 'pendiente' local
  /// para reintentarse despues. Nunca se pierde informacion.
  ///
  /// Se usa insert simple (no upsert) porque la llave de la app solo tiene
  /// permiso de INSERT. Si el uuid ya existe (codigo 23505), significa que
  /// un intento anterior si llego al servidor: se considera sincronizado.
  Future<bool> _subirRegistro(String tabla, Map<String, Object?> row) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return false;
      final payload = await _payloadPara(row);
      await client.from(tabla).insert(payload);
      return true;
    } on PostgrestException catch (e) {
      // Un UUID duplicado puede pertenecer a otra cuenta: no confirmar
      // sincronización sin una comprobación de propiedad.
      if (e.code == '23505') {
        final actual = Supabase.instance.client.auth.currentUser;
        if (actual == null) return false;
        try {
          final existente = await Supabase.instance.client.from(tabla)
              .select('uuid').eq('uuid', row['uuid'] as String).maybeSingle();
          return existente != null;
        } catch (_) {
          return false;
        }
      }
      debugPrint('Sync fallo en $tabla: $e');
      return false;
    } catch (e) {
      debugPrint('Sync fallo en $tabla: $e');
      return false;
    }
  }

  /// Convierte una fila local en el payload que espera Supabase:
  /// - quita campos exclusivamente locales (id, sync_status, fotos_json);
  /// - reemplaza user_id (id local que difiere entre celulares) por la
  ///   identidad real del capturista (email, nombre, puesto);
  /// - decodifica defectos_json para que Postgres lo guarde como jsonb.
  Future<Map<String, Object?>> _payloadPara(Map<String, Object?> row) async {
    final p = Map<String, Object?>.from(row);
    p.remove('id');
    p.remove('sync_status');
    p.remove('fotos_json'); // las fotos permanecen en el celular por ahora

    final userId = p.remove('user_id') as int?;
    final u = await _identidad(userId);
    p['usuario_email'] = u['email'];
    p['usuario_nombre'] = u['nombre'];
    p['usuario_puesto'] = u['puesto'];

    final dj = p['defectos_json'];
    if (dj is String && dj.isNotEmpty) {
      try {
        p['defectos_json'] = jsonDecode(dj);
      } catch (_) {
        // Si no es JSON valido se envia como texto; no bloquea la subida.
      }
    }
    return p;
  }

  Future<Map<String, String>> _identidad(int? userId) async {
    if (userId == null) {
      return {'email': 'desconocido', 'nombre': 'Desconocido', 'puesto': ''};
    }
    final cacheado = _usuarios[userId];
    if (cacheado != null) return cacheado;
    final d = await AppDatabase.instance.db;
    final rows = await d.query('users',
        columns: ['email', 'display_name', 'puesto'],
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1);
    final u = rows.isEmpty
        ? {'email': 'desconocido', 'nombre': 'Desconocido', 'puesto': ''}
        : {
            'email': rows.first['email'] as String,
            'nombre': rows.first['display_name'] as String,
            'puesto': (rows.first['puesto'] as String?) ?? '',
          };
    _usuarios[userId] = u.cast<String, String>();
    return _usuarios[userId]!;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
