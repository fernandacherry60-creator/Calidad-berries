import type { ExpoConfig, ConfigContext } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'QUALYX Control de Calidad Berries',
  icon: './assets/QUALYX-logo-v2.png',
  slug: 'klunder-tropi',
  owner: 'tropicas-team',
  scheme: 'calidadberriespro',
  version: '1.0.0',
  orientation: 'portrait',
  userInterfaceStyle: 'automatic',
  android: { package: 'com.klunder.calidadberriespro', versionCode: 1, adaptiveIcon: { foregroundImage: './assets/QUALYX-logo-v2.png', backgroundColor: '#FFF9F3' } },
  ios: { bundleIdentifier: 'com.klunder.calidadberriespro', supportsTablet: true },
  plugins: ['expo-secure-store', 'expo-sqlite', 'expo-updates'],
  runtimeVersion: { policy: 'appVersion' },
  updates: {
    url: `https://u.expo.dev/5a29290a-a0bb-41a2-8441-a6f19dd75b70`,
    checkAutomatically: 'ON_LOAD',
    fallbackToCacheTimeout: 0,
  },
  extra: {
    eas: { projectId: '5a29290a-a0bb-41a2-8441-a6f19dd75b70' },
  },
});