//  TiltPhotoGrid.swift
//  TiltPhotoGrid
//
//  A kinetic-type intro (heavy black italic words slamming in, hard-cutting through three
//  phrases) that vanishes to reveal a masonry grid of generated gradient portraits. The grid is
//  one 3D plane: it tilts and pans away from your finger (or with device motion on iPhone)
//  through `rotation3DEffect` with perspective on springs, and every card floats at its own
//  depth for parallax. Timeline, masonry layout, portraits and tilt springs live in TiltGridCore.

#if canImport(SwiftUI)
import SwiftUI
import TiltGridCore
#if os(iOS) && !targetEnvironment(simulator)
import CoreMotion
#endif

/// An intro that cuts through a few phrases, then a tilting masonry photo grid.
///
/// ```swift
/// TiltPhotoGrid()
/// TiltPhotoGrid(phrases: ["NORTH WIND", "FIELD NOTES 2026"], useDeviceMotion: false)
/// ```
public struct TiltPhotoGrid: View {
    @State private var engine: TiltEngine
    @State private var isAnimating = true
    @State private var cuts = 0
    @State private var finished = false
    private let useDeviceMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS) && !targetEnvironment(simulator)
    @State private var motion = MotionInput()
    #endif

    public init(phrases: [String] = ["WHIMSY STUDIO", "PHOTO ALBUM 2026", "2026 SHOWCASE APERTURE"], useDeviceMotion: Bool = true) {
        _engine = State(initialValue: TiltEngine(intro: KineticIntro(phrases: phrases)))
        self.useDeviceMotion = useDeviceMotion
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                let f = engine.frame(at: timeline.date, size: proxy.size, reduceMotion: reduceMotion)
                ZStack {
                    Color.white
                    plane(f, size: proxy.size)
                    if let phrase = f.intro.phrase {
                        introText(phrase: phrase, f: f)
                    }
                }
                .onChange(of: f.intro.cuts) { _, n in cuts = n }
                .onChange(of: f.intro.isFinished) { _, done in finished = done }
                .onChange(of: f.isIdle) { _, idle in if idle { isAnimating = false } }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        engine.setFinger(PlaneTilt.normalized(Vec2(Double(v.location.x), Double(v.location.y)),
                                                              in: Vec2(Double(proxy.size.width), Double(proxy.size.height))))
                        isAnimating = true
                    }
                    .onEnded { _ in engine.setFinger(nil); isAnimating = true }
            )
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if finished {
                Button {
                    engine.restart()
                    finished = false
                    isAnimating = true
                } label: {
                    Label("Replay intro", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 38)
                        .background(.black, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: finished)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: cuts)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(finished ? "Photo album, \(engine.grid.cards.count) portraits" : engine.intro.phrases.map { $0.joined(separator: " ") }.joined(separator: ", "))
        .accessibilityAction(named: "Skip intro") { engine.skipIntro(); isAnimating = true }
        .accessibilityAction(named: "Replay intro") { engine.restart(); isAnimating = true }
        .onAppear { startMotion() }
        .onDisappear { stopMotion() }
    }

    // MARK: Pieces

    private func introText(phrase: Int, f: TiltFrame) -> some View {
        let words = engine.intro.phrases[phrase]
        let v = KineticIntro.vanish(f.intro.outro)
        return VStack(alignment: .leading, spacing: -14) {
            ForEach(0..<f.intro.words, id: \.self) { i in
                Text(words[i])
                    .font(.system(size: 92, weight: .black))
                    .italic()
                    .tracking(-3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.3)
                    .foregroundStyle(.black)
                    .scaleEffect(i == f.intro.words - 1 && !reduceMotion ? KineticIntro.slamScale(sinceCut: f.intro.sinceCut) : 1,
                                 anchor: .leading)
            }
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .scaleEffect(v.scale)
        .offset(y: v.rise)
        .opacity(v.opacity)
        .id(phrase)   // a hard cut, not a morph
    }

    private func plane(_ f: TiltFrame, size: CGSize) -> some View {
        let grid = engine.grid
        let origin = Vec2(grid.width / 2, grid.height / 2)
        return ZStack(alignment: .topLeading) {
            ForEach(grid.cards, id: \.index) { card in
                let p = TiltEngine.reveal(f.intro.reveal - grid.revealDelay(of: card, from: origin))
                let par = f.parallax(card.depth)
                PortraitCard(spec: card.portrait)
                    .frame(width: card.width, height: card.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.08 + 0.14 * card.depth), radius: 5 + 9 * card.depth, x: 0, y: 3 + 9 * card.depth)
                    .scaleEffect(0.6 + 0.4 * p)
                    .opacity(min(max(p * 1.6, 0), 1))
                    .offset(x: card.x + par.x, y: card.y + par.y + (1 - p) * 50)
            }
        }
        .frame(width: grid.width, height: grid.height, alignment: .topLeading)
        .offset(x: f.pan.x, y: f.pan.y)
        .rotation3DEffect(.degrees(f.tilt.y), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        .rotation3DEffect(.degrees(f.tilt.x), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: Device motion

    private func startMotion() {
        #if os(iOS) && !targetEnvironment(simulator)
        guard useDeviceMotion else { return }
        let engine = engine
        motion.start { n in
            engine.setMotion(n)
            isAnimating = true
        }
        #endif
    }

    private func stopMotion() {
        #if os(iOS) && !targetEnvironment(simulator)
        motion.stop()
        #endif
    }
}

#if os(iOS) && !targetEnvironment(simulator)
/// Device attitude → the same −1…1 input as a finger.
@MainActor
final class MotionInput {
    private let manager = CMMotionManager()

    func start(_ handler: @escaping @MainActor (Vec2) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let a = data?.attitude else { return }
            let n = MotionTilt.normalized(pitch: a.pitch, roll: a.roll)
            MainActor.assumeIsolated { handler(n) }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
#endif

// MARK: - Portrait

/// A generated "photo": a gradient backdrop with a sitter drawn from shapes.
struct PortraitCard: View {
    let spec: PortraitSpec

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let bg = Gradient(colors: [Color(hue: spec.backgroundTop, saturation: 0.38, brightness: 0.97),
                                       Color(hue: spec.backgroundBottom, saturation: 0.55, brightness: 0.78)])
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(bg, startPoint: .zero, endPoint: CGPoint(x: w * 0.3, y: h)))
            let cx = w * (0.5 + spec.lean), headR = w * 0.17, headY = h * 0.47
            let skinRGB = PortraitSpec.skinTones[spec.skin]
            let skin = Color(red: skinRGB.r, green: skinRGB.g, blue: skinRGB.b)
            let hair = Color(hue: spec.hairHue, saturation: 0.55, brightness: 0.22 + 0.25 * Double(spec.skin % 3) / 2)
            let shirt = Color(hue: spec.shirtHue, saturation: 0.5, brightness: 0.62)
            // Long hair and bobs sit behind the head.
            if spec.hairStyle == 3 {
                ctx.fill(Path(roundedRect: CGRect(x: cx - headR * 1.25, y: headY - headR * 1.15, width: headR * 2.5, height: headR * 3.2),
                              cornerRadius: headR * 1.1), with: .color(hair))
            } else if spec.hairStyle == 1 {
                ctx.fill(Path(roundedRect: CGRect(x: cx - headR * 1.25, y: headY - headR * 1.2, width: headR * 2.5, height: headR * 2.2),
                              cornerRadius: headR * 0.9), with: .color(hair))
            }
            // Shoulders.
            ctx.fill(Path(ellipseIn: CGRect(x: cx - w * 0.42, y: h * 0.72, width: w * 0.84, height: h * 0.5)), with: .color(shirt))
            // Neck and head.
            ctx.fill(Path(roundedRect: CGRect(x: cx - headR * 0.42, y: headY + headR * 0.6, width: headR * 0.84, height: headR * 1.3),
                          cornerRadius: headR * 0.3), with: .color(skin.opacity(0.92)))
            ctx.fill(Path(ellipseIn: CGRect(x: cx - headR, y: headY - headR * 1.1, width: headR * 2, height: headR * 2.2)), with: .color(skin))
            // Hair on top.
            var cap = Path()
            cap.addArc(center: CGPoint(x: cx, y: headY - headR * 0.15), radius: headR * 1.04,
                       startAngle: .degrees(185), endAngle: .degrees(355), clockwise: false)
            cap.closeSubpath()
            ctx.fill(cap, with: .color(hair))
            if spec.hairStyle == 2 {
                ctx.fill(Path(ellipseIn: CGRect(x: cx - headR * 0.5, y: headY - headR * 2.05, width: headR, height: headR * 0.9)), with: .color(hair))
            }
            // Soft window light and a vignette.
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.28), .clear]),
                                           center: CGPoint(x: w * 0.2, y: h * 0.15), startRadius: 0, endRadius: w))
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [.clear, .black.opacity(0.18)]),
                                           startPoint: CGPoint(x: 0, y: h * 0.6), endPoint: CGPoint(x: 0, y: h)))
        }
    }
}

// MARK: - Engine

struct TiltFrame {
    var intro: KineticIntro.Frame
    var tilt: Vec2
    var pan: Vec2
    var parallax: (Double) -> Vec2
    var isIdle: Bool
}

/// Owns the timeline and springs outside SwiftUI's dependency tracking.
final class TiltEngine {
    let intro: KineticIntro
    let grid = MasonryGrid()
    private var tilt = PlaneTilt()
    private var start: Date?
    private var lastDate: Date?
    private var finger: Vec2?
    private var motion: Vec2?

    init(intro: KineticIntro) { self.intro = intro }

    func setFinger(_ n: Vec2?) { finger = n; tilt.setInput(finger ?? motion) }
    func setMotion(_ n: Vec2?) { motion = n; if finger == nil { tilt.setInput(n) } }
    func restart() { start = nil }
    func skipIntro() { start = Date().addingTimeInterval(-intro.duration) }

    /// Card reveal: a slightly bouncy step response (0.6 s spring).
    static func reveal(_ t: Double) -> Double {
        WhimsySpring.stepResponse(at: t, stiffness: pow(2 * .pi / 0.6, 2), dampingRatio: 0.75)
    }

    func frame(at date: Date, size: CGSize, reduceMotion: Bool) -> TiltFrame {
        if start == nil { start = date }
        if tilt.reduceMotion != reduceMotion { tilt.reduceMotion = reduceMotion }
        if let lastDate { tilt.step(date.timeIntervalSince(lastDate)) }
        lastDate = date
        let t = date.timeIntervalSince(start!)
        let f = intro.frame(at: t)
        let revealDone = f.reveal > 1.5 + grid.height * 0.0011
        let idle = f.isFinished && revealDone && tilt.isSettled && finger == nil && motion == nil
        if idle { lastDate = nil }
        let snapshot = tilt
        return TiltFrame(intro: f, tilt: tilt.tilt.value, pan: tilt.pan.value,
                         parallax: { snapshot.parallax(depth: $0) }, isIdle: idle)
    }
}

// MARK: - Preview

#Preview("Tilt Photo Grid") {
    TiltPhotoGrid(useDeviceMotion: false)
}
#endif
