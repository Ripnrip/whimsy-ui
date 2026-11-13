# 41 — CardToPillGlassMorph

Component 41 on main, after PinataReward (40). VelocityGlyphScatter is 39.

## API

`CardToPillGlassMorph(amount:label:payTitle:amber:red:onPaid:)` shows a frosted pay card. The defaults are "$48.00", "Solune", "Pay", and the amber and red in `GlassMorphTuning`. `onPaid` fires once, together with the success haptic, when the lights settle. `CardToPillGlassMorphDemo` is the gallery sample: the same card on the navy field.

`GlassMorphCore` is the pure-Swift model. `GlassMorphTuning` holds the shared numbers. `GlassMorphLayout` turns a progress value into a frame, two lights, face opacities and a flip angle. `GlassMorphModel` runs the trip.

## Constants

The values live on `GlassMorphTuning` and are copied in `webports/glassmorph-core.mjs`. `Tests/GlassMorphCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and the JS port match.

- Stage 390×844. Card and pill share the centre (195, 400).
- Card 308×420, corner 32, tilt −3°. Pill 136×56, corner 28, tilt 0.
- Amber rest (98, 258), radius 88, blur 18. Red rest (322, 548), radius 50, blur 14.
- Logo dots (184, 400) radius 8 and (206, 400) radius 7. Blur 0. 22 pt apart.
- Morph spring k = 170, ζ = 0.75. Settled when progress is within 0.004 of 1 and speed is within 0.04. The lights follow the clamped progress, so they stop on the dots while the glass frame overshoots.
- Hold 1.0 s after settle. Unfold 0.45 s. Reduce Motion fade 0.28 s each way.
- Substeps of 1/240 s. A frame longer than 0.1 s is clamped.

## Behaviour

Pay is accepted only from the resting card, and only on the Pay button when the hit is a point. The phase order is card, morphing, pill, unfolding, card. Full motion springs progress 0 → 1. The frame and both lights are that progress, so they settle together. The spring overshoots past 1. Tilt and blur clamp to the pill. One `.settled` event fires, then the pill holds, then `.unfolding`. The flip is π times an ease-in-out cubic of the unfold age. At π/2 the card face replaces the dots. The trip ends with `.returned`, progress 0 and flip 0, which matches the upright card because the displayed flip is `angle − π` past the edge.

A second pay during the trip does nothing. Stepping while the phase is card does nothing. A non-positive or non-finite step does nothing.

## Accessibility

Reduce Motion does not spring and does not flip. Progress moves in a straight line, and the view crossfades the resting card with the resting pill. The hold is still one second. The success haptic still fires once, when the crossfade reaches the pill. VoiceOver sees one button. The label is the wallet name and the amount. The value is Ready, Paying, Paid or Opening. The Pay action starts a trip. Settling posts the announcement "Payment complete".

## Verification

Linux runs `GlassMorphCoreTests` (25 tests) as part of `swift test` (1480 tests, Swift 6.4.2) and `node webports/verify-glassmorph.mjs` (258 lines, exact match). `swiftc -parse` of the view and the gallery file does not typecheck SwiftUI, because `canImport(SwiftUI)` is false on Linux. No Apple build or device run was done for this component. `.glassEffect` needs the iOS 26 / macOS 26 SDK; the fallback is `.ultraThinMaterial`. The GIF and the contact sheet are the canvas port (`webports/capture-glassmorph.mjs`) at 390×844 points.
