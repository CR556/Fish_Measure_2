# Fish Measure 2 setup

## Requirements

- Windows development computer with Node.js 22
- LiDAR-equipped iPhone running iOS 17 or later
- GitHub account for the macOS build workflow
- Sideloadly and an Apple ID for the unsigned IPA path

## Local setup

```powershell
npm.cmd ci
npm.cmd run typecheck
npm.cmd start
```

The Debug IPA contains Expo Dev Client and connects to Metro on the local
network. Allow Node through Windows Firewall when prompted.

## Unsigned IPA

Run **iOS Unsigned IPA** from GitHub Actions:

- `Debug` creates the development client used for hot reload.
- `Release` embeds the JS bundle and runs without Metro.

Download the IPA artifact and sign/install it with Sideloadly. A free Apple ID
requires re-signing about every seven days, but the same IPA can be reused until
native code changes.

## OpenAI species identification

The user enters an OpenAI API key in Settings. The key is stored with
`expo-secure-store`; it must never be placed in source, an `.env` file committed
to git, Expo public configuration, or the IPA bundle. Catch photos are uploaded
only after the in-app disclosure is accepted and identification is enabled.

The exact Responses API model and schema must be rechecked against current
official OpenAI developer documentation before the cloud-ID milestone ships.
