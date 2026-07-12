import type { StyleProp, ViewStyle } from 'react-native';

export type FishMode = 'auto' | 'manual' | 'off';
export type SubjectState = 'none' | 'candidate' | 'locked';
export type Confidence = 'low' | 'medium' | 'high';
export type MeasureMethod = 'mesh' | 'existingPlane' | 'estimatedPlane' | 'depth';
export type GirthMethod = 'depthBulge' | 'aspectFallback';

export type ViewPoint = { x: number; y: number };
export type NormalizedPoint = [number, number];
export type WorldPoint = { x: number; y: number; z: number };

export type RuntimeModelDescriptor = {
  path: string;
  version: string;
  inputName: string;
  outputName: string;
  inputWidth: number;
  inputHeight: number;
  normalization?: 'zeroToOne' | 'minusOneToOne' | 'imagenet';
  outputEncoding: 'probabilityMask' | 'classIndexMask' | 'classProbabilities';
  foregroundClassIndex?: number;
  threshold?: number;
  resizePolicy?: 'stretch' | 'aspectFit' | 'aspectFill';
};

export type SmoothingConfig = {
  medianWindow?: number;
  emaAlpha?: number;
};

export type SegmentationConfig = {
  hz?: number;
  depthSource?: 'raw' | 'smoothed';
  /** Vision input orientation. Defaults to `right` for the rear portrait camera. */
  visionOrientation?: 'right' | 'left' | 'up' | 'down';
  minDepthConfidence?: 0 | 1 | 2;
  personExclusion?: boolean;
  personMaskDilationPx?: number;
  subjectClosingPx?: number;
  minComponentFraction?: number;
  minAreaFraction?: number;
  maxAreaFraction?: number;
  minAspectRatio?: number;
  maxAspectRatio?: number;
  priorityRegion?: { x: number; y: number; w: number; h: number };
  runtimeModel?: RuntimeModelDescriptor | null;
};

export type ClassifierConfig = {
  enabled?: boolean;
  hz?: number;
  acceptLabels?: string[];
  minConfidence?: number;
  vetoLabels?: string[];
  runtimeModel?: RuntimeModelDescriptor | null;
  requiredForAutoCapture?: boolean;
};

export type TrackingConfig = {
  iouWeight?: number;
  centroidWeight?: number;
  scoreWeight?: number;
  minCandidateFrames?: number;
  minLockFrames?: number;
  lostGraceMs?: number;
  maxCentroidJumpFraction?: number;
  maxLengthJumpFraction?: number;
  tapHintTtlMs?: number;
  relockCooldownMs?: number;
};

export type CenterlineConfig = {
  algorithm?: 'pca' | 'skeleton';
  bins?: number;
  depthSampleRadiusPx?: number;
  depthTransverseSamples?: number;
  depthTransverseInsetFraction?: number;
  depthForegroundQuantile?: number;
  maxDepthStepM?: number;
  maxDepthStepFraction?: number;
  depthEnvelopeMarginM?: number;
  depthFitDegree?: number;
  outlierRejectSigma?: number;
  maxGapBinFraction?: number;
  minValidBinFraction?: number;
};

export type GirthConfig = {
  aspect?: number;
  useDepthBulge?: boolean;
  calibration?: number;
};

export type StabilityConfig = {
  windowMs?: number;
  maxDeltaCm?: number;
  maxDeltaFraction?: number;
  trimOutlierFrames?: number;
  minDistanceM?: number;
  maxDistanceM?: number;
  minDepthCoverage?: number;
};

export type OverlayConfig = {
  contourMaxPoints?: number;
  emitCenterline?: boolean;
};

export type ClassifierLabel = { label: string; confidence: number };

export type SubjectEvent = {
  frameId: number;
  state: SubjectState;
  contour: number[];
  bbox: { x: number; y: number; width: number; height: number } | null;
  selectedBy: 'tapHint' | 'priorityRegion' | 'temporal' | 'area' | 'none';
  instanceCount: number;
  areaFraction: number;
  aspectRatio: number;
  classifierTop: ClassifierLabel[];
  fishScore: number;
  fishGatePassed: boolean;
  autoCaptureEligible: boolean;
  timestampMs: number;
  frameTimestampS: number;
};

export type FishMeasurementEvent = {
  frameId: number;
  valid: boolean;
  curvedM: number;
  chordM: number;
  rawCurvedM: number;
  girthM: number | null;
  girthMethod: GirthMethod | null;
  nose: ViewPoint;
  tail: ViewPoint;
  centerline?: number[];
  distanceM: number;
  depthCoverage: number;
  confidence: number;
  stable: boolean;
  stableForMs: number;
  stabilitySpreadM?: number;
  stabilityAllowedDeltaM?: number;
  stabilityWindowCovered?: boolean;
  autoCaptureEligible: boolean;
  timestampMs: number;
  frameTimestampS: number;
};

export type DistanceEvent = {
  meters: number;
  rawMeters: number;
  confidence: Confidence;
  mode: FishMode;
  method: MeasureMethod;
  timestampMs: number;
};

export type TrackingStateEvent = {
  state: 'initializing' | 'normal' | 'limited' | 'notAvailable';
  reason?: 'excessiveMotion' | 'insufficientFeatures' | 'relocalizing';
};

export type MeasureErrorEvent = { code: string; message: string };

export type ProjectedPoint = {
  id: string;
  x: number;
  y: number;
  visible: boolean;
  cameraMeters: number;
};

export type ProjectedPointsEvent = {
  points: ProjectedPoint[];
  timestampMs: number;
};

export type DebugInfoEvent = {
  frameId: number;
  segmentationMs: number;
  classificationMs: number;
  contourMs: number;
  centerlineMs: number;
  depthLiftMs: number;
  totalMs: number;
  droppedFrames: number;
  depthDropoutFraction: number;
  thermalState: 'nominal' | 'fair' | 'serious' | 'critical' | 'unknown';
  timestampMs: number;
};

type NativeEventHandler<T> = (event: { nativeEvent: T }) => void;

export type FishMeasureViewProps = {
  mode: FishMode;
  updateHz?: number;
  smoothing?: SmoothingConfig;
  showNativeMarkers?: boolean;
  enableSceneReconstruction?: boolean;
  enableHighResCapture?: boolean;
  segmentation?: SegmentationConfig;
  classifier?: ClassifierConfig;
  tracking?: TrackingConfig;
  centerline?: CenterlineConfig;
  girth?: GirthConfig;
  stability?: StabilityConfig;
  overlay?: OverlayConfig;
  debugMode?: boolean;
  debugDepthOverlay?: boolean;
  onSubject?: NativeEventHandler<SubjectEvent>;
  onFishMeasurement?: NativeEventHandler<FishMeasurementEvent>;
  onDistance?: NativeEventHandler<DistanceEvent>;
  onTrackingState?: NativeEventHandler<TrackingStateEvent>;
  onProjectedPoints?: NativeEventHandler<ProjectedPointsEvent>;
  onError?: NativeEventHandler<MeasureErrorEvent>;
  onDebugInfo?: NativeEventHandler<DebugInfoEvent>;
  style?: StyleProp<ViewStyle>;
};

export type CaptureOptions = {
  outputDir: string;
  includePly?: boolean;
  includeMaskPng?: boolean;
  jpegQuality?: number;
  registrationMinScore?: number;
};

export type PhotoRegistration = {
  status: 'registered' | 'fallbackAlignedFrame' | 'unavailable';
  score: number | null;
  annotatedPhotoPath: string | null;
  annotatedPhotoWidth: number | null;
  annotatedPhotoHeight: number | null;
};

export type CameraIntrinsics = {
  fx: number;
  fy: number;
  cx: number;
  cy: number;
  width: number;
  height: number;
};

export type AutoCapturePayload = {
  frameId: number;
  captureId: string;
  photoPath: string;
  photoWidth: number;
  photoHeight: number;
  photoSource: 'highRes' | 'videoFrame' | 'snapshot';
  photoRegistration: PhotoRegistration;
  curvedM: number;
  chordM: number;
  girthM: number | null;
  girthMethod: GirthMethod | null;
  confidence: number;
  distanceM: number;
  depthCoverage: number;
  windowMedianCurvedM: number;
  windowStdDevM: number;
  windowFrames: number;
  /** Normalized coordinates in photoRegistration.annotatedPhotoPath. */
  contour: number[];
  noseNorm: NormalizedPoint;
  tailNorm: NormalizedPoint;
  centerline3D: number[];
  cameraTransform: number[];
  plyPath: string | null;
  maskPngPath: string | null;
  intrinsics: CameraIntrinsics;
  timestampMs: number;
  frameTimestampS: number;
};

export type ManualPathMeasurement = {
  curvedM: number;
  chordM: number;
  sampleCount: number;
  validFraction: number;
  worldPoints: number[];
};

export type ManualCapturePayload = Omit<
  AutoCapturePayload,
  | 'girthM'
  | 'girthMethod'
  | 'windowMedianCurvedM'
  | 'windowStdDevM'
  | 'windowFrames'
  | 'contour'
  | 'noseNorm'
  | 'tailNorm'
> & {
  pathPointsNorm: number[];
  pathKind: 'twoPointChord' | 'drawnSpine';
};

export type MeasureResult = {
  meters: number;
  confidence: Confidence;
  anchorId: string;
  method: MeasureMethod;
  worldPoint: WorldPoint;
} | null;

export type FishMeasureViewRef = {
  setTapHint(x: number, y: number): Promise<void>;
  clearSubject(): Promise<void>;
  captureAutoCatch(options: CaptureOptions): Promise<AutoCapturePayload | null>;
  measureAtPoint(x: number, y: number): Promise<MeasureResult>;
  measureManualPath(points: ViewPoint[], samples?: number): Promise<ManualPathMeasurement | null>;
  captureManualCatch(
    points: ViewPoint[],
    options: CaptureOptions
  ): Promise<ManualCapturePayload | null>;
  clearAnchors(): Promise<void>;
  removeAnchor(anchorId: string): Promise<void>;
  snapshotCamera(): Promise<string>;
};
