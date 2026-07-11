import React from 'react';
import { Text, View } from 'react-native';

import { colors } from '../lib/colors';

export function SpeciesPickerScreen() {
  return (
    <View style={{ flex: 1, backgroundColor: colors.ink, padding: 20 }}>
      <Text style={{ color: colors.textMuted }}>Search freshwater species.</Text>
    </View>
  );
}
