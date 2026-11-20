# 48 — GooMergeDrops

Component 48. Main has the forty-five merged components. GrainBloomPlaceholder (46) and KoiNibblePond (47) are still open, so this count assumes they land first. Package, gallery, and README registrations are appended so the three diffs can be union-merged.

## API

`GooMergeDrops(drops:onMerged:)` is the control. `drops` is four or five `GooDrop` values (`name`, `value` in 0…1). Fewer than four uses the five samples. More than five keeps the first five. `onMerged` receives `"Binder-01.pdf"` once the card has finished. `GooMergeDropsDemo()` is the gallery page.

`GooMergeCore` is the pure-Swift model. `GooMergeTuning` holds the shared numbers. `GooMergeField` is the ring, the radius map, the polynomial smooth-min, and the metaball sum. `GooMergeModel` runs the drag, the snap, the spring, and the morph.

## Constants

The values live on `GooMergeTuning` and are copied in `webports/goomerge-core.mjs`. `Tests/GooMergeCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and the JS port match.

- Canvas 390 × 844. Well (195, 400). Ring radius 112. Dashed well radius 36. Drop radius 26…44 from `value`.
- Stretch begins at a surface gap of 40 pt. Snap is a surface gap of 8 pt. Full stretch slides each drawn centre 16 pt toward the other. A neighbour creeps at 12 pt/s at full stretch.
- Combine spring k = 32, ζ = 1.05, fixed substeps of 1/240 s, frames clamped at 0.1 s. A substep that would move a drop back out of the well is pinned, so the approach does not reverse. Arrival is 2 pt.
- Smooth-min blend k = 32. Metaball epsilon = 4. Merge progress is the lesser of the two normalised fields sampled at the well. It is 1 once the morph starts.
- Morph 0.72 s. Reduce Motion crossfade 0.28 s. Idle bob amplitude 3 pt at ω = 1.7, scaled per drop by the seed.
- Card 168 × 216, corner 16, fold 32. Goo blur 14, alpha threshold 0.52.

## Behaviour

At rest the drops sit on the ring, index 0 at 12 o'clock, and bob on the seed. The well is outside the field, so no pair is connected. Drag one drop. Inside the stretch band both drops slide toward each other. Inside the snap gap the dragged cluster joins the other drop and their centres meet. Let go of a drop that did not snap and it springs home. Let go of a snapped cluster and it stays.

Combine springs every centre toward the well. When all of them are inside the arrival radius the blob morphs into Binder-01.pdf. The folded corner grows through the second half of that morph. The view draws the field with a Canvas blur and an alpha threshold, and uses the Metal SDF (`GooMerge.metal`) on iOS 18 / macOS 15 when Reduce Motion is off. The shader is the same smooth-min. The Canvas path is the fallback.

## Accessibility

Reduce Motion turns off the bob, the stretch, the snap, and the spring. Combine places every drop on the well and crossfades to the card. VoiceOver sees one element, "Goo merge, 5 files". The value is "Ready to combine", "Merging", or "Merged into Binder-01.pdf". Combine is an action.

## Verification

Linux runs `GooMergeCoreTests` (21 tests) as part of `swift test` (1598 tests, Swift 6.4.2), and `node webports/goomerge-parity.mjs` (275 lines, exact match). `swiftc -parse` of the view and the gallery file succeeded. A second parse with the SwiftUI condition forced on checks the view syntax only. That parse does not typecheck SwiftUI, and the Metal file was not compiled. No Apple build or device run was done for this component. The SwiftUI code needs an Xcode build and a device check. The GIF and the contact sheet are the canvas port (`webports/goomerge-capture.mjs`) at 390×844, using the JS core for every sample.
