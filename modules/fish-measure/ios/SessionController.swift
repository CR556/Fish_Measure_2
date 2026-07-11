import ARKit
import Foundation
import RealityKit

extension simd_float4x4 {
  var translation: SIMD3<Float> { SIMD3(columns.3.x, columns.3.y, columns.3.z) }
}

struct RearHit {
  let worldPoint: SIMD3<Float>
  let method: String
  let confidence: String
}

final class SessionController: NSObject, ARSessionDelegate {
  private let arView: ARView
  private weak var host: FishARView?
  let smoother = DistanceSmoother()

  var updateHz: Double = 15
  var showMarkers = true
  var mode = "auto" {
    didSet { if oldValue != mode { smoother.reset() } }
  }
  var enableSceneReconstruction = true
  var enableHighResolutionCapture = true
  var debugDepthOverlay = false

  private var anchors: [String: AnchorEntity] = [:]
  private var anchorOrder: [String] = []
  private var lastManualEventTimestamp: TimeInterval = 0
  private var lastProjectedCount = -1
  private var trackingNormal = false
  private(set) var isRunning = false

  init(arView: ARView, host: FishARView) {
    self.arView = arView
    self.host = host
    super.init()
  }

  func start(resetTracking: Bool = true) {
    guard ARWorldTrackingConfiguration.isSupported,
          ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
      host?.dispatchError(code: "lidar_unsupported", message: "Rear LiDAR scene depth is unavailable.")
      host?.dispatchTrackingState(state: "notAvailable", reason: nil)
      return
    }

    let config = ARWorldTrackingConfiguration()
    if enableSceneReconstruction {
      if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
        config.sceneReconstruction = .meshWithClassification
      } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
        config.sceneReconstruction = .mesh
      }
      arView.environment.sceneUnderstanding.options.insert(.collision)
    } else {
      arView.environment.sceneUnderstanding.options.remove(.collision)
    }

    config.frameSemantics.insert(.sceneDepth)
    if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
      config.frameSemantics.insert(.smoothedSceneDepth)
    }
    config.planeDetection = [.horizontal, .vertical]
    if enableHighResolutionCapture,
       let format = ARWorldTrackingConfiguration.recommendedVideoFormatForHighResolutionFrameCapturing {
      config.videoFormat = format
    }

    arView.session.delegate = self
    smoother.reset()
    trackingNormal = false
    lastManualEventTimestamp = 0
    let options: ARSession.RunOptions = resetTracking
      ? [.resetTracking, .removeExistingAnchors]
      : []
    if resetTracking {
      clearAnchors()
    }
    arView.session.run(config, options: options)
    isRunning = true
    host?.dispatchTrackingState(state: "initializing", reason: nil)
  }

  func restartConfiguration() {
    guard isRunning else { return }
    start(resetTracking: false)
  }

  func pause() {
    guard isRunning else { return }
    arView.session.pause()
    isRunning = false
    trackingNormal = false
  }

  var currentFrame: ARFrame? { arView.session.currentFrame }

  func captureHighResolutionFrame(completion: @escaping (ARFrame?, Error?) -> Void) {
    guard isRunning, enableHighResolutionCapture else {
      completion(nil, nil)
      return
    }
    arView.session.captureHighResolutionFrame(completion: completion)
  }

  private var cameraPosition: SIMD3<Float> { arView.cameraTransform.translation }

  func hitTest(at point: CGPoint) -> RearHit? {
    let limited = !trackingNormal
    if enableSceneReconstruction, let ray = arView.ray(through: point) {
      let hits = arView.scene.raycast(
        origin: ray.origin,
        direction: ray.direction,
        length: 10,
        query: .nearest,
        mask: .all,
        relativeTo: nil)
      if let hit = hits.first(where: { $0.entity is HasSceneUnderstanding }) {
        return RearHit(
          worldPoint: hit.position,
          method: "mesh",
          confidence: limited ? "medium" : "high")
      }
    }
    if let result = arView.raycast(
      from: point, allowing: .existingPlaneGeometry, alignment: .any).first {
      return RearHit(
        worldPoint: result.worldTransform.translation,
        method: "existingPlane",
        confidence: limited ? "medium" : "high")
    }
    if let result = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first {
      return RearHit(
        worldPoint: result.worldTransform.translation,
        method: "estimatedPlane",
        confidence: limited ? "low" : "medium")
    }
    return nil
  }

  func measure(at point: CGPoint) -> [String: Any]? {
    guard isRunning, mode == "manual", let hit = hitTest(at: point) else { return nil }
    let id = UUID().uuidString
    let anchor = AnchorEntity(world: hit.worldPoint)
    if showMarkers { anchor.addChild(MarkerEntityFactory.makeMarker()) }
    arView.scene.addAnchor(anchor)
    anchors[id] = anchor
    anchorOrder.append(id)
    return [
      "meters": Double(simd_length(hit.worldPoint - cameraPosition)),
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
    for anchor in anchors.values { arView.scene.removeAnchor(anchor) }
    anchors.removeAll()
    anchorOrder.removeAll()
  }

  func removeAnchor(id: String) {
    guard let anchor = anchors.removeValue(forKey: id) else { return }
    arView.scene.removeAnchor(anchor)
    anchorOrder.removeAll { $0 == id }
  }

  func session(_ session: ARSession, didUpdate frame: ARFrame) {
    if mode == "auto" {
      host?.consume(frame: frame)
    }
    if debugDepthOverlay {
      let depth = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
      if let depth { host?.updateDebugDepth(depth) }
    }

    guard mode == "manual", updateHz > 0,
          frame.timestamp - lastManualEventTimestamp >= 1.0 / updateHz else { return }
    lastManualEventTimestamp = frame.timestamp
    if arView.bounds.width > 0 {
      let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
      if let hit = hitTest(at: center) {
        let raw = Double(simd_length(hit.worldPoint - cameraPosition))
        host?.dispatchDistance(
          meters: smoother.smooth(raw), raw: raw, confidence: hit.confidence,
          mode: "manual", method: hit.method)
      }
    }
    emitProjectedPoints()
  }

  private func emitProjectedPoints() {
    guard !anchorOrder.isEmpty else {
      if lastProjectedCount != 0 {
        host?.dispatchProjectedPoints(points: [])
        lastProjectedCount = 0
      }
      return
    }
    lastProjectedCount = anchorOrder.count
    let matrix = arView.cameraTransform.matrix
    let forward = -SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
    var points: [[String: Any]] = []
    for id in anchorOrder {
      guard let anchor = anchors[id] else { continue }
      let position = anchor.position(relativeTo: nil)
      let visible = simd_dot(position - cameraPosition, forward) > 0
      var item: [String: Any] = [
        "id": id,
        "cameraMeters": Double(simd_length(position - cameraPosition)),
        "visible": visible,
      ]
      if visible, let projected = arView.project(position) {
        item["x"] = Double(projected.x)
        item["y"] = Double(projected.y)
      } else {
        item["x"] = 0.0
        item["y"] = 0.0
      }
      points.append(item)
    }
    host?.dispatchProjectedPoints(points: points)
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
      case .initializing: host?.dispatchTrackingState(state: "initializing", reason: nil)
      case .excessiveMotion: host?.dispatchTrackingState(state: "limited", reason: "excessiveMotion")
      case .insufficientFeatures: host?.dispatchTrackingState(state: "limited", reason: "insufficientFeatures")
      case .relocalizing: host?.dispatchTrackingState(state: "limited", reason: "relocalizing")
      @unknown default: host?.dispatchTrackingState(state: "limited", reason: nil)
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
    if isRunning { start(resetTracking: false) }
  }
}
