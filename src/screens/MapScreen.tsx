import React from 'react';
import { Text } from 'react-native';

import { ScreenShell } from '../components/ScreenShell';
import { colors } from '../lib/colors';

export function MapScreen() {
  return (
    <ScreenShell title="Catch Map" subtitle="Private locations stored only on this phone">
      <Text style={{ color: colors.textMuted }}>Catch pins will appear here.</Text>
    </ScreenShell>
  );
}
