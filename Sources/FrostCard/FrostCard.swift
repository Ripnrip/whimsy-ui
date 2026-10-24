//  FrostCard.swift
//  FrostCard
//
//  A card that frosts over while you hold it. Ice crystals branch in from the edges as fractal
//  line segments (seeded stems growing inward, children at ~60°, each generation shorter and
//  thinner), drawn in a Canvas driven by TimelineView. Let go and the frost melts back in reverse
//  with a soft blur while little meltwater droplets slide down and fade. A light haptic ticks as
//  new branches spawn. Pattern, growth/melt progress, droplets and spawn events live in FrostCore.

#if canImport(SwiftUI)
import SwiftUI
import FrostCore

/// A card that frosts over while long-pressed and melts when released.
///
/// ```swift
/// FrostCard()
/// FrostCard(title: "NORTH FACE", subtitle: "Base camp · 4,200 m")
/// ```
public struct FrostCard: View {
    @State private var engine = FrostEngine()
    @State private var isAnimating = false
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let title: String
    private let subtitle: String

    public static let cardSize = CGSize(width: 320, height: 200)

    public init(title: String = "GLACIER PASS", subtitle: String = "Day ticket · Zone 3") {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            VStack(spacing: 28) {
                ZStack {
                    FrostCardFace(title: title, subtitle: subtitle)
                    Canvas { ctx, size in
                        FrostRenderer.draw(m, in: &ctx, size: size)
                    }
                    .allowsHitTesting(false)
                }
                .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 22, y: 12)
                .scaleEffect(m.isHeld && !reduceMotion ? 0.985 : 1)
                .animation(.spring(duration: 0.3, bounce: 0.3), value: m.isHeld)
                .onLongPressGesture(minimumDuration: 3600, maximumDistance: 80, perform: {}, onPressingChanged: { pressing in
                    if pressing { engine.model.press() } else { engine.model.release() }
                    isAnimating = true
                })
                .accessibilityElement()
                .accessibilityLabel("\(title) card")
                .accessibilityValue("\(Int((m.progress * 100).rounded())) percent frosted")
                .accessibilityHint("Touch and hold to frost it over.")
                .accessibilityAction(named: m.isHeld ? "Melt" : "Frost over") {
                    if engine.model.isHeld { engine.model.release() } else { engine.model.press() }
                    isAnimating = true
                }

                Text(m.isHeld ? "Keep holding…" : "Hold the card to frost it")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color(white: 0.4))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(colors: [Color(red: 0.95, green: 0.97, blue: 1.0), Color(red: 0.86, green: 0.91, blue: 0.97)],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            )
            .onChange(of: m.ticks) { _, n in ticks = n }
            .onChange(of: m.isIdle) { _, idle in if idle { isAnimating = false; engine.pause() } }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: ticks)
    }
}

/// Steps the model from the timeline; owns no UI.
final class FrostEngine {
    var model = FrostModel(size: Vec2(Double(FrostCard.cardSize.width), Double(FrostCard.cardSize.height)))
    private var lastDate: Date?

    func frame(at date: Date, reduceMotion: Bool) -> FrostModel {
        model.config.reduceMotion = reduceMotion
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        model.step(dt)
        return model
    }

    func pause() { lastDate = nil }
}

/// The printed card under the frost: a dusk-to-ice gradient, generated mountains and a title.
private struct FrostCardFace: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.48), Color(red: 0.22, green: 0.52, blue: 0.74),
                                    Color(red: 0.62, green: 0.86, blue: 0.93)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Canvas { ctx, size in
                let w = size.width, h = size.height
                var far = Path()
                far.move(to: CGPoint(x: 0, y: h * 0.78))
                for (x, y) in [(0.18, 0.5), (0.32, 0.64), (0.5, 0.38), (0.66, 0.6), (0.82, 0.46), (1.0, 0.66)] {
                    far.addLine(to: CGPoint(x: w * x, y: h * y))
                }
                far.addLine(to: CGPoint(x: w, y: h)); far.addLine(to: CGPoint(x: 0, y: h)); far.closeSubpath()
                ctx.fill(far, with: .color(.white.opacity(0.22)))
                var near = Path()
                near.move(to: CGPoint(x: 0, y: h * 0.9))
                for (x, y) in [(0.24, 0.66), (0.42, 0.82), (0.6, 0.6), (0.8, 0.84), (1.0, 0.72)] {
                    near.addLine(to: CGPoint(x: w * x, y: h * y))
                }
                near.addLine(to: CGPoint(x: w, y: h)); near.addLine(to: CGPoint(x: 0, y: h)); near.closeSubpath()
                ctx.fill(near, with: .color(Color(red: 0.10, green: 0.16, blue: 0.36).opacity(0.55)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .tracking(1.5)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Draws haze, crystals and droplets for one frame.
enum FrostRenderer {
    static let generationOpacity = [0.95, 0.85, 0.72, 0.6]

    static func draw(_ m: FrostModel, in ctx: inout GraphicsContext, size: CGSize) {
        let p = m.progress
        let bounds = CGRect(origin: .zero, size: size)
        if p > 0 {
            // Milky haze, thickest at the edges where the frost starts.
            ctx.fill(Path(bounds), with: .color(.white.opacity(0.16 * p)))
            var edge = ctx
            edge.addFilter(.blur(radius: 16))
            edge.stroke(Path(roundedRect: bounds, cornerRadius: 26), with: .color(.white.opacity(0.55 * p)), lineWidth: 44)

            var crystals = ctx
            if m.blurRadius > 0 { crystals.addFilter(.blur(radius: m.blurRadius)) }
            let dim = 1 - 0.25 * m.melt
            for pass in 0..<2 {
                for b in m.pattern.branches {
                    if pass == 0 && b.generation > 1 { continue }
                    // Reduce Motion: no growing lines, the finished pattern just fades in with the progress.
                    let g = m.config.reduceMotion ? 1.0 : b.growth(at: p)
                    guard g > 0 else { continue }
                    var line = Path()
                    line.move(to: CGPoint(x: b.start.x, y: b.start.y))
                    let tip = b.start + b.direction * (b.length * g)
                    line.addLine(to: CGPoint(x: tip.x, y: tip.y))
                    let base = generationOpacity[min(b.generation, generationOpacity.count - 1)] * dim
                        * (m.config.reduceMotion ? p : 1)
                    if pass == 0 {
                        // Soft glow behind stems and first branches.
                        crystals.stroke(line, with: .color(.white.opacity(0.22 * base)),
                                        style: StrokeStyle(lineWidth: b.width * 2.6, lineCap: .round))
                    } else {
                        crystals.stroke(line, with: .color(.white.opacity(base)),
                                        style: StrokeStyle(lineWidth: b.width, lineCap: .round))
                    }
                }
            }
        }
        for d in m.droplets {
            let o = d.opacity
            guard o > 0 else { continue }
            var trail = Path()
            trail.move(to: CGPoint(x: d.position.x, y: d.position.y - d.radius * 4))
            trail.addLine(to: CGPoint(x: d.position.x, y: d.position.y))
            ctx.stroke(trail, with: .color(.white.opacity(0.2 * o)), style: StrokeStyle(lineWidth: d.radius * 0.9, lineCap: .round))
            let r = d.radius
            let drop = Path(ellipseIn: CGRect(x: d.position.x - r, y: d.position.y - r * 1.1, width: 2 * r, height: 2.2 * r))
            ctx.fill(drop, with: .color(Color(red: 0.85, green: 0.94, blue: 1).opacity(0.55 * o)))
            ctx.stroke(drop, with: .color(.white.opacity(0.7 * o)), lineWidth: 0.6)
            let glint = Path(ellipseIn: CGRect(x: d.position.x - r * 0.45, y: d.position.y - r * 0.7, width: r * 0.5, height: r * 0.5))
            ctx.fill(glint, with: .color(.white.opacity(0.9 * o)))
        }
    }
}

#Preview {
    FrostCard()
}
#endif
