//  HoloFoilCard.swift
//  HoloFoilCard
//
//  A holographic trading card you drag to tilt. The tilt (soft-clamped to ±15° on both axes) drives
//  rotation3DEffect and a Metal colorEffect shader that sweeps a rainbow diffraction band across the
//  card, slides a soft glare the other way, and lights sparkles only inside their own angle windows.
//  Let go and it springs back flat with a little wobble. A light haptic ticks each time the band
//  crosses the card's centre. Tilt mapping, spring, band, sparkle gating, crossings and the colour
//  math (mirrored from HoloFoil.metal) live in HoloCore.

#if canImport(SwiftUI)
import SwiftUI
import HoloCore

/// A holo foil card that tilts under your finger.
///
/// ```swift
/// HoloFoilCard()
/// HoloFoilCard(title: "COMET FOX", hp: 90)
/// ```
public struct HoloFoilCard: View {
    @State private var engine = HoloEngine()
    @State private var isAnimating = false
    @State private var crossings = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let title: String
    private let hp: Int

    public static let cardSize = CGSize(width: 300, height: 420)
    public static let cornerRadius: CGFloat = 22
    /// rotation3DEffect perspective (eye distance ≈ 420 / 0.5 = 840 pt).
    public static let perspective: CGFloat = 0.5
    static let yawStep = 5.0

    public init(title: String = "NOVA DRAKE", hp: Int = 120) {
        self.title = title
        self.hp = hp
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            let tilt = m.displayTilt
            let n = HoloTilt.normalized(tilt)
            VStack(spacing: 30) {
                HoloCardFace(title: title, hp: hp)
                    .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                    .colorEffect(ShaderLibrary.bundle(.module).holoFoil(
                        .float2(CGPoint(x: Self.cardSize.width, y: Self.cardSize.height)),
                        .float2(CGPoint(x: n.x, y: n.y)),
                        .float(1)))
                    .shadow(color: .black.opacity(0.28), radius: 22,
                            x: reduceMotion ? 0 : -n.x * 8, y: 14 + (reduceMotion ? 0 : n.y * 6))
                    // Pitch then yaw, both about the card centre. Reduce Motion keeps the card flat;
                    // dragging still sweeps the foil.
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : tilt.y), axis: (x: 1, y: 0, z: 0), perspective: Self.perspective)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : tilt.x), axis: (x: 0, y: 1, z: 0), perspective: Self.perspective)
                    .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                engine.model.dragChanged(translation: Vec2(Double(v.translation.width), Double(v.translation.height)))
                                isAnimating = true
                            }
                            .onEnded { _ in
                                engine.model.dragEnded()
                                isAnimating = true
                            }
                    )
                    .accessibilityElement()
                    .accessibilityLabel("\(title), holographic card")
                    .accessibilityValue(Self.bandDescription(m.bandPosition))
                    .accessibilityHint("Drag to tilt the card. Swipe up or down to sweep the foil.")
                    .accessibilityAdjustableAction { direction in
                        let yaw = engine.model.target.x
                        switch direction {
                        case .increment: engine.model.setHeldYaw(yaw + Self.yawStep)
                        case .decrement: engine.model.setHeldYaw(yaw - Self.yawStep)
                        @unknown default: break
                        }
                        isAnimating = true
                    }
                    .accessibilityAction(named: "Flatten") {
                        engine.model.setHeldYaw(0)
                        isAnimating = true
                    }

                Text(reduceMotion ? "Drag across the card to sweep the foil" : "Drag the card to tilt it")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color(white: 0.72))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RadialGradient(colors: [Color(red: 0.16, green: 0.15, blue: 0.24), Color(red: 0.05, green: 0.05, blue: 0.09)],
                               center: .center, startRadius: 40, endRadius: 520)
                .ignoresSafeArea()
            )
            .onChange(of: m.crossings) { _, c in crossings = c }
            .onChange(of: m.isIdle) { _, idle in if idle { isAnimating = false; engine.pause() } }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: crossings)
    }

    static func bandDescription(_ band: Double) -> String {
        if abs(band) <= CenterCrossingDetector.hysteresis { return "Foil band centred" }
        return band < 0 ? "Foil band left of centre" : "Foil band right of centre"
    }
}

/// Steps the model from the timeline; owns no UI.
final class HoloEngine {
    var model = HoloModel()
    private var lastDate: Date?

    func frame(at date: Date, reduceMotion: Bool) -> HoloModel {
        model.config.reduceMotion = reduceMotion
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        model.step(dt)
        return model
    }

    func pause() { lastDate = nil }
}

/// The printed card under the foil: generated gradients, an eight-point star and orbit rings.
/// Laid out in absolute card points so the web port can mirror it exactly.
struct HoloCardFace: View {
    let title: String
    let hp: Int

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let bounds = CGRect(origin: .zero, size: size)
            ctx.fill(Path(bounds), with: .linearGradient(
                Gradient(colors: [Color(red: 0.10, green: 0.08, blue: 0.26), Color(red: 0.30, green: 0.14, blue: 0.48)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(Path(roundedRect: bounds.insetBy(dx: 10, dy: 10), cornerRadius: 14),
                       with: .color(.white.opacity(0.55)), lineWidth: 3)

            // Header.
            ctx.draw(Text(title).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundColor(.white),
                     at: CGPoint(x: 24, y: 38), anchor: .leading)
            ctx.draw(Text("HP \(hp)").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.9)),
                     at: CGPoint(x: w - 24, y: 38), anchor: .trailing)

            // Art panel.
            let art = CGRect(x: 22, y: 62, width: w - 44, height: 196)
            let artPath = Path(roundedRect: art, cornerRadius: 12)
            ctx.fill(artPath, with: .radialGradient(
                Gradient(colors: [Color(red: 0.35, green: 0.85, blue: 0.95), Color(red: 0.08, green: 0.12, blue: 0.36)]),
                center: CGPoint(x: art.midX, y: art.midY), startRadius: 0, endRadius: 150))
            var inArt = ctx
            inArt.clip(to: artPath)
            let c = CGPoint(x: art.midX, y: art.midY)
            for (rx, ry, o) in [(118.0, 42.0, 0.35), (92.0, 70.0, 0.25), (60.0, 88.0, 0.18)] {
                inArt.stroke(Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: 2 * rx, height: 2 * ry)),
                             with: .color(.white.opacity(o)), lineWidth: 1.5)
            }
            inArt.fill(Self.star(center: c, outer: 64, inner: 26, points: 8), with: .linearGradient(
                Gradient(colors: [.white, Color(red: 1.0, green: 0.84, blue: 0.45)]),
                startPoint: CGPoint(x: c.x, y: c.y - 64), endPoint: CGPoint(x: c.x, y: c.y + 64)))
            ctx.stroke(artPath, with: .color(.white.opacity(0.6)), lineWidth: 2)

            // Moves.
            for (i, (name, dmg)) in [("Prism Burst", "60"), ("Starfall", "90")].enumerated() {
                let y = 292 + Double(i) * 46
                ctx.draw(Text("✦  " + name).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundColor(.white),
                         at: CGPoint(x: 28, y: y), anchor: .leading)
                ctx.draw(Text(dmg).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(.white),
                         at: CGPoint(x: w - 28, y: y), anchor: .trailing)
                var rule = Path()
                rule.move(to: CGPoint(x: 28, y: y + 23)); rule.addLine(to: CGPoint(x: w - 28, y: y + 23))
                ctx.stroke(rule, with: .color(.white.opacity(0.2)), lineWidth: 1)
            }
            ctx.draw(Text("Holo Rare · 027/150").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.7)),
                     at: CGPoint(x: 24, y: h - 30), anchor: .leading)
            ctx.draw(Text("★★★").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.45)),
                     at: CGPoint(x: w - 24, y: h - 30), anchor: .trailing)
        }
        .accessibilityHidden(true)
    }

    static func star(center c: CGPoint, outer: Double, inner: Double, points: Int) -> Path {
        var p = Path()
        for i in 0..<(points * 2) {
            let r = i.isMultiple(of: 2) ? outer : inner
            let a = Double(i) * .pi / Double(points) - .pi / 2
            let q = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }
}

#Preview {
    HoloFoilCard()
        .preferredColorScheme(.dark)
}
#endif
