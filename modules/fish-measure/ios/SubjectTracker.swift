import CoreGraphics

struct TrackingResult: Sendable {
  let state: String
  let selectedBy: String
  let acceptsDetectedSubject: Bool
}

final class SubjectTracker {
  private var lastBounds: CGRect?
  private var consecutive = 0
  private var lastSeen: TimeInterval = 0
  private var locked = false
  private var mismatchFrames = 0

  func reset() {
    lastBounds = nil
    consecutive = 0
    lastSeen = 0
    locked = false
    mismatchFrames = 0
  }

  func update(
    subject: SegmentedSubject?,
    timestamp: TimeInterval,
    params: TrackingParams
  ) -> TrackingResult {
    guard let subject else {
      if locked && (timestamp - lastSeen) * 1000 <= params.lostGraceMs {
        mismatchFrames += 1
        if mismatchFrames <= max(1, params.maxMismatchFrames) {
          return TrackingResult(
            state: "locked", selectedBy: "temporal", acceptsDetectedSubject: false)
        }
        reset()
      }
      if (timestamp - lastSeen) * 1000 > params.lostGraceMs { reset() }
      return TrackingResult(state: "none", selectedBy: "none", acceptsDetectedSubject: false)
    }
    let associated: Bool
    if let lastBounds {
      let iou = intersectionOverUnion(lastBounds, subject.bounds)
      let distance = hypot(lastBounds.midX - subject.bounds.midX, lastBounds.midY - subject.bounds.midY)
      associated = iou > 0.15 || distance <= params.maxCentroidJumpFraction
    } else {
      associated = true
    }
    if !associated && locked {
      mismatchFrames += 1
      if mismatchFrames <= max(1, params.maxMismatchFrames),
         (timestamp - lastSeen) * 1000 <= params.lostGraceMs {
        return TrackingResult(
          state: "locked", selectedBy: "temporal", acceptsDetectedSubject: false)
      }
    }
    consecutive = associated ? consecutive + 1 : 1
    if !associated { locked = false }
    mismatchFrames = 0
    lastBounds = subject.bounds
    lastSeen = timestamp
    if consecutive >= max(params.minLockFrames, params.minCandidateFrames) { locked = true }
    if locked {
      return TrackingResult(
        state: "locked",
        selectedBy: consecutive > params.minLockFrames ? "temporal" : subject.selectedBy,
        acceptsDetectedSubject: true)
    }
    return TrackingResult(
      state: consecutive >= params.minCandidateFrames ? "candidate" : "none",
      selectedBy: subject.selectedBy,
      acceptsDetectedSubject: true)
  }

  private func intersectionOverUnion(_ a: CGRect, _ b: CGRect) -> Double {
    let intersection = a.intersection(b)
    guard !intersection.isNull else { return 0 }
    let intersectionArea = intersection.width * intersection.height
    let union = a.width * a.height + b.width * b.height - intersectionArea
    return union > 0 ? Double(intersectionArea / union) : 0
  }
}
