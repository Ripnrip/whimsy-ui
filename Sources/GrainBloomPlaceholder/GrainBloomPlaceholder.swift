#if canImport(SwiftUI)
import SwiftUI

/// A card that stands in for an image that is still being generated.
/// Grain and dither dots wake, then the picture resolves through a Bayer mask.
///
/// ```swift
/// GrainBloomPlaceholder(image: photo, isGenerating: jobRunning)
/// ```
///
/// With Reduce Motion the ripple and the drift are dropped and the picture
/// crossfades in over a static gradient. The timeline lives in `GrainBloomCore`.
public struct GrainBloomPlaceholder: View {
    private let image: Image?
    private let palette: [Color]
    private let isGenerating: Bool

    @State private var model: GrainBloomModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        image: Image? = nil,
        palette: [Color] = GrainBloomPlaceholder.defaultPalette,
        isGenerating: Bool = false
    ) {
        self.image = image
        self.palette = palette.isEmpty ? GrainBloomPlaceholder.defaultPalette : palette
        self.isGenerating = isGenerating
        _model = State(initialValue: GrainBloomModel(
            generating: isGenerating,
            hasImage: image != nil,
            palette: GrainBloomPlaceholder.rgbSamples(palette)
        ))
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !needsClock)) { timeline in
            canvas
                .onChange(of: timeline.date) { _, date in
                    advance(to: date)
                }
        }
        .aspectRatio(GrainBloomTuning.stageWidth / GrainBloomTuning.stageHeight, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Image placeholder")
        .accessibilityValue(model.accessibilityValue)
        .accessibilityAction(named: Text("Replay bloom")) {
            if model.phase == .done { model.replay() }
        }
        .onTapGesture {
            if model.phase == .done { model.replay() }
        }
        .onAppear {
            model.setReduceMotion(reduceMotion)
            model.setGenerating(isGenerating)
            syncImage(image != nil)
        }
        .onChange(of: isGenerating) { _, on in
            model.setGenerating(on)
        }
        .onChange(of: image != nil) { _, present in
            syncImage(present)
        }
        .onChange(of: reduceMotion) { _, on in
            model.setReduceMotion(on)
        }
    }

    private var needsClock: Bool {
        if reduceMotion { return model.phase != .done && model.phase != .idle }
        return model.phase == .waking || model.phase == .resolving || model.playsSettle
    }

    private var canvas: some View {
        Canvas { context, size in
            let scaleX = size.width / GrainBloomTuning.stageWidth
            let scaleY = size.height / GrainBloomTuning.stageHeight
            drawBlobs(in: &context, scaleX: scaleX, scaleY: scaleY, size: size)
            if let image, model.hasImage {
                let opacity = model.reduceMotion ? model.crossfade : model.resolveProgress
                context.opacity = opacity
                context.draw(image, in: CGRect(origin: .zero, size: size))
                context.opacity = 1
            }
            drawDots(in: &context, scaleX: scaleX, scaleY: scaleY, size: size)
            if model.phase == .waking, !model.reduceMotion {
                let label = Text("Dreaming…").font(.caption).foregroundStyle(.white.opacity(0.8))
                context.draw(context.resolve(label), at: CGPoint(x: size.width / 2, y: size.height * 0.86))
                let band = CGRect(
                    x: size.width * model.shimmer - 30,
                    y: 0,
                    width: 40,
                    height: size.height
                )
                context.fill(Path(band), with: .color(.white.opacity(0.12)))
            }
            if model.glint > 0 {
                let glint = context.resolve(Text("✦").font(.caption2).foregroundStyle(.white))
                context.opacity = model.glint
                context.draw(glint, at: CGPoint(x: size.width * 0.82, y: size.height * 0.12))
            }
        }
        .background(palette.first ?? GrainBloomPlaceholder.defaultPalette[0])
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityHidden(true)
    }

    private func drawBlobs(in context: inout GraphicsContext, scaleX: Double, scaleY: Double, size: CGSize) {
        for index in 0..<min(4, model.palette.count) {
            let blob = model.blob(index)
            let color = index < palette.count ? palette[index] : GrainBloomPlaceholder.defaultPalette[index]
            let rect = CGRect(
                x: blob.x * scaleX - size.width * 0.28,
                y: blob.y * scaleY - size.height * 0.22,
                width: size.width * 0.56,
                height: size.height * 0.44
            )
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.85)))
        }
    }

    private func drawDots(in context: inout GraphicsContext, scaleX: Double, scaleY: Double, size: CGSize) {
        let cell = max(2.0, model.cellSize * min(scaleX, scaleY))
        var y = cell / 2
        while y < size.height {
            var x = cell / 2
            while x < size.width {
                let sx = x / scaleX
                let sy = y / scaleY
                let delay = GrainBloomMath.rippleDelay(x: sx, y: sy)
                let scale = GrainBloomMath.dotScale(
                    wakeTime: model.phase == .waking ? model.phaseTime : 0,
                    delay: delay,
                    reduceMotion: model.reduceMotion
                )
                let revealed = model.reduceMotion
                    ? model.crossfade > 0.5
                    : GrainBloomMath.isRevealed(x: sx, y: sy, progress: model.resolveProgress)
                let radius = cell * 0.22 * scale
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                let alpha = revealed ? 0.15 : 0.55
                context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(alpha)))
                x += cell
            }
            y += cell
        }
        #if os(iOS) || os(macOS)
        if #available(iOS 17.0, macOS 14.0, *) {
            // The Metal grain pass is optional. Canvas dots above are the fallback.
            _ = ShaderLibrary.bundle(.module)
        }
        #endif
    }

    private func advance(to date: Date) {
        let now = date.timeIntervalSinceReferenceDate
        if lastTick == 0 {
            lastTick = now
            return
        }
        let dt = min(0.05, max(0, now - lastTick))
        lastTick = now
        model.step(dt)
    }

    private func syncImage(_ present: Bool) {
        model.setImagePresent(present)
    }

    @State private var lastTick: TimeInterval = 0

    public static let defaultPalette: [Color] = GrainBloomTuning.defaultPalette.map {
        Color(red: $0.r, green: $0.g, blue: $0.b)
    }

    static func rgbSamples(_ colors: [Color]) -> [GrainBloomRGB] {
        if colors.isEmpty { return [] }
        return colors.prefix(4).map { color in
            #if canImport(UIKit)
            let resolved = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
            return GrainBloomRGB(r: Double(r), g: Double(g), b: Double(b))
            #elseif canImport(AppKit)
            let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
            return GrainBloomRGB(
                r: Double(resolved.redComponent),
                g: Double(resolved.greenComponent),
                b: Double(resolved.blueComponent)
            )
            #else
            return GrainBloomTuning.defaultPalette[0]
            #endif
        }
    }
}

public struct GrainBloomPlaceholderDemo: View {
    @State private var generating = false
    @State private var showImage = false

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            GrainBloomPlaceholder(
                image: showImage ? Image(systemName: "photo.fill") : nil,
                isGenerating: generating
            )
            .frame(width: 260)
            HStack {
                Button(generating ? "Stop" : "Generate") { generating.toggle() }
                Button(showImage ? "Clear image" : "Image arrives") { showImage.toggle() }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

#Preview("Grain Bloom") {
    GrainBloomPlaceholderDemo()
}
#endif
