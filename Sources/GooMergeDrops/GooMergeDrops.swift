//
//  GooMergeDrops.swift
//  GooMergeDrops
//
//  Five file drops on a ring around a dashed well. They are one metaball field:
//  drag one near another and the pair stretches, then snaps together. Combine
//  springs them into the well. A Canvas blur and alpha threshold (or the Metal
//  SDF, when it is available) draws the goo, with a darker rim and a warm glow.
//  The merged blob morphs into Binder-01.pdf, folded corner and all.
//  Reduce Motion snaps to the well and crossfades. No stretch, no spring.
//  The ring, the spring, the field and the snap live in GooMergeCore.

#if canImport(SwiftUI)
import SwiftUI
@_exported import GooMergeCore

/// File drops that melt into one document.
///
/// ```swift
/// GooMergeDrops { name in
///     print(name) // "Binder-01.pdf"
/// }
/// ```
public struct GooMergeDrops: View {
    private let onMerged: ((String) -> Void)?
    @State private var model: GooMergeModel
    @State private var lastDate: Date?
    @State private var tracking = false
    @State private var hapticTick = 0
    @State private var didMerge = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(drops: [GooDrop] = GooDrop.samples, onMerged: ((String) -> Void)? = nil) {
        self.onMerged = onMerged
        _model = State(initialValue: GooMergeModel(drops: drops))
    }

    public var body: some View {
        TimelineView(.animation(paused: !model.animates)) { timeline in
            GeometryReader { geo in
                let scale = fitScale(in: geo.size)
                let originX = (geo.size.width - GooMergeTuning.pageWidth * scale) / 2
                let originY = (geo.size.height - GooMergeTuning.pageHeight * scale) / 2
                ZStack(alignment: .topLeading) {
                    scene
                        .frame(width: GooMergeTuning.pageWidth, height: GooMergeTuning.pageHeight)
                        .scaleEffect(scale, anchor: .topLeading)
                        .offset(x: originX, y: originY)
                        .gesture(drag(scale: scale, originX: originX, originY: originY))
                    combineButton(scale: scale, originX: originX, originY: originY)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .onChange(of: timeline.date) { _, now in advance(to: now) }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: hapticTick)
        .onAppear { model.setReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
        .accessibilityHint(GooMergeTuning.accessibilityHint)
        .accessibilityAction(named: Text(GooMergeTuning.combineAction)) {
            note(model.combine())
        }
    }

    private var scene: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawDesk(&context)
                drawWell(&context)
                drawTitle(&context)
            }
            .accessibilityHidden(true)
            field
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            Canvas { context, _ in
                drawLabels(&context)
                drawCard(&context)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var field: some View {
        if model.reduceMotion {
            Canvas { context, _ in drawCrispDrops(&context) }
        } else if usesMetalSDF {
            metalField
        } else {
            Canvas { context, _ in drawGoo(&context) }
        }
    }

    private var usesMetalSDF: Bool {
        guard !model.reduceMotion, model.blobOpacity > 0.01 else { return false }
        if #available(iOS 18.0, macOS 15.0, *) { return true }
        return false
    }

    @available(iOS 18.0, macOS 15.0, *)
    private var metalField: some View {
        Color.clear
            .frame(width: GooMergeTuning.pageWidth, height: GooMergeTuning.pageHeight)
            .layerEffect(
                ShaderLibrary.bundle(.module).gooMergeSDF(
                    .float4(pack(0)),
                    .float4(pack(1)),
                    .float4(pack(2)),
                    .float4(pack(3)),
                    .float4(pack(4)),
                    .float(Float(GooMergeTuning.smoothK)),
                    .float(Float(model.mergeProgress)),
                    .float(Float(model.morphProgress))
                ),
                maxSampleOffset: CGSize(width: 1, height: 1)
            )
            .opacity(model.blobOpacity)
    }

    private func pack(_ index: Int) -> SIMD4<Float> {
        guard model.bodies.indices.contains(index) else { return SIMD4(0, 0, 0, 0) }
        let body = model.bodies[index]
        return SIMD4(Float(body.renderCenter.x), Float(body.renderCenter.y), Float(body.radius), 1)
    }

    private func combineButton(scale: CGFloat, originX: CGFloat, originY: CGFloat) -> some View {
        let width = GooMergeTuning.buttonWidth * scale
        let height = GooMergeTuning.buttonHeight * scale
        return Button(action: pressButton) {
            Text(buttonTitle)
                .font(.headline)
                .frame(width: width, height: height)
        }
        .buttonStyle(.borderedProminent)
        .tint(Self.honey)
        .foregroundStyle(Self.ink)
        .disabled(model.phase == .combining || model.phase == .morphing)
        .offset(
            x: originX + (GooMergeTuning.buttonCenter.x - GooMergeTuning.buttonWidth / 2) * scale,
            y: originY + (GooMergeTuning.buttonCenter.y - GooMergeTuning.buttonHeight / 2) * scale
        )
        .accessibilityHidden(true)
    }

    private var buttonTitle: String {
        switch model.phase {
        case .ready: "Combine"
        case .combining, .morphing: "Merging"
        case .merged: "Reset"
        }
    }

    private func pressButton() {
        if model.phase == .merged {
            didMerge = false
            model.reset()
        } else {
            note(model.combine())
        }
    }

    private func fitScale(in size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        return min(size.width / GooMergeTuning.pageWidth, size.height / GooMergeTuning.pageHeight)
    }

    private func drag(scale: CGFloat, originX: CGFloat, originY: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard scale > 0 else { return }
                let point = Vec2(
                    Double((value.location.x - originX) / scale),
                    Double((value.location.y - originY) / scale)
                )
                if !tracking {
                    tracking = model.beginDrag(at: point)
                } else {
                    note(model.updateDrag(to: point))
                }
            }
            .onEnded { _ in
                if tracking { note(model.endDrag()) }
                tracking = false
            }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        note(model.step(now.timeIntervalSince(last)))
    }

    private func note(_ events: [GooMergeEvent]) {
        for event in events {
            switch event {
            case .haptic, .snapped:
                hapticTick += 1
            case .merged(let name):
                guard !didMerge else { continue }
                didMerge = true
                onMerged?(name)
            case .combining, .morphing:
                break
            }
        }
    }

    // MARK: drawing

    private func drawDesk(_ context: inout GraphicsContext) {
        let rect = CGRect(x: 0, y: 0, width: GooMergeTuning.pageWidth, height: GooMergeTuning.pageHeight)
        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(colors: [
                    Color(red: 0.24, green: 0.15, blue: 0.11),
                    Color(red: 0.09, green: 0.06, blue: 0.05),
                ]),
                center: CGPoint(x: model.well.x, y: model.well.y - 20),
                startRadius: 20,
                endRadius: 520
            )
        )
    }

    private func drawWell(_ context: inout GraphicsContext) {
        let alpha = 1 - model.mergeProgress
        guard alpha > 0.02 else { return }
        let radius = GooMergeTuning.wellDashRadius
        let rect = CGRect(
            x: model.well.x - radius, y: model.well.y - radius,
            width: radius * 2, height: radius * 2
        )
        context.opacity = alpha
        context.stroke(
            Path(ellipseIn: rect),
            with: .color(Color(red: 1, green: 0.84, blue: 0.67).opacity(0.7)),
            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 6])
        )
    }

    private func drawTitle(_ context: inout GraphicsContext) {
        let title = Text("Files").font(.system(size: 34, weight: .bold)).foregroundStyle(.white)
        context.draw(title, at: CGPoint(x: 28, y: 64), anchor: .leading)
        let caption = Text(model.accessibilityValue)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(Color.white.opacity(0.72))
        context.draw(caption, at: CGPoint(x: 28, y: 96), anchor: .leading)
    }

    private func drawCrispDrops(_ context: inout GraphicsContext) {
        context.opacity = model.blobOpacity
        for body in model.bodies {
            let rect = circleRect(body.renderCenter, body.radius)
            context.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(Self.rim))
            context.fill(Path(ellipseIn: rect.insetBy(dx: 3, dy: 3)), with: .color(Self.fill(body.index)))
        }
    }

    private func drawGoo(_ context: inout GraphicsContext) {
        guard model.blobOpacity > 0.01 else { return }
        var glow = context
        glow.opacity = model.blobOpacity * (0.35 + 0.65 * model.mergeProgress)
        glow.addFilter(.blur(radius: 26))
        glow.drawLayer { layer in
            for body in model.bodies {
                let rect = circleRect(body.renderCenter, body.radius + 6)
                layer.fill(Path(ellipseIn: rect), with: .color(Self.glow))
            }
        }

        var rim = context
        rim.opacity = model.blobOpacity
        rim.addFilter(.alphaThreshold(min: GooMergeTuning.gooThreshold, color: Self.rim))
        rim.addFilter(.blur(radius: GooMergeTuning.gooBlur + 3))
        rim.drawLayer { layer in
            for body in model.bodies {
                layer.fill(Path(ellipseIn: circleRect(body.renderCenter, body.radius + 2)), with: .color(.white))
            }
        }

        var goo = context
        goo.opacity = model.blobOpacity
        goo.addFilter(.alphaThreshold(min: GooMergeTuning.gooThreshold, color: Self.honey))
        goo.addFilter(.blur(radius: GooMergeTuning.gooBlur))
        goo.drawLayer { layer in
            for body in model.bodies {
                layer.fill(Path(ellipseIn: circleRect(body.renderCenter, body.radius * 0.92)), with: .color(.white))
            }
        }
    }

    private func drawLabels(_ context: inout GraphicsContext) {
        let alpha = model.blobOpacity * (1 - model.mergeProgress * 0.85)
        guard alpha > 0.05 else { return }
        context.opacity = alpha
        for body in model.bodies {
            let label = Text(body.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
            context.draw(
                label,
                at: CGPoint(x: body.renderCenter.x, y: body.renderCenter.y + body.radius + 14),
                anchor: .top
            )
        }
    }

    private func drawCard(_ context: inout GraphicsContext) {
        guard model.cardOpacity > 0.001 else { return }
        let scale = 0.86 + 0.14 * model.morphProgress
        var card = context
        card.opacity = model.cardOpacity
        card.translateBy(x: model.well.x, y: model.well.y)
        card.scaleBy(x: scale, y: scale)
        card.translateBy(x: -model.well.x, y: -model.well.y)

        let w = GooMergeTuning.cardWidth
        let h = GooMergeTuning.cardHeight
        let fold = GooMergeTuning.foldSize * model.fold
        let origin = CGPoint(x: model.well.x - w / 2, y: model.well.y - h / 2)
        let page = pagePath(origin: origin, size: CGSize(width: w, height: h), fold: fold)
        let shadow = page.applying(CGAffineTransform(translationX: 0, y: 10))
        card.fill(shadow, with: .color(Color.black.opacity(0.28)))
        card.fill(page, with: .color(Self.paper))
        card.stroke(page, with: .color(Color.black.opacity(0.08)), lineWidth: 1)

        if fold > 1 {
            var flap = Path()
            let maxX = origin.x + w
            flap.move(to: CGPoint(x: maxX - fold, y: origin.y))
            flap.addLine(to: CGPoint(x: maxX, y: origin.y + fold))
            flap.addLine(to: CGPoint(x: maxX - fold, y: origin.y + fold))
            flap.closeSubpath()
            card.fill(flap, with: .color(Self.crease))
            card.stroke(
                Path { path in
                    path.move(to: CGPoint(x: maxX - fold, y: origin.y))
                    path.addLine(to: CGPoint(x: maxX, y: origin.y + fold))
                },
                with: .color(Color.black.opacity(0.12)),
                lineWidth: 1
            )
        }

        let name = Text(model.documentName).font(.system(size: 16, weight: .bold)).foregroundColor(Self.ink)
        card.draw(name, at: CGPoint(x: origin.x + 18, y: origin.y + 36), anchor: .leading)
        let kind = Text("PDF").font(.system(size: 11, weight: .semibold)).foregroundColor(Self.ink.opacity(0.45))
        card.draw(kind, at: CGPoint(x: origin.x + 18, y: origin.y + 58), anchor: .leading)
        for row in 0..<4 {
            let y = origin.y + 92 + CGFloat(row) * 22
            let width = row == 3 ? w * 0.42 : w * 0.72
            let bar = CGRect(x: origin.x + 18, y: y, width: width, height: 8)
            card.fill(Path(roundedRect: bar, cornerRadius: 4), with: .color(Self.rule))
        }
    }

    private func pagePath(origin: CGPoint, size: CGSize, fold: Double) -> Path {
        let x = origin.x
        let y = origin.y
        let w = size.width
        let h = size.height
        let r = GooMergeTuning.cardRadius
        if fold <= 1 {
            return Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: GooMergeTuning.cardRadius, style: .continuous)
        }
        var path = Path()
        let cut = fold
        path.move(to: CGPoint(x: x + r, y: y))
        path.addLine(to: CGPoint(x: x + w - cut, y: y))
        path.addLine(to: CGPoint(x: x + w, y: y + cut))
        path.addLine(to: CGPoint(x: x + w, y: y + h - r))
        path.addQuadCurve(to: CGPoint(x: x + w - r, y: y + h), control: CGPoint(x: x + w, y: y + h))
        path.addLine(to: CGPoint(x: x + r, y: y + h))
        path.addQuadCurve(to: CGPoint(x: x, y: y + h - r), control: CGPoint(x: x, y: y + h))
        path.addLine(to: CGPoint(x: x, y: y + r))
        path.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
        path.closeSubpath()
        return path
    }

    private func circleRect(_ center: Vec2, _ radius: Double) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private static func fill(_ index: Int) -> Color {
        let palette = [amber, coral, gold, rose, peach]
        return palette[index % palette.count]
    }

    private static let amber = Color(red: 0.95, green: 0.70, blue: 0.29)
    private static let coral = Color(red: 0.89, green: 0.42, blue: 0.27)
    private static let gold = Color(red: 0.94, green: 0.76, blue: 0.31)
    private static let rose = Color(red: 0.83, green: 0.33, blue: 0.49)
    private static let peach = Color(red: 0.94, green: 0.54, blue: 0.36)
    private static let honey = Color(red: 0.96, green: 0.62, blue: 0.28)
    private static let rim = Color(red: 0.42, green: 0.16, blue: 0.06)
    private static let glow = Color(red: 1.0, green: 0.72, blue: 0.35)
    private static let paper = Color(red: 0.984, green: 0.965, blue: 0.933)
    private static let crease = Color(red: 0.91, green: 0.84, blue: 0.74)
    private static let ink = Color(red: 0.16, green: 0.12, blue: 0.10)
    private static let rule = Color(red: 0.86, green: 0.80, blue: 0.72)
}

/// The gallery page.
public struct GooMergeDropsDemo: View {
    @State private var merged = ""

    public init() {}

    public var body: some View {
        GooMergeDrops { name in
            merged = name
        }
        .overlay(alignment: .bottom) {
            if !merged.isEmpty {
                Text(merged)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 28)
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview("Goo merge") {
    GooMergeDropsDemo()
}
#endif
