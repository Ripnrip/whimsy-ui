# whimsy-ui

Six small, tactile SwiftUI components, each with a pure-Swift, unit-tested core:

| | Component | What it does |
|---|---|---|
| 🫧 | **PopTherapy** | Bubble wrap: drag to pop, per-bubble squish, haptics, a gloss shader, and a gift when you finish. |
| 🧲 | **MagneticBeadSlider** | A slider whose beads trail the thumb like a magnetic chain, with squash, snapping and haptics. |
| 🩹 | **EraserDelete** | Delete a card by rubbing it out with a zig-zagging pink eraser, with crumbs. Automatic or manual scrub. |
| 📷 | **ShutterReveal** | A camera-iris reveal: metallic blades swirl open with overshoot and snap shut. |
| 👀 | **AliveEyes** | Two cartoon eyes with a spring gaze, saccades, asymmetric blinks and a shake-triggered squint. |
| 🧩 | **ScatterRegroup** | Tap a tile grid: tiles fling out tilted, then spring home in a ripple from the centre, ticking as they land. |

iOS 17+ / macOS 14+, Swift tools 6.0 (Swift 6 language mode).

> **Honest status:** every core target builds, and all 162 tests pass on Linux (Swift 6.4).
> The SwiftUI targets have **not yet been compiled or run on an Apple platform**. On Linux
> they compile to empty modules (`#if canImport(SwiftUI)`). They were checked with
> sourcekit-lsp (0 diagnostics), `swiftc -parse` and careful API review, but expect
> possible small fixes on the first Xcode build.
> The GIFs below are **HTML5 Canvas ports** of each view's drawing, running a JS port of
> the same core logic. They approximate the SwiftUI rendering; they are not device
> recordings.

## Install (Swift Package Manager)

In Xcode: **File ▸ Add Package Dependencies…**, enter this repository's URL, and add the
products you want. Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<you>/whimsy-ui.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "ShutterReveal", package: "whimsy-ui"),
        .product(name: "AliveEyes", package: "whimsy-ui"),
    ]),
]
```

Each component is its own product: `PopTherapy`, `MagneticBeadSlider`, `EraserDelete`,
`ShutterReveal`, `AliveEyes` and `ScatterRegroup`. There's also a SwiftUI-free `…Core` product for each
(e.g. `ShutterRevealCore`), plus `WhimsyGallery`, a demo list of all six.

```swift
import WhimsyGallery
WhimsyGallery()   // NavigationStack listing every component with a live demo
```

---

### 🫧 PopTherapy

![PopTherapy](docs/poptherapy.gif)

```swift
import PopTherapy

PopTherapyView()                    // 6 × 8 sheet
PopTherapyView(columns: 5, rows: 7)
```

- **Popping:** drag to pop. Fast drags interpolate, so no bubble is skipped.
- **Feel:** each pop squishes and gives a light haptic of random intensity. A Metal
  `.colorEffect` shader drifts a gloss highlight across the sheet.
- **Finish:** popping everything unwraps a gift, with a Reset button.

### 🧲 MagneticBeadSlider

![MagneticBeadSlider](docs/beads.gif)

```swift
import MagneticBeadSlider

@State private var value = 0.4
MagneticBeadSlider(value: $value, steps: 10)   // stepped; snaps on release
MagneticBeadSlider(value: $value, steps: 0)    // continuous
```

- **Motion:** eight beads follow the thumb with distance-falloff pull and per-bead damped
  springs, squashing along their motion.
- **Haptics:** selection feedback on step crossings, and an impact on snap.

### 🩹 EraserDelete

![EraserDelete](docs/eraser.gif)

```swift
import EraserDelete

NoteCard(note)
    .eraserDelete(isErasing: $isErasing) {
        withAnimation { notes.removeAll { $0.id == note.id } }
    }
// or ErasableCard(isErasing:style: .manual, onErased:) { … } to scrub by hand
```

- **Masking:** the card is masked by the growing stroke (`.destinationOut`).
- **Feel:** a haptic on each zig-zag turn, and crumbs fall off the eraser.
- **Finish:** at 96% coverage the remains fade and `onErased` fires.

### 📷 ShutterReveal

![ShutterReveal](docs/shutter.gif)

```swift
import ShutterReveal

PhotoView()
    .shutterRevealOnTap(isOpen: $isOpen)            // or .shutterReveal(isOpen:blades:response:)
    .clipShape(.rect(cornerRadius: 28))             // after the modifier, so it clips the blades too
```

- **Coverage:** blade *j* is the wedge outside the aperture polygon at vertex *j*, so the
  blades tile the outside exactly. The tests verify full coverage when closed and full
  clearance when open.
- **Motion:** opening is a springy overshoot, and the content scales 0.96 → 1. Closing
  snaps, with a light haptic as the blades shut. Fast motion adds rotated ghost copies as
  motion blur.

### 👀 AliveEyes

![AliveEyes](docs/eyes.gif)

```swift
import AliveEyes

AliveEyesView(lidColor: face, squintTrigger: squints)
    .frame(height: 260)
    .background(face, in: .rect(cornerRadius: 36))
```

Timings follow Matt Busel's ["Making two cartoon eyes feel alive"](https://dev.to/mattbusel/making-two-cartoon-eyes-feel-alive-springs-saccades-and-blinks-in-swiftui-26i9):

- Gaze spring k 420 / ζ 0.8, drifting home on release.
- Saccades every 0.25–0.9 s.
- Blinks every 2.2–6.5 s, 70 ms close / 100 ms open, 18% double blinks.
- Shake (Core Motion, iOS) to squint; double-tap or `squintTrigger` elsewhere.

### 🧩 ScatterRegroup

![ScatterRegroup](docs/scatter.gif)

```swift
import ScatterRegroup

ScatterRegroupGrid()                                  // 4 × 6, tap to toggle
ScatterRegroupGrid(columns: 3, rows: 4, seed: 7, isScattered: $isScattered)
```

- **Scatter:** each tile flies to a random spot, tilted up to ±25° and scaled 0.86–1.14.
  Targets are inset by the tile's half-diagonal, so a tilted tile never leaves the bounds.
- **Springs:** every tile has its own stiffness (150 × 0.7–1.3, fixed per seed) at damping
  0.62, so they arrive at slightly different times with a little bounce.
- **Regroup:** delays grow with distance from the centre (0 → 0.38 s), giving a ripple
  outward. Each tile reports its landing once, and a light haptic ticks at most every
  50 ms, so a burst of landings doesn't blur together.

> **Stagger alternative:** if you'd rather express the ripple with SwiftUI's own
> animations instead of a simulated spring per tile, jazzychad's
> [AnimationSequencing](https://github.com/jazzychad/AnimationSequencing) choreographs
> SwiftUI animations into ordered sequences of steps. It isn't a dependency here: the core does its own staggering so
> it stays deterministic and testable on Linux.

---

## Accessibility

Every component handles **Reduce Motion**, each in its own way:

| Component | With Reduce Motion |
|---|---|
| PopTherapy | No gloss drift or squish. |
| MagneticBeadSlider | Beads settle instantly. |
| EraserDelete | Quick fade. |
| ShutterReveal | Crossfade. |
| AliveEyes | No saccades, gentler blinks. |
| ScatterRegroup | Crossfade between the grid and the scattered layout. |

All six have VoiceOver labels and actions (e.g. pop next bubble, adjustable slider,
erase, open/close shutter, squint, scatter/regroup).

## Layout

```
Sources/
  WhimsyCore/            Shared Vec2 + SeededRandom (SplitMix64), re-exported by the cores that use them
  PopTherapyCore/        PopTherapy/          (+ Resources/Shaders.metal)
  MagneticBeadCore/      MagneticBeadSlider/
  EraserDeleteCore/      EraserDelete/
  ShutterRevealCore/     ShutterReveal/
  AliveEyesCore/         AliveEyes/
  ScatterRegroupCore/    ScatterRegroup/
  WhimsyGallery/         Demo gallery of all six
Tests/                   Swift Testing suites for WhimsyCore and every core
docs/                    README GIFs
```

The `…Core` targets import only Foundation and are deterministic (seedable RNGs, fixed
substeps), so they test on any platform:

```sh
swift build && swift test     # Linux or macOS
```

## License

MIT © 2026 Gurinder Singh. See [LICENSE](LICENSE).
