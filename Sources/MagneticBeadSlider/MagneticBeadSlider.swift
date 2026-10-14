//  MagneticBeadSlider.swift
//  MagneticBeadSlider
//
//  A slider whose thumb is a magnet: a row of glossy beads is pulled toward it with a
//  distance falloff, springs after it like a chain, stretches in the direction it moves
//  (keeping its area), and snaps to the nearest step on release with a little haptic tick.
//  The physics lives in MagneticBeadCore; this file only drives and renders it.

#if canImport(SwiftUI)
import SwiftUI
import MagneticBeadCore

/// A slider (0...1) with a magnetic bead chain.
///
/// - `steps`: the number of step intervals. `4` gives the values 0, 0.25, 0.5, 0.75 and 1.
///   `0` makes the slider continuous.
/// - Takes its colour from `.tint(_:)`.
public struct MagneticBeadSlider: View {
    @Binding private var value: Double
    private let steps: Int
    private let configuration: BeadConfiguration

    @State private var engine: BeadEngine
    @State private var isAnimating = false
    @State private var isDragging = false
    @State private var dragStartPosition: Double?
    @State private var stepCrossings = 0
    @State private var snaps = 0
    /// Bumped whenever the engine changes outside the timeline so a paused timeline redraws.
    @State private var revision = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    private static var trackSpace: NamedCoordinateSpace { .named("MagneticBeadSlider.track") }
    private let thumbDiameter: CGFloat = 28
    private let beadDiameter: CGFloat = 13
    private let trackHeight: CGFloat = 6

    public init(value: Binding<Double>, steps: Int, configuration: BeadConfiguration = .default) {
        _value = value
        self.steps = max(steps, 0)
        self.configuration = configuration
        _engine = State(initialValue: BeadEngine(
            system: MagneticBeadSystem(value: value.wrappedValue, steps: steps, configuration: configuration)
        ))
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = TrackMetrics(size: proxy.size, thumbDiameter: thumbDiameter)
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                let _ = revision
                let snapshot = frame(at: timeline.date)
                track(snapshot, metrics: metrics)
                    .onChange(of: timeline.date) {
                        if !isDragging && engine.system.isSettled { isAnimating = false }
                    }
            }
        }
        .frame(minWidth: 120, minHeight: 44, maxHeight: 44)
        .opacity(isEnabled ? 1 : 0.45)
        .sensoryFeedback(.selection, trigger: stepCrossings)
        .sensoryFeedback(.impact(weight: .light), trigger: snaps)
        .onAppear { syncFromBinding(animated: false) }
        .onChange(of: value) { syncFromBinding(animated: !reduceMotion) }
        .onChange(of: steps) { rebuildEngine() }
        .onChange(of: configuration) { rebuildEngine() }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            let delta = engine.system.stepSize ?? 0.05
            switch direction {
            case .increment: setValueFromAccessibility(value + delta)
            case .decrement: setValueFromAccessibility(value - delta)
            @unknown default: break
            }
        }
    }

    // MARK: Rendering

    private func track(_ system: MagneticBeadSystem, metrics: TrackMetrics) -> some View {
        let thumbX = metrics.x(for: system.thumbPosition)
        return ZStack(alignment: .topLeading) {
            // Groove.
            Capsule()
                .fill(.quaternary)
                .frame(width: metrics.size.width - thumbDiameter + trackHeight, height: trackHeight)
                .position(x: metrics.size.width / 2, y: metrics.midY)

            // Filled portion up to the thumb.
            Capsule()
                .fill(.tint)
                .opacity(0.35)
                .frame(width: max(thumbX - metrics.inset + trackHeight, trackHeight), height: trackHeight)
                .position(x: (metrics.inset - trackHeight / 2 + thumbX) / 2, y: metrics.midY)

            // Step ticks (skipped when they would be too dense to read).
            if steps > 0, metrics.usableWidth / CGFloat(steps) >= 8 {
                ForEach(0...steps, id: \.self) { step in
                    Circle()
                        .fill(.secondary)
                        .opacity(0.5)
                        .frame(width: 3, height: 3)
                        .position(x: metrics.x(for: Double(step) / Double(steps)), y: metrics.midY + trackHeight + 4)
                }
            }

            // Beads: stretched along the track (the motion axis) by their velocity.
            ForEach(system.beads.indices, id: \.self) { index in
                let squash = reduceMotion ? Squash.identity : system.squash(forBead: index)
                GlossyBead(diameter: beadDiameter)
                    .scaleEffect(x: squash.along, y: squash.across)
                    .position(x: metrics.x(for: system.beads[index].position), y: metrics.midY)
            }

            // Thumb (the magnet).
            GlossyBead(diameter: thumbDiameter, isThumb: true)
                .scaleEffect(isDragging ? 1.12 : 1)
                .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.5), value: isDragging)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .position(x: thumbX, y: metrics.midY)
                .gesture(thumbDrag(metrics: metrics))
                .allowsHitTesting(isEnabled)
        }
        .coordinateSpace(Self.trackSpace)
    }

    // MARK: Interaction

    private func thumbDrag(metrics: TrackMetrics) -> some Gesture {
        // Use the track's coordinate space: the thumb moves under the finger, so its own
        // local space would make the translation feed back on itself.
        DragGesture(minimumDistance: 0, coordinateSpace: Self.trackSpace)
            .onChanged { gesture in
                let start: Double
                if let dragStartPosition {
                    start = dragStartPosition
                } else {
                    start = engine.system.thumbPosition
                    dragStartPosition = start
                    isDragging = true
                    startAnimating()
                }
                let raw = start + Double(gesture.translation.width / metrics.usableWidth)
                let crossedStep = engine.system.drag(to: raw)
                if crossedStep { stepCrossings &+= 1 }
                if crossedStep || steps == 0 { value = engine.system.value }
            }
            .onEnded { _ in
                dragStartPosition = nil
                isDragging = false
                value = engine.system.release()
                if reduceMotion { engine.system.settleImmediately() }
                snaps &+= 1
                startAnimating()
            }
    }

    private func setValueFromAccessibility(_ newValue: Double) {
        engine.system.setValue(newValue, animated: !reduceMotion)
        value = engine.system.value
        startAnimating()
    }

    /// Picks up changes made to the binding from outside the slider.
    private func syncFromBinding(animated: Bool) {
        guard !isDragging else { return }
        let target = MagneticBeadSystem.snap(value, steps: steps)
        guard abs(target - engine.system.value) > 1e-9 else { return }
        engine.system.setValue(value, animated: animated)
        startAnimating()
    }

    private func rebuildEngine() {
        engine = BeadEngine(system: MagneticBeadSystem(value: value, steps: steps, configuration: configuration))
        value = engine.system.value
        revision &+= 1
    }

    private func startAnimating() {
        engine.resetClock()
        revision &+= 1
        // Reduce Motion: no physics. Changes are applied immediately and the timeline stays
        // paused, except while dragging so the thumb follows the finger.
        isAnimating = !reduceMotion || isDragging
    }

    /// Advances the physics to `date` and returns a snapshot to render.
    private func frame(at date: Date) -> MagneticBeadSystem {
        if reduceMotion {
            engine.system.settleImmediately()
            return engine.system
        }
        return engine.advance(to: date)
    }
}

// MARK: - Engine

/// Holds the mutable simulation outside SwiftUI's dependency tracking, so stepping it from
/// inside the TimelineView doesn't invalidate the view (the timeline already redraws each frame).
final class BeadEngine {
    var system: MagneticBeadSystem
    private var lastTick: Date?

    init(system: MagneticBeadSystem) {
        self.system = system
    }

    func advance(to date: Date) -> MagneticBeadSystem {
        if let lastTick {
            system.step(dt: date.timeIntervalSince(lastTick))
        }
        lastTick = date
        return system
    }

    /// Call when (re)starting the timeline so a long pause doesn't turn into one huge step.
    func resetClock() {
        lastTick = nil
    }
}

private struct TrackMetrics {
    let size: CGSize
    let thumbDiameter: CGFloat

    var inset: CGFloat { thumbDiameter / 2 }
    var usableWidth: CGFloat { max(size.width - thumbDiameter, 1) }
    var midY: CGFloat { size.height / 2 }

    func x(for position: Double) -> CGFloat {
        inset + CGFloat(position) * usableWidth
    }
}

// MARK: - Bead

private struct GlossyBead: View {
    let diameter: CGFloat
    var isThumb = false

    var body: some View {
        Circle()
            .fill(.tint)
            .overlay {
                // Shading: bright upper-left, darker lower-right, for a domed glassy look.
                Circle().fill(
                    RadialGradient(
                        colors: [.white.opacity(0.75), .white.opacity(0), .black.opacity(0.35)],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 0,
                        endRadius: diameter * 0.8
                    )
                )
            }
            .overlay(alignment: .topLeading) {
                // Specular highlight.
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.95), .white.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: diameter * 0.2
                        )
                    )
                    .frame(width: diameter * 0.42, height: diameter * 0.28)
                    .offset(x: diameter * 0.14, y: diameter * 0.1)
            }
            .overlay {
                Circle().strokeBorder(.white.opacity(isThumb ? 0.55 : 0.3), lineWidth: isThumb ? 1.5 : 0.75)
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.28), radius: isThumb ? 3 : 1.5, y: isThumb ? 2 : 1)
    }
}

// MARK: - Preview

private struct MagneticBeadSliderPreview: View {
    @State private var stepped = 0.5
    @State private var continuous = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Stepped (8): \(stepped, format: .number.precision(.fractionLength(3)))")
            MagneticBeadSlider(value: $stepped, steps: 8)
                .accessibilityLabel("Stepped")

            Text("Continuous: \(continuous, format: .number.precision(.fractionLength(3)))")
            MagneticBeadSlider(value: $continuous, steps: 0)
                .tint(.pink)
                .accessibilityLabel("Continuous")

            Button("Randomize") {
                stepped = .random(in: 0...1)
                continuous = .random(in: 0...1)
            }
        }
        .padding(24)
    }
}

#Preview("Magnetic Bead Slider") {
    MagneticBeadSliderPreview()
}
#endif
