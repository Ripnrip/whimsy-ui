//  ColorFigureGumball.swift
//  ColorFigureGumball
//
//  A hand-inked isometric gumball machine with working buttons. Drag the figure to turn it all the way
//  round (it coasts, then settles onto a quarter turn). Insert a coin, turn the crank once, and a gumball
//  drops down the chute and rolls out of the flap. The See-through switch turns the case into a faint
//  outline and shows the works: the coin mechanism, the pocket wheel, the crank shaft, the chute and the
//  flap spring. Labels name those parts and light them while they work. Swatches change the body colour
//  and the wobble slider changes how shaky the ink is.
//
//  Everything is drawn from generated shapes: the pure-Swift core in ColorFigureCore builds the 3D model,
//  projects it, sorts it painter-style, inks it, and runs the mechanism; this file only paints the result.
//  Inspired by Colorfigures by April Zhu (MIT): the idea of a drag-to-turn, see-through, labelled figure.
//  No code was taken from it (see the README for its licence notice).

#if canImport(SwiftUI)
import SwiftUI
import ColorFigureCore

/// A gumball machine you can turn, look inside, and use.
///
/// ```swift
/// ColorFigureGumball()
/// ```
public struct ColorFigureGumball: View {
    @State private var engine = GumballEngine()
    @State private var isAnimating = true
    @State private var seeThrough = false
    @State private var labelsOn = true
    @State private var swatch: GumballSwatch = .tomato
    @State private var wobble = 0.5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let paper = Color(red: 0.965, green: 0.933, blue: 0.863)
    static let ink = Color(red: 0.169, green: 0.129, blue: 0.094)
    /// What the canvas shows, in figure units: wide enough for two label columns, tall enough for the cap and the base.
    static let viewWidth = 160.0
    static let viewHeight = 124.0
    static let viewTop = -97.0

    public init() {}

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion, seeThrough: seeThrough, labels: labelsOn, swatch: swatch, wobble: wobble)
            VStack(spacing: 12) {
                figure(m)
                    .frame(maxWidth: 520)
                Text(m.notice ?? m.statusText)
                    .font(.system(.headline, design: .serif).italic())
                    .foregroundStyle(Self.ink.opacity(m.notice == nil ? 0.8 : 1))
                    .frame(height: 24)
                    .accessibilityHidden(true)
                controls(m)
                    .frame(maxWidth: 520)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.paper.ignoresSafeArea())
            .onChange(of: timeline.date) { _, _ in if m.isIdle { isAnimating = false } }
            .onChange(of: m.announcementCount) { _, _ in
                if let text = m.announcement { AccessibilityNotification.Announcement(text).post() }
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.8), trigger: engine.hapticCount)
        }
    }

    // MARK: figure

    private func figure(_ m: GumballModel) -> some View {
        GeometryReader { geo in
            let g = Mapping(size: geo.size)
            Canvas { ctx, _ in
                let fr = m.frame()
                Self.draw(fr, labels: m.labels(), xr: m.xr, mapping: g, in: &ctx)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    engine.pointer(at: g.unmap(v.location), x: v.location.x, time: v.time)
                    isAnimating = true
                }
                .onEnded { _ in
                    engine.release()
                    isAnimating = true
                })
        }
        .aspectRatio(Self.viewWidth / Self.viewHeight, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gumball machine")
        .accessibilityValue(m.accessibilityValue)
        .accessibilityHint("Drag to turn it round. Insert a coin, then turn the crank")
        .accessibilityAction(named: "Insert coin") { engine.insertCoin(); isAnimating = true }
        .accessibilityAction(named: "Turn crank") { engine.turnCrank(); isAnimating = true }
        .accessibilityAction(named: "Toggle see-through") { seeThrough.toggle(); isAnimating = true }
    }

    /// Figure units to points and back: the figure's origin sits at the horizontal centre, `viewTop` at the top edge.
    struct Mapping {
        var size: CGSize
        var scale: Double { min(size.width / ColorFigureGumball.viewWidth, size.height / ColorFigureGumball.viewHeight) }
        func point(_ v: Vec2) -> CGPoint {
            CGPoint(x: size.width / 2 + v.x * scale, y: (v.y - ColorFigureGumball.viewTop) * scale + (size.height - ColorFigureGumball.viewHeight * scale) / 2)
        }
        func unmap(_ p: CGPoint) -> Vec2 {
            Vec2((p.x - size.width / 2) / scale, (p.y - (size.height - ColorFigureGumball.viewHeight * scale) / 2) / scale + ColorFigureGumball.viewTop)
        }
    }

    static func color(_ c: FigureColor, _ alpha: Double = 1) -> Color {
        Color(red: c.r, green: c.g, blue: c.b).opacity(alpha)
    }

    static func draw(_ frame: FigureFrame, labels: [PlacedLabel], xr: Double, mapping g: Mapping, in ctx: inout GraphicsContext) {
        let s = g.scale
        for item in frame.items where item.alpha > 0.003 {
            switch item.kind {
            case .fill:
                var p = Path()
                for (i, v) in item.points.enumerated() { i == 0 ? p.move(to: g.point(v)) : p.addLine(to: g.point(v)) }
                p.closeSubpath()
                ctx.fill(p, with: .color(color(item.color, item.alpha)))
            case .stroke:
                var p = Path()
                for (i, v) in item.points.enumerated() { i == 0 ? p.move(to: g.point(v)) : p.addLine(to: g.point(v)) }
                if item.closed { p.closeSubpath() }
                ctx.stroke(p, with: .color(color(item.color, item.alpha)),
                           style: StrokeStyle(lineWidth: max(0.5, item.width * s), lineCap: .round, lineJoin: .round))
            case .hatch:
                var p = Path()
                var i = 0
                while i + 1 < item.points.count {
                    p.move(to: g.point(item.points[i])); p.addLine(to: g.point(item.points[i + 1])); i += 2
                }
                ctx.stroke(p, with: .color(color(item.color, item.alpha)), style: StrokeStyle(lineWidth: max(0.4, item.width * s), lineCap: .round))
            case .disc:
                let c = g.point(item.points[0]), r = item.radius * s
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color(item.color, item.alpha)))
            }
        }
        // Labels: a leader line from the part, then a pill that turns yellow while the part works.
        for l in labels {
            let a = g.point(l.anchor)
            let origin = g.point(Vec2(l.centre.x - l.width / 2, l.centre.y - l.height / 2))
            let pill = CGRect(x: origin.x, y: origin.y, width: l.width * s, height: l.height * s)
            let edge = CGPoint(x: l.side == .left ? pill.maxX : pill.minX, y: pill.midY)
            var line = Path(); line.move(to: a); line.addLine(to: edge)
            ctx.stroke(line, with: .color(ink.opacity(0.7 * xr)), style: StrokeStyle(lineWidth: max(0.8, 0.35 * s), lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: a.x - 0.9 * s, y: a.y - 0.9 * s, width: 1.8 * s, height: 1.8 * s)), with: .color(ink.opacity(xr)))
            let shape = Path(roundedRect: pill, cornerRadius: pill.height / 2)
            ctx.fill(shape, with: .color((l.active ? Color(red: 1, green: 0.9, blue: 0.5) : Color(red: 1, green: 0.98, blue: 0.9)).opacity(xr)))
            ctx.stroke(shape, with: .color(ink.opacity(xr)), lineWidth: l.active ? max(1.2, 0.6 * s) : max(0.8, 0.4 * s))
            ctx.draw(Text(l.text).font(.system(size: max(8, 4.9 * s), weight: l.active ? .bold : .regular, design: .serif)).foregroundStyle(ink.opacity(xr)),
                     at: CGPoint(x: pill.midX, y: pill.midY))
        }
    }

    // MARK: controls

    private func controls(_ m: GumballModel) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button { engine.insertCoin(); isAnimating = true } label: { Label("Insert coin", systemImage: "circle.circle.fill") }
                    .buttonStyle(.borderedProminent).tint(Color(red: 0.89, green: 0.34, blue: 0.24)).controlSize(.large)
                    .disabled(m.mech.phase != .ready)
                    .accessibilityHint("Drops a coin into the slot and unlocks the crank")
                Button { engine.turnCrank(); isAnimating = true } label: { Label("Turn crank", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered).tint(Self.ink).controlSize(.large)
                    .accessibilityHint("Turns the crank one full turn, if a coin is in")
            }
            HStack(spacing: 20) {
                Toggle("See-through", isOn: $seeThrough)
                Toggle("Labels", isOn: $labelsOn).disabled(!seeThrough)
            }
            .toggleStyle(.switch)
            .font(.system(.subheadline, design: .serif))
            .foregroundStyle(Self.ink)
            .onChange(of: seeThrough) { _, _ in isAnimating = true }
            .onChange(of: labelsOn) { _, _ in isAnimating = true }
            HStack(spacing: 14) {
                ForEach(GumballSwatch.allCases, id: \.self) { s in
                    Button { swatch = s; isAnimating = true } label: {
                        Circle().fill(Self.color(FigureColor(hex: s.base)))
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Self.ink, lineWidth: s == swatch ? 3 : 1))
                            .padding(3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(s.title)
                    .accessibilityAddTraits(s == swatch ? .isSelected : [])
                }
            }
            HStack(spacing: 10) {
                Text("Wobble").font(.system(.subheadline, design: .serif)).foregroundStyle(Self.ink)
                Slider(value: $wobble, in: 0...1) { Text("Wobble") }
                    .tint(Self.ink)
                    .onChange(of: wobble) { _, _ in isAnimating = true }
                    .accessibilityValue("\(Int(wobble * 100)) percent")
            }
        }
    }
}

/// Owns the model, maps timeline dates to elapsed seconds, and routes pointer input to the crank or the turntable.
final class GumballEngine {
    private(set) var model = GumballModel()
    private(set) var hapticCount = 0
    private(set) var isPressing = false
    private var last: Date?
    private var dragX = 0.0
    private var dragTime: Date?
    private var turning = false

    func frame(at date: Date, reduceMotion: Bool, seeThrough: Bool, labels: Bool, swatch: GumballSwatch, wobble: Double) -> GumballModel {
        if model.reduceMotion != reduceMotion { model.reduceMotion = reduceMotion }
        if model.seeThrough != seeThrough { model.setSeeThrough(seeThrough) }
        model.labelsOn = labels
        model.swatch = swatch
        model.wobble = wobble
        let dt = last.map { min(0.1, max(0, date.timeIntervalSince($0))) } ?? 0
        last = date
        model.advance(by: dt)
        hapticCount += model.takeHaptics().count
        return model
    }

    /// Pointer at figure-space `p` (and the raw horizontal position `x` in points). The first call of a gesture decides what is grabbed.
    func pointer(at p: Vec2, x: Double, time: Date) {
        if !isPressing {
            isPressing = true
            if model.crankPress(at: p) {
                turning = false
            } else {
                turning = true
                model.turntable.beginDrag()
                dragX = x
                dragTime = time
            }
            return
        }
        if turning {
            let dt = dragTime.map { time.timeIntervalSince($0) } ?? 0
            model.turntable.drag(by: x - dragX, dt: dt)
            dragX = x
            dragTime = time
        } else {
            model.crankMove(to: p)
        }
    }

    func release() {
        if turning { model.turntable.endDrag() } else { model.crankRelease() }
        isPressing = false
        turning = false
    }

    func insertCoin() { model.insertCoin() }
    func turnCrank() { model.turnCrank() }
}

#Preview {
    ColorFigureGumball()
}
#endif
