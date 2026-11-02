//
//  ContourInkLoader.swift
//  ContourInkLoader
//
//  A loader that sketches six or seven nested, wobbly contour rings one after another, like a pen drawing
//  a topographic map on cream paper: each ring is a sine-perturbed circle revealed with `.trim`, the pen
//  nib riding its tip, an index contour every third ring drawn thicker. When the last ring closes a small
//  red dot climbs a dashed route from the outer ring to the peak, the sheet tilts back about 25 degrees,
//  fades, and the loop starts again. A light haptic ticks as each ring closes.
//  Ring geometry, the loop's phases, the route, the tilt, the opacity and the ring-closed events all live
//  in ContourInkCore as pure functions of time.

#if canImport(SwiftUI)
import SwiftUI
import ContourInkCore

/// A topographic-map loader drawn in ink.
///
/// ```swift
/// ContourInkLoader()                                        // 7 rings, sepia ink
/// ContourInkLoader(rings: 6, ink: .indigo, isAnimating: loading)
/// ```
///
/// The sheet is 280 points square; scale it with `.scaleEffect` if you need another size.
public struct ContourInkLoader: View {
    @State private var engine: ContourInkEngine
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rings: Int
    private let ink: Color
    private let isAnimating: Bool

    public static let sheetSide: CGFloat = 280
    public static let defaultInk = Color(red: 0.36, green: 0.22, blue: 0.12)

    /// - Parameters:
    ///   - rings: how many contour rings, 3 ... 12 (default 7).
    ///   - ink: the colour of the contour lines (the dot and its trail stay red).
    ///   - isAnimating: when false, or under Reduce Motion, the finished map is shown still, with the dot at the peak.
    public init(rings: Int = ContourInkGeometry.defaultRings, ink: Color = ContourInkLoader.defaultInk, isAnimating: Bool = true) {
        let n = ContourInkGeometry.clampedCount(rings)
        self.rings = n
        self.ink = ink
        self.isAnimating = isAnimating
        _engine = State(initialValue: ContourInkEngine(rings: n))
    }

    public var body: some View {
        let running = isAnimating && !reduceMotion
        TimelineView(.animation(paused: !running)) { timeline in
            let f = engine.frame(at: timeline.date, isAnimating: isAnimating, reduceMotion: reduceMotion)
            sheet(f)
                .rotation3DEffect(.degrees(f.tiltDegrees), axis: (x: 1, y: 0, z: 0), anchor: .center, anchorZ: 0,
                                  perspective: ContourInkTimeline.perspective)
                .opacity(f.opacity)
                .onChange(of: engine.model.ringsClosed) { _, n in ticks = n }
        }
        .frame(width: Self.sheetSide, height: Self.sheetSide)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.4), trigger: ticks)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isAnimating ? "Loading" : "Topographic map")
        .accessibilityValue(isAnimating ? "Sketching a topographic map" : "")
        .accessibilityAddTraits(isAnimating ? .updatesFrequently : [])
    }

    // MARK: drawing

    private func p(_ v: Vec2) -> CGPoint {
        CGPoint(x: (v.x + 0.5) * Self.sheetSide, y: (v.y + 0.5) * Self.sheetSide)
    }

    private func sheet(_ f: ContourFrame) -> some View {
        let map = engine.map, route = engine.route
        let side = Self.sheetSide
        return ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.97, green: 0.94, blue: 0.86), Color(red: 0.94, green: 0.90, blue: 0.80)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
            ContourGrid(divisions: ContourInkGeometry.gridDivisions)
                .stroke(ink.opacity(0.07), lineWidth: 0.6)
                .padding(10)
            ForEach(map.rings.indices, id: \.self) { k in
                let ring = map.rings[k]
                ContourPolyline(points: ring.points.map(p), closed: true)
                    .trim(from: 0, to: f.ringTrims[k])
                    .stroke(ink.opacity(ring.isIndex ? 0.95 : 0.7),
                            style: StrokeStyle(lineWidth: ring.isIndex ? 2.2 : 1.1, lineCap: .round, lineJoin: .round))
            }
            if let q = f.routeFraction {
                ContourPolyline(points: route.points.map(p), closed: false)
                    .trim(from: 0, to: q)
                    .stroke(Self.red, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: [5, 4]))
                let d = p(route.point(at: q))
                if let pulse = f.pulse {
                    Circle().stroke(Self.red.opacity(0.6 * (1 - pulse)), lineWidth: 1.5)
                        .frame(width: 10 + 44 * pulse, height: 10 + 44 * pulse)
                        .position(d)
                }
                Circle().fill(Self.red).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.6))
                    .position(d)
            }
            if let nib = f.nib {
                let tip = p(map.rings[nib.ring].point(at: nib.fraction))
                Circle().fill(ink).frame(width: 5.5, height: 5.5)
                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 1))
                    .position(tip)
            }
        }
        .frame(width: side, height: side)
    }

    static let red = Color(red: 0.80, green: 0.16, blue: 0.14)
}

/// A polyline as a shape; closed paths include the closing segment, so `.trim` matches the core's arc length.
struct ContourPolyline: Shape {
    var points: [CGPoint]
    var closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for q in points.dropFirst() { path.addLine(to: q) }
        if closed { path.closeSubpath() }
        return path
    }
}

/// A faint survey grid: `divisions` cells across.
struct ContourGrid: Shape {
    var divisions: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 0...divisions {
            let u = CGFloat(i) / CGFloat(divisions)
            path.move(to: CGPoint(x: rect.minX + u * rect.width, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + u * rect.width, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + u * rect.height))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + u * rect.height))
        }
        return path
    }
}

/// Owns the map, the route and the running model; steps the model from the timeline.
final class ContourInkEngine {
    private(set) var model: ContourInkModel
    let map: ContourMap
    let route: ContourRoute
    private var lastDate: Date?

    init(rings: Int) {
        model = ContourInkModel(rings: rings)
        map = ContourMap.make(rings: rings)
        route = ContourRoute.make(map: map)
    }

    func frame(at date: Date, isAnimating: Bool, reduceMotion: Bool) -> ContourFrame {
        model.update(isAnimating: isAnimating, reduceMotion: reduceMotion)
        if model.isStatic { lastDate = nil } else {
            let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
            lastDate = date
            model.step(dt)
        }
        return model.frame
    }
}

#Preview {
    ContourInkLoader()
        .padding(40)
}
#endif
