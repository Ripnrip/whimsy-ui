# 47 — KoiNibblePond

Component 47. GrainBloomPlaceholder is 46 and is still open in pull request #13. This component is numbered 47 on the assumption that one lands first. Gallery, package and README registrations are appended so the two diffs union.

Inspired by the koi nibble onboarding at <https://nativecook.dev/>: a top-down pond, koi with a jointed spine and a beating tail, crowding a held fingertip, with ripples and a light haptic on each peck.

## API

`KoiNibblePond(koiCount:onNibble:)` is the pond. `koiCount` defaults to 6 and is clamped to 1…8. `onNibble` runs once per peck. `KoiNibblePondDemo()` is the gallery page.

`KoiPondCore` is the pure-Swift model. `KoiPondTuning` holds the shared numbers, including the palette and the lily pads. `KoiPondMath` is the polynomial sine, cosine, atan and angle wrap the web port copies. `KoiPondModel` runs the school.

## Constants

The values live on `KoiPondTuning` and are copied in `webports/koipond-core.mjs`. `Tests/KoiPondCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and `webports/koipond-parity.mjs` match.

- Scene 390 × 844. Pond ellipse from (28, 128), 334 × 600. The head swims inside an inset of 36 pt. A fingertip is clamped further in, by the nibble gap plus the bob, so a fish can sit on it and stay in the water.
- Spine of 5 points, each segment 18 pt. Body half-widths 10.5, 13, 10, 5.5, 1.6.
- Fixed step 1/60 s. A frame longer than 0.1 s is clamped, then sliced.
- Long press 0.24 s. Stagger 0.20 s per fish, from the moment the press commits.
- Lap speed 46 pt/s. Seek 128. Scatter 168 for 0.72 s, turning at 8.5 rad/s so they whip outward. Lap turn rate 3.4 rad/s.
- Arrival inside 22 pt, and only once the previous fish is already nibbling, so the school arrives in index order. While waiting, a fish holds inside 48 pt. The head sits 18 pt off the finger and bobs 6 pt. A nibble fires when the bob sine rises through 0.35.
- Tail wave ω 8.4, amplitude 0.52 rad at the tip, lag 0.62 rad per joint. The wave is applied to the constrained spine, so segment lengths stay 18 pt.
- Gather ripple 1.25 s, up to 148 pt. Nibble ripple 0.72 s, up to 34 pt. Reduce Motion holds those at 36 pt and 14 pt and fades them.
- Reduce Motion multiplies lap, seek, return and the tail clock by 0.42, and never enters the scatter burst.
- Feed koi holds the centre for 3.6 s, then releases. Default seed `0x4B6F694E69622B31`.

## Behaviour

At rest the koi orbit the pond, spread evenly with a small seeded jitter. A press arms a gather ripple. Before 0.24 s, letting go cancels and the fish keep lapping. After it, fish `i` leaves its lap at `i × 0.20` s and steers to the finger. It will not commit to a nibble until every earlier fish has. On the finger it faces the point and bobs head-first. Each upward crossing of the bob threshold emits a nibble, spawns a small ripple, and the view plays `.sensoryFeedback(.impact(weight: .light))` and calls `onNibble`.

Letting go aims each fish away from the finger, fans them, and runs the fast turn. When the burst ends they steer back to their laps. After the catch distance, or 3.4 s, the phase is laps again.

## Accessibility

The pond is one element, "Pond, 6 koi" (the count follows `koiCount`). The value is "Koi swimming", or "Koi nibbling" while a hold is committed. Feed koi starts a gather at the centre and lets go on its own, so nobody has to hold.

Reduce Motion drifts. Speeds, the tail and the bob use the 0.42 scale. Release goes straight to the return, with no scatter mode. Ripples do not expand. Turning Reduce Motion on during a burst drops the remaining scatter.

## Verification

Linux runs `KoiPondCoreTests` (17 tests) as part of `swift test` (1594 tests, Swift 6.4.2), and `node webports/koipond-parity.mjs` (413 lines, exact match). `swiftc -parse` of the view and the gallery file was run on Linux. That parse does not typecheck SwiftUI (`#if canImport(SwiftUI)` is false here), and the Metal file is excluded from the Linux build. The SwiftUI code and the caustic shader need an Xcode build and a device check. The GIF and the contact sheet are the canvas port (`webports/koipond-capture.mjs`) at 390×844, using the JS core for every sample.
