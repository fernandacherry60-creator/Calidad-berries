/// Credenciales del backend Supabase (proyecto: calidad-berries).
///
/// La llave publishable es publica por diseno: viaja dentro del APK y las
/// politicas RLS del servidor solo le permiten INSERTAR registros. No puede
/// leer, modificar ni borrar nada. La llave secreta (sb_secret_...) JAMAS
/// debe incluirse en la app.
const String kSupabaseUrl = 'https://rtcncogedsyvnqsdfbeo.supabase.co';
const String kSupabaseKey =
    'sb_publishable_h1F0E17QuZ_R7Q6sfWcG3g_NPMuXL2O';
