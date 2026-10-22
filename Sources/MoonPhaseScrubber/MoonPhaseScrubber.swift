//  MoonPhaseScrubber.swift
//  MoonPhaseScrubber
//
//  A moon you scrub through a lunation with a sideways drag. `MoonView` is an Animatable Shape
//  of the lit region: the limb semicircle on the lit side closed by a terminator half-ellipse
//  whose x-radius is r·cos(2π·phase). Letting go springs to the nearest of the eight named
//  phases with a soft haptic; near new moon the dark disc picks up a faint earthshine glow, and
//  the phase name and percentage roll with a numericText content transition. The maths and
//  the scrub model live in MoonPhaseCore.

#if canImport(SwiftUI)
import SwiftUI
import MoonPhaseCore

// MARK: - Shape

/// The lit part of the Moon for a phase in 0..1 (0 new, 0.25 first quarter, 0.5 full,
/// 0.75 last quarter). The phase is animatable, so `withAnimation { phase = 0.5 }` waxes it.
///
/// ```swift
/// MoonView(phase: 0.3).fill(.white).frame(width: 120, height: 120)
/// ```
public struct MoonView: Shape {
    public var phase: Double
    /// Polygon samples per half outline.
    public var samples: Int

    public init(phase: Double, samples: Int = 72) {
        self.phase = phase
        self.samples = samples
    }

    public var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    public func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let pts = MoonMath.litOutline(phase: phase, radius: Double(r), samples: samples)
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: CGPoint(x: c.x + first.x, y: c.y + first.y))
        for q in pts.dropFirst() { path.addLine(to: CGPoint(x: c.x + q.x, y: c.y + q.y)) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Scrubber

/// A night-sky card with a moon you scrub through its phases.
///
/// ```swift
/// MoonPhaseScrubber()
/// MoonPhaseScrubber(initialPhase: 0.5) { phase in print(phase.title) }
/// ```
public struct MoonPhaseScrubber: View {
    private let onSnap: (MoonPhaseName) -> Void
    @State private var engine: MoonEngine
    @State private var isAnimating = true
    @State private var snapCount = 0
    @State private var countsDown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let moonSize: CGFloat = 236

    public init(initialPhase: Double = 0.04, onSnap: @escaping (MoonPhaseName) -> Void = { _ in }) {
        self.onSnap = onSnap
        _engine = State(initialValue: MoonEngine(phase: initialPhase))
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let frame = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                moon(frame)
                    .frame(width: 320, height: 320)
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Moon phase")
                    .accessibilityValue("\(frame.name.title), \(frame.percent) percent illuminated")
                    .accessibilityHint("Swipe up or down to change the phase.")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: commit { $0.advance(1) }
                        case .decrement: commit { $0.advance(-1) }
                        @unknown default: break
                        }
                    }
                readout(frame)
                    .padding(.top, 18)
                track(frame)
                    .padding(.top, 34)
                Text("Drag sideways to scrub")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 18)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Sky())
            .onChange(of: frame.isSettled, initial: true) { _, settled in
                if settled { isAnimating = false }
            }
        }
        .gesture(scrub)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: snapCount)
        .onChange(of: reduceMotion) { _, _ in isAnimating = true }
    }

    // MARK: Pieces

    private func moon(_ f: MoonFrame) -> some View {
        let d = Self.moonSize
        return ZStack {
            // Outer glow: grows with the lit fraction.
            Circle()
                .fill(Color(red: 0.95, green: 0.93, blue: 0.85).opacity(0.10 + 0.22 * f.illumination))
                .frame(width: d * 1.28, height: d * 1.28)
                .blur(radius: 34)
            // Earthshine halo hugging the dark limb near new moon.
            Circle()
                .fill(Color(red: 0.45, green: 0.58, blue: 0.85).opacity(f.earthshine * 0.9))
                .frame(width: d * 1.08, height: d * 1.08)
                .blur(radius: 18)
            // Dark disc, faintly lit by earthshine.
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.21), Color(red: 0.06, green: 0.07, blue: 0.11)],
                                     center: UnitPoint(x: 0.42, y: 0.4), startRadius: 0, endRadius: d * 0.6))
                .overlay(Circle().fill(Color(red: 0.62, green: 0.70, blue: 0.86).opacity(f.earthshine * 0.45)))
                .overlay(Maria().opacity(0.12 + f.earthshine * 0.5))
                .frame(width: d, height: d)
            // The lit region, its terminator softened a touch.
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.99, blue: 0.95), Color(red: 0.86, green: 0.84, blue: 0.77)],
                                             center: UnitPoint(x: 0.4, y: 0.36), startRadius: 0, endRadius: d * 0.62))
                Maria()
            }
            .frame(width: d, height: d)
            .mask {
                MoonView(phase: f.phase)
                    .fill(.white)
                    .blur(radius: 1.2)
            }
            .shadow(color: Color(red: 1, green: 0.96, blue: 0.85).opacity(0.35 * f.illumination), radius: 14)
        }
    }

    private func readout(_ f: MoonFrame) -> some View {
        VStack(spacing: 8) {
            Text(f.name.title)
                .font(.system(size: 30, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
                .contentTransition(.numericText(countsDown: countsDown))
                .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: f.name)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(f.percent)%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(f.percent)))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: f.percent)
                Text("illuminated  ·  \(MoonFormatting.age(f.phase))")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.62))
        }
        .accessibilityHidden(true)
    }

    /// Eight small moons with an indicator riding under the current phase; tap one to jump.
    private func track(_ f: MoonFrame) -> some View {
        let slot: CGFloat = 38
        return VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(MoonPhaseName.allCases, id: \.self) { name in
                    Button { commit { $0.select(name) } } label: {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.10))
                            MoonView(phase: name.fraction, samples: 24).fill(.white.opacity(name == f.name ? 0.95 : 0.55))
                        }
                        .frame(width: 18, height: 18)
                        .frame(width: slot, height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }
            }
            Capsule()
                .fill(Color(red: 1, green: 0.85, blue: 0.55))
                .frame(width: 14, height: 4)
                .offset(x: (CGFloat(f.phase * 8) + 0.5) * slot - slot * 4)
                .frame(width: slot * 8)
        }
    }

    // MARK: Input

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { v in
                engine.drag(translation: Double(v.translation.width))
                countsDown = v.velocity.width < 0
                isAnimating = true
            }
            .onEnded { v in
                let target = engine.endDrag(velocity: Double(v.velocity.width))
                snapCount = engine.snapCount
                isAnimating = true
                onSnap(MoonPhaseName.nearest(to: target))
            }
    }

    private func commit(_ change: (inout MoonScrubModel) -> Void) {
        let before = engine.target
        engine.mutate(change)
        countsDown = engine.target < before
        snapCount = engine.snapCount
        isAnimating = true
        onSnap(MoonPhaseName.nearest(to: engine.target))
    }
}

// MARK: - Decoration

/// A few seeded dark "seas" so the lit face isn't flat.
private struct Maria: View {
    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 0x6D6F6F6E)
            let s = min(size.width, size.height)
            let seas: [(Double, Double, Double)] = [(0.36, 0.34, 0.17), (0.58, 0.30, 0.12), (0.62, 0.52, 0.15),
                                                    (0.40, 0.60, 0.10), (0.30, 0.48, 0.08), (0.70, 0.70, 0.07)]
            for (x, y, r) in seas {
                let rr = r * s * rng.uniform(0.9...1.1)
                let rect = CGRect(x: x * s - rr, y: y * s - rr * 0.85, width: rr * 2, height: rr * 1.7)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.55, green: 0.54, blue: 0.52).opacity(0.28)))
            }
            for _ in 0..<14 {
                let r = rng.uniform(2...6) * s / 236
                let c = CGPoint(x: rng.uniform(0.18...0.82) * s, y: rng.uniform(0.18...0.82) * s)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(Color(red: 0.5, green: 0.48, blue: 0.45).opacity(0.25)), lineWidth: 1)
            }
        }
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}

private struct Sky: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.10), Color(red: 0.07, green: 0.09, blue: 0.20)],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var rng = SeededRandom(seed: 0x5354_4152)
                for _ in 0..<90 {
                    let r = rng.uniform(0.4...1.3)
                    let p = CGPoint(x: rng.uniform(0...1) * size.width, y: rng.uniform(0...1) * size.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(.white.opacity(rng.uniform(0.15...0.6))))
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

// MARK: - Engine

struct MoonFrame {
    var phase: Double
    var name: MoonPhaseName
    var percent: Int
    var illumination: Double
    var earthshine: Double
    var isSettled: Bool
}

/// Owns the scrub model outside SwiftUI's dependency tracking; the TimelineView steps it by date.
final class MoonEngine {
    private var model: MoonScrubModel
    private var lastDate: Date?

    init(phase: Double) { model = MoonScrubModel(phase: phase) }

    var snapCount: Int { model.snapCount }
    var target: Double { model.target }

    func drag(translation: Double) {
        if !model.isDragging { model.beginDrag() }
        model.drag(translation: translation)
    }

    func endDrag(velocity: Double) -> Double { model.endDrag(velocity: velocity) }

    func mutate(_ change: (inout MoonScrubModel) -> Void) { change(&model) }

    func frame(at date: Date, reduceMotion: Bool) -> MoonFrame {
        if model.reduceMotion != reduceMotion { model.reduceMotion = reduceMotion }
        if let lastDate { model.step(date.timeIntervalSince(lastDate)) }
        let settled = model.isSettled
        lastDate = settled ? nil : date
        let p = model.phase
        return MoonFrame(phase: p, name: model.name, percent: MoonFormatting.percentLit(p),
                         illumination: MoonMath.illumination(p), earthshine: MoonMath.earthshine(p), isSettled: settled)
    }
}

// MARK: - Preview

#Preview("Moon Phase Scrubber") {
    MoonPhaseScrubber()
}
#endif
