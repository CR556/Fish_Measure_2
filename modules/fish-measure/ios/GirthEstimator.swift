import CoreGraphics
import CoreVideo

struct GirthResult: Sendable {
  let meters: Double
  let method: String
}

final class GirthEstimator {
  func estimate(
    centerline: Centerline2D,
    measurement: LiftedMeasurement,
    packet: FramePacket,
    params: GirthParams
  ) -> GirthResult? {
    guard let widestIndex = measurement.widthsM.indices.max(by: {
      measurement.widthsM[$0] < measurement.widthsM[$1]
    }) else { return nil }
    let a = measurement.widthsM[widestIndex] * 0.5
    guard a.isFinite && a > 0 else { return nil }
    var b = a * min(max(params.aspect, 0.1), 1.5)
    var method = "aspectFallback"
    if params.useDepthBulge, widestIndex < centerline.widthSegments.count,
       let bulge = depthBulge(
        segment: centerline.widthSegments[widestIndex],
        depthMap: packet.depthMap),
       bulge > a * 0.08, bulge < a * 1.5 {
      b = bulge
      method = "depthBulge"
    }
    let h = pow(a - b, 2) / pow(a + b, 2)
    let perimeter = Double.pi * (a + b) * (1 + 3 * h / (10 + sqrt(4 - 3 * h)))
    return GirthResult(meters: perimeter * min(max(params.calibration, 0.25), 4), method: method)
  }

  private func depthBulge(segment: WidthSegment, depthMap: CVPixelBuffer) -> Double? {
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
    let width = CVPixelBufferGetWidth(depthMap), height = CVPixelBufferGetHeight(depthMap)
    let stride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
    let values = base.assumingMemoryBound(to: Float32.self)
    var samples: [Double] = []
    for index in 0..<17 {
      let t = CGFloat(index) / 16
      let point = CGPoint(
        x: segment.a.x + (segment.b.x - segment.a.x) * t,
        y: segment.a.y + (segment.b.y - segment.a.y) * t)
      let x = min(width - 1, max(0, Int(point.x * CGFloat(width))))
      let y = min(height - 1, max(0, Int(point.y * CGFloat(height))))
      let value = Double(values[y * stride + x])
      if value.isFinite && value > 0.05 && value < 10 { samples.append(value) }
    }
    guard samples.count >= 9 else { return nil }
    let sorted = samples.sorted()
    let near = median(Array(sorted.prefix(max(3, sorted.count / 4))))
    let far = median(Array(sorted.suffix(max(3, sorted.count / 4))))
    let bulge = far - near
    return bulge.isFinite && bulge > 0 ? bulge : nil
  }
}
