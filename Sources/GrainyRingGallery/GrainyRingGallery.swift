//  GrainyRingGallery.swift
//  GrainyRingGallery
//
//  Eight "photo" cards on a 3D ring under a layer of film grain. Drag to spin it: it follows
//  the finger, coasts on with momentum after a fling, and springs onto the nearest card. Side
//  cards turn outwards, shrink, fade and blur with depth. Tap the front card and it grows
//  into a detail view (matchedGeometryEffect); tap a side card to bring it round. The grain
//  is a Metal [[stitchable]] colorEffect whose seed ticks at 12 fps, like projected film.
//  The ring physics, placement maths and grain clock live in RingGalleryCore.

#if canImport(SwiftUI)
import SwiftUI
import RingGalleryCore

/// A 3D card carousel with momentum, a hero detail view and a film-grain finish.
///
/// ```swift
/// GrainyRingGallery(cards: RingPhotoCard.samples)            // built-in gradient "photos"
///
/// GrainyRingGallery(cards: albums) { album in                 // your own card views
///     AlbumCover(album)
/// } detail: { album in                                       // shown under the enlarged card
///     TrackList(album)
/// }
/// ```
///
/// The gallery draws its own dark backdrop (the grain needs opaque pixels to sit on) and fills
/// the space it is given; the ring itself is about `2 × 140 + cardSize.width` points wide.
public struct GrainyRingGallery<Item: Identifiable, CardContent: View, DetailContent: View>: View {
    private let cards: [Item]
    private let cardSize: CGSize
    private let grain: Double
    private let cardContent: (Item) -> CardContent
    private let detailContent: (Item) -> DetailContent
    private let accessibilityTitle: (Item) -> String

    @State private var engine: RingEngine
    @State private var isAnimating = false
    @State private var frontIndex = 0
    @State private var openID: Item.ID?
    @GestureState private var isDragging = false
    @Namespace private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var tuning: RingGalleryModel.Tuning { .default }
    private let cornerRadius: CGFloat = 22

    /// - Parameters:
    ///   - cards: the items on the ring (8 looks best; any count ≥ 1 works).
    ///   - cardSize: size of the front card, points.
    ///   - grain: film-grain strength, 0 (off) … ~0.25 (heavy). Default 0.12.
    ///   - accessibilityTitle: how VoiceOver names an item (default "Card n").
    ///   - card: the card face. It is also shown enlarged at the top of the detail view.
    ///   - detail: extra content under the enlarged card.
    public init(cards: [Item],
                cardSize: CGSize = CGSize(width: 190, height: 262),
                grain: Double = 0.12,
                accessibilityTitle: ((Item) -> String)? = nil,
                @ViewBuilder card: @escaping (Item) -> CardContent,
                @ViewBuilder detail: @escaping (Item) -> DetailContent) {
        self.cards = cards
        self.cardSize = cardSize
        self.grain = grain
        self.cardContent = card
        self.detailContent = detail
        let ids = cards.map(\.id)
        self.accessibilityTitle = accessibilityTitle ?? { item in
            "Card \((ids.firstIndex(of: item.id) ?? 0) + 1)"
        }
        _engine = State(initialValue: RingEngine(count: cards.count))
    }

    public var body: some View {
        ZStack {
            ring
                .blur(radius: openID == nil ? 0 : 10)
                .opacity(openID == nil ? 1 : 0.35)
                .allowsHitTesting(openID == nil)
                .accessibilityHidden(openID != nil)
            if let item = openItem {
                detailLayer(item)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Self.backdrop)
        .modifier(FilmGrainEffect(amount: grain, reduceMotion: reduceMotion))
        .sensoryFeedback(.selection, trigger: frontIndex)
    }

    // MARK: Ring

    private var ring: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let frame = engine.frame(at: timeline.date, count: cards.count, reduceMotion: reduceMotion)
            ZStack {
                ForEach(Array(cards.enumerated()), id: \.element.id) { index, item in
                    if index < frame.placements.count {
                        ringCard(item, placement: frame.placements[index])
                    }
                }
            }
            .offset(y: Self.tuning.elevation / 2)
            .onChange(of: frame.frontIndex) { _, index in frontIndex = index }
            .onChange(of: frame.isSettled) { _, settled in
                if settled && !isDragging { isAnimating = false }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardSize.height + Self.tuning.elevation + 60)
        .contentShape(Rectangle())
        .gesture(drag)
        .onChange(of: isDragging) { _, dragging in
            // The gesture was cancelled without onEnded (e.g. a system interruption).
            if !dragging, engine.isDragging { engine.dragCancelled(); isAnimating = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gallery")
        .accessibilityValue(frontDescription)
        .accessibilityHint("Swipe up or down to change card. Double-tap to open it.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
        .accessibilityAction { openFront() }
        .accessibilityAction(named: "Open") { openFront() }
    }

    @ViewBuilder
    private func ringCard(_ item: Item, placement p: RingCardPlacement) -> some View {
        let isOpen = openID == item.id
        Group {
            if isOpen {
                // The card is "away" in the detail view; keep its slot so nothing reflows.
                Color.clear
            } else {
                cardContent(item)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .heroMatch(id: item.id, in: hero, enabled: !reduceMotion)
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .shadow(color: .black.opacity(0.45 * p.depth), radius: 6 + 14 * p.depth, y: 10 * p.depth)
        .blur(radius: p.blur)
        .rotation3DEffect(.degrees(p.yawDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .scaleEffect(p.scale)
        .offset(x: p.x, y: p.y)
        .opacity(p.opacity)
        .zIndex(p.zIndex)
        .onTapGesture { tapped(p) }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                if !engine.isDragging { engine.dragBegan() }
                engine.dragChanged(translation: value.translation.width,
                                   time: value.time.timeIntervalSinceReferenceDate)
                isAnimating = true
            }
            .onEnded { value in
                engine.dragEnded(velocity: value.velocity.width)
                isAnimating = true
            }
    }

    /// VoiceOver value for the ring, e.g. "Dunes, 1 of 8".
    private var frontDescription: String {
        guard cards.indices.contains(frontIndex) else { return "" }
        return "\(accessibilityTitle(cards[frontIndex])), \(frontIndex + 1) of \(cards.count)"
    }

    // MARK: Detail

    private var openItem: Item? { openID.flatMap { id in cards.first { $0.id == id } } }

    private func detailLayer(_ item: Item) -> some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            VStack(spacing: 20) {
                cardContent(item)
                    .aspectRatio(cardSize.width / cardSize.height, contentMode: .fit)
                    .frame(maxWidth: 340)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius + 6, style: .continuous))
                    .heroMatch(id: item.id, in: hero, enabled: !reduceMotion)
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 14)
                    .accessibilityHidden(true)
                detailContent(item)
                    .frame(maxWidth: 340, alignment: .leading)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 16)))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel("Close")
            .transition(.opacity)
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityTitle(item))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { close() }
    }

    // MARK: Actions

    private func tapped(_ p: RingCardPlacement) {
        if p.isFront && abs(p.angle) < 0.15 {
            openFront()
        } else {
            engine.select(p.index)
            isAnimating = true
        }
    }

    private func move(by cards: Int) {
        engine.step(by: cards)
        isAnimating = true
    }

    private func openFront() {
        guard cards.indices.contains(frontIndex) else { return }
        withAnimation(heroAnimation) { openID = cards[frontIndex].id }
    }

    private func close() {
        withAnimation(heroAnimation) { openID = nil }
    }

    /// Reduce Motion: a plain crossfade instead of the zoom.
    private var heroAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.45, dampingFraction: 0.84)
    }

    private static var backdrop: some View {
        ZStack {
            Color(red: 0.055, green: 0.05, blue: 0.065)
            RadialGradient(colors: [Color(red: 0.2, green: 0.17, blue: 0.24).opacity(0.85), .clear],
                           center: .center, startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Convenience initialisers

extension GrainyRingGallery where DetailContent == EmptyView {
    /// A ring of your own cards with no extra detail content (the card is just shown enlarged).
    public init(cards: [Item],
                cardSize: CGSize = CGSize(width: 190, height: 262),
                grain: Double = 0.12,
                accessibilityTitle: ((Item) -> String)? = nil,
                @ViewBuilder card: @escaping (Item) -> CardContent) {
        self.init(cards: cards, cardSize: cardSize, grain: grain,
                  accessibilityTitle: accessibilityTitle, card: card) { _ in EmptyView() }
    }
}

extension GrainyRingGallery where Item == RingPhotoCard, CardContent == RingPhotoCardView,
                                  DetailContent == RingPhotoCaption {
    /// A ring of gradient "photo" cards with a caption in the detail view.
    public init(cards: [RingPhotoCard] = RingPhotoCard.samples,
                cardSize: CGSize = CGSize(width: 190, height: 262),
                grain: Double = 0.12) {
        self.init(cards: cards, cardSize: cardSize, grain: grain,
                  accessibilityTitle: { $0.title },
                  card: { RingPhotoCardView(card: $0) },
                  detail: { RingPhotoCaption(card: $0) })
    }
}

// MARK: - Photo cards

/// A placeholder "photo": a two-tone gradient with a hazy sun and a horizon, titled.
public struct RingPhotoCard: Identifiable, Hashable, Sendable {
    public var id: String { title }
    public var title: String
    public var subtitle: String
    public var colors: [Color]
    public var caption: String

    public init(title: String, subtitle: String, colors: [Color], caption: String = "") {
        self.title = title; self.subtitle = subtitle; self.colors = colors; self.caption = caption
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255)
    }

    /// Eight sample cards.
    public static let samples: [RingPhotoCard] = [
        .init(title: "Dunes", subtitle: "Sossusvlei · 06:12", colors: [rgb(0xF6B26B), rgb(0xC0504D)],
              caption: "First light raking across the dunes, the shadows still blue."),
        .init(title: "Lagoon", subtitle: "Bora Bora · 14:30", colors: [rgb(0x5EE7DF), rgb(0x1E6FA8)],
              caption: "Water so clear the boat's shadow looked like it was floating."),
        .init(title: "Aurora", subtitle: "Tromsø · 23:48", colors: [rgb(0x43E97B), rgb(0x2A2A72)],
              caption: "Green curtains, minus twelve, and nobody wanted to go inside."),
        .init(title: "Ember", subtitle: "Kyoto · 18:05", colors: [rgb(0xFF9A5A), rgb(0x8E2DE2)],
              caption: "Maple leaves catching the last of the sun on the temple steps."),
        .init(title: "Moss", subtitle: "Yakushima · 09:40", colors: [rgb(0xB5E48C), rgb(0x2D6A4F)],
              caption: "A forest floor so green it hums."),
        .init(title: "Dusk", subtitle: "Lisbon · 20:17", colors: [rgb(0xFFB3C1), rgb(0x5B4B8A)],
              caption: "Pink rooftops and a tram bell somewhere below."),
        .init(title: "Glacier", subtitle: "Jökulsárlón · 11:02", colors: [rgb(0xD7F1FF), rgb(0x4A7FB5)],
              caption: "Blue ice drifting out to sea, cracking like gunshots."),
        .init(title: "Bloom", subtitle: "Hokkaido · 07:55", colors: [rgb(0xF9D976), rgb(0xE96443)],
              caption: "Rows of poppies and lavender to the horizon."),
    ]
}

/// The face of a ``RingPhotoCard``. Scales to whatever frame it is given.
public struct RingPhotoCardView: View {
    public let card: RingPhotoCard
    public init(card: RingPhotoCard) { self.card = card }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: card.colors, startPoint: .top, endPoint: .bottom)
                // Hazy sun.
                Circle()
                    .fill(.white.opacity(0.55))
                    .frame(width: w * 0.36, height: w * 0.36)
                    .blur(radius: w * 0.06)
                    .position(x: w * 0.68, y: h * 0.36)
                // Two hills for a horizon.
                Ellipse()
                    .fill(.black.opacity(0.18))
                    .frame(width: w * 1.5, height: h * 0.5)
                    .position(x: w * 0.2, y: h * 0.92)
                Ellipse()
                    .fill(.black.opacity(0.28))
                    .frame(width: w * 1.4, height: h * 0.44)
                    .position(x: w * 0.95, y: h * 1.0)
                LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title)
                        .font(.system(size: max(w * 0.1, 15), weight: .bold, design: .rounded))
                    Text(card.subtitle)
                        .font(.system(size: max(w * 0.058, 10), weight: .medium))
                        .opacity(0.8)
                }
                .foregroundStyle(.white)
                .padding(w * 0.08)
            }
        }
    }
}

/// The caption under an opened ``RingPhotoCard`` (the enlarged card already shows its title).
public struct RingPhotoCaption: View {
    public let card: RingPhotoCard
    public init(card: RingPhotoCard) { self.card = card }

    public var body: some View {
        Text(card.caption)
            .font(.body)
            .foregroundStyle(.white.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Film grain

/// Applies the `filmGrain` Metal shader with a seed that changes 12 times a second.
/// With Reduce Motion the grain is frozen (one static pattern, timeline effectively idle).
struct FilmGrainEffect: ViewModifier {
    let amount: Double
    let reduceMotion: Bool
    var fps: Double = RingGalleryModel.Tuning.default.grainFPS

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: reduceMotion || amount <= 0 ? 3600 : 1 / fps)) { timeline in
            let seed = RingGalleryModel.grainSeed(at: timeline.date.timeIntervalSinceReferenceDate,
                                                  fps: fps, reduceMotion: reduceMotion)
            content.colorEffect(
                ShaderLibrary.bundle(.module).filmGrain(.float(Float(seed)), .float(Float(amount)), .float(1.2)),
                isEnabled: amount > 0)
        }
    }
}

// MARK: - Engine

struct RingFrame {
    var placements: [RingCardPlacement]
    var frontIndex: Int
    var isSettled: Bool
}

/// Holds the deterministic model outside SwiftUI's dependency tracking.
final class RingEngine {
    private var model: RingGalleryModel
    private var lastDate: Date?

    init(count: Int) { model = RingGalleryModel(count: count) }

    var isDragging: Bool { model.phase == .dragging }
    func dragBegan() { model.dragBegan() }
    func dragChanged(translation: Double, time: Double) { model.dragChanged(translation: translation, time: time) }
    func dragEnded(velocity: Double) { model.dragEnded(velocity: velocity) }
    func dragCancelled() { model.dragCancelled() }
    func step(by cards: Int) { model.step(by: cards) }
    func select(_ index: Int) { model.select(index) }

    func frame(at date: Date, count: Int, reduceMotion: Bool) -> RingFrame {
        if model.count != max(1, count) {
            model = RingGalleryModel(count: count, tuning: model.tuning, reduceMotion: reduceMotion)
        }
        model.reduceMotion = reduceMotion
        if let lastDate { model.step(date.timeIntervalSince(lastDate)) }
        lastDate = model.isSettled ? nil : date
        return RingFrame(placements: model.placements, frontIndex: model.frontIndex, isSettled: model.isSettled)
    }
}

// MARK: - Helpers

private extension View {
    /// `matchedGeometryEffect` that can be switched off (Reduce Motion crossfades instead).
    @ViewBuilder
    func heroMatch<ID: Hashable>(id: ID, in namespace: Namespace.ID, enabled: Bool) -> some View {
        if enabled {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}

// MARK: - Previews

#Preview("Grainy Ring Gallery") {
    GrainyRingGallery(cards: RingPhotoCard.samples)
}

private struct PreviewSwatch: Identifiable {
    let id: Int
    let hue: Double
}

#Preview("Custom cards") {
    GrainyRingGallery(cards: (0..<8).map { PreviewSwatch(id: $0, hue: Double($0) / 8) },
                             cardSize: CGSize(width: 160, height: 160), grain: 0.18,
                             accessibilityTitle: { "Swatch \($0.id + 1)" }) { swatch in
        Color(hue: swatch.hue, saturation: 0.6, brightness: 0.9)
            .overlay(Text("\(swatch.id + 1)").font(.largeTitle.bold()).foregroundStyle(.white))
    }
}
#endif
