import Foundation

/// The four moments of the piece.
public enum BoutiquePhase: Equatable, Sendable {
    /// The word with a few figures around it.
    case rest
    /// Dozens of figures fill the screen.
    case burst
    /// One figure stays while the rest fade and slide away.
    case focusing(Int)
    /// The kept figure is the hero of the detail view.
    case detail(Int)

    public var selected: Int? {
        switch self {
        case .focusing(let i), .detail(let i): return i
        default: return nil
        }
    }
}

public enum BoutiqueEvent: Equatable, Sendable {
    case tapBackground, scroll, tapFigure(Int), focusSettled, close
}

/// Where and how one figure is drawn for a phase.
public struct FigurePlacement: Equatable, Sendable {
    public var center: Vec2
    public var scale: Double
    public var tilt: Double
    public var opacity: Double
}

public struct BoutiqueModel: Equatable, Sendable {
    public var layout: BoutiqueLayout
    public private(set) var phase: BoutiquePhase = .rest
    /// Where the last burst started; the exit and return ripples start at the selection.
    public private(set) var origin: Vec2
    public let figures: [FigureSpec]
    public let rest: [(center: Vec2, tilt: Double)]
    public let burst: [(center: Vec2, tilt: Double)]

    public init(layout: BoutiqueLayout) {
        self.layout = layout
        figures = FigureSpec.crowd(count: layout.figureCount, seed: layout.seed)
        rest = layout.restPlacements()
        burst = layout.burstPlacements()
        origin = layout.wordRect.center
    }

    public static func == (a: BoutiqueModel, b: BoutiqueModel) -> Bool {
        a.layout == b.layout && a.phase == b.phase && a.origin == b.origin
    }

    /// Applies an event; returns true when the phase changed. Invalid events are ignored.
    @discardableResult
    public mutating func send(_ event: BoutiqueEvent, at point: Vec2? = nil) -> Bool {
        let old = phase
        switch (phase, event) {
        case (.rest, .tapBackground), (.rest, .scroll), (.rest, .tapFigure):
            origin = point ?? Vec2(layout.width / 2, layout.height)
            phase = .burst
        case (.burst, .tapFigure(let i)) where figures.indices.contains(i):
            phase = .focusing(i)
        case (.focusing(let i), .focusSettled):
            phase = .detail(i)
        case (.focusing(let i), .close), (.detail(let i), .close):
            origin = burst[i].center
            phase = .burst
        default:
            break
        }
        return phase != old
    }

    public func placement(of i: Int, in phase: BoutiquePhase) -> FigurePlacement {
        let restCenter = layout.wordRect.center
        switch phase {
        case .rest:
            if i < rest.count { return FigurePlacement(center: rest[i].center, scale: BoutiqueLayout.restScale, tilt: rest[i].tilt, opacity: 1) }
            return FigurePlacement(center: Vec2.lerp(restCenter, burst[i].center, 0.15), scale: layout.burstScale * 0.4, tilt: 0, opacity: 0)
        case .burst:
            return FigurePlacement(center: burst[i].center, scale: layout.burstScale, tilt: burst[i].tilt, opacity: 1)
        case .focusing(let s), .detail(let s):
            if i == s { return FigurePlacement(center: burst[i].center, scale: layout.burstScale, tilt: 0, opacity: 1) }
            let away = layout.exitOffset(for: burst[i].center, awayFrom: burst[s].center) * 0.35
            return FigurePlacement(center: burst[i].center + away, scale: layout.burstScale * 0.9, tilt: burst[i].tilt, opacity: 0)
        }
    }

    /// Delays for the transition into the current phase.
    public func delays(reduceMotion: Bool = false) -> [Double] {
        let n = figures.count
        if reduceMotion { return Array(repeating: 0, count: n) }
        let centers = burst.map(\.center)
        switch phase {
        case .rest:
            return Array(repeating: 0, count: n)
        case .burst:
            return layout.staggerDelays(from: origin, positions: centers, spread: BoutiqueLayout.burstSpread)
        case .focusing(let s), .detail(let s):
            var d = layout.staggerDelays(from: centers[s], positions: centers, spread: BoutiqueLayout.exitSpread, jitter: 0.02)
            d[s] = 0
            return d
        }
    }
}
