//
//  OnAirLampToggle.swift
//  OnAirLampToggle
//
//  A machined aluminium pill. The knob is a glass lens: smoked while off, red and blooming
//  while on. One spring drives the throw, and the room behind the lamp is multiplied toward
//  near-black by that same progress. ON AIR, a timer and a level meter fade in underneath.
//  While live the lens breathes. Reduce Motion crossfades the throw and holds the breath still.
//  The spring, the threshold and the clock live in OnAirCore.

#if canImport(SwiftUI)
import SwiftUI
import OnAirCore

/// An on-air lamp switch.
///
/// ```swift
/// OnAirLampToggle(isOn: $isLive)
/// ```
///
/// The control fills its parent and draws the studio it dims. Drag the pill; past halfway
/// it commits. A short tap toggles.
public struct OnAirLampToggle: View {
    @Binding private var isOn: Bool
    @State private var model: OnAirModel
    @State private var gate: OnAirBindingGate
    @State private var lastDate: Date?
    @State private var hapticTick = 0
    @State private var trackingDrag = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(isOn: Binding<Bool>) {
        _isOn = isOn
        _model = State(initialValue: OnAirModel(isOn: isOn.wrappedValue))
        _gate = State(initialValue: OnAirBindingGate(isOn.wrappedValue))
    }

    public var body: some View {
        TimelineView(.animation(paused: !model.needsClock)) { timeline in
            GeometryReader { geo in
                let scale = fitScale(in: geo.size)
                let originX = (geo.size.width - OnAirTuning.sceneWidth * scale) / 2
                let originY = (geo.size.height - OnAirTuning.sceneHeight * scale) / 2
                ZStack(alignment: .topLeading) {
                    Canvas { context, _ in
                        drawRoom(&context)
                    }
                    .colorMultiply(Color(white: model.backgroundMultiply))
                    .frame(width: OnAirTuning.sceneWidth, height: OnAirTuning.sceneHeight)
                    .accessibilityHidden(true)

                    Canvas { context, _ in
                        drawLamp(&context)
                    }
                    .frame(width: OnAirTuning.sceneWidth, height: OnAirTuning.sceneHeight)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(width: OnAirTuning.sceneWidth, height: OnAirTuning.sceneHeight, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .offset(x: originX, y: originY)
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(drag(scale: scale, originX: originX, originY: originY))
                .onChange(of: timeline.date) { _, now in advance(to: now) }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.62), trigger: hapticTick)
        .onAppear {
            model.setReduceMotion(reduceMotion)
            if isOn != model.isOn { note(model.setOn(isOn)) }
        }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .onChange(of: isOn) { _, newValue in
            // A parent write during a drag is held. Applying it now would fight the finger,
            // and dropping it would leave the binding off while the lamp stays on.
            guard gate.receive(newValue, dragging: model.isDragging) else { return }
            guard newValue != model.isOn else { return }
            note(model.setOn(newValue))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("On air")
        .accessibilityValue(model.accessibilityValue)
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint(model.isOn ? "Double tap to leave the air" : "Double tap to go on air")
        .accessibilityAction { note(model.toggle()) }
    }

    private func fitScale(in size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        return min(size.width / OnAirTuning.sceneWidth, size.height / OnAirTuning.sceneHeight)
    }

    private func drag(scale: CGFloat, originX: CGFloat, originY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard scale > 0 else { return }
                let x = (value.location.x - originX) / scale
                let y = (value.location.y - originY) / scale
                if !trackingDrag {
                    trackingDrag = model.beginDrag(sceneX: Double(x), sceneY: Double(y))
                } else {
                    model.updateDrag(sceneX: Double(x))
                }
            }
            .onEnded { value in
                let travel = scale > 0 ? Double(value.translation.width / scale) : 0
                if trackingDrag {
                    note(model.endDrag(translation: travel))
                } else if abs(travel) <= OnAirTuning.tapSlop {
                    note(model.toggle())
                }
                trackingDrag = false
                // Republish even when the release commits the state the model already had,
                // so a binding flipped during the drag cannot be left behind.
                let published = gate.finishGesture(modelOn: model.isOn)
                if isOn != published { isOn = published }
            }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        note(model.step(now.timeIntervalSince(last)))
    }

    private func note(_ events: [OnAirEvent]) {
        for event in events {
            switch event {
            case .haptic:
                hapticTick += 1
            case .committed(let on):
                if isOn != on { isOn = on }
            }
        }
    }

    // MARK: room
    // The room is the only layer under colorMultiply, so the spring's progress is what
    // takes the studio to near-black. The lamp is drawn on top and stays bright.

    private func drawRoom(_ ctx: inout GraphicsContext) {
        let w = OnAirTuning.sceneWidth
        let h = OnAirTuning.sceneHeight
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .linearGradient(
                Gradient(colors: [rgb(0.965, 0.945, 0.910), rgb(0.902, 0.855, 0.784)]),
                startPoint: CGPoint(x: w / 2, y: 0),
                endPoint: CGPoint(x: w / 2, y: h)
            )
        )
        ctx.fill(
            Path(CGRect(x: 0, y: 748, width: w, height: h - 748)),
            with: .color(rgb(0.855, 0.792, 0.710))
        )

        let frame = CGRect(x: 214, y: 186, width: 132, height: 158)
        ctx.fill(Path(roundedRect: frame, cornerRadius: 18), with: .color(rgb(0.769, 0.710, 0.627)))
        let pane = frame.insetBy(dx: 8, dy: 8)
        ctx.fill(
            Path(roundedRect: pane, cornerRadius: 12),
            with: .linearGradient(
                Gradient(colors: [rgb(0.557, 0.722, 0.847), rgb(0.953, 0.843, 0.690)]),
                startPoint: CGPoint(x: pane.midX, y: pane.minY),
                endPoint: CGPoint(x: pane.midX, y: pane.maxY)
            )
        )
        var hill = Path()
        hill.move(to: CGPoint(x: pane.minX, y: pane.maxY))
        hill.addLine(to: CGPoint(x: pane.minX, y: pane.maxY - 36))
        hill.addQuadCurve(to: CGPoint(x: pane.maxX, y: pane.maxY - 28), control: CGPoint(x: pane.midX, y: pane.maxY - 62))
        hill.addLine(to: CGPoint(x: pane.maxX, y: pane.maxY))
        hill.closeSubpath()
        ctx.fill(hill, with: .color(rgb(0.498, 0.604, 0.471)))
        var mullion = Path()
        mullion.move(to: CGPoint(x: pane.midX, y: pane.minY))
        mullion.addLine(to: CGPoint(x: pane.midX, y: pane.maxY))
        mullion.move(to: CGPoint(x: pane.minX, y: pane.midY))
        mullion.addLine(to: CGPoint(x: pane.maxX, y: pane.midY))
        ctx.stroke(mullion, with: .color(rgb(0.769, 0.710, 0.627)), lineWidth: 4)

        drawPlant(&ctx)
        drawMic(&ctx)

        let word = ctx.resolve(
            Text(OnAirTuning.wordmark)
                .font(.system(size: 40, weight: .medium, design: .serif))
                .foregroundColor(rgb(0.165, 0.149, 0.133))
        )
        ctx.draw(word, at: CGPoint(x: w / 2, y: OnAirTuning.wordmarkY), anchor: .center)
        let sub = ctx.resolve(
            Text(OnAirTuning.subtitle)
                .font(.system(size: 12, weight: .semibold))
                .tracking(3)
                .foregroundColor(rgb(0.541, 0.506, 0.471))
        )
        ctx.draw(sub, at: CGPoint(x: w / 2, y: OnAirTuning.subtitleY), anchor: .center)
    }

    private func drawPlant(_ ctx: inout GraphicsContext) {
        ctx.fill(Path(ellipseIn: CGRect(x: 62, y: 300, width: 36, height: 18)), with: .color(rgb(0.420, 0.510, 0.345).opacity(0.9)))
        ctx.fill(Path(ellipseIn: CGRect(x: 48, y: 286, width: 28, height: 22)), with: .color(rgb(0.345, 0.455, 0.290)))
        ctx.fill(Path(ellipseIn: CGRect(x: 78, y: 280, width: 26, height: 24)), with: .color(rgb(0.455, 0.545, 0.360)))
        let pot = CGRect(x: 64, y: 312, width: 28, height: 22)
        ctx.fill(Path(roundedRect: pot, cornerRadius: 3), with: .color(rgb(0.545, 0.310, 0.235)))
    }

    private func drawMic(_ ctx: inout GraphicsContext) {
        var stand = Path()
        stand.move(to: CGPoint(x: 158, y: 268))
        stand.addLine(to: CGPoint(x: 158, y: 392))
        ctx.stroke(stand, with: .color(rgb(0.227, 0.212, 0.196)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: 136, y: 388, width: 44, height: 10)), with: .color(rgb(0.227, 0.212, 0.196)))
        let head = CGRect(x: 136, y: 228, width: 44, height: 52)
        ctx.fill(Path(roundedRect: head, cornerRadius: 22), with: .color(rgb(0.165, 0.153, 0.145)))
        ctx.fill(
            Path(roundedRect: head.insetBy(dx: 6, dy: 8), cornerRadius: 16),
            with: .linearGradient(
                Gradient(colors: [rgb(0.788, 0.635, 0.478), rgb(0.478, 0.365, 0.275)]),
                startPoint: CGPoint(x: head.minX, y: head.minY),
                endPoint: CGPoint(x: head.maxX, y: head.maxY)
            )
        )
    }

    // MARK: lamp

    private func drawLamp(_ ctx: inout GraphicsContext) {
        let center = model.knobCenter
        let glow = model.glow
        let chrome = model.chromeOpacity
        if glow > 0.01 {
            let radius = 168 + 28 * glow
            ctx.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .radialGradient(
                    Gradient(colors: [
                        rgb(1, 0.18, 0.10).opacity(0.55 * glow),
                        rgb(1, 0.05, 0.02).opacity(0.16 * glow),
                        rgb(1, 0, 0).opacity(0),
                    ]),
                    center: CGPoint(x: center.x, y: center.y),
                    startRadius: 8,
                    endRadius: radius
                )
            )
        }

        let pill = CGRect(x: OnAirTuning.pillX, y: OnAirTuning.pillY, width: OnAirTuning.pillWidth, height: OnAirTuning.pillHeight)
        let shell = Path(roundedRect: pill, cornerRadius: pill.height / 2)
        ctx.fill(
            Path(ellipseIn: CGRect(x: pill.minX + 24, y: pill.maxY - 10, width: pill.width - 48, height: 22)),
            with: .radialGradient(
                Gradient(colors: [Color.black.opacity(0.22), Color.black.opacity(0)]),
                center: CGPoint(x: pill.midX, y: pill.maxY),
                startRadius: 2,
                endRadius: 70
            )
        )
        ctx.fill(
            shell,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: rgb(0.973, 0.961, 0.945), location: 0),
                    .init(color: rgb(0.851, 0.831, 0.800), location: 0.18),
                    .init(color: rgb(0.718, 0.694, 0.659), location: 0.48),
                    .init(color: rgb(0.561, 0.537, 0.510), location: 0.74),
                    .init(color: rgb(0.831, 0.812, 0.780), location: 1),
                ]),
                startPoint: CGPoint(x: pill.midX, y: pill.minY),
                endPoint: CGPoint(x: pill.midX, y: pill.maxY)
            )
        )
        ctx.drawLayer { layer in
            layer.clip(to: shell)
            var grain = Path()
            let rows = 16
            for row in 0..<rows {
                let y = pill.minY + (Double(row) + 0.5) * pill.height / Double(rows)
                grain.move(to: CGPoint(x: pill.minX, y: y))
                grain.addLine(to: CGPoint(x: pill.maxX, y: y))
            }
            layer.stroke(grain, with: .color(.white.opacity(0.16)), lineWidth: 1)
        }
        if glow > 0.02 {
            ctx.drawLayer { layer in
                layer.clip(to: shell)
                layer.fill(shell, with: .color(rgb(1, 0.22, 0.12).opacity(0.22 * glow)))
            }
        }
        ctx.stroke(shell, with: .color(.white.opacity(0.45)), lineWidth: 1)

        let channel = pill.insetBy(dx: 8, dy: 8)
        let groove = Path(roundedRect: channel, cornerRadius: channel.height / 2)
        ctx.fill(
            groove,
            with: .linearGradient(
                Gradient(colors: [rgb(0.361, 0.337, 0.314), rgb(0.145, 0.137, 0.129)]),
                startPoint: CGPoint(x: channel.midX, y: channel.minY),
                endPoint: CGPoint(x: channel.midX, y: channel.maxY)
            )
        )

        let knob = OnAirTuning.knobDiameter
        let bezelRect = CGRect(x: center.x - knob / 2, y: center.y - knob / 2, width: knob, height: knob)
        ctx.fill(
            Path(ellipseIn: bezelRect.offsetBy(dx: 0, dy: 2)),
            with: .color(Color.black.opacity(0.28))
        )
        ctx.fill(
            Path(ellipseIn: bezelRect),
            with: .linearGradient(
                Gradient(colors: [rgb(0.965, 0.949, 0.925), rgb(0.494, 0.471, 0.435)]),
                startPoint: CGPoint(x: bezelRect.minX, y: bezelRect.minY),
                endPoint: CGPoint(x: bezelRect.maxX, y: bezelRect.maxY)
            )
        )
        let lensR = knob / 2 - 5
        let lens = CGRect(x: center.x - lensR, y: center.y - lensR, width: lensR * 2, height: lensR * 2)
        ctx.fill(
            Path(ellipseIn: lens),
            with: .radialGradient(
                Gradient(colors: [rgb(0.361, 0.384, 0.408), rgb(0.071, 0.078, 0.086)]),
                center: CGPoint(x: center.x - 6, y: center.y - 8),
                startRadius: 2,
                endRadius: lensR
            )
        )
        if glow > 0.001 {
            ctx.fill(
                Path(ellipseIn: lens),
                with: .radialGradient(
                    Gradient(colors: [
                        rgb(1, 0.816, 0.784).opacity(glow),
                        rgb(1, 0.165, 0.102).opacity(glow),
                        rgb(0.557, 0, 0.031).opacity(glow),
                    ]),
                    center: CGPoint(x: center.x, y: center.y),
                    startRadius: 1,
                    endRadius: lensR
                )
            )
        }
        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - lensR * 0.55, y: center.y - lensR * 0.62, width: lensR * 0.55, height: lensR * 0.32)),
            with: .color(.white.opacity(0.42 * (1 - 0.35 * glow)))
        )

        guard chrome > 0.01 else { return }
        ctx.drawLayer { layer in
            layer.opacity = chrome
            let label = layer.resolve(
                Text(OnAirTuning.onAirLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(3.5)
                    .foregroundColor(rgb(1, 0.231, 0.188))
            )
            layer.draw(label, at: CGPoint(x: OnAirTuning.sceneWidth / 2 + 8, y: OnAirTuning.onAirY), anchor: .center)
            layer.fill(
                Path(ellipseIn: CGRect(x: OnAirTuning.sceneWidth / 2 - 46, y: OnAirTuning.onAirY - 4, width: 8, height: 8)),
                with: .color(rgb(1, 0.231, 0.188))
            )
            let timer = layer.resolve(
                Text(model.timerText)
                    .font(.system(size: 32, weight: .medium, design: .monospaced))
                    .foregroundColor(rgb(1, 0.945, 0.925))
            )
            layer.draw(timer, at: CGPoint(x: OnAirTuning.sceneWidth / 2, y: OnAirTuning.timerY), anchor: .center)
            drawMeter(&layer)
        }
    }

    private func drawMeter(_ ctx: inout GraphicsContext) {
        let levels = model.meter
        let count = levels.count
        let width = OnAirTuning.meterBarWidth
        let gap = OnAirTuning.meterGap
        let total = Double(count) * width + Double(count - 1) * gap
        let origin = OnAirTuning.sceneWidth / 2 - total / 2
        let base = OnAirTuning.meterY + OnAirTuning.meterMaxHeight
        for (index, level) in levels.enumerated() {
            let barH = max(3, OnAirTuning.meterMaxHeight * level)
            let x = origin + Double(index) * (width + gap)
            let rect = CGRect(x: x, y: base - barH, width: width, height: barH)
            ctx.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(rgb(1, 0.231, 0.188)))
        }
    }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }
}

/// The gallery page: the lamp on the Murmur studio, starting off air.
public struct OnAirLampToggleDemo: View {
    @State private var isOn = false

    public init() {}

    public var body: some View {
        OnAirLampToggle(isOn: $isOn)
            .background(Color(red: 0.965, green: 0.945, blue: 0.910))
    }
}

#Preview("On Air") {
    OnAirLampToggleDemo()
}
#endif
