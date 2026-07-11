import ARKit
import CoreVideo
import UIKit

struct FramePacket: @unchecked Sendable {
  let capturedImage: CVPixelBuffer
  let depthMap: CVPixelBuffer
  let confidenceMap: CVPixelBuffer?
  let cameraTransform: simd_float4x4
  let intrinsics: simd_float3x3
  let imageResolution: CGSize
  let displayTransform: CGAffineTransform
  let timestamp: TimeInterval
  let epochTimestampMs: Double
  let viewSize: CGSize

  static func copy(
    frame: ARFrame,
    depthSource: String,
    viewSize: CGSize,
    orientation: UIInterfaceOrientation
  ) -> FramePacket? {
    let depthData = depthSource == "raw"
      ? frame.sceneDepth
      : (frame.smoothedSceneDepth ?? frame.sceneDepth)
    guard let depthData,
          let imageCopy = PixelBufferCopier.copy(frame.capturedImage),
          let depthCopy = PixelBufferCopier.copy(depthData.depthMap) else { return nil }
    let confidenceCopy: CVPixelBuffer?
    if let confidenceMap = depthData.confidenceMap {
      confidenceCopy = PixelBufferCopier.copy(confidenceMap)
    } else {
      confidenceCopy = nil
    }
    return FramePacket(
      capturedImage: imageCopy,
      depthMap: depthCopy,
      confidenceMap: confidenceCopy,
      cameraTransform: frame.camera.transform,
      intrinsics: frame.camera.intrinsics,
      imageResolution: frame.camera.imageResolution,
      displayTransform: frame.displayTransform(for: orientation, viewportSize: viewSize),
      timestamp: frame.timestamp,
      epochTimestampMs: Date().timeIntervalSince1970 * 1000,
      viewSize: viewSize)
  }
}

enum PixelBufferCopier {
  static func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
    let width = CVPixelBufferGetWidth(source)
    let height = CVPixelBufferGetHeight(source)
    let format = CVPixelBufferGetPixelFormatType(source)
    let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]
    var destination: CVPixelBuffer?
    guard CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, format, attributes as CFDictionary, &destination) == kCVReturnSuccess,
      let destination else { return nil }

    CVPixelBufferLockBaseAddress(source, .readOnly)
    CVPixelBufferLockBaseAddress(destination, [])
    defer {
      CVPixelBufferUnlockBaseAddress(destination, [])
      CVPixelBufferUnlockBaseAddress(source, .readOnly)
    }

    if CVPixelBufferIsPlanar(source) {
      let planes = min(CVPixelBufferGetPlaneCount(source), CVPixelBufferGetPlaneCount(destination))
      for plane in 0..<planes {
        guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
              let dst = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else { continue }
        let rows = min(
          CVPixelBufferGetHeightOfPlane(source, plane),
          CVPixelBufferGetHeightOfPlane(destination, plane))
        let srcStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
        let dstStride = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
        let bytes = min(srcStride, dstStride)
        for row in 0..<rows {
          memcpy(dst.advanced(by: row * dstStride), src.advanced(by: row * srcStride), bytes)
        }
      }
    } else if let src = CVPixelBufferGetBaseAddress(source),
              let dst = CVPixelBufferGetBaseAddress(destination) {
      let rows = min(CVPixelBufferGetHeight(source), CVPixelBufferGetHeight(destination))
      let srcStride = CVPixelBufferGetBytesPerRow(source)
      let dstStride = CVPixelBufferGetBytesPerRow(destination)
      let bytes = min(srcStride, dstStride)
      for row in 0..<rows {
        memcpy(dst.advanced(by: row * dstStride), src.advanced(by: row * srcStride), bytes)
      }
    }
    return destination
  }
}

enum CoordinateMapper {
  static func imageNormalizedToView(_ point: CGPoint, packet: FramePacket) -> CGPoint {
    let transformed = point.applying(packet.displayTransform)
    return CGPoint(x: transformed.x * packet.viewSize.width, y: transformed.y * packet.viewSize.height)
  }

  static func viewToImageNormalized(
    _ point: CGPoint,
    viewSize: CGSize,
    displayTransform: CGAffineTransform
  ) -> CGPoint {
    guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
    let normalized = CGPoint(x: point.x / viewSize.width, y: point.y / viewSize.height)
    return normalized.applying(displayTransform.inverted())
  }
}
