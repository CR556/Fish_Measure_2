import type { ExpoConfig } from 'expo/config';

const config: ExpoConfig = {
  name: 'Fish Measure 2',
  slug: 'fish-measure-2',
  scheme: 'fishmeasure2',
  version: '0.2.2',
  orientation: 'portrait',
  icon: './assets/icon.png',
  userInterfaceStyle: 'dark',
  ios: {
    bundleIdentifier: 'com.fishmeasure2.app',
    buildNumber: '4',
    supportsTablet: false,
    infoPlist: {
      NSCameraUsageDescription:
        'The camera and LiDAR sensor are used to measure fish and photograph catches.',
      NSLocationWhenInUseUsageDescription:
        'Your location can be attached to catches and displayed on your private catch map.',
      NSPhotoLibraryAddUsageDescription:
        'Fish Measure 2 can save exported catch photos to your photo library when you ask it to.',
    },
  },
  plugins: [
    [
      'expo-build-properties',
      {
        ios: {
          deploymentTarget: '17.0',
        },
      },
    ],
    [
      'expo-location',
      {
        locationWhenInUsePermission:
          'Allow Fish Measure 2 to attach your location to catches and show them on your private map.',
      },
    ],
    'expo-sqlite',
    'expo-secure-store',
    'expo-sharing',
  ],
  // Bump whenever native code changes so OTA updates never land on an
  // incompatible binary.
  runtimeVersion: { policy: 'appVersion' },
  // `eas update:configure` fills in updates.url once the EAS project exists.
};

export default config;
