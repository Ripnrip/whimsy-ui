# 35 — NeighborBouncePicker

Component 35 on main, after TiltScatterRestore (34). HoldToFanDock is 33.

A segmented control of 5, 6 or 7 ticks. Selecting one kicks every other tick upward and outward. The kick is delayed by distance and multiplied by 5/8 at each step. Landing plays a light haptic, and a second landing inside the gap is dropped. A new selection does not rewrite positions or velocities.

## API

```swift
NeighborBouncePicker(selection: $choice)
NeighborBouncePicker(selection: $choice, ticks: ticks)   // NeighborTick.fitted
NeighborBounceModel(count:selection:reduceMotion:)
model.select(_:) -> [NeighborBounceEvent]
model.step(_:) -> [NeighborBounceEvent]
model.setReduceMotion(_:)
model.pose(_:) -> NeighborBouncePose
```

`select` returns `.selected(index)` when the index changes and `.nudged(index)` when it does not. Both schedule a wave unless Reduce Motion is on. `step` returns `.launched(index)`, `.landed(index)` and, once, `.settled`.

Counts outside 5…7 clamp. An empty tick list is the six demo ticks. A shorter list is padded. A longer list keeps the first seven.

## Constants

Shared with `webports/neighborbounce-core.js`.

| Name | Value |
|---|---|
| Canvas | 404 × 196, rest y 128, tick 46, gap 10 |
| Track / pill | 376 × 78, pill 74 × 54 |
| Substep | 1/240 s, frame cap 24 substeps |
| Stagger | 12 substeps (50 ms) per step of distance |
| Kick | speed 1200, then ×3/5 outward and ×−4/5 up, ×0.625 per extra step |
| Offset spring | k = 100, ζ = 0.5 |
| Scale spring | k = 324, ζ = 0.75, selected scale 1.125 |
| Pill spring | k = 196, ζ = 0.75 |
| Landing | above 4 pt, downward speed over 48 pt/s, one per kick |
| Haptic gap | 18 substeps (75 ms) |
| Squash | stretch = clamp(−vy / 1600, −0.125, 0.125) |

Screen y grows downward, so “up” is a negative offset.

## Behaviour

- Kicks fire after `time` advances, then the springs integrate for that substep. Same-distance ticks fire in index order.
- A later `select` clears kicks that have not fired. Ticks already in the air keep their velocity, and the new wave adds to it when its own kicks come due.
- Reduce Motion snaps the pill, the scales and every offset, and emits no launch or landing. A selection haptic is the view’s job in that mode.
- Turning Reduce Motion on mid-wave seats the row. Turning it off does not invent a wave.
- Non-finite or non-positive `step` input is ignored.

## Accessibility

The control is a group, “Neighbor bounce picker”, value `spokenSelection` (“Gold, selected”). Each tick is a button with Selected or Not selected. Activate selects that tick.

## Verification

`NeighborBounceCoreTests` on Linux. `webports/neighborbounce-parity.mjs` compares `NeighborBounceTrace.parityLines()` to the JavaScript port. The SwiftUI file is behind `#if canImport(SwiftUI)` and is not executed on Linux.
