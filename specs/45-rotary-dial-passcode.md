# 45 — RotaryDialPasscode

Component 45, the last in the gallery, after GlassDropPourMenu (44).

## API

`RotaryDialPasscode(code:onUnlock:)` is the lock. `code` is four digits; shorter strings are left-padded with zeroes and longer ones keep the first four digit characters. `onUnlock` runs when the badge appears. `RotaryDialPasscodeDemo()` is the gallery page, with the code 5216 and a Reset button.

`RotaryDialCore` is the pure-Swift model. `RotaryDialTuning` holds the shared numbers. `RotaryDialMath` is the angle map, the detent index, the finger-stop clamp and the polynomial sine used by the shake. `RotaryDialModel` runs the drag, the spring, the entry, the shake and the morph.

## Constants

The values live on `RotaryDialTuning` and are copied in `webports/rotarydial-core.mjs`. `Tests/RotaryDialCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and the JS port match.

- Canvas 390 × 844. Dial centre (195, 500). Outer radius 148. Hole orbit 102. Hole radius 20. Grab slop 6.
- Ten holes, step π/6 (30°). Finger stop at π/5 (36° clockwise from 3 o'clock, y down). Digit 0 is ten steps, so its travel is 300°, short of a full turn.
- Commit slop is 0.42 of a step. The return spring is k = 400, ζ = 1. Drop 0.38 s. Shake 0.56 s, amplitude 16, five cycles. Reduce Motion tint 0.32 s. Morph 0.55 s, or 0.28 s with Reduce Motion.
- Dots sit at y = 156, 36 pt apart. Keypad keys are 62 pt with a 16 pt gap. The badge is 128 pt.

## Behaviour

A drag grabs one hole. Clockwise motion rotates the whole wheel, clamped so that hole cannot pass the stop. Extra travel past the stop is slack. Each hole-step that reaches or leaves the stop emits a tick, both while the finger is on the wheel and as it springs home. Release on the stop commits that digit and springs the wheel to rest. Release earlier declines it and still springs home. The committed numeral falls from the hole into the next dot.

The fourth digit is compared with `code`. A match morphs the dial into a check badge and then reports unlocked. A miss shakes, clears the dots, and morphs the dial into a keypad. A miss on the keypad shakes in place and stays a keypad. A match on the keypad morphs into the badge.

## Accessibility

Reduce Motion snaps the wheel to rest, uses a red tint instead of the shake, and fades the morph. There is no spin-back. VoiceOver sees one element, "Rotary passcode". The value is `n of 4`, "Incorrect", or "Unlocked". Digit 0 through 9 and Delete are actions. The entered count, a wrong code and unlocking are announced.

## Verification

Linux runs `RotaryDialCoreTests` (29 tests) as part of `swift test`, and `node webports/rotarydial-parity.mjs` (349 lines, exact match). `swiftc -parse` of the view and the gallery file succeeded. A second parse with the SwiftUI condition forced on checks the view syntax only. That parse does not typecheck SwiftUI. No Apple build or device run was done for this component. The SwiftUI code needs an Xcode build and a device check. The GIF and the contact sheet are the canvas port (`webports/rotarydial-capture.mjs`) at 390×844, using the JS core for every sample.
