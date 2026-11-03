//
//  ShelfPull.swift
//  ShelfPull
//
//  A shelf of seven book spines on a wooden plank. Pull one up and it fights back like a rubber band,
//  rising out of its slot while the books beside it lean into the gap, each a little less than the one
//  before. Pull past 55% of its height (or flick it) and it lifts free, turns 90 degrees about its vertical
//  axis to show its front cover, and the cover grows into a card holding a small live demo. Close the card
//  and it shrinks back to a book, turns, slides down into its slot, and a soft thunk lands as it seats.
//  Let go sooner and it springs home. Reduce Motion crossfades to the card with no 3D.
//  The resistance curve, the commit decision, the phase machine, the neighbours' lean, the seat event and
//  the layout all live in ShelfPullCore as pure functions of time.

#if canImport(SwiftUI)
import SwiftUI
import ShelfPullCore

/// One book on the shelf: a spine title and colour, and the view shown on the open card.
///
/// ```swift
/// ShelfBook(title: "Dot", color: .orange) { MyBouncingDot() }
/// ```
public struct ShelfBook: Identifiable {
    public let id = UUID()
    public var title: String
    public var color: Color
    let content: AnyView

    public init<Content: View>(title: String, color: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.color = color
        self.content = AnyView(content())
    }
}

/// A bookshelf you pull books off.
///
/// ```swift
/// ShelfPull()                                        // seven books, each with a small animated demo
/// ShelfPull(books: [
///     ShelfBook(title: "Dot", color: .orange) { Circle().frame(width: 40) },
///     ShelfBook(title: "Ring", color: .teal) { Circle().stroke(lineWidth: 6).frame(width: 60) },
///     ShelfBook(title: "Wave", color: .indigo) { Text("~") },
/// ])                                                 // 3 ... 9 books (extra books are dropped, a short list repeats)
/// ```
///
/// The shelf is 340 × 440 points; scale it with `.scaleEffect` if you need another size.
public struct ShelfPull: View {
    @State private var engine: ShelfEngine
    @State private var isAnimating = false
    @State private var revision = 0
    @State private var seats = 0
    @State private var arms = 0
    @State private var grabbed = false
    @State private var touching = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let books: [ShelfBook]

    public static let shelfSize = CGSize(width: ShelfLayout.width, height: ShelfLayout.height)

    /// Seven books named after gallery components, each with a small animated demo.
    public init() {
        self.init(books: ShelfDefaults.books)
    }

    /// Your own books. 3 ... 9 are shown: a short list is repeated, a long one cut.
    public init(books: [ShelfBook]) {
        var list = books.isEmpty ? ShelfDefaults.books : books
        var k = 0
        while list.count < ShelfLayout.minBooks { list.append(books.isEmpty ? ShelfDefaults.books[k] : books[k % books.count]); k += 1 }
        self.books = Array(list.prefix(ShelfLayout.maxBooks))
        _engine = State(initialValue: ShelfEngine(count: self.books.count))
    }

    public var body: some View {
        let _ = revision
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let f = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            scene(f)
                .onChange(of: engine.model.seats) { _, n in seats = n }
                .onChange(of: engine.model.isAnimating) { _, running in
                    if !running { isAnimating = false; engine.pause() }
                }
                .onChange(of: engine.model.opens) { _, _ in
                    if let b = engine.model.book { AccessibilityNotification.Announcement("\(books[b].title), open").post() }
                }
        }
        .frame(width: Self.shelfSize.width, height: Self.shelfSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.8), trigger: seats)
        .sensoryFeedback(.selection, trigger: arms)
    }

    // MARK: scene

    private func scene(_ f: ShelfFrame) -> some View {
        let layout = engine.model.layout
        let open = f.card != nil
        return ZStack(alignment: .topLeading) {
            ShelfBackdrop()
            ShelfPlank()
            ForEach(drawOrder(f), id: \.self) { i in
                spine(i, f, layout)
            }
            .accessibilityHidden(open)
            if f.scrim > 0 {
                Color.black.opacity(f.scrim).allowsHitTesting(false)
            }
            if let card = f.card, let b = f.book {
                cardView(card, book: books[b], index: b)
            }
        }
        .frame(width: Self.shelfSize.width, height: Self.shelfSize.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in pointerChanged(v) }
                .onEnded { v in pointerEnded(v) }
        )
    }

    /// The pulled book is drawn last, so it passes in front of its neighbours.
    private func drawOrder(_ f: ShelfFrame) -> [Int] {
        let all = Array(books.indices)
        guard let b = f.book else { return all }
        return all.filter { $0 != b } + [b]
    }

    private func spine(_ i: Int, _ f: ShelfFrame, _ layout: ShelfLayout) -> some View {
        let s = layout.spines[i], sf = f.spines[i]
        let book = books[i]
        return ZStack {
            if sf.turn > 0.01 {
                turningBook(s, book, index: i, frame: sf)
            } else {
                BookSpine(spine: s, title: book.title, color: book.color)
            }
        }
        .frame(width: s.width, height: s.height)
        .rotationEffect(.degrees(sf.lean), anchor: UnitPoint(x: sf.pivotsTrailing ? 1 : 0, y: 1))
        .scaleEffect(sf.scale)
        .offset(x: sf.offsetX, y: -sf.rise)
        .opacity(sf.opacity)
        .position(x: s.centerX, y: ShelfLayout.plankTop - s.height / 2)
        .shadow(color: .black.opacity(sf.isActive && sf.rise > 1 ? 0.35 : 0), radius: 8, x: 0, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Book: \(book.title)")
        .accessibilityHint("Opens the book.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate(i) }
    }

    /// While the book turns: the spine face swings away to the left of the shared edge, the front cover swings
    /// in on the right. Both hinge on that edge, so the book stays centred.
    private func turningBook(_ s: ShelfSpine, _ book: ShelfBook, index: Int, frame sf: ShelfSpineFrame) -> some View {
        let t = ShelfTimeline.turnLayout(spineWidth: s.width, coverWidth: s.coverWidth, degrees: sf.turn)
        return ZStack {
            BookSpine(spine: s, title: book.title, color: book.color)
                .frame(width: s.width, height: s.height)
                .rotation3DEffect(.degrees(-sf.turn), axis: (x: 0, y: 1, z: 0), anchor: .trailing, anchorZ: 0, perspective: 0.4)
                .offset(x: t.hinge - s.width / 2)
                .opacity(sf.turn > 89.5 ? 0 : 1)
            BookCover(title: book.title, color: book.color, index: index)
                .frame(width: s.coverWidth, height: s.height)
                .rotation3DEffect(.degrees(90 - sf.turn), axis: (x: 0, y: 1, z: 0), anchor: .leading, anchorZ: 0, perspective: 0.4)
                .offset(x: t.hinge + s.coverWidth / 2)
        }
        .frame(width: s.width, height: s.height)
    }

    private func cardView(_ card: ShelfCard, book: ShelfBook, index: Int) -> some View {
        let r = card.rect
        return ZStack {
            RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous)
                .fill(Color(red: 0.97, green: 0.94, blue: 0.88))
            BookCover(title: book.title, color: book.color, index: index)
                .frame(width: r.width, height: r.height)
                .opacity(card.coverOpacity)
            VStack(spacing: 14) {
                HStack {
                    Text(book.title)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 0.2, green: 0.14, blue: 0.1))
                    Spacer()
                    Button { closeBook() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundStyle(Color.black.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(book.color.opacity(0.16))
                    book.content.padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Tap outside to put it back")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.4))
            }
            .padding(18)
            .frame(width: ShelfLayout.cardSize.x, height: ShelfLayout.cardSize.y)
            .scaleEffect(min(r.width / ShelfLayout.cardSize.x, r.height / ShelfLayout.cardSize.y))
            .opacity(card.contentOpacity)
        }
        .frame(width: r.width, height: r.height)
        .clipShape(RoundedRectangle(cornerRadius: card.cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
        .opacity(card.opacity)
        .position(x: r.midX, y: r.midY)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { closeBook() }
    }

    // MARK: input

    private func pointerChanged(_ v: DragGesture.Value) {
        let ts = v.time.timeIntervalSinceReferenceDate
        if !touching {
            touching = true
            let hit = engine.model.layout.spine(atX: Double(v.startLocation.x), y: Double(v.startLocation.y))
            grabbed = hit.map { engine.model.pointerDown(book: $0) } ?? false
            if grabbed { isAnimating = false }
        }
        guard grabbed else { return }
        let events = engine.model.pointerMoved(upward: -Double(v.translation.height), at: ts)
        if events.contains(where: { if case .armed = $0 { return true }; return false }) { arms += 1 }
        revision += 1
    }

    private func pointerEnded(_ v: DragGesture.Value) {
        defer { touching = false; grabbed = false }
        if grabbed {
            _ = engine.model.pointerUp(at: v.time.timeIntervalSinceReferenceDate)
            isAnimating = true
            revision += 1
        } else if engine.model.canClose, abs(v.translation.width) < 8, abs(v.translation.height) < 8,
                  !ShelfLayout.cardRect.contains(Double(v.startLocation.x), Double(v.startLocation.y)) {
            closeBook()
        }
    }

    private func activate(_ i: Int) {
        _ = engine.model.activate(book: i)
        isAnimating = true
        revision += 1
    }

    private func closeBook() {
        if engine.model.close() { isAnimating = true; revision += 1 }
    }
}

/// Owns the running model; steps it from the timeline.
final class ShelfEngine {
    private(set) var model: ShelfPullModel
    private var lastDate: Date?

    init(count: Int) { model = ShelfPullModel(count: count) }

    func pause() { lastDate = nil }

    func frame(at date: Date, reduceMotion: Bool) -> ShelfFrame {
        model.setReduceMotion(reduceMotion)
        if model.isAnimating {
            let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
            lastDate = date
            model.step(dt)
        } else {
            lastDate = nil
        }
        return model.frame
    }
}

// MARK: - pieces

private struct ShelfBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.25, green: 0.19, blue: 0.16), Color(red: 0.14, green: 0.10, blue: 0.09)],
                           startPoint: .top, endPoint: .bottom)
            // light falling on the back panel from the upper left
            RadialGradient(colors: [Color.white.opacity(0.10), .clear], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 10, endRadius: 320)
        }
    }
}

private struct ShelfPlank: View {
    var body: some View {
        let top = ShelfLayout.plankTop
        ZStack(alignment: .topLeading) {
            // soft contact shadow where the books stand
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .bottom, endPoint: .top)
                .frame(width: ShelfLayout.width, height: 14)
                .offset(y: top - 14)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.43, blue: 0.27), Color(red: 0.42, green: 0.28, blue: 0.17)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: ShelfLayout.width - 2 * 4, height: ShelfLayout.plankThickness)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1) }
                .overlay(WoodGrain().stroke(Color.black.opacity(0.10), lineWidth: 0.7).clipped())
                .shadow(color: .black.opacity(0.55), radius: 8, y: 6)
                .offset(x: 4, y: top)
        }
        .allowsHitTesting(false)
    }
}

private struct WoodGrain: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for k in 0..<4 {
            let y = rect.minY + rect.height * (CGFloat(k) + 0.7) / 4.4
            p.move(to: CGPoint(x: rect.minX, y: y))
            var x = rect.minX
            while x < rect.maxX {
                x += 24
                p.addQuadCurve(to: CGPoint(x: x, y: y + (k % 2 == 0 ? 0.8 : -0.8)), control: CGPoint(x: x - 12, y: y + (k % 2 == 0 ? -1.4 : 1.4)))
            }
        }
        return p
    }
}

/// The spine face: cloth gradient, rounded-back highlight, bands and the title running up the spine.
private struct BookSpine: View {
    let spine: ShelfSpine
    let title: String
    let color: Color

    var body: some View {
        let w = spine.width, h = spine.height
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.62)], startPoint: .leading, endPoint: .trailing))
            LinearGradient(stops: [.init(color: .white.opacity(0.28), location: 0), .init(color: .clear, location: 0.35),
                                   .init(color: .black.opacity(0.28), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .clipShape(RoundedRectangle(cornerRadius: 2.5, style: .continuous))
            ForEach(Array(spine.bands.enumerated()), id: \.offset) { k, f in
                Rectangle()
                    .fill(Color(red: 0.95, green: 0.85, blue: 0.55).opacity(k % 2 == 0 ? 0.85 : 0.55))
                    .frame(width: w, height: k == 0 ? 3 : 1.6)
                    .position(x: w / 2, y: h * f)
            }
            Text(title)
                .font(.system(size: min(13, w * 0.36), weight: .semibold, design: .serif))
                .foregroundStyle(Color(red: 0.97, green: 0.93, blue: 0.82))
                .lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: h * 0.58, height: w)
                .rotationEffect(.degrees(-90))
                .position(x: w / 2, y: h * 0.5)
        }
        .frame(width: w, height: h)
    }
}

/// The front cover, drawn only from gradients and shapes: a framed emblem above the title.
private struct BookCover: View {
    let title: String
    let color: Color
    let index: Int

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                LinearGradient(colors: [color.opacity(0.95), color.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Color(red: 0.95, green: 0.85, blue: 0.55).opacity(0.8), lineWidth: max(1, w * 0.012))
                    .padding(w * 0.07)
                emblem(size: w * 0.42)
                    .position(x: w / 2, y: h * 0.40)
                Text(title)
                    .font(.system(size: w * 0.115, weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: 0.97, green: 0.93, blue: 0.82))
                    .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                    .frame(width: w * 0.72)
                    .position(x: w / 2, y: h * 0.74)
                LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .leading, endPoint: UnitPoint(x: 0.12, y: 0.5))
            }
        }
    }

    @ViewBuilder private func emblem(size s: CGFloat) -> some View {
        let gold = Color(red: 0.95, green: 0.85, blue: 0.55)
        switch index % 4 {
        case 0:
            ZStack { Circle().stroke(gold, lineWidth: s * 0.07); Circle().fill(gold.opacity(0.7)).frame(width: s * 0.3) }
                .frame(width: s, height: s)
        case 1:
            ZStack { RoundedRectangle(cornerRadius: s * 0.1).stroke(gold, lineWidth: s * 0.07).rotationEffect(.degrees(45)); Circle().fill(gold.opacity(0.7)).frame(width: s * 0.25) }
                .frame(width: s, height: s)
        case 2:
            ZStack { ForEach(0..<3, id: \.self) { k in Circle().stroke(gold.opacity(0.9 - 0.25 * Double(k)), lineWidth: s * 0.05).frame(width: s * (1 - 0.3 * CGFloat(k))) } }
                .frame(width: s, height: s)
        default:
            ZStack { ForEach(0..<6, id: \.self) { k in Capsule().fill(gold.opacity(0.85)).frame(width: s * 0.1, height: s * 0.5).offset(y: -s * 0.25).rotationEffect(.degrees(Double(k) * 60)) } }
                .frame(width: s, height: s)
        }
    }
}

// MARK: - demo books

/// Seven books named after gallery components, each holding a small animated demo.
enum ShelfDefaults {
    static var books: [ShelfBook] {
        [
            ShelfBook(title: "Frost Card", color: Color(red: 0.16, green: 0.45, blue: 0.55)) { BounceDotDemo() },
            ShelfBook(title: "Holo Foil", color: Color(red: 0.45, green: 0.22, blue: 0.40)) { SpinRingDemo() },
            ShelfBook(title: "Cloth Poster", color: Color(red: 0.78, green: 0.33, blue: 0.25)) { WaveDemo() },
            ShelfBook(title: "Moon Phase", color: Color(red: 0.16, green: 0.27, blue: 0.46)) { OrbitDemo() },
            ShelfBook(title: "Channel Flip", color: Color(red: 0.18, green: 0.40, blue: 0.32)) { EqualizerDemo() },
            ShelfBook(title: "Contour Ink", color: Color(red: 0.55, green: 0.38, blue: 0.24)) { RippleDemo() },
            ShelfBook(title: "Dog Ear", color: Color(red: 0.86, green: 0.65, blue: 0.20)) { PendulumDemo() },
        ]
    }
}

/// Runs `content` with the time in seconds; frozen at a pleasant still under Reduce Motion.
private struct DemoClock<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let still: Double
    let content: (Double) -> Content

    init(still: Double = 0.4, @ViewBuilder content: @escaping (Double) -> Content) {
        self.still = still
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            content(reduceMotion ? still : tl.date.timeIntervalSinceReferenceDate)
        }
    }
}

private let demoInk = Color(red: 0.2, green: 0.14, blue: 0.1)

private struct BounceDotDemo: View {
    var body: some View {
        DemoClock(still: 0.25) { t in
            GeometryReader { g in
                let phase = abs(sin(t * 3.2))
                ZStack {
                    Capsule().fill(demoInk.opacity(0.18)).frame(width: 60 - 26 * phase, height: 8)
                        .position(x: g.size.width / 2, y: g.size.height - 24)
                    Circle().fill(Color(red: 0.16, green: 0.45, blue: 0.55)).frame(width: 36, height: 36)
                        .scaleEffect(x: 1 + 0.15 * (1 - phase), y: 1 - 0.15 * (1 - phase))
                        .position(x: g.size.width / 2, y: g.size.height - 44 - (g.size.height - 100) * phase)
                }
            }
        }
    }
}

private struct SpinRingDemo: View {
    var body: some View {
        DemoClock { t in
            ZStack {
                Circle().stroke(demoInk.opacity(0.12), lineWidth: 10)
                Circle().trim(from: 0, to: 0.72)
                    .stroke(AngularGradient(colors: [Color(red: 0.45, green: 0.22, blue: 0.40).opacity(0.1), Color(red: 0.45, green: 0.22, blue: 0.40)], center: .center),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(t * 220))
            }
            .frame(width: 90, height: 90)
        }
    }
}

private struct WaveDemo: View {
    var body: some View {
        DemoClock { t in
            Canvas { ctx, size in
                for k in 0..<3 {
                    var p = Path()
                    let amp = 16.0 - Double(k) * 4
                    for x in stride(from: 0.0, through: Double(size.width), by: 3) {
                        let y = Double(size.height) / 2 + amp * sin(x / 28 + t * (2.4 + Double(k) * 0.5) + Double(k))
                        if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(p, with: .color(Color(red: 0.78, green: 0.33, blue: 0.25).opacity(1 - 0.28 * Double(k))),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

private struct OrbitDemo: View {
    var body: some View {
        DemoClock { t in
            ZStack {
                Circle().stroke(demoInk.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 4])).frame(width: 110, height: 110)
                Circle().fill(Color(red: 0.16, green: 0.27, blue: 0.46)).frame(width: 34, height: 34)
                Circle().fill(Color(red: 0.95, green: 0.85, blue: 0.55)).frame(width: 14, height: 14)
                    .offset(x: 55 * cos(t * 1.8), y: 55 * sin(t * 1.8))
            }
        }
    }
}

private struct EqualizerDemo: View {
    var body: some View {
        DemoClock { t in
            HStack(alignment: .bottom, spacing: 7) {
                ForEach(0..<7, id: \.self) { k in
                    let v = 0.5 + 0.5 * sin(t * (2.2 + Double(k) * 0.37) + Double(k) * 1.3)
                    Capsule().fill(Color(red: 0.18, green: 0.40, blue: 0.32)).frame(width: 14, height: 14 + 70 * v)
                }
            }
            .frame(height: 90, alignment: .bottom)
        }
    }
}

private struct RippleDemo: View {
    var body: some View {
        DemoClock { t in
            ZStack {
                ForEach(0..<3, id: \.self) { k in
                    let u = (t * 0.5 + Double(k) / 3).truncatingRemainder(dividingBy: 1)
                    Circle().stroke(Color(red: 0.55, green: 0.38, blue: 0.24).opacity(1 - u), lineWidth: 3)
                        .frame(width: 20 + 110 * u, height: 20 + 110 * u)
                }
                Circle().fill(Color(red: 0.55, green: 0.38, blue: 0.24)).frame(width: 14, height: 14)
            }
        }
    }
}

private struct PendulumDemo: View {
    var body: some View {
        DemoClock { t in
            VStack(spacing: 0) {
                Rectangle().fill(demoInk.opacity(0.6)).frame(width: 2, height: 70)
                Circle().fill(Color(red: 0.86, green: 0.65, blue: 0.20)).frame(width: 30, height: 30)
            }
            .rotationEffect(.degrees(28 * sin(t * 3.0)), anchor: .top)
            .frame(width: 140, height: 110, alignment: .top)
        }
    }
}

#Preview {
    ShelfPull()
        .padding(24)
        .background(Color.black)
}
#endif
