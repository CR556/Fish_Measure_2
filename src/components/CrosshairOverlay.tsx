import React from 'react';
import { StyleSheet, View } from 'react-native';

const ARM = 14;
const THICKNESS = 2;
const GAP = 6;

/** Center reticle: four arms around a small dot, with a gap in the middle. */
export function CrosshairOverlay() {
  return (
    <View style={styles.container} pointerEvents="none">
      <View style={styles.center}>
        <View style={[styles.arm, { top: -(ARM + GAP), width: THICKNESS, height: ARM }]} />
        <View style={[styles.arm, { top: GAP, width: THICKNESS, height: ARM }]} />
        <View style={[styles.arm, { left: -(ARM + GAP), width: ARM, height: THICKNESS }]} />
        <View style={[styles.arm, { left: GAP, width: ARM, height: THICKNESS }]} />
        <View style={styles.dot} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    alignItems: 'center',
    justifyContent: 'center',
  },
  center: {
    width: 0,
    height: 0,
    alignItems: 'center',
    justifyContent: 'center',
  },
  arm: {
    position: 'absolute',
    backgroundColor: '#fff',
    borderRadius: 1,
    shadowColor: '#000',
    shadowOpacity: 0.6,
    shadowRadius: 1,
    shadowOffset: { width: 0, height: 0 },
  },
  dot: {
    position: 'absolute',
    width: 4,
    height: 4,
    borderRadius: 2,
    backgroundColor: '#fff',
  },
});
