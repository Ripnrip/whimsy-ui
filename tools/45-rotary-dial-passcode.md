# 45 — RotaryDialPasscode tools

Component 45, appended after PinataReward on this branch. Numbers 41–44 are other branches.

## Core tests (Linux)

```sh
swift test --filter RotaryDialCoreTests
```

The parity fixture is `Tests/RotaryDialCoreTests/Fixtures/golden-trace.txt`. `WRITE_GOLDEN=1` rewrites it from the core.

## Bit-identical preview

```sh
node webports/rotarydial-parity.mjs
```

`webports/rotarydial-core.mjs` repeats the angles, the stop, the 1/240 s spring and the scripted session. `webports/rotarydial.html` draws that model. Drag a hole, or open `?drive=1` and call `renderAt(t)`.

## Capture

```sh
node webports/rotarydial-capture.mjs
```

The script imports `puppeteer-core` from the repo's `node_modules`, or from `/tmp/node-tools` when that checkout is absent. Chrome is `/usr/bin/google-chrome`.

Writes `docs/rotarydial.gif` and `docs/rotarydial-stills.png` at a 390×844 phone frame. Copy both to the artifacts directory for delivery.

## Syntax, not an Apple run

```sh
swiftc -parse Sources/RotaryDialPasscode/RotaryDialPasscode.swift
swiftc -parse Sources/WhimsyGallery/WhimsyGallery.swift
```

On Linux `canImport(SwiftUI)` is false, so that parse does not typecheck the view. A second parse with the condition forced on checks the view syntax only. Neither is a SwiftUI runtime, a haptic, or a VoiceOver pass. The SwiftUI code needs an Xcode build and a device check.
