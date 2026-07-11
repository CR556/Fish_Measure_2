import CoreGraphics

struct WidthSegment: Sendable {
  let a: CGPoint
  let b: CGPoint
}

struct Centerline2D: Sendable {
  let points: [CGPoint]
  let widths: [Double]
  let widthSegments: [WidthSegment]
}

final class CenterlineBuilder {
  func build(mask: BinaryMask, params: CenterlineParams) -> Centerline2D? {
    let bins = min(max(params.bins, 12), 128)
    if params.algorithm == "skeleton", let skeleton = buildSkeleton(mask: mask, bins: bins) {
      return skeleton
    }
    return buildPCA(mask: mask, bins: bins)
  }

  private func buildPCA(mask: BinaryMask, bins: Int) -> Centerline2D? {
    var samples: [CGPoint] = []
    samples.reserveCapacity(mask.foregroundCount)
    for y in 0..<mask.height {
      for x in 0..<mask.width where mask[x, y] != 0 {
        samples.append(CGPoint(
          x: (CGFloat(x) + 0.5) / CGFloat(mask.width),
          y: (CGFloat(y) + 0.5) / CGFloat(mask.height)))
      }
    }
    guard samples.count >= bins else { return nil }
    let mean = samples.reduce(CGPoint.zero) {
      CGPoint(x: $0.x + $1.x, y: $0.y + $1.y)
    }
    let center = CGPoint(x: mean.x / CGFloat(samples.count), y: mean.y / CGFloat(samples.count))
    var xx: CGFloat = 0, xy: CGFloat = 0, yy: CGFloat = 0
    for point in samples {
      let dx = point.x - center.x, dy = point.y - center.y
      xx += dx * dx; xy += dx * dy; yy += dy * dy
    }
    let theta = 0.5 * atan2(2 * xy, xx - yy)
    let axis = CGVector(dx: cos(theta), dy: sin(theta))
    let normal = CGVector(dx: -axis.dy, dy: axis.dx)
    let projected = samples.map { point -> (t: CGFloat, s: CGFloat) in
      let dx = point.x - center.x, dy = point.y - center.y
      return (dx * axis.dx + dy * axis.dy, dx * normal.dx + dy * normal.dy)
    }
    guard let minT = projected.map(\.t).min(), let maxT = projected.map(\.t).max(), maxT > minT
    else { return nil }

    var points: [CGPoint] = []
    var widths: [Double] = []
    var widthSegments: [WidthSegment] = []
    let binWidth = (maxT - minT) / CGFloat(bins)
    for bin in 0..<bins {
      let low = minT + CGFloat(bin) * binWidth
      let high = bin == bins - 1 ? maxT + 0.000001 : low + binWidth
      let values = projected.filter { $0.t >= low && $0.t < high }
      guard let minS = values.map(\.s).min(), let maxS = values.map(\.s).max() else { continue }
      let t = (low + min(high, maxT)) * 0.5
      let s = (minS + maxS) * 0.5
      points.append(CGPoint(
        x: center.x + t * axis.dx + s * normal.dx,
        y: center.y + t * axis.dy + s * normal.dy))
      widths.append(Double(maxS - minS))
      widthSegments.append(WidthSegment(
        a: CGPoint(
          x: center.x + t * axis.dx + minS * normal.dx,
          y: center.y + t * axis.dy + minS * normal.dy),
        b: CGPoint(
          x: center.x + t * axis.dx + maxS * normal.dx,
          y: center.y + t * axis.dy + maxS * normal.dy)))
    }
    guard points.count >= max(6, bins / 2) else { return nil }
    return Centerline2D(points: points, widths: widths, widthSegments: widthSegments)
  }

  private func buildSkeleton(mask source: BinaryMask, bins: Int) -> Centerline2D? {
    let scale = min(1, 256.0 / Double(max(source.width, source.height)))
    let mask = source.resized(
      width: max(1, Int(Double(source.width) * scale)),
      height: max(1, Int(Double(source.height) * scale)))
    guard mask.width >= 3, mask.height >= 3 else { return nil }
    var skeleton = mask
    var changed = true
    var iterations = 0
    while changed && iterations < 256 {
      changed = false
      iterations += 1
      for phase in 0...1 {
        var remove: [Int] = []
        for y in 1..<(skeleton.height - 1) {
          for x in 1..<(skeleton.width - 1) where skeleton[x, y] != 0 {
            let p2 = skeleton[x, y - 1], p3 = skeleton[x + 1, y - 1]
            let p4 = skeleton[x + 1, y], p5 = skeleton[x + 1, y + 1]
            let p6 = skeleton[x, y + 1], p7 = skeleton[x - 1, y + 1]
            let p8 = skeleton[x - 1, y], p9 = skeleton[x - 1, y - 1]
            let neighbors = [p2, p3, p4, p5, p6, p7, p8, p9]
            let count = neighbors.reduce(0) { $0 + Int($1) }
            guard count >= 2 && count <= 6 else { continue }
            var transitions = 0
            for index in neighbors.indices where neighbors[index] == 0 && neighbors[(index + 1) % 8] != 0 {
              transitions += 1
            }
            guard transitions == 1 else { continue }
            let conditionA = phase == 0 ? p2 * p4 * p6 == 0 : p2 * p4 * p8 == 0
            let conditionB = phase == 0 ? p4 * p6 * p8 == 0 : p2 * p6 * p8 == 0
            if conditionA && conditionB { remove.append(y * skeleton.width + x) }
          }
        }
        if !remove.isEmpty { changed = true }
        for index in remove { skeleton.pixels[index] = 0 }
      }
    }
    guard let seed = skeleton.pixels.firstIndex(of: 1) else { return nil }
    let first = farthest(from: seed, skeleton: skeleton)
    let second = farthest(from: first.index, skeleton: skeleton, keepParents: true)
    var pathIndices: [Int] = []
    var current: Int? = second.index
    while let index = current {
      pathIndices.append(index)
      if index == first.index { break }
      current = second.parents[index]
    }
    guard pathIndices.count >= 8 else { return nil }
    let raw = pathIndices.reversed().map { index in
      CGPoint(
        x: (CGFloat(index % skeleton.width) + 0.5) / CGFloat(skeleton.width),
        y: (CGFloat(index / skeleton.width) + 0.5) / CGFloat(skeleton.height))
    }
    let points = resampleOpen(raw, count: bins)
    var widths: [Double] = []
    var segments: [WidthSegment] = []
    for index in points.indices {
      let previous = points[max(0, index - 1)]
      let next = points[min(points.count - 1, index + 1)]
      let tangentPixels = CGVector(
        dx: (next.x - previous.x) * CGFloat(skeleton.width),
        dy: (next.y - previous.y) * CGFloat(skeleton.height))
      let length = max(0.0001, hypot(tangentPixels.dx, tangentPixels.dy))
      let normalPixels = CGVector(dx: -tangentPixels.dy / length, dy: tangentPixels.dx / length)
      let edges = scanEdges(point: points[index], normalPixels: normalPixels, mask: mask)
      segments.append(edges)
      widths.append(Double(hypot(edges.b.x - edges.a.x, edges.b.y - edges.a.y)))
    }
    return Centerline2D(points: points, widths: widths, widthSegments: segments)
  }

  private func farthest(
    from start: Int,
    skeleton: BinaryMask,
    keepParents: Bool = false
  ) -> (index: Int, parents: [Int: Int]) {
    var queue = [start], cursor = 0
    var distance = [start: 0]
    var parents: [Int: Int] = [:]
    var farthest = start
    while cursor < queue.count {
      let index = queue[cursor]; cursor += 1
      let x = index % skeleton.width, y = index / skeleton.width
      for yy in max(0, y - 1)...min(skeleton.height - 1, y + 1) {
        for xx in max(0, x - 1)...min(skeleton.width - 1, x + 1) {
          let next = yy * skeleton.width + xx
          guard next != index, skeleton.pixels[next] != 0, distance[next] == nil else { continue }
          distance[next] = (distance[index] ?? 0) + 1
          parents[next] = index
          queue.append(next)
          if (distance[next] ?? 0) > (distance[farthest] ?? 0) { farthest = next }
        }
      }
    }
    return (farthest, keepParents ? parents : [:])
  }

  private func scanEdges(
    point: CGPoint,
    normalPixels: CGVector,
    mask: BinaryMask
  ) -> WidthSegment {
    func scan(sign: CGFloat) -> CGPoint {
      var last = point
      for step in 1...max(mask.width, mask.height) {
        let candidate = CGPoint(
          x: point.x + sign * normalPixels.dx * CGFloat(step) / CGFloat(mask.width),
          y: point.y + sign * normalPixels.dy * CGFloat(step) / CGFloat(mask.height))
        let x = Int(candidate.x * CGFloat(mask.width)), y = Int(candidate.y * CGFloat(mask.height))
        guard x >= 0, y >= 0, x < mask.width, y < mask.height, mask[x, y] != 0 else { break }
        last = candidate
      }
      return last
    }
    return WidthSegment(a: scan(sign: -1), b: scan(sign: 1))
  }

  private func resampleOpen(_ points: [CGPoint], count: Int) -> [CGPoint] {
    guard points.count > 1 else { return points }
    var cumulative = [CGFloat](repeating: 0, count: points.count)
    for index in 1..<points.count {
      cumulative[index] = cumulative[index - 1] + hypot(
        points[index].x - points[index - 1].x,
        points[index].y - points[index - 1].y)
    }
    guard let total = cumulative.last, total > 0 else { return points }
    var output: [CGPoint] = [], segment = 1
    for sample in 0..<count {
      let target = total * CGFloat(sample) / CGFloat(count - 1)
      while segment < cumulative.count - 1 && cumulative[segment] < target { segment += 1 }
      let span = max(0.000001, cumulative[segment] - cumulative[segment - 1])
      let t = (target - cumulative[segment - 1]) / span
      output.append(CGPoint(
        x: points[segment - 1].x + (points[segment].x - points[segment - 1].x) * t,
        y: points[segment - 1].y + (points[segment].y - points[segment - 1].y) * t))
    }
    return output
  }
}
