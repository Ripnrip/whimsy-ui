//  OilPaintRestore.swift
//  OilPaintRestore
//
//  Paint the colour back into a faded photo. The photo starts greyscale and blurred; drag across it
//  and each stroke (sampled with timestamps, brush width from speed) is rendered into a soft-edged
//  Canvas mask that lets the full-colour image through. While wet, a small Metal layerEffect smears
//  the colour along the stroke and another lights the stroke's bristle ridges with an impasto glint.
//  Over ~2 s each stroke dries: the gloss fades to matte and its edge tightens. A light haptic ticks
//  every few strokes. Capture, width, falloff, drying, smear, highlight maths and events live in PaintCore.

#if canImport(SwiftUI)
import SwiftUI
import PaintCore

/// A faded photo you restore with oil-paint strokes.
///
/// ```swift
/// OilPaintRestore()
/// OilPaintRestore(caption: "Lake Orta, 1962")
/// ```
public struct OilPaintRestore: View {
    @State private var engine = PaintEngine()
    @State private var isAnimating = false
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let caption: String

    public static let canvasSize = CGSize(width: 320, height: 420)
    static let cornerRadius: CGFloat = 16

    public init(caption: String = "Lakeside, 1962") {
        self.caption = caption
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            let lib = ShaderLibrary.bundle(.module)
            let pct = Int(m.percentRestored.rounded())
            VStack(spacing: 18) {
                ZStack {
                    // The faded print: greyscale, soft, washed toward the paper colour.
                    PaintingArt()
                        .grayscale(1)
                        .blur(radius: 4)
                        .overlay(Color(red: 0.93, green: 0.90, blue: 0.84).opacity(0.28))
                    // The restored colour, through the stroke mask, smeared while wet.
                    PaintingArt()
                        .mask {
                            Canvas { ctx, _ in PaintRenderer.drawMask(m, in: &ctx, size: Self.canvasSize) }
                        }
                        .layerEffect(lib.paintSmear(.float2(CGPoint(x: m.smear.x, y: m.smear.y))),
                                     maxSampleOffset: CGSize(width: 4, height: 4), isEnabled: m.smear != .zero)
                    // Wet impasto: the bristle height field, lit by the gloss shader.
                    Canvas { ctx, _ in PaintRenderer.drawHeight(m, in: &ctx) }
                        .blur(radius: 1.5)
                        .layerEffect(lib.paintGloss(.float(1)), maxSampleOffset: CGSize(width: 2, height: 2))
                        .allowsHitTesting(false)
                }
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
                .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in
                            engine.drag(to: Vec2(Double(v.location.x), Double(v.location.y)), at: v.time)
                            isAnimating = true
                        }
                        .onEnded { v in
                            engine.end(at: v.time)
                            isAnimating = true
                        }
                )
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                .accessibilityElement()
                .accessibilityLabel("\(caption), faded photo")
                .accessibilityValue("\(pct) percent restored")
                .accessibilityHint("Drag across the photo to paint its colour back.")
                .accessibilityAction(named: "Restore all") { engine.model.restoreAll(); isAnimating = true }
                .accessibilityAction(named: "Reset") { engine.model.reset(); isAnimating = true }

                HStack(spacing: 12) {
                    Text("\(pct)% restored")
                        .font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Color(white: 0.35))
                        .monospacedDigit()
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                    Button("Reset") { engine.model.reset(); isAnimating = true }
                    Button("Restore all") { engine.model.restoreAll(); isAnimating = true }
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(Color(red: 0.55, green: 0.32, blue: 0.20))
                .frame(width: Self.canvasSize.width + 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.96, green: 0.94, blue: 0.90).ignoresSafeArea())
            .onChange(of: m.ticks) { _, n in ticks = n }
            .onChange(of: m.isIdle) { _, idle in if idle { isAnimating = false } }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: ticks)
    }
}

/// Owns the model and maps wall-clock dates (timeline frames and gesture samples alike) to model time.
final class PaintEngine {
    var model = PaintModel(size: Vec2(Double(OilPaintRestore.canvasSize.width), Double(OilPaintRestore.canvasSize.height)))
    private var origin: Date?

    private func seconds(_ date: Date) -> Double {
        if origin == nil { origin = date }
        return date.timeIntervalSince(origin!)
    }

    func frame(at date: Date, reduceMotion: Bool) -> PaintModel {
        model.config.reduceMotion = reduceMotion
        model.advance(to: seconds(date))
        return model
    }

    func drag(to p: Vec2, at date: Date) { model.dragChanged(to: p, at: seconds(date)) }
    func end(at date: Date) { model.dragEnded(at: seconds(date)) }
}

/// Mask and height-field drawing for the strokes.
enum PaintRenderer {
    static func strokePath(_ pts: [Vec2], widths: [Double], in ctx: inout GraphicsContext, color: Color) {
        guard let first = pts.first else { return }
        if pts.count == 1 {
            let r = widths[0] / 2
            ctx.fill(Path(ellipseIn: CGRect(x: first.x - r, y: first.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
            return
        }
        for i in 1..<pts.count {
            var seg = Path()
            seg.move(to: CGPoint(x: pts[i - 1].x, y: pts[i - 1].y))
            seg.addLine(to: CGPoint(x: pts[i].x, y: pts[i].y))
            ctx.stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: (widths[i - 1] + widths[i]) / 2, lineCap: .round, lineJoin: .round))
        }
    }

    /// Each stroke under its own blur: soft while wet, tightening as it dries.
    static func drawMask(_ m: PaintModel, in ctx: inout GraphicsContext, size: CGSize) {
        for s in m.strokes {
            var c = ctx
            c.addFilter(.blur(radius: m.softness(s)))
            strokePath(s.points.map(\.position), widths: s.points.map(\.width), in: &c, color: .white)
        }
        let r = m.restoreOpacity
        if r > 0 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(r))) }
    }

    /// Bristle lines of the wet strokes; their alpha is the impasto height the gloss shader lights.
    static func drawHeight(_ m: PaintModel, in ctx: inout GraphicsContext) {
        for s in m.strokes {
            let wet = m.wetness(s)
            guard wet > 0.005 else { continue }
            for b in s.bristles {
                let color = Color.white.opacity(b.alpha * wet)
                guard let first = b.points.first else { continue }
                if b.points.count == 1 {
                    let r = b.width / 2
                    ctx.fill(Path(ellipseIn: CGRect(x: first.x - r, y: first.y - r, width: 2 * r, height: 2 * r)), with: .color(color))
                    continue
                }
                var line = Path()
                line.move(to: CGPoint(x: first.x, y: first.y))
                for q in b.points.dropFirst() { line.addLine(to: CGPoint(x: q.x, y: q.y)) }
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: b.width, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

/// The photo: a generated lakeside landscape at dusk (gradients, polygons and seeded flowers).
/// Absolute 320 × 420 coordinates so the web port mirrors it exactly.
struct PaintingArt: View {
    static let flowerColors: [Color] = [Color(red: 0.92, green: 0.26, blue: 0.24), Color(red: 0.98, green: 0.84, blue: 0.30),
                                        Color(red: 0.97, green: 0.95, blue: 0.92)]

    static func poly(_ pts: [(Double, Double)]) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: CGPoint(x: q.0, y: q.1)) }
        p.closeSubpath()
        return p
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color { Color(red: r, green: g, blue: b).opacity(a) }
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .linearGradient(
                Gradient(stops: [.init(color: rgb(0.99, 0.60, 0.40), location: 0), .init(color: rgb(1.0, 0.80, 0.55), location: 0.6),
                                 .init(color: rgb(0.98, 0.90, 0.70), location: 1)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: 230)))
            let sun = CGPoint(x: 226, y: 118)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: 240)), with: .radialGradient(
                Gradient(colors: [rgb(1, 0.92, 0.7, 0.55), rgb(1, 0.92, 0.7, 0)]), center: sun, startRadius: 0, endRadius: 90))
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - 30, y: sun.y - 30, width: 60, height: 60)), with: .color(rgb(1, 0.96, 0.78)))
            for (x, y, rx, ry) in [(70.0, 70.0, 46.0, 14.0), (96.0, 62.0, 34.0, 12.0), (260.0, 48.0, 40.0, 10.0)] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry)), with: .color(.white.opacity(0.55)))
            }
            ctx.fill(Self.poly([(0, 206), (40, 170), (92, 190), (150, 150), (205, 182), (262, 158), (320, 188), (320, 240), (0, 240)]),
                     with: .color(rgb(0.52, 0.42, 0.62)))
            ctx.fill(Self.poly([(0, 232), (60, 210), (130, 226), (190, 206), (260, 224), (320, 212), (320, 262), (0, 262)]),
                     with: .color(rgb(0.30, 0.50, 0.46)))
            ctx.fill(Path(CGRect(x: 0, y: 252, width: w, height: 66)), with: .linearGradient(
                Gradient(colors: [rgb(0.40, 0.66, 0.80), rgb(0.20, 0.40, 0.60)]), startPoint: CGPoint(x: 0, y: 252), endPoint: CGPoint(x: 0, y: 318)))
            for (y, sw) in [(262.0, 60.0), (272.0, 46.0), (284.0, 34.0), (298.0, 22.0)] {
                ctx.fill(Path(roundedRect: CGRect(x: sun.x - sw / 2, y: y - 1.5, width: sw, height: 3), cornerRadius: 1.5),
                         with: .color(rgb(1, 0.93, 0.72, 0.7)))
            }
            ctx.fill(Self.poly([(0, 318), (80, 308), (170, 316), (250, 304), (320, 312), (320, 420), (0, 420)]), with: .linearGradient(
                Gradient(colors: [rgb(0.48, 0.66, 0.28), rgb(0.26, 0.44, 0.18)]), startPoint: CGPoint(x: 0, y: 304), endPoint: CGPoint(x: 0, y: 420)))
            for (x, y, rx, ry) in [(52.0, 268.0, 11.0, 46.0), (74.0, 280.0, 9.0, 34.0), (292.0, 276.0, 10.0, 40.0)] {
                ctx.fill(Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry)), with: .color(rgb(0.14, 0.28, 0.18)))
            }
            var rng = SeededRandom(seed: 0xF10E)
            for _ in 0..<46 {
                let x = rng.uniform(8...312), y = rng.uniform(330...410), r = rng.uniform(1.6...3.2)
                let c = Self.flowerColors[min(Int(rng.uniform(0...3)), 2)]
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(c))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    OilPaintRestore()
}
#endif
