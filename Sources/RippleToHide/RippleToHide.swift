//
//  RippleToHide.swift
//  RippleToHide
//
//  A balance card whose amount hides behind a ripple. Tapping sends a Metal distortionEffect
//  out from the finger: each pixel is pulled along the radius by a damped sine of its distance
//  from the tap, with a spatial falloff. Halfway through, the digits swap for dots. A soft
//  haptic fires as the wavefront passes the far side of the view. Tapping again runs the same
//  wave backward and brings the amount back. Reduce Motion crossfades instead.
//  The wave, the swap, the haptic and the mask live in RippleToHideCore.

#if canImport(SwiftUI)
import SwiftUI
import RippleToHideCore

/// Ripples `content` away to `hidden`, or a balance string away to its dotted mask.
///
/// ```swift
/// RippleToHide(isHidden: $hidden, balance: "$4,820.16")
///
/// RippleToHide(isHidden: $hidden, accessibilityLabel: "Savings balance", shownValue: balance) {
///     BalanceLabel(balance)
/// } hidden: {
///     BalanceLabel(BalanceMask.mask(balance))
/// }
/// ```
///
/// `isHidden` flips when the digits swap, halfway through the trip. Setting it from outside
/// starts a hide or a reveal. A tap during a trip is ignored.
public struct RippleToHide<Content: View, Mask: View>: View {
    @Binding private var isHidden: Bool
    private let content: Content
    private let mask: Mask
    private let accessibilityLabel: String
    private let shownValue: String?

    @State private var model = RippleModel()
    @State private var lastDate: Date?
    @State private var hapticTick = 0
    @State private var viewSize: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isHidden: Binding<Bool>,
        accessibilityLabel: String = "Balance",
        shownValue: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder hidden: () -> Mask
    ) {
        _isHidden = isHidden
        self.content = content()
        self.mask = hidden()
        self.accessibilityLabel = accessibilityLabel
        self.shownValue = shownValue
    }

    public var body: some View {
        TimelineView(.animation(paused: !model.isAnimating)) { timeline in
            ZStack {
                content
                    .opacity(1 - model.maskAmount)
                    .allowsHitTesting(false)
                mask
                    .opacity(model.maskAmount)
                    .allowsHitTesting(false)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { viewSize = proxy.size }
                        .onChange(of: proxy.size) { _, newValue in viewSize = newValue }
                }
            }
            .contentShape(Rectangle())
            .distortionEffect(
                ShaderLibrary.bundle(.module).rippleToHide(
                    .float2(CGPoint(x: model.tap.x, y: model.tap.y)),
                    .float(model.shaderTime),
                    .float(model.shaderAmplitude)
                ),
                maxSampleOffset: CGSize(width: 16, height: 16),
                isEnabled: model.shaderAmplitude != 0
            )
            .gesture(tap)
            .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: hapticTick)
        .onAppear {
            model.reduceMotion = reduceMotion
            if isHidden != model.isHidden { model.snap(hidden: isHidden) }
        }
        .onChange(of: reduceMotion) { _, on in
            if !model.isAnimating { model.reduceMotion = on }
        }
        .onChange(of: isHidden) { _, newValue in
            guard newValue != model.isHidden else { return }
            model.reduceMotion = reduceMotion
            let events = model.setHidden(newValue, at: center, passRadius: radius(at: center))
            if events.isEmpty {
                publishHidden()
            } else {
                note(events, resetClock: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(model.isHidden ? "Hidden" : (shownValue ?? "Visible"))
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint(model.isHidden ? "Shows the amount" : "Hides the amount behind a ripple")
        .accessibilityAction(.default) { toggle(at: center) }
        .accessibilityAction(named: model.isHidden ? "Show balance" : "Hide balance") { toggle(at: center) }
    }

    private var tap: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onEnded { value in
                toggle(at: Vec2(Double(value.location.x), Double(value.location.y)))
            }
    }

    private var center: Vec2 {
        Vec2(Double(viewSize.width) / 2, Double(viewSize.height) / 2)
    }

    private func radius(at point: Vec2) -> Double {
        let bounds = RippleBounds(
            x: 0, y: 0,
            width: Double(viewSize.width),
            height: Double(viewSize.height)
        )
        return RippleWave.passRadius(tap: point, in: bounds, reach: model.rules.reach)
    }

    private func toggle(at point: Vec2) {
        model.reduceMotion = reduceMotion
        note(model.toggle(at: point, passRadius: radius(at: point)), resetClock: true)
    }

    private func advance(to now: Date) {
        guard model.isAnimating else {
            lastDate = nil
            return
        }
        guard let last = lastDate else {
            lastDate = now
            return
        }
        let dt = min(now.timeIntervalSince(last), 0.05)
        lastDate = now
        guard dt > 0 else { return }
        note(model.advance(by: dt), resetClock: false)
    }

    private func note(_ events: [RippleEvent], resetClock: Bool) {
        guard !events.isEmpty else { return }
        if resetClock { lastDate = nil }
        if events.contains(.haptic) { hapticTick += 1 }
        publishHidden()
    }

    private func publishHidden() {
        if isHidden != model.isHidden { isHidden = model.isHidden }
    }
}

extension RippleToHide where Content == RippleBalanceLabel, Mask == RippleBalanceLabel {
    /// The amount, and the same amount with each digit replaced by a bullet.
    public init(isHidden: Binding<Bool>, balance: String, accessibilityLabel: String = "Balance") {
        self.init(isHidden: isHidden, accessibilityLabel: accessibilityLabel, shownValue: balance) {
            RippleBalanceLabel(balance)
        } hidden: {
            RippleBalanceLabel(BalanceMask.mask(balance))
        }
    }
}

/// One line of a balance, set so the dotted mask occupies the same place as the digits.
public struct RippleBalanceLabel: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// The sample card: a dark green balance with a chip, so the ripple has edges to bend.
public struct RippleBalanceCard: View {
    public var amount: String
    public var title: String
    public var account: String

    public init(amount: String = "$4,820.16", title: String = "Everyday", account: String = "···· 4291") {
        self.amount = amount
        self.title = title
        self.account = account
    }

    private static let ink = Color(red: 0.08, green: 0.22, blue: 0.18)
    private static let deep = Color(red: 0.05, green: 0.13, blue: 0.11)
    private static let cream = Color(red: 0.96, green: 0.93, blue: 0.86)
    private static let gold = Color(red: 0.79, green: 0.64, blue: 0.34)

    public var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Self.ink, Self.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Self.cream.opacity(0.06))
                .frame(width: 180, height: 180)
                .offset(x: 170, y: -50)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text(title.uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.4)
                    Spacer()
                    Text(account)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(Self.cream.opacity(0.62))
                Spacer(minLength: 8)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Self.gold)
                    .frame(width: 36, height: 28)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Self.deep.opacity(0.35), lineWidth: 1)
                            .padding(5)
                    }
                Spacer(minLength: 8)
                Text("Available")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Self.cream.opacity(0.55))
                Text(amount)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Self.cream)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(22)
        }
        .frame(width: 300, height: 188)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

/// The gallery sample. Tap the card to hide the balance, then tap again to bring it back.
public struct RippleToHideDemo: View {
    @State private var isHidden = false
    private let balance = "$4,820.16"

    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            RippleToHide(
                isHidden: $isHidden,
                accessibilityLabel: "Everyday checking balance",
                shownValue: balance
            ) {
                RippleBalanceCard(amount: balance)
            } hidden: {
                RippleBalanceCard(amount: BalanceMask.mask(balance))
            }
            .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
            Text(isHidden ? "Tap again to show it" : "Tap the balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.94, green: 0.91, blue: 0.84))
    }
}

#Preview("Ripple to Hide") {
    RippleToHideDemo()
}
#endif
