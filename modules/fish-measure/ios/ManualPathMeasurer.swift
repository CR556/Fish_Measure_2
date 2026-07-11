import ARKit
import Foundation

struct ManualPathMeasurementNative: @unchecked Sendable {
  let packet: FramePacket
  let measurement: LiftedMeasurement
  let imagePoints: [CGPoint]

  var dictionary: [String: Any] {
    [
      "curvedM": measurement.curvedM,
      "chordM": measurement.chordM,
      "sampleCount": measurement.centerlineWorld.count,
      "validFraction": measurement.depthCoverage,
      "worldPoints": measurement.centerlineWorld.flatMap {
        [Double($0.x), Double($0.y), Double($0.z)]
      },
    ]
  }
}

final class ManualPathMeasurer {
  private let queue = DispatchQueue(label: "fish.manual-path", qos: .userInitiated)
  private let depthLifter = DepthLifter()

  func measure(
    frame: ARFrame,
    points: [CGPoint],
    sampleCount: Int?,
    viewSize: CGSize,
    orientation: UIInterfaceOrientation,
    params: CenterlineParams
  ) async -> [String: Any]? {
    await withCheckedContinuation { continuation in
      measure(
        frame: frame, points: points, sampleCount: sampleCount,
        viewSize: viewSize, orientation: orientation, params: params
      ) { result in
        continuation.resume(returning: result?.dictionary)
      }
    }
  }

  func measure(
    frame: ARFrame,
    points: [CGPoint],
    sampleCount: Int?,
    viewSize: CGSize,
    orientation: UIInterfaceOrientation,
    params: CenterlineParams,
    completion: @escaping (ManualPathMeasurementNative?) -> Void
  ) {
    guard points.count >= 2,
          let packet = FramePacket.copy(
            frame: frame, depthSource: "smoothed", viewSize: viewSize, orientation: orientation)
    else {
      completion(nil)
      return
    }
    let count = min(max(sampleCount ?? max(32, points.count * 8), 8), 256)
    let resampledView = resample(points, count: count)
    let imagePoints = resampledView.map {
      CoordinateMapper.viewToImageNormalized(
        $0, viewSize: viewSize, displayTransform: packet.displayTransform)
    }
    let dummySegments = imagePoints.map { WidthSegment(a: $0, b: $0) }
    let line = Centerline2D(
      points: imagePoints,
      widths: [Double](repeating: 0, count: imagePoints.count),
      widthSegments: dummySegments)
    queue.async { [depthLifter] in
      guard let measurement = depthLifter.lift(
        centerline: line,
        packet: packet,
        segmentation: SegmentationParams(),
        params: params) else {
        completion(nil)
        return
      }
      completion(ManualPathMeasurementNative(
        packet: packet, measurement: measurement, imagePoints: imagePoints))
    }
  }

  private func resample(_ points: [CGPoint], count: Int) -> [CGPoint] {
    guard points.count > 1 else { return points }
    var cumulative = [CGFloat](repeating: 0, count: points.count)
    for index in 1..<points.count {
      cumulative[index] = cumulative[index - 1] + hypot(
        points[index].x - points[index - 1].x,
        points[index].y - points[index - 1].y)
    }
    guard let total = cumulative.last, total > 0 else { return points }
    var output: [CGPoint] = []
    var segment = 1
    for sample in 0..<count {
      let target = total * CGFloat(sample) / CGFloat(count - 1)
      while segment < cumulative.count - 1 && cumulative[segment] < target { segment += 1 }
      let startDistance = cumulative[segment - 1]
      let span = max(0.000001, cumulative[segment] - startDistance)
      let t = (target - startDistance) / span
      output.append(CGPoint(
        x: points[segment - 1].x + (points[segment].x - points[segment - 1].x) * t,
        y: points[segment - 1].y + (points[segment].y - points[segment - 1].y) * t))
    }
    return output
  }
}
