import ARKit
import AVFoundation
import ExpoModulesCore
import ImageIO
import Photos

struct SmoothingParams: Record {
  @Field var medianWindow: Int = 5
  @Field var emaAlpha: Double = 0.3
}

struct HeatmapRange: Record {
  @Field var min: Double = 0.3
  @Field var max: Double = 5.0
}

public class LidarMeasureModule: Module {
  public func definition() -> ModuleDefinition {
    Name("LidarMeasure")

    // Pre-render capability gates.
    Function("isLidarSupported") { () -> Bool in
      ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    Function("isTrueDepthSupported") { () -> Bool in
      AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) != nil
    }

    /// Embeds measurement metadata into the image's EXIF (UserComment) and
    /// TIFF (ImageDescription) fields, then saves it to the camera roll.
    AsyncFunction("saveImageToPhotos") { (path: String, userComment: String, imageDescription: String, promise: Promise) in
      let sourceURL: URL
      if path.hasPrefix("file://"), let parsed = URL(string: path) {
        sourceURL = parsed
      } else {
        sourceURL = URL(fileURLWithPath: path)
      }

      guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
            let sourceType = CGImageSourceGetType(source) else {
        promise.reject("capture_read_failed", "Could not read the captured image.")
        return
      }

      let outputURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("jpg")
      guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, sourceType, 1, nil) else {
        promise.reject("capture_write_failed", "Could not create the output image.")
        return
      }

      var properties = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
      var exif = (properties[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
      exif[kCGImagePropertyExifUserComment] = userComment
      properties[kCGImagePropertyExifDictionary] = exif
      var tiff = (properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]
      tiff[kCGImagePropertyTIFFImageDescription] = imageDescription
      properties[kCGImagePropertyTIFFDictionary] = tiff

      CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
      guard CGImageDestinationFinalize(destination) else {
        promise.reject("capture_write_failed", "Could not write image metadata.")
        return
      }

      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        guard status == .authorized || status == .limited else {
          promise.reject("photos_permission_denied", "Allow photo additions in Settings to save captures.")
          return
        }
        PHPhotoLibrary.shared().performChanges({
          PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: outputURL, options: nil)
        }) { success, error in
          if success {
            promise.resolve(nil)
          } else {
            promise.reject("photos_save_failed", error?.localizedDescription ?? "Unknown Photos error.")
          }
        }
      }
    }

    View(LidarARView.self) {
      Events("onDistance", "onTrackingState", "onError", "onProjectedPoints", "onHeatmapRange")

      Prop("mode") { (view: LidarARView, mode: String) in
        view.setMode(mode)
      }

      Prop("updateHz") { (view: LidarARView, hz: Double) in
        view.setUpdateHz(hz)
      }

      Prop("smoothing") { (view: LidarARView, params: SmoothingParams) in
        view.setSmoothing(medianWindow: params.medianWindow, emaAlpha: params.emaAlpha)
      }

      Prop("showNativeMarkers") { (view: LidarARView, show: Bool) in
        view.setShowMarkers(show)
      }

      Prop("heatmapRange") { (view: LidarARView, range: HeatmapRange) in
        view.setHeatmapRange(min: range.min, max: range.max)
      }

      Prop("heatmapOpacity") { (view: LidarARView, opacity: Double) in
        view.setHeatmapOpacity(opacity)
      }

      Prop("heatmapColors") { (view: LidarARView, colors: [String]) in
        view.setHeatmapColors(colors)
      }

      Prop("heatmapRotation") { (view: LidarARView, degrees: Int) in
        view.setHeatmapRotation(degrees)
      }

      Prop("heatmapAutoRange") { (view: LidarARView, enabled: Bool) in
        view.setHeatmapAutoRange(enabled)
      }

      AsyncFunction("measureAtPoint") { (view: LidarARView, x: Double, y: Double) -> [String: Any]? in
        view.measureAtPoint(x: x, y: y)
      }.runOnQueue(.main)

      AsyncFunction("clearAnchors") { (view: LidarARView) in
        view.clearAnchors()
      }.runOnQueue(.main)

      // Fallback capture path: RealityKit's own snapshot of the AR view
      // (camera + markers, no JS overlay). Used if view-shot renders the
      // Metal-backed camera view black.
      AsyncFunction("snapshotCamera") { (view: LidarARView, promise: Promise) in
        view.snapshotCamera(promise: promise)
      }.runOnQueue(.main)

      AsyncFunction("removeAnchor") { (view: LidarARView, anchorId: String) in
        view.removeAnchor(id: anchorId)
      }.runOnQueue(.main)
    }
  }
}
