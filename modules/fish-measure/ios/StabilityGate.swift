import Foundation

struct StabilitySample: Sendable {
  let frameId: Int
  let timestamp: TimeInterval
  let curvedM: Double
  let chordM: Double
  let girth: GirthResult?
  let confidence: Double
  let distanceM: Double
  let depthCoverage: Double
}

struct StabilitySnapshot: Sendable {
  let stable: Bool
  let stableForMs: Double
  let medianCurvedM: Double
  let standardDeviationM: Double
  let frames: Int
  let representative: StabilitySample
}

final class StabilityGate {
  private var samples: [StabilitySample] = []
  private var stableSince: TimeInterval?

  func reset() {
    samples.removeAll()
    stableSince = nil
  }

  func update(_ sample: StabilitySample, params: StabilityParams) -> StabilitySnapshot {
    samples.append(sample)
    let cutoff = sample.timestamp - params.windowMs / 1000
    samples.removeAll { $0.timestamp < cutoff }
    let lengths = samples.map(\.curvedM)
    let medianLength = median(lengths)
    let mean = lengths.reduce(0, +) / Double(max(1, lengths.count))
    let variance = lengths.reduce(0) { $0 + pow($1 - mean, 2) } / Double(max(1, lengths.count))
    let stddev = sqrt(variance)
    let allowedDelta = max(params.maxDeltaCm / 100, medianLength * params.maxDeltaFraction)
    let spread = (lengths.max() ?? 0) - (lengths.min() ?? 0)
    let windowCovered = (samples.last?.timestamp ?? 0) - (samples.first?.timestamp ?? 0)
      >= params.windowMs / 1000 * 0.8
    let stable = samples.count >= 4 && windowCovered && spread <= allowedDelta
      && sample.distanceM >= params.minDistanceM && sample.distanceM <= params.maxDistanceM
      && sample.depthCoverage >= params.minDepthCoverage
    if stable {
      if stableSince == nil { stableSince = sample.timestamp }
    } else {
      stableSince = nil
    }
    let representative = samples.min(by: {
      abs($0.curvedM - medianLength) < abs($1.curvedM - medianLength)
    }) ?? sample
    return StabilitySnapshot(
      stable: stable,
      stableForMs: stableSince.map { max(0, sample.timestamp - $0) * 1000 } ?? 0,
      medianCurvedM: medianLength,
      standardDeviationM: stddev,
      frames: samples.count,
      representative: representative)
  }
}
