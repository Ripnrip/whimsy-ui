//
//  PinataReward.swift
//  PinataReward
//
//  A piñata on a ribbon. It swings on a damped spring pendulum from the peg, and each tap
//  kicks it the other way, a little harder than the last, with a glow, an impact haptic and
//  a handful of candies. Cracks accumulate. On the eighth hit the body splits, the halves
//  fall away, and a token bursts in while the pill changes from "Keep tapping" to
//  "Come back tomorrow". Reduce Motion holds the body still, skips the particles, and fades
//  the token in over the same hit count.
//  The pendulum, the impulses, the seeded candy and the burst all live in PinataCore.

#if canImport(SwiftUI)
import SwiftUI
import PinataCore

/// A piñata you tap until it breaks.
///
/// ```swift
/// PinataReward()
/// PinataReward(hitsToBreak: 8) { grantReward() }
/// ```
public struct PinataReward: View {
    private let onBurst: () -> Void
    private let resetToken: Int

    @State private var model: PinataModel
    @State private var lastDate: Date? = nil
    @State private var hitTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(hitsToBreak: Int = PinataTuning.defaultHits, seed: UInt64 = PinataTuning.defaultSeed, resetToken: Int = 0, onBurst: @escaping () -> Void = {}) {
        self.onBurst = onBurst
        self.resetToken = resetToken
        _model = State(initialValue: PinataModel(hitsToBreak: hitsToBreak, seed: seed))
    }

    public var body: some View {
        TimelineView(.animation(paused: model.isAtRest)) { timeline in
            Canvas { ctx, _ in
                drawBackdrop(&ctx)
                drawPegAndRibbon(&ctx)
                if model.phase == .intact {
                    drawGlow(&ctx, at: model.bodyCenter)
                    drawBody(&ctx, at: model.bodyCenter, angle: model.angle, clip: .both, opacity: 1)
                } else if model.reduceMotion {
                    drawBody(&ctx, at: model.bodyCenter, angle: 0, clip: .both, opacity: 1 - model.reveal)
                    drawToken(&ctx, opacity: model.reveal)
                } else {
                    for half in model.halves where half.opacity > 0.01 {
                        drawBody(&ctx, at: half.position, angle: half.angle,
                                 clip: half.side == .left ? .left : .right, opacity: half.opacity)
                    }
                    drawParticles(&ctx)
                    drawToken(&ctx, opacity: min(1, model.token.scale))
                }
                if model.phase == .intact { drawParticles(&ctx) }
                drawPips(&ctx)
                drawPill(&ctx)
            }
            .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
        .frame(width: PinataTuning.canvasWidth, height: PinataTuning.canvasHeight)
        .contentShape(Rectangle())
        .onTapGesture { location in
            handle(model.hit(at: Vec2(location.x, location.y)))
        }
        .sensoryFeedback(trigger: hitTick) { old, new in
            guard new > old, model.hits > 0 else { return nil }
            let intensity = min(1, 0.4 + 0.075 * Double(model.hits))
            let weight: SensoryFeedback.Weight = model.hits >= model.hitsToBreak ? .heavy : .medium
            return .impact(weight: weight, intensity: intensity)
        }
        .onAppear { model.setReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .onChange(of: resetToken) { _, _ in
            model.reset()
            model.setReduceMotion(reduceMotion)
            lastDate = nil
        }
        .accessibilityElement()
        .accessibilityLabel("Piñata")
        .accessibilityValue(model.accessibilityValue)
        .accessibilityHint(model.phase == .intact ? "Double tap to hit" : "Come back tomorrow")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { handle(model.hitForAccessibility()) }
        .accessibilityAction(named: "Hit") { handle(model.hitForAccessibility()) }
    }

    private enum Clip { case both, left, right }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        handle(model.step(now.timeIntervalSince(last)))
    }

    private func handle(_ events: [PinataEvent]) {
        for event in events {
            switch event {
            case .hit:
                hitTick += 1
            case .burst:
                onBurst()
            case .settled:
                break
            }
        }
    }

    // MARK: drawing

    private func drawBackdrop(_ ctx: inout GraphicsContext) {
        let rect = CGRect(x: 0, y: 0, width: PinataTuning.canvasWidth, height: PinataTuning.canvasHeight)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 28), with: .linearGradient(
            Gradient(colors: [
                Color(red: 0.12, green: 0.06, blue: 0.22),
                Color(red: 0.36, green: 0.12, blue: 0.32),
                Color(red: 0.72, green: 0.38, blue: 0.28),
            ]),
            startPoint: CGPoint(x: 160, y: 0), endPoint: CGPoint(x: 160, y: 480)))
        // A few still stars, placed by hand so the card doesn't shimmer.
        let stars = [(40, 36), (78, 70), (250, 48), (286, 90), (210, 28), (120, 54)]
        for star in stars {
            ctx.fill(Path(ellipseIn: CGRect(x: star.0, y: star.1, width: 3, height: 3)),
                     with: .color(.white.opacity(0.7)))
        }
    }

    private func drawPegAndRibbon(_ ctx: inout GraphicsContext) {
        let peg = CGPoint(x: PinataTuning.anchorX, y: PinataTuning.anchorY)
        ctx.fill(Path(ellipseIn: CGRect(x: peg.x - 7, y: peg.y - 7, width: 14, height: 14)),
                 with: .color(Color(red: 0.45, green: 0.28, blue: 0.16)))
        guard model.phase == .intact else {
            var stub = Path()
            stub.move(to: peg)
            stub.addLine(to: CGPoint(x: peg.x, y: peg.y + 16))
            ctx.stroke(stub, with: .color(Color(red: 0.86, green: 0.24, blue: 0.32)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))
            return
        }
        let crown = model.pendulum.world(Vec2(0, -PinataTuning.bodyRadiusY))
        var ribbon = Path()
        ribbon.move(to: peg)
        ribbon.addLine(to: CGPoint(x: crown.x, y: crown.y))
        ctx.stroke(ribbon, with: .color(Color(red: 0.86, green: 0.24, blue: 0.32)),
                   style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    private func drawGlow(_ ctx: inout GraphicsContext, at center: Vec2) {
        guard model.glow > 0.02 else { return }
        let r = 92.0
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(
                    Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.55).opacity(0.85 * model.glow), .clear]),
                    center: CGPoint(x: center.x, y: center.y), startRadius: 8, endRadius: r))
    }

    private func drawBody(_ ctx: inout GraphicsContext, at center: Vec2, angle: Double, clip: Clip, opacity: Double) {
        guard opacity > 0.01 else { return }
        ctx.drawLayer { layer in
            layer.opacity = opacity
            layer.translateBy(x: center.x, y: center.y)
            // SwiftUI rotates clockwise for a positive angle. The pendulum frame is the other way:
            // local (x, y) maps to (x cos + y sin, −x sin + y cos), so the crown stays on the ribbon.
            layer.rotate(by: .radians(-angle))
            switch clip {
            case .both: break
            case .left:
                layer.clip(to: Path(CGRect(x: -220, y: -220, width: 220, height: 440)))
            case .right:
                layer.clip(to: Path(CGRect(x: 0, y: -220, width: 220, height: 440)))
            }
            drawLocalBody(&layer)
            drawCracks(&layer)
        }
    }

    private func drawLocalBody(_ ctx: inout GraphicsContext) {
        let rx = PinataTuning.bodyRadiusX
        let ry = PinataTuning.bodyRadiusY
        let body = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
        ctx.drawLayer { layer in
            layer.clip(to: body)
            layer.fill(Path(CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)),
                       with: .color(Color(red: 0.93, green: 0.29, blue: 0.45)))
            layer.fill(Path(CGRect(x: -rx, y: -18, width: rx * 2, height: 22)),
                       with: .color(Color(red: 0.98, green: 0.78, blue: 0.28)))
            layer.fill(Path(CGRect(x: -rx, y: 16, width: rx * 2, height: 18)),
                       with: .color(Color(red: 0.28, green: 0.75, blue: 0.74)))
        }
        ctx.stroke(body, with: .color(Color(red: 0.45, green: 0.08, blue: 0.18).opacity(0.45)), lineWidth: 1.5)
        // Fringe along the lower half.
        let fringe = 14
        for i in 0..<fringe {
            let t = (Double(i) + 0.5) / Double(fringe)
            let a = Double.pi * (0.15 + 0.7 * t)
            let x = rx * 0.92 * cos(a)
            let y = ry * 0.55 + 10
            let color: Color = i % 3 == 0
                ? Color(red: 0.98, green: 0.78, blue: 0.28)
                : (i % 3 == 1 ? Color(red: 0.28, green: 0.75, blue: 0.74) : Color(red: 0.93, green: 0.29, blue: 0.45))
            let rect = CGRect(x: x - 4, y: y, width: 8, height: 18)
            ctx.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
        }
        // Face.
        ctx.fill(Path(ellipseIn: CGRect(x: -26, y: -36, width: 16, height: 18)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: 10, y: -36, width: 16, height: 18)), with: .color(.white))
        ctx.fill(Path(ellipseIn: CGRect(x: -20, y: -30, width: 7, height: 8)), with: .color(Color(red: 0.18, green: 0.08, blue: 0.14)))
        ctx.fill(Path(ellipseIn: CGRect(x: 14, y: -30, width: 7, height: 8)), with: .color(Color(red: 0.18, green: 0.08, blue: 0.14)))
        ctx.fill(Path(ellipseIn: CGRect(x: -34, y: -12, width: 12, height: 8)), with: .color(Color(red: 1, green: 0.55, blue: 0.62).opacity(0.85)))
        ctx.fill(Path(ellipseIn: CGRect(x: 22, y: -12, width: 12, height: 8)), with: .color(Color(red: 1, green: 0.55, blue: 0.62).opacity(0.85)))
        var smile = Path()
        smile.move(to: CGPoint(x: -12, y: 2))
        smile.addQuadCurve(to: CGPoint(x: 12, y: 2), control: CGPoint(x: 0, y: 16))
        ctx.stroke(smile, with: .color(Color(red: 0.35, green: 0.08, blue: 0.14)),
                   style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }

    private func drawCracks(_ ctx: inout GraphicsContext) {
        for crack in model.cracks {
            guard crack.points.count >= 2 else { continue }
            var path = Path()
            path.move(to: CGPoint(x: crack.points[0].x, y: crack.points[0].y))
            for point in crack.points.dropFirst() {
                path.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            ctx.stroke(path, with: .color(Color(red: 0.16, green: 0.05, blue: 0.1).opacity(0.9)),
                       style: StrokeStyle(lineWidth: 1.6 + crack.span / 40, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawParticles(_ ctx: inout GraphicsContext) {
        guard !model.reduceMotion else { return }
        let colors = Self.candyColors
        for p in model.particles where p.opacity > 0.02 {
            let color = colors[p.colorIndex % colors.count].opacity(p.opacity)
            ctx.drawLayer { layer in
                layer.translateBy(x: p.position.x, y: p.position.y)
                layer.rotate(by: .radians(p.rotation))
                let s = p.size
                switch p.shape {
                case 1:
                    layer.fill(Path(roundedRect: CGRect(x: -s, y: -s * 0.62, width: s * 2, height: s * 1.24), cornerRadius: 2),
                               with: .color(color))
                case 2:
                    var tri = Path()
                    tri.move(to: CGPoint(x: 0, y: -s))
                    tri.addLine(to: CGPoint(x: s, y: s * 0.8))
                    tri.addLine(to: CGPoint(x: -s, y: s * 0.8))
                    tri.closeSubpath()
                    layer.fill(tri, with: .color(color))
                default:
                    layer.fill(Path(ellipseIn: CGRect(x: -s * 0.7, y: -s * 0.7, width: s * 1.4, height: s * 1.4)),
                               with: .color(color))
                }
            }
        }
    }

    private func drawToken(_ ctx: inout GraphicsContext, opacity: Double) {
        guard model.token.present, opacity > 0.01 else { return }
        let c = model.tokenPosition
        let s = 0.4 + 0.6 * min(1, max(0, model.token.scale))
        ctx.drawLayer { layer in
            layer.opacity = opacity
            layer.translateBy(x: c.x, y: c.y)
            layer.scaleBy(x: s, y: s)
            layer.fill(Path(ellipseIn: CGRect(x: -22, y: -22, width: 44, height: 44)),
                       with: .color(Color(red: 0.98, green: 0.78, blue: 0.28)))
            layer.stroke(Path(ellipseIn: CGRect(x: -16, y: -16, width: 32, height: 32)),
                         with: .color(Color(red: 0.72, green: 0.48, blue: 0.1)), lineWidth: 2)
            var star = Path()
            for i in 0..<10 {
                let a = Double(i) / 10 * Double.pi * 2 - Double.pi / 2
                let r = i % 2 == 0 ? 10.0 : 4.5
                let point = CGPoint(x: cos(a) * r, y: sin(a) * r)
                if i == 0 { star.move(to: point) } else { star.addLine(to: point) }
            }
            star.closeSubpath()
            layer.fill(star, with: .color(Color(red: 0.55, green: 0.28, blue: 0.08)))
        }
    }

    private func drawPips(_ ctx: inout GraphicsContext) {
        let count = model.hitsToBreak
        let gap = 14.0
        let total = gap * Double(count - 1)
        let origin = PinataTuning.canvasWidth / 2 - total / 2
        for i in 0..<count {
            let filled = i < model.hits
            let rect = CGRect(x: origin + Double(i) * gap - 4, y: 404, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: rect), with: .color(filled
                ? Color(red: 0.98, green: 0.78, blue: 0.28)
                : Color.white.opacity(0.28)))
        }
    }

    private func drawPill(_ ctx: inout GraphicsContext) {
        let text = model.pillText
        let wide = text.count > 16
        let w = wide ? 196.0 : 148.0
        let rect = CGRect(x: (PinataTuning.canvasWidth - w) / 2, y: 422, width: w, height: 34)
        let fill = model.phase == .intact
            ? Color.white.opacity(0.92)
            : Color(red: 0.98, green: 0.78, blue: 0.28)
        ctx.fill(Path(roundedRect: rect, cornerRadius: 17), with: .color(fill))
        ctx.draw(
            Text(text).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(Color(red: 0.22, green: 0.1, blue: 0.16)),
            at: CGPoint(x: PinataTuning.canvasWidth / 2, y: 439))
    }

    private static let candyColors: [Color] = [
        Color(red: 1.00, green: 0.36, blue: 0.56),
        Color(red: 1.00, green: 0.82, blue: 0.36),
        Color(red: 0.49, green: 0.87, blue: 0.80),
        Color(red: 0.55, green: 0.48, blue: 1.00),
        Color(red: 1.00, green: 0.54, blue: 0.30),
        Color(red: 0.96, green: 0.96, blue: 1.00),
    ]
}

/// The gallery page: the piñata, a running burst count, and a reset.
public struct PinataRewardDemo: View {
    @State private var resetToken = 0
    @State private var bursts = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            PinataReward(hitsToBreak: PinataTuning.defaultHits, resetToken: resetToken) {
                bursts += 1
            }
            Button("Reset") { resetToken += 1 }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.86, green: 0.24, blue: 0.32))
                .accessibilityHint("Restores the piñata")
            Text(bursts == 0 ? "Eight hits to break it" : "Burst \(bursts)×")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}

#Preview("Piñata") { PinataRewardDemo() }
#endif
