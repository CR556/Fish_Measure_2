import React from 'react';
import { Text } from 'react-native';

import { ScreenShell } from '../components/ScreenShell';
import { colors } from '../lib/colors';

export function SettingsScreen() {
  return (
    <ScreenShell title="Settings" subtitle="Units, privacy, capture, and OpenAI identification">
      <Text style={{ color: colors.textMuted }}>Imperial units · Location on · Save to Photos off</Text>
    </ScreenShell>
  );
}
