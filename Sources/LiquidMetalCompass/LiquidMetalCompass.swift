//  LiquidMetalCompass.swift
//  LiquidMetalCompass
//
//  A blob of liquid chrome that leans and stretches toward a friend. The friend's bearing is
//  fixed in the world; as you turn, the blob swings round to keep pointing at them on an
//  underdamped spring, overshooting and wobbling, and flings itself longer while it swings.
//  A soft haptic ticks when you face them dead on (with hysteresis), and the distance below
//  rolls with a numeric content transition. The chrome is a Metal [[stitchable]] layerEffect.
//  Springs, blob geometry, alignment and distance formatting live in LiquidCompassCore.

#if canImport(SwiftUI)
import SwiftUI
import LiquidCompassCore

/// A liquid-metal compass that points at a friend.
///
/// ```swift
/// LiquidMetalCompass(friendName: "Maya", friendBearing: 62, distance: 1_240)
/// LiquidMetalCompass(friendName: "Maya", friend: mayaCoordinate, from: myCoordinate)
/// ```
///
/// On an iPhone it reads the compass via ``HeadingSources/automatic()`` (Core Motion, falling
/// back to Core Location). In Xcode previews, the simulator, on a Mac, or whenever you pass
/// `fakeHeadingWithDrag: true`, dragging horizontally fakes the heading instead.
/// The view draws its own dark backdrop and wants roughly 300 × 440 points.
public struct LiquidMetalCompass: View {
    private let friendName: String
    private let friendBearing: Double
    private let distance: Double?
    private let units: DistanceUnits
    private let explicitSource: (any HeadingSource)?
    private let useAutomaticSource: Bool
    private let fakeHeadingOverride: Bool?

    @State private var engine: CompassEngine
    @State private var isAnimating = false
    @State private var heading: Double = 0
    @State private var tickCount = 0
    @State private var isAligned = false
    @State private var source: (any HeadingSource)?
    @State private var drag = FakeHeadingDrag(sensitivity: 0.5)
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let blobCanvas: CGFloat = 300
    private static let dialRadius: CGFloat = 136

    /// - Parameters:
    ///   - friendName: shown under the blob and used by VoiceOver.
    ///   - friendBearing: compass bearing to the friend (degrees from north, clockwise).
    ///   - distance: metres to the friend, or nil to hide the distance.
    ///   - units: metric or imperial rounding.
    ///   - headingSource: a custom sensor; nil (default) picks ``HeadingSources/automatic()``.
    ///   - fakeHeadingWithDrag: force drag-to-turn on or off; nil = on when there's no sensor
    ///     (previews, simulator, Mac).
    public init(friendName: String = "Friend", friendBearing: Double, distance: Double? = nil,
                units: DistanceUnits = .metric, headingSource: (any HeadingSource)? = nil,
                fakeHeadingWithDrag: Bool? = nil) {
        self.friendName = friendName
        self.friendBearing = CompassMath.wrap360(friendBearing)
        self.distance = distance
        self.units = units
        self.explicitSource = headingSource
        self.useAutomaticSource = headingSource == nil
        self.fakeHeadingOverride = fakeHeadingWithDrag
        _engine = State(initialValue: CompassEngine(friendBearing: friendBearing))
    }

    /// Points from `origin` to `friend`, with the great-circle bearing and distance.
    public init(friendName: String = "Friend", friend: GeoCoordinate, from origin: GeoCoordinate,
                units: DistanceUnits = .metric, headingSource: (any HeadingSource)? = nil,
                fakeHeadingWithDrag: Bool? = nil) {
        self.init(friendName: friendName,
                  friendBearing: CompassMath.bearing(from: origin, to: friend),
                  distance: CompassMath.distance(from: origin, to: friend),
                  units: units, headingSource: headingSource, fakeHeadingWithDrag: fakeHeadingWithDrag)
    }

    public var body: some View {
        VStack(spacing: 26) {
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                let frame = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
                ZStack {
                    DialView(heading: frame.heading, friendBearing: friendBearing,
                             radius: Self.dialRadius, glow: frame.glow)
                    BlobLayer(outline: frame.outline, glow: frame.glow,
                              spin: reduceMotion ? 0 : -frame.heading * .pi / 180,
                              size: Self.blobCanvas)
                }
                .frame(width: Self.blobCanvas, height: Self.blobCanvas)
                .onChange(of: frame.tickCount) { _, n in tickCount = n }
                .onChange(of: frame.isAligned) { _, a in isAligned = a }
                .onChange(of: frame.isSettled) { _, settled in
                    if settled && !isDragging { isAnimating = false }
                }
            }
            .contentShape(Rectangle())
            .gesture(dragToTurn, including: fakeHeadingEnabled ? .all : .subviews)
            caption
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.backdrop)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: tickCount)
        .onAppear(perform: startSource)
        .onDisappear { source?.stop() }
        .onChange(of: friendBearing) { _, b in engine.setFriendBearing(b); isAnimating = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Compass to \(friendName)")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAdjustableAction { direction in
            guard fakeHeadingEnabled else { return }
            switch direction {
            case .increment: setHeading(heading + 15)
            case .decrement: setHeading(heading - 15)
            @unknown default: break
            }
        }
    }

    // MARK: Caption

    private var formatted: FormattedDistance? {
        distance.map { DistanceFormatting.format(metres: $0, units: units) }
    }

    private var caption: some View {
        VStack(spacing: 6) {
            Text(friendName)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.75))
            if let formatted {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formatted.number)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: formatted.value))
                    Text(formatted.unit)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .foregroundStyle(.white)
                .animation(reduceMotion ? nil : .snappy, value: formatted.number)
            }
            Text(isAligned ? "Dead ahead" : directionWords)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isAligned ? Color(red: 1, green: 0.84, blue: 0.5) : .white.opacity(0.5))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isAligned)
        }
    }

    private var relative: Double { CompassMath.relativeBearing(heading: heading, friendBearing: friendBearing) }
    private var directionWords: String {
        let words = CompassMath.spokenDirection(relative: relative)
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    private var accessibilityHintText: String {
        fakeHeadingEnabled ? "Swipe up or down to turn." : ""
    }

    private var accessibilityValue: String {
        let direction = CompassMath.spokenDirection(relative: relative)
        guard let formatted else { return direction }
        return "\(direction), \(formatted.spoken)"
    }

    // MARK: Heading

    private var fakeHeadingEnabled: Bool {
        if let fakeHeadingOverride { return fakeHeadingOverride }
        return source == nil || Self.isRunningForPreviews
    }

    private static var isRunningForPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private func startSource() {
        if source == nil {
            source = useAutomaticSource ? HeadingSources.automatic() : explicitSource
        }
        guard !(fakeHeadingOverride ?? false), !Self.isRunningForPreviews, let source else { return }
        source.start { degrees in setHeading(degrees) }
    }

    private func setHeading(_ degrees: Double) {
        heading = CompassMath.wrap360(degrees)
        engine.setHeading(heading)
        isAnimating = true
    }

    private var dragToTurn: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if !isDragging { isDragging = true; drag.begin(at: heading) }
                setHeading(drag.heading(forTranslation: value.translation.width))
            }
            .onEnded { _ in isDragging = false; isAnimating = true }
    }

    private static var backdrop: some View {
        ZStack {
            Color(red: 0.045, green: 0.05, blue: 0.065)
            RadialGradient(colors: [Color(red: 0.16, green: 0.18, blue: 0.24), .clear],
                           center: UnitPoint(x: 0.5, y: 0.4), startRadius: 10, endRadius: 380)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Blob

/// The blob drawn as a height field (dome gradient, blurred), then shaded as chrome.
struct BlobLayer: View {
    let outline: [Vec2]
    let glow: Double
    let spin: Double
    let size: CGFloat

    /// Blur that turns the filled outline into a smooth height field (points).
    static let blur: CGFloat = 10

    var body: some View {
        ZStack {
            // Aligned: a warm halo behind the metal.
            Circle()
                .fill(Color(red: 1, green: 0.78, blue: 0.4).opacity(0.35 * glow))
                .frame(width: 190, height: 190)
                .blur(radius: 30)
            Canvas { context, canvasSize in
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                let path = Self.smoothPath(outline, offset: c)
                let centroid = BlobGeometry.centroid(of: outline)
                let center = CGPoint(x: c.x + centroid.x, y: c.y + centroid.y)
                context.fill(path, with: .radialGradient(
                    Gradient(stops: [.init(color: .white, location: 0),
                                     .init(color: Color(white: 0.92), location: 0.35),
                                     .init(color: Color(white: 0.7), location: 0.65),
                                     .init(color: Color(white: 0.35), location: 1)]),
                    center: center, startRadius: 0, endRadius: 130))
            }
            .frame(width: size, height: size)
            .blur(radius: Self.blur)
            .layerEffect(ShaderLibrary.bundle(.module).liquidChrome(.float(Float(spin)), .float(Float(glow))),
                         maxSampleOffset: CGSize(width: 8, height: 8))
            .shadow(color: .black.opacity(0.55), radius: 16, y: 14)
        }
        .allowsHitTesting(false)
    }

    /// Closed quadratic spline through the polygon's edge midpoints (vertices as controls).
    static func smoothPath(_ pts: [Vec2], offset: CGPoint) -> Path {
        var path = Path()
        guard pts.count > 2 else { return path }
        func p(_ v: Vec2) -> CGPoint { CGPoint(x: offset.x + v.x, y: offset.y + v.y) }
        func mid(_ i: Int) -> CGPoint {
            let a = pts[i % pts.count], b = pts[(i + 1) % pts.count]
            return p(Vec2.lerp(a, b, 0.5))
        }
        path.move(to: mid(0))
        for i in 1...pts.count { path.addQuadCurve(to: mid(i), control: p(pts[i % pts.count])) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Dial

/// Tick ring that turns with the heading (north stays north), with a dot at the friend.
struct DialView: View {
    let heading: Double
    let friendBearing: Double
    let radius: CGFloat
    let glow: Double

    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func point(_ bearing: Double, _ r: CGFloat) -> CGPoint {
                let v = CompassMath.screenVector(degrees: bearing - heading)
                return CGPoint(x: c.x + v.x * r, y: c.y + v.y * r)
            }
            for k in 0..<72 {
                let b = Double(k) * 5
                let major = k % 18 == 0, mid = k % 6 == 0
                let len: CGFloat = major ? 12 : mid ? 8 : 4
                var tick = Path()
                tick.move(to: point(b, radius))
                tick.addLine(to: point(b, radius - len))
                context.stroke(tick, with: .color(.white.opacity(major ? 0.55 : mid ? 0.32 : 0.16)),
                               lineWidth: major ? 2 : 1)
            }
            let n = point(0, radius + 14)
            context.draw(Text("N").font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.38)), at: n)
            let f = point(friendBearing, radius - 22)
            let friendColor = Color(red: 1, green: 0.84, blue: 0.5)
            context.fill(Path(ellipseIn: CGRect(x: f.x - 4, y: f.y - 4, width: 8, height: 8)),
                         with: .color(friendColor.opacity(0.55 + 0.45 * glow)))
            // Fixed lubber line at the top: "where the phone points".
            var lubber = Path()
            lubber.move(to: CGPoint(x: c.x, y: c.y - radius - 4))
            lubber.addLine(to: CGPoint(x: c.x - 5, y: c.y - radius - 13))
            lubber.addLine(to: CGPoint(x: c.x + 5, y: c.y - radius - 13))
            lubber.closeSubpath()
            context.fill(lubber, with: .color(.white.opacity(0.8)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Engine

struct CompassFrame {
    var outline: [Vec2]
    var heading: Double
    var glow: Double
    var tickCount: Int
    var isAligned: Bool
    var isSettled: Bool
}

/// Holds the deterministic model outside SwiftUI's dependency tracking.
final class CompassEngine {
    private var model: LiquidCompassModel
    private var lastDate: Date?

    init(friendBearing: Double) { model = LiquidCompassModel(heading: 0, friendBearing: friendBearing) }

    func setHeading(_ degrees: Double) { model.setHeading(degrees) }
    func setFriendBearing(_ degrees: Double) { model.setFriendBearing(degrees) }

    func frame(at date: Date, reduceMotion: Bool) -> CompassFrame {
        if model.reduceMotion != reduceMotion { model.reduceMotion = reduceMotion }
        if let lastDate { model.step(date.timeIntervalSince(lastDate)) }
        lastDate = model.isSettled ? nil : date
        return CompassFrame(outline: model.outline(), heading: model.heading, glow: model.glow,
                            tickCount: model.tickCount, isAligned: model.isAligned,
                            isSettled: model.isSettled)
    }
}

// MARK: - Preview

private struct CompassDemo: View {
    @State private var distance = 1_480.0
    var body: some View {
        LiquidMetalCompass(friendName: "Maya", friendBearing: 62, distance: distance,
                           fakeHeadingWithDrag: true)
            .overlay(alignment: .bottom) {
                Button("Walk closer") { distance = max(distance * 0.82 - 20, 0) }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .padding(.bottom, 24)
            }
    }
}

#Preview("Liquid Metal Compass") {
    CompassDemo()
}
#endif
