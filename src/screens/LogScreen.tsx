import React from 'react';
import { Text } from 'react-native';

import { ScreenShell } from '../components/ScreenShell';
import { colors } from '../lib/colors';

export function LogScreen() {
  return (
    <ScreenShell title="Catch Log" subtitle="Search, filter, and compare your catches">
      <Text style={{ color: colors.textMuted }}>Your saved catches will appear here.</Text>
    </ScreenShell>
  );
}
