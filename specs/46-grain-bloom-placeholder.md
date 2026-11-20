# 46 — GrainBloomPlaceholder

Component 46, after RotaryDialPasscode (45).

## API

`GrainBloomPlaceholder(image:palette:isGenerating:)` is the card. `image` is optional. `palette` defaults to four soft colors. `isGenerating` wakes the card when no picture is present. A picture becoming present starts the resolve. Passing the image through nil and back starts another resolve. `GrainBloomPlaceholderDemo()` is the gallery page, with Generate and Image arrives buttons. A tap on a finished card replays the bloom.

`GrainBloomCore` is the pure-Swift model. It never sees pixels. `GrainBloomTuning` holds the shared numbers. `GrainBloomMath` is the Bayer matrices, the cell-size steps, the ripple delay, the seeded grain and the blob drift. `GrainBloomModel` runs the phase timeline.

## Constants

The values live on `GrainBloomTuning` and are copied in `webports/grainbloom-core.mjs`. `Tests/GrainBloomCoreTests/Fixtures/golden-trace.txt` is the trace both the Swift tests and the JS port match.

- Stage 390 × 844. Wake 0.90 s. Resolve 1.40 s. Settle 0.35 s. Reduce Motion crossfade 0.28 s.
- Cell sizes 16, 8, 4, 2, 1 px, in equal slices of resolve progress. The 4×4 Bayer matrix is the conventional one. The 8×8 matrix is the recursive tiling of that 4×4, values 0 through 63.
- Coverage is measured on a 32×32 lattice of the same reveal rule. Blur starts at 18 and is 0 at the end of the resolve. The shimmer crosses once during waking.

## Behaviour

Idle is the resting mesh. Turning generation on with no picture enters waking immediately, including when the card is created that way. Dots light from the center, pulse, and a "Dreaming…" label sits over a shimmer. An arriving picture interrupts waking and starts resolving. The mask coarsens from 16 px cells to 1 px. A cell that has appeared stays visible as the cells shrink. Done plays a short grain settle and a small glint.

A tap, or the Replay bloom action, works only while done and a picture is showing. It plays waking, then resolving, then done again. Turning generation on after done does not replay. Clearing the picture returns to idle, or to waking if generation is still on.

A card that appears with a picture and generation off rests in done, with no glint. A card that appears with both starts resolving.

## Accessibility

Reduce Motion drops the ripple, the drift, the dot pulse and the shimmer. A static grain gradient crossfades to the picture over 0.28 s. VoiceOver uses one element, "Image placeholder". The value is "Generating image" until done, then "Image ready". Replay bloom is the accessibility action, and it runs only when the card is done.

## Verification

Linux runs `GrainBloomCoreTests` as part of `swift test`, and `node webports/grainbloom-parity.mjs` (exact match). `swiftc -parse` of the view and the gallery file checks syntax. That parse does not typecheck SwiftUI or compile the Metal shader. No Apple build or device run was done for this component. The SwiftUI and Metal code needs an Xcode build and a device check. The GIF and the contact sheet are the canvas port (`webports/grainbloom-capture.mjs`) at 390×844, using the JS core for every sample.
