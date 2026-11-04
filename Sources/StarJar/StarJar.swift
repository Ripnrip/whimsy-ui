//
//  StarJar.swift
//  StarJar
//
//  A glass jar of about forty stars that sleeps until you tap it. Asleep, the stars lie in a dim heap at the
//  bottom. Tap the jar and they brighten, twinkle each on its own rhythm and float up to drift like fireflies;
//  drag a finger inside to stir them, and a soft haptic tick lands when one brushes the glass. While the jar
//  is awake the surrounding ScrollView stops scrolling (add `.starJarScrollLock()` to it). Tap outside the
//  jar, or the Done chip, and the stars settle back down and dim over about 1.5 s before scrolling returns.
//  Reduce Motion: no wander or stirring, and a steady glow instead of twinkling.
//  Jar geometry and containment, the seeded star simulation, twinkle, the phase machine, the scroll-lock
//  flag, the stir field and rate-limited brush events all live in StarJarCore.

#if canImport(SwiftUI)
import SwiftUI
import StarJarCore

// MARK: - Scroll lock plumbing

/// Carries "some StarJar inside wants scrolling off" up to the enclosing scroll view.
public struct StarJarScrollLockKey: PreferenceKey {
    public static let defaultValue = false
    public static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct StarJarScrollLockModifier: ViewModifier {
    @State private var locked = false
    func body(content: Content) -> some View {
        content
            .scrollDisabled(locked)
            .onPreferenceChange(StarJarScrollLockKey.self) { value in locked = value }
    }
}

public extension View {
    /// Put this on the ScrollView that contains a StarJar: scrolling turns off while the jar is awake.
    func starJarScrollLock() -> some View { modifier(StarJarScrollLockModifier()) }
}

// MARK: - The jar

/// A jar of stars you wake with a tap.
///
/// ```swift
/// ScrollView {
///     StarJar()
/// }
/// .starJarScrollLock()
///
/// StarJar(starCount: 60, tint: .mint, isEngaged: $jarAwake)
/// ```
public struct StarJar: View {
    private let starCount: Int
    private let tint: Color
    private let external: Binding<Bool>?

    @State private var model: StarJarModel
    @State private var lastDate: Date? = nil
    @State private var stirring = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() { self.init(starCount: StarJarModel.defaultStars, tint: Color(red: 1.0, green: 0.86, blue: 0.45), isEngaged: nil) }

    public init(starCount: Int = StarJarModel.defaultStars, tint: Color = Color(red: 1.0, green: 0.86, blue: 0.45), isEngaged: Binding<Bool>? = nil) {
        self.starCount = StarJarModel.clampedCount(starCount)
        self.tint = tint
        self.external = isEngaged
        _model = State(initialValue: StarJarModel(starCount: starCount))
    }

    private static let hintHeight = 32.0
    private var size: CGSize { CGSize(width: StarJarGeometry.width, height: StarJarGeometry.height + Self.hintHeight) }

    public var body: some View {
        TimelineView(.animation(paused: model.isAtRest)) { timeline in
            Canvas { ctx, _ in
                drawJarBack(&ctx)
                drawStars(&ctx)
                drawJarFront(&ctx)
                if model.isEngaged { drawDone(&ctx) }
                drawHint(&ctx)
            }
            .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        // Asleep, a plain tap (so a drag on the jar still scrolls the page); awake, a drag that stirs or taps.
        .onTapGesture { p in if !model.isEngaged { tap(p) } }
        .gesture(dragGesture, including: model.isEngaged ? .all : .none)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: model.brushes)
        .preference(key: StarJarScrollLockKey.self, value: model.isScrollLocked)
        .onAppear { model.setReduceMotion(reduceMotion); if external?.wrappedValue == true { send(model.setEngaged(true)) } }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .onChange(of: external?.wrappedValue) { _, on in
            guard let on, on != model.isEngaged else { return }
            send(model.setEngaged(on))
        }
        .accessibilityElement()
        .accessibilityLabel("Star jar")
        .accessibilityValue(model.isEngaged ? "Awake" : "Asleep")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { send(model.setEngaged(!model.isEngaged)) }
    }

    // MARK: input

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                let moved = hypot(g.translation.width, g.translation.height)
                if !stirring && model.isEngaged && moved > 6 && StarJarGeometry.contains(g.startLocation.x, g.startLocation.y) {
                    stirring = true
                    model.touchBegan(x: g.startLocation.x, y: g.startLocation.y)
                }
                if stirring { model.touchMoved(x: g.location.x, y: g.location.y, at: g.time.timeIntervalSinceReferenceDate) }
            }
            .onEnded { g in
                if stirring { model.touchEnded() }
                else if hypot(g.translation.width, g.translation.height) <= 6 { tap(g.location) }
                stirring = false
            }
    }

    private func tap(_ p: CGPoint) { send(model.tap(x: p.x, y: p.y)) }

    private func send(_ events: [StarJarEvent]) {
        if model.isEngaged { lastDate = nil }
        for e in events {
            switch e {
            case .waking: external?.wrappedValue = true
            case .settling: external?.wrappedValue = false
            default: break
            }
        }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        send(model.step(now.timeIntervalSince(last)))
    }

    // MARK: drawing

    private var jarPath: Path {
        let b = StarJarGeometry.body, n = StarJarGeometry.neck, w = StarJarGeometry.wall
        var p = Path(roundedRect: CGRect(x: b.x - w, y: b.y - w, width: b.width + 2 * w, height: b.height + 2 * w),
                     cornerRadius: StarJarGeometry.bodyRadius + w, style: .continuous)
        p.addPath(Path(roundedRect: CGRect(x: n.x - w, y: n.y - w, width: n.width + 2 * w, height: n.height + 2 * w),
                       cornerRadius: StarJarGeometry.neckRadius + w))
        return p
    }

    private func drawJarBack(_ ctx: inout GraphicsContext) {
        let b = StarJarGeometry.body
        let glass = Gradient(colors: [Color.white.opacity(0.10), Color(red: 0.55, green: 0.75, blue: 0.95).opacity(0.10), Color.white.opacity(0.05)])
        ctx.fill(jarPath, with: .linearGradient(glass, startPoint: CGPoint(x: b.x, y: b.y), endPoint: CGPoint(x: b.maxX, y: b.maxY)))
        // A warm pool of light behind the stars that rises with the wake level.
        let w = model.wake
        ctx.fill(Path(ellipseIn: CGRect(x: b.x + 10, y: b.y + 20, width: b.width - 20, height: b.height - 10)),
                 with: .radialGradient(Gradient(colors: [tint.opacity(0.05 + 0.18 * w), .clear]),
                                       center: CGPoint(x: b.midX, y: b.midY + 30 * (1 - w)), startRadius: 0, endRadius: 140))
    }

    private func drawStars(_ ctx: inout GraphicsContext) {
        for (i, s) in model.stars.enumerated() {
            let br = model.brightness(i)
            let r = s.radius * (0.75 + 0.45 * br)
            let c = CGPoint(x: s.x, y: s.y)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 3, y: c.y - r * 3, width: r * 6, height: r * 6)),
                     with: .radialGradient(Gradient(colors: [tint.opacity(0.55 * br), .clear]), center: c, startRadius: 0, endRadius: r * 3))
            ctx.fill(starShape(center: c, radius: r, spin: s.phase), with: .color(tint.opacity(0.35 + 0.65 * br)))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.3, y: c.y - r * 0.3, width: r * 0.6, height: r * 0.6)),
                     with: .color(.white.opacity(0.2 + 0.8 * br)))
        }
    }

    private func starShape(center c: CGPoint, radius r: Double, spin: Double) -> Path {
        var p = Path()
        for k in 0..<10 {
            let a = spin + Double(k) * .pi / 5 - .pi / 2
            let rr = k % 2 == 0 ? r : r * 0.45
            let pt = CGPoint(x: c.x + rr * Foundation.cos(a), y: c.y + rr * Foundation.sin(a))
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private func drawJarFront(_ ctx: inout GraphicsContext) {
        let b = StarJarGeometry.body, n = StarJarGeometry.neck
        // Rim: a light outline, brighter on the left where the light comes from.
        ctx.stroke(jarPath, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.75), Color.white.opacity(0.25), Color(red: 0.6, green: 0.8, blue: 1).opacity(0.5)]),
                                                  startPoint: CGPoint(x: b.x, y: b.y), endPoint: CGPoint(x: b.maxX, y: b.maxY)), lineWidth: 2.5)
        // Highlights: a long streak down the left of the body, a short one on the right, one on the neck.
        var streak = Path()
        streak.move(to: CGPoint(x: b.x + 18, y: b.y + 60))
        streak.addQuadCurve(to: CGPoint(x: b.x + 22, y: b.maxY - 50), control: CGPoint(x: b.x + 8, y: b.midY))
        ctx.stroke(streak, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        var short = Path()
        short.move(to: CGPoint(x: b.maxX - 16, y: b.y + 70)); short.addLine(to: CGPoint(x: b.maxX - 14, y: b.y + 110))
        ctx.stroke(short, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        var neckHi = Path()
        neckHi.move(to: CGPoint(x: n.x + 10, y: n.y + 12)); neckHi.addLine(to: CGPoint(x: n.x + 10, y: n.maxY - 10))
        ctx.stroke(neckHi, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        // Refraction band across the shoulder.
        ctx.stroke(Path(roundedRect: CGRect(x: b.x + 6, y: b.y + 6, width: b.width - 12, height: b.height - 12), cornerRadius: StarJarGeometry.bodyRadius - 6),
                   with: .color(Color(red: 0.7, green: 0.85, blue: 1).opacity(0.12)), lineWidth: 3)
        // Cork.
        let k = StarJarGeometry.cork
        let cork = Path(roundedRect: CGRect(x: k.x, y: k.y, width: k.width, height: k.height), cornerRadius: StarJarGeometry.corkRadius)
        ctx.fill(cork, with: .linearGradient(Gradient(colors: [Color(red: 0.80, green: 0.60, blue: 0.38), Color(red: 0.58, green: 0.40, blue: 0.24)]),
                                             startPoint: CGPoint(x: k.midX, y: k.y), endPoint: CGPoint(x: k.midX, y: k.maxY)))
        for i in 0..<9 {
            let x = k.x + 8 + Double(i) * 11, y = k.y + 6 + Double((i * 5) % 3) * 6
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3, height: 2.4)), with: .color(Color(red: 0.45, green: 0.30, blue: 0.18).opacity(0.6)))
        }
    }

    private func drawDone(_ ctx: inout GraphicsContext) {
        let c = StarJarGeometry.doneChip
        let chip = Path(roundedRect: CGRect(x: c.x, y: c.y, width: c.width, height: c.height), cornerRadius: c.height / 2)
        ctx.fill(chip, with: .color(.white.opacity(0.14)))
        ctx.stroke(chip, with: .color(.white.opacity(0.35)), lineWidth: 1)
        ctx.draw(Text("Done").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundColor(.white),
                 at: CGPoint(x: c.midX, y: c.midY))
    }

    private func drawHint(_ ctx: inout GraphicsContext) {
        let text = model.isEngaged ? "Tap outside to rest" : "Tap to wake"
        ctx.draw(Text(text).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundColor(.secondary),
                 at: CGPoint(x: StarJarGeometry.width / 2, y: StarJarGeometry.height + Self.hintHeight / 2))
    }
}

// MARK: - Demo

/// A night-sky page with content above and below the jar, so you can feel scrolling stop while it is awake.
public struct StarJarDemo: View {
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(0..<3, id: \.self) { i in card(i) }
                StarJar()
                    .padding(.vertical, 8)
                ForEach(3..<7, id: \.self) { i in card(i) }
            }
            .padding()
        }
        .starJarScrollLock()
        .background(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.16), Color(red: 0.10, green: 0.08, blue: 0.24)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func card(_ i: Int) -> some View {
        let titles = ["Tonight", "Moon", "Constellations", "Fireflies", "Comets", "Dawn", "Notes"]
        return VStack(alignment: .leading, spacing: 8) {
            Text(titles[i]).font(.headline).foregroundStyle(.white)
            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.18)).frame(height: 8)
            RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.12)).frame(width: 180, height: 8)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))
    }
}

#Preview { StarJarDemo() }
#endif
