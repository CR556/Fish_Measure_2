import CoreGraphics

final class ContourTracer {
  private let directions = [
    CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
    CGPoint(x: -1, y: 1), CGPoint(x: -1, y: 0), CGPoint(x: -1, y: -1),
    CGPoint(x: 0, y: -1), CGPoint(x: 1, y: -1),
  ]

  func trace(mask: BinaryMask, maxPoints: Int) -> [CGPoint] {
    guard let start = firstBoundary(mask) else { return [] }
    var contour: [CGPoint] = []
    var current = start
    var backtrack = CGPoint(x: start.x - 1, y: start.y)
    let initialBacktrack = backtrack
    let limit = max(mask.width * mask.height, 64)

    repeat {
      contour.append(current)
      let startIndex = directionIndex(from: current, to: backtrack)
      var found: CGPoint?
      var foundIndex = 0
      for offset in 1...8 {
        let index = (startIndex + offset) % 8
        let candidate = CGPoint(
          x: current.x + directions[index].x,
          y: current.y + directions[index].y)
        if isForeground(candidate, mask: mask) {
          found = candidate
          foundIndex = index
          break
        }
      }
      guard let next = found else { break }
      let previousIndex = (foundIndex + 7) % 8
      backtrack = CGPoint(
        x: current.x + directions[previousIndex].x,
        y: current.y + directions[previousIndex].y)
      current = next
      if contour.count > limit { break }
    } while current != start || backtrack != initialBacktrack

    let normalized = contour.map {
      CGPoint(x: $0.x / CGFloat(mask.width), y: $0.y / CGFloat(mask.height))
    }
    guard normalized.count > 3 else { return normalized }
    let simplified = douglasPeucker(normalized + [normalized[0]], epsilon: 0.002)
    return resampleClosed(simplified, count: max(16, maxPoints))
  }

  private func firstBoundary(_ mask: BinaryMask) -> CGPoint? {
    for y in 0..<mask.height {
      for x in 0..<mask.width where mask[x, y] != 0 {
        return CGPoint(x: x, y: y)
      }
    }
    return nil
  }

  private func isForeground(_ point: CGPoint, mask: BinaryMask) -> Bool {
    let x = Int(point.x), y = Int(point.y)
    return x >= 0 && y >= 0 && x < mask.width && y < mask.height && mask[x, y] != 0
  }

  private func directionIndex(from: CGPoint, to: CGPoint) -> Int {
    let dx = Int(to.x - from.x), dy = Int(to.y - from.y)
    return directions.firstIndex { Int($0.x) == dx && Int($0.y) == dy } ?? 4
  }

  private func douglasPeucker(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
    guard points.count > 2 else { return points }
    let first = points[0], last = points[points.count - 1]
    var maxDistance: CGFloat = 0
    var index = 0
    for i in 1..<(points.count - 1) {
      let distance = perpendicularDistance(points[i], lineStart: first, lineEnd: last)
      if distance > maxDistance { maxDistance = distance; index = i }
    }
    if maxDistance > epsilon {
      let left = douglasPeucker(Array(points[0...index]), epsilon: epsilon)
      let right = douglasPeucker(Array(points[index...]), epsilon: epsilon)
      return Array(left.dropLast()) + right
    }
    return [first, last]
  }

  private func perpendicularDistance(
    _ point: CGPoint,
    lineStart: CGPoint,
    lineEnd: CGPoint
  ) -> CGFloat {
    let dx = lineEnd.x - lineStart.x, dy = lineEnd.y - lineStart.y
    let lengthSquared = dx * dx + dy * dy
    guard lengthSquared > 0 else { return hypot(point.x - lineStart.x, point.y - lineStart.y) }
    let t = max(0, min(1,
      ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / lengthSquared))
    return hypot(point.x - (lineStart.x + t * dx), point.y - (lineStart.y + t * dy))
  }

  private func resampleClosed(_ points: [CGPoint], count: Int) -> [CGPoint] {
    guard points.count > 1, count > 1 else { return points }
    var closed = points
    if closed.first != closed.last, let first = closed.first { closed.append(first) }
    var cumulative = [CGFloat](repeating: 0, count: closed.count)
    for i in 1..<closed.count {
      cumulative[i] = cumulative[i - 1] + hypot(
        closed[i].x - closed[i - 1].x,
        closed[i].y - closed[i - 1].y)
    }
    guard let total = cumulative.last, total > 0 else { return points }
    var output: [CGPoint] = []
    var segment = 1
    for sample in 0..<count {
      let target = total * CGFloat(sample) / CGFloat(count)
      while segment < cumulative.count - 1 && cumulative[segment] < target { segment += 1 }
      let startDistance = cumulative[segment - 1]
      let span = max(0.000001, cumulative[segment] - startDistance)
      let t = (target - startDistance) / span
      output.append(CGPoint(
        x: closed[segment - 1].x + (closed[segment].x - closed[segment - 1].x) * t,
        y: closed[segment - 1].y + (closed[segment].y - closed[segment - 1].y) * t))
    }
    return output
  }
}
