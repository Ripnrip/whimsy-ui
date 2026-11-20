# 48 — GooMergeDrops tools

Component 48, appended after RotaryDialPasscode on this branch. Numbers 46 and 47 are other branches.

## Core tests (Linux)

```sh
swift test --filter GooMergeCoreTests
```

The parity fixture is `Tests/GooMergeCoreTests/Fixtures/golden-trace.txt`. `WRITE_GOLDEN=1` rewrites it from the core.

## Bit-identical preview

```sh
node webports/goomerge-parity.mjs
```

`webports/goomerge-core.mjs` repeats the ring, the smooth-min, the metaball, the 1/240 s spring and the scripted session. `webports/goomerge.html` draws that model. Drag a drop, or open `?drive=1` and call `renderAt(t)`.

## Capture

```sh
NODE_PATH=/tmp/node-tools/node_modules node webports/goomerge-capture.mjs
```

The script imports `puppeteer-core`. Chrome is `/usr/local/bin/google-chrome`.

Writes `docs/goomerge.gif` and `docs/goomerge-stills.png` at a 390×844 phone frame. Copy both to the artifacts directory for delivery.

## Syntax, not an Apple run

```sh
swiftc -parse Sources/GooMergeDrops/GooMergeDrops.swift
swiftc -parse Sources/WhimsyGallery/WhimsyGallery.swift
```

On Linux `canImport(SwiftUI)` is false, so that parse does not typecheck the view. A second parse with the condition forced on checks the view syntax only. Neither is a SwiftUI runtime, a haptic, or a VoiceOver pass. The SwiftUI code needs an Xcode build and a device check.
