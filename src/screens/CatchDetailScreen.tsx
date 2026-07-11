import React from 'react';
import { Text, View } from 'react-native';

import { colors } from '../lib/colors';

export function CatchDetailScreen() {
  return (
    <View style={{ flex: 1, backgroundColor: colors.ink, padding: 20 }}>
      <Text style={{ color: colors.textMuted }}>Catch details and export options.</Text>
    </View>
  );
}
