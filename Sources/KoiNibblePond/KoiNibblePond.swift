//
//  KoiNibblePond.swift
//  KoiNibblePond
//
//  A top-down pond. Six koi lap until a fingertip is held in the water: a ripple
//  opens, they steer in one after another, and each nibble ticks a light impact.
//  Letting go scatters them, then they drift back to the laps. Reduce Motion skips
//  the burst and fades the rings in place. The floor can wear a Metal caustic wash;
//  without it the Canvas paints the same light. The fish, the ripples and the clock
//  live in KoiPondCore.

#if canImport(SwiftUI)
import SwiftUI
import KoiPondCore

/// A pond you can hold a finger in.
///
/// ```swift
/// KoiNibblePond { feedTheCat() }
/// KoiNibblePond(koiCount: 6)
/// ```
///
/// `onNibble` runs once per peck. The view fills its parent and letterboxes the 390×844 pond.
public struct KoiNibblePond: View {
    private let onNibble: (() -> Void)?

    @State private var model: KoiPondModel
    @State private var lastDate: Date?
    @State private var touching = false
    @State private var nibbleTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(koiCount: Int = 6, onNibble: (() -> Void)? = nil) {
        self.onNibble = onNibble
        _model = State(initialValue: KoiPondModel(koiCount: koiCount))
    }

    public var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geo in
                let scale = fitScale(in: geo.size)
                let originX = (geo.size.width - KoiPondTuning.sceneWidth * scale) / 2
                let originY = (geo.size.height - KoiPondTuning.sceneHeight * scale) / 2
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        drawFloor(&context, caustics: !causticsShaderAvailable)
                    }
                    .frame(width: KoiPondTuning.sceneWidth, height: KoiPondTuning.sceneHeight)
                    .modifier(KoiCausticFloor(enabled: causticsShaderAvailable, time: model.swimTime))
                    .accessibilityHidden(true)

                    Canvas { context, _ in
                        drawLife(&context)
                    }
                    .frame(width: KoiPondTuning.sceneWidth, height: KoiPondTuning.sceneHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(width: KoiPondTuning.sceneWidth, height: KoiPondTuning.sceneHeight, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: originX, y: originY)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(drag(scale: scale, originX: originX, originY: originY))
                .onChange(of: timeline.date) { _, now in advance(to: now) }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: nibbleTick)
        .onAppear { model.setReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
        .accessibilityHint("Hold a fingertip in the water")
        .accessibilityAction(named: Text(KoiPondTuning.feedAction)) { note(model.feed()) }
    }

    /// The stitchable caustic is an iOS 17 / macOS 14 colorEffect. Older systems, and
    /// Reduce Motion, keep the Canvas wash instead.
    private var causticsShaderAvailable: Bool {
        if reduceMotion { return false }
        if #available(iOS 17.0, macOS 14.0, *) { return true }
        return false
    }

    private func fitScale(in size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        return min(size.width / KoiPondTuning.sceneWidth, size.height / KoiPondTuning.sceneHeight)
    }

    private func drag(scale: CGFloat, originX: CGFloat, originY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard scale > 0 else { return }
                let point = Vec2(
                    Double((value.location.x - originX) / scale),
                    Double((value.location.y - originY) / scale)
                )
                if !touching {
                    touching = true
                    note(model.beginTouch(at: point))
                } else {
                    model.updateTouch(at: point)
                }
            }
            .onEnded { _ in
                if touching { note(model.endTouch()) }
                touching = false
            }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        note(model.step(now.timeIntervalSince(last)))
    }

    private func note(_ events: [KoiPondEvent]) {
        for event in events {
            if case .nibble = event {
                nibbleTick += 1
                onNibble?()
            }
        }
    }

    // MARK: drawing

    private var pondRect: CGRect {
        CGRect(x: KoiPondTuning.pondX, y: KoiPondTuning.pondY, width: KoiPondTuning.pondWidth, height: KoiPondTuning.pondHeight)
    }

    private func drawFloor(_ context: inout GraphicsContext, caustics: Bool) {
        let w = KoiPondTuning.sceneWidth
        let h = KoiPondTuning.sceneHeight
        context.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(paint(KoiPondTuning.paper)))

        var shadow = Path(ellipseIn: pondRect)
        context.translateBy(x: 0, y: 8)
        context.fill(shadow, with: .color(Color.black.opacity(0.16)))
        context.translateBy(x: 0, y: -8)

        let pond = Path(ellipseIn: pondRect)
        let center = CGPoint(x: KoiPondTuning.pondCenter.x, y: KoiPondTuning.pondCenter.y)
        context.fill(
            pond,
            with: .radialGradient(
                Gradient(colors: [
                    paint(KoiPondTuning.waterShallow),
                    paint(KoiPondTuning.waterMid),
                    paint(KoiPondTuning.waterDeep),
                ]),
                center: CGPoint(x: center.x, y: center.y - 40),
                startRadius: 20,
                endRadius: KoiPondTuning.pondHeight / 2
            )
        )

        context.drawLayer { layer in
            layer.clip(to: pond)
            let sand = Path(CGRect(x: KoiPondTuning.pondX, y: KoiPondTuning.pondY, width: KoiPondTuning.pondWidth, height: KoiPondTuning.pondHeight))
            layer.fill(
                sand,
                with: .radialGradient(
                    Gradient(colors: [paint(KoiPondTuning.sand).opacity(0.28), paint(KoiPondTuning.sand).opacity(0)]),
                    center: CGPoint(x: center.x - 30, y: center.y + 80),
                    startRadius: 10,
                    endRadius: 180
                )
            )
            if caustics { drawCanvasCaustics(&layer) }
        }

        context.stroke(pond, with: .color(paint(KoiPondTuning.stone)), lineWidth: 10)
        context.stroke(pond, with: .color(Color.white.opacity(0.28)), lineWidth: 2)

        for (index, lily) in KoiPondTuning.lilies.enumerated() {
            drawLily(&context, x: lily.x, y: lily.y, radius: lily.r, flower: index == 1)
        }
        drawCopy(&context)
    }

    private func drawLife(_ context: inout GraphicsContext) {
        let pond = Path(ellipseIn: pondRect)
        context.drawLayer { layer in
            layer.clip(to: pond)
            for ripple in model.ripples {
                guard ripple.opacity > 0.01, ripple.radius > 0.5 else { continue }
                let rect = CGRect(
                    x: ripple.origin.x - ripple.radius,
                    y: ripple.origin.y - ripple.radius,
                    width: ripple.radius * 2,
                    height: ripple.radius * 2
                )
                layer.stroke(
                    Path(ellipseIn: rect),
                    with: .color(Color.white.opacity(ripple.opacity * 0.92)),
                    lineWidth: ripple.kind == .gather ? 2.2 : 1.3
                )
            }
            for fish in model.fish { drawFish(&layer, fish) }
            if model.phase == .arming || model.phase == .gathering { drawFinger(&layer) }
        }
    }

    private func drawCanvasCaustics(_ context: inout GraphicsContext) {
        let time = reduceMotion ? 0.4 : model.swimTime
        let center = KoiPondTuning.pondCenter
        for index in 0..<8 {
            let u = Double(index) / 8
            let x = center.x + KoiPondMath.sin(time * 0.65 + u * 6.2) * (70 + Double(index % 3) * 18)
            let y = center.y + KoiPondMath.cos(time * 0.42 + u * 4.4) * (120 + Double(index % 4) * 16)
            let radius = 38 + Double(index % 3) * 10
            let alpha = reduceMotion ? 0.09 : 0.16
            let blob = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            context.fill(
                Path(ellipseIn: blob),
                with: .radialGradient(
                    Gradient(colors: [Color(red: 0.84, green: 0.96, blue: 0.93).opacity(alpha), Color(red: 0.84, green: 0.96, blue: 0.93).opacity(0)]),
                    center: CGPoint(x: x, y: y),
                    startRadius: 1,
                    endRadius: radius
                )
            )
        }
    }

    private func drawLily(_ context: inout GraphicsContext, x: Double, y: Double, radius: Double, flower: Bool) {
        var pad = Path()
        pad.addArc(center: CGPoint(x: x, y: y), radius: radius, startAngle: .radians(0.45), endAngle: .radians(.pi * 2 + 0.15), clockwise: false)
        pad.addLine(to: CGPoint(x: x, y: y))
        pad.closeSubpath()
        context.fill(pad, with: .color(paint(KoiPondTuning.lily)))
        if flower {
            for petal in 0..<5 {
                let angle = Double(petal) * .pi * 2 / 5 - 0.4
                let rect = CGRect(x: x + cos(angle) * 6 - 4.5, y: y + sin(angle) * 6 - 2.6, width: 9, height: 5.2)
                context.fill(Path(ellipseIn: rect), with: .color(paint(KoiPondTuning.flower)))
            }
            let heart = CGRect(x: x - 2.4, y: y - 2.4, width: 4.8, height: 4.8)
            context.fill(Path(ellipseIn: heart), with: .color(paint(KoiPondTuning.sand)))
        }
    }

    private func drawFish(_ context: inout GraphicsContext, _ fish: KoiFish) {
        let spine = fish.posedSpine(at: model.swimTime)
        guard spine.count == KoiPondTuning.bodyWidths.count else { return }
        let palette = fish.palette
        let mid = spine[min(1, spine.count - 1)]
        let shadow = CGRect(x: mid.x - 14, y: mid.y, width: 32, height: 14)
        context.fill(Path(ellipseIn: shadow), with: .color(Color.black.opacity(0.14)))

        let body = ribbon(spine, KoiPondTuning.bodyWidths)
        context.fill(body, with: .color(paint(palette.body)))
        context.stroke(body, with: .color(Color.black.opacity(0.22)), lineWidth: 1)
        context.fill(ribbon(spine, KoiPondTuning.bodyWidths.map { $0 * 0.38 }), with: .color(paint(palette.belly)))

        let tail = spine[spine.count - 1]
        let prev = spine[spine.count - 2]
        let dx = tail.x - prev.x
        let dy = tail.y - prev.y
        let len = max((dx * dx + dy * dy).squareRoot(), 1)
        let ux = dx / len
        let uy = dy / len
        let px = -uy
        let py = ux
        var fin = Path()
        fin.move(to: CGPoint(x: prev.x, y: prev.y))
        fin.addQuadCurve(
            to: CGPoint(x: tail.x + ux * 18 + px * 12, y: tail.y + uy * 18 + py * 12),
            control: CGPoint(x: tail.x + px * 4, y: tail.y + py * 4)
        )
        fin.addQuadCurve(
            to: CGPoint(x: tail.x + ux * 18 - px * 12, y: tail.y + uy * 18 - py * 12),
            control: CGPoint(x: tail.x + ux * 8, y: tail.y + uy * 8)
        )
        fin.addQuadCurve(
            to: CGPoint(x: prev.x, y: prev.y),
            control: CGPoint(x: tail.x - px * 4, y: tail.y - py * 4)
        )
        context.fill(fin, with: .color(paint(palette.fin)))

        let head = spine[0]
        let hx = KoiPondMath.cos(fish.heading)
        let hy = KoiPondMath.sin(fish.heading)
        for side in [-1.0, 1.0] {
            let ex = head.x + hx * 3.5 - hy * 3.1 * side
            let ey = head.y + hy * 3.5 + hx * 3.1 * side
            context.fill(Path(ellipseIn: CGRect(x: ex - 1.7, y: ey - 1.7, width: 3.4, height: 3.4)), with: .color(Color(red: 0.11, green: 0.10, blue: 0.09)))
        }
    }

    private func drawFinger(_ context: inout GraphicsContext) {
        let x = model.finger.x
        let y = model.finger.y
        context.fill(Path(ellipseIn: CGRect(x: x - 13, y: y + 1, width: 28, height: 12)), with: .color(Color.black.opacity(0.12)))
        let disc = CGRect(x: x - 15, y: y - 15, width: 30, height: 30)
        context.fill(
            Path(ellipseIn: disc),
            with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.88, blue: 0.80), paint(KoiPondTuning.finger)]),
                center: CGPoint(x: x - 4, y: y - 5),
                startRadius: 2,
                endRadius: 16
            )
        )
        context.stroke(Path(ellipseIn: disc), with: .color(Color(red: 0.47, green: 0.28, blue: 0.23).opacity(0.35)), lineWidth: 1)
    }

    private func drawCopy(_ context: inout GraphicsContext) {
        let title = context.resolve(
            Text(KoiPondTuning.title)
                .font(.system(size: 36, weight: .medium, design: .serif))
                .foregroundColor(paint(KoiPondTuning.ink))
        )
        context.draw(title, at: CGPoint(x: KoiPondTuning.sceneWidth / 2, y: 72), anchor: .center)
        let caption = model.phase == .gathering ? "Nibbling" : KoiPondTuning.hint
        let hint = context.resolve(
            Text(caption)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(paint(KoiPondTuning.ink).opacity(0.62))
        )
        context.draw(hint, at: CGPoint(x: KoiPondTuning.sceneWidth / 2, y: 102), anchor: .center)
    }

    private func ribbon(_ spine: [Vec2], _ widths: [Double]) -> Path {
        var path = Path()
        guard spine.count > 1 else { return path }
        func side(_ index: Int, _ sign: Double) -> CGPoint {
            let n = normal(spine, index)
            let width = widths[min(index, widths.count - 1)]
            return CGPoint(x: spine[index].x + n.x * width * sign, y: spine[index].y + n.y * width * sign)
        }
        path.move(to: side(0, 1))
        for index in 1..<spine.count { path.addLine(to: side(index, 1)) }
        for index in stride(from: spine.count - 1, through: 0, by: -1) { path.addLine(to: side(index, -1)) }
        path.closeSubpath()
        return path
    }

    private func normal(_ spine: [Vec2], _ index: Int) -> (x: Double, y: Double) {
        let prev = spine[max(0, index - 1)]
        let next = spine[min(spine.count - 1, index + 1)]
        let dx = next.x - prev.x
        let dy = next.y - prev.y
        let len = max((dx * dx + dy * dy).squareRoot(), 1e-6)
        return (-dy / len, dx / len)
    }

    private func paint(_ rgb: KoiRGB) -> Color {
        Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b, opacity: 1)
    }
}

/// Applies the pond-floor caustic when the stitchable shader can load. The Canvas wash
/// stays in the view for Reduce Motion and for systems without the color effect.
private struct KoiCausticFloor: ViewModifier {
    var enabled: Bool
    var time: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            caustic(content)
        } else {
            content
        }
    }

    @ViewBuilder
    private func caustic(_ content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.colorEffect(
                ShaderLibrary.bundle(.module).koiCaustics(
                    .float(Float(time)),
                    .float2(Float(KoiPondTuning.sceneWidth), Float(KoiPondTuning.sceneHeight))
                )
            )
        } else {
            content
        }
    }
}

/// The gallery page: the pond, and a count of nibbles.
public struct KoiNibblePondDemo: View {
    @State private var nibbles = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            KoiNibblePond { nibbles += 1 }
            Text(nibbles == 0 ? "Hold the water" : "Nibbles \(nibbles)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Koi pond") { KoiNibblePondDemo() }
#endif
