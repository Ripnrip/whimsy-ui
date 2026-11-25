# 51 — LiquidRepDial tools

Component 51, appended after BoltStreak.

## Core tests (Linux)

```sh
swift test --filter LiquidRepCoreTests
```

The parity fixture is `Tests/LiquidRepCoreTests/Fixtures/golden-trace.txt`. `WRITE_GOLDEN=1` rewrites it from the core.

## Bit-identical preview

```sh
node webports/liquidrepdial-parity.mjs
```

`webports/liquidrepdial-core.mjs` repeats the spring, the slosh, the meniscus and the scripted reel. `webports/liquidrepdial.html` draws that model. Tap the dial, or open `?drive=1` and call `renderAt(t)`.

## Capture

```sh
NODE_PATH=/tmp/node-tools/node_modules node webports/liquidrepdial-capture.mjs
```

The script imports `puppeteer-core`. Chrome is `/usr/local/bin/google-chrome`.

Writes `docs/liquidrepdial.gif` and `docs/liquidrepdial-stills.png` at a 390×844 phone frame. Copy both to the artifacts directory for delivery.

## Syntax, not an Apple run

```sh
swiftc -parse Sources/LiquidRepDial/LiquidRepDial.swift
swiftc -parse Sources/WhimsyGallery/WhimsyGallery.swift
```

On Linux `canImport(SwiftUI)` is false, so that parse does not typecheck the view. A second parse with the condition forced on checks the view syntax only. Neither is a SwiftUI runtime, a haptic, or a VoiceOver pass. The SwiftUI code and `Resources/LiquidRepGlass.metal` need an Xcode build and a device check.
