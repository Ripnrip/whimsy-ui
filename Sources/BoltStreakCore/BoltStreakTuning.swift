import Foundation

/// Shared numbers for the bolt streak. The SwiftUI view, the tests and
/// `webports/boltstreak-core.mjs` all read these; the web port copies the values.
public enum BoltStreakTuning {
    public static let sceneWidth = 390.0
    public static let sceneHeight = 844.0

    public static let dayCount = 7
    public static let ignitionDuration = 0.64
    /// A stalled frame advances by at most this much. 1/60 s steps pass through whole.
    public static let maxFrame = 0.05

    public static let wordmark = "BOLT"
    public static let caption = "THIS WEEK"
    public static let ofSeven = "OF 7"
    public static let wordmarkY = 86.0
    public static let captionY = 116.0
    public static let readoutY = 500.0
    public static let ofSevenY = 548.0

    public static let weeklyWidth = 150.0
    public static let weeklyHeight = 292.0
    public static let weeklyY = 150.0
    public static var weeklyRect: BoltRect {
        BoltRect(
            x: (sceneWidth - weeklyWidth) / 2,
            y: weeklyY,
            width: weeklyWidth,
            height: weeklyHeight
        )
    }
    public static let weeklyStroke = 20.0
    public static let weeklyHead = 11.0
    public static let weeklyBevel = 2.2

    public static let dayWidth = 28.0
    public static let dayHeight = 74.0
    public static let dayStride = 48.0
    public static let dayOriginY = 592.0
    public static let dayStroke = 4.5
    public static let dayHead = 4.0
    public static let dayBevel = 0.8
    public static let labelGap = 18.0
    public static let hitSlop = 16.0

    public static var dayRowWidth: Double { dayStride * Double(dayCount - 1) + dayWidth }
    public static var dayOriginX: Double { (sceneWidth - dayRowWidth) / 2 }

    public static func dayRect(index: Int) -> BoltRect {
        let clamped = min(max(index, 0), dayCount - 1)
        return BoltRect(
            x: dayOriginX + Double(clamped) * dayStride,
            y: dayOriginY,
            width: dayWidth,
            height: dayHeight
        )
    }

    public static func dayRect(for day: Weekday) -> BoltRect { dayRect(index: day.rawValue) }

    public static func labelY() -> Double { dayOriginY + dayHeight + labelGap }

    /// Static perspective on the day row. Reduce Motion keeps it; it is not a travel.
    public static let tiltDegrees = 22.0
    public static let tiltPerspective = 0.6

    /// Settled burn. The pulse is added only while a bolt is igniting, and only
    /// when Reduce Motion is off.
    public static let glowSettled = 0.62
    public static let glowPulse = 0.28
    public static let glowOmega = 18.0
    public static let glowBlur = 14.0

    public static let reflectionOpacity = 0.26
    public static let reflectionGap = 8.0

    public static let backgroundTop = BoltRGB(0.09, 0.10, 0.11)
    public static let backgroundBottom = BoltRGB(0.05, 0.05, 0.06)
    public static let spill = BoltRGB(1.0, 0.62, 0.16)
    public static let zinc = BoltRGB(0.42, 0.45, 0.48)
    public static let zincHighlight = BoltRGB(0.75, 0.78, 0.82)
    public static let zincShadow = BoltRGB(0.14, 0.15, 0.17)
    public static let gold = BoltRGB(1.0, 0.76, 0.22)
    public static let goldCore = BoltRGB(1.0, 0.94, 0.72)
    public static let head = BoltRGB(1, 1, 1)
    public static let labelDim = BoltRGB(0.55, 0.57, 0.60)
    public static let labelLit = BoltRGB(1.0, 0.82, 0.42)
    public static let wordmarkColor = BoltRGB(0.86, 0.88, 0.90)
    public static let captionColor = BoltRGB(0.62, 0.58, 0.48)
    public static let plate = BoltRGB(1, 1, 1)

    public static let accessibilityLabel = "Weekly bolt streak"
    public static let accessibilityHint = "Marks today and lights its bolt."
    public static let markTodayAction = "Mark today"

    /// How many 1/60 s steps it takes to finish one ignition. Locked so the reel
    /// and the web port share a frame, not a rounded division of 0.64.
    public static let burnFrames = 39
}

/// One sRGB colour. Channels are 0…1. The canvas port copies the same triples.
public struct BoltRGB: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// A rectangle in scene points, y down. The core stays off CoreGraphics.
public struct BoltRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    public func contains(_ point: Vec2, slop: Double = 0) -> Bool {
        point.x >= x - slop && point.x <= x + width + slop
            && point.y >= y - slop && point.y <= y + height + slop
    }
}

/// Monday-first day of the week. `rawValue` is the column, 0 through 6.
public enum Weekday: Int, CaseIterable, Hashable, Sendable, Comparable {
    case monday = 0
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var label: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "S"
        }
    }

    public var name: String {
        switch self {
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        case .sunday: "Sunday"
        }
    }

    /// Lowercase name used by the golden trace and the web port.
    public var traceName: String {
        switch self {
        case .monday: "monday"
        case .tuesday: "tuesday"
        case .wednesday: "wednesday"
        case .thursday: "thursday"
        case .friday: "friday"
        case .saturday: "saturday"
        case .sunday: "sunday"
        }
    }

    /// Gregorian `Calendar` weekday (1 = Sunday … 7 = Saturday) mapped onto this type.
    /// Anything outside 1…7 is Monday, so a broken calendar does not invent an eighth day.
    public static func on(_ date: Date, calendar: Calendar = .current) -> Weekday {
        switch calendar.component(.weekday, from: date) {
        case 1: .sunday
        case 2: .monday
        case 3: .tuesday
        case 4: .wednesday
        case 5: .thursday
        case 6: .friday
        case 7: .saturday
        default: .monday
        }
    }

    /// The device's today. Tests pass an explicit day; this is the view's default.
    public static var current: Weekday { on(Date(), calendar: .current) }
}
