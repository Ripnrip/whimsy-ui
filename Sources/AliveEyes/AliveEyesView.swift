//  AliveEyesView.swift
//  AliveEyes
//
//  Two cartoon eyes that feel alive: a fast spring gaze that follows your finger and
//  drifts home on release, tiny saccades, asymmetric blinks with occasional doubles, and a
//  squint when the phone is shaken. All timing lives in AliveEyesCore; this file just
//  feeds it input and draws the frame.

#if canImport(SwiftUI)
import SwiftUI
import AliveEyesCore
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

/// Two cartoon eyes drawn in a single `Canvas`.
///
/// - Drag anywhere on the view and the eyes follow your finger. Release, and they drift back.
/// - Shaking an iPhone makes them squint (Core Motion). Elsewhere, double-tap or bump
///   `squintTrigger`.
/// - With Reduce Motion: no saccades, and blinks are slower with no doubles.
public struct AliveEyesView: View {
    private let lidColor: Color
    private let irisColor: Color
    private let squintTrigger: Int

    @State private var engine: EyesEngine
    @State private var shake = ShakeSource()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - seed: seed for saccade and blink timing. Pass a fixed value for reproducible
    ///     motion (previews, snapshot tests).
    ///   - lidColor: eyelid colour; usually your face/background colour.
    ///   - irisColor: base iris colour.
    ///   - squintTrigger: change this value to make the eyes squint (fallback for shake).
    public init(
        seed: UInt64 = UInt64.random(in: 0...UInt64.max),
        lidColor: Color = Color(red: 0.98, green: 0.80, blue: 0.56),
        irisColor: Color = Color(red: 0.20, green: 0.55, blue: 0.62),
        squintTrigger: Int = 0
    ) {
        self.lidColor = lidColor
        self.irisColor = irisColor
        self.squintTrigger = squintTrigger
        _engine = State(initialValue: EyesEngine(seed: seed))
    }

    public var body: some View {
        GeometryReader { proxy in
            let layout = EyesLayout(size: proxy.size)
            TimelineView(.animation) { timeline in
                let frame = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
                Canvas { context, _ in
                    EyesRenderer(lidColor: lidColor, irisColor: irisColor)
                        .draw(frame, layout: layout, in: &context)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        engine.setFinger(EyeGeometry.gazeTarget(
                            finger: Vec2(Double(value.location.x), Double(value.location.y)),
                            eyesCenter: layout.center,
                            reach: layout.reach
                        ))
                    }
                    .onEnded { _ in engine.setFinger(nil) }
            )
            .simultaneousGesture(TapGesture(count: 2).onEnded { engine.squint() })
        }
        .onChange(of: squintTrigger) { engine.squint() }
        .onAppear {
            shake.start { x, y, z in engine.feedAcceleration(x: x, y: y, z: z) }
        }
        .onDisappear { shake.stop() }
        .accessibilityElement()
        .accessibilityLabel(Text("Two cartoon eyes"))
        .accessibilityHint(Text("Drag to make them look around. Double-tap to make them squint."))
        .accessibilityAddTraits(.allowsDirectInteraction)
        .accessibilityAction(named: Text("Squint")) { engine.squint() }
        .accessibilityAction(named: Text("Blink")) { engine.blink() }
    }
}

// MARK: - Engine

/// Holds the deterministic model outside SwiftUI's dependency tracking; the TimelineView
/// steps it once per frame (stepping the same date twice is a no-op).
final class EyesEngine {
    private var model: AliveEyesModel
    private var lastDate: Date?

    init(seed: UInt64) { model = AliveEyesModel(seed: seed) }

    func frame(at date: Date, reduceMotion: Bool) -> EyesFrame {
        if model.reduceMotion != reduceMotion { model.reduceMotion = reduceMotion }
        if let lastDate { model.step(dt: date.timeIntervalSince(lastDate)) }
        lastDate = date
        return model.frame
    }

    func setFinger(_ target: Vec2?) { model.setFinger(target) }
    func feedAcceleration(x: Double, y: Double, z: Double) { model.feedAcceleration(x: x, y: y, z: z) }
    func squint() { model.squint() }
    func blink() { model.blinkNow() }
}

// MARK: - Shake input

#if canImport(CoreMotion) && os(iOS)
/// Streams user acceleration (gravity removed, in g) from Core Motion at 50 Hz on the main queue.
@MainActor
final class ShakeSource {
    private let manager = CMMotionManager()

    func start(_ handler: @escaping @MainActor (Double, Double, Double) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: .main) { motion, _ in
            guard let a = motion?.userAcceleration else { return }
            MainActor.assumeIsolated { handler(a.x, a.y, a.z) }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
#else
/// No accelerometer here (macOS, Linux): squint via double-tap or `squintTrigger` instead.
@MainActor
final class ShakeSource {
    func start(_ handler: @escaping @MainActor (Double, Double, Double) -> Void) {}
    func stop() {}
}
#endif

// MARK: - Layout & drawing

struct EyesLayout {
    let left: Vec2
    let right: Vec2
    let radius: Double
    let center: Vec2
    /// Finger distance (from between the eyes) at which the gaze is fully turned.
    let reach: Double

    init(size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        radius = max(min(w * 0.19, h * 0.36), 1)
        center = Vec2(w / 2, h / 2)
        left = center - Vec2(radius * 1.18, 0)
        right = center + Vec2(radius * 1.18, 0)
        reach = max(w * 0.55, 1)
    }
}

struct EyesRenderer {
    let lidColor: Color
    let irisColor: Color

    static let outline = Color(red: 0.24, green: 0.15, blue: 0.10)

    func draw(_ frame: EyesFrame, layout: EyesLayout, in context: inout GraphicsContext) {
        drawEye(at: layout.left, radius: layout.radius, gaze: frame.gaze, lid: frame.leftLid, squint: frame.squint, in: &context)
        drawEye(at: layout.right, radius: layout.radius, gaze: frame.gaze, lid: frame.rightLid, squint: frame.squint, in: &context)
    }

    private func drawEye(at c: Vec2, radius r: Double, gaze: Vec2, lid: Double, squint: Double, in context: inout GraphicsContext) {
        let ball = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        // Soft drop shadow under the eyeball.
        context.fill(ball.offsetBy(dx: 0, dy: r * 0.06), with: .color(Self.outline.opacity(0.18)))

        var eye = context
        eye.clip(to: ball)

        // Sclera: white with a cool falloff, lit from the top-left.
        eye.fill(ball, with: .radialGradient(
            Gradient(colors: [.white, Color(red: 0.86, green: 0.88, blue: 0.93)]),
            center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.35), startRadius: 0, endRadius: r * 1.5
        ))

        // Iris + pupil, offset by the gaze but clamped so the iris stays inside the eye.
        let irisR = r * 0.46
        let o = EyeGeometry.irisOffset(gaze: gaze, eyeRadius: r, irisRadius: irisR)
        let ic = c + o
        let iris = Path(ellipseIn: CGRect(x: ic.x - irisR, y: ic.y - irisR, width: 2 * irisR, height: 2 * irisR))
        eye.fill(iris, with: .radialGradient(
            Gradient(colors: [irisColor.opacity(0.75), irisColor, Color(red: 0.06, green: 0.18, blue: 0.22)]),
            center: CGPoint(x: ic.x, y: ic.y + irisR * 0.2), startRadius: 0, endRadius: irisR
        ))
        eye.stroke(iris, with: .color(.black.opacity(0.35)), lineWidth: max(r * 0.025, 0.5))
        let pupilR = irisR * 0.5
        eye.fill(Path(ellipseIn: CGRect(x: ic.x - pupilR, y: ic.y - pupilR, width: 2 * pupilR, height: 2 * pupilR)),
                 with: .color(Color(white: 0.04)))
        // Catch-lights: fixed relative to the light, not the gaze.
        for (dx, dy, s, a) in [(-0.38, -0.42, 0.24, 0.95), (0.32, 0.30, 0.10, 0.7)] {
            let hr = irisR * s
            let hc = ic + Vec2(dx, dy) * irisR
            eye.fill(Path(ellipseIn: CGRect(x: hc.x - hr, y: hc.y - hr, width: 2 * hr, height: 2 * hr)),
                     with: .color(.white.opacity(a)))
        }

        // Lower lid rises with the squint.
        let lowerEdge = c.y + r * 1.25 - squint * r * 0.45
        var lower = Path()
        lower.move(to: CGPoint(x: c.x - r * 1.1, y: c.y + r * 1.2))
        lower.addLine(to: CGPoint(x: c.x - r * 1.1, y: lowerEdge))
        lower.addQuadCurve(to: CGPoint(x: c.x + r * 1.1, y: lowerEdge), control: CGPoint(x: c.x, y: lowerEdge - r * 0.5))
        lower.addLine(to: CGPoint(x: c.x + r * 1.1, y: c.y + r * 1.2))
        lower.closeSubpath()
        eye.fill(lower, with: .color(lidColor))

        // Upper lid: the edge follows the eyeball (convex downward) and sweeps down as it closes.
        let l = min(max(lid, 0), 1)
        let edge = c.y - r * 1.25 + l * r * 2.15
        let sag = r * 0.5 * (1 - 0.6 * l)
        var upperEdge = Path()
        upperEdge.move(to: CGPoint(x: c.x - r * 1.1, y: edge))
        upperEdge.addQuadCurve(to: CGPoint(x: c.x + r * 1.1, y: edge), control: CGPoint(x: c.x, y: edge + sag))
        var upper = upperEdge
        upper.addLine(to: CGPoint(x: c.x + r * 1.1, y: c.y - r * 1.2))
        upper.addLine(to: CGPoint(x: c.x - r * 1.1, y: c.y - r * 1.2))
        upper.closeSubpath()
        // Opaque lid, then a faint shade toward the lash line (a translucent lid would show the iris).
        eye.fill(upper, with: .color(lidColor))
        eye.fill(upper, with: .linearGradient(
            Gradient(colors: [.black.opacity(0), .black.opacity(0.07)]),
            startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: edge + sag)
        ))
        eye.stroke(upperEdge, with: .color(Self.outline), style: StrokeStyle(lineWidth: max(r * 0.07, 1), lineCap: .round))

        context.stroke(ball, with: .color(Self.outline), lineWidth: max(r * 0.05, 1))
    }
}

// MARK: - Preview

private struct AliveEyesDemo: View {
    @State private var squints = 0
    private let face = Color(red: 0.98, green: 0.80, blue: 0.56)

    var body: some View {
        VStack(spacing: 20) {
            AliveEyesView(seed: 7, lidColor: face, squintTrigger: squints)
                .frame(height: 260)
                .background(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(face)
                        .shadow(color: .black.opacity(0.15), radius: 14, y: 8)
                )
                .padding(.horizontal)
            Text("Drag to make them look. Shake to squint.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Squint") { squints += 1 }
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Alive Eyes") {
    AliveEyesDemo()
}
#endif
