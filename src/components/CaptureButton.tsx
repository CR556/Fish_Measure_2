import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

type Props = {
  onPress: () => void;
  disabled?: boolean;
};

/** Camera-style shutter button. */
export function CaptureButton({ onPress, disabled }: Props) {
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [styles.ring, pressed && styles.ringPressed, disabled && styles.disabled]}
    >
      <View style={styles.core} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  ring: {
    width: 58,
    height: 58,
    borderRadius: 29,
    borderWidth: 3,
    borderColor: '#fff',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.25)',
  },
  ringPressed: {
    transform: [{ scale: 0.92 }],
  },
  core: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: '#fff',
  },
  disabled: {
    opacity: 0.4,
  },
});
