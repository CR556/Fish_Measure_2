import ARKit
import ExpoModulesCore
import ImageIO
import Photos

struct GPSParams: Record {
  @Field var lat: Double = 0
  @Field var lon: Double = 0
}

struct PointParams: Record {
  @Field var x: Double = 0
  @Field var y: Double = 0
}

struct SmoothingParams: Record {
  @Field var medianWindow: Int = 5
  @Field var emaAlpha: Double = 0.3
}

struct RuntimeModelParams: Record {
  @Field var path: String = ""
  @Field var version: String = ""
  @Field var inputName: String = ""
  @Field var outputName: String = ""
  @Field var inputWidth: Int = 256
  @Field var inputHeight: Int = 256
  @Field var normalization: String = "zeroToOne"
  @Field var outputEncoding: String = "probabilityMask"
  @Field var foregroundClassIndex: Int = 1
  @Field var threshold: Double = 0.5
  @Field var resizePolicy: String = "aspectFit"
}

struct RegionParams: Record {
  @Field var x: Double = 0.1
  @Field var y: Double = 0.3
  @Field var w: Double = 0.8
  @Field var h: Double = 0.4
}

struct SegmentationParams: Record {
  @Field var hz: Double = 10
  @Field var depthSource: String = "smoothed"
  @Field var visionOrientation: String = "right"
  @Field var minDepthConfidence: Int = 1
  @Field var personExclusion: Bool = true
  @Field var personMaskDilationPx: Int = 2
  @Field var subjectClosingPx: Int = 2
  @Field var minComponentFraction: Double = 0.5
  @Field var minAreaFraction: Double = 0.02
  @Field var maxAreaFraction: Double = 0.6
  @Field var minAspectRatio: Double = 1.8
  @Field var maxAspectRatio: Double = 10
  @Field var priorityRegion: RegionParams = RegionParams()
  @Field var runtimeModel: RuntimeModelParams?
}

struct ClassifierParams: Record {
  @Field var enabled: Bool = true
  @Field var hz: Double = 2
  @Field var acceptLabels: [String] = []
  @Field var minConfidence: Double = 0.15
  @Field var vetoLabels: [String] = []
  @Field var runtimeModel: RuntimeModelParams?
  @Field var requiredForAutoCapture: Bool = true
}

struct TrackingParams: Record {
  @Field var iouWeight: Double = 0.55
  @Field var centroidWeight: Double = 0.25
  @Field var scoreWeight: Double = 0.2
  @Field var minCandidateFrames: Int = 2
  @Field var minLockFrames: Int = 4
  @Field var lostGraceMs: Double = 350
  @Field var maxCentroidJumpFraction: Double = 0.2
  @Field var maxLengthJumpFraction: Double = 0.15
  @Field var tapHintTtlMs: Double = 3000
  @Field var relockCooldownMs: Double = 500
}

struct CenterlineParams: Record {
  @Field var algorithm: String = "pca"
  @Field var bins: Int = 48
  @Field var depthSampleRadiusPx: Int = 2
  @Field var depthFitDegree: Int = 3
  @Field var outlierRejectSigma: Double = 2.5
  @Field var maxGapBinFraction: Double = 0.25
  @Field var minValidBinFraction: Double = 0.5
}

struct GirthParams: Record {
  @Field var aspect: Double = 0.5
  @Field var useDepthBulge: Bool = true
  @Field var calibration: Double = 1
}

struct StabilityParams: Record {
  @Field var windowMs: Double = 750
  @Field var maxDeltaCm: Double = 0.5
  @Field var maxDeltaFraction: Double = 0.015
  @Field var minDistanceM: Double = 0.3
  @Field var maxDistanceM: Double = 2.5
  @Field var minDepthCoverage: Double = 0.7
}

struct OverlayParams: Record {
  @Field var contourMaxPoints: Int = 120
  @Field var emitCenterline: Bool = true
}

struct CaptureParams: Record {
  @Field var outputDir: String = ""
  @Field var includePly: Bool = false
  @Field var includeMaskPng: Bool = false
  @Field var jpegQuality: Double = 0.9
  @Field var registrationMinScore: Double = 0.6
}

public class FishMeasureModule: Module {
  public func definition() -> ModuleDefinition {
    Name("FishMeasure")

    Function("isLidarSupported") { () -> Bool in
      ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        && ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    AsyncFunction("saveImageToPhotos") {
      (path: String, userComment: String, imageDescription: String, gps: GPSParams?, promise: Promise) in
      Self.saveImageToPhotos(
        path: path,
        userComment: userComment,
        imageDescription: imageDescription,
        gps: gps,
        promise: promise)
    }

    View(FishARView.self) {
      Events(
        "onSubject", "onFishMeasurement", "onDistance", "onTrackingState",
        "onProjectedPoints", "onError", "onDebugInfo")

      Prop("mode") { (view: FishARView, value: String) in view.setMode(value) }
      Prop("updateHz") { (view: FishARView, value: Double) in view.setUpdateHz(value) }
      Prop("smoothing") { (view: FishARView, value: SmoothingParams) in view.setSmoothing(value) }
      Prop("showNativeMarkers") { (view: FishARView, value: Bool) in view.setShowMarkers(value) }
      Prop("enableSceneReconstruction") { (view: FishARView, value: Bool) in
        view.setSceneReconstruction(value)
      }
      Prop("enableHighResCapture") { (view: FishARView, value: Bool) in
        view.setHighResolutionCapture(value)
      }
      Prop("segmentation") { (view: FishARView, value: SegmentationParams) in
        view.setSegmentation(value)
      }
      Prop("classifier") { (view: FishARView, value: ClassifierParams) in
        view.setClassifier(value)
      }
      Prop("tracking") { (view: FishARView, value: TrackingParams) in view.setTracking(value) }
      Prop("centerline") { (view: FishARView, value: CenterlineParams) in
        view.setCenterline(value)
      }
      Prop("girth") { (view: FishARView, value: GirthParams) in view.setGirth(value) }
      Prop("stability") { (view: FishARView, value: StabilityParams) in view.setStability(value) }
      Prop("overlay") { (view: FishARView, value: OverlayParams) in view.setOverlay(value) }
      Prop("debugMode") { (view: FishARView, value: Bool) in view.setDebugMode(value) }
      Prop("debugDepthOverlay") { (view: FishARView, value: Bool) in
        view.setDebugDepthOverlay(value)
      }

      AsyncFunction("setTapHint") { (view: FishARView, x: Double, y: Double) in
        view.setTapHint(x: x, y: y)
      }.runOnQueue(.main)

      AsyncFunction("clearSubject") { (view: FishARView) in view.clearSubject() }
        .runOnQueue(.main)

      AsyncFunction("captureAutoCatch") {
        (view: FishARView, options: CaptureParams, promise: Promise) in
        view.captureAutoCatch(options: options, promise: promise)
      }.runOnQueue(.main)

      AsyncFunction("measureAtPoint") {
        (view: FishARView, x: Double, y: Double) -> [String: Any]? in
        view.measureAtPoint(x: x, y: y)
      }.runOnQueue(.main)

      AsyncFunction("measureManualPath") {
        (view: FishARView, points: [PointParams], samples: Int?) async -> [String: Any]? in
        await view.measureManualPath(points: points, samples: samples)
      }

      AsyncFunction("captureManualCatch") {
        (view: FishARView, points: [PointParams], options: CaptureParams, promise: Promise) in
        view.captureManualCatch(points: points, options: options, promise: promise)
      }.runOnQueue(.main)

      AsyncFunction("clearAnchors") { (view: FishARView) in view.clearAnchors() }
        .runOnQueue(.main)
      AsyncFunction("removeAnchor") { (view: FishARView, id: String) in view.removeAnchor(id: id) }
        .runOnQueue(.main)
      AsyncFunction("snapshotCamera") { (view: FishARView, promise: Promise) in
        view.snapshotCamera(promise: promise)
      }.runOnQueue(.main)
    }
  }

  private static func saveImageToPhotos(
    path: String,
    userComment: String,
    imageDescription: String,
    gps: GPSParams?,
    promise: Promise
  ) {
    let sourceURL = path.hasPrefix("file://") ? URL(string: path) : URL(fileURLWithPath: path)
    guard let sourceURL,
          let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let sourceType = CGImageSourceGetType(source) else {
      promise.reject("capture_read_failed", "Could not read the captured image.")
      return
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("jpg")
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, sourceType, 1, nil)
    else {
      promise.reject("capture_write_failed", "Could not create the metadata image.")
      return
    }

    var properties =
      (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
    exif[kCGImagePropertyExifUserComment] = userComment
    properties[kCGImagePropertyExifDictionary] = exif
    var tiff = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
    tiff[kCGImagePropertyTIFFImageDescription] = imageDescription
    properties[kCGImagePropertyTIFFDictionary] = tiff
    if let gps {
      properties[kCGImagePropertyGPSDictionary] = [
        kCGImagePropertyGPSLatitude: abs(gps.lat),
        kCGImagePropertyGPSLatitudeRef: gps.lat >= 0 ? "N" : "S",
        kCGImagePropertyGPSLongitude: abs(gps.lon),
        kCGImagePropertyGPSLongitudeRef: gps.lon >= 0 ? "E" : "W",
        kCGImagePropertyGPSVersion: [2, 3, 0, 0],
      ]
    }

    CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      promise.reject("capture_write_failed", "Could not write image metadata.")
      return
    }

    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        try? FileManager.default.removeItem(at: outputURL)
        promise.reject("photos_permission_denied", "Allow photo additions in Settings to save exports.")
        return
      }
      PHPhotoLibrary.shared().performChanges({
        PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: outputURL, options: nil)
      }) { success, error in
        try? FileManager.default.removeItem(at: outputURL)
        if success {
          promise.resolve(nil)
        } else {
          promise.reject("photos_save_failed", error?.localizedDescription ?? "Unknown Photos error.")
        }
      }
    }
  }
}
