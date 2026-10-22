//  BoutiqueBurst.swift
//  BoutiqueBurst
//
//  A large serif "Boutique" on white with a few paper-doll cutouts around it. A tap or a
//  swipe fills the screen with dozens of figures in a staggered spring ripple from your
//  finger. Tap one and it stays while the rest fade and slide away from it, then it flies
//  into a detail view via `matchedGeometryEffect`. Figures are drawn from rounded shapes in
//  generated outfit colours; layout, stagger and scatter live in BoutiqueCore.

#if canImport(SwiftUI)
import SwiftUI
import BoutiqueCore

/// A serif word with a few cutouts that bursts into a crowd of outfits.
///
/// ```swift
/// BoutiqueBurst()
/// BoutiqueBurst(word: "Atelier", figureCount: 36)
/// ```
public struct BoutiqueBurst: View {
    private let word: String
    private let figureCount: Int
    @State private var model: BoutiqueModel
    @Namespace private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(word: String = "Boutique", figureCount: Int = 42) {
        self.word = word
        self.figureCount = max(figureCount, 1)
        _model = State(initialValue: BoutiqueModel(layout: BoutiqueLayout(width: 393, height: 852, figureCount: max(figureCount, 1))))
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { loc in
                        send(.tapBackground, at: Vec2(Double(loc.x), Double(loc.y)))
                    }
                wordmark
                crowd
                if case .detail(let s) = model.phase {
                    BoutiqueDetail(figure: model.figures[s], namespace: hero, close: { send(.close) })
                        .transition(.opacity)
                        .zIndex(2)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12).onEnded { v in
                    if model.phase == .rest, v.translation.height < -20 {
                        send(.scroll, at: Vec2(Double(v.startLocation.x), Double(v.startLocation.y)))
                    }
                }
            )
            .onAppear { relayout(proxy.size) }
            .onChange(of: proxy.size) { _, size in relayout(size) }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.impact(weight: .light), trigger: model.phase)
    }

    // MARK: Pieces

    private var wordmark: some View {
        let rect = model.layout.wordRect
        let resting = model.phase == .rest
        return VStack(spacing: 6) {
            Text("SS 2026 · THE EDIT")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.black.opacity(0.45))
                .opacity(resting ? 1 : 0)
            Text(word)
                .font(.custom("Didot", size: 84, relativeTo: .largeTitle))
                .fontWeight(.regular)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.black)
                .accessibilityAddTraits(.isHeader)
            Text("Tap to open the collection")
                .font(.system(size: 13, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.black.opacity(0.5))
                .opacity(resting ? 1 : 0)
        }
        .frame(width: rect.width + 20)
        .opacity(resting ? 1 : (model.phase == .burst ? 0.1 : 0))
        .position(x: rect.center.x, y: rect.center.y)
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.5), value: model.phase)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Open the collection") { send(.tapBackground, at: nil) }
        .accessibilityHidden(!resting)
        .allowsHitTesting(false)
    }

    private var crowd: some View {
        let delays = model.delays(reduceMotion: reduceMotion)
        let spring: Animation = reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.6, bounce: 0.25)
        return ForEach(model.figures) { figure in
            let i = figure.id
            let place = placement(i)
            let size = model.layout.figureSize(scale: place.scale)
            if model.phase != .detail(i) {
                FigureView(spec: figure)
                    .matchedGeometryEffect(id: i, in: hero)
                    .frame(width: size.width, height: size.height)
                    .rotationEffect(.degrees(place.tilt))
                    .opacity(place.opacity)
                    .position(x: place.center.x, y: place.center.y)
                    .animation(spring.delay(delays.indices.contains(i) ? delays[i] : 0), value: model.phase)
                    .onTapGesture { send(.tapFigure(i)) }
                    .allowsHitTesting(place.opacity > 0.5)
                    .zIndex(model.phase.selected == i ? 1 : 0)
                    .accessibilityElement()
                    .accessibilityLabel("\(figure.name), \(figure.price) dollars")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { send(.tapFigure(i)) }
                    .accessibilityHidden(place.opacity < 0.5)
            }
        }
    }

    private func placement(_ i: Int) -> FigurePlacement {
        var p = model.placement(of: i, in: model.phase)
        // Reduce Motion: leaving figures only fade, they don't slide.
        if reduceMotion, p.opacity == 0, model.phase.selected != nil { p.center = model.burst[i].center }
        return p
    }

    // MARK: Actions

    private func relayout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let layout = BoutiqueLayout(width: Double(size.width), height: Double(size.height), figureCount: figureCount)
        if layout != model.layout { model = BoutiqueModel(layout: layout) }
    }

    private func send(_ event: BoutiqueEvent, at point: Vec2? = nil) {
        let heroAnimation: Animation = reduceMotion ? .easeInOut(duration: 0.25) : .spring(duration: 0.55, bounce: 0.18)
        switch event {
        case .close:
            withAnimation(heroAnimation) { _ = model.send(.close) }
        default:
            guard model.send(event, at: point) else { return }
        }
        if case .focusing(let s) = model.phase {
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.2 : 0.42)) {
                guard model.phase == .focusing(s) else { return }
                withAnimation(heroAnimation) { _ = model.send(.focusSettled) }
            }
        }
    }
}

// MARK: - Detail

private struct BoutiqueDetail: View {
    var figure: FigureSpec
    var namespace: Namespace.ID
    var close: () -> Void

    var body: some View {
        let c = FigureSpec.palette[figure.color], a = FigureSpec.palette[figure.accent]
        VStack(spacing: 0) {
            HStack {
                Text("LOOK \(String(format: "%02d", figure.id + 1))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.black.opacity(0.5))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.black.opacity(0.06)))
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 62)
            ZStack {
                Circle()
                    .fill(Color(red: c.r, green: c.g, blue: c.b).opacity(0.14))
                    .frame(width: 270, height: 270)
                    .offset(y: 20)
                FigureView(spec: figure)
                    .matchedGeometryEffect(id: figure.id, in: namespace)
                    .frame(width: 150, height: 360)
            }
            .frame(height: 400)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text(figure.name)
                    .font(.custom("Didot", size: 36, relativeTo: .title))
                    .foregroundStyle(.black)
                HStack(spacing: 10) {
                    Text("$\(figure.price)")
                        .font(.system(size: 17, weight: .semibold))
                    Circle().fill(Color(red: c.r, green: c.g, blue: c.b)).frame(width: 14, height: 14)
                    Circle().fill(Color(red: a.r, green: a.g, blue: a.b)).frame(width: 14, height: 14)
                    Text("\(c.name) with \(a.name.lowercased())")
                        .font(.system(size: 13))
                        .foregroundStyle(.black.opacity(0.55))
                }
                Spacer(minLength: 12)
                Text("Add to bag")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Capsule().fill(.black))
                    .accessibilityAddTraits(.isButton)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 44)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white.opacity(0.0001))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
    }
}

// MARK: - Figure

/// A cutout drawn in a 50 × 120 model box and stretched to its frame.
struct FigureView: View {
    var spec: FigureSpec

    var body: some View {
        Canvas { ctx, size in
            FigurePainter.draw(spec, in: &ctx, size: size)
        }
        .shadow(color: .black.opacity(0.14), radius: 2.5, x: 0, y: 1.5)
    }
}

enum FigurePainter {
    static func color(_ p: (name: String, r: Double, g: Double, b: Double), _ k: Double = 1) -> Color {
        Color(red: p.r * k, green: p.g * k, blue: p.b * k)
    }

    static func draw(_ f: FigureSpec, in ctx: inout GraphicsContext, size: CGSize) {
        let t = FigureSpec.skinTones[f.skin]
        let skin = Color(red: t.r, green: t.g, blue: t.b)
        let pal = FigureSpec.palette[f.color], acc = FigureSpec.palette[f.accent]
        let outfit = color(pal), outfitDark = color(pal, 0.82), accent = color(acc)
        let h = f.hairShade
        let hair = Color(red: 0.10 + 0.35 * h, green: 0.08 + 0.22 * h, blue: 0.07 + 0.13 * h)
        let st = f.stance
        let k = f.height / 1.06
        ctx.scaleBy(x: size.width / 50, y: size.height / 120)
        ctx.translateBy(x: 0, y: 120 * (1 - k))
        ctx.scaleBy(x: 1, y: k)

        func rr(_ x: Double, _ y: Double, _ w: Double, _ hh: Double, _ r: Double) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: hh), cornerRadius: r, style: .continuous)
        }
        func line(_ a: CGPoint, _ b: CGPoint) -> Path { var p = Path(); p.move(to: a); p.addLine(to: b); return p }

        ctx.fill(Path(ellipseIn: CGRect(x: 25 + st * 2 - 14, y: 117 - 2.5, width: 28, height: 5)), with: .color(.black.opacity(0.10)))
        // Legs and shoes.
        let trousers = f.garment == .suit || f.garment == .jumpsuit
        for lx in [20 + st * 2, 30 + st * 2] {
            ctx.stroke(line(CGPoint(x: lx, y: 80), CGPoint(x: lx, y: 113)), with: .color(trousers ? outfitDark : skin),
                       style: StrokeStyle(lineWidth: 6.5, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: lx - 1 - 4.5, y: 115.5 - 2.2, width: 9, height: 4.4)), with: .color(Color(white: 0.12)))
        }
        // Arms behind the body.
        let hands = [CGPoint(x: 12 - st * 3, y: 70), CGPoint(x: 38 + st * 4, y: 68)]
        for (s, e) in zip([CGPoint(x: 15, y: 34), CGPoint(x: 35, y: 34)], hands) {
            ctx.stroke(line(s, e), with: .color(color(pal, 0.9)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: e.x - 3, y: e.y - 3, width: 6, height: 6)), with: .color(skin))
        }
        // Garment.
        switch f.garment {
        case .dress:
            var p = Path()
            p.move(to: CGPoint(x: 16, y: 30)); p.addLine(to: CGPoint(x: 34, y: 30))
            p.addQuadCurve(to: CGPoint(x: 36, y: 34), control: CGPoint(x: 36, y: 31))
            p.addLine(to: CGPoint(x: 41, y: 84)); p.addQuadCurve(to: CGPoint(x: 38, y: 87), control: CGPoint(x: 41, y: 87))
            p.addLine(to: CGPoint(x: 12, y: 87)); p.addQuadCurve(to: CGPoint(x: 9, y: 84), control: CGPoint(x: 9, y: 87))
            p.addLine(to: CGPoint(x: 14, y: 34)); p.addQuadCurve(to: CGPoint(x: 16, y: 30), control: CGPoint(x: 14, y: 31))
            p.closeSubpath()
            ctx.fill(p, with: .color(outfit))
        case .trench:
            ctx.fill(rr(13, 30, 24, 62, 6), with: .color(outfit))
            ctx.fill(rr(13, 58, 24, 3, 1), with: .color(color(pal, 0.75)))
            var v = Path(); v.move(to: CGPoint(x: 19, y: 30)); v.addLine(to: CGPoint(x: 25, y: 44)); v.addLine(to: CGPoint(x: 31, y: 30))
            ctx.stroke(v, with: .color(color(pal, 0.7)), lineWidth: 1.2)
        case .suit:
            ctx.fill(rr(13, 30, 24, 38, 6), with: .color(outfit))
            var shirt = Path(); shirt.move(to: CGPoint(x: 21, y: 30)); shirt.addLine(to: CGPoint(x: 25, y: 40)); shirt.addLine(to: CGPoint(x: 29, y: 30)); shirt.closeSubpath()
            ctx.fill(shirt, with: .color(.white))
        case .jumpsuit:
            ctx.fill(rr(14, 30, 22, 52, 6), with: .color(outfit))
            ctx.fill(rr(14, 52, 22, 2.5, 1), with: .color(accent))
        case .skirtSet:
            var skirt = Path()
            skirt.move(to: CGPoint(x: 15, y: 52)); skirt.addLine(to: CGPoint(x: 35, y: 52)); skirt.addLine(to: CGPoint(x: 40, y: 86))
            skirt.addQuadCurve(to: CGPoint(x: 37, y: 88), control: CGPoint(x: 40, y: 88)); skirt.addLine(to: CGPoint(x: 13, y: 88))
            skirt.addQuadCurve(to: CGPoint(x: 10, y: 86), control: CGPoint(x: 10, y: 88)); skirt.closeSubpath()
            ctx.fill(skirt, with: .color(outfit))
            ctx.fill(rr(15, 30, 20, 24, 6), with: .color(accent))
        }
        // Neck, hair behind, head, hair in front.
        ctx.fill(Path(CGRect(x: 22.5, y: 22, width: 5, height: 9)), with: .color(skin))
        if f.hairStyle == 1 { ctx.fill(rr(14.5, 4, 21, 22, 9), with: .color(hair)) }
        if f.hairStyle == 3 { ctx.fill(rr(14.5, 4.5, 21, 36, 9), with: .color(hair)) }
        ctx.fill(Path(ellipseIn: CGRect(x: 16, y: 6, width: 18, height: 18)), with: .color(skin))
        var cap = Path()
        cap.addArc(center: CGPoint(x: 25, y: 14), radius: 9.6, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        cap.closeSubpath()
        ctx.fill(cap, with: .color(hair))
        if f.hairStyle == 2 { ctx.fill(Path(ellipseIn: CGRect(x: 20, y: -1, width: 10, height: 10)), with: .color(hair)) }
        // Accessory: a bag on the swinging side, otherwise a scarf.
        if st > 0 {
            let bx = 37.5 + st * 4
            var handle = Path(); handle.addArc(center: CGPoint(x: bx + 4.5, y: 64), radius: 3.2, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            ctx.stroke(handle, with: .color(color(acc, 0.7)), lineWidth: 1.2)
            ctx.fill(rr(bx, 64, 9, 10, 2), with: .color(accent))
        } else {
            ctx.fill(rr(19, 28, 12, 4, 2), with: .color(accent))
        }
    }
}
#endif
