import ARKit
import CoreImage
import ExpoModulesCore
import ImageIO
import RealityKit
import UIKit

private struct PhotoFrame: @unchecked Sendable {
  let image: CVPixelBuffer
  let cameraTransform: simd_float4x4
  let intrinsics: simd_float3x3
  let imageResolution: CGSize
  let timestamp: TimeInterval

  init?(frame: ARFrame) {
    guard let copy = PixelBufferCopier.copy(frame.capturedImage) else { return nil }
    image = copy
    cameraTransform = frame.camera.transform
    intrinsics = frame.camera.intrinsics
    imageResolution = frame.camera.imageResolution
    timestamp = frame.timestamp
  }
}

private struct PixelSize {
  let width: Int
  let height: Int
}

final class CaptureService {
  private let queue = DispatchQueue(label: "fish.capture", qos: .utility)
  private let lock = NSLock()
  private var captureInProgress = false
  private let ciContext = CIContext(options: [.cacheIntermediates: false])
  private let segmenter = SubjectSegmenter()
  private let contourTracer = ContourTracer()
  private let depthLifter = DepthLifter()

  func captureAuto(
    session: SessionController,
    arView: ARView,
    snapshot: FishPipelineSnapshot,
    options: CaptureParams,
    orientation: UIInterfaceOrientation,
    promise: Promise
  ) {
    guard beginCapture(promise: promise) else { return }
    session.captureHighResolutionFrame { [weak self] frame, _ in
      let highResolution = frame.flatMap(PhotoFrame.init)
      self?.queue.async {
        self?.finishAuto(
          highResolution: highResolution,
          snapshot: snapshot,
          options: options,
          promise: promise)
      }
    }
  }

  func captureManual(
    session: SessionController,
    arView: ARView,
    measurement: ManualPathMeasurementNative,
    pathPoints: [CGPoint],
    viewSize: CGSize,
    options: CaptureParams,
    orientation: UIInterfaceOrientation,
    promise: Promise
  ) {
    guard beginCapture(promise: promise) else { return }
    session.captureHighResolutionFrame { [weak self] frame, _ in
      let highResolution = frame.flatMap(PhotoFrame.init)
      self?.queue.async {
        self?.finishManual(
          highResolution: highResolution,
          measurement: measurement,
          pathPoints: pathPoints,
          viewSize: viewSize,
          options: options,
          promise: promise)
      }
    }
  }

  private func beginCapture(promise: Promise) -> Bool {
    lock.lock(); defer { lock.unlock() }
    guard !captureInProgress else {
      promise.reject("capture_in_progress", "Wait for the current catch capture to finish.")
      return false
    }
    captureInProgress = true
    return true
  }

  private func endCapture() {
    lock.lock(); captureInProgress = false; lock.unlock()
  }

  private func finishAuto(
    highResolution: PhotoFrame?,
    snapshot: FishPipelineSnapshot,
    options: CaptureParams,
    promise: Promise
  ) {
    defer { endCapture() }
    do {
      let directory = try outputDirectory(options.outputDir)
      let captureId = UUID().uuidString
      let cleanURL = directory.appendingPathComponent("photo.jpg")
      let alignedURL = directory.appendingPathComponent("measurement-frame.jpg")
      let photoFrame = highResolution
      let photoSource = photoFrame == nil ? "videoFrame" : "highRes"
      if let photoFrame {
        try writeJPEG(photoFrame.image, to: cleanURL, quality: options.jpegQuality)
      } else {
        try writeJPEG(snapshot.packet.capturedImage, to: cleanURL, quality: options.jpegQuality)
      }

      var registrationStatus = "fallbackAlignedFrame"
      var registrationScore: Double? = nil
      var annotationURL = cleanURL
      var annotationSize = uprightSize(cleanURL)
      var contour = snapshot.contour.map(uprightPoint)
      var nose = uprightPoint(snapshot.measurement.centerlineImage.first ?? .zero)
      var tail = uprightPoint(snapshot.measurement.centerlineImage.last ?? .zero)

      if let photoFrame,
         let registered = registerHighResolution(frame: photoFrame, snapshot: snapshot),
         registered.score >= options.registrationMinScore {
        registrationStatus = "registered"
        registrationScore = registered.score
        contour = registered.contour
        nose = registered.nose
        tail = registered.tail
      } else if highResolution != nil {
        try writeJPEG(snapshot.packet.capturedImage, to: alignedURL, quality: options.jpegQuality)
        annotationURL = alignedURL
        annotationSize = uprightSize(alignedURL)
      } else {
        registrationStatus = "registered"
        registrationScore = 1
      }

      let plyURL = options.includePly ? directory.appendingPathComponent("cloud.ply") : nil
      if let plyURL { try writePLY(snapshot: snapshot, to: plyURL) }
      let maskURL = options.includeMaskPng ? directory.appendingPathComponent("mask.png") : nil
      if let maskURL { try writeMask(snapshot.subject.mask, to: maskURL) }
      let cleanSize = uprightSize(cleanURL)
      let photoPacket = photoFrame.map {
        photoIntrinsics($0.intrinsics, sourceResolution: $0.imageResolution, buffer: $0.image)
      } ?? photoIntrinsics(
        snapshot.packet.intrinsics,
        sourceResolution: snapshot.packet.imageResolution,
        buffer: snapshot.packet.capturedImage)
      let cameraTransform = photoFrame?.cameraTransform ?? snapshot.packet.cameraTransform

      resolve(promise, [
        "frameId": snapshot.frameId,
        "captureId": captureId,
        "photoPath": cleanURL.path,
        "photoWidth": cleanSize.width,
        "photoHeight": cleanSize.height,
        "photoSource": photoSource,
        "photoRegistration": [
          "status": registrationStatus,
          "score": bridgeValue(registrationScore),
          "annotatedPhotoPath": annotationURL.path,
          "annotatedPhotoWidth": annotationSize.width,
          "annotatedPhotoHeight": annotationSize.height,
        ],
        "curvedM": snapshot.curvedM,
        "chordM": snapshot.measurement.chordM,
        "girthM": bridgeValue(snapshot.girth?.meters),
        "girthMethod": bridgeValue(snapshot.girth?.method),
        "confidence": snapshot.confidence,
        "distanceM": snapshot.measurement.distanceM,
        "depthCoverage": snapshot.measurement.depthCoverage,
        "windowMedianCurvedM": snapshot.stability.medianCurvedM,
        "windowStdDevM": snapshot.stability.standardDeviationM,
        "windowFrames": snapshot.stability.frames,
        "contour": contour.flatMap { [Double($0.x), Double($0.y)] },
        "noseNorm": [Double(nose.x), Double(nose.y)],
        "tailNorm": [Double(tail.x), Double(tail.y)],
        "centerline3D": snapshot.measurement.centerlineWorld.flatMap {
          [Double($0.x), Double($0.y), Double($0.z)]
        },
        "cameraTransform": flatten(cameraTransform),
        "plyPath": bridgeValue(plyURL?.path),
        "maskPngPath": bridgeValue(maskURL?.path),
        "intrinsics": photoPacket,
        "timestampMs": snapshot.packet.epochTimestampMs,
        "frameTimestampS": snapshot.packet.timestamp,
      ])
    } catch {
      reject(promise, code: "capture_failed", message: error.localizedDescription)
    }
  }

  private func finishManual(
    highResolution: PhotoFrame?,
    measurement: ManualPathMeasurementNative,
    pathPoints: [CGPoint],
    viewSize: CGSize,
    options: CaptureParams,
    promise: Promise
  ) {
    defer { endCapture() }
    do {
      let directory = try outputDirectory(options.outputDir)
      let cleanURL = directory.appendingPathComponent("photo.jpg")
      let alignedURL = directory.appendingPathComponent("measurement-frame.jpg")
      if let highResolution {
        try writeJPEG(highResolution.image, to: cleanURL, quality: options.jpegQuality)
        try writeJPEG(measurement.packet.capturedImage, to: alignedURL, quality: options.jpegQuality)
      } else {
        try writeJPEG(measurement.packet.capturedImage, to: cleanURL, quality: options.jpegQuality)
      }
      let annotationURL = highResolution == nil ? cleanURL : alignedURL
      let cleanSize = uprightSize(cleanURL), annotationSize = uprightSize(annotationURL)
      let imagePath = measurement.imagePoints.map(uprightPoint)
      let intrinsics = highResolution.map {
        photoIntrinsics($0.intrinsics, sourceResolution: $0.imageResolution, buffer: $0.image)
      } ?? photoIntrinsics(
        measurement.packet.intrinsics,
        sourceResolution: measurement.packet.imageResolution,
        buffer: measurement.packet.capturedImage)
      let cameraTransform = highResolution?.cameraTransform ?? measurement.packet.cameraTransform
      resolve(promise, [
        "frameId": 0,
        "captureId": UUID().uuidString,
        "photoPath": cleanURL.path,
        "photoWidth": cleanSize.width,
        "photoHeight": cleanSize.height,
        "photoSource": highResolution == nil ? "videoFrame" : "highRes",
        "photoRegistration": [
          "status": highResolution == nil ? "registered" : "fallbackAlignedFrame",
          "score": highResolution == nil ? 1.0 as Any : NSNull(),
          "annotatedPhotoPath": annotationURL.path,
          "annotatedPhotoWidth": annotationSize.width,
          "annotatedPhotoHeight": annotationSize.height,
        ],
        "curvedM": measurement.measurement.curvedM,
        "chordM": measurement.measurement.chordM,
        "confidence": measurement.measurement.depthCoverage,
        "distanceM": measurement.measurement.distanceM,
        "depthCoverage": measurement.measurement.depthCoverage,
        "centerline3D": measurement.measurement.centerlineWorld.flatMap {
          [Double($0.x), Double($0.y), Double($0.z)]
        },
        "cameraTransform": flatten(cameraTransform),
        "plyPath": NSNull(),
        "maskPngPath": NSNull(),
        "intrinsics": intrinsics,
        "timestampMs": measurement.packet.epochTimestampMs,
        "frameTimestampS": measurement.packet.timestamp,
        "pathPointsNorm": imagePath.flatMap { [Double($0.x), Double($0.y)] },
        "pathKind": pathPoints.count == 2 ? "twoPointChord" : "drawnSpine",
      ])
    } catch {
      reject(promise, code: "capture_failed", message: error.localizedDescription)
    }
  }

  private func registerHighResolution(
    frame: PhotoFrame,
    snapshot: FishPipelineSnapshot
  ) -> (score: Double, contour: [CGPoint], nose: CGPoint, tail: CGPoint)? {
    guard let subject = try? segmenter.segment(
      image: frame.image,
      params: snapshot.segmentationParams,
      tapHint: nil) else { return nil }
    let projected = snapshot.measurement.centerlineWorld.compactMap {
      project(world: $0, frame: frame)
    }
    guard projected.count >= snapshot.measurement.centerlineWorld.count / 2 else { return nil }
    let inside = projected.filter { point in
      let x = min(subject.mask.width - 1, max(0, Int(point.x * CGFloat(subject.mask.width))))
      let y = min(subject.mask.height - 1, max(0, Int(point.y * CGFloat(subject.mask.height))))
      return subject.mask[x, y] != 0
    }.count
    let score = Double(inside) / Double(max(1, projected.count))
    let contour = contourTracer.trace(mask: subject.mask, maxPoints: 120).map(uprightPoint)
    guard let first = projected.first, let last = projected.last else { return nil }
    return (score, contour, uprightPoint(first), uprightPoint(last))
  }

  private func project(world: SIMD3<Float>, frame: PhotoFrame) -> CGPoint? {
    let local = simd_inverse(frame.cameraTransform) * SIMD4<Float>(world.x, world.y, world.z, 1)
    let depth = -local.z
    guard depth > 0.05 else { return nil }
    let u = frame.intrinsics.columns.0.x * local.x / depth + frame.intrinsics.columns.2.x
    let v = frame.intrinsics.columns.2.y - frame.intrinsics.columns.1.y * local.y / depth
    let point = CGPoint(
      x: CGFloat(u) / frame.imageResolution.width,
      y: CGFloat(v) / frame.imageResolution.height)
    return point.x.isFinite && point.y.isFinite ? point : nil
  }

  private func outputDirectory(_ path: String) throws -> URL {
    guard !path.isEmpty else {
      throw NSError(domain: "FishMeasure", code: 50, userInfo: [NSLocalizedDescriptionKey: "Capture output directory is empty."])
    }
    guard let url = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path) else {
      throw NSError(domain: "FishMeasure", code: 51, userInfo: [NSLocalizedDescriptionKey: "Capture output directory is invalid."])
    }
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func writeJPEG(_ buffer: CVPixelBuffer, to url: URL, quality: Double) throws {
    let oriented = CIImage(cvPixelBuffer: buffer).oriented(.right)
    guard let cgImage = ciContext.createCGImage(oriented, from: oriented.extent),
          let data = UIImage(cgImage: cgImage).jpegData(
            compressionQuality: CGFloat(min(max(quality, 0.4), 1))) else {
      throw NSError(domain: "FishMeasure", code: 52, userInfo: [NSLocalizedDescriptionKey: "Could not encode capture JPEG."])
    }
    try data.write(to: url, options: .atomic)
  }

  private func uprightSize(_ url: URL) -> PixelSize {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return PixelSize(width: 0, height: 0) }
    return PixelSize(
      width: properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
      height: properties[kCGImagePropertyPixelHeight] as? Int ?? 0)
  }

  private func uprightPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: 1 - point.y, y: point.x)
  }

  private func photoIntrinsics(
    _ intrinsics: simd_float3x3,
    sourceResolution: CGSize,
    buffer: CVPixelBuffer
  ) -> [String: Any] {
    let rawWidth = Double(CVPixelBufferGetWidth(buffer))
    let rawHeight = Double(CVPixelBufferGetHeight(buffer))
    let sx = rawWidth / max(1, Double(sourceResolution.width))
    let sy = rawHeight / max(1, Double(sourceResolution.height))
    let fx = Double(intrinsics.columns.0.x) * sx
    let fy = Double(intrinsics.columns.1.y) * sy
    let cx = Double(intrinsics.columns.2.x) * sx
    let cy = Double(intrinsics.columns.2.y) * sy
    return [
      "fx": fy, "fy": fx,
      "cx": rawHeight - cy, "cy": cx,
      "width": rawHeight, "height": rawWidth,
    ]
  }

  private func flatten(_ matrix: simd_float4x4) -> [Double] {
    (0..<4).flatMap { column in
      (0..<4).map { row in Double(matrix[column][row]) }
    }
  }

  private func bridgeValue<T>(_ value: T?) -> Any {
    value.map { $0 as Any } ?? NSNull()
  }

  private func writeMask(_ mask: BinaryMask, to url: URL) throws {
    let bytes = mask.pixels.map { $0 == 0 ? UInt8(0) : UInt8(255) }
    let data = Data(bytes)
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
            width: mask.width, height: mask.height,
            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: mask.width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent),
          let png = UIImage(cgImage: image).pngData() else {
      throw NSError(domain: "FishMeasure", code: 53, userInfo: [NSLocalizedDescriptionKey: "Could not encode mask PNG."])
    }
    try png.write(to: url, options: .atomic)
  }

  private func writePLY(snapshot: FishPipelineSnapshot, to url: URL) throws {
    let depth = snapshot.packet.depthMap
    let confidence = snapshot.packet.confidenceMap
    CVPixelBufferLockBaseAddress(depth, .readOnly)
    if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
    defer {
      if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
      CVPixelBufferUnlockBaseAddress(depth, .readOnly)
    }
    guard let base = CVPixelBufferGetBaseAddress(depth) else { return }
    let width = CVPixelBufferGetWidth(depth), height = CVPixelBufferGetHeight(depth)
    let stride = CVPixelBufferGetBytesPerRow(depth) / MemoryLayout<Float32>.size
    let depths = base.assumingMemoryBound(to: Float32.self)
    let confidenceBase: UnsafeMutablePointer<UInt8>?
    let confidenceStride: Int
    if let confidence, let base = CVPixelBufferGetBaseAddress(confidence) {
      confidenceBase = base.assumingMemoryBound(to: UInt8.self)
      confidenceStride = CVPixelBufferGetBytesPerRow(confidence)
    } else {
      confidenceBase = nil
      confidenceStride = 0
    }
    var vertices: [(SIMD3<Float>, SIMD3<UInt8>)] = []
    for y in 0..<snapshot.subject.mask.height {
      for x in 0..<snapshot.subject.mask.width where snapshot.subject.mask[x, y] != 0 {
        let normalized = CGPoint(
          x: (CGFloat(x) + 0.5) / CGFloat(snapshot.subject.mask.width),
          y: (CGFloat(y) + 0.5) / CGFloat(snapshot.subject.mask.height))
        let dx = min(width - 1, max(0, Int(normalized.x * CGFloat(width))))
        let dy = min(height - 1, max(0, Int(normalized.y * CGFloat(height))))
        if let confidenceBase,
           Int(confidenceBase[dy * confidenceStride + dx]) < snapshot.segmentationParams.minDepthConfidence { continue }
        let value = Double(depths[dy * stride + dx])
        guard value.isFinite && value > 0.05 && value < 10 else { continue }
        let world = depthLifter.unproject(normalizedPoint: normalized, depth: value, packet: snapshot.packet)
        vertices.append((world, sampleColor(snapshot.packet.capturedImage, normalized: normalized)))
      }
    }
    var data = Data("ply\nformat binary_little_endian 1.0\nelement vertex \(vertices.count)\nproperty float x\nproperty float y\nproperty float z\nproperty uchar red\nproperty uchar green\nproperty uchar blue\nend_header\n".utf8)
    for (point, color) in vertices {
      appendFloat(point.x, to: &data); appendFloat(point.y, to: &data); appendFloat(point.z, to: &data)
      data.append(color.x); data.append(color.y); data.append(color.z)
    }
    try data.write(to: url, options: .atomic)
  }

  private func sampleColor(_ buffer: CVPixelBuffer, normalized: CGPoint) -> SIMD3<UInt8> {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard CVPixelBufferGetPlaneCount(buffer) >= 2,
          let yBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 0),
          let uvBase = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else {
      return SIMD3(128, 128, 128)
    }
    let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
    let x = min(width - 1, max(0, Int(normalized.x * CGFloat(width))))
    let y = min(height - 1, max(0, Int(normalized.y * CGFloat(height))))
    let luma = Double(yBase.assumingMemoryBound(to: UInt8.self)[y * CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) + x])
    let uvWidth = CVPixelBufferGetWidthOfPlane(buffer, 1), uvHeight = CVPixelBufferGetHeightOfPlane(buffer, 1)
    let ux = min(uvWidth - 1, x / 2), uy = min(uvHeight - 1, y / 2)
    let uv = uvBase.assumingMemoryBound(to: UInt8.self)
    let offset = uy * CVPixelBufferGetBytesPerRowOfPlane(buffer, 1) + ux * 2
    let cb = Double(uv[offset]) - 128, cr = Double(uv[offset + 1]) - 128
    return SIMD3(
      UInt8(clamping: Int(luma + 1.402 * cr)),
      UInt8(clamping: Int(luma - 0.344136 * cb - 0.714136 * cr)),
      UInt8(clamping: Int(luma + 1.772 * cb)))
  }

  private func appendFloat(_ value: Float, to data: inout Data) {
    var bits = value.bitPattern.littleEndian
    Swift.withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
  }

  private func resolve(_ promise: Promise, _ value: [String: Any]) {
    DispatchQueue.main.async { promise.resolve(value) }
  }

  private func reject(_ promise: Promise, code: String, message: String) {
    DispatchQueue.main.async { promise.reject(code, message) }
  }
}
