# Architecture

## Native build contract

`modules/fish-measure` owns the AR session and all accuracy-critical work. Its
public TypeScript contract is defined in `src/FishMeasure.types.ts`.

Native measurement stages:

1. Foreground-instance segmentation and optional person-mask subtraction.
2. Temporal subject association and fish-gate evaluation.
3. Contour tracing and PCA or skeleton centerline construction.
4. Confidence-filtered depth sampling, robust longitudinal depth fitting, and
   3D unprojection.
5. Curve/chord/girth measurement and stability-window evaluation.
6. Registration-checked high-resolution capture with an aligned-frame fallback
   for annotated exports.

Every event carries a native `frameId`. Capture payloads preserve the source
frame, 3D centerline, intrinsics, camera transform, and registration result.

## Manual measurement

Manual mode has two paths:

- Two points produce a chord measurement.
- A nose-to-tail drawn polyline is arc-length resampled, depth-lifted, and
  measured as a 3D curve.

This remains usable when foreground segmentation or fish classification fails.

## Runtime model escape hatch

Custom Core ML models require both a file path and a runtime descriptor. The
descriptor fixes feature names, tensor dimensions, normalization, output
encoding, class index, threshold, and resize policy so a new model can be loaded
without changing Swift.

## JavaScript data flow

- Per-frame contour, centerline, and measurement data go to external stores.
- One Skia canvas reads those stores without React state updates per frame.
- React state is reserved for navigation, capture review, settings, filters,
  and notifications.
- SQLite uses WAL, foreign keys, explicit migrations, and relative file paths.
- Captures are written to a staging directory and moved into the catch directory
  only when Keep succeeds.

## Cloud identification

OpenAI identification is a single post-capture request, never a live-frame
operation. A 1024-pixel compressed image and measured-length prior are sent for
strictly structured species suggestions and visible-bait classification. Failed
requests enter a foreground-only SQLite retry queue and never overwrite a
species chosen by the user.
