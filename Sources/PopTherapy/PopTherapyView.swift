//  PopTherapyView.swift
//  PopTherapy
//
//  A tactile bubble-wrap / pop-it toy. One Canvas draws every bubble; a drag pops
//  every bubble it crosses (interpolated in PopTherapyCore so fast swipes never skip),
//  each pop gets a keyframed squish + wobble, a light randomized haptic, and a Metal
//  gloss highlight drifts across the sheet. Pop them all to unwrap a gift.

#if canImport(SwiftUI)
import SwiftUI
import PopTherapyCore

/// Bubble-wrap therapy. Drop it anywhere; it sizes itself to a 6:8 aspect ratio.
public struct PopTherapyView: View {
    @State private var grid: PopGrid
    @State private var tracker = DragPopTracker()
    /// When each recently popped cell was popped; drives the per-cell squish.
    @State private var popDates: [Int: Date] = [:]
    @State private var feedbackIntensity: Double = 0.7
    @State private var popTick = 0
    @State private var startDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let squish = PopSquish.timeline

    public init(columns: Int = PopGrid.defaultColumns, rows: Int = PopGrid.defaultRows) {
        _grid = State(initialValue: PopGrid(columns: columns, rows: rows))
    }

    public var body: some View {
        ZStack {
            bubbleSheet
                .opacity(grid.allPopped ? 0 : 1)
                .allowsHitTesting(!grid.allPopped)

            if grid.allPopped {
                GiftReveal(onReset: reset)
                    .transition(.opacity)
            }
        }
        .aspectRatio(CGFloat(grid.columns) / CGFloat(grid.rows), contentMode: .fit)
        .animation(.easeInOut(duration: 0.35), value: grid.allPopped)
        .sensoryFeedback(.impact(weight: .light, intensity: feedbackIntensity), trigger: popTick)
    }

    // MARK: Bubble sheet

    private var bubbleSheet: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation(paused: grid.allPopped)) { timeline in
                let now = timeline.date
                let shaderTime = Float(now.timeIntervalSince(startDate))
                // Snapshot state into plain values for the renderer closure.
                let gridSnapshot = grid
                let popDatesSnapshot = popDates
                let squishTimeline = squish
                let animatePops = !reduceMotion

                Canvas { context, canvasSize in
                    BubbleRenderer.draw(
                        in: &context,
                        size: canvasSize,
                        grid: gridSnapshot,
                        popDates: popDatesSnapshot,
                        now: now,
                        squish: squishTimeline,
                        animatePops: animatePops
                    )
                }
                .colorEffect(
                    ShaderLibrary.bundle(.module).glossSweep(.boundingRect, .float(shaderTime)),
                    isEnabled: !reduceMotion
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        // First sample of a new drag: never connect to a previous
                        // (possibly cancelled) gesture's last point.
                        if value.translation == .zero { tracker.end() }
                        handleDrag(at: value.location, in: size)
                    }
                    .onEnded { _ in tracker.end() }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bubble wrap")
        .accessibilityValue("\(grid.popped.count) of \(grid.cellCount) popped")
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAction(named: "Pop a bubble") { popNextForAccessibility() }
        .accessibilityAction(named: "Reset") { reset() }
    }

    // MARK: Interaction

    private func handleDrag(at location: CGPoint, in size: CGSize) {
        var grid = self.grid
        var tracker = self.tracker
        let newlyPopped = tracker.update(
            GridPoint(x: Double(location.x), y: Double(location.y)),
            grid: &grid,
            size: GridSize(width: Double(size.width), height: Double(size.height))
        )
        self.tracker = tracker
        guard !newlyPopped.isEmpty else { return }
        registerPops(newlyPopped, grid: grid)
    }

    private func registerPops(_ cells: [Int], grid: PopGrid) {
        let now = Date()
        // Forget pops whose squish has finished; they render at rest from here on.
        var dates = popDates.filter { now.timeIntervalSince($0.value) < squish.duration }
        for cell in cells { dates[cell] = now }
        popDates = dates
        self.grid = grid
        feedbackIntensity = PopGrid.feedbackIntensity()
        popTick &+= 1
    }

    private func popNextForAccessibility() {
        guard let next = (0..<grid.cellCount).first(where: { !grid.isPopped($0) }) else { return }
        var grid = self.grid
        grid.pop(next)
        registerPops([next], grid: grid)
    }

    private func reset() {
        tracker.end()
        popDates = [:]
        grid.reset()
        startDate = Date()
    }
}

// MARK: - Squish keyframes

/// Animated per-bubble transform: overall scale plus a wobble that squashes one axis
/// while stretching the other.
struct PopSquish {
    var scale: Double = 1
    var wobble: Double = 0

    /// Resting scale of a popped (deflated) bubble once the animation has settled.
    static let restScale: Double = 0.9

    /// 1 -> 1.15 (inflate) -> 0.6 (burst) -> settle at `restScale`, with a damped wobble.
    /// Sampled manually with `value(time:)` so every cell in the single Canvas can run
    /// its own KeyframeAnimator-style timeline.
    static var timeline: KeyframeTimeline<PopSquish> {
        KeyframeTimeline(initialValue: PopSquish()) {
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.15, duration: 0.07)
                SpringKeyframe(0.6, duration: 0.12, spring: .snappy)
                SpringKeyframe(restScale, duration: 0.45, spring: .bouncy)
            }
            KeyframeTrack(\.wobble) {
                LinearKeyframe(0, duration: 0.07)
                CubicKeyframe(0.16, duration: 0.07)
                CubicKeyframe(-0.12, duration: 0.08)
                CubicKeyframe(0.07, duration: 0.09)
                CubicKeyframe(-0.03, duration: 0.1)
                CubicKeyframe(0, duration: 0.12)
            }
        }
    }

    /// The point in the timeline where the bubble visually bursts (switches to flat).
    static let burstTime: TimeInterval = 0.07
}

// MARK: - Rendering

private enum BubbleRenderer {
    static func draw(
        in context: inout GraphicsContext,
        size: CGSize,
        grid: PopGrid,
        popDates: [Int: Date],
        now: Date,
        squish: KeyframeTimeline<PopSquish>,
        animatePops: Bool
    ) {
        let sheet = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: min(size.width, size.height) * 0.06)
        context.fill(sheet, with: .color(Color(white: 0.16)))
        context.stroke(sheet, with: .color(.white.opacity(0.08)), lineWidth: 1)

        var sparkle = context.resolve(Image(systemName: "sparkle"))
        sparkle.shading = .color(.white)

        let gridSize = GridSize(width: Double(size.width), height: Double(size.height))
        for index in 0..<grid.cellCount {
            guard let cell = grid.cellRect(for: index, in: gridSize),
                  let position = grid.position(of: index) else { continue }

            let rect = CGRect(x: cell.x, y: cell.y, width: cell.width, height: cell.height)
            let diameter = min(rect.width, rect.height) * 0.82
            let palette = BubblePalette(row: position.row, rows: grid.rows)

            var bubble = context
            bubble.translateBy(x: rect.midX, y: rect.midY)

            guard grid.isPopped(index) else {
                drawGlossyBubble(in: &bubble, diameter: diameter, palette: palette)
                continue
            }

            let elapsed = popDates[index].map { now.timeIntervalSince($0) } ?? .infinity
            let animating = animatePops && elapsed < squish.duration
            let value = animating ? squish.value(time: max(elapsed, 0)) : PopSquish(scale: PopSquish.restScale)

            bubble.scaleBy(x: value.scale * (1 + value.wobble), y: value.scale * (1 - value.wobble))
            bubble.rotate(by: .radians(value.wobble * 0.6))

            if animating && elapsed < PopSquish.burstTime {
                drawGlossyBubble(in: &bubble, diameter: diameter, palette: palette)
            } else {
                drawPoppedBubble(in: &bubble, diameter: diameter, palette: palette, seed: UInt64(index))
            }

            // A little sparkle flies up out of a freshly popped bubble.
            let sparkleDuration = 0.4
            if animating && elapsed < sparkleDuration {
                let progress = elapsed / sparkleDuration
                var burst = context
                burst.opacity = 1 - progress
                let side = diameter * (0.35 + 0.25 * progress)
                let center = CGPoint(x: rect.midX, y: rect.midY - diameter * 0.45 * progress)
                burst.draw(sparkle, in: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side))
            }
        }
    }

    private static func drawGlossyBubble(in context: inout GraphicsContext, diameter d: Double, palette: BubblePalette) {
        let circle = Path(ellipseIn: CGRect(x: -d / 2, y: -d / 2, width: d, height: d))

        // Contact shadow.
        context.fill(
            Path(ellipseIn: CGRect(x: -d / 2, y: -d / 2 + d * 0.06, width: d, height: d)),
            with: .color(.black.opacity(0.35))
        )
        // Body: off-centre radial gradient gives the domed look.
        context.fill(
            circle,
            with: .radialGradient(
                Gradient(colors: [palette.highlight, palette.base, palette.shade]),
                center: CGPoint(x: -d * 0.18, y: -d * 0.22),
                startRadius: 0,
                endRadius: d * 0.78
            )
        )
        // Specular hotspot.
        let hotspot = CGRect(x: -d * 0.33, y: -d * 0.36, width: d * 0.32, height: d * 0.22)
        context.fill(
            Path(ellipseIn: hotspot),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.9), .white.opacity(0)]),
                center: CGPoint(x: hotspot.midX, y: hotspot.midY),
                startRadius: 0,
                endRadius: d * 0.18
            )
        )
        // Rim light.
        context.stroke(circle, with: .color(.white.opacity(0.28)), lineWidth: max(d * 0.02, 0.75))
    }

    private static func drawPoppedBubble(in context: inout GraphicsContext, diameter d: Double, palette: BubblePalette, seed: UInt64) {
        // Deflated: wider than tall, flat matte fill, no specular.
        let flat = CGRect(x: -d / 2, y: -d * 0.42, width: d, height: d * 0.84)
        let outline = Path(ellipseIn: flat)
        context.fill(outline, with: .color(palette.flat))
        context.stroke(outline, with: .color(palette.shade.opacity(0.6)), lineWidth: max(d * 0.02, 0.75))

        // Deterministic crinkles so each bubble keeps the same wrinkles every frame.
        var rng = SeededPopRandom(seed: seed &* 0x9E37_79B9 &+ 1)
        var wrinkles = Path()
        for _ in 0..<4 {
            let angle = rng.next(in: 0...(2 * .pi))
            let radius = rng.next(in: 0.05...0.3) * d
            var point = CGPoint(x: CGFloat(cos(angle) * radius), y: CGFloat(sin(angle) * radius * 0.8))
            wrinkles.move(to: point)
            for _ in 0..<3 {
                point.x += CGFloat(rng.next(in: -0.14...0.14) * d)
                point.y += CGFloat(rng.next(in: -0.1...0.1) * d)
                wrinkles.addLine(to: point)
            }
        }
        context.clip(to: outline)
        context.stroke(wrinkles, with: .color(.black.opacity(0.28)), style: StrokeStyle(lineWidth: max(d * 0.025, 0.75), lineCap: .round, lineJoin: .round))
        var crease = context
        crease.translateBy(x: d * 0.015, y: -d * 0.02)
        crease.stroke(wrinkles, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: max(d * 0.015, 0.5), lineCap: .round, lineJoin: .round))
    }
}

/// Pastel rainbow, one hue per row.
private struct BubblePalette {
    let highlight: Color
    let base: Color
    let shade: Color
    let flat: Color

    init(row: Int, rows: Int) {
        let hue = Double(row) / Double(max(rows, 1)) * 0.85
        highlight = Color(hue: hue, saturation: 0.25, brightness: 1.0)
        base = Color(hue: hue, saturation: 0.55, brightness: 0.95)
        shade = Color(hue: hue, saturation: 0.7, brightness: 0.6)
        flat = Color(hue: hue, saturation: 0.35, brightness: 0.55)
    }
}

// MARK: - Gift reveal

private enum UnwrapPhase: CaseIterable {
    case wrapped, wiggle, tear, reveal

    var paperOffset: Double {
        switch self {
        case .wrapped, .wiggle: 0
        case .tear: 0.35
        case .reveal: 1.2
        }
    }
    var paperRotation: Angle {
        switch self {
        case .wrapped: .zero
        case .wiggle: .degrees(-6)
        case .tear: .degrees(4)
        case .reveal: .degrees(18)
        }
    }
    var paperOpacity: Double { self == .reveal ? 0 : 1 }
    var giftScale: Double {
        switch self {
        case .wrapped, .wiggle: 0.3
        case .tear: 0.7
        case .reveal: 1
        }
    }
    var giftOpacity: Double { self == .wrapped || self == .wiggle ? 0 : 1 }
}

private struct GiftReveal: View {
    let onReset: () -> Void
    @State private var unwrapTrigger = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height) * 0.6
            VStack(spacing: side * 0.15) {
                PhaseAnimator(UnwrapPhase.allCases, trigger: unwrapTrigger) { phase in
                    ZStack {
                        Image(systemName: "gift.fill")
                            .resizable()
                            .scaledToFit()
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.pink, .yellow)
                            .frame(width: side * 0.7, height: side * 0.7)
                            .scaleEffect(phase.giftScale)
                            .opacity(phase.giftOpacity)

                        // Two halves of wrapping paper that tear apart.
                        HStack(spacing: 0) {
                            WrappingHalf()
                                .offset(x: -side * phase.paperOffset)
                                .rotationEffect(-phase.paperRotation)
                            WrappingHalf()
                                .scaleEffect(x: -1)
                                .offset(x: side * phase.paperOffset)
                                .rotationEffect(phase.paperRotation)
                        }
                        .frame(width: side, height: side)
                        .opacity(phase.paperOpacity)
                    }
                    .frame(width: side, height: side)
                } animation: { phase in
                    switch phase {
                    case .wrapped: .easeOut(duration: 0.15)
                    case .wiggle: .spring(duration: 0.25, bounce: 0.6)
                    case .tear: .easeIn(duration: 0.2)
                    case .reveal: .spring(duration: 0.6, bounce: 0.45)
                    }
                }
                .accessibilityLabel("Gift unwrapped")

                Button("Reset", systemImage: "arrow.counterclockwise", action: onReset)
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // PhaseAnimator only runs when its trigger changes, so kick it once on appear.
        .onAppear { unwrapTrigger.toggle() }
    }
}

private struct WrappingHalf: View {
    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16)
            .fill(
                LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(alignment: .trailing) {
                Rectangle().fill(.yellow).frame(width: 10)
            }
            .overlay {
                Rectangle().fill(.yellow).frame(height: 10)
            }
    }
}

#Preview("Pop Therapy") {
    PopTherapyView()
        .padding()
        .background(Color.black)
}
#endif
