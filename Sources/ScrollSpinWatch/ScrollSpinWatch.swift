//  ScrollSpinWatch.swift
//  ScrollSpinWatch
//
//  A dark technical product page whose centrepiece is a smartwatch built from shapes. Scrolling
//  scrubs it front → side profile → back → front: the watch is a stack of flat layers (straps,
//  case slices, dial, caseback, crown), each turned with `rotation3DEffect`, slid by its depth
//  and shaded by a Lambert term, painted far-to-near. Copy blocks fade and slide up in sync with
//  the rotation's holds, ending on a stats row with numericText transitions. Scroll progress
//  comes from `onScrollGeometryChange` on iOS 18 / macOS 15 and a GeometryReader before that.
//  Keyframes, story timing and the layer projection live in SpinWatchCore.

#if canImport(SwiftUI)
import SwiftUI
import SpinWatchCore

/// A scroll-scrubbed product page with a turning watch.
///
/// ```swift
/// ScrollSpinWatch()
/// ```
public struct ScrollSpinWatch: View {
    @State private var progress = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let story = SpinStory()

    /// How many screens of scrolling the story takes.
    static let pages: CGFloat = 4

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                TechBackground()
                content(size: proxy.size)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint("Swipe up or down to turn the watch")
                    .accessibilityAdjustableAction { direction in
                        // VoiceOver can't use the hidden scroll driver, so step between the poses.
                        let holds = story.sections.map { ($0.start + $0.end) / 2 }
                        let current = story.activeSection(at: progress)
                        switch direction {
                        case .increment: progress = holds[min(current + 1, holds.count - 1)]
                        case .decrement: progress = holds[max(current - 1, 0)]
                        @unknown default: break
                        }
                    }
                ScrollView(.vertical) {
                    Color.clear
                        .frame(height: proxy.size.height * Self.pages)
                        .background {
                            // iOS 17 / macOS 14: read the offset from the content's frame.
                            GeometryReader { g in
                                let minY = g.frame(in: .named("spin")).minY
                                Color.clear.onChange(of: minY) { _, y in
                                    if !Self.usesScrollGeometry {
                                        progress = Self.progress(minY: Double(y), viewport: Double(proxy.size.height))
                                    }
                                }
                            }
                        }
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "spin")
                .modifier(ScrollProgressReader(progress: $progress))
                .accessibilityHidden(true)
            }
        }
        .background(Color(white: 0.04))
        .preferredColorScheme(.dark)
    }

    static var usesScrollGeometry: Bool {
        if #available(iOS 18.0, macOS 15.0, *) { return true } else { return false }
    }

    static func progress(minY: Double, viewport: Double) -> Double {
        let range = viewport * Double(pages - 1)
        return range > 0 ? min(max(-minY / range, 0), 1) : 0
    }

    // MARK: Layout

    private func content(size: CGSize) -> some View {
        let p = progress
        let yaw = story.yaw(at: p)
        return ZStack {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    ForEach(0..<3, id: \.self) { i in section(i, p: p) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 150, alignment: .top)
                .padding(.top, 70)
                .padding(.horizontal, 26)
                Spacer(minLength: 0)
                stats(p: p)
                    .padding(.horizontal, 26)
                    .padding(.bottom, 46)
            }
            WatchModel(yaw: yaw, seconds: p * 360 * 3)
                .scaleEffect(0.78)
                .position(x: size.width / 2, y: size.height * 0.53)
                .accessibilityHidden(true)
            Readout(yaw: yaw, progress: p, holds: story.sections.map(\.start))
                .frame(width: size.width, height: size.height)
                .opacity(1 - story.opacity(ofSection: story.sections.count - 1, at: p))
                .accessibilityHidden(true)
        }
    }

    private func section(_ i: Int, p: Double) -> some View {
        let s = story.sections[i]
        return VStack(alignment: .leading, spacing: 10) {
            Text(s.kicker)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color(red: 1, green: 0.23, blue: 0.19))
            Text(s.title)
                .font(.system(size: 34, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(s.body)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.55))
        }
        .opacity(story.opacity(ofSection: i, at: p))
        .offset(y: reduceMotion ? 0 : story.offset(ofSection: i, at: p))
        .accessibilityHidden(story.opacity(ofSection: i, at: p) < 0.5)
    }

    private func stats(p: Double) -> some View {
        let last = story.sections.count - 1
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(story.stats.indices, id: \.self) { i in
                    let v = story.statValue(i, at: p)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(v)")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(v)))
                                .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: v)
                            Text(story.stats[i].unit)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(red: 1, green: 0.23, blue: 0.19))
                        }
                        Text(story.stats[i].label.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(story.stats[i].value) \(story.stats[i].unit), \(story.stats[i].label)")
                }
            }
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            Text(story.sections[last].body)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
        }
        .opacity(story.opacity(ofSection: last, at: p))
        .offset(y: reduceMotion ? 0 : story.offset(ofSection: last, at: p))
        .accessibilityHidden(story.opacity(ofSection: last, at: p) < 0.5)
    }
}

/// Feeds scroll progress from the iOS 18 / macOS 15 scroll geometry API.
private struct ScrollProgressReader: ViewModifier {
    @Binding var progress: Double

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content.onScrollGeometryChange(for: Double.self) { geo in
                let range = geo.contentSize.height - geo.containerSize.height
                return range > 0 ? (geo.contentOffset.y + geo.contentInsets.top) / range : 0
            } action: { _, new in
                progress = min(max(new, 0), 1)
            }
        } else {
            content
        }
    }
}

// MARK: - Watch

/// The watch as painted layers. Model units: case 168 × 200 pt, 40 pt deep (47 mm × 11.2 mm).
struct WatchModel: View {
    var yaw: Double
    var seconds: Double

    static let caseSize = CGSize(width: 168, height: 200)
    static let depth = 40.0
    static let strapDepth = 6.0
    static let red = Color(red: 1, green: 0.23, blue: 0.19)

    /// `side` / `strapSide` are the left (−1) and right (+1) edge faces, which carry the
    /// profile when the flat layers turn edge-on.
    enum Part: Hashable { case strap(Double), strapSide(Double), slice(Double), side(Double), back, front, crown }

    struct Layer: Identifiable {
        var part: Part
        var place: WatchProjection.Placement
        var id: Part { part }
    }

    private var parts: [Layer] {
        var list: [(Part, WatchProjection.Placement)] = []
        for z in stride(from: -3.0, through: 3, by: 1.5) { list.append((.strap(z), WatchProjection.place(z: z, yawDegrees: yaw))) }
        for side in [-1.0, 1.0] {
            list.append((.strapSide(side), WatchProjection.place(x: side * 61, z: 0, yawDegrees: yaw)))
            list.append((.side(side), WatchProjection.place(x: side * Self.caseSize.width / 2, z: 0, yawDegrees: yaw)))
        }
        for z in stride(from: -18.0, through: 18, by: 2) { list.append((.slice(z), WatchProjection.place(z: z, yawDegrees: yaw))) }
        list.append((.back, WatchProjection.place(z: -Self.depth / 2, yawDegrees: yaw)))
        list.append((.front, WatchProjection.place(z: Self.depth / 2, yawDegrees: yaw)))
        list.append((.crown, WatchProjection.place(x: Self.caseSize.width / 2 + 3, z: 0, yawDegrees: yaw)))
        return WatchProjection.paintOrder(list.map { $0.1.depth }).map { Layer(part: list[$0].0, place: list[$0].1) }
    }

    var body: some View {
        ZStack {
            ForEach(parts) { item in
                layer(item.part)
                    .rotation3DEffect(.degrees(Self.isBillboard(item.part) ? 0 : -yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.2)
                    .offset(x: item.place.offsetX)
            }
        }
        .frame(width: 420, height: 520)
    }

    /// Edge faces and the crown are sized from the yaw directly instead of being rotated.
    static func isBillboard(_ part: Part) -> Bool {
        switch part {
        case .crown, .side, .strapSide: return true
        default: return false
        }
    }

    @ViewBuilder private func layer(_ part: Part) -> some View {
        let edge = abs(sin(yaw * .pi / 180))
        let band = WatchProjection.bandBrightness(yawDegrees: yaw)
        switch part {
        case .strap:
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.10), Color(white: 0.17), Color(white: 0.10)], startPoint: .top, endPoint: .bottom))
                .frame(width: 122, height: 470)
        case .strapSide:
            RoundedRectangle(cornerRadius: min(Self.strapDepth * edge / 2, 3), style: .continuous)
                .fill(Color(white: 0.16))
                .frame(width: Self.strapDepth * edge, height: 470 - 40)
        case .side(let sign):
            RoundedRectangle(cornerRadius: min(Self.depth * edge / 2, 16), style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.5 * WatchProjection.brightness(normalAngle: 90 * sign, yawDegrees: yaw)),
                                              Color(white: 0.7 * WatchProjection.brightness(normalAngle: 90 * sign, yawDegrees: yaw)),
                                              Color(white: 0.5 * WatchProjection.brightness(normalAngle: 90 * sign, yawDegrees: yaw))],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: Self.depth * edge, height: Self.caseSize.height - 12)
        case .slice:
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(Color(white: 0.62 * band))
                .frame(width: Self.caseSize.width, height: Self.caseSize.height)
        case .back:
            CaseBack(brightness: WatchProjection.brightness(normalAngle: 180, yawDegrees: yaw))
        case .front:
            Dial(seconds: seconds, brightness: WatchProjection.brightness(normalAngle: 0, yawDegrees: yaw))
        case .crown:
            let s = abs(sin(yaw * .pi / 180)), c = abs(cos(yaw * .pi / 180))
            ZStack {
                Capsule().fill(Color(white: 0.7 * band))
                Capsule().strokeBorder(Self.red, lineWidth: 1.5).padding(.vertical, 6)
            }
            .frame(width: 9 * c + 18 * s, height: 30)
            .offset(y: -26)
        }
    }
}

private struct Dial: View {
    var seconds: Double
    var brightness: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.85 * brightness), Color(white: 0.45 * brightness)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(RadialGradient(colors: [Color(white: 0.11), Color(white: 0.02)], center: .center, startRadius: 0, endRadius: 110))
                .padding(7)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<60 {
                    let a = Double(i) / 60 * 2 * .pi, major = i % 5 == 0
                    let r0 = major ? 58.0 : 62, r1 = 67.0
                    var p = Path()
                    p.move(to: CGPoint(x: c.x + sin(a) * r0, y: c.y - cos(a) * r0))
                    p.addLine(to: CGPoint(x: c.x + sin(a) * r1, y: c.y - cos(a) * r1))
                    ctx.stroke(p, with: .color(.white.opacity(major ? 0.9 : 0.35)), lineWidth: major ? 2 : 1)
                }
                func hand(_ deg: Double, _ len: Double, _ w: Double, _ color: Color, tail: Double = 0) {
                    let a = deg * .pi / 180
                    var p = Path()
                    p.move(to: CGPoint(x: c.x - sin(a) * tail, y: c.y + cos(a) * tail))
                    p.addLine(to: CGPoint(x: c.x + sin(a) * len, y: c.y - cos(a) * len))
                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round))
                }
                hand(304.5, 38, 4.5, .white)          // 10 o'clock
                hand(54, 54, 3, .white)               // 09 minutes
                hand(seconds, 60, 1.4, WatchModel.red, tail: 12)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(WatchModel.red))
            }
            VStack {
                Text("CHRONO")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 40)
                Spacer()
                Text("WED 22")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WatchModel.red)
                    .padding(.bottom, 44)
            }
            // Glass glint.
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.16 * brightness), .clear], startPoint: .topLeading, endPoint: .center))
                .padding(7)
        }
        .frame(width: WatchModel.caseSize.width, height: WatchModel.caseSize.height)
    }
}

private struct CaseBack: View {
    var brightness: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 46, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.78 * brightness), Color(white: 0.5 * brightness)],
                                     startPoint: .top, endPoint: .bottom))
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.16), Color(white: 0.05)], center: .center, startRadius: 0, endRadius: 60))
                .frame(width: 112, height: 112)
            ForEach(0..<4, id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i % 2 == 0 ? Color(red: 0.2, green: 0.9, blue: 0.5).opacity(0.8) : WatchModel.red.opacity(0.85))
                    .frame(width: 7, height: 16)
                    .offset(y: -22)
                    .rotationEffect(.degrees(45 + Double(i) * 90))
            }
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1).frame(width: 140, height: 140)
            Text("SN 0001-26  ·  TI GR5")
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.black.opacity(0.45))
                .offset(y: 84)
        }
        .frame(width: WatchModel.caseSize.width, height: WatchModel.caseSize.height)
    }
}

// MARK: - Decoration

private struct TechBackground: View {
    var body: some View {
        Canvas { ctx, size in
            for x in stride(from: 0.0, through: size.width, by: 24) {
                ctx.fill(Path(CGRect(x: x, y: 0, width: 0.5, height: size.height)), with: .color(.white.opacity(0.045)))
            }
            for y in stride(from: 0.0, through: size.height, by: 24) {
                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), with: .color(.white.opacity(0.045)))
            }
            let c = CGPoint(x: size.width / 2, y: size.height * 0.53)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 160, y: c.y - 160, width: 320, height: 320)), with: .color(.white.opacity(0.07)), lineWidth: 1)
        }
        .background(Color(white: 0.04))
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Small red instrumentation: a yaw readout and a progress rail with the hold marks.
private struct Readout: View {
    var yaw: Double
    var progress: Double
    var holds: [Double]

    var body: some View {
        ZStack(alignment: .topLeading) {
            let deg = Int(yaw.rounded()) % 360
            HStack(spacing: 6) {
                Rectangle().fill(WatchModel.red).frame(width: 6, height: 6)
                Text("YAW \(String(format: "%03d", deg))°")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText(value: Double(deg)))
            }
            .position(x: 62, y: 610)
            GeometryReader { g in
                let x = g.size.width - 14, top = 250.0, h = 260.0
                Rectangle().fill(.white.opacity(0.14)).frame(width: 1, height: h).position(x: x, y: top + h / 2)
                Rectangle().fill(WatchModel.red).frame(width: 2, height: h * progress).position(x: x, y: top + h * progress / 2)
                ForEach(holds.indices, id: \.self) { i in
                    Rectangle().fill(.white.opacity(0.5)).frame(width: 7, height: 1).position(x: x, y: top + h * holds[i])
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Scroll Spin Watch") {
    ScrollSpinWatch()
}
#endif
