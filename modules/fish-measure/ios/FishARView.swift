import ARKit
import AVFoundation
import ExpoModulesCore
import RealityKit

/// Single native view that owns both camera pipelines and switches between
/// them with an explicit teardown-then-start state machine (ARSession and
/// AVCaptureSession must never run simultaneously — that's the classic
/// frozen-camera bug).
class LidarARView: ExpoView {
  let onDistance = EventDispatcher()
  let onTrackingState = EventDispatcher()
  let onError = EventDispatcher()
  let onProjectedPoints = EventDispatcher()
  let onHeatmapRange = EventDispatcher()

  let arView = ARView(frame: .zero)
  private lazy var rear = RearSessionController(arView: arView, host: self)
  private lazy var front = FrontDepthController(host: self)
  private lazy var heatmap = DepthHeatmapRenderer()

  private var mode = "rearCrosshair"
  private var isActive = false

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    clipsToBounds = true
    backgroundColor = .black
    arView.frame = bounds
    arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(arView)

    NotificationCenter.default.addObserver(
      self, selector: #selector(handleDidEnterBackground),
      name: UIApplication.didEnterBackgroundNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(handleWillEnterForeground),
      name: UIApplication.willEnterForegroundNotification, object: nil)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil {
      isActive = true
      applyMode()
    } else {
      isActive = false
      teardownAll()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    front.updatePreviewFrame(bounds)
    heatmap.layer.frame = bounds
  }

  @objc private func handleDidEnterBackground() {
    teardownAll()
  }

  @objc private func handleWillEnterForeground() {
    if isActive {
      applyMode()
    }
  }

  // MARK: - Props

  func setMode(_ newMode: String) {
    guard ["rearTap", "rearCrosshair", "heatmap", "front"].contains(newMode) else {
      dispatchError(code: "invalid_mode", message: "Unknown mode '\(newMode)'.")
      return
    }
    mode = newMode
    rear.mode = newMode
    if isActive {
      applyMode()
    }
  }

  func setUpdateHz(_ hz: Double) {
    let clamped = min(max(hz, 1), 60)
    rear.updateHz = clamped
    front.updateHz = clamped
  }

  func setSmoothing(medianWindow: Int, emaAlpha: Double) {
    rear.smoother.medianWindow = medianWindow
    rear.smoother.emaAlpha = emaAlpha
    front.smoother.medianWindow = medianWindow
    front.smoother.emaAlpha = emaAlpha
  }

  func setShowMarkers(_ show: Bool) {
    rear.showMarkers = show
  }

  func setHeatmapRange(min: Double, max: Double) {
    heatmap.minMeters = Float(min)
    heatmap.maxMeters = Float(Swift.max(max, min + 0.01))
  }

  func setHeatmapOpacity(_ opacity: Double) {
    heatmap.setOpacity(opacity)
  }

  func setHeatmapColors(_ colors: [String]) {
    heatmap.setColors(colors)
  }

  func setHeatmapRotation(_ degrees: Int) {
    heatmap.rotationDegrees = degrees
  }

  func setHeatmapAutoRange(_ enabled: Bool) {
    heatmap.autoRange = enabled
  }

  // MARK: - Mode state machine

  private func applyMode() {
    if mode == "front" {
      if rear.isRunning {
        rear.pause()
      }
      setHeatmapActive(false)
      arView.isHidden = true
      front.start(in: layer, frame: bounds)
    } else {
      if front.isRunning {
        front.stop()
      }
      arView.isHidden = false
      if !rear.isRunning {
        rear.start()
      }
      setHeatmapActive(mode == "heatmap")
    }
  }

  private func setHeatmapActive(_ active: Bool) {
    if active {
      if heatmap.layer.superlayer == nil {
        heatmap.layer.frame = bounds
        layer.addSublayer(heatmap.layer)
      }
      heatmap.layer.isHidden = false
      heatmap.onAutoMaxChanged = { [weak self] maxMeters in
        guard let self else { return }
        self.onHeatmapRange([
          "min": Double(self.heatmap.minMeters),
          "max": Double(maxMeters),
        ])
      }
      rear.onDepthFrame = { [weak self] depthMap in
        self?.heatmap.update(depthMap: depthMap)
      }
    } else {
      rear.onDepthFrame = nil
      heatmap.layer.isHidden = true
      heatmap.layer.contents = nil
    }
  }

  private func teardownAll() {
    if rear.isRunning {
      rear.pause()
    }
    if front.isRunning {
      front.stop()
    }
  }

  // MARK: - View functions (called via ref from JS)

  func measureAtPoint(x: Double, y: Double) -> [String: Any]? {
    guard mode == "rearTap" || mode == "rearCrosshair" else { return nil }
    return rear.measure(at: CGPoint(x: x, y: y))
  }

  func snapshotCamera(promise: Promise) {
    arView.snapshot(saveToHDR: false) { image in
      guard let image, let data = image.jpegData(compressionQuality: 0.9) else {
        promise.reject("snapshot_failed", "Could not capture the camera view.")
        return
      }
      let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("jpg")
      do {
        try data.write(to: url)
        promise.resolve(url.path)
      } catch {
        promise.reject("snapshot_failed", error.localizedDescription)
      }
    }
  }

  func clearAnchors() {
    rear.clearAnchors()
  }

  func removeAnchor(id: String) {
    rear.removeAnchor(id: id)
  }

  // MARK: - Event dispatch helpers

  func dispatchDistance(meters: Double, raw: Double, confidence: String, mode: String, method: String) {
    onDistance([
      "meters": meters,
      "rawMeters": raw,
      "confidence": confidence,
      "mode": mode,
      "method": method,
      "timestamp": Date().timeIntervalSince1970 * 1000,
    ])
  }

  func dispatchProjectedPoints(points: [[String: Any]]) {
    onProjectedPoints([
      "points": points,
      "timestamp": Date().timeIntervalSince1970 * 1000,
    ])
  }

  func dispatchTrackingState(state: String, reason: String?) {
    var payload: [String: Any] = ["state": state]
    if let reason {
      payload["reason"] = reason
    }
    onTrackingState(payload)
  }

  func dispatchError(code: String, message: String) {
    onError(["code": code, "message": message])
  }
}
