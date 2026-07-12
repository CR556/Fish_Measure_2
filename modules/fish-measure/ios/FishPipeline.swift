import ARKit
import Foundation
import QuartzCore

struct FishPipelineSnapshot: @unchecked Sendable {
  let frameId: Int
  let packet: FramePacket
  let subject: SegmentedSubject
  let contour: [CGPoint]
  let measurement: LiftedMeasurement
  let curvedM: Double
  let girth: GirthResult?
  let stability: StabilitySnapshot
  let confidence: Double
  let segmentationParams: SegmentationParams
}

final class FishPipeline {
  private weak var host: FishARView?
  private let queue = DispatchQueue(label: "fish.vision", qos: .userInitiated)
  private let stateLock = NSLock()
  private let configLock = NSLock()
  private var processing = false
  private var droppedFrames = 0
  private var lastAcceptedTimestamp: TimeInterval = -Double.greatestFiniteMagnitude
  private var nextFrameId = 1
  private var latestSnapshot: FishPipelineSnapshot?
  private var tapHintViewPoint: CGPoint?
  private var tapHintSetAtMs: Double = 0
  private var lastTrackedSubject: SegmentedSubject?

  private var segmentation = SegmentationParams()
  private var classifier = ClassifierParams()
  private var tracking = TrackingParams()
  private var centerline = CenterlineParams()
  private var girth = GirthParams()
  private var stability = StabilityParams()
  private var overlay = OverlayParams()
  private let segmenter = SubjectSegmenter()
  private let classifierEngine = FishClassifier()
  private let tracker = SubjectTracker()
  private let contourTracer = ContourTracer()
  private let centerlineBuilder = CenterlineBuilder()
  private let depthLifter = DepthLifter()
  private let girthEstimator = GirthEstimator()
  private let stabilityGate = StabilityGate()
  private let smoother = DistanceSmoother()
  var debugMode = false

  init(host: FishARView) { self.host = host }

  func setSmoothing(_ value: SmoothingParams) {
    queue.async { [weak self] in
      self?.smoother.medianWindow = min(max(value.medianWindow, 1), 31)
      self?.smoother.emaAlpha = min(max(value.emaAlpha, 0.01), 1)
      self?.smoother.reset()
    }
  }

  func setSegmentation(_ value: SegmentationParams) { withConfig { segmentation = value } }
  func setClassifier(_ value: ClassifierParams) { withConfig { classifier = value } }
  func setTracking(_ value: TrackingParams) { withConfig { tracking = value } }
  func setCenterline(_ value: CenterlineParams) { withConfig { centerline = value } }
  func setGirth(_ value: GirthParams) { withConfig { girth = value } }
  func setStability(_ value: StabilityParams) { withConfig { stability = value } }
  func setOverlay(_ value: OverlayParams) { withConfig { overlay = value } }

  private func withConfig(_ update: () -> Void) {
    configLock.lock(); update(); configLock.unlock()
  }

  private func configSnapshot() -> (
    SegmentationParams, ClassifierParams, TrackingParams,
    CenterlineParams, GirthParams, StabilityParams, OverlayParams
  ) {
    configLock.lock(); defer { configLock.unlock() }
    return (segmentation, classifier, tracking, centerline, girth, stability, overlay)
  }

  func setTapHint(_ point: CGPoint, viewSize: CGSize) {
    stateLock.lock()
    tapHintViewPoint = point
    tapHintSetAtMs = Date().timeIntervalSince1970 * 1000
    stateLock.unlock()
  }

  func enqueue(frame: ARFrame, viewSize: CGSize, orientation: UIInterfaceOrientation) {
    let config = configSnapshot()
    guard frame.timestamp - lastAcceptedTimestamp >= 1 / max(0.1, config.0.hz) else { return }
    stateLock.lock()
    if processing {
      droppedFrames += 1
      stateLock.unlock()
      return
    }
    processing = true
    stateLock.unlock()
    lastAcceptedTimestamp = frame.timestamp
    guard let packet = FramePacket.copy(
      frame: frame,
      depthSource: config.0.depthSource,
      viewSize: viewSize,
      orientation: orientation) else {
      finishProcessing()
      return
    }
    let frameId = nextFrameId
    nextFrameId += 1
    queue.async { [weak self] in
      self?.process(packet: packet, frameId: frameId, config: config)
      self?.finishProcessing()
    }
  }

  private func finishProcessing() {
    stateLock.lock(); processing = false; stateLock.unlock()
  }

  func clear() {
    queue.async { [weak self] in
      self?.tracker.reset()
      self?.stabilityGate.reset()
      self?.smoother.reset()
      self?.stateLock.lock()
      self?.latestSnapshot = nil
      self?.tapHintViewPoint = nil
      self?.stateLock.unlock()
      self?.lastTrackedSubject = nil
    }
  }

  func captureSnapshot() -> FishPipelineSnapshot? {
    stateLock.lock(); defer { stateLock.unlock() }
    return latestSnapshot
  }

  private func process(
    packet: FramePacket,
    frameId: Int,
    config: (
      SegmentationParams, ClassifierParams, TrackingParams,
      CenterlineParams, GirthParams, StabilityParams, OverlayParams
    )
  ) {
    let started = CACurrentMediaTime()
    stateLock.lock(); latestSnapshot = nil; stateLock.unlock()
    let (configuredSegmentation, classifier, tracking, centerline, girth, stability, overlay) = config
    var segmentation = configuredSegmentation
    segmentation.priorityRegion = sensorPriorityRegion(
      configuredSegmentation.priorityRegion,
      packet: packet)
    let tapHint = currentTapHint(packet: packet, ttlMs: tracking.tapHintTtlMs)
    let segmentationStart = CACurrentMediaTime()
    let detectedSubject: SegmentedSubject?
    do {
      detectedSubject = try segmenter.segment(
        image: packet.capturedImage,
        params: segmentation,
        tapHint: tapHint)
    } catch {
      host?.dispatchError(code: "segmentation_failed", message: error.localizedDescription)
      emitEmpty(frameId: frameId, packet: packet, tracking: tracking)
      return
    }
    let segmentationMs = elapsedMs(segmentationStart)
    let trackingResult = tracker.update(
      subject: detectedSubject, timestamp: packet.timestamp, params: tracking)
    let subject: SegmentedSubject?
    if trackingResult.acceptsDetectedSubject {
      subject = detectedSubject
      lastTrackedSubject = detectedSubject
    } else if trackingResult.state == "locked" {
      subject = lastTrackedSubject
    } else {
      subject = nil
      lastTrackedSubject = nil
    }
    guard let subject else {
      emitSubject(
        frameId: frameId, packet: packet, subject: nil, contour: [], tracking: trackingResult,
        classifier: ClassifierResult(labels: [], fishScore: 0, gatePassed: false),
        autoCaptureEligible: false)
      return
    }

    let classifierStart = CACurrentMediaTime()
    let classification = (try? classifierEngine.classify(
      image: packet.capturedImage,
      timestamp: packet.timestamp,
      params: classifier)) ?? ClassifierResult(labels: [], fishScore: 0, gatePassed: false)
    let classificationMs = elapsedMs(classifierStart)
    let contourStart = CACurrentMediaTime()
    let contour = contourTracer.trace(mask: subject.mask, maxPoints: overlay.contourMaxPoints)
    let contourMs = elapsedMs(contourStart)
    let autoEligible = trackingResult.state == "locked"
      && (!classifier.requiredForAutoCapture || classification.gatePassed)
    emitSubject(
      frameId: frameId, packet: packet, subject: subject, contour: contour,
      tracking: trackingResult, classifier: classification,
      autoCaptureEligible: autoEligible)

    let centerlineStart = CACurrentMediaTime()
    guard let line = centerlineBuilder.build(mask: subject.mask, params: centerline) else { return }
    let centerlineMs = elapsedMs(centerlineStart)
    let depthStart = CACurrentMediaTime()
    guard let lifted = depthLifter.lift(
      centerline: line, packet: packet, segmentation: segmentation, params: centerline) else { return }
    let depthMs = elapsedMs(depthStart)
    let smoothedCurved = smoother.smooth(lifted.curvedM)
    let girthResult = girthEstimator.estimate(
      centerline: line, measurement: lifted, packet: packet, params: girth)
    let confidence = min(1, max(0,
      lifted.depthCoverage * (classification.labels.isEmpty ? 0.65 : max(0.2, classification.fishScore))))
    let sample = StabilitySample(
      frameId: frameId,
      timestamp: packet.timestamp,
      curvedM: smoothedCurved,
      chordM: lifted.chordM,
      girth: girthResult,
      confidence: confidence,
      distanceM: lifted.distanceM,
      depthCoverage: lifted.depthCoverage)
    let stable = stabilityGate.update(sample, params: stability)
    let finalEligible = autoEligible && stable.stable
    emitMeasurement(
      frameId: frameId, packet: packet, measurement: lifted,
      smoothedCurved: smoothedCurved, girth: girthResult, confidence: confidence,
      stable: stable, emitCenterline: overlay.emitCenterline,
      autoCaptureEligible: finalEligible)
    let snapshot = FishPipelineSnapshot(
      frameId: frameId, packet: packet, subject: subject, contour: contour,
      measurement: lifted, curvedM: stable.medianCurvedM, girth: girthResult,
      stability: stable, confidence: confidence, segmentationParams: segmentation)
    stateLock.lock()
    latestSnapshot = finalEligible ? snapshot : nil
    let dropped = droppedFrames
    stateLock.unlock()

    if debugMode {
      host?.dispatchDebugInfo([
        "frameId": frameId,
        "segmentationMs": segmentationMs,
        "classificationMs": classificationMs,
        "contourMs": contourMs,
        "centerlineMs": centerlineMs,
        "depthLiftMs": depthMs,
        "totalMs": elapsedMs(started),
        "droppedFrames": dropped,
        "depthDropoutFraction": 1 - lifted.depthCoverage,
        "thermalState": thermalState(),
        "timestampMs": packet.epochTimestampMs,
      ])
    }
  }

  private func currentTapHint(packet: FramePacket, ttlMs: Double) -> CGPoint? {
    stateLock.lock(); defer { stateLock.unlock() }
    guard let tapHintViewPoint,
          packet.epochTimestampMs - tapHintSetAtMs <= ttlMs else { return nil }
    return CoordinateMapper.viewToImageNormalized(
      tapHintViewPoint,
      viewSize: packet.viewSize,
      displayTransform: packet.displayTransform)
  }

  /// The JS priority region is normalized in the RN view. Subject masks are
  /// canonicalized to camera-sensor coordinates, so account for ARKit's
  /// aspect-fill display transform before comparing mask centroids.
  private func sensorPriorityRegion(_ region: RegionParams, packet: FramePacket) -> RegionParams {
    let corners = [
      CGPoint(x: region.x, y: region.y),
      CGPoint(x: region.x + region.w, y: region.y),
      CGPoint(x: region.x + region.w, y: region.y + region.h),
      CGPoint(x: region.x, y: region.y + region.h),
    ].map {
      CoordinateMapper.viewToImageNormalized(
        CGPoint(x: $0.x * packet.viewSize.width, y: $0.y * packet.viewSize.height),
        viewSize: packet.viewSize,
        displayTransform: packet.displayTransform)
    }
    var converted = RegionParams()
    converted.x = Double(corners.map(\.x).min() ?? 0)
    converted.y = Double(corners.map(\.y).min() ?? 0)
    converted.w = Double((corners.map(\.x).max() ?? 1) - CGFloat(converted.x))
    converted.h = Double((corners.map(\.y).max() ?? 1) - CGFloat(converted.y))
    return converted
  }

  private func emitEmpty(frameId: Int, packet: FramePacket, tracking: TrackingParams) {
    let result = tracker.update(subject: nil, timestamp: packet.timestamp, params: tracking)
    emitSubject(
      frameId: frameId, packet: packet, subject: nil, contour: [], tracking: result,
      classifier: ClassifierResult(labels: [], fishScore: 0, gatePassed: false),
      autoCaptureEligible: false)
  }

  private func emitSubject(
    frameId: Int,
    packet: FramePacket,
    subject: SegmentedSubject?,
    contour: [CGPoint],
    tracking: TrackingResult,
    classifier: ClassifierResult,
    autoCaptureEligible: Bool
  ) {
    let viewContour = contour.map { CoordinateMapper.imageNormalizedToView($0, packet: packet) }
    let flat = viewContour.flatMap { [Double($0.x), Double($0.y)] }
    var payload: [String: Any] = [
      "frameId": frameId,
      "state": tracking.state,
      "contour": flat,
      "selectedBy": tracking.selectedBy,
      "instanceCount": subject?.instanceCount ?? 0,
      "areaFraction": subject?.areaFraction ?? 0,
      "aspectRatio": subject?.aspectRatio ?? 0,
      "classifierTop": classifier.labels.map {
        ["label": $0.label, "confidence": $0.confidence]
      },
      "fishScore": classifier.fishScore,
      "fishGatePassed": classifier.gatePassed,
      "autoCaptureEligible": autoCaptureEligible,
      "timestampMs": packet.epochTimestampMs,
      "frameTimestampS": packet.timestamp,
    ]
    if let bounds = subject?.bounds {
      let corners = [
        CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
        CGPoint(x: bounds.maxX, y: bounds.maxY), CGPoint(x: bounds.minX, y: bounds.maxY),
      ].map { CoordinateMapper.imageNormalizedToView($0, packet: packet) }
      let minX = corners.map(\.x).min() ?? 0, maxX = corners.map(\.x).max() ?? 0
      let minY = corners.map(\.y).min() ?? 0, maxY = corners.map(\.y).max() ?? 0
      payload["bbox"] = [
        "x": Double(minX), "y": Double(minY),
        "width": Double(maxX - minX), "height": Double(maxY - minY),
      ]
    } else {
      payload["bbox"] = NSNull()
    }
    host?.dispatchSubject(payload)
  }

  private func emitMeasurement(
    frameId: Int,
    packet: FramePacket,
    measurement: LiftedMeasurement,
    smoothedCurved: Double,
    girth: GirthResult?,
    confidence: Double,
    stable: StabilitySnapshot,
    emitCenterline: Bool,
    autoCaptureEligible: Bool
  ) {
    let viewPoints = measurement.centerlineImage.map {
      CoordinateMapper.imageNormalizedToView($0, packet: packet)
    }
    guard let nose = viewPoints.first, let tail = viewPoints.last else { return }
    host?.dispatchFishMeasurement([
      "frameId": frameId,
      "valid": true,
      "curvedM": smoothedCurved,
      "chordM": measurement.chordM,
      "rawCurvedM": measurement.curvedM,
      "girthM": girth.map { $0.meters as Any } ?? NSNull(),
      "girthMethod": girth.map { $0.method as Any } ?? NSNull(),
      "nose": ["x": Double(nose.x), "y": Double(nose.y)],
      "tail": ["x": Double(tail.x), "y": Double(tail.y)],
      "centerline": emitCenterline
        ? viewPoints.flatMap { [Double($0.x), Double($0.y)] }
        : [],
      "distanceM": measurement.distanceM,
      "depthCoverage": measurement.depthCoverage,
      "confidence": confidence,
      "stable": stable.stable,
      "stableForMs": stable.stableForMs,
      "stabilitySpreadM": stable.spreadM,
      "stabilityAllowedDeltaM": stable.allowedDeltaM,
      "stabilityWindowCovered": stable.windowCovered,
      "autoCaptureEligible": autoCaptureEligible,
      "timestampMs": packet.epochTimestampMs,
      "frameTimestampS": packet.timestamp,
    ])
  }

  private func elapsedMs(_ start: CFTimeInterval) -> Double {
    (CACurrentMediaTime() - start) * 1000
  }

  private func thermalState() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }
}
