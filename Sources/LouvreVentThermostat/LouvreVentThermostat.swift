//
//  LouvreVentThermostat.swift
//  LouvreVentThermostat
//
//  Seven steel blades in a frame, over a hot chamber. A vertical drag sets the
//  temperature. Hotter opens the blades on X (rotation3DEffect, 0° closed to
//  70° open) and the gaps go from deep orange to white-hot. A highlight slides
//  down each face as it turns. The spring, the glow and the ticks live in
//  LouvreVentCore. Reduce Motion snaps the angle and the glow and skips the sweep.
//

#if canImport(SwiftUI)
import SwiftUI
@_exported import LouvreVentCore

/// A steel louvre vent used as a thermostat.
///
/// ```swift
/// LouvreVentThermostat(temperature: $setPoint)
/// LouvreVentThermostat(temperature: $setPoint, range: 60...85)
/// ```
///
/// Drag up to raise the set point. Each integer degree ticks a soft haptic.
/// VoiceOver is adjustable by one degree. Reduce Motion snaps the blades and
/// holds the highlight still.
public struct LouvreVentThermostat: View {
    @Binding private var temperature: Int
    private let range: ClosedRange<Int>

    @State private var model: LouvreVentModel
    @State private var lastDate: Date?
    @State private var ticks = 0
    @State private var pendingTicks = 0
    @State private var tracking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        temperature: Binding<Int>,
        range: ClosedRange<Int> = LouvreVentTuning.defaultLower...LouvreVentTuning.defaultUpper
    ) {
        _temperature = temperature
        self.range = range
        _model = State(initialValue: LouvreVentModel(temperature: temperature.wrappedValue, range: range))
    }

    public var body: some View {
        TimelineView(.animation(paused: !model.animates && pendingTicks == 0)) { timeline in
            GeometryReader { geo in
                let scale = fitScale(in: geo.size)
                let originX = (geo.size.width - LouvreVentTuning.sceneWidth * scale) / 2
                let originY = (geo.size.height - LouvreVentTuning.sceneHeight * scale) / 2
                scene
                    .frame(width: LouvreVentTuning.sceneWidth, height: LouvreVentTuning.sceneHeight, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: originX, y: originY)
                    // Top-leading, so a container that is not 390×844 does not
                    // center the unscaled layout on top of the scale origin.
                    // The drag subtracts that origin and nothing else.
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .gesture(drag(scale: scale, originY: originY))
                    .onChange(of: timeline.date) { _, now in advance(to: now) }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.42), trigger: ticks)
        .onAppear {
            model.setReduceMotion(reduceMotion)
            note(model.setTemperature(temperature))
        }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .onChange(of: range) { _, newRange in
            note(model.setRange(newRange))
        }
        .onChange(of: temperature) { _, newValue in
            guard !model.isDragging else { return }
            guard newValue != model.temperature else { return }
            note(model.setTemperature(newValue))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
        .accessibilityHint(model.accessibilityHint)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: note(model.adjust(by: 1))
            case .decrement: note(model.adjust(by: -1))
            @unknown default: break
            }
        }
    }

    private var scene: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawScene(&context)
            }
            .frame(width: LouvreVentTuning.sceneWidth, height: LouvreVentTuning.sceneHeight)
            .accessibilityHidden(true)

            ForEach(model.slots, id: \.index) { slot in
                LouvreBladeFace(
                    slot: slot,
                    intensity: model.specularIntensity(),
                    reduceMotion: reduceMotion
                )
                .accessibilityHidden(true)
            }

            Text(LouvreVentTuning.wordmark)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .tracking(6)
                .foregroundStyle(Color.white.opacity(0.72))
                .position(x: LouvreVentTuning.sceneWidth / 2, y: LouvreVentTuning.wordmarkY)
                .accessibilityHidden(true)

            Text(LouvreVentTuning.caption)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .tracking(3.2)
                .foregroundStyle(Color.white.opacity(0.42))
                .position(x: LouvreVentTuning.sceneWidth / 2, y: LouvreVentTuning.captionY)
                .accessibilityHidden(true)

            Text(model.readout)
                .font(.system(size: 92, weight: .medium, design: .monospaced))
                .foregroundStyle(readoutColor)
                .position(x: LouvreVentTuning.sceneWidth / 2 - 8, y: LouvreVentTuning.readoutY)
                .accessibilityHidden(true)

            Text("°F")
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(readoutColor.opacity(0.8))
                .position(x: LouvreVentTuning.sceneWidth / 2 + 78, y: LouvreVentTuning.readoutY - 28)
                .accessibilityHidden(true)
        }
        .frame(width: LouvreVentTuning.sceneWidth, height: LouvreVentTuning.sceneHeight, alignment: .topLeading)
    }

    private var readoutColor: Color {
        let glow = model.glow
        let wash = 0.35 + 0.65 * glow.intensity
        return Color(
            .sRGB,
            red: glow.red + (1 - glow.red) * wash,
            green: glow.green + (1 - glow.green) * wash,
            blue: glow.blue + (1 - glow.blue) * wash,
            opacity: 1
        )
    }

    private func fitScale(in size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        return min(size.width / LouvreVentTuning.sceneWidth, size.height / LouvreVentTuning.sceneHeight)
    }

    private func drag(scale: CGFloat, originY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard scale > 0 else { return }
                let y = Double((value.location.y - originY) / scale)
                if !tracking {
                    tracking = true
                    note(model.beginDrag(sceneY: y))
                } else {
                    note(model.updateDrag(sceneY: y))
                }
            }
            .onEnded { _ in
                model.endDrag()
                tracking = false
                if temperature != model.temperature { temperature = model.temperature }
            }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        model.step(now.timeIntervalSince(last))
        guard pendingTicks > 0 else { return }
        ticks += 1
        pendingTicks -= 1
    }

    /// One haptic for the first degree now, and one more on each following frame
    /// when a single drag sample crossed several degrees.
    private func note(_ events: [LouvreVentEvent]) {
        let crossed = events.reduce(into: 0) { count, event in
            if case .tick = event { count += 1 }
        }
        if crossed > 0 {
            ticks += 1
            pendingTicks += crossed - 1
        }
        if temperature != model.temperature { temperature = model.temperature }
    }

    // MARK: scene

    private func drawScene(_ ctx: inout GraphicsContext) {
        let width = LouvreVentTuning.sceneWidth
        let height = LouvreVentTuning.sceneHeight
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: height)),
            with: .linearGradient(
                Gradient(colors: [rgb(0.09, 0.10, 0.12), rgb(0.14, 0.09, 0.06)]),
                startPoint: CGPoint(x: width / 2, y: 0),
                endPoint: CGPoint(x: width / 2, y: height)
            )
        )

        let glow = model.glow
        let spill = glow.intensity * 0.22
        let frame = frameRect
        ctx.fill(
            Path(ellipseIn: CGRect(x: frame.midX - 150, y: frame.maxY - 30, width: 300, height: 180)),
            with: .color(paint(glow, white: 0.15).opacity(spill))
        )

        let shell = Path(roundedRect: frame, cornerRadius: LouvreVentTuning.frameRadius)
        ctx.fill(
            shell,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: rgb(0.62, 0.66, 0.70), location: 0),
                    .init(color: rgb(0.78, 0.81, 0.84), location: 0.18),
                    .init(color: rgb(0.42, 0.45, 0.48), location: 0.72),
                    .init(color: rgb(0.24, 0.26, 0.28), location: 1),
                ]),
                startPoint: CGPoint(x: frame.midX, y: frame.minY),
                endPoint: CGPoint(x: frame.midX, y: frame.maxY)
            )
        )
        ctx.stroke(shell, with: .color(.white.opacity(0.28)), lineWidth: 1)

        let opening = openingRect
        let mouth = Path(roundedRect: opening, cornerRadius: LouvreVentTuning.openingRadius)
        ctx.fill(mouth, with: .color(rgb(0.05, 0.03, 0.02)))
        drawGlow(&ctx, in: mouth, glow: glow)
        drawRail(&ctx)
        drawScrews(&ctx, frame: frame)
    }

    /// The chamber gradient, masked to the foreshortened gaps between the blades.
    private func drawGlow(_ ctx: inout GraphicsContext, in mouth: Path, glow: LouvreGlow) {
        let opening = openingRect
        let core = paint(glow, white: max(0, glow.intensity - 0.35) * 1.35)
        let edge = paint(glow, white: glow.intensity * 0.2)
        ctx.drawLayer { layer in
            layer.clip(to: mouth)
            layer.fill(
                mouth,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: edge.opacity(0.82), location: 0),
                        .init(color: core.opacity(0.96), location: 0.5),
                        .init(color: edge.opacity(0.88), location: 1),
                    ]),
                    startPoint: CGPoint(x: opening.midX, y: opening.minY),
                    endPoint: CGPoint(x: opening.midX, y: opening.maxY)
                )
            )
            layer.blendMode = .destinationOut
            for slot in model.slots {
                let height = max(0, slot.projectedHeight)
                let rect = CGRect(
                    x: slot.x,
                    y: slot.centerY - height / 2,
                    width: slot.width,
                    height: height
                )
                layer.fill(Path(rect), with: .color(.black))
            }
        }
    }

    private func drawRail(_ ctx: inout GraphicsContext) {
        let top = LouvreVentTuning.openingY
        let bottom = top + LouvreVentTuning.openingHeight
        let x = LouvreVentTuning.railX
        var shaft = Path()
        shaft.move(to: CGPoint(x: x, y: top))
        shaft.addLine(to: CGPoint(x: x, y: bottom))
        ctx.stroke(shaft, with: .color(.white.opacity(0.28)), lineWidth: 2)
        let span = LouvreVentTuning.defaultUpper - LouvreVentTuning.defaultLower
        if model.range == LouvreVentTuning.defaultRange {
            for temperature in stride(from: LouvreVentTuning.defaultLower, through: LouvreVentTuning.defaultUpper, by: 5) {
                let hot = Double(temperature - LouvreVentTuning.defaultLower) / Double(span)
                let y = bottom - hot * (bottom - top)
                var tick = Path()
                tick.move(to: CGPoint(x: x - 5, y: y))
                tick.addLine(to: CGPoint(x: x + 5, y: y))
                ctx.stroke(tick, with: .color(.white.opacity(0.4)), lineWidth: 1)
            }
        }
        let y = bottom - model.displayedUnit * (bottom - top)
        let mark = CGRect(x: x - 7, y: y - 5, width: 14, height: 10)
        ctx.fill(Path(roundedRect: mark, cornerRadius: 3), with: .color(readoutColor))
    }

    private func drawScrews(_ ctx: inout GraphicsContext, frame: CGRect) {
        let inset = 16.0
        let centers = [
            CGPoint(x: frame.minX + inset, y: frame.minY + inset),
            CGPoint(x: frame.maxX - inset, y: frame.minY + inset),
            CGPoint(x: frame.minX + inset, y: frame.maxY - inset),
            CGPoint(x: frame.maxX - inset, y: frame.maxY - inset),
        ]
        for center in centers {
            let screw = CGRect(x: center.x - 4.5, y: center.y - 4.5, width: 9, height: 9)
            ctx.fill(
                Path(ellipseIn: screw),
                with: .radialGradient(
                    Gradient(colors: [rgb(0.86, 0.88, 0.90), rgb(0.32, 0.34, 0.36)]),
                    center: CGPoint(x: center.x - 1.5, y: center.y - 1.5),
                    startRadius: 0,
                    endRadius: 6
                )
            )
            var slot = Path()
            slot.move(to: CGPoint(x: center.x - 2.4, y: center.y))
            slot.addLine(to: CGPoint(x: center.x + 2.4, y: center.y))
            ctx.stroke(slot, with: .color(rgb(0.15, 0.16, 0.17)), lineWidth: 1)
        }
    }

    private var frameRect: CGRect {
        CGRect(
            x: LouvreVentTuning.frameX,
            y: LouvreVentTuning.frameY,
            width: LouvreVentTuning.frameWidth,
            height: LouvreVentTuning.frameHeight
        )
    }

    private var openingRect: CGRect {
        CGRect(
            x: LouvreVentTuning.openingX,
            y: LouvreVentTuning.openingY,
            width: LouvreVentTuning.openingWidth,
            height: LouvreVentTuning.openingHeight
        )
    }

    private func paint(_ glow: LouvreGlow, white: Double) -> Color {
        let mix = min(1, max(0, white))
        return rgb(
            glow.red + (1 - glow.red) * mix,
            glow.green + (1 - glow.green) * mix,
            glow.blue + (1 - glow.blue) * mix
        )
    }

    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

/// One blade. The Metal glint is used when it can load and motion is allowed.
/// Otherwise a Canvas band draws the same highlight.
private struct LouvreBladeFace: View {
    var slot: LouvreBladeSlot
    var intensity: Double
    var reduceMotion: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
    }

    private var metalEnabled: Bool {
        if reduceMotion { return false }
        if #available(iOS 17.0, macOS 14.0, *) { return true }
        return false
    }

    var body: some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        rgb(0.16, 0.18, 0.20),
                        rgb(0.49, 0.53, 0.55),
                        rgb(0.72, 0.75, 0.78),
                        rgb(0.43, 0.46, 0.49),
                        rgb(0.14, 0.15, 0.17),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 0.6))
            .frame(width: slot.width, height: max(1, slot.faceHeight))
            .overlay {
                if !metalEnabled {
                    Canvas { context, size in
                        let bandHeight = max(3, size.height * 0.26)
                        let y = size.height * slot.specular - bandHeight / 2
                        let band = CGRect(x: 0, y: y, width: size.width, height: bandHeight)
                        context.fill(
                            Path(band),
                            with: .linearGradient(
                                Gradient(colors: [
                                    Color.white.opacity(0),
                                    Color.white.opacity(0.35 + 0.55 * intensity),
                                    Color.white.opacity(0),
                                ]),
                                startPoint: CGPoint(x: size.width / 2, y: y),
                                endPoint: CGPoint(x: size.width / 2, y: y + bandHeight)
                            )
                        )
                    }
                    .blendMode(.screen)
                    .clipShape(shape)
                    .allowsHitTesting(false)
                }
            }
            .modifier(
                LouvreSpecularShader(
                    enabled: metalEnabled,
                    width: slot.width,
                    height: max(1, slot.faceHeight),
                    specular: slot.specular,
                    intensity: intensity
                )
            )
            .rotation3DEffect(
                .degrees(slot.angle),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                perspective: 0.45
            )
            .position(x: slot.centerX, y: slot.centerY)
    }

    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }
}

/// Applies the stitchable glint when the shader can load. Reduce Motion, and any
/// system without the color effect, keep the Canvas band instead.
private struct LouvreSpecularShader: ViewModifier {
    var enabled: Bool
    var width: Double
    var height: Double
    var specular: Double
    var intensity: Double

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
                ShaderLibrary.bundle(.module).louvreSpecular(
                    .float2(Float(width), Float(height)),
                    .float(Float(specular)),
                    .float(Float(intensity))
                )
            )
        } else {
            content
        }
    }
}

/// The gallery page.
public struct LouvreVentThermostatDemo: View {
    @State private var temperature = 68

    public init() {}

    public var body: some View {
        LouvreVentThermostat(temperature: $temperature)
    }
}

#Preview("Louvre vent") {
    LouvreVentThermostatDemo()
}
#endif
