import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database.dart';
import '../data/models.dart';

/// Autenticacion local (offline-first) con registro por codigo de ingreso.
///
/// Seguridad:
/// - Contrasenas NUNCA en claro: PBKDF2-HMAC-SHA256, sal aleatoria por
///   usuario, 30,000 iteraciones.
/// - Nadie puede crear cuenta sin un codigo de ingreso vigente generado por
///   el administrador. El codigo es de un solo uso y define el rol.
/// - La sesion guarda solo el id del usuario, jamas credenciales.
/// - Primer arranque: admin inicial con contrasena temporal de cambio
///   obligatorio.
class AuthService extends ChangeNotifier {
  static const _kSessionKey = 'session_user_id';
  static const _iteraciones = 30000;
  static const _passwordInicialAdmin = 'cambiar123';

  AppUser? _usuario;
  AppUser? get usuario => _usuario;
  bool get autenticado => _usuario != null;
  bool requiereCambioPassword = false;

  Future<void> init() async {
    // La cuenta administradora se valida en Supabase.
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_kSessionKey);
    if (id != null && Supabase.instance.client.auth.currentUser != null) {
      final d = await AppDatabase.instance.db;
      final rows = await d.query('users',
          where: 'id = ? AND active = 1', whereArgs: [id], limit: 1);
      if (rows.isNotEmpty) {
        _usuario = AppUser.fromMap(rows.first);
        // Si el admin restablecio la contrasena mientras la sesion seguia
        // abierta, al reabrir la app se exige definir una nueva.
        requiereCambioPassword =
            ((rows.first['must_change_password'] as int?) ?? 0) == 1;
      }
    }
    notifyListeners();
  }

  Future<void> _asegurarAdminInicial() async {
    final d = await AppDatabase.instance.db;
    final r = await d.rawQuery('SELECT COUNT(*) c FROM users');
    if (((r.first['c'] as int?) ?? 0) == 0) {
      final salt = _nuevaSal();
      await d.insert('users', {
        'email': 'admin@calidad.app',
        'display_name': 'Administrador',
        'puesto': 'Administrador',
        'password_hash': _hash(_passwordInicialAdmin, salt),
        'salt': salt,
        'role': 'admin',
        'created_at': DateTime.now().toIso8601String(),
      });
    }
  }

  bool _emailValido(String e) =>
      RegExp(r'^[\w.+-]+@[\w-]+\.[\w.]+$').hasMatch(e);

  Future<String?> login(String email, String password) async {
    try {
      final client = Supabase.instance.client;
      final response = await client.auth.signInWithPassword(
        email: email.trim().toLowerCase(), password: password);
      if (response.user == null) return 'No se pudo iniciar sesión';
      final profile = await client.from('cb_profiles').select()
          .eq('user_id', response.user!.id).maybeSingle();
      if (profile == null || profile['active'] != true) {
        await client.auth.signOut();
        return 'Cuenta sin activar. Confirma el correo de invitación.';
      }
      final d = await AppDatabase.instance.db;
      final correo = (profile['email'] as String).toLowerCase();
      final rows = await d.query('users', where: 'email = ?',
          whereArgs: [correo], limit: 1);
      final role = profile['role'] == 'admin' ? 'admin' : 'usuario';
      final id = rows.isEmpty ? await d.insert('users', {
        'email': correo, 'display_name': profile['display_name'],
        'puesto': profile['puesto'], 'password_hash': 'cloud-auth',
        'salt': 'cloud-auth', 'role': role,
        'created_at': DateTime.now().toIso8601String()
      }) : rows.first['id'] as int;
      await d.update('users', {
        'display_name': profile['display_name'],
        'puesto': profile['puesto'], 'role': role,
        'active': 1, 'must_change_password': 0
      }, where: 'id = ?', whereArgs: [id]);
      final updated = await d.query('users', where: 'id = ?',
          whereArgs: [id], limit: 1);
      _usuario = AppUser.fromMap(updated.first);
      requiereCambioPassword = false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSessionKey, id);
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      debugPrint('Login nube: $e');
      return 'No fue posible conectar con el servidor';
    }
  }

  /// Registro con codigo de ingreso (un solo uso, define el acceso).
  /// El puesto lo elige la persona y es informativo.
  Future<String?> registrar({
    required String nombre,
    required String email,
    required String password,
    required String codigo,
    required String puesto,
  }) async {
    // No crear cuentas solo locales en la versión Pro: deben existir en Supabase.
    return 'El registro de trabajadores estará disponible cuando se activen las invitaciones en la nube.';
  }

  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    _usuario = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
    notifyListeners();
  }

  Future<String?> cambiarPassword(String actual, String nueva) async {
    if (Supabase.instance.client.auth.currentUser == null) return 'Sin sesión';
    if (nueva.length < 8) return 'La contraseña debe tener al menos 8 caracteres';
    try {
      final email = Supabase.instance.client.auth.currentUser!.email;
      if (email == null) return 'Correo no disponible';
      await Supabase.instance.client.auth.signInWithPassword(
          email: email, password: actual);
      await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: nueva));
      requiereCambioPassword = false;
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  Future<String?> definirPasswordObligatoria(String nueva) async {
    if (Supabase.instance.client.auth.currentUser == null) return 'Sin sesión';
    if (nueva.length < 8) return 'Mínimo 8 caracteres';
    try {
      await Supabase.instance.client.auth.updateUser(
          UserAttributes(password: nueva));
      requiereCambioPassword = false;
      notifyListeners();
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  /// Restablece la contrasena de otra persona y devuelve una temporal.
  ///
  /// Solo el administrador puede hacerlo y solo sobre cuentas de ESTE
  /// telefono (la tabla users es local, no viaja a Supabase). La persona
  /// entra con la temporal y la app la obliga a definir una propia.
  /// Devuelve null si la operacion no es valida.
  // Las contraseñas de Supabase no se restablecen desde SQLite.
  // Se debe usar el flujo de recuperación por correo.
  Future<String?> resetearPassword(int userId) async => null;

  // ---- codigos de ingreso (solo admin) ----

  // Nunca emitir invitaciones locales que no funcionen entre dispositivos.
  Future<String?> generarCodigo(String role) async => null;

  Future<List<Map<String, Object?>>> listarCodigos() async {
    final d = await AppDatabase.instance.db;
    return d.rawQuery('''
      SELECT ic.code, ic.role, ic.created_at, u.display_name AS usado_por
      FROM invite_codes ic
      LEFT JOIN users u ON u.id = ic.used_by
      ORDER BY ic.created_at DESC
      LIMIT 50''');
  }

  Future<List<AppUser>> listarUsuarios() async {
    final d = await AppDatabase.instance.db;
    final rows = await d.query('users', where: 'active = 1', orderBy: 'email');
    return rows.map(AppUser.fromMap).toList();
  }

  // ---- criptografia ----
  String _nuevaSal() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return base64Encode(bytes);
  }

  /// PBKDF2-HMAC-SHA256 implementado sobre package:crypto.
  String _hash(String password, String saltB64) {
    final salt = base64Decode(saltB64);
    final hmacKey = Hmac(sha256, utf8.encode(password));
    var block = hmacKey.convert([...salt, 0, 0, 0, 1]).bytes;
    final result = List<int>.from(block);
    for (var i = 1; i < _iteraciones; i++) {
      block = hmacKey.convert(block).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }
    return base64Encode(result);
  }
}
