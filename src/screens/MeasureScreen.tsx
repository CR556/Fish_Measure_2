import { randomUUID } from 'expo-crypto';
import { Directory, Paths } from 'expo-file-system';
import * as Haptics from 'expo-haptics';
import { useIsFocused, useNavigation } from '@react-navigation/native';
import type { NativeStackNavigationProp } from '@react-navigation/native-stack';
import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  View,
  type GestureResponderEvent,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import {
  FishMeasureView,
  type AutoCapturePayload,
  type FishMeasureViewRef,
  type FishMeasurementEvent,
  type FishMode,
  type ManualCapturePayload,
  type ManualPathMeasurement,
  type SubjectEvent,
  type ViewPoint,
} from '../../modules/fish-measure';
import { MeasurementOverlay } from '../components/measure/MeasurementOverlay';
import { useThrottledStore } from '../hooks/useThrottledStore';
import { colors } from '../lib/colors';
import type { RootStackParamList } from '../navigation/types';
import { useDeviceCapabilities } from '../navigation/DeviceCapabilitiesContext';
import { putCaptureDraft } from '../stores/captureDraftStore';
import {
  clearMeasurementStores,
  measurementStore,
  receiveMeasurement,
  receiveSubject,
  subjectStore,
} from '../stores/measurementStores';

const AUTO_CAPTURE_COOLDOWN_MS = 4000;

function gateMessage(subject: SubjectEvent | null, measurement: FishMeasurementEvent | null) {
  if (!subject || subject.state === 'none') return 'Fit a real fish or fish-shaped object inside the outline';
  if (subject.state === 'candidate') return 'Fish-shaped subject found — hold it steady';
  if (!subject.fishGatePassed) return 'Shape locked — classifier is still checking the subject';
  if (!measurement) return 'Shape locked — tilt slightly to improve LiDAR depth';
  if (measurement.depthCoverage < 0.6) return 'Low depth coverage — reduce glare or move closer';
  if (!measurement.stable) return 'Measurement found — hold steady';
  return 'Stable — ready to capture';
}

function safelyDeleteDirectory(uri: string) {
  try {
    const directory = new Directory(uri);
    if (directory.exists) directory.delete();
  } catch {
    // Draft cleanup is best-effort; cache cleanup can remove leftovers later.
  }
}

export function MeasureScreen() {
  const navigation = useNavigation<NativeStackNavigationProp<RootStackParamList>>();
  const isFocused = useIsFocused();
  const { lidarSupported } = useDeviceCapabilities();
  const viewRef = useRef<FishMeasureViewRef>(null);
  const previousSubjectState = useRef<SubjectEvent['state']>('none');
  const previousAutoEligible = useRef(false);
  const lastCaptureAt = useRef(0);
  const capturingRef = useRef(false);
  const toastTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [mode, setMode] = useState<Exclude<FishMode, 'off'>>('auto');
  const [capturing, setCapturing] = useState(false);
  const [toast, setToast] = useState<string | null>(null);
  const [manualPoints, setManualPoints] = useState<ViewPoint[]>([]);
  const [manualMeasurement, setManualMeasurement] = useState<ManualPathMeasurement | null>(null);
  const measurement = useThrottledStore(measurementStore, 100);
  const subject = useThrottledStore(subjectStore, 100);

  const showToast = useCallback((message: string) => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
    setToast(message);
    toastTimer.current = setTimeout(() => setToast(null), 2600);
  }, []);

  useEffect(() => () => {
    if (toastTimer.current) clearTimeout(toastTimer.current);
  }, []);

  useEffect(() => {
    if (!isFocused) {
      clearMeasurementStores();
      previousAutoEligible.current = false;
    }
  }, [isFocused]);

  const createOutputDirectory = useCallback(() => {
    const id = randomUUID();
    const directory = new Directory(Paths.cache, 'fish-measure-drafts', id);
    directory.create({ intermediates: true, idempotent: true });
    return { id, directory };
  }, []);

  const finishCapture = useCallback((
    id: string,
    outputDirectoryUri: string,
    captureMode: 'auto' | 'manual',
    payload: AutoCapturePayload | ManualCapturePayload
  ) => {
    putCaptureDraft({ id, outputDirectoryUri, mode: captureMode, payload });
    lastCaptureAt.current = Date.now();
    void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    navigation.navigate('CaptureReview', { draftId: id });
  }, [navigation]);

  const captureAuto = useCallback(async () => {
    if (capturingRef.current) return;
    capturingRef.current = true;
    setCapturing(true);
    const { id, directory } = createOutputDirectory();
    try {
      const payload = await viewRef.current?.captureAutoCatch({
        outputDir: directory.uri,
        includePly: false,
        includeMaskPng: true,
        jpegQuality: 0.92,
      });
      if (!payload) {
        safelyDeleteDirectory(directory.uri);
        showToast('No stable 3D measurement yet');
        void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
        return;
      }
      finishCapture(id, directory.uri, 'auto', payload);
    } catch (error) {
      safelyDeleteDirectory(directory.uri);
      showToast(error instanceof Error ? error.message : 'Capture failed');
      void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
    } finally {
      capturingRef.current = false;
      setCapturing(false);
    }
  }, [createOutputDirectory, finishCapture, showToast]);

  const captureManual = useCallback(async () => {
    if (capturingRef.current || manualPoints.length < 2) {
      showToast('Tap the nose and tail first');
      return;
    }
    capturingRef.current = true;
    setCapturing(true);
    const { id, directory } = createOutputDirectory();
    try {
      const payload = await viewRef.current?.captureManualCatch(manualPoints, {
        outputDir: directory.uri,
        includePly: false,
        includeMaskPng: false,
        jpegQuality: 0.92,
      });
      if (!payload) {
        safelyDeleteDirectory(directory.uri);
        showToast('LiDAR could not measure that path — try again');
        return;
      }
      finishCapture(id, directory.uri, 'manual', payload);
    } catch (error) {
      safelyDeleteDirectory(directory.uri);
      showToast(error instanceof Error ? error.message : 'Manual capture failed');
    } finally {
      capturingRef.current = false;
      setCapturing(false);
    }
  }, [createOutputDirectory, finishCapture, manualPoints, showToast]);

  const handleSubject = useCallback((event: { nativeEvent: SubjectEvent }) => {
    const next = event.nativeEvent;
    receiveSubject(next);
    if (next.state === 'candidate' && previousSubjectState.current === 'none') {
      void Haptics.selectionAsync();
    }
    if (next.state === 'locked' && previousSubjectState.current !== 'locked') {
      void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
    }
    previousSubjectState.current = next.state;
  }, []);

  const handleMeasurement = useCallback((event: { nativeEvent: FishMeasurementEvent }) => {
    const next = event.nativeEvent;
    receiveMeasurement(next);
    const eligibleEdge = next.autoCaptureEligible && !previousAutoEligible.current;
    previousAutoEligible.current = next.autoCaptureEligible;
    if (eligibleEdge && Date.now() - lastCaptureAt.current >= AUTO_CAPTURE_COOLDOWN_MS) {
      void captureAuto();
    }
  }, [captureAuto]);

  const handleCameraPress = useCallback(async (event: GestureResponderEvent) => {
    const point = {
      x: event.nativeEvent.locationX,
      y: event.nativeEvent.locationY,
    };
    if (mode === 'auto') {
      await viewRef.current?.setTapHint(point.x, point.y);
      showToast('Selection focused here');
      void Haptics.selectionAsync();
      return;
    }
    const nextPoints = manualPoints.length >= 2 ? [point] : [...manualPoints, point];
    setManualPoints(nextPoints);
    setManualMeasurement(null);
    if (nextPoints.length === 2) {
      const result = await viewRef.current?.measureManualPath(nextPoints, 48);
      setManualMeasurement(result ?? null);
      if (result) void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      else showToast('No usable LiDAR depth on that path');
    }
  }, [manualPoints, mode, showToast]);

  const changeMode = useCallback((nextMode: 'auto' | 'manual') => {
    setMode(nextMode);
    setManualPoints([]);
    setManualMeasurement(null);
    clearMeasurementStores();
    previousAutoEligible.current = false;
    void viewRef.current?.clearSubject();
  }, []);

  const displayedMeters = mode === 'manual'
    ? manualMeasurement?.curvedM ?? null
    : measurement?.curvedM ?? null;
  const inches = displayedMeters == null ? null : displayedMeters * 39.3700787402;
  const status = mode === 'manual'
    ? manualPoints.length === 0
      ? 'Tap the nose, then the tail'
      : manualPoints.length === 1
        ? 'Now tap the tail'
        : manualMeasurement
          ? 'Manual path measured — ready to capture'
          : 'Checking LiDAR depth…'
    : gateMessage(subject, measurement);
  const topClassifier = subject?.classifierTop[0];

  return (
    <SafeAreaView style={styles.safe} edges={['top']}>
      <View style={styles.camera}>
        {isFocused && lidarSupported ? (
          <FishMeasureView
            ref={viewRef}
            mode={mode}
            updateHz={15}
            enableSceneReconstruction={mode === 'manual'}
            enableHighResCapture
            segmentation={{
              hz: 10,
              depthSource: 'smoothed',
              visionOrientation: 'right',
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
              requiredForAutoCapture: false,
            }}
            tracking={{ minCandidateFrames: 2, minLockFrames: 4, lostGraceMs: 350 }}
            centerline={{
              algorithm: 'pca',
              bins: 48,
              depthTransverseSamples: 7,
              depthTransverseInsetFraction: 0.15,
              depthForegroundQuantile: 0.25,
              maxDepthStepM: 0.08,
              maxDepthStepFraction: 0.12,
              depthEnvelopeMarginM: 0.05,
            }}
            stability={{
              windowMs: 750,
              maxDeltaCm: 1,
              maxDeltaFraction: 0.025,
              trimOutlierFrames: 1,
              minDepthCoverage: 0.6,
            }}
            overlay={{ contourMaxPoints: 120, emitCenterline: true }}
            debugMode
            onSubject={handleSubject}
            onFishMeasurement={handleMeasurement}
            onError={(event) => showToast(event.nativeEvent.message)}
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

        <Pressable style={StyleSheet.absoluteFill} onPress={handleCameraPress} />
        <MeasurementOverlay
          subject={mode === 'auto' ? subject : null}
          measurement={mode === 'auto' ? measurement : null}
          manualPoints={mode === 'manual' ? manualPoints : []}
        />

        <View style={styles.topBar} pointerEvents="box-none">
          <Text style={styles.brand}>FISH MEASURE 2</Text>
          <View style={styles.modeSwitch}>
            {(['auto', 'manual'] as const).map((value) => (
              <Pressable
                key={value}
                onPress={() => changeMode(value)}
                style={[styles.modeOption, mode === value && styles.modeOptionActive]}
              >
                <Text style={[styles.modeText, mode === value && styles.modeTextActive]}>
                  {value.toUpperCase()}
                </Text>
              </Pressable>
            ))}
          </View>
        </View>

        {mode === 'auto' && subject ? (
          <View style={styles.diagnostics} pointerEvents="none">
            <Text style={styles.diagnosticText}>
              {subject.state.toUpperCase()} · shape {Math.round(subject.fishScore * 100)}%
            </Text>
            <Text style={styles.diagnosticText}>
              {measurement
                ? `depth ${Math.round(measurement.depthCoverage * 100)}% · ${measurement.distanceM.toFixed(2)} m`
                : topClassifier
                  ? `${topClassifier.label} ${Math.round(topClassifier.confidence * 100)}%`
                  : 'waiting for classifier/depth'}
            </Text>
            {measurement?.stabilitySpreadM != null &&
            measurement.stabilityAllowedDeltaM != null ? (
              <Text style={styles.diagnosticText}>
                spread {(measurement.stabilitySpreadM * 100).toFixed(1)} /{' '}
                {(measurement.stabilityAllowedDeltaM * 100).toFixed(1)} cm
              </Text>
            ) : null}
          </View>
        ) : null}

        <View style={styles.readout} pointerEvents="none">
          <View style={styles.measurementRow}>
            <Text style={styles.readoutValue}>{inches == null ? '—.—' : inches.toFixed(1)}</Text>
            <Text style={styles.readoutUnit}>in</Text>
          </View>
          <Text style={styles.readoutHint}>{status}</Text>
        </View>

        <Pressable
          disabled={capturing}
          onPress={() => void (mode === 'auto' ? captureAuto() : captureManual())}
          style={({ pressed }) => [
            styles.captureButton,
            pressed && styles.captureButtonPressed,
            capturing && styles.captureButtonDisabled,
          ]}
        >
          {capturing ? <ActivityIndicator color={colors.ink} /> : <View style={styles.captureInner} />}
        </Pressable>

        {toast ? (
          <View style={styles.toast} pointerEvents="none">
            <Text style={styles.toastText}>{toast}</Text>
          </View>
        ) : null}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.cameraInk },
  camera: { flex: 1, overflow: 'hidden', backgroundColor: colors.cameraInk },
  unsupported: {
    position: 'absolute', inset: 0, alignItems: 'center', justifyContent: 'center', padding: 36,
  },
  unsupportedTitle: { color: colors.text, fontSize: 20, fontWeight: '800' },
  unsupportedText: { color: colors.textMuted, textAlign: 'center', lineHeight: 21, marginTop: 8 },
  topBar: {
    position: 'absolute', top: 14, left: 16, right: 16,
    flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center',
  },
  brand: { color: colors.text, fontSize: 13, fontWeight: '900', letterSpacing: 1.6 },
  modeSwitch: {
    flexDirection: 'row', padding: 3, borderRadius: 99,
    backgroundColor: 'rgba(7,16,20,0.82)', borderColor: colors.border, borderWidth: 1,
  },
  modeOption: { borderRadius: 99, paddingHorizontal: 10, paddingVertical: 6 },
  modeOptionActive: { backgroundColor: colors.aqua },
  modeText: { color: colors.textMuted, fontSize: 10, fontWeight: '900', letterSpacing: 0.8 },
  modeTextActive: { color: colors.ink },
  diagnostics: {
    position: 'absolute', top: 62, left: 16, paddingHorizontal: 10, paddingVertical: 7,
    borderRadius: 10, backgroundColor: 'rgba(7,16,20,0.72)',
  },
  diagnosticText: { color: colors.textMuted, fontSize: 10, lineHeight: 15 },
  readout: {
    position: 'absolute', left: 18, right: 18, bottom: 103,
    backgroundColor: 'rgba(7,16,20,0.86)', borderColor: colors.border, borderWidth: 1,
    borderRadius: 20, paddingVertical: 11, paddingHorizontal: 14, alignItems: 'center',
  },
  measurementRow: { flexDirection: 'row', alignItems: 'baseline' },
  readoutValue: {
    color: colors.text, fontSize: 34, fontWeight: '800', fontVariant: ['tabular-nums'],
  },
  readoutUnit: { color: colors.aqua, fontSize: 18, fontWeight: '800', marginLeft: 5 },
  readoutHint: { color: colors.textMuted, fontSize: 12, textAlign: 'center', marginTop: 2 },
  captureButton: {
    position: 'absolute', bottom: 22, alignSelf: 'center', width: 66, height: 66,
    borderRadius: 33, borderColor: colors.white, borderWidth: 3, padding: 5,
    alignItems: 'center', justifyContent: 'center',
  },
  captureButtonPressed: { transform: [{ scale: 0.94 }] },
  captureButtonDisabled: { opacity: 0.65 },
  captureInner: { width: '100%', height: '100%', borderRadius: 99, backgroundColor: colors.white },
  toast: {
    position: 'absolute', alignSelf: 'center', bottom: 188, maxWidth: '86%',
    backgroundColor: colors.panelRaised, borderColor: colors.border, borderWidth: 1,
    borderRadius: 12, paddingHorizontal: 14, paddingVertical: 9,
  },
  toastText: { color: colors.text, fontSize: 12, fontWeight: '700', textAlign: 'center' },
});
