# 51 — LiquidRepDial

Component 51. Main has the fifty merged components through BoltStreak. Package, gallery, and README registrations are appended so a parallel diff can be union-merged.

## API

`LiquidRepDial(reps:goal:tilt:useDeviceMotion:onRep:)` is the control. `reps` is an `Int` binding. `goal` defaults to 20. `onRep` fires once when a tap or the VoiceOver action adds a rep. `tilt` is a `LiquidTilt` in radians (positive roll lowers the right side, positive pitch lowers the bottom). It is used when `useDeviceMotion` is false, so a preview can slosh the liquid without CoreMotion. On device, and when `useDeviceMotion` is true, roll and pitch come from CoreMotion behind `canImport` and an iOS check.

`LiquidRepDialDemo()` is the gallery page. It starts at 0 of 20.

`LiquidRepDialCore` is the pure-Swift model. `LiquidRepTuning` holds the shared numbers. `LiquidRepMath` maps a fill, a tilt and a meniscus onto the rim. `LiquidRepModel` runs the spring, the kick, the slosh, the wobble and Reduce Motion. `LiquidRepReel` is the scripted reel the canvas port plays.

## Constants

The values live on `LiquidRepTuning` and are copied in `webports/liquidrepdial-core.mjs`. `Tests/LiquidRepCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and the JS port match.

- Canvas 390 × 844. Dial 220 points, centred at (195, 430). Stroke 16, so the rim path has radius 102.
- Fill is reps ÷ goal, clamped to 0…1. Reps clamp to 0…999. Goal clamps to at least 1.
- Display spring k = 120, ζ = 0.6, which is bounce 0.4. A rising count adds 2.4 fill-units per second of velocity, so one rep runs past its mark. Frames clamp at 0.1 s, substeps at 1/240 s.
- Slosh spring k = 70, same ζ. The target is the shortest turn from the arc's centre toward the low side, weighted by sin(π · fill) so an empty or full ring does not move, and clamped to ±0.48 rad. Tilt magnitude (after the shared sine) saturates at 0.40.
- Meniscus envelope rises at 6/s with speed and falls at 2.4/s. Phase advances at ω = 16. The tip stretches by 0.018 of the circle and 7 points of radius at a wobble of +1.
- Reduce Motion crossfades the fill over 0.28 s. Slosh and meniscus stay at 0. The goal glow holds at 1.
- Goal glow otherwise breathes between 0.78 and 1 at ω = 5.2.

## Behaviour

A tap, `addRep`, or a binding that moves the count upward ticks once per rep. Crossing the goal adds one `goalReached` event. Setting the current count again emits nothing. Lowering the count does not tick. The drawn fill is the spring, so it overshoots the new fraction and settles. The blurred arc and the leading blob follow that trim.

Tilt stores a roll and pitch. The pool springs toward the low side. A level phone returns the arc to the top. Reduce Motion keeps the stored tilt but draws no slosh.

## Accessibility

VoiceOver sees one element, "Liquid rep dial". The value is the count and the goal, for example "12 of 20 reps". Increment, and the Add rep action, add one rep. Reduce Motion crossfades the rim and does not overshoot, slosh or wobble.

## Verification

Linux runs `LiquidRepCoreTests` (16 tests) as part of `swift test` (1707 tests, Swift 6.4.2), and `node webports/liquidrepdial-parity.mjs` (58 lines, exact match). `swiftc -parse` of the view and the gallery file was run on Linux. A second parse with the SwiftUI condition forced on checks the view syntax only. That parse does not typecheck SwiftUI. The Metal file is excluded from the Linux build. No Apple build or device run was done for this component. The SwiftUI code and `Resources/LiquidRepGlass.metal` need an Xcode build and a device check. The GIF and the contact sheet are the canvas port (`webports/liquidrepdial-capture.mjs`) at 390×844, using the JS core for every sample.
