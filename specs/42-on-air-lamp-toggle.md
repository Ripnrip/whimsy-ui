# 42 — OnAirLampToggle

Component 42. Main has forty components through PinataReward (40). Open pull request 8, CardToPillGlassMorph, claims 41. HoldToFanDock is 33.

## API

`OnAirLampToggle(isOn:)` is the public control. It fills its parent, draws the Murmur studio, and multiplies that studio by the throw. `OnAirLampToggleDemo` is the gallery page, the same control starting off.

`OnAirCore` is the pure-Swift model. `OnAirTuning` holds the shared numbers. `OnAirModel` runs the throw, the drag and the clock. `OnAirClock` formats elapsed seconds as `mm:ss`. `OnAirMath` is the polynomial sine the breath and the meter share with the web port.

## Constants

The values live on `OnAirTuning` and are copied in `webports/onair-core.mjs`. `Tests/OnAirCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and the JS port match.

- Scene 390 × 844. Pill 232 × 88 at (79, 456). Knob diameter 68, inset 10, travel 144.
- Commit at progress 0.5. A horizontal release of 8 pt or less is a tap and toggles.
- One spring: k = 260, ζ = 0.72. Substep 1/240 s, frame cap 0.1 s, settle tolerance 0.001.
- Reduce Motion crossfade 0.28 s. No breath.
- Breath period 2.6 s, depth 0.28. It multiplies the glow only while the switch is committed on.
- Room multiply floors at 0.055. Dim, glow and the ON AIR opacity are functions of the one throw progress.
- Clock truncates toward zero and stops at 99:59. `83` formats as `01:23`.

## Behaviour

A drag on the pill moves the knob with the finger. Release at or past halfway commits on; earlier, the spring throws back. A short release toggles from where the knob was. The click fires once, when the knob first reaches the stop (or when the crossfade ends). The studio's colour multiply, the red bloom, the label, the timer and the meter all read that progress. The timer counts only while committed on, holds through the return, and clears when the knob seats off.

## Accessibility

Reduce Motion crossfades the throw, skips the breath, and holds the meter still. The click still fires at the end of the fade. VoiceOver sees one toggle labelled "On air". The value is "Off", or "On air, 01:23" while live.

## Verification

Linux runs `OnAirCoreTests` (26 tests) as part of `swift test` (1481 tests, Swift 6.4.2), and `node webports/onair-parity.mjs` (287 lines, exact match). `swiftc -parse` of the view and the gallery file checks syntax only. That parse does not typecheck SwiftUI. No Apple build or device run was done for this component. The GIF and the contact sheet are the canvas port (`webports/onair-capture.mjs`) at 390 × 844, using the JS core for every sample.
