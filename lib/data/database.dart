import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Acceso unico a SQLite. Todas las consultas usan parametros (?) para
/// prevenir inyeccion SQL. La base vive en el almacenamiento privado de la
/// app (otras apps no pueden leerla).
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _db;

  Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      join(dir, 'calidad_berries.db'),
      version: 4,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: _createSchema,
      onUpgrade: _upgrade,
    );
  }

  Future<void> _createSchema(Database d, int v) async {
    await d.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        puesto TEXT NOT NULL DEFAULT '',
        password_hash TEXT NOT NULL,
        salt TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'usuario',
        active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        must_change_password INTEGER NOT NULL DEFAULT 0
      )''');

    // Codigos de ingreso: nadie puede crear cuenta sin un codigo vigente
    // generado por el administrador. Un codigo es de un solo uso y define
    // el nivel de acceso (usuario o admin). El puesto lo elige la persona
    // al registrarse y es informativo.
    await d.execute('''
      CREATE TABLE invite_codes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        role TEXT NOT NULL,
        used_by INTEGER REFERENCES users(id),
        created_at TEXT NOT NULL,
        used_at TEXT
      )''');

    await d.execute('''
      CREATE TABLE ranchos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE
      )''');

    await d.execute('''
      CREATE TABLE variedades(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cultivo TEXT NOT NULL,
        nombre TEXT NOT NULL
      )''');

    await d.execute('''
      CREATE TABLE muestreos_anden(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        user_id INTEGER NOT NULL REFERENCES users(id),
        cultivo TEXT NOT NULL,
        rancho TEXT NOT NULL,
        sector TEXT NOT NULL,
        variedad TEXT NOT NULL,
        presentacion TEXT NOT NULL,
        cuadrilla TEXT NOT NULL,
        cajas_recibidas INTEGER NOT NULL,
        canastos INTEGER NOT NULL,
        fruta_muestra INTEGER NOT NULL,
        licencia TEXT NOT NULL,
        grados_brix REAL,
        peso REAL,
        frutos_larva INTEGER NOT NULL DEFAULT 0,
        evaluador TEXT NOT NULL DEFAULT '',
        muestreados TEXT NOT NULL DEFAULT '',
        defectos_json TEXT NOT NULL,
        fotos_json TEXT NOT NULL DEFAULT '[]',
        pct_condicion REAL NOT NULL,
        pct_apariencia REAL NOT NULL,
        puntos_condicion INTEGER NOT NULL,
        puntos_apariencia INTEGER NOT NULL,
        puntos_total INTEGER NOT NULL,
        disposicion TEXT NOT NULL,
        motivo TEXT NOT NULL DEFAULT '',
        fecha TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pendiente'
      )''');
    await d.execute(
        'CREATE INDEX idx_anden_user_fecha ON muestreos_anden(user_id, fecha DESC)');
    await d.execute(
        'CREATE INDEX idx_anden_rancho_fecha ON muestreos_anden(rancho, fecha DESC)');

    await d.execute('''
      CREATE TABLE muestreos_proceso(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        user_id INTEGER NOT NULL REFERENCES users(id),
        cultivo TEXT NOT NULL,
        frutos_muestra INTEGER,
        rancho TEXT NOT NULL DEFAULT '',
        cajas INTEGER,
        taras INTEGER,
        pct_proceso REAL,
        defectos_json TEXT NOT NULL,
        area_agronomia REAL NOT NULL,
        area_poscosecha REAL NOT NULL,
        area_cosecha REAL NOT NULL,
        area_actividades REAL NOT NULL,
        area_inocuidad REAL NOT NULL,
        total_defectos REAL NOT NULL,
        potencial_empacable REAL NOT NULL,
        fecha TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pendiente'
      )''');
    await d.execute(
        'CREATE INDEX idx_proc_user_fecha ON muestreos_proceso(user_id, fecha DESC)');

    await d.execute('''
      CREATE TABLE semaforo(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        user_id INTEGER NOT NULL REFERENCES users(id),
        cultivo TEXT NOT NULL,
        categoria TEXT NOT NULL,
        nivel TEXT NOT NULL,
        nota TEXT,
        fecha TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pendiente'
      )''');

    await _seed(d);
  }

  /// Migraciones. Cada version agrega SOLO columnas nuevas: los datos
  /// existentes (incluidos los pendientes de sincronizar) nunca se tocan.
  ///
  /// v2 (app 1.3.0): evaluador y muestreados en muestreos_anden;
  /// frutos_muestra en muestreos_proceso.
  /// v3 (app 1.4.0): rancho, cajas, taras y pct_proceso en
  /// muestreos_proceso (porcentaje de proceso del Excel de la clienta).
  /// IMPORTANTE: estas mismas columnas deben existir en Supabase ANTES
  /// de distribuir el APK (ver migracion_supabase_v1.4.sql), porque el
  /// sync sube todas las columnas locales.
  /// v4 (app 1.6.0): must_change_password en users. NO requiere migracion
  /// en Supabase: la tabla users es 100% local, nunca se sincroniza.
  Future<void> _upgrade(Database d, int oldV, int newV) async {
    if (oldV < 2) {
      await d.execute(
          "ALTER TABLE muestreos_anden ADD COLUMN evaluador TEXT NOT NULL DEFAULT ''");
      await d.execute(
          "ALTER TABLE muestreos_anden ADD COLUMN muestreados TEXT NOT NULL DEFAULT ''");
      await d.execute(
          'ALTER TABLE muestreos_proceso ADD COLUMN frutos_muestra INTEGER');
    }
    if (oldV < 3) {
      await d.execute(
          "ALTER TABLE muestreos_proceso ADD COLUMN rancho TEXT NOT NULL DEFAULT ''");
      await d.execute(
          'ALTER TABLE muestreos_proceso ADD COLUMN cajas INTEGER');
      await d.execute(
          'ALTER TABLE muestreos_proceso ADD COLUMN taras INTEGER');
      await d.execute(
          'ALTER TABLE muestreos_proceso ADD COLUMN pct_proceso REAL');
    }
    if (oldV < 4) {
      await d.execute(
          'ALTER TABLE users ADD COLUMN must_change_password INTEGER NOT NULL DEFAULT 0');
    }
  }

  /// Catalogos oficiales del cliente (tabla WhatsApp). El admin puede
  /// ampliar desde Administracion.
  Future<void> _seed(Database d) async {
    const ranchos = [
      'ALEGRE 1',
      'ALEGRE 3',
      'ALEGRE 4',
      'NOGAL',
      'DERRAMADERO',
      'BLANCO',
      'CATARINA',
    ];
    for (final r in ranchos) {
      await d.insert('ranchos', {'nombre': r});
    }
    const variedades = ['MYA', 'MARILYN', 'FRYDA'];
    for (final v in variedades) {
      await d.insert('variedades', {'cultivo': 'Frambuesa', 'nombre': v});
    }
  }
}
