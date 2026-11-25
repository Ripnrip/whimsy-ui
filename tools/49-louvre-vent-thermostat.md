# 49 — LouvreVentThermostat tools

Component 49, added after GooMergeDrops.

## Core tests (Linux)

```sh
swift test --filter LouvreVentCoreTests
```

The parity fixture is `Tests/LouvreVentCoreTests/Fixtures/golden-trace.txt`. `WRITE_GOLDEN=1` rewrites it from the core.

## Bit-identical preview

```sh
node webports/louvrevent-parity.mjs
```

`webports/louvrevent-core.mjs` repeats the angle map, the glow, the per-blade highlight, the 1/240 s spring and the scripted session. `webports/louvrevent.html` draws that model. Drag the vent, or open `?drive=1` and call `renderAt(t)`.

## Capture

```sh
NODE_PATH=/tmp/node-tools/node_modules node webports/louvrevent-capture.mjs
```

The script imports `puppeteer-core`. Chrome is `/usr/local/bin/google-chrome`.

Writes `docs/louvrevent.gif` and `docs/louvrevent-stills.png` at a 390×844 phone frame, and copies both to `/opt/cursor/artifacts`.

## Syntax, not an Apple run

```sh
swiftc -parse Sources/LouvreVentThermostat/LouvreVentThermostat.swift
swiftc -parse Sources/WhimsyGallery/WhimsyGallery.swift
```

On Linux `canImport(SwiftUI)` is false, so that parse does not typecheck the view. A second parse with the condition forced on checks the view syntax only. Neither is a SwiftUI runtime, a haptic, or a VoiceOver pass. The SwiftUI code needs an Xcode build and a device check.
