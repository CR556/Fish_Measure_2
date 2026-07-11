import ARKit
import ExpoModulesCore
import RealityKit

final class FishARView: ExpoView {
  let onSubject = EventDispatcher()
  let onFishMeasurement = EventDispatcher()
  let onDistance = EventDispatcher()
  let onTrackingState = EventDispatcher()
  let onProjectedPoints = EventDispatcher()
  let onError = EventDispatcher()
  let onDebugInfo = EventDispatcher()

  let arView = ARView(frame: .zero)
  private lazy var sessionController = SessionController(arView: arView, host: self)
  private lazy var pipeline = FishPipeline(host: self)
  private lazy var manualPathMeasurer = ManualPathMeasurer()
  private lazy var captureService = CaptureService()
  private lazy var heatmap = DepthHeatmapRenderer()

  private var mode = "auto"
  private var isActive = false
  private var centerlineParams = CenterlineParams()
  private var debugDepthOverlay = false

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true
    backgroundColor = .black
    arView.frame = bounds
    arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(arView)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification,
      object: nil)
  }

  deinit { NotificationCenter.default.removeObserver(self) }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    isActive = window != nil
    applyMode()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    heatmap.layer.frame = bounds
  }

  private var interfaceOrientation: UIInterfaceOrientation {
    window?.windowScene?.interfaceOrientation ?? .portrait
  }

  @objc private func handleDidEnterBackground() {
    pipeline.clear()
    sessionController.pause()
  }

  @objc private func handleWillEnterForeground() {
    if isActive { applyMode() }
  }

  func setMode(_ value: String) {
    guard ["auto", "manual", "off"].contains(value) else {
      dispatchError(code: "invalid_mode", message: "Unknown fish mode '\(value)'.")
      return
    }
    mode = value
    sessionController.mode = value
    if value != "auto" { pipeline.clear() }
    applyMode()
  }

  func setUpdateHz(_ value: Double) { sessionController.updateHz = min(max(value, 1), 60) }

  func setSmoothing(_ value: SmoothingParams) {
    sessionController.smoother.medianWindow = min(max(value.medianWindow, 1), 31)
    sessionController.smoother.emaAlpha = min(max(value.emaAlpha, 0.01), 1)
    pipeline.setSmoothing(value)
  }

  func setShowMarkers(_ value: Bool) { sessionController.showMarkers = value }

  func setSceneReconstruction(_ value: Bool) {
    guard sessionController.enableSceneReconstruction != value else { return }
    sessionController.enableSceneReconstruction = value
    sessionController.restartConfiguration()
  }

  func setHighResolutionCapture(_ value: Bool) {
    guard sessionController.enableHighResolutionCapture != value else { return }
    sessionController.enableHighResolutionCapture = value
    sessionController.restartConfiguration()
  }

  func setSegmentation(_ value: SegmentationParams) { pipeline.setSegmentation(value) }
  func setClassifier(_ value: ClassifierParams) { pipeline.setClassifier(value) }
  func setTracking(_ value: TrackingParams) { pipeline.setTracking(value) }

  func setCenterline(_ value: CenterlineParams) {
    centerlineParams = value
    pipeline.setCenterline(value)
  }

  func setGirth(_ value: GirthParams) { pipeline.setGirth(value) }
  func setStability(_ value: StabilityParams) { pipeline.setStability(value) }
  func setOverlay(_ value: OverlayParams) { pipeline.setOverlay(value) }
  func setDebugMode(_ value: Bool) { pipeline.debugMode = value }

  func setDebugDepthOverlay(_ value: Bool) {
    debugDepthOverlay = value
    sessionController.debugDepthOverlay = value
    if value {
      if heatmap.layer.superlayer == nil {
        heatmap.layer.frame = bounds
        layer.addSublayer(heatmap.layer)
      }
      heatmap.layer.isHidden = false
    } else {
      heatmap.layer.isHidden = true
      heatmap.layer.contents = nil
    }
  }

  private func applyMode() {
    guard isActive else {
      sessionController.pause()
      return
    }
    if mode == "off" {
      sessionController.pause()
    } else if !sessionController.isRunning {
      sessionController.start()
    }
  }

  func consume(frame: ARFrame) {
    pipeline.enqueue(
      frame: frame,
      viewSize: bounds.size,
      orientation: interfaceOrientation)
  }

  func updateDebugDepth(_ depth: CVPixelBuffer) {
    guard debugDepthOverlay else { return }
    heatmap.update(depthMap: depth)
  }

  func setTapHint(x: Double, y: Double) {
    pipeline.setTapHint(CGPoint(x: x, y: y), viewSize: bounds.size)
  }

  func clearSubject() { pipeline.clear() }

  func captureAutoCatch(options: CaptureParams, promise: Promise) {
    guard let snapshot = pipeline.captureSnapshot() else {
      promise.resolve(nil)
      return
    }
    captureService.captureAuto(
      session: sessionController,
      arView: arView,
      snapshot: snapshot,
      options: options,
      orientation: interfaceOrientation,
      promise: promise)
  }

  func measureAtPoint(x: Double, y: Double) -> [String: Any]? {
    sessionController.measure(at: CGPoint(x: x, y: y))
  }

  func measureManualPath(points: [PointParams], samples: Int?) async -> [String: Any]? {
    guard let frame = sessionController.currentFrame, points.count >= 2 else { return nil }
    return await manualPathMeasurer.measure(
      frame: frame,
      points: points.map { CGPoint(x: $0.x, y: $0.y) },
      sampleCount: samples,
      viewSize: bounds.size,
      orientation: interfaceOrientation,
      params: centerlineParams)
  }

  func captureManualCatch(points: [PointParams], options: CaptureParams, promise: Promise) {
    guard let frame = sessionController.currentFrame, points.count >= 2 else {
      promise.resolve(nil)
      return
    }
    let cgPoints = points.map { CGPoint(x: $0.x, y: $0.y) }
    manualPathMeasurer.measure(
      frame: frame,
      points: cgPoints,
      sampleCount: nil,
      viewSize: bounds.size,
      orientation: interfaceOrientation,
      params: centerlineParams) { [weak self] measurement in
        guard let self, let measurement else {
          promise.resolve(nil)
          return
        }
        DispatchQueue.main.async {
          self.captureService.captureManual(
            session: self.sessionController,
            arView: self.arView,
            measurement: measurement,
            pathPoints: cgPoints,
            viewSize: self.bounds.size,
            options: options,
            orientation: self.interfaceOrientation,
            promise: promise)
        }
      }
  }

  func clearAnchors() { sessionController.clearAnchors() }
  func removeAnchor(id: String) { sessionController.removeAnchor(id: id) }

  func snapshotCamera(promise: Promise) {
    arView.snapshot(saveToHDR: false) { image in
      guard let image, let data = image.jpegData(compressionQuality: 0.9) else {
        promise.reject("snapshot_failed", "Could not capture the camera view.")
        return
      }
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
      do {
        try data.write(to: url, options: .atomic)
        promise.resolve(url.path)
      } catch {
        promise.reject("snapshot_failed", error.localizedDescription)
      }
    }
  }

  func dispatchSubject(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.onSubject(payload) }
  }

  func dispatchFishMeasurement(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.onFishMeasurement(payload) }
  }

  func dispatchDebugInfo(_ payload: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.onDebugInfo(payload) }
  }

  func dispatchDistance(
    meters: Double, raw: Double, confidence: String, mode: String, method: String
  ) {
    onDistance([
      "meters": meters,
      "rawMeters": raw,
      "confidence": confidence,
      "mode": mode,
      "method": method,
      "timestampMs": Date().timeIntervalSince1970 * 1000,
    ])
  }

  func dispatchProjectedPoints(points: [[String: Any]]) {
    onProjectedPoints([
      "points": points,
      "timestampMs": Date().timeIntervalSince1970 * 1000,
    ])
  }

  func dispatchTrackingState(state: String, reason: String?) {
    var payload: [String: Any] = ["state": state]
    if let reason { payload["reason"] = reason }
    DispatchQueue.main.async { [weak self] in self?.onTrackingState(payload) }
  }

  func dispatchError(code: String, message: String) {
    DispatchQueue.main.async { [weak self] in self?.onError(["code": code, "message": message]) }
  }
}
