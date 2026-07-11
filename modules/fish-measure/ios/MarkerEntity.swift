import RealityKit
import UIKit

enum MarkerEntityFactory {
  /// Small unlit sphere pinned at the measured point. Unlit so it stays
  /// visible regardless of scene lighting. No CollisionComponent — markers
  /// must never intercept the measurement raycasts.
  static func makeMarker() -> ModelEntity {
    let mesh = MeshResource.generateSphere(radius: 0.008)
    let material = UnlitMaterial(color: UIColor.systemYellow)
    return ModelEntity(mesh: mesh, materials: [material])
  }
}
