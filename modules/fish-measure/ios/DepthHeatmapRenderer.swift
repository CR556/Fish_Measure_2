import CoreGraphics
import CoreVideo
import Foundation
import QuartzCore
import UIKit

/// Colorizes the LiDAR depth map (256×192 Float32 meters) into a CALayer
/// overlaid on the camera view. CPU LUT mapping — ~49k pixels/frame is
/// sub-millisecond, done off-main with frame dropping when busy.
final class DepthHeatmapRenderer {
  let layer = CALayer()

  /// Distances mapped across the color ramp; JS keeps these in sync with the
  /// on-screen legend.
  var minMeters: Float = 0.3
  var maxMeters: Float = 5.0
  /// Degrees to rotate the sensor-orientation depth map for display.
  /// JS-tunable so an orientation surprise never costs a native rebuild.
  var rotationDegrees: Int = 90

  /// Auto mode: the far end of the ramp tracks the furthest visible object
  /// (99th-percentile depth, smoothed) instead of `maxMeters`.
  var autoRange = false {
    didSet {
      if autoRange != oldValue {
        smoothedAutoMax = -1
        lastReportedMax = -1
      }
    }
  }
  /// Invoked on the main queue when the smoothed auto max moves meaningfully.
  var onAutoMaxChanged: ((Float) -> Void)?

  private var smoothedAutoMax: Float = -1
  private var lastReportedMax: Float = -1

  private var lut: [UInt8] = [] // 256 RGBA entries
  private let queue = DispatchQueue(label: "lidarmeasure.heatmap")
  private var busy = false

  init() {
    layer.contentsGravity = .resizeAspectFill
    layer.opacity = 0.65
    layer.isHidden = true
    setColors(["#ff3b30", "#ff9f0a", "#ffd60a", "#30d158", "#64d2ff", "#0a84ff"])
  }

  func setOpacity(_ value: Double) {
    layer.opacity = Float(min(max(value, 0), 1))
  }

  func setColors(_ hexStops: [String]) {
    let stops = hexStops.compactMap(Self.parseHex)
    guard stops.count >= 2 else { return }
    var table = [UInt8](repeating: 0, count: 256 * 4)
    let segments = stops.count - 1
    for i in 0..<256 {
      let t = Float(i) / 255.0
      let scaled = t * Float(segments)
      let index = min(Int(scaled), segments - 1)
      let frac = scaled - Float(index)
      let a = stops[index]
      let b = stops[index + 1]
      table[i * 4 + 0] = UInt8((a.r + (b.r - a.r) * frac) * 255)
      table[i * 4 + 1] = UInt8((a.g + (b.g - a.g) * frac) * 255)
      table[i * 4 + 2] = UInt8((a.b + (b.b - a.b) * frac) * 255)
      table[i * 4 + 3] = 255
    }
    queue.async { [weak self] in self?.lut = table }
  }

  private static func parseHex(_ hex: String) -> (r: Float, g: Float, b: Float)? {
    var cleaned = hex.trimmingCharacters(in: .whitespaces)
    if cleaned.hasPrefix("#") { cleaned.removeFirst() }
    guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
    return (
      r: Float((value >> 16) & 0xFF) / 255.0,
      g: Float((value >> 8) & 0xFF) / 255.0,
      b: Float(value & 0xFF) / 255.0
    )
  }

  /// Called from the ARSession frame callback (main thread) at the event
  /// rate. Drops frames if colorization hasn't finished.
  func update(depthMap: CVPixelBuffer) {
    guard !busy else { return }
    busy = true
    // Retaining the pixel buffer across the queue hop is safe; ARKit pools
    // them and this holds one for <1 ms.
    queue.async { [weak self] in
      guard let self else { return }
      let result = self.colorize(depthMap: depthMap)
      DispatchQueue.main.async {
        if let result {
          self.layer.contents = result.image
          if self.autoRange, abs(result.effectiveMax - self.lastReportedMax) > 0.05 {
            self.lastReportedMax = result.effectiveMax
            self.onAutoMaxChanged?(result.effectiveMax)
          }
        }
        self.busy = false
      }
    }
  }

  private func colorize(depthMap: CVPixelBuffer) -> (image: CGImage, effectiveMax: Float)? {
    guard !lut.isEmpty else { return nil }
    CVPixelBufferLockBaseAddress(depthMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

    let srcW = CVPixelBufferGetWidth(depthMap)
    let srcH = CVPixelBufferGetHeight(depthMap)
    guard srcW > 0, srcH > 0, let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
    let rowFloats = CVPixelBufferGetBytesPerRow(depthMap) / MemoryLayout<Float32>.size
    let src = base.assumingMemoryBound(to: Float32.self)

    let rotation = ((rotationDegrees % 360) + 360) % 360
    let swap = rotation == 90 || rotation == 270
    let dstW = swap ? srcH : srcW
    let dstH = swap ? srcW : srcH

    // Auto range: 99th-percentile depth via histogram (robust to hot pixels),
    // EMA-smoothed so the legend doesn't flicker frame to frame.
    var effectiveMax = maxMeters
    if autoRange {
      let binCount = 128
      let histogramCeiling: Float = 10.0
      var histogram = [Int](repeating: 0, count: binCount)
      var validCount = 0
      for sy in 0..<srcH {
        for sx in 0..<srcW {
          let depth = src[sy * rowFloats + sx]
          guard depth.isFinite, depth > 0 else { continue }
          let bin = min(binCount - 1, Int(depth / histogramCeiling * Float(binCount)))
          histogram[bin] += 1
          validCount += 1
        }
      }
      if validCount > 100 {
        let cutoff = validCount / 100 // drop the farthest 1%
        var seen = 0
        var p99 = histogramCeiling
        for bin in stride(from: binCount - 1, through: 0, by: -1) {
          seen += histogram[bin]
          if seen >= cutoff {
            p99 = Float(bin + 1) / Float(binCount) * histogramCeiling
            break
          }
        }
        smoothedAutoMax = smoothedAutoMax < 0 ? p99 : smoothedAutoMax + 0.25 * (p99 - smoothedAutoMax)
      }
      if smoothedAutoMax > 0 {
        effectiveMax = max(smoothedAutoMax, minMeters + 0.5)
      }
    }

    var pixels = [UInt8](repeating: 0, count: dstW * dstH * 4)
    let range = max(effectiveMax - minMeters, 0.001)

    for y in 0..<dstH {
      for x in 0..<dstW {
        let sx: Int
        let sy: Int
        switch rotation {
        case 90: // 90° CW: sensor-landscape → portrait
          sx = y
          sy = srcH - 1 - x
        case 180:
          sx = srcW - 1 - x
          sy = srcH - 1 - y
        case 270:
          sx = srcW - 1 - y
          sy = x
        default:
          sx = x
          sy = y
        }
        let depth = src[sy * rowFloats + sx]
        guard depth.isFinite, depth > 0 else { continue } // stays transparent
        let t = min(max((depth - minMeters) / range, 0), 1)
        let lutIndex = Int(t * 255) * 4
        let dstIndex = (y * dstW + x) * 4
        pixels[dstIndex + 0] = lut[lutIndex + 0]
        pixels[dstIndex + 1] = lut[lutIndex + 1]
        pixels[dstIndex + 2] = lut[lutIndex + 2]
        pixels[dstIndex + 3] = lut[lutIndex + 3]
      }
    }

    let data = Data(pixels)
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    guard let image = CGImage(
      width: dstW,
      height: dstH,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: dstW * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    ) else { return nil }
    return (image, effectiveMax)
  }
}
