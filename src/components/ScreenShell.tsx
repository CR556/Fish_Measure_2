import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { colors } from '../lib/colors';

export function ScreenShell({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle?: string;
  children?: React.ReactNode;
}) {
  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <View style={styles.header}>
        <Text style={styles.title}>{title}</Text>
        {subtitle ? <Text style={styles.subtitle}>{subtitle}</Text> : null}
      </View>
      <View style={styles.body}>{children}</View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.ink },
  header: { paddingHorizontal: 20, paddingTop: 14, paddingBottom: 16 },
  title: { color: colors.text, fontSize: 30, fontWeight: '800', letterSpacing: -0.7 },
  subtitle: { color: colors.textMuted, fontSize: 14, marginTop: 4 },
  body: { flex: 1, paddingHorizontal: 20 },
});
