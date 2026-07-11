import { useIsFocused } from '@react-navigation/native';
import React, { useEffect } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { FishMeasureView } from '../../modules/fish-measure';
import { colors } from '../lib/colors';
import { useDeviceCapabilities } from '../navigation/DeviceCapabilitiesContext';
import { useThrottledStore } from '../hooks/useThrottledStore';
import {
  clearMeasurementStores,
  measurementStore,
  receiveMeasurement,
  receiveSubject,
  subjectStore,
} from '../stores/measurementStores';

export function MeasureScreen() {
  const isFocused = useIsFocused();
  const { lidarSupported } = useDeviceCapabilities();
  const measurement = useThrottledStore(measurementStore, 100);
  const subject = useThrottledStore(subjectStore, 100);
  useEffect(() => {
    if (!isFocused) clearMeasurementStores();
  }, [isFocused]);
  const inches = measurement ? measurement.curvedM * 39.3700787402 : null;

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <View style={styles.camera}>
        {isFocused && lidarSupported ? (
          <FishMeasureView
            mode="auto"
            updateHz={15}
            enableSceneReconstruction={false}
            enableHighResCapture
            segmentation={{
              hz: 10,
              depthSource: 'smoothed',
              personExclusion: true,
              personMaskDilationPx: 2,
              subjectClosingPx: 2,
              priorityRegion: { x: 0.12, y: 0.31, w: 0.76, h: 0.28 },
            }}
            classifier={{
              enabled: true,
              hz: 2,
              minConfidence: 0.15,
              acceptLabels: ['fish', 'tench', 'goldfish', 'coho', 'sturgeon', 'gar', 'eel'],
              vetoLabels: ['person', 'hand', 'rock', 'net'],
              requiredForAutoCapture: true,
            }}
            tracking={{ minCandidateFrames: 2, minLockFrames: 4, lostGraceMs: 350 }}
            centerline={{ algorithm: 'pca', bins: 48 }}
            stability={{ windowMs: 750, minDepthCoverage: 0.7 }}
            overlay={{ contourMaxPoints: 120, emitCenterline: true }}
            onSubject={(event) => receiveSubject(event.nativeEvent)}
            onFishMeasurement={(event) => receiveMeasurement(event.nativeEvent)}
            style={StyleSheet.absoluteFill}
          />
        ) : (
          <View style={styles.unsupported}>
            <Text style={styles.unsupportedTitle}>LiDAR iPhone required</Text>
            <Text style={styles.unsupportedText}>
              Fish measurement runs on iPhone 12 Pro and newer LiDAR-equipped Pro models.
            </Text>
          </View>
        )}

        <View pointerEvents="none" style={styles.ghost}>
          <Text style={styles.ghostText}>FISH OUTLINE</Text>
        </View>
        <View style={styles.topBar}>
          <Text style={styles.brand}>FISH MEASURE 2</Text>
          <View style={styles.modeChip}>
            <Text style={styles.modeText}>{subject?.state.toUpperCase() ?? 'AUTO'}</Text>
          </View>
        </View>
        <View style={styles.readout}>
          <Text style={styles.readoutValue}>{inches == null ? '—.—' : inches.toFixed(1)}</Text>
          <Text style={styles.readoutUnit}>in</Text>
          <Text style={styles.readoutHint}>
            {measurement?.autoCaptureEligible
              ? 'Stable — ready to capture'
              : subject?.state === 'locked'
                ? 'Hold steady'
                : 'Fit the fish inside the outline'}
          </Text>
        </View>
        <View style={styles.captureButton}>
          <View style={styles.captureInner} />
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.cameraInk },
  camera: { flex: 1, overflow: 'hidden', backgroundColor: colors.cameraInk },
  unsupported: { position: 'absolute', inset: 0, alignItems: 'center', justifyContent: 'center', padding: 36 },
  unsupportedTitle: { color: colors.text, fontSize: 20, fontWeight: '800' },
  unsupportedText: { color: colors.textMuted, textAlign: 'center', lineHeight: 21, marginTop: 8 },
  topBar: { position: 'absolute', top: 16, left: 18, right: 18, flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  brand: { color: colors.text, fontSize: 13, fontWeight: '900', letterSpacing: 1.6 },
  modeChip: { backgroundColor: 'rgba(49,214,196,0.16)', borderColor: colors.aqua, borderWidth: 1, borderRadius: 99, paddingHorizontal: 12, paddingVertical: 6 },
  modeText: { color: colors.aqua, fontSize: 11, fontWeight: '900', letterSpacing: 1 },
  ghost: { position: 'absolute', left: '12%', right: '12%', top: '32%', height: '25%', borderWidth: 2, borderColor: 'rgba(49,214,196,0.55)', borderRadius: 999, borderStyle: 'dashed', alignItems: 'center', justifyContent: 'center' },
  ghostText: { color: 'rgba(49,214,196,0.8)', fontSize: 11, fontWeight: '800', letterSpacing: 1.5 },
  readout: { position: 'absolute', left: 20, right: 20, bottom: 112, backgroundColor: 'rgba(7,16,20,0.82)', borderColor: colors.border, borderWidth: 1, borderRadius: 20, paddingVertical: 12, alignItems: 'center', flexDirection: 'row', justifyContent: 'center' },
  readoutValue: { color: colors.text, fontSize: 34, fontWeight: '800', fontVariant: ['tabular-nums'] },
  readoutUnit: { color: colors.aqua, fontSize: 18, fontWeight: '800', marginLeft: 5, marginTop: 8 },
  readoutHint: { position: 'absolute', bottom: -24, color: colors.textMuted, fontSize: 12 },
  captureButton: { position: 'absolute', bottom: 24, alignSelf: 'center', width: 66, height: 66, borderRadius: 33, borderColor: colors.white, borderWidth: 3, padding: 5 },
  captureInner: { flex: 1, borderRadius: 99, backgroundColor: colors.white },
});
