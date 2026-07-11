import React from 'react';
import { Text, View } from 'react-native';

import { colors } from '../lib/colors';

export function CaptureReviewScreen() {
  return (
    <View style={{ flex: 1, backgroundColor: colors.ink, padding: 20 }}>
      <Text style={{ color: colors.textMuted }}>Captured fish, measurements, species, bait, and notes.</Text>
    </View>
  );
}
