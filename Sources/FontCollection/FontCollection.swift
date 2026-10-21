//  FontCollection.swift
//  FontCollection
//
//  A tactile font specimen gallery. The headline flaps through the collection like a split-flap
//  board, fast then slower, and settles on one face (light haptic ticks as it slows, a firmer
//  one when it lands; tap it to shuffle again). Category chips make the specimen cards hop and
//  regroup on springs. Tap a card and it grows into a detail view (matchedGeometryEffect) with
//  editable sample text, size and weight sliders, and a full glyph strip.
//  Only fonts that ship with iOS 17 / macOS 14 are used; nothing is bundled. The catalog,
//  filtering, flip-board schedule, regroup choreography and haptic timing live in
//  FontCollectionCore.

#if canImport(SwiftUI)
import SwiftUI
import CoreText
import FontCollectionCore

/// A font collection showcase: a flip-board headline, filter chips and specimen cards that open
/// into a detail view.
///
/// ```swift
/// FontCollection()                                    // 16 built-in faces
/// FontCollection(headline: "Hello")                   // your own flip-board word
/// FontCollection(fonts: FontCatalog.standard.specimens.filter { $0.category != .script })
/// ```
///
/// The view paints its own warm paper backdrop and scrolls vertically; give it the whole screen.
public struct FontCollection: View {
    private let catalog: FontCatalog
    private let headline: String

    @State private var engine: FontEngine
    @State private var isAnimating = true
    @State private var filter: FontFilter = .all
    @State private var openID: String?
    @State private var chipTaps = 0
    @Namespace private var hero
    @Namespace private var chipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// - Parameters:
    ///   - fonts: the specimens to show (default: ``FontCatalog/standard``, 16 faces).
    ///   - headline: the word on the flip board (keep it short; ~6–10 letters fit a phone).
    ///   - seed: fixes the flip-board sequence and the card tilts (default random).
    public init(fonts: [FontSpecimen] = FontCatalog.standard.specimens,
                headline: String = "Fontastic",
                seed: UInt64 = UInt64.random(in: 0...UInt64.max)) {
        let catalog = FontCatalog(fonts)
        self.catalog = catalog
        self.headline = headline.isEmpty ? "Aa" : headline
        _engine = State(initialValue: FontEngine(catalog: catalog, headline: self.headline, seed: seed))
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: !isAnimating)) { timeline in
                let frame = engine.frame(at: timeline.date, width: Double(proxy.size.width), reduceMotion: reduceMotion)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(frame, width: proxy.size.width)
                        chips
                        grid(frame, width: proxy.size.width)
                    }
                    .padding(.top, 12)
                }
                .scrollDisabled(openID != nil)
                .hapticFeedback(trigger: frame.tickCount) { old, new in
                    new > old ? .impact(weight: .light, intensity: frame.lastTickIntensity) : nil
                }
                .hapticFeedback(trigger: frame.settleCount) { old, new in
                    new > old ? .impact(weight: .medium, intensity: 0.9) : nil
                }
                .hapticFeedback(trigger: frame.landingCount) { old, new in
                    new > old ? .impact(weight: .light, intensity: 0.5) : nil
                }
                .onChange(of: frame.isSettled) { _, settled in
                    if settled { isAnimating = false }
                }
            }
        }
        .blur(radius: openID == nil ? 0 : 8)
        .allowsHitTesting(openID == nil)
        .accessibilityHidden(openID != nil)
        .overlay {
            if let id = openID, let specimen = catalog.specimen(id: id) {
                SpecimenDetailView(specimen: specimen, hero: hero, reduceMotion: reduceMotion, close: close)
            }
        }
        .background(FontPalette.paper.ignoresSafeArea())
        .hapticFeedback(trigger: chipTaps) { _, _ in .selection }
    }

    // MARK: Header

    private func header(_ frame: FontFrame, width: CGFloat) -> some View {
        let count = max(frame.cells.count, 1)
        let spacing: CGFloat = 4
        let cellWidth = min(40, (width - 32 - spacing * CGFloat(count - 1)) / CGFloat(count))
        let cellSize = CGSize(width: max(cellWidth, 12), height: max(cellWidth, 12) * 1.42)
        let characters = headline.map(String.init)
        let settled = catalog.specimens.indices.contains(frame.target) ? catalog.specimens[frame.target] : nil
        return VStack(spacing: 10) {
            HStack(spacing: spacing) {
                ForEach(Array(frame.cells.enumerated()), id: \.offset) { column, cell in
                    FlapCell(character: column < characters.count ? characters[column] : " ",
                             from: flapFont(cell.fromFont, size: cellSize.height * 0.6),
                             to: flapFont(cell.toFont, size: cellSize.height * 0.6),
                             progress: cell.progress, size: cellSize)
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Text(frame.isHeadlineSettled ? "set in" : "flipping…")
                    .foregroundStyle(FontPalette.inkSoft)
                if frame.isHeadlineSettled, let settled {
                    Text(settled.name)
                        .foregroundStyle(FontPalette.tint(settled.category))
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7), value: frame.isHeadlineSettled)
            Text("Tap the board to shuffle")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(FontPalette.inkSoft.opacity(0.7))
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: shuffle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(settled.map { "\(headline), set in \($0.name)" } ?? headline))
        .accessibilityHint(Text("Double-tap to flip to another font."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { shuffle() }
    }

    private func flapFont(_ index: Int, size: CGFloat) -> Font {
        guard catalog.specimens.indices.contains(index) else { return .system(size: size, weight: .bold) }
        return catalog.specimens[index].swiftUIFont(size: size)
    }

    // MARK: Chips

    private var chips: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(catalog.availableFilters, id: \.self) { chip in
                        let selected = chip == filter
                        Button { select(chip) } label: {
                            HStack(spacing: 5) {
                                Text(chip.title)
                                Text("\(catalog.count(for: chip))")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .opacity(0.6)
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(selected ? Color.white : FontPalette.ink)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background {
                                if selected {
                                    Capsule().fill(FontPalette.ink)
                                        .matchedGeometryEffect(id: "chip", in: chipNamespace)
                                } else {
                                    Capsule().fill(Color.white.opacity(0.75))
                                        .overlay(Capsule().strokeBorder(FontPalette.ink.opacity(0.12)))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .id(chip)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityLabel(Text("\(chip.title), \(catalog.count(for: chip)) fonts"))
                    }
                }
                .padding(.horizontal, 16)
            }
            .onChange(of: filter) { _, chip in
                // Keep the selected chip in view (the row is wider than a phone).
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.75)) {
                    proxy.scrollTo(chip, anchor: .center)
                }
            }
        }
    }

    // MARK: Grid

    private func grid(_ frame: FontFrame, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(frame.cards, id: \.specimen.id) { card in
                let isOpen = openID == card.specimen.id
                let lift = isOpen ? 0 : max(card.pose.zIndex - 1, 0)   // 0 on the ground, up to 2 mid-hop
                Group {
                    if isOpen {
                        Color.clear
                    } else {
                        SpecimenCardFace(specimen: card.specimen)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .heroMatch(id: card.specimen.id, in: hero, enabled: !reduceMotion)
                    }
                }
                .frame(width: frame.cardSize.width, height: frame.cardSize.height)
                .shadow(color: FontPalette.ink.opacity(0.08 + 0.1 * min(lift, 1)), radius: 6 + 8 * lift, y: 4 + 6 * lift)
                .scaleEffect(card.pose.scale)
                .rotationEffect(.degrees(card.pose.rotation))
                .opacity(card.pose.opacity)
                .position(x: card.pose.center.x, y: card.pose.center.y)
                .zIndex(card.pose.zIndex)
                .onTapGesture { open(card.specimen.id) }
                .allowsHitTesting(card.isVisible)
                .accessibilityHidden(!card.isVisible)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(card.specimen.name), \(card.specimen.category.title)"))
                .accessibilityValue(Text(card.specimen.sample))
                .accessibilityHint(Text("Double-tap to open the specimen."))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open(card.specimen.id) }
            }
        }
        .frame(width: width, height: frame.contentHeight, alignment: .topLeading)
    }

    // MARK: Actions

    private func select(_ chip: FontFilter) {
        guard chip != filter else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.75)) {
            filter = chip
        }
        engine.setFilter(chip)
        chipTaps &+= 1
        isAnimating = true
    }

    private func shuffle() {
        engine.shuffle()
        isAnimating = true
    }

    private func open(_ id: String) {
        withAnimation(heroAnimation) { openID = id }
    }

    private func close() {
        withAnimation(heroAnimation) { openID = nil }
    }

    private var heroAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.48, dampingFraction: 0.82)
    }
}

// MARK: - Split-flap cell

/// One character on the flip board: a top and bottom half, with a flap that falls from the old
/// font to the new one (top half folds down to 90°, then the bottom half lands).
struct FlapCell: View {
    let character: String
    let from: Font
    let to: Font
    let progress: Double
    let size: CGSize

    var body: some View {
        let falling = progress < 1
        ZStack {
            // Behind the flap: the new glyph's top half, the old glyph's bottom half.
            half(to, top: true)
            half(falling ? from : to, top: false)
            if falling {
                if progress < 0.5 {
                    half(from, top: true)
                        .brightness(-0.25 * progress)
                        .rotation3DEffect(.degrees(-180 * progress), axis: (x: 1, y: 0, z: 0),
                                          anchor: .center, perspective: 0.5)
                } else {
                    half(to, top: false)
                        .brightness(-0.25 * (1 - progress))
                        .rotation3DEffect(.degrees(180 * (1 - progress)), axis: (x: 1, y: 0, z: 0),
                                          anchor: .center, perspective: 0.5)
                }
            }
            // The hinge.
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1.5)
        .accessibilityHidden(true)
    }

    private func half(_ font: Font, top: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.width * 0.16, style: .continuous)
                .fill(top ? FontPalette.flapTop : FontPalette.flapBottom)
            Text(character)
                .font(font)
                .foregroundStyle(FontPalette.flapInk)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(width: size.width, height: size.height)
        .mask(alignment: top ? .top : .bottom) {
            Rectangle().frame(height: size.height / 2)
        }
    }
}

// MARK: - Cards

/// The face of a specimen card: category tag, a big "Aa", the family name and its sample.
/// Scales to whatever frame it is given (the detail view shows it large).
public struct SpecimenCardFace: View {
    public let specimen: FontSpecimen
    public var large: Bool

    public init(specimen: FontSpecimen, large: Bool = false) {
        self.specimen = specimen
        self.large = large
    }

    public var body: some View {
        let tint = FontPalette.tint(specimen.category)
        VStack(alignment: .leading, spacing: large ? 8 : 4) {
            HStack {
                Text(specimen.category.title.uppercased())
                    .font(.system(size: large ? 12 : 10, weight: .heavy, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.14), in: Capsule())
                Spacer(minLength: 4)
                Text(specimen.weights.count == 1 ? "1 weight" : "\(specimen.weights.count) weights")
                    .font(.system(size: large ? 12 : 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(FontPalette.inkSoft)
            }
            Spacer(minLength: 0)
            Text("Aa")
                .font(specimen.swiftUIFont(size: large ? 110 : 64))
                .foregroundStyle(FontPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, alignment: large ? .center : .leading)
            Spacer(minLength: 0)
            Text(specimen.name)
                .font(.system(size: large ? 22 : 15, weight: .bold, design: .rounded))
                .foregroundStyle(FontPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(large ? specimen.note : specimen.sample)
                .font(large ? .system(size: 14, weight: .regular, design: .rounded) : specimen.swiftUIFont(size: 13))
                .foregroundStyle(FontPalette.inkSoft)
                .lineLimit(large ? 2 : 1)
                .minimumScaleFactor(0.7)
        }
        .padding(large ? 20 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack(alignment: .topTrailing) {
                FontPalette.card
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: large ? 220 : 120, height: large ? 220 : 120)
                    .offset(x: large ? 70 : 44, y: large ? -90 : -52)
            }
        }
    }
}

// MARK: - Detail

/// The opened specimen: the card, grown, then editable sample text, size and weight sliders
/// and the full glyph strip.
struct SpecimenDetailView: View {
    let specimen: FontSpecimen
    let hero: Namespace.ID
    let reduceMotion: Bool
    let close: () -> Void

    @State private var state: SpecimenDetailState
    @State private var text: String
    @FocusState private var editing: Bool

    init(specimen: FontSpecimen, hero: Namespace.ID, reduceMotion: Bool, close: @escaping () -> Void) {
        self.specimen = specimen
        self.hero = hero
        self.reduceMotion = reduceMotion
        self.close = close
        _state = State(initialValue: SpecimenDetailState(specimen: specimen))
        _text = State(initialValue: SpecimenDetailState.defaultSample)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            FontPalette.ink.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)
                .accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SpecimenCardFace(specimen: specimen, large: true)
                        .frame(height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .heroMatch(id: specimen.id, in: hero, enabled: !reduceMotion)
                        .shadow(color: FontPalette.ink.opacity(0.2), radius: 20, y: 12)
                        .accessibilityElement(children: .combine)
                    controls
                        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 18)))
                }
                .padding(.horizontal, 20)
                .padding(.top, 64)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(FontPalette.ink)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.9), in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel(Text("Close"))
        }
        .transition(.opacity)
        .hapticFeedback(trigger: state.weightSteps) { old, new in new != old ? .selection : nil }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(specimen.name))
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                label("Sample", trailing: "\(state.sampleText.count)/\(SpecimenDetailState.maxSampleLength)")
                TextField(SpecimenDetailState.defaultSample, text: $text, axis: .vertical)
                    .font(specimen.swiftUIFont(size: state.size, weight: state.weight))
                    .foregroundStyle(FontPalette.ink)
                    .focused($editing)
                    .lineLimit(1...4)
                    .onChange(of: text) { _, new in
                        state.setSampleText(new)
                        if new != state.sampleText { text = state.sampleText }
                    }
                    .padding(14)
                    .background(FontPalette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel(Text("Sample text"))
            }
            VStack(alignment: .leading, spacing: 4) {
                label("Size", trailing: "\(Int(state.size.rounded())) pt")
                Slider(value: Binding(get: { state.size }, set: { state.setSize($0) }),
                       in: SpecimenDetailState.sizeRange)
                    .tint(FontPalette.tint(specimen.category))
                    .accessibilityLabel(Text("Size"))
                    .accessibilityValue(Text("\(Int(state.size.rounded())) points"))
            }
            VStack(alignment: .leading, spacing: 4) {
                label("Weight", trailing: state.weight.title)
                if state.weightStops > 1 {
                    Slider(value: Binding(get: { state.weightPosition }, set: { state.setWeightPosition($0) }),
                           in: 0...1, step: 1 / Double(state.weightStops - 1))
                        .tint(FontPalette.tint(specimen.category))
                        .accessibilityLabel(Text("Weight"))
                        .accessibilityValue(Text(state.weight.title))
                } else {
                    Text("This family has a single weight.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(FontPalette.inkSoft)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                label("Glyphs", trailing: "\(GlyphStrip.all.count)")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(GlyphStrip.all, id: \.self) { glyph in
                            Text(glyph)
                                .font(specimen.swiftUIFont(size: 30, weight: state.weight))
                                .foregroundStyle(FontPalette.ink)
                                .frame(width: 46, height: 56)
                                .background(FontPalette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .frame(height: 56)
                .accessibilityLabel(Text("Glyph strip: A to Z, a to z, digits and punctuation"))
            }
        }
        .padding(18)
        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func label(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(1)
            Spacer()
            Text(trailing)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(FontPalette.inkSoft)
    }

    private func dismiss() {
        editing = false
        close()
    }
}

// MARK: - Fonts

extension FontSpecimen {
    /// The SwiftUI font for this specimen at a fixed point size. Named families are looked up by
    /// family name; if one is missing on a device, the category's system design stands in.
    public func swiftUIFont(size: CGFloat, weight: FontWeightStep? = nil) -> Font {
        let w = (weight.map(nearestWeight(to:)) ?? displayWeight).swiftUIWeight
        switch source {
        case .system(let design):
            return .system(size: size, weight: w, design: design.swiftUIDesign)
        case .named(let family):
            guard FontAvailability.isInstalled(family) else {
                return .system(size: size, weight: w, design: fallbackDesign.swiftUIDesign)
            }
            return .custom(family, fixedSize: size).weight(w)
        }
    }

    /// False when a named family isn't installed (the view is using the fallback design).
    public var isAvailable: Bool {
        guard let family = source.familyName else { return true }
        return FontAvailability.isInstalled(family)
    }
}

/// Which font families this device has (asked once, via Core Text).
enum FontAvailability {
    static let families: Set<String> = {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return Set(names)
    }()

    static func isInstalled(_ family: String) -> Bool { families.contains(family) }
}

extension FontWeightStep {
    var swiftUIWeight: Font.Weight {
        switch self {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

extension SystemFontDesign {
    var swiftUIDesign: Font.Design {
        switch self {
        case .default: .default
        case .serif: .serif
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }
}

// MARK: - Palette

enum FontPalette {
    static let paper = Color(red: 1.0, green: 0.968, blue: 0.925)
    static let card = Color(red: 1.0, green: 0.992, blue: 0.973)
    static let ink = Color(red: 0.231, green: 0.165, blue: 0.125)
    static let inkSoft = Color(red: 0.541, green: 0.435, blue: 0.369)
    static let flapTop = Color(red: 0.17, green: 0.15, blue: 0.16)
    static let flapBottom = Color(red: 0.13, green: 0.115, blue: 0.125)
    static let flapInk = Color(red: 1.0, green: 0.95, blue: 0.86)

    static func tint(_ category: FontCategory) -> Color {
        switch category {
        case .serif: Color(red: 0.91, green: 0.36, blue: 0.29)
        case .sans: Color(red: 0.20, green: 0.47, blue: 0.93)
        case .rounded: Color(red: 0.13, green: 0.66, blue: 0.52)
        case .mono: Color(red: 0.49, green: 0.33, blue: 0.86)
        case .display: Color(red: 0.88, green: 0.58, blue: 0.10)
        case .script: Color(red: 0.89, green: 0.29, blue: 0.56)
        }
    }
}

// MARK: - Engine

struct FontCardFrame {
    var specimen: FontSpecimen
    var pose: CardPose
    /// False for cards fading out after a filter change.
    var isVisible: Bool
}

struct FontFrame {
    var cells: [FlipCellState]
    var target: Int
    var isHeadlineSettled: Bool
    var cards: [FontCardFrame]
    var cardSize: CGSize
    var contentHeight: CGFloat
    var isSettled: Bool
    var tickCount: Int
    var settleCount: Int
    var landingCount: Int
    var lastTickIntensity: Double
}

/// Holds the deterministic model outside SwiftUI's dependency tracking. The TimelineView steps
/// it once per frame and pauses when everything has settled.
final class FontEngine {
    private var model: FontCollectionModel
    private var lastDate: Date?
    private var started = false
    private var lastTickIntensity = 0.5

    init(catalog: FontCatalog, headline: String, seed: UInt64) {
        model = FontCollectionModel(catalog: catalog, headline: headline, seed: seed)
    }

    func setFilter(_ filter: FontFilter) { model.setFilter(filter) }
    func shuffle() { model.shuffleHeadline() }

    func frame(at date: Date, width: Double, reduceMotion: Bool) -> FontFrame {
        if !started {
            started = true
            if reduceMotion {
                // Show the launch font straight away instead of flapping.
                model.reduceMotion = true
                model.shuffleHeadline(to: model.flipTarget)
            }
        }
        model.reduceMotion = reduceMotion
        if width > 0 { model.resize(width: width) }
        if let lastDate {
            for event in model.step(date.timeIntervalSince(lastDate)) {
                if case .flipTick(let intensity) = event { lastTickIntensity = intensity }
            }
        }
        lastDate = model.isSettled ? nil : date

        let visible = Set(model.visibleIDs)
        let poses = model.cardPoses
        let cards: [FontCardFrame] = model.catalog.specimens.compactMap { specimen in
            guard let pose = poses[specimen.id] else { return nil }
            return FontCardFrame(specimen: specimen, pose: pose, isVisible: visible.contains(specimen.id))
        }
        return FontFrame(cells: model.headlineCells, target: model.flipTarget,
                         isHeadlineSettled: model.isHeadlineSettled, cards: cards,
                         cardSize: CGSize(width: model.layout.cardWidth, height: model.layout.cardHeight),
                         contentHeight: CGFloat(model.contentHeight), isSettled: model.isSettled,
                         tickCount: model.tickCount, settleCount: model.settleCount,
                         landingCount: model.landingCount, lastTickIntensity: lastTickIntensity)
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

    /// Haptics on iOS only (a Mac has no Taptic Engine under the content).
    @ViewBuilder
    func hapticFeedback<T: Equatable>(trigger: T, _ feedback: @escaping (T, T) -> SensoryFeedback?) -> some View {
        #if os(iOS)
        sensoryFeedback(trigger: trigger, feedback)
        #else
        self
        #endif
    }
}

// MARK: - Previews

#Preview("Font Collection") {
    FontCollection(seed: 68)   // settles on Didot
}

#Preview("Card") {
    SpecimenCardFace(specimen: FontCatalog.standard.specimens[13])
        .frame(width: 170, height: 196)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding()
}
#endif
