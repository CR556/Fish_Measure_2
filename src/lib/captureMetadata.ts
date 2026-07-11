import type { AutoCapturePayload, FishMode, ManualCapturePayload } from '../../modules/fish-measure';

type CapturePayload = AutoCapturePayload | ManualCapturePayload;

export function buildCaptureMetadata(
  payload: CapturePayload,
  context: { mode: FishMode; units: 'imperial' | 'metric'; species?: string | null }
) {
  const inches = payload.curvedM * 39.3700787402;
  const centimeters = payload.curvedM * 100;
  const description = [
    context.species ?? 'Unknown fish',
    `${centimeters.toFixed(1)} cm`,
    `${inches.toFixed(1)} in`,
    `curve-corrected; chord ${(payload.chordM * 100).toFixed(1)} cm`,
  ].join(' · ');

  return {
    userComment: JSON.stringify({
      app: 'Fish Measure 2',
      schemaVersion: 1,
      capturedAt: new Date(payload.timestampMs).toISOString(),
      mode: context.mode,
      unitsAtCapture: context.units,
      measurement: {
        curvedM: payload.curvedM,
        chordM: payload.chordM,
        confidence: payload.confidence,
        distanceM: payload.distanceM,
        depthCoverage: payload.depthCoverage,
      },
      capture: {
        frameId: payload.frameId,
        captureId: payload.captureId,
        photoSource: payload.photoSource,
        registration: payload.photoRegistration,
      },
    }),
    description,
  };
}
