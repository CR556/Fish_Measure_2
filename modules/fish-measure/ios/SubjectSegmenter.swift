import CoreML
import CoreVideo
import ImageIO
import Vision

struct BinaryMask: Sendable {
  let width: Int
  let height: Int
  var pixels: [UInt8]

  subscript(x: Int, y: Int) -> UInt8 {
    get { pixels[y * width + x] }
    set { pixels[y * width + x] = newValue }
  }

  var foregroundCount: Int { pixels.reduce(0) { $0 + ($1 == 0 ? 0 : 1) } }

  var normalizedBounds: CGRect {
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
      for x in 0..<width where self[x, y] != 0 {
        minX = min(minX, x); minY = min(minY, y)
        maxX = max(maxX, x); maxY = max(maxY, y)
      }
    }
    guard maxX >= minX, maxY >= minY else { return .zero }
    return CGRect(
      x: CGFloat(minX) / CGFloat(width),
      y: CGFloat(minY) / CGFloat(height),
      width: CGFloat(maxX - minX + 1) / CGFloat(width),
      height: CGFloat(maxY - minY + 1) / CGFloat(height))
  }

  static func from(
    _ buffer: CVPixelBuffer,
    maxDimension: Int = 320,
    outputEncoding: String = "probabilityMask",
    foregroundClassIndex: Int = 1,
    threshold: Double = 0.5
  ) -> BinaryMask? {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let sourceWidth = CVPixelBufferGetWidth(buffer)
    let sourceHeight = CVPixelBufferGetHeight(buffer)
    let scale = min(1, Double(maxDimension) / Double(max(sourceWidth, sourceHeight)))
    let width = max(1, Int(Double(sourceWidth) * scale))
    let height = max(1, Int(Double(sourceHeight) * scale))
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let format = CVPixelBufferGetPixelFormatType(buffer)
    var pixels = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
      let sourceY = min(sourceHeight - 1, Int(Double(y) / scale))
      for x in 0..<width {
        let sourceX = min(sourceWidth - 1, Int(Double(x) / scale))
        let foreground: Bool
        if format == kCVPixelFormatType_OneComponent32Float {
          let row = base.advanced(by: sourceY * stride).assumingMemoryBound(to: Float32.self)
          let value = Double(row[sourceX])
          foreground = outputEncoding == "classIndexMask"
            ? Int(value.rounded()) == foregroundClassIndex
            : value >= threshold
        } else {
          let row = base.advanced(by: sourceY * stride).assumingMemoryBound(to: UInt8.self)
          foreground = outputEncoding == "classIndexMask"
            ? Int(row[sourceX]) == foregroundClassIndex
            : Double(row[sourceX]) / 255 >= threshold
        }
        pixels[y * width + x] = foreground ? 1 : 0
      }
    }
    return BinaryMask(width: width, height: height, pixels: pixels)
  }

  func subtracting(_ other: BinaryMask, dilation: Int) -> BinaryMask {
    let person = other.resized(width: width, height: height).dilated(radius: dilation)
    var result = self
    for index in result.pixels.indices where person.pixels[index] != 0 {
      result.pixels[index] = 0
    }
    return result
  }

  func resized(width newWidth: Int, height newHeight: Int) -> BinaryMask {
    guard newWidth != width || newHeight != height else { return self }
    var output = BinaryMask(
      width: newWidth, height: newHeight,
      pixels: [UInt8](repeating: 0, count: newWidth * newHeight))
    for y in 0..<newHeight {
      for x in 0..<newWidth {
        output[x, y] = self[min(width - 1, x * width / newWidth), min(height - 1, y * height / newHeight)]
      }
    }
    return output
  }

  func dilated(radius: Int) -> BinaryMask {
    guard radius > 0 else { return self }
    var output = self
    for y in 0..<height {
      for x in 0..<width where self[x, y] != 0 {
        for yy in max(0, y - radius)...min(height - 1, y + radius) {
          for xx in max(0, x - radius)...min(width - 1, x + radius) { output[xx, yy] = 1 }
        }
      }
    }
    return output
  }

  func eroded(radius: Int) -> BinaryMask {
    guard radius > 0 else { return self }
    var output = self
    for y in 0..<height {
      for x in 0..<width where self[x, y] != 0 {
        var keep = true
        for yy in max(0, y - radius)...min(height - 1, y + radius) {
          for xx in max(0, x - radius)...min(width - 1, x + radius) where self[xx, yy] == 0 {
            keep = false
          }
        }
        if !keep { output[x, y] = 0 }
      }
    }
    return output
  }

  func closed(radius: Int) -> BinaryMask { dilated(radius: radius).eroded(radius: radius) }

  /// Vision returns masks in the oriented image space supplied to its request
  /// handler. ARKit display transforms, scene depth, intrinsics, and captured
  /// image sampling all use the camera sensor's native landscape coordinates.
  /// Canonicalizing here keeps every downstream consumer in sensor space.
  func convertedFromVisionToSensor(_ orientation: String) -> BinaryMask {
    switch orientation {
    case "left":
      var output = BinaryMask(
        width: height, height: width,
        pixels: [UInt8](repeating: 0, count: pixels.count))
      for sensorY in 0..<output.height {
        for sensorX in 0..<output.width {
          output[sensorX, sensorY] = self[sensorY, height - 1 - sensorX]
        }
      }
      return output
    case "up":
      return self
    case "down":
      var output = BinaryMask(
        width: width, height: height,
        pixels: [UInt8](repeating: 0, count: pixels.count))
      for sensorY in 0..<height {
        for sensorX in 0..<width {
          output[sensorX, sensorY] = self[width - 1 - sensorX, height - 1 - sensorY]
        }
      }
      return output
    default: // Vision `.right`: oriented (x,y) came from sensor (y,1-x).
      var output = BinaryMask(
        width: height, height: width,
        pixels: [UInt8](repeating: 0, count: pixels.count))
      for sensorY in 0..<output.height {
        for sensorX in 0..<output.width {
          output[sensorX, sensorY] = self[width - 1 - sensorY, sensorX]
        }
      }
      return output
    }
  }

  func largestComponent() -> (mask: BinaryMask, fraction: Double) {
    var visited = [Bool](repeating: false, count: pixels.count)
    var best: [Int] = []
    let total = max(1, foregroundCount)
    for start in pixels.indices where pixels[start] != 0 && !visited[start] {
      var queue = [start]
      visited[start] = true
      var component: [Int] = []
      var cursor = 0
      while cursor < queue.count {
        let index = queue[cursor]; cursor += 1
        component.append(index)
        let x = index % width, y = index / width
        for (xx, yy) in [(x-1,y), (x+1,y), (x,y-1), (x,y+1)]
        where xx >= 0 && yy >= 0 && xx < width && yy < height {
          let next = yy * width + xx
          if pixels[next] != 0 && !visited[next] {
            visited[next] = true
            queue.append(next)
          }
        }
      }
      if component.count > best.count { best = component }
    }
    var output = BinaryMask(width: width, height: height, pixels: [UInt8](repeating: 0, count: pixels.count))
    for index in best { output.pixels[index] = 1 }
    return (output, Double(best.count) / Double(total))
  }
}

struct SegmentedSubject: Sendable {
  let mask: BinaryMask
  let bounds: CGRect
  let areaFraction: Double
  let aspectRatio: Double
  let instanceCount: Int
  let selectedBy: String
}

final class SubjectSegmenter {
  private var runtimeVersion: String?
  private var runtimeVisionModel: VNCoreMLModel?

  func segment(
    image: CVPixelBuffer,
    params: SegmentationParams,
    tapHint: CGPoint?
  ) throws -> SegmentedSubject? {
    if let descriptor = params.runtimeModel {
      return try segmentWithRuntimeModel(image: image, params: params, descriptor: descriptor)
    }
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(
      cvPixelBuffer: image,
      orientation: Self.exifOrientation(params.visionOrientation),
      options: [:])
    try handler.perform([request])
    guard let observation = request.results?.first else { return nil }
    let instances = observation.allInstances
    guard !instances.isEmpty else { return nil }

    var personMask: BinaryMask?
    if params.personExclusion {
      let person = VNGeneratePersonSegmentationRequest()
      person.qualityLevel = .balanced
      person.outputPixelFormat = kCVPixelFormatType_OneComponent8
      try? handler.perform([person])
      if let buffer = person.results?.first?.pixelBuffer {
        personMask = BinaryMask.from(buffer)
      }
    }

    var best: (subject: SegmentedSubject, score: Double)?
    for instance in instances {
      let one = IndexSet(integer: instance)
      guard let buffer = try? observation.generateScaledMaskForImage(forInstances: one, from: handler),
            var mask = BinaryMask.from(buffer) else { continue }
      if let personMask {
        mask = mask.subtracting(personMask, dilation: max(0, params.personMaskDilationPx))
      }
      mask = mask.convertedFromVisionToSensor(params.visionOrientation)
      mask = mask.closed(radius: max(0, params.subjectClosingPx))
      let component = mask.largestComponent()
      guard component.fraction >= params.minComponentFraction else { continue }
      mask = component.mask
      let bounds = mask.normalizedBounds
      let area = Double(mask.foregroundCount) / Double(mask.width * mask.height)
      let aspect = Double(max(bounds.width, bounds.height) / max(0.0001, min(bounds.width, bounds.height)))
      guard area >= params.minAreaFraction, area <= params.maxAreaFraction,
            aspect >= params.minAspectRatio, aspect <= params.maxAspectRatio else { continue }

      let center = CGPoint(x: bounds.midX, y: bounds.midY)
      let inPriority = CGRect(
        x: CGFloat(params.priorityRegion.x), y: CGFloat(params.priorityRegion.y),
        width: CGFloat(params.priorityRegion.w), height: CGFloat(params.priorityRegion.h)).contains(center)
      let tapDistance = tapHint.map { Double(hypot(center.x - $0.x, center.y - $0.y)) }
      let selectedBy: String
      let score: Double
      if let tapDistance {
        selectedBy = "tapHint"
        score = 3 - min(2, tapDistance * 4) + area
      } else if inPriority {
        selectedBy = "priorityRegion"
        score = 2 + area
      } else {
        selectedBy = "area"
        score = area
      }
      let subject = SegmentedSubject(
        mask: mask, bounds: bounds, areaFraction: area, aspectRatio: aspect,
        instanceCount: instances.count, selectedBy: selectedBy)
      if best == nil || score > best!.score { best = (subject, score) }
    }
    return best?.subject
  }

  private func segmentWithRuntimeModel(
    image: CVPixelBuffer,
    params: SegmentationParams,
    descriptor: RuntimeModelParams
  ) throws -> SegmentedSubject? {
    let request = VNCoreMLRequest(model: try runtimeModel(descriptor))
    switch descriptor.resizePolicy {
    case "stretch": request.imageCropAndScaleOption = .scaleFill
    case "aspectFill": request.imageCropAndScaleOption = .centerCrop
    default: request.imageCropAndScaleOption = .scaleFit
    }
    let handler = VNImageRequestHandler(
      cvPixelBuffer: image,
      orientation: Self.exifOrientation(params.visionOrientation),
      options: [:])
    try handler.perform([request])
    let buffer: CVPixelBuffer?
    if let observation = request.results?.first as? VNPixelBufferObservation {
      buffer = observation.pixelBuffer
    } else if let observation = request.results?.first as? VNCoreMLFeatureValueObservation {
      buffer = observation.featureValue.imageBufferValue
    } else {
      buffer = nil
    }
    guard let buffer,
          var mask = BinaryMask.from(
            buffer,
            outputEncoding: descriptor.outputEncoding,
            foregroundClassIndex: descriptor.foregroundClassIndex,
            threshold: descriptor.threshold) else { return nil }
    if params.personExclusion {
      let person = VNGeneratePersonSegmentationRequest()
      person.qualityLevel = .balanced
      person.outputPixelFormat = kCVPixelFormatType_OneComponent8
      if (try? handler.perform([person])) != nil,
         let personBuffer = person.results?.first?.pixelBuffer,
         let personMask = BinaryMask.from(personBuffer) {
        mask = mask.subtracting(personMask, dilation: max(0, params.personMaskDilationPx))
      }
    }
    mask = mask.convertedFromVisionToSensor(params.visionOrientation)
    mask = mask.closed(radius: max(0, params.subjectClosingPx))
    let component = mask.largestComponent()
    guard component.fraction >= params.minComponentFraction else { return nil }
    mask = component.mask
    let bounds = mask.normalizedBounds
    let area = Double(mask.foregroundCount) / Double(mask.width * mask.height)
    let aspect = Double(max(bounds.width, bounds.height) / max(0.0001, min(bounds.width, bounds.height)))
    guard area >= params.minAreaFraction, area <= params.maxAreaFraction,
          aspect >= params.minAspectRatio, aspect <= params.maxAspectRatio else { return nil }
    return SegmentedSubject(
      mask: mask, bounds: bounds, areaFraction: area, aspectRatio: aspect,
      instanceCount: 1, selectedBy: "priorityRegion")
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

  private static func exifOrientation(_ value: String) -> CGImagePropertyOrientation {
    switch value {
    case "left": return .left
    case "up": return .up
    case "down": return .down
    default: return .right
    }
  }
}
