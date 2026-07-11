import Constants from 'expo-constants';
import React, { useEffect, useRef, useState } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import type { DistanceEvent, TrackingStateEvent } from '../../modules/fish-measure';

type Props = {
  event: DistanceEvent | null;
  tracking: TrackingStateEvent;
  lastError: string | null;
};

/**
 * The primary no-Xcode diagnostics surface: native truth exposed through JS.
 * Toggled by triple-tapping the distance readout.
 */
export function DebugOverlay({ event, tracking, lastError }: Props) {
  const insets = useSafeAreaInsets();
  const previousTimestamp = useRef<number | null>(null);
  const [hz, setHz] = useState<number | null>(null);

  useEffect(() => {
    if (!event) return;
    if (previousTimestamp.current !== null) {
      const delta = event.timestampMs - previousTimestamp.current;
      if (delta > 0) {
        setHz(1000 / delta);
      }
    }
    previousTimestamp.current = event.timestampMs;
  }, [event]);

  const rows: [string, string][] = [
    ['version', Constants.expoConfig?.version ?? '?'],
    ['tracking', tracking.state + (tracking.reason ? ` (${tracking.reason})` : '')],
    ['mode', event?.mode ?? '—'],
    ['method', event?.method ?? '—'],
    ['raw', event ? `${event.rawMeters.toFixed(3)} m` : '—'],
    ['smoothed', event ? `${event.meters.toFixed(3)} m` : '—'],
    ['confidence', event?.confidence ?? '—'],
    ['rate', hz ? `${hz.toFixed(1)} Hz` : '—'],
    ['last error', lastError ?? 'none'],
  ];

  return (
    <View style={[styles.container, { top: insets.top + 76 }]} pointerEvents="none">
      {rows.map(([label, value]) => (
        <View key={label} style={styles.row}>
          <Text style={styles.label}>{label}</Text>
          <Text style={styles.value}>{value}</Text>
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    position: 'absolute',
    left: 12,
    backgroundColor: 'rgba(0,0,0,0.7)',
    borderRadius: 10,
    padding: 10,
    gap: 2,
    maxWidth: 260,
  },
  row: {
    flexDirection: 'row',
    gap: 8,
  },
  label: {
    color: 'rgba(255,255,255,0.6)',
    fontSize: 12,
    fontVariant: ['tabular-nums'],
    width: 82,
  },
  value: {
    color: '#fff',
    fontSize: 12,
    fontVariant: ['tabular-nums'],
    flexShrink: 1,
  },
});
