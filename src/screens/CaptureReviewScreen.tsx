import { Directory } from 'expo-file-system';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import React, { useCallback, useEffect, useMemo, useRef } from 'react';
import { Image, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

import { colors } from '../lib/colors';
import type { RootStackParamList } from '../navigation/types';
import { getCaptureDraft, removeCaptureDraft } from '../stores/captureDraftStore';

type Props = NativeStackScreenProps<RootStackParamList, 'CaptureReview'>;

function imageUri(path: string) {
  return path.startsWith('file://') ? path : `file://${path}`;
}

function deleteDraft(id: string) {
  const draft = removeCaptureDraft(id);
  if (!draft) return;
  try {
    const directory = new Directory(draft.outputDirectoryUri);
    if (directory.exists) directory.delete();
  } catch {
    // Cache cleanup is best-effort.
  }
}

export function CaptureReviewScreen({ navigation, route }: Props) {
  const accepted = useRef(false);
  const draft = useMemo(() => getCaptureDraft(route.params.draftId), [route.params.draftId]);

  useEffect(() => navigation.addListener('beforeRemove', () => {
    if (!accepted.current) deleteDraft(route.params.draftId);
  }), [navigation, route.params.draftId]);

  const discard = useCallback(() => {
    deleteDraft(route.params.draftId);
    navigation.goBack();
  }, [navigation, route.params.draftId]);

  const acceptPreview = useCallback(() => {
    accepted.current = true;
    navigation.goBack();
  }, [navigation]);

  if (!draft) {
    return (
      <SafeAreaView style={styles.safe}>
        <View style={styles.missing}>
          <Text style={styles.title}>Capture unavailable</Text>
          <Text style={styles.muted}>The temporary capture was already removed.</Text>
          <Pressable onPress={() => navigation.goBack()} style={styles.secondaryButton}>
            <Text style={styles.secondaryText}>Back to camera</Text>
          </Pressable>
        </View>
      </SafeAreaView>
    );
  }

  const payload = draft.payload;
  const previewPath = payload.photoRegistration.annotatedPhotoPath ?? payload.photoPath;
  const lengthIn = payload.curvedM * 39.3700787402;
  const chordIn = payload.chordM * 39.3700787402;

  return (
    <SafeAreaView style={styles.safe} edges={['bottom']}>
      <ScrollView contentContainerStyle={styles.content}>
        <Image source={{ uri: imageUri(previewPath) }} style={styles.photo} resizeMode="contain" />
        <View style={styles.card}>
          <Text style={styles.eyebrow}>{draft.mode.toUpperCase()} MEASUREMENT</Text>
          <Text style={styles.length}>{lengthIn.toFixed(1)} in</Text>
          <Text style={styles.muted}>Curve-corrected length</Text>
          <View style={styles.metrics}>
            <Metric label="Straight chord" value={`${chordIn.toFixed(1)} in`} />
            <Metric label="Depth coverage" value={`${Math.round(payload.depthCoverage * 100)}%`} />
            <Metric label="Confidence" value={`${Math.round(payload.confidence * 100)}%`} />
            <Metric label="Distance" value={`${payload.distanceM.toFixed(2)} m`} />
          </View>
          <Text style={styles.registration}>
            Photo: {payload.photoSource} · overlay {payload.photoRegistration.status}
          </Text>
        </View>
        <Text style={styles.notice}>
          This is the M2 capture preview. Accepting keeps the draft available for the upcoming
          persistence milestone; it is not in the Catch Log yet.
        </Text>
        <View style={styles.actions}>
          <Pressable onPress={discard} style={[styles.button, styles.discardButton]}>
            <Text style={styles.buttonText}>Discard</Text>
          </Pressable>
          <Pressable onPress={acceptPreview} style={[styles.button, styles.acceptButton]}>
            <Text style={[styles.buttonText, styles.acceptText]}>Accept Preview</Text>
          </Pressable>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.metric}>
      <Text style={styles.metricLabel}>{label}</Text>
      <Text style={styles.metricValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  safe: { flex: 1, backgroundColor: colors.ink },
  content: { padding: 18, paddingBottom: 28 },
  photo: { width: '100%', aspectRatio: 3 / 4, backgroundColor: colors.black, borderRadius: 18 },
  card: {
    marginTop: 16, padding: 18, borderRadius: 18,
    backgroundColor: colors.panel, borderColor: colors.border, borderWidth: 1,
  },
  eyebrow: { color: colors.aqua, fontSize: 11, fontWeight: '900', letterSpacing: 1.3 },
  length: { color: colors.text, fontSize: 42, fontWeight: '900', marginTop: 8 },
  title: { color: colors.text, fontSize: 22, fontWeight: '800' },
  muted: { color: colors.textMuted, fontSize: 13 },
  metrics: { flexDirection: 'row', flexWrap: 'wrap', marginTop: 18, gap: 10 },
  metric: { width: '47%', padding: 12, borderRadius: 12, backgroundColor: colors.panelRaised },
  metricLabel: { color: colors.textMuted, fontSize: 11 },
  metricValue: { color: colors.text, fontSize: 16, fontWeight: '800', marginTop: 3 },
  registration: { color: colors.textMuted, fontSize: 11, marginTop: 14 },
  notice: { color: colors.textMuted, fontSize: 12, lineHeight: 18, margin: 12 },
  actions: { flexDirection: 'row', gap: 12 },
  button: { flex: 1, paddingVertical: 15, borderRadius: 14, alignItems: 'center' },
  discardButton: { backgroundColor: colors.discard },
  acceptButton: { backgroundColor: colors.keep },
  buttonText: { color: colors.white, fontWeight: '900' },
  acceptText: { color: colors.ink },
  missing: { flex: 1, alignItems: 'center', justifyContent: 'center', padding: 30, gap: 10 },
  secondaryButton: {
    marginTop: 12, paddingHorizontal: 18, paddingVertical: 12,
    borderColor: colors.border, borderWidth: 1, borderRadius: 12,
  },
  secondaryText: { color: colors.text, fontWeight: '700' },
});
