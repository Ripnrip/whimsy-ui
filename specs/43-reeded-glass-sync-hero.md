# 43 — ReededGlassSyncHero

Component 43. Main has 40, ending at PinataReward. Open pull request #8 claims 41 (`CardToPillGlassMorph`). No open pull request claims 42, so that number stays free. This branch adds one component to the forty on main, and the gallery count on this branch is forty-one.

## API

`ReededGlassSyncHero(progress:title:subtitle:detail:roll:pitch:useDeviceMotion:)` shows the Halo Vault sync hero. `progress` is a `Binding<Double>` from 0 to 1. The other arguments have defaults: "Halo Vault", "Studio library", "1,284 files · 3 devices", roll 0, pitch 0, and device motion on.

`roll` and `pitch` are radians. They are used only when `useDeviceMotion` is false, so a preview can inject a tilt. On an iPhone, the default reads CoreMotion and ignores the injected values.

`ReededGlassSyncHeroDemo` plays progress from 0 to 1 and offers Replay.

`SlatSyncCore` is the pure-Swift model. `SlatSyncTuning` holds the shared numbers. `SlatSyncMath` turns a progress value into reeds, spread, colour, a percent, a label and a wobble. `SlatSyncScene.make` is one frame. `SlatSyncMonitor` counts crossings into 100%.

## Constants

The values live on `SlatSyncTuning` and are copied in `webports/slatsync-core.mjs`. `Tests/SlatSyncCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and the JS port match (275 lines).

- Stage 390×844. Eleven slats, 332×26, gap 8, stack top 176, corner 4.
- Spread floor 0.22, ceiling 1. Reach grows from 2.45 slats to 6.2. The gate feathers over 0.85 slats.
- Attitude clamps at ±0.55 rad. Roll travel is 40 pt per radian before the depth scale. Pitch bow is 0.55.
- Demo delay 0.35 s, then an ease-in-out cubic over 3.5 s.
- Cobalt `(47, 92, 255)`, teal `(32, 214, 206)`, lime `(184, 255, 74)`, all over 255. The blend leaves cobalt at 0.42 of the stack.
- The 1 pt edge is `0.22 + 0.78 * spread * opacity`.

## Behaviour

At progress 0 only the middle five slats (indices 3…7) are lit, and the centre is about 22% of the slat width. Spread is monotonic in progress and stays in 0…1. At 1 the centre is exactly full and every slat is above 0.95. A non-finite progress is 0. Values outside 0…1 clamp.

The percent is the nearest integer, half away from zero. A 1e-8 epsilon keeps 0.995 on the 100 side of the tie, and 0.994 on the 99 side. 0.42 is "Syncing, 42 percent". The label is "Syncing…" below 100 and "All synced" at 100.

`SlatSyncMonitor.setProgress` fires once when the displayed percent crosses into 100. Holding at 100% does not fire again. Dropping below 100% re-arms the next crossing. A non-finite update is ignored.

Each slat's blur, offset and tilt come from a 32-bit mix of its index (`unit(index:salt:)`). The centre is the sharpest reed. An index outside 0…10 is dark and flat.

Roll adds a sideways offset of the same sign on every slat, larger at the ends. Pitch adds a tilt of opposite sign at the top and the bottom, and zero at the centre. Reduce Motion, or a non-finite attitude, returns a zero wobble. Attitude past the clamp matches the clamp exactly.

Reduce Motion fades the finished aurora: every slat uses the spread it would have at progress 1, and the opacity is the clamped progress. Wobble is zero. The view also skips the 3D tilt and fades the percentage instead of rolling it.

The scripted demo stays at 0 until 0.35 s, is exactly 0.5 at the midpoint of the 3.5 s run, and is 1 at the end.

## Accessibility

VoiceOver sees one progress indicator. The label is `SlatSyncMath.voiceOver`: "Syncing, 42 percent" while the displayed percent is below 100, and "All synced" at 100%. The slats, the plus and the header are hidden from the rotor. One soft impact fires when the percent crosses 100.

## Verification

Linux runs `SlatSyncCoreTests` (24 tests) as part of `swift test` (1479 tests, Swift 6.4.2) and `node webports/slatsync-verify.mjs` (275 lines, exact match). `swiftc -parse` of the view and the gallery file does not typecheck SwiftUI, because `canImport(SwiftUI)` is false on Linux. No Apple build or device run was done for this component. `MeshGradient` needs the iOS 18 / macOS 15 SDK; the fallback is three blurred circles. The GIF and the contact sheet are the canvas port (`webports/slatsync-capture.mjs`) at 390×844 points.
