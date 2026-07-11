import CoreML
import ImageIO
import Vision

struct NativeClassifierLabel: Sendable {
  let label: String
  let confidence: Double
}

struct ClassifierResult: Sendable {
  let labels: [NativeClassifierLabel]
  let fishScore: Double
  let gatePassed: Bool
}

final class FishClassifier {
  private var lastRunTimestamp: TimeInterval = -Double.greatestFiniteMagnitude
  private var sticky = ClassifierResult(labels: [], fishScore: 0, gatePassed: false)
  private var runtimeVersion: String?
  private var runtimeVisionModel: VNCoreMLModel?

  func classify(
    image: CVPixelBuffer,
    timestamp: TimeInterval,
    params: ClassifierParams
  ) throws -> ClassifierResult {
    guard params.enabled else {
      return ClassifierResult(labels: [], fishScore: 1, gatePassed: true)
    }
    if timestamp - lastRunTimestamp < 1 / max(0.1, params.hz) { return sticky }
    lastRunTimestamp = timestamp
    let request: VNRequest
    if let descriptor = params.runtimeModel {
      request = VNCoreMLRequest(model: try runtimeModel(descriptor))
    } else {
      request = VNClassifyImageRequest()
    }
    let handler = VNImageRequestHandler(cvPixelBuffer: image, orientation: .right, options: [:])
    try handler.perform([request])
    let observations = (request.results as? [VNClassificationObservation]) ?? []
    let labels = observations.prefix(5).map {
      NativeClassifierLabel(label: $0.identifier, confidence: Double($0.confidence))
    }
    let accepts = params.acceptLabels.map { $0.lowercased() }
    let vetoes = params.vetoLabels.map { $0.lowercased() }
    let fishScore = labels.filter { item in
      accepts.contains { item.label.lowercased().contains($0) }
    }.map(\.confidence).max() ?? 0
    let vetoed = labels.contains { item in
      item.confidence >= params.minConfidence && vetoes.contains { item.label.lowercased().contains($0) }
    }
    sticky = ClassifierResult(
      labels: labels,
      fishScore: fishScore,
      gatePassed: !vetoed && fishScore >= params.minConfidence)
    return sticky
  }

  private func runtimeModel(_ descriptor: RuntimeModelParams) throws -> VNCoreMLModel {
    if runtimeVersion == descriptor.version, let runtimeVisionModel { return runtimeVisionModel }
    let source = descriptor.path.hasPrefix("file://")
      ? URL(string: descriptor.path)!
      : URL(fileURLWithPath: descriptor.path)
    let compiledURL: URL
    if source.pathExtension == "mlmodelc" {
      compiledURL = source
    } else {
      compiledURL = try MLModel.compileModel(at: source)
    }
    let model = try MLModel(contentsOf: compiledURL)
    let visionModel = try VNCoreMLModel(for: model)
    runtimeVersion = descriptor.version
    runtimeVisionModel = visionModel
    return visionModel
  }
}
