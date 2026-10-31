//  DogEarPeelCard.swift
//  DogEarPeelCard
//
//  A Halloween invitation whose bottom-right corner peels back as you drag it. The fold is real paper
//  geometry: the crease is the perpendicular bisector of the segment from the corner to your finger, the
//  card is clipped to the part still lying flat, and the lifted part is reflected across the crease and
//  drawn as the paper's back, shaded with a gradient that starts at the crease, with a soft shadow cast
//  on the card. Let go before 60% and the corner springs flat with a tiny bounce. Past 60% the crease
//  sweeps across the card, which flies away with a slight turn and reveals a note hidden under it. Reset
//  puts the card back. The fold maths comes from PeelCore (shared with PeelableSticker); the drag clamp,
//  threshold, spring-back, peel-off timeline and shading live in DogEarCore. Reduce Motion drops the
//  wobble and fades the card out instead of flying it away.

#if canImport(SwiftUI)
import SwiftUI
import DogEarCore

/// An invitation card with a peelable corner and a hidden note.
///
/// ```swift
/// DogEarPeelCard()
/// ```
public struct DogEarPeelCard: View {
    @State private var engine = DogEarEngine()
    @State private var isAnimating = true
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The note's cream paper, and the card's lilac back (so the flap reads as a different sheet than the note).
    static let paper = Color(red: 0.97, green: 0.94, blue: 0.86)
    static let backPaper = Color(red: 0.93, green: 0.89, blue: 0.96)
    static let overlayPadding = 260.0

    public init() {}

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            let f = m.frame
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                cardStack(m, f)
                VStack(spacing: 14) {
                    Text("Drag the bottom-right corner. Past 60% the card peels away.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.6)).multilineTextAlignment(.center)
                    Button("Reset") { engine.reset(at: Date()); isAnimating = true }
                        .buttonStyle(.borderedProminent).tint(.orange).controlSize(.large)
                        .disabled(m.phase == .idle)
                        .accessibilityHint("Puts the card back over the note")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: [Color(red: 0.09, green: 0.05, blue: 0.16), Color(red: 0.03, green: 0.02, blue: 0.07)],
                                       startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .onChange(of: timeline.date) { _, _ in if m.isIdle && !isDragging { isAnimating = false } }
            .onChange(of: m.announcementCount) { _, _ in
                if let text = m.announcement { AccessibilityNotification.Announcement(text).post() }
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.8), trigger: m.hapticCount)
        }
    }

    private func cardStack(_ m: DogEarModel, _ f: DogEarFrame) -> some View {
        ZStack {
            NoteView(content: m.content)
                .clipShape(RoundedRectangle(cornerRadius: DogEarLayout.cornerRadius, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(m.content.noteLabel)
                .accessibilityHidden(!m.noteRevealed)

            InvitationFront(content: m.content)
                .clipShape(PolygonShape(polygon: f.flat))
                .shadow(color: .black.opacity(DogEarShading.cardShadowOpacity), radius: DogEarShading.cardShadowRadius, y: DogEarShading.cardShadowY)
                .scaleEffect(f.cardScale)
                .opacity(f.cardOpacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(m.accessibilityLabel)
                .accessibilityValue(m.accessibilityValue)
                .accessibilityHint("Drag the bottom-right corner to peel the card away")
                .accessibilityAction(named: "Peel") { engine.peel(at: Date()); isAnimating = true }
                .accessibilityHidden(m.noteRevealed)
        }
        .frame(width: DogEarLayout.width, height: DogEarLayout.height)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { g in
            if !isDragging {
                isDragging = true
                guard engine.begin(at: Vec2(g.startLocation.x, g.startLocation.y), date: Date()) else { return }
            }
            engine.drag(to: Vec2(g.location.x, g.location.y), date: Date())
            isAnimating = true
        }.onEnded { _ in
            isDragging = false
            engine.end(at: Date())
            isAnimating = true
        })
        .overlay { FlapLayer(frame: f).allowsHitTesting(false) }
    }
}

/// The folded-back paper and the shadow it casts on the card. Drawn in a canvas bigger than the card so
/// the flap can swing out past the edges.
private struct FlapLayer: View {
    let frame: DogEarFrame

    var body: some View {
        let pad = DogEarPeelCard.overlayPadding
        Canvas { ctx, _ in
            guard !frame.flap.isEmpty else { return }
            func pt(_ v: Vec2) -> CGPoint { CGPoint(x: v.x + pad, y: v.y + pad) }
            func path(_ p: Polygon) -> Path {
                var path = Path()
                for (i, v) in p.points.enumerated() { i == 0 ? path.move(to: pt(v)) : path.addLine(to: pt(v)) }
                path.closeSubpath()
                return path
            }
            let s = frame.shading
            // Shadow of the flap on the card: the flap's outline pushed along the peel direction, blurred
            // and clipped to the part of the card still lying flat.
            if !frame.flat.isEmpty {
                var shadow = ctx
                shadow.clip(to: path(frame.flat))
                shadow.opacity = frame.flapOpacity
                shadow.drawLayer { layer in
                    layer.addFilter(.blur(radius: s.shadowBlur / 2))
                    layer.translateBy(x: frame.shadowDirection.x * s.shadowOffset, y: frame.shadowDirection.y * s.shadowOffset)
                    layer.fill(path(frame.flap), with: .color(.black.opacity(s.shadowOpacity)))
                }
            }
            var c = ctx
            c.opacity = frame.flapOpacity
            let flap = path(frame.flap)
            c.fill(flap, with: .color(DogEarPeelCard.backPaper))
            c.fill(flap, with: .linearGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(s.creaseDark), location: 0),
                    .init(color: .black.opacity(0), location: 0.5),
                    .init(color: .white.opacity(s.highlight), location: 1),
                ]),
                startPoint: pt(frame.gradientFrom), endPoint: pt(frame.gradientTo)))
            c.stroke(flap, with: .color(.black.opacity(0.12)), lineWidth: 0.5)
            if let a = frame.creaseFrom, let b = frame.creaseTo {
                var crease = Path(); crease.move(to: pt(a)); crease.addLine(to: pt(b))
                c.stroke(crease, with: .color(.black.opacity(0.18)), lineWidth: 0.75)
            }
        }
        .frame(width: DogEarLayout.width + 2 * pad, height: DogEarLayout.height + 2 * pad)
    }
}

/// A `PeelCore` polygon in card-local points as a shape (the view's rect is the card).
struct PolygonShape: Shape {
    var polygon: Polygon
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (i, v) in polygon.points.enumerated() {
            let p = CGPoint(x: rect.minX + v.x, y: rect.minY + v.y)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        if !polygon.points.isEmpty { path.closeSubpath() }
        return path
    }
}

/// The invitation front: a night sky, a moon, bats and a pumpkin, all drawn from shapes.
private struct InvitationFront: View {
    let content: DogEarContent

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(stops: [
                .init(color: Color(red: 0.09, green: 0.04, blue: 0.22), location: 0),
                .init(color: Color(red: 0.30, green: 0.08, blue: 0.40), location: 0.55),
                .init(color: Color(red: 0.96, green: 0.46, blue: 0.14), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                // Stars.
                for k in 0..<28 {
                    let x = Double((k * 7919) % 291) + 4, y = Double((k * 104729) % 190) + 6
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: k % 4 == 0 ? 2 : 1.2, height: k % 4 == 0 ? 2 : 1.2)),
                             with: .color(.white.opacity(0.35 + 0.1 * Double(k % 5))))
                }
                // Moon with a glow.
                let moon = CGPoint(x: 212, y: 232)
                ctx.fill(Path(ellipseIn: CGRect(x: moon.x - 74, y: moon.y - 74, width: 148, height: 148)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.6).opacity(0.35), .clear]),
                                               center: moon, startRadius: 30, endRadius: 74))
                ctx.fill(Path(ellipseIn: CGRect(x: moon.x - 42, y: moon.y - 42, width: 84, height: 84)),
                         with: .color(Color(red: 1.0, green: 0.93, blue: 0.68)))
                for (dx, dy, r) in [(-12.0, -10.0, 9.0), (14.0, 8.0, 6.0), (-4.0, 18.0, 4.5)] {
                    ctx.fill(Path(ellipseIn: CGRect(x: moon.x + dx - r, y: moon.y + dy - r, width: 2 * r, height: 2 * r)),
                             with: .color(Color(red: 0.93, green: 0.82, blue: 0.52).opacity(0.7)))
                }
                // Bats.
                for (x, y, s) in [(170.0, 190.0, 1.0), (250.0, 170.0, 0.7), (130.0, 245.0, 0.6)] {
                    ctx.fill(Self.bat(at: CGPoint(x: x, y: y), scale: s), with: .color(Color(red: 0.05, green: 0.02, blue: 0.1)))
                }
                // Hills.
                var hills = Path()
                hills.move(to: CGPoint(x: 0, y: size.height))
                for x in stride(from: 0.0, through: size.width, by: 6) {
                    hills.addLine(to: CGPoint(x: x, y: 330 + 14 * sin(x / 300 * 2 * .pi * 1.3 + 0.8)))
                }
                hills.addLine(to: CGPoint(x: size.width, y: size.height))
                hills.closeSubpath()
                ctx.fill(hills, with: .color(Color(red: 0.05, green: 0.02, blue: 0.09)))
                // Pumpkin.
                let p = CGPoint(x: 66, y: 336)
                for dx in [-17.0, 0.0, 17.0] {
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x + dx - 17 + (dx == 0 ? 2 : 0), y: p.y - 24, width: dx == 0 ? 30 : 34, height: 48)),
                             with: .color(Color(red: 0.98, green: 0.52, blue: 0.1).opacity(dx == 0 ? 1 : 0.92)))
                }
                var stem = Path(); stem.addRoundedRect(in: CGRect(x: p.x - 3, y: p.y - 34, width: 6, height: 12), cornerSize: CGSize(width: 2, height: 2))
                ctx.fill(stem, with: .color(Color(red: 0.25, green: 0.4, blue: 0.12)))
                for sx in [-10.0, 10.0] {
                    var eye = Path(); eye.move(to: CGPoint(x: p.x + sx - 5, y: p.y - 2)); eye.addLine(to: CGPoint(x: p.x + sx + 5, y: p.y - 2)); eye.addLine(to: CGPoint(x: p.x + sx, y: p.y - 11)); eye.closeSubpath()
                    ctx.fill(eye, with: .color(Color(red: 0.2, green: 0.07, blue: 0.02)))
                }
                var smile = Path(); smile.move(to: CGPoint(x: p.x - 13, y: p.y + 7))
                smile.addQuadCurve(to: CGPoint(x: p.x + 13, y: p.y + 7), control: CGPoint(x: p.x, y: p.y + 24))
                ctx.stroke(smile, with: .color(Color(red: 0.2, green: 0.07, blue: 0.02)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(content.kicker).font(.system(size: 12, weight: .bold)).tracking(3).foregroundStyle(Color(red: 1, green: 0.62, blue: 0.25))
                Text("Midnight\nMasquerade").font(.system(size: 36, weight: .bold, design: .serif)).foregroundStyle(.white).lineSpacing(0)
                Text(content.host).font(.system(size: 15, design: .serif).italic()).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.leading, 26).padding(.top, 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(content.when).font(.system(size: 17, weight: .bold, design: .serif)).foregroundStyle(Color(red: 1, green: 0.88, blue: 0.62))
                Text(content.line).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.7))
            }
            .padding(.leading, 26).padding(.top, 366)
        }
        .frame(width: DogEarLayout.width, height: DogEarLayout.height)
    }

    static func bat(at c: CGPoint, scale s: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - 4 * s))
        p.addQuadCurve(to: CGPoint(x: c.x - 22 * s, y: c.y - 6 * s), control: CGPoint(x: c.x - 10 * s, y: c.y - 14 * s))
        p.addQuadCurve(to: CGPoint(x: c.x - 14 * s, y: c.y + 2 * s), control: CGPoint(x: c.x - 18 * s, y: c.y - 2 * s))
        p.addQuadCurve(to: CGPoint(x: c.x - 6 * s, y: c.y + 4 * s), control: CGPoint(x: c.x - 10 * s, y: c.y + 2 * s))
        p.addLine(to: CGPoint(x: c.x, y: c.y + 8 * s))
        p.addLine(to: CGPoint(x: c.x + 6 * s, y: c.y + 4 * s))
        p.addQuadCurve(to: CGPoint(x: c.x + 14 * s, y: c.y + 2 * s), control: CGPoint(x: c.x + 10 * s, y: c.y + 2 * s))
        p.addQuadCurve(to: CGPoint(x: c.x + 22 * s, y: c.y - 6 * s), control: CGPoint(x: c.x + 18 * s, y: c.y - 2 * s))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - 4 * s), control: CGPoint(x: c.x + 10 * s, y: c.y - 14 * s))
        p.closeSubpath()
        return p
    }
}

/// The hidden note: cream paper, a wax seal and a few lines.
private struct NoteView: View {
    let content: DogEarContent

    var body: some View {
        ZStack(alignment: .topLeading) {
            DogEarPeelCard.paper
            VStack(alignment: .leading, spacing: 14) {
                Text(content.noteTitle).font(.system(size: 24, weight: .bold, design: .serif)).foregroundStyle(Color(red: 0.25, green: 0.1, blue: 0.35))
                Text(content.noteBody).font(.system(size: 17, design: .serif)).foregroundStyle(Color(red: 0.2, green: 0.15, blue: 0.25)).lineSpacing(4)
                Spacer(minLength: 0)
                HStack {
                    Text(content.noteFooter).font(.system(size: 14, weight: .semibold, design: .serif).italic()).foregroundStyle(Color(red: 0.55, green: 0.25, blue: 0.1))
                    Spacer()
                    Circle().fill(Color(red: 0.7, green: 0.12, blue: 0.14)).frame(width: 44, height: 44)
                        .overlay(Text("M").font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(.white.opacity(0.85)))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                }
            }
            .padding(26)
        }
        .frame(width: DogEarLayout.width, height: DogEarLayout.height)
    }
}

/// Owns the model and maps wall-clock dates (timeline frames and input) to model time.
final class DogEarEngine {
    private(set) var model = DogEarModel()
    private var origin: Date?

    private func seconds(_ date: Date) -> Double {
        if origin == nil { origin = date }
        return date.timeIntervalSince(origin!)
    }

    func frame(at date: Date, reduceMotion: Bool) -> DogEarModel {
        model.reduceMotion = reduceMotion
        model.advance(to: seconds(date))
        return model
    }

    func begin(at p: Vec2, date: Date) -> Bool { model.begin(at: p, time: seconds(date)) }
    func drag(to p: Vec2, date: Date) { model.drag(to: p, time: seconds(date)) }
    func end(at date: Date) { model.end(time: seconds(date)) }
    func peel(at date: Date) { model.peel(time: seconds(date)) }
    func reset(at date: Date) { model.reset(time: seconds(date)) }
}

#Preview {
    DogEarPeelCard()
}
#endif
