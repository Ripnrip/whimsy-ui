//  ScatterRegroupGrid.swift
//  ScatterRegroup
//
//  Tap the grid: tiles fling to random spots, tilted and scaled. Tap again and they spring
//  home in a ripple from the centre outward, with a light haptic tick as they land
//  (throttled). Layout, scatter targets, springs, ripple and landing detection live in
//  ScatterRegroupCore.

#if canImport(SwiftUI)
import SwiftUI
import ScatterRegroupCore

/// A `columns × rows` grid of gradient tiles that scatters and regroups when tapped.
///
/// Pass `isScattered` to drive it from outside; otherwise the grid keeps its own state.
public struct ScatterRegroupGrid: View {
    private let external: Binding<Bool>?
    @State private var internalScattered = false
    @State private var engine: ScatterEngine
    @State private var isAnimating = false
    /// Regroup haptic for the Reduce Motion crossfade (the spring path counts landings).
    @State private var crossfadeRegroups = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - columns, rows: grid size (default 4 × 6).
    ///   - seed: fixes the scatter positions and per-tile spring stiffness (default random).
    ///   - isScattered: optional external state; taps still toggle it.
    public init(columns: Int = 4, rows: Int = 6,
                seed: UInt64 = UInt64.random(in: 0...UInt64.max),
                isScattered: Binding<Bool>? = nil) {
        external = isScattered
        _engine = State(initialValue: ScatterEngine(columns: columns, rows: rows, seed: seed))
    }

    private var scattered: Bool { external?.wrappedValue ?? internalScattered }

    private func setScattered(_ value: Bool) {
        if let external { external.wrappedValue = value } else { internalScattered = value }
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: !isAnimating || reduceMotion)) { timeline in
                let frame = engine.frame(at: timeline.date, size: proxy.size)
                ZStack {
                    if reduceMotion {
                        // Crossfade between the two static layouts.
                        TileCanvas(tiles: engine.homeTiles, layout: engine.model.layout)
                            .opacity(scattered ? 0 : 1)
                        TileCanvas(tiles: engine.scatteredTiles, layout: engine.model.layout)
                            .opacity(scattered ? 1 : 0)
                    } else {
                        TileCanvas(tiles: engine.liveTiles, layout: engine.model.layout)
                    }
                }
                .animation(reduceMotion ? .easeInOut(duration: 0.3) : nil, value: scattered)
                .sensoryFeedback(trigger: frame.landingTicks) { old, new in
                    new > old ? .impact(weight: .light, intensity: 0.7) : nil
                }
                .onChange(of: frame.isSettled) { _, settled in
                    if settled { isAnimating = false }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { setScattered(!scattered) }
        .onChange(of: scattered, initial: true) { old, new in
            if old == new {
                engine.set(scattered: new, animated: false)    // first appearance
                return
            }
            engine.set(scattered: new, animated: !reduceMotion)
            if reduceMotion {
                if !new { crossfadeRegroups &+= 1 }
            } else {
                isAnimating = true
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: crossfadeRegroups)
        .accessibilityElement()
        .accessibilityLabel(Text("Tile grid"))
        .accessibilityValue(Text(scattered ? "Scattered" : "Arranged"))
        .accessibilityHint(Text(scattered ? "Double-tap to regroup the tiles." : "Double-tap to scatter the tiles."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { setScattered(!scattered) }
    }
}

// MARK: - Engine

struct ScatterFrame {
    var landingTicks: Int
    var isSettled: Bool
}

/// What the canvas needs to draw one tile.
struct TileDrawState {
    var index: Int
    var center: Vec2
    var rotation: Double
    var scale: Double
    /// 0 at home … 1 when far away; drives the shadow and stacking order.
    var lift: Double
}

/// Holds the deterministic model outside SwiftUI's dependency tracking. The TimelineView
/// steps it once per frame (stepping the same date twice is a no-op) and pauses when settled.
final class ScatterEngine {
    private(set) var model: ScatterRegroupModel
    /// Last scatter layout, kept so Reduce Motion can crossfade to and from it.
    private var lastScatter: [ScatterTarget] = []
    private var throttle = LandingThrottle(minimumInterval: 0.05)
    private var ticks = 0
    private var lastDate: Date?

    init(columns: Int, rows: Int, seed: UInt64) {
        model = ScatterRegroupModel(layout: TileLayout(columns: columns, rows: rows, width: 0, height: 0), seed: seed)
    }

    func set(scattered: Bool, animated: Bool) {
        guard scattered != model.isScattered else { return }
        if scattered {
            model.scatter(animated: animated)
            lastScatter = model.targets
        } else {
            model.regroup(animated: animated)
        }
        lastDate = nil
    }

    func frame(at date: Date, size: CGSize) -> ScatterFrame {
        let w = Double(size.width), h = Double(size.height)
        if w != model.layout.width || h != model.layout.height {
            let old = model.layout
            model.resize(width: w, height: h)
            if old.width > 0, old.height > 0 {
                lastScatter = lastScatter.map {
                    ScatterTarget(position: Vec2($0.position.x * w / old.width, $0.position.y * h / old.height),
                                  rotation: $0.rotation, scale: $0.scale)
                }
            }
        }
        if let lastDate {
            let landed = model.step(dt: date.timeIntervalSince(lastDate))
            if !landed.isEmpty && throttle.shouldFire(at: model.time) { ticks += 1 }
        }
        lastDate = date
        return ScatterFrame(landingTicks: ticks, isSettled: model.isSettled)
    }

    private var farDistance: Double { max(model.layout.width, model.layout.height) * 0.25 }

    var liveTiles: [TileDrawState] {
        model.tiles.enumerated().map { i, t in
            TileDrawState(index: i, center: t.position, rotation: t.rotation, scale: t.scale,
                          lift: min(t.liftAmount(home: model.layout.home(i)) / max(farDistance, 1), 1))
        }
    }

    var homeTiles: [TileDrawState] {
        (0..<model.layout.count).map { TileDrawState(index: $0, center: model.layout.home($0), rotation: 0, scale: 1, lift: 0) }
    }

    var scatteredTiles: [TileDrawState] {
        let targets = lastScatter.count == model.layout.count ? lastScatter : model.targets
        return targets.enumerated().map { TileDrawState(index: $0, center: $1.position, rotation: $1.rotation, scale: $1.scale, lift: 1) }
    }
}

// MARK: - Drawing

/// Draws the tiles in one Canvas: rounded rects with a per-tile gradient, a top highlight, and a
/// shadow that grows as the tile lifts away from home. Lifted tiles draw on top.
struct TileCanvas: View {
    let tiles: [TileDrawState]
    let layout: TileLayout

    var body: some View {
        Canvas { context, _ in
            let w = layout.tileWidth, h = layout.tileHeight
            guard w > 0, h > 0 else { return }
            let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
            let shape = Path(roundedRect: rect, cornerRadius: min(w, h) * 0.22, style: .continuous)
            let count = max(layout.count - 1, 1)
            for tile in tiles.sorted(by: { $0.lift < $1.lift }) {
                // Shadow: tight at home, soft and dropped further when lifted. The offset is in
                // screen space (straight down, light from above), not rotated with the tile.
                var shadow = context
                shadow.addFilter(.blur(radius: 2 + 8 * tile.lift))
                shadow.translateBy(x: tile.center.x, y: tile.center.y + 2 + 6 * tile.lift)
                shadow.rotate(by: .radians(tile.rotation))
                shadow.scaleBy(x: tile.scale, y: tile.scale)
                shadow.fill(shape, with: .color(.black.opacity(0.14 + 0.12 * tile.lift)))

                var ctx = context
                ctx.translateBy(x: tile.center.x, y: tile.center.y)
                ctx.rotate(by: .radians(tile.rotation))
                ctx.scaleBy(x: tile.scale, y: tile.scale)

                let hue = (0.52 + 0.42 * Double(tile.index) / Double(count)).truncatingRemainder(dividingBy: 1)
                ctx.fill(shape, with: .linearGradient(
                    Gradient(colors: [
                        Color(hue: hue, saturation: 0.45, brightness: 1.0),
                        Color(hue: (hue + 0.05).truncatingRemainder(dividingBy: 1), saturation: 0.72, brightness: 0.86),
                    ]),
                    startPoint: CGPoint(x: rect.minX, y: rect.minY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                ))
                ctx.stroke(shape.offsetBy(dx: 0, dy: 0.5), with: .color(.white.opacity(0.35)), lineWidth: 1)
            }
        }
    }
}

// MARK: - Preview

private struct ScatterRegroupDemo: View {
    @State private var isScattered = false
    var body: some View {
        VStack(spacing: 16) {
            ScatterRegroupGrid(seed: 7, isScattered: $isScattered)
                .frame(width: 340, height: 500)
            Text(isScattered ? "Tap to regroup" : "Tap to scatter")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview("Scatter & Regroup") {
    ScatterRegroupDemo()
}
#endif
