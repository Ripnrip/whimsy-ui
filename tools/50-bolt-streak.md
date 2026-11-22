# 50 — BoltStreak tools

Component 50, appended after GooMergeDrops on this branch. Number 49 is the open Louvre pull request.

## Core tests (Linux)

```sh
swift test --filter BoltStreakCoreTests
```

The parity fixture is `Tests/BoltStreakCoreTests/Fixtures/golden-trace.txt`. `WRITE_GOLDEN=1` rewrites it from the core.

## Bit-identical preview

```sh
node webports/boltstreak-parity.mjs
```

`webports/boltstreak-core.mjs` repeats the centreline, the arc-length head, the smoothstep ignition and the scripted reel. `webports/boltstreak.html` draws that model. Tap today's bolt, or open `?drive=1` and call `renderAt(t)`.

## Capture

```sh
NODE_PATH=/tmp/node-tools/node_modules node webports/boltstreak-capture.mjs
```

The script imports `puppeteer-core`. Chrome is `/usr/local/bin/google-chrome`.

Writes `docs/boltstreak.gif` and `docs/boltstreak-stills.png` at a 390×844 phone frame. Copy both to the artifacts directory for delivery.

## Syntax, not an Apple run

```sh
swiftc -parse Sources/BoltStreak/BoltStreak.swift
swiftc -parse Sources/WhimsyGallery/WhimsyGallery.swift
```

On Linux `canImport(SwiftUI)` is false, so that parse does not typecheck the view. A second parse with the condition forced on checks the view syntax only. Neither is a SwiftUI runtime, a haptic, or a VoiceOver pass. The SwiftUI code needs an Xcode build and a device check.
