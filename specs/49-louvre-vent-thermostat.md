# 49 — LouvreVentThermostat

Component 49. Main has the forty-eight merged components through GooMergeDrops.

## API

`LouvreVentThermostat(temperature:range:)` is the control. `temperature` is an `Int` binding. `range` defaults to `60...85`. `LouvreVentThermostatDemo()` is the gallery page and starts at 68°F.

`LouvreVentCore` is the pure-Swift model. `LouvreVentTuning` holds the shared numbers. `LouvreVentMath` maps a set point to the blade angle, the chamber glow, the highlight on each blade, and the foreshortened face. `LouvreVentModel` runs the drag, the spring, the sweep, and the degree ticks.

## Constants

The values live on `LouvreVentTuning` and are copied in `webports/louvrevent-core.mjs`. `Tests/LouvreVentCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and the JS port match.

- Canvas 390 × 844. Frame (48, 168), 270 × 404, bezel 18. Opening (66, 186), 234 × 368.
- Seven blades. Angle 0° at the cool end (closed) and 70° at the hot end (open), linear in the set point. A single-degree range stays at 0°.
- Face ratio 0.92 of the slot when closed. The projected height is that face times cos(angle), from the shared Taylor cosine. The glow is the opening gradient with those projected faces cut out.
- Glow at 60°F is deep orange `(0.62, 0.16, 0.02)` at intensity 0.42. At 85°F it is white-hot `(1, 0.97, 0.91)` at intensity 1. Every channel rises with the set point.
- The resting highlight slides from 0.18 toward 0.80 down each face. Blade `i` adds `0.04 * i * (1 - unit) * 0.5`, so the glints stagger and still move together.
- The sweep is a triangle wave, amplitude 0.10, rising at 6.5/s while dragging or while the spring is moving, falling at 2.4/s after. Reduce Motion keeps the envelope at 0.
- Display spring k = 220, ζ = 0.92. Frames clamp at 0.1 s, substeps at 1/240 s. Reduce Motion snaps.

## Behaviour

Drag up (a smaller scene Y) raises the temperature. The opening's height maps onto the range, and the value rounds to an integer degree. Above the opening is the hot stop. Below it is the cool stop. A jump from 60 to 63 emits ticks for 61, 62, and 63. Setting the current degree again, or a value that clamps to the current stop, emits nothing.

The blades and the glow chase the set point on the spring, so a fast change does not pop. The highlight sweeps while they move. The readout is the integer degree.

## Accessibility

Reduce Motion snaps the angle and the glow on the set-point change and does not sweep the highlight. VoiceOver sees one adjustable element, "Louvre vent thermostat". The value is "72 degrees". A swipe changes the set point by one degree, and that swipe emits the same tick the drag would.

## Verification

Linux runs `LouvreVentCoreTests` (22 tests) as part of `swift test` (1670 tests, Swift 6.4.2), and `node webports/louvrevent-parity.mjs` (142 lines, exact match). `swiftc -parse` of the view and the gallery file was run on Linux. That parse does not typecheck SwiftUI (`#if canImport(SwiftUI)` is false here). A second parse with the condition forced on checks the view syntax only. The Metal file is excluded from the Linux build. No Apple build or device run was done for this component. The SwiftUI code and `Resources/LouvreSpecular.metal` need an Xcode build and a device check. The GIF and the contact sheet are the canvas port (`webports/louvrevent-capture.mjs`) at 390×844, using the JS core for every sample.
