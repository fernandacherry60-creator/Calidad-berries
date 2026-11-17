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
    /*
    final e = email.trim().toLowerCase();
    if (nombre.trim().length < 3) return 'Escribe tu nombre completo';
    if (!_emailValido(e)) return 'El correo no es valido';
    if (password.length < 8) {
      return 'La contrasena debe tener al menos 8 caracteres';
    }
    final d = await AppDatabase.instance.db;
    final existe =
        await d.query('users', where: 'email = ?', whereArgs: [e], limit: 1);
    if (existe.isNotEmpty) return 'Ya existe una cuenta con ese correo';

    final codigoRows = await d.query('invite_codes',
        where: 'code = ? AND used_by IS NULL',
        whereArgs: [codigo.trim().toUpperCase()],
        limit: 1);
    if (codigoRows.isEmpty) {
      return 'Codigo de ingreso invalido o ya utilizado';
    }
    final invite = codigoRows.first;

    if (puesto.trim().isEmpty) return 'Selecciona tu puesto';
    final salt = _nuevaSal();
    final userId = await d.insert('users', {
      'email': e,
      'display_name': nombre.trim(),
      'puesto': puesto.trim(),
      'password_hash': _hash(password, salt),
      'salt': salt,
      'role': invite['role'],
      'created_at': DateTime.now().toIso8601String(),
    });
    await d.update(
      'invite_codes',
      {'used_by': userId, 'used_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [invite['id']],
    );

    // Inicia sesion directo tras registrarse.
    _usuario = AppUser(
      id: userId,
      email: e,
      displayName: nombre.trim(),
      puesto: puesto.trim(),
      role: invite['role'] as String,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kSessionKey, userId);
    notifyListeners();
    return null;
  }

    */
  Future<void> logout() async {
    await Supabase.instance.client.auth.signOut();
    _usuario = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
    notifyListeners();
  }

  Future<String?> cambiarPassword(String actual, String nueva) async {
    if (_usuario == null) return 'Sin sesion';
    if (nueva.length < 8) {
      return 'La nueva contrasena debe tener al menos 8 caracteres';
    }
    final d = await AppDatabase.instance.db;
    final rows = await d
        .query('users', where: 'id = ?', whereArgs: [_usuario!.id], limit: 1);
    final row = rows.first;
    if (_hash(actual, row['salt'] as String) != row['password_hash']) {
      return 'La contrasena actual no es correcta';
    }
    final salt = _nuevaSal();
    await d.update(
      'users',
      {
        'password_hash': _hash(nueva, salt),
        'salt': salt,
        'must_change_password': 0,
      },
      where: 'id = ?',
      whereArgs: [_usuario!.id],
    );
    requiereCambioPassword = false;
    notifyListeners();
    return null;
  }

  /// Define una contrasena nueva SIN pedir la actual.
  ///
  /// Solo se usa desde la pantalla de cambio obligatorio, a la que unicamente
  /// se llega despues de un login valido (con la contrasena de fabrica o con
  /// la temporal que genero el administrador). No es un atajo: la persona ya
  /// demostro conocer una credencial vigente.
  Future<String?> definirPasswordObligatoria(String nueva) async {
    if (_usuario == null) return 'Sin sesion';
    if (nueva.length < 8) {
      return 'La nueva contrasena debe tener al menos 8 caracteres';
    }
    final d = await AppDatabase.instance.db;
    final salt = _nuevaSal();
    await d.update(
      'users',
      {
        'password_hash': _hash(nueva, salt),
        'salt': salt,
        'must_change_password': 0,
      },
      where: 'id = ?',
      whereArgs: [_usuario!.id],
    );
    requiereCambioPassword = false;
    notifyListeners();
    return null;
  }

  /// Restablece la contrasena de otra persona y devuelve una temporal.
  ///
  /// Solo el administrador puede hacerlo y solo sobre cuentas de ESTE
  /// telefono (la tabla users es local, no viaja a Supabase). La persona
  /// entra con la temporal y la app la obliga a definir una propia.
  /// Devuelve null si la operacion no es valida.
  Future<String?> resetearPassword(int userId) async {
    if (!(_usuario?.esAdmin ?? false)) return null;
    if (userId == _usuario!.id) return null; // no sobre uno mismo
    final d = await AppDatabase.instance.db;
    final rows = await d.query('users',
        where: 'id = ? AND active = 1', whereArgs: [userId], limit: 1);
    if (rows.isEmpty) return null;

    final temporal = _passwordTemporal();
    final salt = _nuevaSal();
    await d.update(
      'users',
      {
        'password_hash': _hash(temporal, salt),
        'salt': salt,
        'must_change_password': 1,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
    return temporal;
  }

  /// Contrasena temporal legible: 'Temp-' + 6 caracteres sin ambiguedades.
  /// Son 11 caracteres, por encima del minimo de 8 que exige la app.
  String _passwordTemporal() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final cuerpo =
        List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    return 'Temp-$cuerpo';
  }

  // ---- codigos de ingreso (solo admin) ----

  Future<String?> generarCodigo(String role) async {
    if (!(_usuario?.esAdmin ?? false)) return null;
    final d = await AppDatabase.instance.db;
    // Sin caracteres confusos (0/O, 1/I/L).
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    String code;
    do {
      code = List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
    } while ((await d.query('invite_codes',
            where: 'code = ?', whereArgs: [code], limit: 1))
        .isNotEmpty);
    await d.insert('invite_codes', {
      'code': code,
      'role': role,
      'created_at': DateTime.now().toIso8601String(),
    });
    return code;
  }

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
