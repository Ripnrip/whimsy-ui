# 37 — CrumpleToDelete

Component 37 on main, after TiltScatterRestore (34), NeighborBouncePicker (35), and RubberBandCardHand (36). HoldToFanDock is 33.

## API

`CrumpleToDelete` takes the caller's SwiftUI content as the flat card face and an `onDeleted` callback that fires once when the ball arrives, or when the Reduce Motion fade ends. `restoreToken` asks the card to spring back, including mid-toss. `CrumpleToDeleteDemo` is the gallery sample: one grocery card, the trash, and Undo.

`CrumpleCore` is the pure-Swift model. `CrumpleRules` holds the shared numbers. `CrumpleMesh.sample` builds the triangles. `CrumpleModel` tracks the drag, the creases, the toss, and the restore.

The triangles are generated paper. They do not show the wrapped view.

## Constants

The values live on `CrumpleRules` and are copied in `webports/crumple-core.js`. `webports/crumple-golden.json` is the trace both sides match.

- Commit when progress is at least 0.8, or when the card center is inside the bin.
- Leaving the bin clears that latch. There is no second progress threshold.
- 5 by 4 quads, 40 triangles. The settled ball's radius is one sixth of the shorter side.
- Light `(0.45, 0.55, 0.70)`, normalized. One paper colour, Lambert shade.
- A crease is a shared edge whose fold angle crosses 0.35 radians while progress is increasing, once per gesture.
- Spring-back uses stiffness 380 and damping 0.4. Reduce Motion uses 520 and 1, and fades for 0.35 s.
- The view plays at most one light haptic per 0.12 s. The core log keeps every crease.

## Behaviour

Dragging projects the finger from the card's rest center toward the bin center. Releasing early springs the card flat. A commit snaps the hull to the ball, lets that spring overshoot, then tosses the ball on a quadratic arc. The lid bumps on arrival in full motion. VoiceOver Delete commits without a drag. Reset before arrival does not report the delete.

## Accessibility

Reduce Motion fades and shrinks instead of drawing the mesh, and it does not toss or bump the lid. The commit rule is the same. VoiceOver uses a Delete action. The demo's Undo restores the card.

## Verification

Linux runs `CrumpleCoreTests` and `node webports/parity.mjs`. `swiftc -parse` of the view file on Linux does not see the SwiftUI body. No Apple build or device run was done for this component.
