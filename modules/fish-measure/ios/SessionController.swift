import ARKit
import Foundation
import RealityKit

extension simd_float4x4 {
  var translation: SIMD3<Float> {
    SIMD3(columns.3.x, columns.3.y, columns.3.z)
  }
}

struct RearHit {
  let worldPoint: SIMD3<Float>
  let method: String      // "mesh" | "existingPlane" | "estimatedPlane"
  let confidence: String  // "low" | "medium" | "high"
}

/// Owns the ARKit world-tracking session used by both rear modes.
/// - rearCrosshair: raycasts from screen center every frame (throttled to
///   `updateHz`) and emits smoothed distance events.
/// - rearTap: `measure(at:)` places a world anchor + marker; the frame loop
///   keeps emitting the live camera→anchor distance for the latest anchor.
final class RearSessionController: NSObject, ARSessionDelegate {
  private let arView: ARView
  private weak var host: LidarARView?
  let smoother = DistanceSmoother()

  var updateHz: Double = 15
  var showMarkers = true
  /// Set while heatmap mode is active; receives sceneDepth at the event rate.
  var onDepthFrame: ((CVPixelBuffer) -> Void)?
  var mode: String = "rearCrosshair" {
    didSet {
      if mode != oldValue {
        smoother.reset()
      }
    }
  }

  private var anchors: [String: AnchorEntity] = [:]
  private var anchorOrder: [String] = []
  private var lastEventTimestamp: TimeInterval = 0
  private var lastProjectedCount = -1
  private var trackingNormal = false
  private(set) var isRunning = false

  init(arView: ARView, host: LidarARView) {
    self.arView = arView
    self.host = host
    super.init()
  }

  func start() {
    guard ARWorldTrackingConfiguration.isSupported else {
      host?.dispatchError(code: "ar_unsupported", message: "ARKit world tracking is not supported on this device.")
      host?.dispatchTrackingState(state: "notAvailable", reason: nil)
      return
    }

    let config = ARWorldTrackingConfiguration()
    if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
      config.sceneReconstruction = .meshWithClassification
    } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
      config.sceneReconstruction = .mesh
    }
    if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
      config.frameSemantics.insert(.sceneDepth)
    }
    config.planeDetection = [.horizontal, .vertical]

    arView.environment.sceneUnderstanding.options.insert(.collision)
    arView.session.delegate = self

    anchors.removeAll()
    anchorOrder.removeAll()
    smoother.reset()
    trackingNormal = false
    lastEventTimestamp = 0

    arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    isRunning = true
    host?.dispatchTrackingState(state: "initializing", reason: nil)
  }

  func pause() {
    guard isRunning else { return }
    arView.session.pause()
    isRunning = false
    trackingNormal = false
  }

  // MARK: - Measurement

  private var cameraPosition: SIMD3<Float> {
    arView.cameraTransform.translation
  }

  private func distance(to worldPoint: SIMD3<Float>) -> Double {
    Double(simd_length(worldPoint - cameraPosition))
  }

  /// Three-tier raycast fallback: LiDAR scene mesh → detected plane geometry
  /// → estimated plane. Tier and tracking quality drive the confidence label.
  func hitTest(at point: CGPoint) -> RearHit? {
    let limited = !trackingNormal

    if let ray = arView.ray(through: point) {
      let hits = arView.scene.raycast(
        origin: ray.origin,
        direction: ray.direction,
        length: 10,
        query: .nearest,
        mask: .all,
        relativeTo: nil
      )
      if let hit = hits.first(where: { $0.entity is HasSceneUnderstanding }) {
        return RearHit(worldPoint: hit.position, method: "mesh", confidence: limited ? "medium" : "high")
      }
    }

    if let result = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any).first {
      return RearHit(worldPoint: result.worldTransform.translation, method: "existingPlane", confidence: limited ? "medium" : "high")
    }

    if let result = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first {
      return RearHit(worldPoint: result.worldTransform.translation, method: "estimatedPlane", confidence: limited ? "low" : "medium")
    }

    return nil
  }

  /// Tap-to-measure: raycast, drop a world anchor (so ARKit keeps it glued to
  /// the surface), and return the measurement. Returns nil on a miss.
  func measure(at point: CGPoint) -> [String: Any]? {
    guard isRunning else { return nil }
    guard let hit = hitTest(at: point) else { return nil }

    let id = UUID().uuidString
    let anchor = AnchorEntity(world: hit.worldPoint)
    if showMarkers {
      anchor.addChild(MarkerEntityFactory.makeMarker())
    }
    arView.scene.addAnchor(anchor)
    anchors[id] = anchor
    anchorOrder.append(id)
    smoother.reset()

    return [
      "meters": distance(to: hit.worldPoint),
      "confidence": hit.confidence,
      "anchorId": id,
      "method": hit.method,
      "worldPoint": [
        "x": Double(hit.worldPoint.x),
        "y": Double(hit.worldPoint.y),
        "z": Double(hit.worldPoint.z),
      ],
    ]
  }

  func clearAnchors() {
    for (_, anchor) in anchors {
      arView.scene.removeAnchor(anchor)
    }
    anchors.removeAll()
    anchorOrder.removeAll()
  }

  func removeAnchor(id: String) {
    guard let anchor = anchors.removeValue(forKey: id) else { return }
    arView.scene.removeAnchor(anchor)
    anchorOrder.removeAll { $0 == id }
  }

  // MARK: - ARSessionDelegate

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard updateHz > 0 else { return }
    guard frame.timestamp - lastEventTimestamp >= 1.0 / updateHz else { return }
    lastEventTimestamp = frame.timestamp
    guard mode == "rearCrosshair" || mode == "rearTap" || mode == "heatmap" else { return }

    if mode == "heatmap", let depthMap = frame.sceneDepth?.depthMap {
      onDepthFrame?(depthMap)
    }

    // Center-crosshair distance in all rear modes (in tap mode the JS
    // readout can toggle to it; heatmap shows it under the crosshair).
    if arView.bounds.width > 0 {
      let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
      if let hit = hitTest(at: center) {
        let raw = distance(to: hit.worldPoint)
        emitDistance(raw: raw, confidence: hit.confidence, method: hit.method)
      }
    }

    emitProjectedPoints()
  }

  /// Screen-space projection of every tapped point plus its live distance to
  /// the camera — the JS overlay draws lines/labels/fill from this.
  private func emitProjectedPoints() {
    guard !anchorOrder.isEmpty else {
      // Emit the empty set once (so JS clears the overlay), then stay quiet
      // instead of spamming the bridge 30×/s with nothing.
      if lastProjectedCount != 0 {
        host?.dispatchProjectedPoints(points: [])
        lastProjectedCount = 0
      }
      return
    }
    lastProjectedCount = anchorOrder.count
    let camPos = cameraPosition
    let matrix = arView.cameraTransform.matrix
    // Camera looks down its local -Z axis.
    let forward = -SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)

    var points: [[String: Any]] = []
    points.reserveCapacity(anchorOrder.count)
    for id in anchorOrder {
      guard let anchor = anchors[id] else { continue }
      let position = anchor.position(relativeTo: nil)
      let meters = Double(simd_length(position - camPos))
      let inFront = simd_dot(position - camPos, forward) > 0
      var entry: [String: Any] = ["id": id, "cameraMeters": meters]
      if inFront, let screen = arView.project(position) {
        entry["x"] = Double(screen.x)
        entry["y"] = Double(screen.y)
        entry["visible"] = true
      } else {
        entry["x"] = 0.0
        entry["y"] = 0.0
        entry["visible"] = false
      }
      points.append(entry)
    }
    host?.dispatchProjectedPoints(points: points)
  }

  private func emitDistance(raw: Double, confidence: String, method: String) {
    let smoothed = smoother.smooth(raw)
    host?.dispatchDistance(meters: smoothed, raw: raw, confidence: confidence, mode: mode, method: method)
  }

  func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    switch camera.trackingState {
    case .normal:
      trackingNormal = true
      host?.dispatchTrackingState(state: "normal", reason: nil)
    case .notAvailable:
      trackingNormal = false
      host?.dispatchTrackingState(state: "notAvailable", reason: nil)
    case .limited(let reason):
      trackingNormal = false
      switch reason {
      case .initializing:
        host?.dispatchTrackingState(state: "initializing", reason: nil)
      case .excessiveMotion:
        host?.dispatchTrackingState(state: "limited", reason: "excessiveMotion")
      case .insufficientFeatures:
        host?.dispatchTrackingState(state: "limited", reason: "insufficientFeatures")
      case .relocalizing:
        host?.dispatchTrackingState(state: "limited", reason: "relocalizing")
      @unknown default:
        host?.dispatchTrackingState(state: "limited", reason: nil)
      }
    }
  }

  func session(_ session: ARSession, didFailWithError error: Error) {
    isRunning = false
    trackingNormal = false
    host?.dispatchError(code: "ar_session_failed", message: error.localizedDescription)
    host?.dispatchTrackingState(state: "notAvailable", reason: nil)
  }

  func sessionWasInterrupted(_ session: ARSession) {
    host?.dispatchTrackingState(state: "limited", reason: "relocalizing")
  }

  func sessionInterruptionEnded(_ session: ARSession) {
    host?.dispatchTrackingState(state: trackingNormal ? "normal" : "initializing", reason: nil)
  }
}
