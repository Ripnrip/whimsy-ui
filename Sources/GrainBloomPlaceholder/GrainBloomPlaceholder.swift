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

/// The gallery's sample picture: a soft sunset, drawn the same way as the web port.
enum GrainBloomSunset {
    static let size = CGSize(width: 390, height: 844)

    static func image() -> Image {
        guard let cg = makeImage() else { return Image(systemName: "sun.horizon.fill") }
        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cg))
        #elseif canImport(AppKit)
        return Image(nsImage: NSImage(cgImage: cg, size: size))
        #else
        return Image(systemName: "sun.horizon.fill")
        #endif
    }

    private static func makeImage() -> CGImage? {
        let width = Int(size.width)
        let height = Int(size.height)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context, size: size)
        return context.makeImage()
    }

    private static func draw(_ context: CGContext, size: CGSize) {
        let width = size.width
        let height = size.height
        let colors = [
            CGColor(red: 0.173, green: 0.141, blue: 0.408, alpha: 1),
            CGColor(red: 0.604, green: 0.302, blue: 0.525, alpha: 1),
            CGColor(red: 0.961, green: 0.549, blue: 0.380, alpha: 1),
            CGColor(red: 0.953, green: 0.788, blue: 0.541, alpha: 1),
        ] as CFArray
        let stops: [CGFloat] = [0, 0.38, 0.58, 1]
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: stops) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: height),
                options: []
            )
        }
        let sun = CGPoint(x: width * 0.68, y: height * 0.60)
        let radius = min(width, height) * 0.11
        if let glow = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CGColor(red: 1, green: 0.894, blue: 0.667, alpha: 0.95),
                CGColor(red: 0.961, green: 0.549, blue: 0.380, alpha: 0.55),
                CGColor(red: 0.961, green: 0.549, blue: 0.380, alpha: 0),
            ] as CFArray,
            locations: [0, 0.28, 1]
        ) {
            context.drawRadialGradient(
                glow,
                startCenter: sun,
                startRadius: radius * 0.2,
                endCenter: sun,
                endRadius: radius * 3.1,
                options: []
            )
        }
        context.setFillColor(CGColor(red: 1, green: 0.906, blue: 0.659, alpha: 1))
        context.fillEllipse(in: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2))
        cloud(context, cx: width * 0.22, cy: height * 0.20, rw: width * 0.16, rh: height * 0.038)
        cloud(context, cx: width * 0.50, cy: height * 0.12, rw: width * 0.10, rh: height * 0.026)
        cloud(context, cx: width * 0.78, cy: height * 0.28, rw: width * 0.12, rh: height * 0.030)
        hill(context, width: width, height: height, baseline: height * 0.64, amplitude: height * 0.028, phase: 0.6, color: CGColor(red: 0.416, green: 0.345, blue: 0.651, alpha: 1))
        hill(context, width: width, height: height, baseline: height * 0.76, amplitude: height * 0.040, phase: 1.8, color: CGColor(red: 0.184, green: 0.486, blue: 0.518, alpha: 1))
        hill(context, width: width, height: height, baseline: height * 0.88, amplitude: height * 0.022, phase: 0.3, color: CGColor(red: 0.227, green: 0.165, blue: 0.200, alpha: 1))
    }

    private static func cloud(_ context: CGContext, cx: CGFloat, cy: CGFloat, rw: CGFloat, rh: CGFloat) {
        context.setFillColor(CGColor(red: 1, green: 0.925, blue: 0.863, alpha: 0.78))
        context.fillEllipse(in: CGRect(x: cx - rw, y: cy - rh, width: rw * 2, height: rh * 2))
        context.fillEllipse(in: CGRect(x: cx - rw * 1.17, y: cy - rh * 0.55, width: rw * 1.24, height: rh * 1.5))
        context.fillEllipse(in: CGRect(x: cx - rw * 0.02, y: cy - rh * 0.56, width: rw, height: rh * 1.36))
    }

    private static func hill(
        _ context: CGContext,
        width: CGFloat,
        height: CGFloat,
        baseline: CGFloat,
        amplitude: CGFloat,
        phase: CGFloat,
        color: CGColor
    ) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: baseline))
        var x: CGFloat = 0
        while x <= width {
            let u = x / width
            let y = baseline
                + sin(u * .pi * 2 + phase) * amplitude
                + sin(u * .pi * 5 + phase * 1.7) * amplitude * 0.22
            path.addLine(to: CGPoint(x: x, y: y))
            x += 3
        }
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(color)
        context.fillPath()
    }
}

public struct GrainBloomPlaceholderDemo: View {
    @State private var generating = false
    @State private var picture: Image?

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            GrainBloomPlaceholder(image: picture, isGenerating: generating)
                .frame(width: 260)
            HStack {
                Button(generating ? "Stop" : "Generate") { generating.toggle() }
                Button(picture == nil ? "Image arrives" : "Clear image") {
                    picture = picture == nil ? GrainBloomSunset.image() : nil
                }
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
