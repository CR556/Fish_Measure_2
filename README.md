# Fish Measure 2

Fish Measure 2 is an iOS 17 app for LiDAR-equipped iPhones. It is designed to
measure a fish from nose to tail, preserve a measurement-linked photo, estimate
girth and weight, identify the species and visible bait, and maintain a private
on-device catch log.

> Status: active implementation. The Round 1 Swift pipeline compiles under
> Xcode 26/Swift 6.2; on-phone accuracy and thermal verification are pending.

## Product rules

- Curve-corrected 3D centerline length is the headline measurement; chord
  length is stored alongside it.
- Manual mode supports both a two-point chord and a drawn nose-to-tail spine.
- High-resolution photos are registration-checked against the measurement.
  Annotated exports fall back to the aligned measurement frame when needed.
- Catch data remains on the device unless the user explicitly shares an export
  or sends a catch photo for OpenAI identification.
- OpenAI identification uses a key entered by the user and stored in iOS secure
  storage. No API key belongs in this repository or in an app bundle.
- Measurements and calculated weights are estimates, not legally certified
  measurements.

## Stack

- Expo SDK 57, React Native 0.86, strict TypeScript
- Local Expo Module in Swift using ARKit, Vision, Core ML, and RealityKit
- React Navigation native stack and bottom tabs
- React Native Skia for per-frame overlays and share-card rendering
- SQLite plus per-catch files for local persistence
- GitHub Actions `macos-15` unsigned IPA builds for Windows development

## Development

```powershell
npm.cmd ci
npm.cmd run typecheck
npm.cmd start
```

Native Swift changes require a new unsigned IPA. TypeScript and visual changes
can normally be iterated through the installed Expo development client.

See [SETUP.md](./SETUP.md) and [docs/ARCHITECTURE.md](./docs/ARCHITECTURE.md).
