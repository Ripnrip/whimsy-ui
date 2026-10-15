//  SolarFlareLikeButton.swift
//  SolarFlareLike
//
//  A like button that erupts: on like, the heart pulses 1 → 1.25 → 1 while 7–9 curved,
//  tapering flare ribbons shoot out in a slight swirl with staggered launches, then detach
//  and fade. Unlike is a quick shrink with no flare. Ribbon shapes, timing and the pulse
//  spring live in SolarFlareCore.

#if canImport(SwiftUI)
import SwiftUI
import SolarFlareCore

/// A heart toggle with a solar-flare burst on like.
///
/// The flare is drawn outside the button's frame (a centred square 2.6× its size) and never
/// intercepts touches, so give it some room or let it overlap neighbouring content.
public struct SolarFlareLikeButton: View {
    @Binding private var isLiked: Bool
    private let size: CGFloat
    private let label: Text

    @State private var engine: FlareEngine
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - isLiked: the like state; tapping toggles it.
    ///   - size: heart size in points (default 44, a comfortable tap target).
    ///   - label: accessibility label (default "Like").
    ///   - seed: fixes the flare shapes (default random).
    public init(isLiked: Binding<Bool>, size: CGFloat = 44, label: Text = Text("Like"),
                seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        _isLiked = isLiked
        self.size = size
        self.label = label
        _engine = State(initialValue: FlareEngine(isLiked: isLiked.wrappedValue, seed: seed))
    }

    public var body: some View {
        Button {
            isLiked.toggle()
        } label: {
            TimelineView(.animation(paused: !isAnimating || reduceMotion)) { timeline in
                let frame = engine.frame(at: timeline.date)
                heart
                    .scaleEffect(reduceMotion ? 1 : frame.scale)
                    .overlay {
                        if !reduceMotion && !frame.ribbons.isEmpty {
                            FlareCanvas(ribbons: frame.ribbons, heartRadius: Double(size) / 2)
                                .frame(width: size * 2.6, height: size * 2.6)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .onChange(of: frame.isSettled) { _, settled in
                        if settled { isAnimating = false }
                    }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isLiked) { _, liked in liked }
        .onChange(of: isLiked) { _, liked in
            engine.setLiked(liked, animated: !reduceMotion)
            isAnimating = !reduceMotion
        }
        .accessibilityLabel(label)
        .accessibilityValue(Text(isLiked ? "Liked" : "Not liked"))
        .accessibilityAddTraits(.isToggle)
    }

    private var heart: some View {
        Image(systemName: isLiked ? "heart.fill" : "heart")
            .resizable()
            .scaledToFit()
            .foregroundStyle(
                isLiked
                    ? AnyShapeStyle(LinearGradient(
                        colors: [Color(red: 1.0, green: 0.36, blue: 0.42), Color(red: 0.88, green: 0.12, blue: 0.42)],
                        startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(Color.secondary)
            )
            .frame(width: size, height: size)
            // Reduce Motion: the colour/fill change is the whole effect, softened by a crossfade.
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: isLiked)
    }
}

// MARK: - Engine

struct FlareFrame {
    var scale: Double
    var ribbons: [(ribbon: FlareRibbon, state: RibbonState)]
    var isSettled: Bool
}

/// Holds the deterministic model outside SwiftUI's dependency tracking.
final class FlareEngine {
    private var model: SolarFlareModel
    private var lastDate: Date?

    init(isLiked: Bool, seed: UInt64) { model = SolarFlareModel(isLiked: isLiked, seed: seed) }

    func setLiked(_ liked: Bool, animated: Bool) {
        model.setLiked(liked, animated: animated)
        lastDate = nil
    }

    func frame(at date: Date) -> FlareFrame {
        if let lastDate { model.step(dt: date.timeIntervalSince(lastDate)) }
        lastDate = date
        return FlareFrame(scale: model.scale, ribbons: model.visibleRibbons, isSettled: model.isSettled)
    }
}

// MARK: - Drawing

/// The ribbons, centred in the canvas, each filled with a warm gold → orange → magenta
/// gradient from base to tip. (Normal compositing: an additive blend would wash out to white
/// on light backgrounds.)
struct FlareCanvas: View {
    let ribbons: [(ribbon: FlareRibbon, state: RibbonState)]
    let heartRadius: Double

    static let gradient = Gradient(stops: [
        .init(color: Color(red: 1.00, green: 0.84, blue: 0.30), location: 0),
        .init(color: Color(red: 1.00, green: 0.52, blue: 0.16), location: 0.5),
        .init(color: Color(red: 0.93, green: 0.20, blue: 0.62), location: 1),
    ])

    var body: some View {
        Canvas { context, size in
            let c = Vec2(Double(size.width) / 2, Double(size.height) / 2)
            for (ribbon, state) in ribbons {
                let outline = ribbon.outline(state)
                guard let first = outline.first else { continue }
                var path = Path()
                path.move(to: point(first, c))
                for p in outline.dropFirst() { path.addLine(to: point(p, c)) }
                path.closeSubpath()
                var ctx = context
                ctx.opacity = state.opacity
                ctx.fill(path, with: .linearGradient(
                    Self.gradient,
                    startPoint: point(ribbon.centerline(state.tail), c),
                    endPoint: point(ribbon.centerline(state.head), c)
                ))
            }
        }
    }

    private func point(_ p: Vec2, _ c: Vec2) -> CGPoint {
        CGPoint(x: c.x + p.x * heartRadius, y: c.y + p.y * heartRadius)
    }
}

// MARK: - Preview

private struct SolarFlareDemo: View {
    @State private var isLiked = false
    var body: some View {
        VStack(spacing: 56) {
            // The flare reaches ~1.25× the heart size from its centre; leave it room.
            SolarFlareLikeButton(isLiked: $isLiked, size: 72, seed: 7)
            Text(isLiked ? "Liked" : "Tap the heart")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Solar Flare Like") {
    SolarFlareDemo()
}
#endif
