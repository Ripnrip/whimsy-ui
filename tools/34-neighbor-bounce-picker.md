# 34 — NeighborBouncePicker tools

Numbered against `main` (33 components, HoldToFanDock last). Do not treat the unmerged TiltScatterRestore pull request as already landed.

## Core tests (Linux)

```sh
swift test --filter NeighborBounceCoreTests
```

The parity test writes `/tmp/neighborbounce-swift-trace.txt`.

## Bit-identical preview

```sh
node webports/parity.mjs /tmp/neighborbounce-swift-trace.txt
```

`webports/neighborbounce-core.js` repeats the layout, the kick, the 1/240 s integrator and the scripted session. `webports/neighborbounce.html` draws that model. Open it to tap, or `?t=1.2` to render one instant.

## Capture

```sh
node webports/capture.mjs
```

Writes `docs/neighborbounce.gif` plus stills. Copy the gif and the contact sheet to the artifacts directory for delivery.

## Syntax, not an Apple run

```sh
swiftc -parse Sources/NeighborBouncePicker/NeighborBouncePicker.swift
swiftc -parse Sources/WhimsyGallery/WhimsyGallery.swift
```

On Linux `canImport(SwiftUI)` is false, so that parse does not typecheck the view. A second parse with the condition forced on checks the view syntax only. Neither is a SwiftUI runtime, a haptic, or a VoiceOver pass.
