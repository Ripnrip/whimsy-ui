# 34 — RippleToHide

Numbered from current main, where HoldToFanDock is 33. Open pull requests 1, 2, 3, and 4 also use 34 and are not included here.

## API

`RippleToHide(isHidden:balance:)` shows a balance string and its dotted mask. `RippleToHide(isHidden:content:hidden:)` ripples whatever you pass, swapping to the hidden view halfway through. `isHidden` flips at that swap. Setting it from outside starts a hide or a reveal. `RippleToHideDemo` is the gallery sample: one checking card.

`RippleToHideCore` is the pure-Swift model. `RippleRules` holds the shared numbers. `RippleWave` is the displacement. `BalanceMask` replaces ASCII digits with bullets. `RippleModel` runs the trip.

## Constants

The values live on `RippleRules` and are copied in `webports/ripple-core.js` and as `constant float`s in `Sources/RippleToHide/Resources/RippleToHide.metal`. `webports/ripple-golden.json` is the trace both the Swift tests and the JS port match.

- Wavelength 44 pt, speed 240 pt/s, spatial decay 150 pt, time damping 0.48 s, front softness 20 pt.
- Duration 0.90 s. Amplitude 14 pt. Swap at halfway.
- Reduce Motion duration 0.28 s. Amplitude 0. No haptic.
- Displacement, for `t > 0`: `sin(k·d − ω·t) · gate · exp(−t / 0.48) · exp(−d / 150)`, with `k = 2π/44` and `ω = k·240`.
- `gate` is 1 behind the front and 0 past it, smooth over the last 20 pt. It is `1 − smoothstep(front − 20, front, d)`, the same Hermite as `WhimsyMath.smoothstep` and Metal's `smoothstep`.
- The stitchable function is `rippleToHide(position, tap, time, amplitude)`. It returns `position` within 0.001 pt of the tap, otherwise `position − normalize(position − tap) · displacement · amplitude`.
- Revealing passes `time = 0.90 − elapsed`, so the front travels back toward the tap.
- The pass radius is the distance from the tap to the farthest corner, capped at 92% of the 216 pt reach.

## Behaviour

A tap while shown starts an outward ripple. At 0.45 s the digits become dots and `isHidden` becomes true. The soft haptic fires once, when the front crosses the pass radius. At 0.90 s the trip settles hidden and the shader turns off. A tap while hidden runs the clock backward: the digits return at 0.45 s, the front crosses the radius on the way in, and it settles shown. A tap during a trip is ignored. `"$4,820.16"` masks as `"$•,•••.••"`.

## Accessibility

Reduce Motion crossfades the two faces over 0.28 s and does not distort or tick. The swap is still halfway. VoiceOver sees one toggle. The label defaults to "Balance". The value is "Hidden" or the shown amount. The actions are "Hide balance" and "Show balance".

## Verification

Linux runs `RippleToHideCoreTests` (29 tests) as part of `swift test` (1263 tests, Swift 6.4.1) and `node webports/parity.mjs`. `swiftc -parse` of the view and the gallery file succeeded. That parse does not typecheck SwiftUI, and the Metal file was not compiled. No Apple build or device run was done for this component. The GIF and the contact sheet are the canvas port (`webports/capture.mjs`), using the JS core for every sample coordinate.
