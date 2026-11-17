import type { ExpoConfig, ConfigContext } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => ({
  ...config,
  name: 'Calidad Berries Pro',
  slug: 'calidad-berries-pro',
  scheme: 'calidadberriespro',
  version: '1.0.0',
  orientation: 'portrait',
  userInterfaceStyle: 'automatic',
  android: { package: 'com.klunder.calidadberriespro', versionCode: 1 },
  ios: { bundleIdentifier: 'com.klunder.calidadberriespro', supportsTablet: true },
  plugins: ['expo-secure-store', 'expo-sqlite', 'expo-updates'],
  runtimeVersion: { policy: 'appVersion' },
  updates: {
    url: process.env.EXPO_PUBLIC_EAS_PROJECT_ID
      ? `https://u.expo.dev/${process.env.EXPO_PUBLIC_EAS_PROJECT_ID}`
      : undefined,
    checkAutomatically: 'ON_LOAD',
    fallbackToCacheTimeout: 0,
  },
  extra: {
    eas: { projectId: process.env.EXPO_PUBLIC_EAS_PROJECT_ID || undefined },
  },
});