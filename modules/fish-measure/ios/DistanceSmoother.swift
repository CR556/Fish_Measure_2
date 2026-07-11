import Foundation

/// Rolling median (kills spike outliers) followed by an EMA (kills jitter).
/// Parameters are settable at runtime via the `smoothing` prop so tuning
/// never requires a native rebuild.
final class DistanceSmoother {
  private var window: [Double] = []
  private var ema: Double?

  var medianWindow: Int = 5
  var emaAlpha: Double = 0.3

  func reset() {
    window.removeAll()
    ema = nil
  }

  func smooth(_ value: Double) -> Double {
    window.append(value)
    let size = max(1, medianWindow)
    if window.count > size {
      window.removeFirst(window.count - size)
    }
    let sorted = window.sorted()
    let median = sorted[sorted.count / 2]

    let alpha = min(max(emaAlpha, 0.01), 1.0)
    let next: Double
    if let previous = ema {
      next = previous + alpha * (median - previous)
    } else {
      next = median
    }
    ema = next
    return next
  }
}
