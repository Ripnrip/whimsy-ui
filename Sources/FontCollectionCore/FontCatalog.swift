import Foundation

/// The shelf a specimen sits on (and the filter chips).
public enum FontCategory: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case serif, sans, rounded, mono, display, script

    /// Chip / label title, e.g. "Serif".
    public var title: String {
        switch self {
        case .serif: "Serif"
        case .sans: "Sans"
        case .rounded: "Rounded"
        case .mono: "Mono"
        case .display: "Display"
        case .script: "Script"
        }
    }

    /// Order used when sorting by category.
    public var sortIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// The four designs of the system font (`Font.Design` without SwiftUI).
public enum SystemFontDesign: String, CaseIterable, Equatable, Hashable, Sendable, Codable {
    case `default`, serif, rounded, monospaced
}

/// Where a specimen's glyphs come from. Nothing is bundled: either the system font in one of
/// its designs, or a family that ships with iOS 17 and macOS 14 (looked up by family name).
public enum FontSource: Equatable, Hashable, Sendable {
    case system(SystemFontDesign)
    case named(family: String)

    /// The family name for `.named`, nil for the system font.
    public var familyName: String? {
        if case .named(let family) = self { return family }
        return nil
    }
}

/// Nine standard weights (CSS 100…900), mirroring `Font.Weight`.
public enum FontWeightStep: Int, CaseIterable, Comparable, Equatable, Hashable, Sendable, Codable {
    case ultraLight = 100, thin = 200, light = 300, regular = 400, medium = 500
    case semibold = 600, bold = 700, heavy = 800, black = 900

    public var cssWeight: Int { rawValue }

    public var title: String {
        switch self {
        case .ultraLight: "Ultralight"
        case .thin: "Thin"
        case .light: "Light"
        case .regular: "Regular"
        case .medium: "Medium"
        case .semibold: "Semibold"
        case .bold: "Bold"
        case .heavy: "Heavy"
        case .black: "Black"
        }
    }

    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// One font in the collection.
public struct FontSpecimen: Identifiable, Equatable, Hashable, Sendable {
    /// Stable identifier (e.g. "didot").
    public var id: String
    /// Display name, e.g. "Didot" or "New York".
    public var name: String
    public var source: FontSource
    public var category: FontCategory
    /// A short sample word or phrase for the card.
    public var sample: String
    /// One line of trivia for the detail view.
    public var note: String
    /// Weights the family actually has, ascending. The detail view's weight slider snaps to these.
    public var weights: [FontWeightStep]
    /// The weight cards and the flip board use.
    public var displayWeight: FontWeightStep
    /// The system design to fall back to if the family is missing on a device.
    public var fallbackDesign: SystemFontDesign

    public init(id: String, name: String, source: FontSource, category: FontCategory, sample: String,
                note: String = "", weights: [FontWeightStep] = FontWeightStep.allCases,
                displayWeight: FontWeightStep = .regular, fallbackDesign: SystemFontDesign? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.category = category
        self.sample = sample
        self.note = note
        let sorted = Array(Set(weights)).sorted()
        self.weights = sorted.isEmpty ? [.regular] : sorted
        self.displayWeight = self.weights.contains(displayWeight) ? displayWeight : Self.nearest(displayWeight, in: self.weights)
        self.fallbackDesign = fallbackDesign ?? category.defaultFallback
    }

    /// The supported weight closest to `weight` (ties go to the lighter one).
    public func nearestWeight(to weight: FontWeightStep) -> FontWeightStep { Self.nearest(weight, in: weights) }

    static func nearest(_ w: FontWeightStep, in list: [FontWeightStep]) -> FontWeightStep {
        list.min { abs($0.rawValue - w.rawValue) < abs($1.rawValue - w.rawValue) } ?? .regular
    }

    /// True when the specimen matches a search query (name or category, case- and diacritic-insensitive).
    public func matches(query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return name.range(of: q, options: opts) != nil || category.title.range(of: q, options: opts) != nil
    }
}

extension FontCategory {
    /// The system design that best stands in for this category.
    public var defaultFallback: SystemFontDesign {
        switch self {
        case .serif, .display, .script: .serif
        case .sans: .default
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }
}

/// What the chips select.
public enum FontFilter: Equatable, Hashable, Sendable {
    case all
    case category(FontCategory)

    /// "All" followed by every category, in chip order.
    public static var chips: [FontFilter] { [.all] + FontCategory.allCases.map { .category($0) } }

    public var title: String {
        switch self {
        case .all: "All"
        case .category(let c): c.title
        }
    }

    public func includes(_ specimen: FontSpecimen) -> Bool {
        switch self {
        case .all: true
        case .category(let c): specimen.category == c
        }
    }
}

public enum FontSortOrder: String, CaseIterable, Equatable, Hashable, Sendable {
    /// The catalog's own order.
    case catalog
    /// Alphabetical by name.
    case name
    /// By category (chip order), then catalog order.
    case category
}

/// An ordered list of specimens with filtering and sorting.
public struct FontCatalog: Equatable, Sendable {
    public var specimens: [FontSpecimen]

    /// Duplicate ids are dropped (first one wins) so ids can key views safely.
    public init(_ specimens: [FontSpecimen]) {
        var seen = Set<String>()
        self.specimens = specimens.filter { seen.insert($0.id).inserted }
    }

    public var count: Int { specimens.count }
    public var ids: [String] { specimens.map(\.id) }

    public func specimen(id: String) -> FontSpecimen? { specimens.first { $0.id == id } }
    public func index(of id: String) -> Int? { specimens.firstIndex { $0.id == id } }

    /// The specimens a filter, query and sort order select, in display order.
    public func visible(filter: FontFilter = .all, query: String = "", sort: FontSortOrder = .catalog) -> [FontSpecimen] {
        let picked = specimens.enumerated().filter { filter.includes($0.element) && $0.element.matches(query: query) }
        let sorted: [(offset: Int, element: FontSpecimen)]
        switch sort {
        case .catalog:
            sorted = picked
        case .name:
            sorted = picked.sorted {
                let c = $0.element.name.compare($1.element.name, options: [.caseInsensitive, .diacriticInsensitive])
                return c == .orderedSame ? $0.offset < $1.offset : c == .orderedAscending
            }
        case .category:
            sorted = picked.sorted {
                let a = $0.element.category.sortIndex, b = $1.element.category.sortIndex
                return a == b ? $0.offset < $1.offset : a < b
            }
        }
        return sorted.map(\.element)
    }

    /// How many specimens each chip would show (for chip badges).
    public func count(for filter: FontFilter) -> Int { specimens.filter(filter.includes).count }

    /// Chips worth showing: "All" plus every category that has at least one specimen.
    public var availableFilters: [FontFilter] { FontFilter.chips.filter { count(for: $0) > 0 } }
}

extension FontCatalog {
    /// Sixteen faces that ship with both iOS 17 and macOS 14: the four system designs plus
    /// twelve named families (`Font.custom` by family name). No font files are bundled.
    public static let standard = FontCatalog([
        FontSpecimen(id: "sf-pro", name: "SF Pro", source: .system(.default), category: .sans,
                     sample: "Hello, whimsy", note: "Apple's system face, with optical sizes baked in.",
                     displayWeight: .semibold),
        FontSpecimen(id: "avenir-next", name: "Avenir Next", source: .named(family: "Avenir Next"), category: .sans,
                     sample: "Quiet confidence", note: "Adrian Frutiger's geometric sans, redrawn in 2004.",
                     weights: [.ultraLight, .regular, .medium, .semibold, .bold, .heavy], displayWeight: .medium),
        FontSpecimen(id: "futura", name: "Futura", source: .named(family: "Futura"), category: .sans,
                     sample: "Bauhaus 1927", note: "Paul Renner's circles and triangles. It went to the Moon.",
                     weights: [.medium, .bold], displayWeight: .medium),
        FontSpecimen(id: "new-york", name: "New York", source: .system(.serif), category: .serif,
                     sample: "Once upon a time", note: "The system serif, tuned to sit beside SF Pro.",
                     displayWeight: .medium),
        FontSpecimen(id: "georgia", name: "Georgia", source: .named(family: "Georgia"), category: .serif,
                     sample: "Read me slowly", note: "Matthew Carter drew it for screens in 1993.",
                     weights: [.regular, .bold]),
        FontSpecimen(id: "baskerville", name: "Baskerville", source: .named(family: "Baskerville"), category: .serif,
                     sample: "Ink & parchment", note: "A 1750s transitional serif from Birmingham.",
                     weights: [.regular, .semibold, .bold]),
        FontSpecimen(id: "rockwell", name: "Rockwell", source: .named(family: "Rockwell"), category: .serif,
                     sample: "Slab & sturdy", note: "A geometric slab serif from Monotype, 1934.",
                     weights: [.regular, .bold], displayWeight: .bold),
        FontSpecimen(id: "sf-rounded", name: "SF Rounded", source: .system(.rounded), category: .rounded,
                     sample: "Squishy & kind", note: "SF Pro with every terminal softened.",
                     displayWeight: .bold),
        FontSpecimen(id: "chalkboard", name: "Chalkboard SE", source: .named(family: "Chalkboard SE"), category: .rounded,
                     sample: "Recess at 10:15", note: "Classroom chalk, minus the dust.",
                     weights: [.light, .regular, .bold]),
        FontSpecimen(id: "marker-felt", name: "Marker Felt", source: .named(family: "Marker Felt"), category: .rounded,
                     sample: "Do not erase!", note: "Felt-tip lettering in Thin and Wide.",
                     weights: [.light, .bold], displayWeight: .bold),
        FontSpecimen(id: "sf-mono", name: "SF Mono", source: .system(.monospaced), category: .mono,
                     sample: "let x = 42", note: "The system monospace, from Xcode and Terminal.",
                     displayWeight: .medium),
        FontSpecimen(id: "menlo", name: "Menlo", source: .named(family: "Menlo"), category: .mono,
                     sample: "$ swift test", note: "Bitstream Vera Mono, tweaked by Apple in 2009.",
                     weights: [.regular, .bold]),
        FontSpecimen(id: "american-typewriter", name: "American Typewriter", source: .named(family: "American Typewriter"),
                     category: .mono, sample: "Dear diary,", note: "Proportional, but it remembers the keys.",
                     weights: [.light, .regular, .semibold, .bold], fallbackDesign: .monospaced),
        FontSpecimen(id: "didot", name: "Didot", source: .named(family: "Didot"), category: .display,
                     sample: "Vogue, darling", note: "Hairlines and high contrast from 1780s Paris.",
                     weights: [.regular, .bold]),
        FontSpecimen(id: "copperplate", name: "Copperplate", source: .named(family: "Copperplate"), category: .display,
                     sample: "EST. 1901", note: "All small caps, like an engraved calling card.",
                     weights: [.light, .regular, .bold]),
        FontSpecimen(id: "snell-roundhand", name: "Snell Roundhand", source: .named(family: "Snell Roundhand"),
                     category: .script, sample: "With love", note: "Copperplate script after Charles Snell, 1694.",
                     weights: [.regular, .bold, .black]),
    ])
}
