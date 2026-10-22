//  ClothPoster.swift
//  ClothPoster
//
//  A poster card that behaves like hanging cloth: drag across it and ripples travel out from
//  your finger, the faster you drag the taller they get. A Metal `distortionEffect` pulls each
//  pixel along the radius by the ripple height (touch position, time and a decaying amplitude
//  are its uniforms), a `colorEffect` shades the slopes and puts a specular sheen on the
//  crests, and a light haptic ticks for every new crest. Let go and the amplitude rings down on
//  an underdamped spring. Wave, lighting and the amplitude/crest model live in ClothPosterCore.

#if canImport(SwiftUI)
import SwiftUI
import ClothPosterCore

/// Any content as a rippling cloth card.
///
/// ```swift
/// ClothPoster()                                         // the sample poster
/// ClothPoster(size: CGSize(width: 280, height: 380)) { Image("gig-poster").resizable() }
/// ```
public struct ClothPoster<Content: View>: View {
    private let size: CGSize
    private let content: Content
    private let label: String
    @State private var engine = ClothEngine()
    @State private var isAnimating = false
    @State private var tickCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room around the card so its edges can ripple outwards.
    static var pad: CGFloat { 14 }

    public init(size: CGSize = CGSize(width: 300, height: 420), accessibilityLabel: String = "Poster",
                @ViewBuilder content: () -> Content) {
        self.size = size
        self.label = accessibilityLabel
        self.content = content()
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let f = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            let lib = ShaderLibrary.bundle(.module)
            let touch = CGPoint(x: f.touch.x, y: f.touch.y)
            content
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(Self.pad)
                .colorEffect(lib.clothSheen(.float2(touch), .float(f.time), .float(f.amplitude)), isEnabled: !f.isSettled)
                .distortionEffect(lib.clothRipple(.float2(touch), .float(f.time), .float(f.amplitude)),
                                  maxSampleOffset: CGSize(width: 12, height: 12), isEnabled: !f.isSettled)
                .onChange(of: f.tickCount) { _, n in tickCount = n }
                .onChange(of: f.isSettled) { _, settled in if settled { isAnimating = false } }
        }
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    engine.touch(Vec2(Double(v.location.x), Double(v.location.y)))
                    isAnimating = true
                }
                .onEnded { _ in engine.release() }
        )
        .sensoryFeedback(trigger: tickCount) { _, _ in
            .impact(weight: .light, intensity: 0.35 + 0.65 * engine.lastTickStrength)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isImage)
        .accessibilityHint("Drag across it to make it ripple.")
        .accessibilityAction(named: "Ripple") {
            engine.poke(at: Vec2(Double(size.width / 2 + Self.pad), Double(size.height / 2 + Self.pad)))
            isAnimating = true
        }
    }
}

extension ClothPoster where Content == PosterArt {
    /// The sample poster.
    public init() {
        self.init(accessibilityLabel: "Poster: Soft Goods, Autumn Linen Fair, 24 to 27 October") { PosterArt() }
    }
}

// MARK: - Sample art

/// A retro screen-print: a striped sun over terracotta, big serif type and a woven texture so
/// the ripples have something to bend.
public struct PosterArt: View {
    public var title: [String]
    public var kicker: String
    public var footer: String

    public init(title: [String] = ["SOFT", "GOODS"], kicker: String = "AUTUMN LINEN FAIR", footer: String = "24 — 27 OCT  ·  HALL 3") {
        self.title = title
        self.kicker = kicker
        self.footer = footer
    }

    static let cream = Color(red: 0.98, green: 0.90, blue: 0.74)
    static let rust = Color(red: 0.72, green: 0.27, blue: 0.18)

    public var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.88, green: 0.45, blue: 0.29), Self.rust], startPoint: .top, endPoint: .bottom)
            // Striped sun.
            Canvas { ctx, size in
                let r = size.width * 0.3, c = CGPoint(x: size.width * 0.66, y: size.height * 0.5)
                let sun = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(sun, with: .color(Self.cream))
                ctx.drawLayer { layer in
                    layer.clip(to: sun)
                    for i in 0..<5 {
                        let h = 3.0 + Double(i) * 2.2, y = c.y + r * 0.1 + Double(i) * 15
                        layer.fill(Path(CGRect(x: c.x - r - 2, y: y, width: 2 * r + 4, height: h)), with: .color(Self.rust.opacity(0.92)))
                    }
                }
                // Hills.
                var hill = Path()
                hill.move(to: CGPoint(x: 0, y: size.height * 0.74))
                hill.addCurve(to: CGPoint(x: size.width, y: size.height * 0.66),
                              control1: CGPoint(x: size.width * 0.35, y: size.height * 0.6),
                              control2: CGPoint(x: size.width * 0.6, y: size.height * 0.78))
                hill.addLine(to: CGPoint(x: size.width, y: size.height)); hill.addLine(to: CGPoint(x: 0, y: size.height)); hill.closeSubpath()
                ctx.fill(hill, with: .color(Color(red: 0.36, green: 0.16, blue: 0.13)))
                // Weave.
                for x in stride(from: 0.0, to: size.width, by: 5) {
                    ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.05)))
                }
                for y in stride(from: 0.0, to: size.height, by: 5) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.black.opacity(0.05)))
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(kicker)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .padding(.bottom, 10)
                ForEach(title, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 66, weight: .black, design: .serif))
                        .tracking(-2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(height: 62, alignment: .bottom)
                }
                Spacer(minLength: 0)
                Rectangle().fill(Self.cream.opacity(0.7)).frame(height: 1).padding(.bottom, 8)
                HStack {
                    Text(footer)
                    Spacer()
                    Text("No. 07")
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1)
            }
            .foregroundStyle(Self.cream)
            .padding(22)
        }
    }
}

// MARK: - Engine

struct ClothFrame {
    var touch: Vec2
    var time: Double
    var amplitude: Double
    var isSettled: Bool
    var tickCount: Int
}

/// Owns the model outside SwiftUI's dependency tracking; the TimelineView steps it by date.
final class ClothEngine {
    private var model = ClothModel()
    private var lastDate: Date?
    private var releaseAt: Date?

    var lastTickStrength: Double { model.lastTickStrength }

    func touch(_ p: Vec2) {
        if model.isTouching { model.touchMoved(to: p) } else { model.touchDown(at: p) }
        releaseAt = nil
    }

    func release() { model.touchUp() }

    /// A short press in the middle (the accessibility action).
    func poke(at p: Vec2) {
        model.touchDown(at: p)
        releaseAt = Date().addingTimeInterval(0.6)
    }

    func frame(at date: Date, reduceMotion: Bool) -> ClothFrame {
        if model.reduceMotion != reduceMotion { model.reduceMotion = reduceMotion }
        if let releaseAt, date >= releaseAt { model.touchUp(); self.releaseAt = nil }
        if let lastDate { model.step(date.timeIntervalSince(lastDate)) }
        let settled = model.isSettled
        lastDate = settled ? nil : date
        return ClothFrame(touch: model.touch, time: model.emitTime, amplitude: model.effectiveAmplitude,
                          isSettled: settled, tickCount: model.tickCount)
    }
}

// MARK: - Preview

private struct ClothPosterDemo: View {
    var body: some View {
        VStack(spacing: 22) {
            ClothPoster()
            Text("Drag across the poster")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color(red: 0.45, green: 0.38, blue: 0.32))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.94, green: 0.91, blue: 0.86).ignoresSafeArea())
    }
}

#Preview("Cloth Poster") {
    ClothPosterDemo()
}
#endif
