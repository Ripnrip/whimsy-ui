//  PeelableSticker.swift
//  PeelableSticker
//
//  An emoji sticker on a card. Drag from a corner and it peels back along your finger: the
//  crease is the perpendicular bisector of corner → finger, the lifted part is reflected over it
//  as a flap showing the sticker's lighter back, with a soft shadow along the fold. Let go before
//  halfway and it springs back flat; past halfway it pops off and tumbles away. Yank fast and it
//  tears in two, leaving a faint glue patch. No Metal: just polygons, clips and gradients in a
//  Canvas. Geometry, release rules, tearing and tumble physics live in PeelCore.

#if canImport(SwiftUI)
import SwiftUI
import PeelCore

/// A peelable emoji sticker on a card.
///
/// ```swift
/// PeelableSticker()
/// PeelableSticker(prompt: "Peel me")
/// ```
public struct PeelableSticker: View {
    @State private var engine = PeelEngine()
    @State private var isAnimating = false
    @State private var grabs = 0
    @State private var pops = 0
    @State private var tears = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let prompt: String

    public init(prompt: String = "Peel from a corner") {
        self.prompt = prompt
    }

    public var body: some View {
        GeometryReader { proxy in
            let center = Vec2(Double(proxy.size.width) / 2, Double(proxy.size.height) * 0.46)
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                let m = engine.frame(at: timeline.date, center: center, reduceMotion: reduceMotion)
                ZStack {
                    PeelBackdrop()
                    Canvas { ctx, size in
                        PeelRenderer.draw(m, in: &ctx, size: size)
                    }
                    .accessibilityHidden(true)
                    caption(m, size: proxy.size)
                    accessibleSticker(m)
                }
                .onChange(of: m.grabs) { _, n in grabs = n }
                .onChange(of: m.pops) { _, n in pops = n }
                .onChange(of: m.tears) { _, n in tears = n }
                .onChange(of: m.isSettled) { _, idle in if idle { isAnimating = false; engine.pause() } }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = Vec2(Double(v.location.x), Double(v.location.y))
                        let t = v.time.timeIntervalSinceReferenceDate
                        if engine.isTouching {
                            engine.model.move(to: p, time: t)
                        } else {
                            engine.isTouching = true
                            if engine.model.begin(at: p, time: t) { isAnimating = true }
                        }
                    }
                    .onEnded { v in
                        engine.isTouching = false
                        engine.model.end(time: v.time.timeIntervalSinceReferenceDate)
                        isAnimating = true
                    }
            )
        }
        .sensoryFeedback(.selection, trigger: grabs)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.9), trigger: pops)
        .sensoryFeedback(.impact(weight: .heavy), trigger: tears)
    }

    private func caption(_ m: PeelModel, size: CGSize) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(prompt)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .foregroundStyle(Color(white: 0.22))
            Text("Past halfway it pops off. Yank fast and it tears.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color(white: 0.45))
        }
        .multilineTextAlignment(.center)
        .padding(.bottom, max(40, size.height * 0.12))
        .accessibilityHidden(true)
    }

    private func accessibleSticker(_ m: PeelModel) -> some View {
        let s = CGFloat(PeelModel.size)
        let fraction = m.peel?.fraction ?? 1
        return Color.clear
            .frame(width: s, height: s)
            .position(x: CGFloat(m.center.x), y: CGFloat(m.center.y))
            .accessibilityElement()
            .accessibilityLabel("\(m.design.name) sticker")
            .accessibilityValue(m.peel == nil ? "Peeled off" : "\(Int((fraction * 100).rounded())) percent peeled")
            .accessibilityHint("Drag from a corner to peel it.")
            .accessibilityAction(named: "Peel off") {
                engine.model.popNow()
                isAnimating = true
            }
    }
}

/// Steps the model from the timeline; owns no UI.
final class PeelEngine {
    var model = PeelModel(center: Vec2(200, 380))
    var isTouching = false
    private var lastDate: Date?

    func frame(at date: Date, center: Vec2, reduceMotion: Bool) -> PeelModel {
        if model.physics.reduceMotion != reduceMotion { model.physics = TumblePhysics(reduceMotion: reduceMotion) }
        model.setCenter(center)
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        model.step(dt)
        return model
    }

    func pause() { lastDate = nil }
}

/// The card the sticker lives on.
private struct PeelBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.93, green: 0.92, blue: 0.97), Color(red: 0.86, green: 0.89, blue: 0.96)],
                           startPoint: .top, endPoint: .bottom)
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Color(white: 0.995))
                .shadow(color: .black.opacity(0.08), radius: 24, y: 10)
                .padding(.horizontal, 22)
                .padding(.vertical, 90)
        }
        .ignoresSafeArea()
    }
}

/// Draws the sticker, its flap and shadows, the glue residue and any flying pieces.
enum PeelRenderer {
    static func draw(_ m: PeelModel, in ctx: inout GraphicsContext, size: CGSize) {
        let design = m.design
        let footprint = path(m.shape)

        // Glue residue left by a tear.
        if m.residueOpacity > 0 {
            ctx.fill(footprint, with: .color(Color(hue: design.hue, saturation: 0.18, brightness: 0.86)
                .opacity(m.residueOpacity)))
        }

        if let peel = m.peel {
            var layer = ctx
            let a = m.appear
            if a < 1 {
                layer.translateBy(x: CGFloat(m.center.x), y: CGFloat(m.center.y))
                layer.scaleBy(x: CGFloat(a), y: CGFloat(a))
                layer.translateBy(x: CGFloat(-m.center.x), y: CGFloat(-m.center.y))
                layer.opacity = min(1, a * 1.6)
            }
            drawSticker(peel, art: m.center, design: design, in: &layer, castShadow: true)
        }

        for piece in m.pieces {
            var layer = ctx
            let b = piece.body
            layer.opacity = m.opacity(of: piece)
            layer.translateBy(x: CGFloat(b.position.x), y: CGFloat(b.position.y))
            layer.rotate(by: .radians(b.angle))
            let s = CGFloat(m.scale(of: piece))
            layer.scaleBy(x: s, y: s)
            drawSticker(piece.peel, art: piece.artOffset, design: design, in: &layer, castShadow: true)
        }
    }

    /// One sticker (or torn piece) whose artwork is centred on `art`.
    static func drawSticker(_ peel: PeelState, art: Vec2, design: StickerDesign,
                            in ctx: inout GraphicsContext, castShadow: Bool) {
        let flat = path(peel.flat)
        let flap = path(peel.flap)
        let lift = peel.fraction

        // Resting shadow under the flat part, kept tight: it's stuck down.
        if castShadow {
            var shadow = ctx
            shadow.addFilter(.shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1))
            shadow.fill(flat, with: .color(.white))
        }

        // Front face, clipped to what's still flat.
        var front = ctx
        front.clip(to: flat)
        drawFace(art: art, design: design, in: &front)

        guard let fold = peel.fold, !peel.flap.isEmpty else { return }
        let reach = peel.flap.points.map { fold.signedDistance($0) }.max() ?? 0
        let n = fold.normal
        let creaseMid = peel.crease.map { Vec2.lerp($0.0, $0.1, 0.5) } ?? fold.point

        // Soft shadow on the card where the sticker lifted, darkest at the crease.
        if !peel.lifted.isEmpty {
            var card = ctx
            card.clip(to: path(peel.lifted))
            let w = min(26, max(6, reach * 0.35))
            card.fill(path(peel.lifted), with: .linearGradient(
                Gradient(colors: [.black.opacity(0.16), .black.opacity(0)]),
                startPoint: point(creaseMid), endPoint: point(creaseMid - n * w)))
        }

        // Drop shadow of the flap onto the sticker and card beyond.
        var drop = ctx
        drop.addFilter(.shadow(color: .black.opacity(0.18 + 0.1 * lift), radius: 6 + 8 * lift,
                               x: CGFloat(n.x * (2 + 6 * lift)), y: CGFloat(n.y * (2 + 6 * lift) + 3)))
        drop.fill(flap, with: .color(.white))

        // The flap: the sticker's back, lighter at the tip, shaded where it curls at the crease.
        let tip = creaseMid + n * max(reach, 1)
        ctx.fill(flap, with: .linearGradient(
            Gradient(stops: [
                .init(color: Color(white: 0.80), location: 0),
                .init(color: Color(white: 0.97), location: 0.22),
                .init(color: Color(white: 0.99), location: 0.55),
                .init(color: Color(white: 0.91), location: 1),
            ]),
            startPoint: point(creaseMid), endPoint: point(tip)))
        // A faint tint of the backing paper.
        ctx.fill(flap, with: .color(Color(hue: design.hue, saturation: 0.25, brightness: 1).opacity(0.08)))

        // Crease highlight.
        if let c = peel.crease {
            var line = Path()
            line.move(to: point(c.0 + n * 0.8))
            line.addLine(to: point(c.1 + n * 0.8))
            ctx.stroke(line, with: .color(.white.opacity(0.9)), lineWidth: 1.2)
        }
    }

    /// The printed face: a white die-cut border around a tinted panel with the emoji.
    static func drawFace(art: Vec2, design: StickerDesign, in ctx: inout GraphicsContext) {
        let s = PeelModel.size
        let outer = path(Polygon.roundedRect(center: art, width: s, height: s, cornerRadius: PeelModel.cornerRadius, segments: 10))
        ctx.fill(outer, with: .color(.white))
        let inset = 11.0
        let inner = path(Polygon.roundedRect(center: art, width: s - 2 * inset, height: s - 2 * inset,
                                             cornerRadius: PeelModel.cornerRadius - inset, segments: 10))
        let top = Color(hue: design.hue, saturation: 0.38, brightness: 1)
        let bottom = Color(hue: (design.hue + 0.06).truncatingRemainder(dividingBy: 1), saturation: 0.62, brightness: 0.93)
        ctx.fill(inner, with: .linearGradient(Gradient(colors: [top, bottom]),
                                              startPoint: point(art + Vec2(-s / 2, -s / 2)),
                                              endPoint: point(art + Vec2(s / 2, s / 2))))
        // Glossy sheen.
        ctx.fill(inner, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.35), .white.opacity(0)]),
            startPoint: point(art + Vec2(0, -s / 2)), endPoint: point(art + Vec2(0, -s * 0.05))))
        let emoji = ctx.resolve(Text(design.emoji).font(.system(size: 92)))
        ctx.draw(emoji, at: point(art + Vec2(0, 4)), anchor: .center)
    }

    static func path(_ poly: Polygon) -> Path {
        var p = Path()
        guard let first = poly.points.first, poly.points.count >= 3 else { return p }
        p.move(to: point(first))
        for v in poly.points.dropFirst() { p.addLine(to: point(v)) }
        p.closeSubpath()
        return p
    }

    static func point(_ v: Vec2) -> CGPoint { CGPoint(x: v.x, y: v.y) }
}

#Preview {
    PeelableSticker()
}
#endif
