import ARKit
import CoreGraphics

struct LiftedMeasurement: @unchecked Sendable {
  let curvedM: Double
  let chordM: Double
  let centerlineWorld: [SIMD3<Float>]
  let centerlineImage: [CGPoint]
  let widthsM: [Double]
  let fittedDepths: [Double]
  let depthCoverage: Double
  let distanceM: Double
}

final class DepthLifter {
  func lift(
    centerline: Centerline2D,
    packet: FramePacket,
    segmentation: SegmentationParams,
    params: CenterlineParams
  ) -> LiftedMeasurement? {
    let radius = min(max(params.depthSampleRadiusPx, 0), 5)
    var rawDepths = sampleForegroundDepths(
      centerline: centerline,
      depthMap: packet.depthMap,
      confidenceMap: packet.confidenceMap,
      minimumConfidence: segmentation.minDepthConfidence,
      radius: radius,
      params: params)
    rawDepths = rejectDepthDiscontinuities(rawDepths, params: params)
    let validCount = rawDepths.compactMap { $0 }.count
    let initialCoverage = Double(validCount) / Double(max(1, rawDepths.count))
    guard initialCoverage >= params.minValidBinFraction,
          maximumGapFraction(rawDepths) <= params.maxGapBinFraction else { return nil }

    let degree = min(max(params.depthFitDegree, 1), 5)
    guard var coefficients = fit(depths: rawDepths, degree: degree) else { return nil }
    let residuals = rawDepths.enumerated().compactMap { index, depth -> Double? in
      guard let depth else { return nil }
      return depth - evaluate(coefficients, t: normalizedT(index, rawDepths.count))
    }
    let medianResidual = median(residuals)
    let mad = median(residuals.map { abs($0 - medianResidual) })
    if mad > 0 {
      let scale = 1.4826 * mad
      for index in rawDepths.indices {
        guard let depth = rawDepths[index] else { continue }
        let residual = abs(depth - evaluate(coefficients, t: normalizedT(index, rawDepths.count)))
        if residual > params.outlierRejectSigma * scale { rawDepths[index] = nil }
      }
      guard let refit = fit(depths: rawDepths, degree: degree) else { return nil }
      coefficients = refit
    }

    let finalValidCount = rawDepths.compactMap { $0 }.count
    let coverage = Double(finalValidCount) / Double(max(1, rawDepths.count))
    guard coverage >= params.minValidBinFraction,
          maximumGapFraction(rawDepths) <= params.maxGapBinFraction else { return nil }
    let acceptedDepths = rawDepths.compactMap { $0 }
    guard let minimumAccepted = acceptedDepths.min(), let maximumAccepted = acceptedDepths.max()
    else { return nil }
    let envelopeMargin = min(max(params.depthEnvelopeMarginM, 0), 0.5)
    let fitted = centerline.points.indices.map { index in
      let value = evaluate(coefficients, t: normalizedT(index, centerline.points.count))
      return min(max(value, minimumAccepted - envelopeMargin), maximumAccepted + envelopeMargin)
    }
    guard fitted.allSatisfy({ $0.isFinite && $0 > 0.05 && $0 < 10 }) else { return nil }
    let world = zip(centerline.points, fitted).map {
      unproject(normalizedPoint: $0.0, depth: $0.1, packet: packet)
    }
    guard world.count >= 2 else { return nil }
    var curved = 0.0
    for index in 1..<world.count { curved += Double(simd_length(world[index] - world[index - 1])) }
    let chord = Double(simd_length(world[world.count - 1] - world[0]))
    guard curved.isFinite, chord.isFinite, curved + 0.001 >= chord else { return nil }

    var widthsM: [Double] = []
    for (index, segment) in centerline.widthSegments.enumerated() {
      let depth = fitted[min(index, fitted.count - 1)]
      let a = unproject(normalizedPoint: segment.a, depth: depth, packet: packet)
      let b = unproject(normalizedPoint: segment.b, depth: depth, packet: packet)
      widthsM.append(Double(simd_length(b - a)))
    }
    return LiftedMeasurement(
      curvedM: curved,
      chordM: chord,
      centerlineWorld: world,
      centerlineImage: centerline.points,
      widthsM: widthsM,
      fittedDepths: fitted,
      depthCoverage: coverage,
      distanceM: median(fitted))
  }

  func unproject(normalizedPoint: CGPoint, depth: Double, packet: FramePacket) -> SIMD3<Float> {
    let u = Float(normalizedPoint.x * packet.imageResolution.width)
    let v = Float(normalizedPoint.y * packet.imageResolution.height)
    let z = Float(depth)
    let fx = packet.intrinsics.columns.0.x
    let fy = packet.intrinsics.columns.1.y
    let cx = packet.intrinsics.columns.2.x
    let cy = packet.intrinsics.columns.2.y
    let cameraPoint = SIMD4<Float>((u - cx) * z / fx, -(v - cy) * z / fy, -z, 1)
    let world = packet.cameraTransform * cameraPoint
    return SIMD3(world.x, world.y, world.z)
  }

  private func sampleForegroundDepths(
    centerline: Centerline2D,
    depthMap: CVPixelBuffer,
    confidenceMap: CVPixelBuffer?,
    minimumConfidence: Int,
    radius: Int,
    params: CenterlineParams
  ) -> [Double?] {
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    if let confidenceMap { CVPixelBufferLockBaseAddress(confidenceMap, .readOnly) }
    defer {
      if let confidenceMap { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
      CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
    }
    guard let depthBase = CVPixelBufferGetBaseAddress(depthMap) else {
      return [Double?](repeating: nil, count: centerline.points.count)
    }
    let width = CVPixelBufferGetWidth(depthMap), height = CVPixelBufferGetHeight(depthMap)
    let depthStride = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
    let depthValues = depthBase.assumingMemoryBound(to: Float32.self)
    let confidenceBase: UnsafeMutablePointer<UInt8>?
    let confidenceStride: Int
    if let confidenceMap, let base = CVPixelBufferGetBaseAddress(confidenceMap) {
      confidenceBase = base.assumingMemoryBound(to: UInt8.self)
      confidenceStride = CVPixelBufferGetBytesPerRow(confidenceMap)
    } else {
      confidenceBase = nil
      confidenceStride = 0
    }
    let transverseCount = min(max(params.depthTransverseSamples, 1), 15)
    let inset = min(max(params.depthTransverseInsetFraction, 0), 0.45)
    let foregroundQuantile = min(max(params.depthForegroundQuantile, 0), 0.5)

    func values(around point: CGPoint) -> [Double] {
      let x = min(width - 1, max(0, Int(point.x * CGFloat(width))))
      let y = min(height - 1, max(0, Int(point.y * CGFloat(height))))
      var output: [Double] = []
      for yy in max(0, y - radius)...min(height - 1, y + radius) {
        for xx in max(0, x - radius)...min(width - 1, x + radius) {
          if let confidenceBase,
             Int(confidenceBase[yy * confidenceStride + xx]) < minimumConfidence { continue }
          let value = Double(depthValues[yy * depthStride + xx])
          if value.isFinite && value > 0.05 && value < 10 { output.append(value) }
        }
      }
      return output
    }

    return centerline.points.indices.map { index in
      var candidates = values(around: centerline.points[index])
      if index < centerline.widthSegments.count, transverseCount > 1 {
        let segment = centerline.widthSegments[index]
        for sample in 0..<transverseCount {
          let unit = Double(sample) / Double(transverseCount - 1)
          let t = CGFloat(inset + (1 - inset * 2) * unit)
          let point = CGPoint(
            x: segment.a.x + (segment.b.x - segment.a.x) * t,
            y: segment.a.y + (segment.b.y - segment.a.y) * t)
          candidates.append(contentsOf: values(around: point))
        }
      }
      return quantile(candidates, foregroundQuantile)
    }
  }

  /// Starting from a representative body sample, walk toward both tips and
  /// discard sudden depth jumps. A real curved fish changes depth smoothly;
  /// an exposed background pixel behind a thin tail does not.
  private func rejectDepthDiscontinuities(
    _ depths: [Double?],
    params: CenterlineParams
  ) -> [Double?] {
    guard depths.count >= 3 else { return depths }
    let lower = depths.count / 4
    let upper = min(depths.count - 1, depths.count * 3 / 4)
    let central = (lower...upper).compactMap { index -> (Int, Double)? in
      depths[index].map { (index, $0) }
    }
    guard !central.isEmpty else { return depths }
    let centralMedian = median(central.map { $0.1 })
    guard let seed = central.min(by: { abs($0.1 - centralMedian) < abs($1.1 - centralMedian) })
    else { return depths }
    var filtered = depths
    let fixedLimit = min(max(params.maxDepthStepM, 0.005), 0.5)
    let fractionalLimit = min(max(params.maxDepthStepFraction, 0), 0.5)

    func accepted(_ value: Double, after previous: Double) -> Bool {
      abs(value - previous) <= max(fixedLimit, abs(previous) * fractionalLimit)
    }

    var previous = seed.1
    if seed.0 + 1 < depths.count {
      for index in (seed.0 + 1)..<depths.count {
        guard let value = depths[index] else { continue }
        if accepted(value, after: previous) { previous = value }
        else { filtered[index] = nil }
      }
    }
    previous = seed.1
    if seed.0 > 0 {
      for index in stride(from: seed.0 - 1, through: 0, by: -1) {
        guard let value = depths[index] else { continue }
        if accepted(value, after: previous) { previous = value }
        else { filtered[index] = nil }
      }
    }
    return filtered
  }

  private func quantile(_ values: [Double], _ fraction: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * fraction)))
    return sorted[index]
  }

  private func maximumGapFraction(_ values: [Double?]) -> Double {
    var current = 0, maximum = 0
    for value in values {
      if value == nil { current += 1; maximum = max(maximum, current) } else { current = 0 }
    }
    return Double(maximum) / Double(max(1, values.count))
  }

  private func normalizedT(_ index: Int, _ count: Int) -> Double {
    count <= 1 ? 0 : Double(index) / Double(count - 1)
  }

  private func fit(depths: [Double?], degree: Int) -> [Double]? {
    let rows = depths.enumerated().compactMap { index, depth -> (Double, Double)? in
      depth.map { (normalizedT(index, depths.count), $0) }
    }
    guard rows.count > degree else { return nil }
    let size = degree + 1
    var matrix = Array(repeating: Array(repeating: 0.0, count: size + 1), count: size)
    for row in 0..<size {
      for column in 0..<size {
        matrix[row][column] = rows.reduce(0) { $0 + pow($1.0, Double(row + column)) }
      }
      matrix[row][size] = rows.reduce(0) { $0 + $1.1 * pow($1.0, Double(row)) }
    }
    return solve(matrix)
  }

  private func solve(_ source: [[Double]]) -> [Double]? {
    var matrix = source
    let count = matrix.count
    for column in 0..<count {
      guard let pivot = (column..<count).max(by: {
        abs(matrix[$0][column]) < abs(matrix[$1][column])
      }), abs(matrix[pivot][column]) > 1e-12 else { return nil }
      if pivot != column { matrix.swapAt(pivot, column) }
      let divisor = matrix[column][column]
      for item in column...count { matrix[column][item] /= divisor }
      for row in 0..<count where row != column {
        let factor = matrix[row][column]
        for item in column...count { matrix[row][item] -= factor * matrix[column][item] }
      }
    }
    return matrix.map { $0[count] }
  }

  private func evaluate(_ coefficients: [Double], t: Double) -> Double {
    coefficients.enumerated().reduce(0) { $0 + $1.element * pow(t, Double($1.offset)) }
  }
}

func median(_ values: [Double]) -> Double {
  guard !values.isEmpty else { return 0 }
  let sorted = values.sorted()
  let middle = sorted.count / 2
  return sorted.count.isMultiple(of: 2)
    ? (sorted[middle - 1] + sorted[middle]) * 0.5
    : sorted[middle]
}
