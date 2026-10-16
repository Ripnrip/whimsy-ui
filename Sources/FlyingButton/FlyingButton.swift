//  FlyingButton.swift
//  FlyingButton
//
//  A capsule button that takes off: tap it and it behaves like any button; press and hold
//  and it crouches, fires a warm plume of embers and smoke, springs up ~24 pt and hovers
//  with a gentle bob while its shadow shrinks. Let go and it floats down with a tiny bounce.
//  The state machine, lift spring and seeded particle emitter live in FlyingButtonCore.

#if canImport(SwiftUI)
import SwiftUI
import FlyingButtonCore

/// A capsule button with a press-and-hold "liftoff" easter egg.
///
/// A normal tap calls `action`. The plume and shadow are drawn behind the capsule, below its
/// frame (about 60 pt wider and 40 pt taller underneath), and never intercept touches.
public struct FlyingButton: View {
    private let title: Text
    private let action: () -> Void
    private let seed: UInt64

    @State private var engine: FlyingEngine
    @State private var isPressing = false
    @State private var isAnimating = false
    @State private var liftoffs = 0
    @State private var touchdowns = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Canvas geometry (points): the ground origin sits `plumeAbove` from the canvas top.
    private static let plumeSize = CGSize(width: 200, height: 96)
    private static let plumeAbove: CGFloat = 56

    /// - Parameters:
    ///   - title: the button's label, also used as its accessibility label.
    ///   - seed: fixes the plume pattern (default random).
    ///   - action: called on a normal tap (and by VoiceOver's activate).
    public init(_ title: LocalizedStringKey, seed: UInt64 = UInt64.random(in: 0...UInt64.max),
                action: @escaping () -> Void) {
        self.init(Text(title), seed: seed, action: action)
    }

    /// Creates the button from a ready-made `Text`.
    public init(_ title: Text, seed: UInt64 = UInt64.random(in: 0...UInt64.max),
                action: @escaping () -> Void) {
        self.title = title
        self.action = action
        self.seed = seed
        _engine = State(initialValue: FlyingEngine(seed: seed))
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating || reduceMotion)) { timeline in
            let frame = engine.frame(at: timeline.date)
            capsule
                .scaleEffect(x: 1, y: reduceMotion ? 1 : frame.stretch, anchor: .bottom)
                .offset(y: reduceMotion ? 0 : -frame.lift)
                // Reduce Motion: a soft fade while held replaces the flight.
                .opacity(reduceMotion && isPressing ? 0.55 : 1)
                .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: isPressing)
                .background(alignment: .bottom) {
                    if !reduceMotion {
                        PlumeCanvas(particles: frame.particles, shadowScale: frame.shadowScale,
                                    shadowOpacity: frame.shadowOpacity, floor: frame.floor,
                                    groundY: Self.plumeAbove)
                            .frame(width: Self.plumeSize.width, height: Self.plumeSize.height)
                            .offset(y: Self.plumeSize.height - Self.plumeAbove)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .onChange(of: frame.liftoffCount) { _, n in liftoffs = n }
                .onChange(of: frame.touchdownCount) { _, n in touchdowns = n }
                .onChange(of: frame.isSettled) { _, settled in
                    if settled && !isPressing { isAnimating = false }
                }
        }
        .contentShape(Capsule())
        .onTapGesture(perform: action)
        .onLongPressGesture(minimumDuration: FlyingButtonModel.Tuning.default.thrustDuration,
                            maximumDistance: 40, perform: {}) { pressing in
            isPressing = pressing
            guard !reduceMotion else { return }
            if pressing { engine.pressBegan() } else { engine.pressEnded() }
            isAnimating = true
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: liftoffs)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: touchdowns)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(action)
    }

    private var capsule: some View {
        title
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule().fill(LinearGradient(
                    colors: [Color(red: 0.36, green: 0.42, blue: 1.0), Color(red: 0.42, green: 0.22, blue: 0.86)],
                    startPoint: .top, endPoint: .bottom))
            )
    }
}

// MARK: - Engine

struct FlyingFrame {
    var lift: CGFloat
    var stretch: CGFloat
    var particles: [PlumeParticle]
    var shadowScale: Double
    var shadowOpacity: Double
    var floor: Double
    var liftoffCount: Int
    var touchdownCount: Int
    var isSettled: Bool
}

/// Holds the deterministic model outside SwiftUI's dependency tracking.
final class FlyingEngine {
    private var model: FlyingButtonModel
    private var lastDate: Date?

    init(seed: UInt64) { model = FlyingButtonModel(seed: seed) }

    func pressBegan() { model.pressBegan() }
    func pressEnded() { model.pressEnded() }

    func frame(at date: Date) -> FlyingFrame {
        if let lastDate { model.step(date.timeIntervalSince(lastDate)) }
        lastDate = model.isSettled ? nil : date
        return FlyingFrame(lift: CGFloat(model.lift), stretch: CGFloat(model.stretch),
                           particles: model.particles, shadowScale: model.shadowScale,
                           shadowOpacity: model.shadowOpacity, floor: model.tuning.floor,
                           liftoffCount: model.liftoffCount, touchdownCount: model.touchdownCount,
                           isSettled: model.isSettled)
    }
}

// MARK: - Drawing

/// Contact shadow plus exhaust puffs. Hot puffs glow ember-yellow → orange; cooling ones
/// turn into translucent warm-grey smoke.
struct PlumeCanvas: View {
    let particles: [PlumeParticle]
    let shadowScale: Double
    let shadowOpacity: Double
    let floor: Double
    /// Canvas y of the ground-frame origin (the resting capsule's bottom edge).
    let groundY: CGFloat

    static func color(heat: Double) -> (r: Double, g: Double, b: Double) {
        let ember = (1.0, 0.86, 0.42), flame = (1.0, 0.47, 0.16), smoke = (0.56, 0.50, 0.49)
        func mix(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (r: Double, g: Double, b: Double) {
            (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }
        return heat > 0.6 ? mix(flame, ember, (heat - 0.6) / 0.4) : mix(smoke, flame, heat / 0.6)
    }

    var body: some View {
        Canvas { context, size in
            let cx = size.width / 2
            // Shadow on the floor line.
            let sw = 120 * shadowScale, sh = 12 * shadowScale
            let shadow = CGRect(x: cx - sw / 2, y: groundY + floor - sh / 2, width: sw, height: sh)
            context.fill(Path(ellipseIn: shadow), with: .radialGradient(
                Gradient(colors: [.black.opacity(shadowOpacity), .black.opacity(0)]),
                center: CGPoint(x: shadow.midX, y: shadow.midY), startRadius: 0, endRadius: sw / 2))
            // Oldest first so fresh embers sit on top of the smoke.
            for p in particles.sorted(by: { $0.age > $1.age }) {
                let c = Self.color(heat: p.heat)
                let center = CGPoint(x: cx + p.position.x, y: groundY + p.position.y)
                let r = p.radius
                let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
                let col = Color(red: c.r, green: c.g, blue: c.b)
                context.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(stops: [.init(color: col.opacity(p.opacity), location: 0),
                                     .init(color: col.opacity(p.opacity * 0.8), location: 0.45),
                                     .init(color: col.opacity(0), location: 1)]),
                    center: center, startRadius: 0, endRadius: r))
            }
        }
    }
}

// MARK: - Preview

private struct FlyingButtonDemo: View {
    @State private var taps = 0
    var body: some View {
        VStack(spacing: 64) {
            FlyingButton("Launch", seed: 11) { taps += 1 }
            Text(taps == 0 ? "Tap, or press and hold" : "Tapped \(taps)×")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Flying Button") {
    FlyingButtonDemo()
}
#endif
