//  SweaterRail.swift
//  SweaterRail
//
//  A clothes rail that behaves like the macOS Dock. Run a finger along it and the garments
//  under it swell and come forward while their neighbours shuffle apart; every hook rides a
//  spring, and every garment hangs from its hook on a pendulum driven by the hook's
//  acceleration, so a spread sets the whole rail gently swinging. Tap one and it flies into a
//  detail page (matchedGeometryEffect) while the others slide off left and right. A ticker
//  scrolls along the bottom. Falloff, layout, springs, pendulums, exits and the marquee live
//  in SweaterRailCore.

#if canImport(SwiftUI)
import SwiftUI
import SweaterRailCore

/// One garment on the rail. Drawn from shapes (no images).
public struct RailGarment: Identifiable, Hashable, Sendable {
    public enum Style: String, Hashable, Sendable, CaseIterable {
        case crew, stripes, cardigan, hoodie, cable
    }

    public let id: String
    public var name: String
    public var price: String
    public var blurb: String
    public var style: Style
    /// sRGB components 0…1.
    public var body: RGB
    public var accent: RGB

    public struct RGB: Hashable, Sendable {
        public var r: Double, g: Double, b: Double
        public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
        var color: Color { Color(red: r, green: g, blue: b) }
        func scaled(_ k: Double) -> Color { Color(red: r * k, green: g * k, blue: b * k) }
    }

    public init(id: String, name: String, price: String, blurb: String, style: Style, body: RGB, accent: RGB) {
        self.id = id; self.name = name; self.price = price; self.blurb = blurb
        self.style = style; self.body = body; self.accent = accent
    }

    public static let samples: [RailGarment] = [
        RailGarment(id: "fern", name: "Fern Crewneck", price: "$128", blurb: "Brushed lambswool, relaxed shoulder.",
                    style: .crew, body: RGB(0.16, 0.42, 0.30), accent: RGB(0.10, 0.30, 0.21)),
        RailGarment(id: "tangerine", name: "Tangerine Stripe", price: "$112", blurb: "Breton stripes in organic cotton.",
                    style: .stripes, body: RGB(0.96, 0.55, 0.22), accent: RGB(0.98, 0.91, 0.80)),
        RailGarment(id: "cobalt", name: "Cobalt Cardigan", price: "$146", blurb: "Merino rib with horn-look buttons.",
                    style: .cardigan, body: RGB(0.18, 0.32, 0.72), accent: RGB(0.92, 0.80, 0.45)),
        RailGarment(id: "plum", name: "Plum Hoodie", price: "$98", blurb: "Heavy loopback fleece, kangaroo pocket.",
                    style: .hoodie, body: RGB(0.50, 0.24, 0.46), accent: RGB(0.36, 0.15, 0.33)),
        RailGarment(id: "oat", name: "Oat Cable Knit", price: "$164", blurb: "Chunky fisherman cables, undyed wool.",
                    style: .cable, body: RGB(0.90, 0.84, 0.72), accent: RGB(0.78, 0.70, 0.56)),
    ]
}

/// A Dock-style clothes rail with a hero detail page and a marquee.
///
/// ```swift
/// SweaterRail()                                    // five sample knits
/// SweaterRail(garments: myKnits, brand: "Loop")
/// ```
public struct SweaterRail: View {
    private let garments: [RailGarment]
    private let brand: String
    private let ticker: String

    @State private var engine: RailEngine
    @State private var isAnimating = false
    @State private var hovered: Int?
    @State private var selected: RailGarment.ID?
    @State private var stageWidth: CGFloat = 393
    @Namespace private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Garment width at rest; height is 1.6 × that.
    static let garmentWidth: CGFloat = 58
    static let aspect: CGFloat = 1.6
    /// Where the hook sits, as a fraction of the garment's height (the swing pivot).
    static let hookPivot = UnitPoint(x: 0.5, y: 0.075 / 1.6)
    static let rodY: CGFloat = 56
    static let stageHeight: CGFloat = 290

    public init(garments: [RailGarment] = RailGarment.samples, brand: String = "Knit & Rail",
                ticker: String = "NEW KNITS DAILY  ✦  FREE RETURNS  ✦  SUBSCRIBE TO OUR NEWSLETTER  ✦  ") {
        self.garments = garments
        self.brand = brand
        self.ticker = ticker
        _engine = State(initialValue: RailEngine(count: garments.count))
    }

    private var selectedIndex: Int? { selected.flatMap { id in garments.firstIndex { $0.id == id } } }

    public var body: some View {
        ZStack {
            RailBackdrop()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                stage
                caption
                Spacer(minLength: 12)
                MarqueeBanner(text: ticker, isPaused: reduceMotion)
            }
            if let i = selectedIndex {
                detail(garments[i])
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .sensoryFeedback(.selection, trigger: hovered)
        .sensoryFeedback(.impact(weight: .light), trigger: selected)
    }

    // MARK: Header and caption

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text("SHOP     ABOUT")
                Spacer()
                Text("BAG (0)")
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(.black.opacity(0.6))
            Text(brand)
                .font(.system(size: 34, weight: .semibold, design: .serif).italic())
                .foregroundStyle(Color(red: 0.13, green: 0.27, blue: 0.20))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .opacity(selected == nil ? 1 : 0)
        .accessibilityElement(children: .combine)
    }

    private var caption: some View {
        let g = hovered.map { garments[$0] }
        return VStack(spacing: 14) {
            Text(g.map { "\($0.name.uppercased())  ·  \($0.price)" } ?? "DRAG ALONG THE RAIL")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.black.opacity(0.55))
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.15), value: hovered)
            Text("TAP TO VIEW")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .overlay(Capsule().strokeBorder(.black.opacity(0.55), lineWidth: 1))
                .foregroundStyle(.black.opacity(0.7))
                .opacity(hovered == nil ? 0.35 : 1)
        }
        .opacity(selected == nil ? 1 : 0)
        .accessibilityHidden(true)
    }

    // MARK: Rail

    private var stage: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                let frame = engine.frame(at: timeline.date, reduceMotion: reduceMotion, center: proxy.size.width / 2)
                ZStack(alignment: .topLeading) {
                    RailRod(width: proxy.size.width).position(x: proxy.size.width / 2, y: Self.rodY)
                        .opacity(selected == nil ? 1 : 0)
                        .animation(.easeOut(duration: 0.25), value: selected)
                    // Wall shadows first, so a neighbour's shadow never lands on a garment.
                    ForEach(Array(garments.enumerated()), id: \.element.id) { i, g in
                        if g.id != selected {
                            shadow(g, pose: frame.poses[i], index: i)
                        }
                    }
                    ForEach(Array(garments.enumerated()), id: \.element.id) { i, g in
                        if g.id != selected {
                            garment(g, pose: frame.poses[i], index: i)
                        }
                    }
                }
                .onChange(of: frame.isSettled) { _, settled in
                    if settled && engine.fingerX == nil { isAnimating = false }
                }
            }
            .contentShape(Rectangle())
            .gesture(railDrag)
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): setFinger(p.x)
                case .ended: setFinger(nil)
                }
            }
            #endif
            .onAppear { stageWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, w in stageWidth = w; isAnimating = true }
        }
        .frame(height: Self.stageHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Clothes rail")
    }

    private func size(_ scale: Double) -> CGSize {
        CGSize(width: Self.garmentWidth * scale, height: Self.garmentWidth * Self.aspect * scale)
    }

    /// The garment's frame origin so its hook sits on the rod.
    private func origin(_ pose: RailPose, size s: CGSize) -> CGPoint {
        CGPoint(x: pose.x - s.width / 2, y: Self.rodY - s.height * Self.hookPivot.y + pose.emphasis * 6)
    }

    private func exitOffset(_ i: Int) -> CGFloat {
        guard let s = selectedIndex else { return 0 }
        return RailExit.offset(index: i, selected: s, width: stageWidth)
    }

    private func exitAnimation(_ i: Int) -> Animation {
        guard let s = selectedIndex ?? lastSelected else { return .spring(duration: 0.5, bounce: 0.15) }
        return .spring(duration: 0.55, bounce: 0.12).delay(RailExit.delay(index: i, selected: s))
    }

    @State private var lastSelected: Int?

    private func shadow(_ g: RailGarment, pose: RailPose, index i: Int) -> some View {
        let s = size(pose.scale), o = origin(pose, size: s)
        return GarmentCanvas(garment: g, silhouette: true)
            .frame(width: s.width, height: s.height)
            .rotationEffect(.degrees(-pose.swingDegrees), anchor: Self.hookPivot)
            .blur(radius: 5 + pose.emphasis * 4)
            .opacity(0.16 + pose.emphasis * 0.05)
            .position(x: o.x + s.width / 2 + 10 + pose.emphasis * 6, y: o.y + s.height / 2 + 34 + pose.emphasis * 16)
            .offset(x: exitOffset(i))
            .opacity(selected == nil ? 1 : 0)
            .animation(exitAnimation(i), value: selected)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func garment(_ g: RailGarment, pose: RailPose, index i: Int) -> some View {
        let s = size(pose.scale), o = origin(pose, size: s)
        return GarmentCanvas(garment: g)
            .matchedGeometryEffect(id: g.id, in: hero)
            .frame(width: s.width, height: s.height)
            .rotationEffect(.degrees(-pose.swingDegrees), anchor: Self.hookPivot)
            // .position (layout), not .offset, so matchedGeometryEffect sees where it hangs.
            .position(x: o.x + s.width / 2, y: o.y + s.height / 2)
            .offset(x: exitOffset(i))
            .animation(exitAnimation(i), value: selected)
            .zIndex(pose.emphasis)
            .accessibilityElement()
            .accessibilityLabel("\(g.name), \(g.price)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { select(i) }
    }

    private var railDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in if selected == nil { setFinger(v.location.x) } }
            .onEnded { v in
                let moved = hypot(v.translation.width, v.translation.height)
                let tapped = moved < 8 ? engine.hoveredIndex : nil
                setFinger(nil)
                if let tapped { select(tapped) }
            }
    }

    private func setFinger(_ x: CGFloat?) {
        engine.setFinger(x.map(Double.init))
        hovered = engine.hoveredIndex
        isAnimating = true
    }

    private func select(_ i: Int) {
        lastSelected = i
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.55, bounce: 0.18)) {
            selected = garments[i].id
        }
    }

    private func close() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.5, bounce: 0.15)) {
            selected = nil
        }
        isAnimating = true
    }

    // MARK: Detail

    private func detail(_ g: RailGarment) -> some View {
        VStack(spacing: 18) {
            HStack {
                Text(brand).font(.system(size: 20, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(Color(red: 0.13, green: 0.27, blue: 0.20))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(.black.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20)
            GarmentCanvas(garment: g)
                .matchedGeometryEffect(id: g.id, in: hero)
                .frame(width: 200, height: 200 * Self.aspect)
                .shadow(color: .black.opacity(0.18), radius: 18, y: 16)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text(g.name).font(.system(size: 28, weight: .semibold, design: .serif))
                Text(g.price).font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.6))
                Text(g.blurb).font(.system(size: 15)).foregroundStyle(.black.opacity(0.55))
                    .multilineTextAlignment(.center).padding(.top, 2)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                ForEach(["XS", "S", "M", "L", "XL"], id: \.self) { size in
                    Text(size).font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .frame(width: 44, height: 34)
                        .background(size == "M" ? Color.black : Color.black.opacity(0.06), in: Capsule())
                        .foregroundStyle(size == "M" ? Color.white : Color.black.opacity(0.7))
                }
            }
            .accessibilityHidden(true)
            Text("ADD TO BAG")
                .font(.system(size: 13, weight: .semibold, design: .monospaced)).tracking(1.5)
                .frame(maxWidth: 260).padding(.vertical, 14)
                .background(Color(red: 0.13, green: 0.27, blue: 0.20), in: Capsule())
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isButton)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }
}

// MARK: - Drawing

/// Draws one hanging garment in unit coordinates (width 1, height 1.6), so it scales to any
/// frame and matches the web preview stroke for stroke.
struct GarmentCanvas: View {
    let garment: RailGarment
    var silhouette = false

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * w, y: y * w) }
            func poly(_ pts: [(Double, Double)]) -> Path {
                var path = Path()
                path.move(to: p(pts[0].0, pts[0].1))
                for q in pts.dropFirst() { path.addLine(to: p(q.0, q.1)) }
                path.closeSubpath()
                return path
            }
            var bodyPath = Path()
            bodyPath.move(to: p(0.37, 0.22))
            bodyPath.addQuadCurve(to: p(0.63, 0.22), control: p(0.5, 0.36))
            for q in [(0.90, 0.30), (0.80, 0.62), (0.81, 1.52), (0.19, 1.52), (0.20, 0.62), (0.10, 0.30)] {
                bodyPath.addLine(to: p(q.0, q.1))
            }
            bodyPath.closeSubpath()
            let sleeveL = poly([(0.10, 0.30), (0.25, 0.36), (0.17, 1.40), (0.02, 1.38)])
            let sleeveR = poly([(0.90, 0.30), (0.75, 0.36), (0.83, 1.40), (0.98, 1.38)])

            // Hook and hanger, behind the garment.
            var hook = Path()
            hook.addArc(center: p(0.5, 0.075), radius: 0.055 * w, startAngle: .radians(.pi),
                        endAngle: .radians(2.5 * .pi), clockwise: false)
            hook.addLine(to: p(0.5, 0.2))
            var bar = Path()
            bar.move(to: p(0.12, 0.27)); bar.addLine(to: p(0.5, 0.19)); bar.addLine(to: p(0.88, 0.27))

            if silhouette {
                ctx.fill(bodyPath, with: .color(.black))
                ctx.fill(sleeveL, with: .color(.black))
                ctx.fill(sleeveR, with: .color(.black))
                ctx.stroke(hook, with: .color(.black), lineWidth: 0.022 * w)
                return
            }
            ctx.stroke(hook, with: .color(Color(white: 0.28)), style: StrokeStyle(lineWidth: 0.022 * w, lineCap: .round))
            ctx.stroke(bar, with: .color(Color(red: 0.55, green: 0.38, blue: 0.22)),
                       style: StrokeStyle(lineWidth: 0.03 * w, lineCap: .round, lineJoin: .round))

            let g = garment
            let stripes = g.style == .stripes
            for sleeve in [sleeveL, sleeveR] {
                ctx.fill(sleeve, with: .color(g.body.scaled(0.86)))
                var c = ctx
                c.clip(to: sleeve)
                if stripes { drawStripes(&c, w: w, color: g.accent.scaled(0.92)) }
                c.fill(Path(CGRect(x: 0, y: 1.31 * w, width: w, height: 0.2 * w)), with: .color(g.accent.scaled(stripes ? 0.8 : 1)))
            }
            ctx.fill(bodyPath, with: .color(g.body.color))
            var c = ctx
            c.clip(to: bodyPath)
            if stripes { drawStripes(&c, w: w, color: g.accent.color) }
            switch g.style {
            case .crew:
                c.fill(Path(ellipseIn: CGRect(x: 0.6 * w, y: 0.5 * w, width: 0.09 * w, height: 0.09 * w)), with: .color(g.accent.color))
            case .cardigan:
                var placket = Path(); placket.move(to: p(0.5, 0.29)); placket.addLine(to: p(0.5, 1.52))
                c.stroke(placket, with: .color(.black.opacity(0.22)), lineWidth: 0.018 * w)
                for k in 0..<5 {
                    let y = 0.42 + Double(k) * 0.22
                    c.fill(Path(ellipseIn: CGRect(x: 0.468 * w, y: (y - 0.032) * w, width: 0.064 * w, height: 0.064 * w)),
                           with: .color(g.accent.color))
                }
            case .hoodie:
                for x in [0.45, 0.55] {
                    var cord = Path(); cord.move(to: p(x, 0.28)); cord.addLine(to: p(x + (x < 0.5 ? -0.01 : 0.01), 0.62))
                    c.stroke(cord, with: .color(Color(white: 0.95)), style: StrokeStyle(lineWidth: 0.018 * w, lineCap: .round))
                }
                c.fill(Path(roundedRect: CGRect(x: 0.3 * w, y: 1.06 * w, width: 0.4 * w, height: 0.26 * w), cornerRadius: 0.06 * w),
                       with: .color(g.accent.color))
            case .cable:
                for x0 in [0.36, 0.5, 0.64] {
                    for phase in [0.0, Double.pi] {
                        var cable = Path()
                        for k in 0...40 {
                            let y = 0.34 + Double(k) / 40 * 1.06
                            let pt = p(x0 + 0.03 * sin(y * 18 + phase), y)
                            if k == 0 { cable.move(to: pt) } else { cable.addLine(to: pt) }
                        }
                        c.stroke(cable, with: .color(g.accent.color), lineWidth: 0.02 * w)
                    }
                }
            case .stripes:
                break
            }
            // Ribbed hem.
            c.fill(Path(CGRect(x: 0, y: 1.42 * w, width: w, height: 0.12 * w)), with: .color(g.accent.scaled(stripes ? 0.8 : 1)))
            for k in 0..<34 {
                let x = 0.18 + Double(k) * 0.019
                c.fill(Path(CGRect(x: x * w, y: 1.42 * w, width: 0.006 * w, height: 0.1 * w)), with: .color(.black.opacity(0.1)))
            }
            // Soft light from above.
            c.fill(Path(CGRect(x: 0, y: 0, width: w, height: 1.6 * w)),
                   with: .linearGradient(Gradient(colors: [.white.opacity(0.12), .clear, .black.opacity(0.14)]),
                                         startPoint: p(0.2, 0.2), endPoint: p(0.8, 1.55)))
            // Collar rib.
            var neck = Path(); neck.move(to: p(0.37, 0.22)); neck.addQuadCurve(to: p(0.63, 0.22), control: p(0.5, 0.36))
            ctx.stroke(neck, with: .color(g.accent.scaled(stripes ? 0.8 : 1)),
                       style: StrokeStyle(lineWidth: 0.045 * w, lineCap: .round))
        }
    }

    private func drawStripes(_ c: inout GraphicsContext, w: CGFloat, color: Color) {
        var y = 0.4
        while y < 1.5 {
            c.fill(Path(CGRect(x: 0, y: y * w, width: w, height: 0.06 * w)), with: .color(color))
            y += 0.14
        }
    }
}

private struct RailRod: View {
    let width: CGFloat
    var body: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.25)], startPoint: .top, endPoint: .bottom))
                .frame(width: width - 48, height: 5)
            HStack {
                bracket
                Spacer()
                bracket
            }
            .frame(width: width - 56)
        }
        .accessibilityHidden(true)
    }

    private var bracket: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color(white: 0.3))
            .frame(width: 3, height: 26)
            .offset(y: -11)
    }
}

private struct RailBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.91, green: 0.90, blue: 0.87)))
            var y: CGFloat = 9
            while y < size.height {
                var x: CGFloat = 9
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)), with: .color(.black.opacity(0.07)))
                    x += 18
                }
                y += 18
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// An endless ticker along the bottom.
struct MarqueeBanner: View {
    let text: String
    var isPaused = false
    @State private var itemWidth: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: isPaused || itemWidth == 0)) { timeline in
                let marquee = Marquee(speed: 40, itemWidth: itemWidth)
                let copies = Marquee.copiesNeeded(viewport: proxy.size.width, itemWidth: itemWidth)
                HStack(spacing: 0) {
                    ForEach(0..<max(copies, 1), id: \.self) { _ in label }
                }
                .offset(x: isPaused ? 0 : marquee.offset(at: timeline.date.timeIntervalSinceReferenceDate))
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 34)
        .clipped()
        .background(Color(red: 0.13, green: 0.27, blue: 0.20).ignoresSafeArea(edges: .bottom))
        .background(alignment: .topLeading) {
            label.hidden().background(GeometryReader { p in
                Color.clear
                    .onAppear { itemWidth = p.size.width }
                    .onChange(of: p.size.width) { _, w in itemWidth = w }
            })
        }
        .accessibilityElement()
        .accessibilityLabel(text.replacingOccurrences(of: "✦", with: ","))
    }

    private var label: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(2)
            .foregroundStyle(Color(red: 0.95, green: 0.92, blue: 0.82))
            .fixedSize()
    }
}

// MARK: - Engine

struct RailPose: Equatable {
    var x: Double, scale: Double, swingDegrees: Double, emphasis: Double
}

struct RailFrame {
    var poses: [RailPose]
    var isSettled: Bool
}

/// Owns the model outside SwiftUI's dependency tracking; the TimelineView steps it by date.
final class RailEngine {
    private var model: SweaterRailModel
    private var lastDate: Date?

    init(count: Int) { model = SweaterRailModel(count: count) }

    var fingerX: Double? { model.fingerX }
    var hoveredIndex: Int? { model.hoveredIndex }

    func setFinger(_ x: Double?) { model.setFinger(x) }

    func frame(at date: Date, reduceMotion: Bool, center: Double) -> RailFrame {
        if model.reduceMotion != reduceMotion { model.reduceMotion = reduceMotion }
        model.setRailCenter(center)
        if let lastDate { model.step(date.timeIntervalSince(lastDate)) }
        let settled = model.isSettled
        lastDate = settled && model.fingerX == nil ? nil : date
        return RailFrame(poses: (0..<model.count).map { i in
            let p = model.pose(i)
            return RailPose(x: p.x, scale: p.scale, swingDegrees: p.swingDegrees, emphasis: p.emphasis)
        }, isSettled: settled)
    }
}

// MARK: - Preview

#Preview("Sweater Rail") {
    SweaterRail()
}
#endif
