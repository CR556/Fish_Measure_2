import { NavigationContainer, DarkTheme } from '@react-navigation/native';
import { StatusBar } from 'expo-status-bar';
import React, { useEffect } from 'react';
import { SafeAreaProvider } from 'react-native-safe-area-context';

import { isLidarSupported } from './modules/fish-measure';
import { AppNavigator } from './src/navigation/AppNavigator';
import { DeviceCapabilitiesProvider } from './src/navigation/DeviceCapabilitiesContext';
import { colors } from './src/lib/colors';
import { getDatabase } from './src/db/database';
import { cleanupAbandonedStagingDirectories } from './src/lib/files';

function detectLidarSupport() {
  try {
    return isLidarSupported();
  } catch {
    return false;
  }
}

const navigationTheme = {
  ...DarkTheme,
  colors: {
    ...DarkTheme.colors,
    primary: colors.aqua,
    background: colors.ink,
    card: colors.panel,
    border: colors.border,
    text: colors.text,
    notification: colors.amber,
  },
};

export default function App() {
  useEffect(() => {
    cleanupAbandonedStagingDirectories();
    void getDatabase();
  }, []);

  return (
    <SafeAreaProvider>
      <DeviceCapabilitiesProvider lidarSupported={detectLidarSupport()}>
        <NavigationContainer theme={navigationTheme}>
          <StatusBar style="light" />
          <AppNavigator />
        </NavigationContainer>
      </DeviceCapabilitiesProvider>
    </SafeAreaProvider>
  );
}
