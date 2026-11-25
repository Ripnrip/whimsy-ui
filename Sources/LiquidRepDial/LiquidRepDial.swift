//
//  LiquidRepDial.swift
//  LiquidRepDial
//
//  A navy glass dial. The count sits in the middle, and the rim holds lime light
//  the way a glass holds a liquid: an angular gradient trimmed around the circle,
//  a blurred copy of that arc, and a meniscus at the leading edge. A tap adds a
//  rep. The arc runs past the new mark and settles, because the fill is a spring
//  with bounce. Tip the phone, or pass a tilt, and the pool shifts toward the
//  low side. Reduce Motion crossfades the fill and does not slosh.
//  The spring, the slosh and the wobble live in LiquidRepDialCore.
//

#if canImport(SwiftUI)
import SwiftUI
@_exported import LiquidRepDialCore
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

/// A glass dial that counts reps.
///
/// ```swift
/// LiquidRepDial(reps: $reps, goal: 20, onRep: { session.note() })
/// LiquidRepDial(reps: $reps, goal: 20, tilt: LiquidTilt(roll: 0.2, pitch: 0.4), useDeviceMotion: false)
/// ```
///
/// Tap the dial to add a rep. `tilt` is used when `useDeviceMotion` is false,
/// so a preview can slosh the liquid without CoreMotion. VoiceOver reads
/// "12 of 20 reps" and increments with Add rep.
public struct LiquidRepDial: View {
    @Binding private var reps: Int
    private let goal: Int
    private let tilt: LiquidTilt
    private let useDeviceMotion: Bool
    private let onRep: (() -> Void)?

    @State private var model: LiquidRepModel
    @State private var lastDate: Date?
    @State private var hapticTick = 0
    @State private var goalTick = 0
    @State private var pendingTicks = 0
    @State private var motionRoll = 0.0
    @State private var motionPitch = 0.0
    @State private var motionToken: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        reps: Binding<Int>,
        goal: Int = LiquidRepTuning.defaultGoal,
        tilt: LiquidTilt = .zero,
        useDeviceMotion: Bool = true,
        onRep: (() -> Void)? = nil
    ) {
        _reps = reps
        self.goal = goal
        self.tilt = tilt
        self.useDeviceMotion = useDeviceMotion
        self.onRep = onRep
        _model = State(initialValue: LiquidRepModel(
            reps: reps.wrappedValue,
            goal: goal,
            tilt: useDeviceMotion ? .zero : tilt
        ))
    }

    public var body: some View {
        let running = model.needsClock || pendingTicks > 0 || motionToken != nil
        return TimelineView(.animation(paused: !running)) { timeline in
            GeometryReader { geo in
                let scale = fitScale(in: geo.size)
                let originX = (geo.size.width - LiquidRepTuning.sceneWidth * scale) / 2
                let originY = (geo.size.height - LiquidRepTuning.sceneHeight * scale) / 2
                scene
                    .frame(width: LiquidRepTuning.sceneWidth, height: LiquidRepTuning.sceneHeight, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: originX, y: originY)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(tap(scale: scale, originX: originX, originY: originY))
                    .onChange(of: timeline.date) { _, now in advance(to: now) }
            }
        }
        .modifier(LiquidRepHaptics(ticks: hapticTick, goals: goalTick))
        .onAppear {
            model.setReduceMotion(reduceMotion)
            model.setGoal(goal)
            model.setTilt(appliedTilt)
            if reps != model.reps { note(model.setReps(reps), user: false) }
            startMotionIfNeeded()
        }
        .onDisappear { stopMotion() }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .onChange(of: goal) { _, newGoal in model.setGoal(newGoal) }
        .onChange(of: tilt) { _, _ in
            guard !useDeviceMotion else { return }
            model.setTilt(appliedTilt)
        }
        .onChange(of: reps) { _, newValue in
            guard newValue != model.reps else { return }
            note(model.setReps(newValue), user: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
        .accessibilityHint(model.canAddRep ? LiquidRepTuning.accessibilityHint : "The count is full.")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { addRep() }
        }
        .accessibilityAction(named: Text(LiquidRepTuning.addRepAction)) { addRep() }
    }

    private var scene: some View {
        let rim = model.rim
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawGround(&context)
            }
            .frame(width: LiquidRepTuning.sceneWidth, height: LiquidRepTuning.sceneHeight)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            glass
            track
            glowArc(rim)
            liquidArc(rim)
            meniscus(rim)
            captions
            readout
        }
        .frame(width: LiquidRepTuning.sceneWidth, height: LiquidRepTuning.sceneHeight, alignment: .topLeading)
    }

    private var glass: some View {
        let side = LiquidRepTuning.dialDiameter
        let center = LiquidRepTuning.dialCenter
        return Circle()
            .fill(
                RadialGradient(
                    colors: [rgb(LiquidRepTuning.glassInner), rgb(LiquidRepTuning.glassOuter)],
                    center: .init(x: 0.5, y: 0.42),
                    startRadius: 8,
                    endRadius: side * 0.55
                )
            )
            .overlay(Circle().stroke(rgb(LiquidRepTuning.glassEdge).opacity(0.28), lineWidth: 1.25))
            .overlay {
                if !metalEnabled {
                    Canvas { context, size in
                        let highlight = CGRect(x: size.width * 0.18, y: size.height * 0.08, width: size.width * 0.64, height: size.height * 0.42)
                        context.fill(
                            Path(ellipseIn: highlight),
                            with: .color(Color.white.opacity(0.08 + 0.06 * model.glow))
                        )
                    }
                    .clipShape(Circle())
                    .allowsHitTesting(false)
                }
            }
            .frame(width: side, height: side)
            .modifier(LiquidGlassShader(
                enabled: metalEnabled,
                side: side,
                fill: model.displayedFill,
                glow: model.glow,
                meniscus: model.meniscus
            ))
            .position(x: center.x, y: center.y)
            .accessibilityHidden(true)
    }

    private var track: some View {
        let side = LiquidRepTuning.ringRadius * 2
        let center = LiquidRepTuning.dialCenter
        return Circle()
            .stroke(rgb(LiquidRepTuning.track).opacity(0.10), style: strokeStyle(LiquidRepTuning.stroke))
            .frame(width: side, height: side)
            .position(x: center.x, y: center.y)
            .accessibilityHidden(true)
    }

    private func glowArc(_ rim: LiquidRim) -> some View {
        let side = LiquidRepTuning.ringRadius * 2
        let center = rim.center
        return Circle()
            .trim(from: 0, to: rim.trim)
            .stroke(rgb(LiquidRepTuning.lime).opacity(0.95), style: strokeStyle(LiquidRepTuning.stroke * 1.45))
            .frame(width: side, height: side)
            .rotationEffect(.radians(rim.rotation))
            .blur(radius: 14)
            .opacity(0.55 + 0.45 * rim.glow)
            .blendMode(.plusLighter)
            .position(x: center.x, y: center.y)
            .accessibilityHidden(true)
    }

    private func liquidArc(_ rim: LiquidRim) -> some View {
        let side = LiquidRepTuning.ringRadius * 2
        let center = rim.center
        let sweep = max(rim.trim, 0.0001) * 2 * Double.pi
        return Circle()
            .trim(from: 0, to: rim.trim)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        rgb(LiquidRepTuning.limeDeep),
                        rgb(LiquidRepTuning.lime),
                        rgb(LiquidRepTuning.limeBright),
                        rgb(LiquidRepTuning.lime),
                    ]),
                    center: .center,
                    startAngle: .radians(0),
                    endAngle: .radians(sweep)
                ),
                style: strokeStyle(LiquidRepTuning.stroke)
            )
            .frame(width: side, height: side)
            .rotationEffect(.radians(rim.rotation))
            .position(x: center.x, y: center.y)
            .accessibilityHidden(true)
    }

    private func meniscus(_ rim: LiquidRim) -> some View {
        let blob = 18 + rim.bulge
        return Circle()
            .fill(rgb(LiquidRepTuning.limeBright))
            .frame(width: blob, height: blob)
            .blur(radius: 6)
            .opacity(rim.trim > 0.004 ? 0.85 : 0)
            .blendMode(.plusLighter)
            .position(x: rim.leading.x, y: rim.leading.y)
            .accessibilityHidden(true)
    }

    private var captions: some View {
        ZStack {
            Text(LiquidRepTuning.wordmark)
                .font(.system(size: 28, weight: .medium, design: .serif))
                .tracking(8)
                .foregroundStyle(rgb(LiquidRepTuning.wordmarkColor))
                .position(x: LiquidRepTuning.sceneWidth / 2, y: LiquidRepTuning.wordmarkY)
            Text(LiquidRepTuning.caption)
                .font(.system(size: 12, weight: .semibold))
                .tracking(3.6)
                .foregroundStyle(rgb(LiquidRepTuning.captionColor))
                .position(x: LiquidRepTuning.sceneWidth / 2, y: LiquidRepTuning.captionY)
            Text(LiquidRepTuning.goalCaption(goal: model.goal))
                .font(.system(size: 13, weight: .semibold))
                .tracking(3.2)
                .foregroundStyle(rgb(LiquidRepTuning.captionColor))
                .position(x: LiquidRepTuning.sceneWidth / 2, y: LiquidRepTuning.goalY)
        }
        .accessibilityHidden(true)
    }

    private var readout: some View {
        ZStack {
            Text(model.readout)
                .font(.system(size: 84, weight: .medium, design: .rounded))
                .foregroundStyle(rgb(model.atGoal ? LiquidRepTuning.limeBright : LiquidRepTuning.number))
                .position(x: LiquidRepTuning.dialCenter.x, y: LiquidRepTuning.numberY)
            Text(LiquidRepTuning.repsLabel)
                .font(.system(size: 13, weight: .semibold))
                .tracking(4)
                .foregroundStyle(rgb(LiquidRepTuning.label))
                .position(x: LiquidRepTuning.dialCenter.x, y: LiquidRepTuning.repsLabelY)
        }
        .accessibilityHidden(true)
    }

    private var metalEnabled: Bool {
        if #available(iOS 17.0, macOS 14.0, *) { return true }
        return false
    }

    private var appliedTilt: LiquidTilt {
        if useDeviceMotion {
            #if canImport(CoreMotion) && os(iOS)
            if motionToken != nil { return LiquidTilt(roll: motionRoll, pitch: motionPitch) }
            #endif
            return .zero
        }
        return tilt
    }

    private func fitScale(in size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        return min(size.width / LiquidRepTuning.sceneWidth, size.height / LiquidRepTuning.sceneHeight)
    }

    private func tap(scale: CGFloat, originX: CGFloat, originY: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard scale > 0 else { return }
                let x = (value.location.x - originX) / scale
                let y = (value.location.y - originY) / scale
                let center = LiquidRepTuning.dialCenter
                let dx = Double(x) - center.x
                let dy = Double(y) - center.y
                let reach = LiquidRepTuning.dialDiameter / 2 + LiquidRepTuning.hitSlop
                guard dx * dx + dy * dy <= reach * reach else { return }
                addRep()
            }
    }

    private func addRep() {
        guard model.canAddRep else { return }
        note(model.addRep(), user: true)
    }

    private func advance(to now: Date) {
        model.setTilt(appliedTilt)
        defer { lastDate = now }
        guard let last = lastDate else { return }
        model.step(now.timeIntervalSince(last))
        guard pendingTicks > 0 else { return }
        hapticTick += 1
        pendingTicks -= 1
    }

    /// One haptic for the first tick now, and one more on each following frame
    /// when a single change crossed several reps.
    private func note(_ events: [LiquidRepEvent], user: Bool) {
        var ticks = 0
        var reached = false
        for event in events {
            switch event {
            case .tick: ticks += 1
            case .goalReached: reached = true
            }
        }
        if ticks > 0 {
            hapticTick += 1
            pendingTicks += ticks - 1
            if user { onRep?() }
        }
        if reached { goalTick += 1 }
        if reps != model.reps { reps = model.reps }
    }

    private func startMotionIfNeeded() {
        guard useDeviceMotion else { return }
        #if canImport(CoreMotion) && os(iOS)
        motionToken = LiquidRepMotion.shared.start { roll, pitch in
            motionRoll = roll
            motionPitch = pitch
        }
        #endif
    }

    private func stopMotion() {
        #if canImport(CoreMotion) && os(iOS)
        if let motionToken {
            LiquidRepMotion.shared.stop(motionToken)
        }
        #endif
        motionToken = nil
    }

    private func strokeStyle(_ width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    private func drawGround(_ ctx: inout GraphicsContext) {
        let width = LiquidRepTuning.sceneWidth
        let height = LiquidRepTuning.sceneHeight
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: height)),
            with: .linearGradient(
                Gradient(colors: [rgb(LiquidRepTuning.backgroundTop), rgb(LiquidRepTuning.backgroundBottom)]),
                startPoint: CGPoint(x: width / 2, y: 0),
                endPoint: CGPoint(x: width / 2, y: height)
            )
        )
        guard model.displayedFill > 0 else { return }
        let center = LiquidRepTuning.dialCenter
        var spill = Path()
        spill.addEllipse(in: CGRect(x: center.x - 120, y: center.y + 70, width: 240, height: 90))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 18))
            layer.fill(spill, with: .color(rgb(LiquidRepTuning.lime).opacity(0.05 + 0.16 * model.glow)))
        }
    }

    private func rgb(_ color: LiquidRGB) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
    }
}

/// Soft tick on each rep, and a success tap when the count first reaches the goal.
/// Older systems keep the dial and skip the haptic.
private struct LiquidRepHaptics: ViewModifier {
    var ticks: Int
    var goals: Int

    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content
                .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: ticks)
                .sensoryFeedback(.success, trigger: goals)
        } else {
            content
        }
    }
}

/// The stitchable glass when it can load. Otherwise the disc keeps the Canvas highlight.
private struct LiquidGlassShader: ViewModifier {
    var enabled: Bool
    var side: Double
    var fill: Double
    var glow: Double
    var meniscus: Double

    func body(content: Content) -> some View {
        if enabled {
            shaded(content)
        } else {
            content
        }
    }

    @ViewBuilder
    private func shaded(_ content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.colorEffect(
                ShaderLibrary.bundle(.module).liquidRepGlass(
                    .float2(Float(side), Float(side)),
                    .float(Float(fill)),
                    .float(Float(glow)),
                    .float(Float(meniscus))
                )
            )
        } else {
            content
        }
    }
}

#if canImport(CoreMotion) && os(iOS)
/// One CoreMotion stream. Roll and pitch are radians, the same axes as ``LiquidTilt``.
@MainActor
final class LiquidRepMotion {
    static let shared = LiquidRepMotion()
    private let manager = CMMotionManager()
    private var handlers: [UUID: @MainActor (Double, Double) -> Void] = [:]

    @discardableResult
    func start(_ handler: @escaping @MainActor (Double, Double) -> Void) -> UUID {
        let id = UUID()
        handlers[id] = handler
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return id }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let attitude = data?.attitude else { return }
            let roll = attitude.roll
            let pitch = attitude.pitch
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = Array(self.handlers.values)
                for handler in current {
                    handler(roll, pitch)
                }
            }
        }
        return id
    }

    func stop(_ id: UUID) {
        handlers[id] = nil
        if handlers.isEmpty { manager.stopDeviceMotionUpdates() }
    }
}
#endif

/// Gallery page. The dial starts empty, at a goal of 20.
public struct LiquidRepDialDemo: View {
    @State private var reps = 0

    public init() {}

    public var body: some View {
        LiquidRepDial(reps: $reps, goal: 20, onRep: nil)
    }
}

#Preview("Liquid rep dial") {
    LiquidRepDialDemo()
}

#Preview("Tilted") {
    LiquidRepDial(reps: .constant(10), goal: 20, tilt: LiquidTilt(roll: -0.35, pitch: 0.45), useDeviceMotion: false)
}
#endif
