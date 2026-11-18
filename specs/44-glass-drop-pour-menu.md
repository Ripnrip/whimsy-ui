# 44 — Glass Drop Pour Menu

Component 44, between ReededGlassSyncHero (43) and RotaryDialPasscode (45) in the gallery.

Inspired by the glass pour menu at <https://nativecook.dev/blocks/glass-pour-menu/>: one glossy droplet pours open into Share, Duplicate, Rename and Delete.

## API

`GlassDropPourMenu(items:onSelect:)` is the control. `items` defaults to Share, Duplicate, Rename and Delete. `onSelect` receives the `GlassDropItem` that was tapped. `GlassDropPourMenuDemo()` is the gallery page: a note on a sunset, the drop on the card, and the last choice along the bottom.

`GlassPourCore` is the pure-Swift model. `GlassPourTuning` and `GlassPourLayout` hold the shared numbers. `GlassPourModel` runs the long-press, the stagger, the springs and the suck-back. There is no Metal shader. The liquid join is a SwiftUI `Canvas` blur plus `alphaThreshold`, the same filter `PourOpenMenu` uses.

## Constants

The values live on `GlassPourTuning` and `GlassPourLayout`. `webports/glasspour-core.mjs` copies them. `Tests/GlassPourCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and `webports/glasspour-parity.mjs` match.

- Long-press 0.32 s. Stagger 0.07 s between rows.
- Travel spring k = 170, ζ = 0.62. A row leaves the drop at scale 0.42 and may pass its seat (the overshoot tops out near 1.08) before it settles. Scale is clamped to 0.20…1.08.
- Delete's wobble is a second spring, k = 260, ζ = 0.16. When its travel crosses 0.86 on the way open, it takes a kick of 2.4 rad/s. The peak is about 6°. The other rows are not kicked.
- Necks: max width 40 pt, gone once the gap is 11 pt, waist thins by 0.55, and a neck under half a point is dropped. Goo blur is 9 pt, alpha threshold 0.5.
- Label opacity fades in from travel 0.62 to 0.92. Reduce Motion fades in place over 0.24 s.
- Layout, menu coordinates: width 228, drop radius 30 at (114, 36), pills 196×50, gap 14, pitch 64. Rest seats are y = 105, 169, 233, 297. The menu is 340 pt tall for four rows and 468 pt for six. The web stage is 390×844 with the menu's origin at (81, 300).
- On screen, the menu prefers to start 36% of the way down (at most 360 pt) and then moves up so the last row stays 8 pt inside the container. A 390-pt-tall page therefore starts the four-row menu at y = 42, not y = 160. If the menu is taller or wider than the container, the view scrolls it.
- A step longer than 0.1 s is clamped. Springs integrate at 1/240 s, the same semi-implicit Euler as `WhimsySpring`.

## Behaviour

A press on the drop arms. Past 0.32 s the rows pour downward, each waiting `index · 0.07` s, joined to the drop by an hourglass neck. A release before 0.32 s is a short press and the menu stays shut. Once the springs have seated, the necks have pinched off and the pills are crisp glass. Delete is red and wobbles as it lands. Tap outside, or tap the drop, and the rows suck back up, last row first. Tap a row and `onSelect` fires, then the same suck-back runs. VoiceOver activates the drop without the hold. Up to six rows are kept; an empty list uses the four defaults.

## Accessibility

The drop is a button labelled "Menu". Its value is Closed or Open, and its hint is "Opens the menu" or "Closes the menu". Opening announces "Menu opened". Closing announces "Menu closed". Choosing a row announces its title. Each visible row is a button; Delete's hint is "Deletes". Rows are hidden from VoiceOver until they are far enough out to tap. The escape action sucks the menu back up.

Reduce Motion does not pour and does not wobble. The drop does not swell while arming. The rows sit on their seats and crossfade over 0.24 s. Necks are empty. Choosing, the announcements and the long-press gate still work. VoiceOver still opens the menu without holding.

## Verification

Linux runs `GlassPourCoreTests` (15 tests) as part of `swift test` (1470 tests, Swift 6.4.2), and `node webports/glasspour-parity.mjs` checks the fixture (812 lines, exact match). `swiftc -parse` of the view and the gallery file was run on Linux. That parse does not typecheck SwiftUI (`#if canImport(SwiftUI)` is false here), and there is no Metal file to compile. The SwiftUI code needs an Xcode build and a device check. The GIF and the contact sheet are the canvas port (`webports/glasspour-capture.mjs`) at 390×844, using the JS core for every sample.
