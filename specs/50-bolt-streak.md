# 50 — BoltStreak

Component 50. Main has the forty-eight merged components. LouvreVentThermostat (49) is still open, so this count assumes it lands first. Package, gallery, and README registrations are appended so the two diffs can be union-merged.

## API

`BoltStreak(completedDays:today:)` is the control. `completedDays` is the set of lit weekdays. `today` defaults to `Weekday.current`. Tapping today's bolt marks it. `BoltStreakDemo()` is the gallery page: Monday through Wednesday start lit, and Thursday is today.

`BoltStreakCore` is the pure-Swift model. `BoltStreakTuning` holds the shared numbers. `BoltPath` is the normalised zigzag and the arc-length sample. `BoltStreakModel` runs the ignition clock, the queue, and Reduce Motion. `BoltStreakReel` is the scripted reel the canvas port plays.

## Constants

The values live on `BoltStreakTuning` and are copied in `webports/boltstreak-core.mjs`. `Tests/BoltStreakCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and the JS port match.

- Canvas 390 × 844. Weekly bolt 150 × 292 at y 150, centred. Day bolts 28 × 74, stride 48, row y 592.
- Centreline, unit box, y down: (0.72, 0.06), (0.30, 0.34), (0.78, 0.44), (0.22, 0.70), (0.58, 0.78), (0.18, 0.94).
- Ignition 0.64 s on a smoothstep. Frames longer than 0.05 s are clamped. One ignition is 39 steps of 1/60 s.
- Glow settled 0.62. Pulse amplitude 0.28 at ω = 18 while the bolt is the one igniting. Reduce Motion drops the pulse.
- Tilt 22° on X, perspective 0.6. It stays under Reduce Motion.
- Weekly stroke 20, day stroke 4.5. Head 11 and 4. Bloom blur 14.

## Behaviour

At rest a day in the set is full and its head sits on the tip. An empty day is bare zinc. Tapping today, or calling `ignite`, inserts the day and starts the burn from the shoulder. The head rides `trim`. The weekly target becomes the new count over seven immediately. The drawn weekly fill is the mean of the seven progresses, so it rises with the burn and meets the target when the burn ends. A second day asked during a burn waits, and ticks when it is asked.

Reduce Motion snaps the new day to full, parks the head, and holds the glow. Turning it on mid-burn fills every day already in the set, including one that was waiting.

## Accessibility

VoiceOver sees one element, "Weekly bolt streak". The value is the count and the lit days in weekday order, then whether today is lit. Mark today is the action while today is still dark.

## Verification

Linux runs `BoltStreakCoreTests` (18 tests) as part of `swift test` (1666 tests, Swift 6.4.2), and `node webports/boltstreak-parity.mjs` (133 lines, exact match). `swiftc -parse` of the view and the gallery file was run on Linux. A second parse with the SwiftUI condition forced on checks the view syntax only. That parse does not typecheck SwiftUI, and there is no Metal file. No Apple build or device run was done for this component. The SwiftUI code needs an Xcode build and a device check. The GIF and the contact sheet are the canvas port (`webports/boltstreak-capture.mjs`) at 390×844, using the JS core for every sample.
