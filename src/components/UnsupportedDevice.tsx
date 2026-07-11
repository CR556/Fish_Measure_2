import React from 'react';
import { StyleSheet, Text, View } from 'react-native';

export function UnsupportedDevice() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>LiDAR not available</Text>
      <Text style={styles.body}>
        Fish Measure 2 requires the rear LiDAR sensor found on iPhone 12 Pro and
        later LiDAR-equipped Pro models. This device cannot provide the depth
        data required for fish measurement.
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
    gap: 16,
  },
  title: {
    color: '#fff',
    fontSize: 24,
    fontWeight: '600',
  },
  body: {
    color: 'rgba(255,255,255,0.75)',
    fontSize: 16,
    lineHeight: 23,
    textAlign: 'center',
  },
});
