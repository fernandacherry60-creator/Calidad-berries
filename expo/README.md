# Calidad Berries Pro — nueva aplicación Expo

Esta carpeta es una **migración nueva a Expo + React Native + TypeScript**. El código Flutter de referencia se conserva en la raíz, sin modificaciones para instalar Expo. La app original distribuida a la clienta no se actualiza por estos cambios.

## Funcionalidades migradas

- Supabase Auth: inicio de sesión, activación de Fernanda con su correo autorizado, registro por invitación de un solo uso.
- Perfil de administradora/trabajador desde `cb_profiles` y políticas RLS.
- Panel de equipo: crear invitaciones de 12 caracteres, ver trabajadores y muestras de la nube.
- Muestreos de andén, proceso y semáforo; catálogos oficiales y motor de cálculo v1.5 migrados a TypeScript.
- Expo SQLite: guarda capturas en el teléfono, con propietario UUID y estado de sincronización.
- Reintentos de sincronización a Supabase con verificación de UUID duplicado y separación por cuenta.
- Captura offline para usuarios con perfil previamente verificado, almacenado en SecureStore.
- Configuración remota de banderas de módulos en `cb_app_config`.
- Configuración base de EAS Build y EAS Update (requiere registro del proyecto).

## Ejecutar en Windows

```powershell
git clone https://github.com/tropicana1930-ship-it/Calidad-berries.git
cd Calidad-berries
git checkout feature/paneles-admin-trabajador-20261117
cd expo
Copy-Item .env.example .env
npm install
npx expo install --fix
npx tsc --noEmit
npx expo start
```

Para distribuir APK real, iniciar sesión en Expo/EAS con una cuenta propiedad del cliente:

```powershell
npx eas-cli login
npx eas-cli init
npx eas-cli update:configure
npx eas-cli build --platform android --profile preview
```

Guardar el **ID real de EAS** en `EXPO_PUBLIC_EAS_PROJECT_ID`, confirmar que `app.config.ts` incluye `updates.url`, generar build inicial y verificar en un dispositivo.

Para publicar actualizaciones compatibles de JavaScript/TypeScript y estilos:

```powershell
npx eas-cli update --branch preview --message "Mejoras de Calidad Berries Pro"
```

Las actualizaciones solo llegan a compilaciones con canal y runtime compatibles. Cambios nativos, plugins nativos o permisos requieren otra compilación.

## Pendientes antes de entrega

1. En Supabase Auth > URL Configuration, agregar `calidadberriespro://auth-callback` como URL de redirección autorizada.
2. Probar activación de Fernanda, correo del trabajador, canje de código y separación de cuentas.
3. Probar formularios y cálculos contra las hojas originales y muestras reales. La nueva UI es funcional pero todavía no reproduce todos los reportes, fotografías, exportación Excel y detalles avanzados del Flutter de referencia.
4. Confirmar peso mínimo por presentación, tolerancias y campos obligatorios con la clienta.
5. Probar conexión/desconexión, colas SQLite, sincronización y lectura desde otro teléfono.
6. Configurar EAS en una cuenta autorizada, crear APK de prueba y verificar una actualización OTA real.
7. Revisar CI, ejecutar TypeScript, Expo Doctor y pruebas de dispositivo.

**No declarar la migración lista para producción hasta cerrar estos puntos.**
