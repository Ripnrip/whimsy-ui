//  ChannelFlipCard.swift
//  ChannelFlipCard
//
//  A photo card that changes pictures like an old CRT TV changing channel. Tap for the next photo: for
//  about a third of a second the picture tears sideways in horizontal bands (a new tear on each of a few
//  discrete frames, 15 per second), red and blue pull apart, a bar rolls down the screen, static crackles
//  and the picture flashes toward white. The photo is swapped on the brightest frame, with a light haptic,
//  and then settles. Swipe for next / previous: a slow swipe is a short mild glitch, a fast flick a longer,
//  stronger one (up to 0.7 s). A green "CH 03" number fades in and out like an on-screen display.
//  The effect is one Metal layerEffect (ChannelFlip.metal); the timing, envelope, tears, speed mapping,
//  index wrap and swap moment live in ChannelFlipCore.

#if canImport(SwiftUI)
import SwiftUI
import ChannelFlipCore

/// A photo card that flips channels like a CRT TV.
///
/// ```swift
/// ChannelFlipCard()                                   // six generated photos
/// ChannelFlipCard(images: [Image("a"), Image("b")])   // your own
/// ```
public struct ChannelFlipCard: View {
    @State private var engine: ChannelFlipEngine
    @State private var isAnimating = false
    @State private var switches = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let images: [Image]?
    private let captions: [String]
    private let showsChannelNumber: Bool
    private let staticNoise: Bool

    public static let cardSize = CGSize(width: 300, height: 420)
    public static let cornerRadius: CGFloat = 26

    /// The six generated photos.
    public init(showsChannelNumber: Bool = true, staticNoise: Bool = true) {
        images = nil
        captions = ChannelScenes.names
        self.showsChannelNumber = showsChannelNumber
        self.staticNoise = staticNoise
        _engine = State(initialValue: ChannelFlipEngine(count: ChannelScenes.count))
    }

    /// Your own photos. `captions` (optional) are read by VoiceOver, one per image.
    public init(images: [Image], captions: [String] = [], showsChannelNumber: Bool = true, staticNoise: Bool = true) {
        self.images = images
        self.captions = captions
        self.showsChannelNumber = showsChannelNumber
        self.staticNoise = staticNoise
        _engine = State(initialValue: ChannelFlipEngine(count: images.count))
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            let f = m.frame
            VStack(spacing: 28) {
                screen(m, f)
                Text(reduceMotion ? "Tap or swipe to change photo" : "Tap or swipe to change the channel")
                    .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 0.55).opacity(0.75))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RadialGradient(colors: [Color(red: 0.10, green: 0.14, blue: 0.13), Color(red: 0.02, green: 0.03, blue: 0.03)],
                               center: .center, startRadius: 40, endRadius: 560)
                .ignoresSafeArea()
            )
            .onChange(of: m.switches) { _, s in switches = s }
            .onChange(of: m.announcementCount) { _, _ in
                if m.announcement != nil { AccessibilityNotification.Announcement(spokenText(m)).post() }
            }
            .onChange(of: m.isIdle) { _, idle in if idle { isAnimating = false; engine.pause() } }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: switches)
    }

    private func caption(_ i: Int) -> String {
        i >= 0 && i < captions.count ? captions[i] : "Photo \(i + 1)"
    }

    private func spokenText(_ m: ChannelFlipModel) -> String { "\(m.channelLabel), \(caption(m.index))" }

    private func screen(_ m: ChannelFlipModel, _ f: ChannelFlipModel.Frame) -> some View {
        let size = Self.cardSize
        return ZStack(alignment: .topTrailing) {
            picture(f)
                .frame(width: size.width, height: size.height)
                .layerEffect(
                    ShaderLibrary.bundle(.module).channelFlip(
                        .float2(CGPoint(x: size.width, y: size.height)),
                        .float(f.progress), .float(f.intensity), .float(f.seed), .float(staticNoise ? 1 : 0)),
                    maxSampleOffset: CGSize(width: size.width, height: 0),
                    isEnabled: f.intensity > 0)
            if showsChannelNumber {
                Text(m.channelLabel)
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.35, green: 1.0, blue: 0.45))
                    .shadow(color: Color(red: 0.2, green: 1.0, blue: 0.4).opacity(0.8), radius: 6)
                    .shadow(color: .black.opacity(0.9), radius: 1, x: 2, y: 2)
                    .padding(.top, 18).padding(.trailing, 20)
                    .opacity(m.osdAlpha)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1.5))
        .shadow(color: Color(red: 0.2, green: 1.0, blue: 0.5).opacity(0.10 + 0.3 * f.intensity), radius: 26, y: 12)
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in engine.track(x: Double(v.location.x), at: v.time) }
                .onEnded { v in
                    engine.release(translation: Vec2(Double(v.translation.width), Double(v.translation.height)), at: v.time)
                    isAnimating = true
                }
        )
        .accessibilityElement()
        .accessibilityLabel("Channel flip card")
        .accessibilityValue("\(m.channelLabel), \(caption(m.index)), photo \(m.index + 1) of \(m.count)")
        .accessibilityHint("Tap or swipe to change the channel.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: engine.model.flip(.next)
            case .decrement: engine.model.flip(.previous)
            @unknown default: break
            }
            isAnimating = true
        }
        .accessibilityAction(named: "Next channel") { engine.model.flip(.next); isAnimating = true }
        .accessibilityAction(named: "Previous channel") { engine.model.flip(.previous); isAnimating = true }
    }

    /// The photo on screen: one picture normally, a crossfade under Reduce Motion.
    @ViewBuilder
    private func picture(_ f: ChannelFlipModel.Frame) -> some View {
        if reduceMotion && f.isActive {
            ZStack {
                photo(f.from)
                photo(f.to).opacity(f.crossfade)
            }
        } else {
            photo(f.shown)
        }
    }

    @ViewBuilder
    private func photo(_ i: Int) -> some View {
        if let images, i >= 0, i < images.count {
            images[i].resizable().scaledToFill()
                .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                .clipped()
        } else {
            ChannelScenePhoto(scene: ChannelScenes.scene(i))
        }
    }
}

/// Steps the model from the timeline and tracks the drag; owns no UI.
final class ChannelFlipEngine {
    var model: ChannelFlipModel
    private var lastDate: Date?
    private var tracker = FlipVelocityTracker()
    private var startTime: Date?

    init(count: Int) { model = ChannelFlipModel(count: count) }

    func frame(at date: Date, reduceMotion: Bool) -> ChannelFlipModel {
        model.reduceMotion = reduceMotion
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        model.step(dt)
        return model
    }

    func pause() { lastDate = nil }

    func track(x: Double, at date: Date) {
        if startTime == nil { startTime = date; tracker.reset() }
        tracker.add(x: x, at: date.timeIntervalSinceReferenceDate)
    }

    /// The finger lifted: tap or swipe, with the speed of the last moments of the drag.
    func release(translation: Vec2, at date: Date) {
        let vx = tracker.velocity(endingAt: date.timeIntervalSinceReferenceDate)
        startTime = nil
        tracker.reset()
        model.handle(FlipGestureClassifier.classify(translation: translation, velocity: Vec2(vx, 0)))
    }
}

/// One generated photo, drawn from the core's scene description (card points, 300 x 420).
struct ChannelScenePhoto: View {
    let scene: ChannelScene

    static func color(_ hex: UInt32, _ alpha: Double = 1) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255).opacity(alpha)
    }

    var body: some View {
        Canvas { ctx, size in
            for op in scene.ops {
                switch op.kind {
                case .gradient:
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                        Gradient(colors: [Self.color(op.color), Self.color(op.color2)]),
                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                case .rect:
                    let a = op.points[0], b = op.points[1]
                    ctx.fill(Path(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)), with: .color(Self.color(op.color, op.alpha)))
                case .circle:
                    let c = op.points[0], r = op.size
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Self.color(op.color, op.alpha)))
                case .poly:
                    var p = Path()
                    for (i, v) in op.points.enumerated() {
                        if i == 0 { p.move(to: CGPoint(x: v.x, y: v.y)) } else { p.addLine(to: CGPoint(x: v.x, y: v.y)) }
                    }
                    p.closeSubpath()
                    ctx.fill(p, with: .color(Self.color(op.color, op.alpha)))
                case .line:
                    var p = Path()
                    p.move(to: CGPoint(x: op.points[0].x, y: op.points[0].y)); p.addLine(to: CGPoint(x: op.points[1].x, y: op.points[1].y))
                    ctx.stroke(p, with: .color(Self.color(op.color, op.alpha)), style: StrokeStyle(lineWidth: op.size, lineCap: .butt))
                case .radial:
                    let c = op.points[0], r = op.size
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .radialGradient(
                        Gradient(colors: [Self.color(op.color, op.alpha), Self.color(op.color, 0)]),
                        center: CGPoint(x: c.x, y: c.y), startRadius: 0, endRadius: r))
                }
            }
        }
        .frame(width: ChannelFlipCard.cardSize.width, height: ChannelFlipCard.cardSize.height)
        .accessibilityHidden(true)
    }
}

#Preview {
    ChannelFlipCard()
        .preferredColorScheme(.dark)
}
#endif
