//
//  CardToPillGlassMorph.swift
//  CardToPillGlassMorph
//
//  A frosted glass pay card, leaned −3°, with an amber orb and a red orb behind it.
//  Pay springs the glass into a pill and the two lights dock inside it as a two-dot
//  mark. About a second later the pill opens back into the card with a half-turn.
//  One success haptic fires as the lights settle. Reduce Motion crossfades the two
//  poses and does not spring or turn.
//  The clock, the spring and the light paths live in GlassMorphCore.

#if canImport(SwiftUI)
@_exported import GlassMorphCore
import SwiftUI

/// A glass pay card that condenses into a pill.
///
/// ```swift
/// CardToPillGlassMorph()
/// CardToPillGlassMorph(amount: "$48.00", label: "Solune") { recordPayment() }
/// ```
///
/// `onPaid` fires once, with the success haptic, when the lights settle into the mark.
public struct CardToPillGlassMorph: View {
    private let amount: String
    private let label: String
    private let payTitle: String
    private let amberColor: GlassRGB
    private let redColor: GlassRGB
    private let onPaid: () -> Void

    @State private var model = GlassMorphModel()
    @State private var lastDate: Date? = nil
    @State private var hapticTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(amount: String = GlassMorphTuning.defaultAmount,
                label: String = GlassMorphTuning.defaultLabel,
                payTitle: String = GlassMorphTuning.payTitle,
                amber: GlassRGB = GlassMorphTuning.amber,
                red: GlassRGB = GlassMorphTuning.red,
                onPaid: @escaping () -> Void = {}) {
        self.amount = amount
        self.label = label
        self.payTitle = payTitle
        self.amberColor = amber
        self.redColor = red
        self.onPaid = onPaid
    }

    public var body: some View {
        TimelineView(.animation(paused: model.isAtRest)) { timeline in
            stage
                .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
        .frame(width: GlassMorphTuning.canvasWidth, height: GlassMorphTuning.canvasHeight)
        .clipped()
        .onAppear { model.setReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .sensoryFeedback(.success, trigger: hapticTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(amount)")
        .accessibilityValue(model.accessibilityValue)
        .accessibilityHint(model.phase == .card ? "Double tap to pay" : "Payment in progress")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { beginPay() }
        .accessibilityAction(named: payTitle) { beginPay() }
    }

    private var stage: some View {
        ZStack {
            background
            if model.reduceMotion {
                pose(progress: 0, textOpacity: 1, dotOpacity: 0, glow: 1, edge: 0)
                    .opacity(1 - model.crossfade)
                pose(progress: 1, textOpacity: 0, dotOpacity: 1, glow: 0, edge: 0)
                    .opacity(model.crossfade)
                    .allowsHitTesting(false)
            } else {
                pose(progress: model.progress,
                     textOpacity: model.cardContentOpacity,
                     dotOpacity: model.dotOpacity,
                     glow: model.glowOpacity,
                     edge: model.edgeGlow,
                     flip: model.displayFlip)
            }
        }
    }

    private var background: some View {
        LinearGradient(colors: [Color(GlassMorphTuning.backgroundTop), Color(GlassMorphTuning.backgroundBottom)],
                       startPoint: .top, endPoint: .bottom)
    }

    private func pose(progress: Double,
                      textOpacity: Double,
                      dotOpacity: Double,
                      glow: Double,
                      edge: Double,
                      flip: Double = 0) -> some View {
        let frame = GlassMorphLayout.frame(progress: progress)
        let amber = GlassMorphLayout.light(.amber, progress: progress)
        let red = GlassMorphLayout.light(.red, progress: progress)
        return ZStack {
            orb(amber, color: amberColor, opacity: glow)
            orb(red, color: redColor, opacity: glow)
            glass(frame, amber: amber, red: red, textOpacity: textOpacity, dotOpacity: dotOpacity, flip: flip)
            Capsule()
                .fill(Color.white.opacity(0.9))
                .frame(width: 3, height: max(12, frame.height * 0.72))
                .rotationEffect(.radians(frame.tilt))
                .position(x: frame.center.x, y: frame.center.y)
                .opacity(edge)
                .allowsHitTesting(false)
        }
    }

    /// A backdrop orb in stage space. It stays in the room while the glass turns.
    private func orb(_ light: GlassLight, color: GlassRGB, opacity: Double) -> some View {
        Circle()
            .fill(Color(color))
            .frame(width: light.radius * 2, height: light.radius * 2)
            .blur(radius: light.blur)
            .opacity(opacity)
            .position(x: light.center.x, y: light.center.y)
            .allowsHitTesting(false)
    }

    private func glass(_ frame: GlassMorphFrame, amber: GlassLight, red: GlassLight,
                       textOpacity: Double, dotOpacity: Double, flip: Double) -> some View {
        let sx = frame.width / GlassMorphTuning.cardWidth
        let sy = frame.height / GlassMorphTuning.cardHeight
        return ZStack {
            face(textOpacity: textOpacity)
        }
        .frame(width: GlassMorphTuning.cardWidth, height: GlassMorphTuning.cardHeight)
        .scaleEffect(x: max(0.02, sx), y: max(0.02, sy))
        .frame(width: frame.width, height: frame.height)
        .overlay {
            ZStack {
                mark(amber, color: amberColor, in: frame, opacity: dotOpacity)
                mark(red, color: redColor, in: frame, opacity: dotOpacity)
            }
        }
        .modifier(FrostedGlass(cornerRadius: frame.cornerRadius))
        .rotation3DEffect(.radians(flip), axis: (x: 0, y: 1, z: 0), perspective: 0.65)
        .rotationEffect(.radians(frame.tilt))
        .shadow(color: .black.opacity(0.34), radius: 28, y: 16)
        .position(x: frame.center.x, y: frame.center.y)
    }

    /// A logo dot in the glass's own points, drawn after the card face has been scaled
    /// down, so the half-turn carries it at the size the core specifies.
    private func mark(_ light: GlassLight, color: GlassRGB, in frame: GlassMorphFrame, opacity: Double) -> some View {
        Circle()
            .fill(Color(color))
            .frame(width: light.radius * 2, height: light.radius * 2)
            .position(x: frame.width / 2 + (light.center.x - frame.center.x),
                      y: frame.height / 2 + (light.center.y - frame.center.y))
            .opacity(opacity)
            .allowsHitTesting(false)
    }

    private func face(textOpacity: Double) -> some View {
        ZStack {
            brand.position(x: GlassMorphTuning.cardWidth / 2,
                           y: GlassMorphTuning.cardHeight / 2 + GlassMorphTuning.brandLocalY)
            Text(amount)
                .font(.system(size: GlassMorphTuning.amountSize, weight: .light, design: .rounded))
                .foregroundStyle(.white)
                .position(x: GlassMorphTuning.cardWidth / 2,
                          y: GlassMorphTuning.cardHeight / 2 + GlassMorphTuning.amountLocalY)
            Text(GlassMorphTuning.caption)
                .font(.system(size: GlassMorphTuning.captionSize, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .position(x: GlassMorphTuning.cardWidth / 2,
                          y: GlassMorphTuning.cardHeight / 2 + GlassMorphTuning.captionLocalY)
            payButton
                .position(x: GlassMorphTuning.cardWidth / 2,
                          y: GlassMorphTuning.cardHeight / 2 + GlassMorphTuning.payButtonLocal.y)
        }
        .opacity(textOpacity)
        .allowsHitTesting(model.phase == .card && textOpacity > 0.5)
    }

    private var brand: some View {
        Text(label.uppercased())
            .font(.system(size: GlassMorphTuning.brandSize, weight: .semibold, design: .rounded))
            .tracking(2.6)
            .foregroundStyle(.white.opacity(0.82))
    }

    private var payButton: some View {
        Button(action: beginPay) {
            Text(payTitle)
                .font(.system(size: GlassMorphTuning.paySize, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(GlassMorphTuning.ink))
                .frame(width: GlassMorphTuning.payButtonWidth, height: GlassMorphTuning.payButtonHeight)
                .background(Capsule().fill(Color.white.opacity(0.94)))
        }
        .buttonStyle(.plain)
        .disabled(model.phase != .card)
    }

    private func beginPay() {
        handle(model.pay())
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        handle(model.step(now.timeIntervalSince(last)))
    }

    private func handle(_ events: [GlassMorphEvent]) {
        for event in events {
            if event == .settled {
                hapticTick += 1
                onPaid()
                AccessibilityNotification.Announcement(GlassMorphTuning.announcement).post()
            }
        }
    }
}

/// Liquid Glass where the OS has it, otherwise the ultra-thin material.
private struct FrostedGlass: ViewModifier {
    var cornerRadius: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, macOS 26, *) {
            content
                .clipShape(shape)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.42), lineWidth: 1))
                .clipShape(shape)
        }
    }
}

private extension Color {
    init(_ rgb: GlassRGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// The gallery page: Solune's pay card on the navy field.
public struct CardToPillGlassMorphDemo: View {
    public init() {}

    public var body: some View {
        ZStack {
            LinearGradient(colors: [Color(GlassMorphTuning.backgroundTop), Color(GlassMorphTuning.backgroundBottom)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            CardToPillGlassMorph()
        }
    }
}

#Preview("Glass pay") { CardToPillGlassMorphDemo() }
#endif
