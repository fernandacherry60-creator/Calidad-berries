import type { ExpoConfig, ConfigContext } from 'expo/config';

const easProjectId =
  process.env.EXPO_PUBLIC_EAS_PROJECT_ID || '4ced7997-9a09-4962-b3d5-222d923b0287';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'QUALYX',
  icon: './assets/QUALYX-logo-v2.png',
  slug: 'fernanda-1',
  owner: 'fer-cherrys-team',
  scheme: 'calidadberriespro',
  version: '1.0.1',
  orientation: 'portrait',
  userInterfaceStyle: 'automatic',
  android: { package: 'com.klunder.calidadberriespro', versionCode: 2, adaptiveIcon: { foregroundImage: './assets/QUALYX-logo-v2.png', backgroundColor: '#FFF9F3' } },
  ios: { bundleIdentifier: 'com.klunder.calidadberriespro', supportsTablet: true },
  plugins: ['expo-secure-store', 'expo-sqlite', 'expo-updates', ['expo-image-picker', { cameraPermission: 'Permitir que QUALYX tome fotografías como evidencia de los muestreos.', photosPermission: 'Permitir que QUALYX adjunte fotografías de evidencia de calidad.' }]],
  runtimeVersion: { policy: 'appVersion' },
  updates: {
    url: `https://u.expo.dev/${easProjectId}`,
    checkAutomatically: 'ON_LOAD',
    fallbackToCacheTimeout: 0,
  },
  extra: {
    eas: { projectId: easProjectId },
  },
});
