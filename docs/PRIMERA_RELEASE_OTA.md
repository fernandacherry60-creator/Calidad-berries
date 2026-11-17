# Preparación de la primera versión de Calidad Berries Pro

Esta es una aplicación **nueva** e independiente. La app original y su Supabase no se modifican.

## Identidad
- Android applicationId: `com.klunder.calidadberriespro`
- Flutter version inicial: `1.0.0+1`
- Supabase nuevo: `zcwtlremnqkptjzlnpao`
- Esquema: autenticación Supabase, perfiles, invitaciones y muestreos; SQLite para captura offline.

## Antes de la primera APK que se distribuirá
1. Configurar en Supabase > Authentication > URL Configuration la URL de redirección permitida `calidadberriespro://auth-callback`. Confirmar que el envío de correo esté habilitado.
2. Probar con dispositivos reales: activación de Fernanda, invitación de un trabajador, confirmación de correo, captura offline, sincronización, vista del admin y aislamiento de usuarios.
3. Registrar la app en una cuenta Shorebird controlada por el propietario y generar su `shorebird.yaml` **real** con `shorebird init`. No inventar `app_id`.
4. Configurar un keystore de firma Android **propio de la nueva app** y guardar la contraseña/keystore en secretos de CI; nunca en Git.
5. Crear la **primera release Shorebird firmada** (no una APK de depuración): `shorebird release android --artifact apk`, tras verificar configuración y firma.
6. Instalar esa release en dispositivos de prueba. Para cambios compatibles de Dart posteriores, usar `shorebird patch android` con la misma app, versión base y firma.
7. Los cambios nativos, permisos, plugins nativos o configuraciones Android que no admitan parche requerirán una nueva release APK.

## Estado de CI
El workflow de esta rama **solo valida** con `flutter analyze` y `flutter test`. Se retiró la compilación automática de APK de depuración para no confundirla con la primera release OTA.

## Notas
- Supabase configura datos y banderas remotas, no distribuye automáticamente código Dart.
- No se debe anunciar soporte OTA activo hasta probar un parche Shorebird en la release instalada.
- El admin ve muestras de equipo vía RLS; trabajadores solo las propias.
- El panel de catálogos aún utiliza SQLite local: requiere sincronización de catálogos antes de declararlo compartido entre teléfonos.
