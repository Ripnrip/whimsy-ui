import Foundation

/// The whole showcase as one deterministic state machine: catalog + filter, the regroup in
/// flight, the flip-board headline and the open detail. Drive it with ``step(_:)`` once per
/// frame; each step returns the haptics that came due, already rate-limited.
public struct FontCollectionModel: Equatable, Sendable {
    public let catalog: FontCatalog
    /// Characters in the flip-board headline.
    public let headline: String
    public var reduceMotion: Bool

    public private(set) var filter: FontFilter = .all
    public private(set) var sort: FontSortOrder = .catalog
    /// Ids visible now (after the latest filter change), in slot order.
    public private(set) var visibleIDs: [String]
    public private(set) var layout: SpecimenGridLayout
    public private(set) var plan: RegroupPlan
    public private(set) var planStart: Double = 0
    public private(set) var flipBoard: FlipBoardSchedule
    public private(set) var flipStart: Double = 0
    /// Catalog index the board settled (or is settling) on.
    public var flipTarget: Int { flipBoard.target }
    public private(set) var detail: SpecimenDetailState?
    public private(set) var time: Double = 0
    /// Haptics delivered so far, by kind (handy as `sensoryFeedback` triggers).
    public private(set) var tickCount = 0
    public private(set) var settleCount = 0
    public private(set) var landingCount = 0

    private var rng: SeededRandom
    private var gate = HapticGate()
    /// Schedule-relative times up to which haptics were already collected (−∞ = from the start,
    /// so an event at exactly t = 0 is included).
    private var flipCursor = -Double.infinity
    private var planCursor = -Double.infinity
    private var pendingChip = false

    public init(catalog: FontCatalog = .standard, headline: String = "Fontastic", width: Double = 393,
                seed: UInt64 = 0xF0_57, reduceMotion: Bool = false) {
        self.catalog = catalog
        self.headline = headline.isEmpty ? "Aa" : headline
        self.reduceMotion = reduceMotion
        var rng = SeededRandom(seed: seed)
        let ids = catalog.visible().map(\.id)
        visibleIDs = ids
        layout = SpecimenGridLayout(width: width)
        plan = RegroupPlan(from: ids, to: ids, layout: layout, seed: rng.next(), reduceMotion: true)
        let n = max(catalog.count, 1)
        let target = min(Int(rng.uniform(0...1) * Double(n)), n - 1)
        flipBoard = FlipBoardSchedule(fontCount: n, startFont: 0, target: target,
                                      columns: self.headline.count, seed: rng.next(), reduceMotion: reduceMotion)
        self.rng = rng
    }

    // MARK: Commands

    /// Selects a chip. Cards shuffle into their new slots (or crossfade with Reduce Motion).
    public mutating func setFilter(_ f: FontFilter) {
        guard f != filter else { return }
        filter = f
        regroup()
        pendingChip = true
    }

    public mutating func setSort(_ s: FontSortOrder) {
        guard s != sort else { return }
        sort = s
        regroup()
    }

    private mutating func regroup() {
        let next = catalog.visible(filter: filter, sort: sort).map(\.id)
        let current = currentOrderForReplan()
        plan = RegroupPlan(from: current, to: next, layout: layout, seed: rng.next(), reduceMotion: reduceMotion)
        planStart = time
        planCursor = -.infinity
        visibleIDs = next
    }

    /// Ids to treat as "on screen" when a new regroup starts mid-flight: the previous target set
    /// (leavers that haven't faded yet just pop out, which is fine at that speed).
    private func currentOrderForReplan() -> [String] { visibleIDs }

    /// Replays the flip board from wherever it is to a fresh random font (never the current one
    /// when there's a choice). Pass `target` to pick it yourself.
    public mutating func shuffleHeadline(to target: Int? = nil) {
        let n = max(catalog.count, 1)
        let start = flipBoard.cell(column: 0, at: time - flipStart).visibleFont
        let goal: Int
        if let target {
            goal = target
        } else if n > 1 {
            // Uniform over every font except the one showing.
            let i = min(Int(rng.uniform(0...1) * Double(n - 1)), n - 2)
            goal = i >= start ? i + 1 : i
        } else {
            goal = 0
        }
        flipBoard = FlipBoardSchedule(fontCount: n, startFont: start, target: goal, columns: headline.count,
                                      seed: rng.next(), reduceMotion: reduceMotion)
        flipStart = time
        flipCursor = -.infinity
    }

    public mutating func open(_ id: String) {
        guard let s = catalog.specimen(id: id) else { return }
        detail = SpecimenDetailState(specimen: s)
    }

    public mutating func close() { detail = nil }

    /// Edits the open detail (no-op when closed). Weight changes that cross a detent emit a haptic
    /// on the next ``step(_:)``.
    public mutating func updateDetail(_ change: (inout SpecimenDetailState) -> Void) {
        guard var d = detail else { return }
        change(&d)
        detail = d
    }

    /// Re-lays the grid for a new width (no animation).
    public mutating func resize(width: Double) {
        let new = SpecimenGridLayout(columns: layout.columns, width: width, cardHeight: layout.cardHeight,
                                     spacing: layout.spacing, inset: layout.inset)
        guard new != layout else { return }
        layout = new
        plan = RegroupPlan(from: visibleIDs, to: visibleIDs, layout: new, seed: 0, reduceMotion: true)
        planStart = time - plan.duration - 1
        planCursor = time - planStart
    }

    // MARK: Simulation

    private var lastWeightSteps = 0

    /// Advances the clock and returns the haptics that came due (rate-limited, in time order).
    @discardableResult
    public mutating func step(_ dt: Double) -> [FontHapticEvent] {
        guard dt.isFinite, dt > 0 else { return [] }
        let t0 = time
        time += min(dt, 0.25)
        var due: [(time: Double, event: FontHapticEvent)] = []
        if pendingChip { due.append((t0, .chip)); pendingChip = false }
        due += flipBoard.hapticEvents(after: flipCursor, through: time - flipStart).map { ($0.time + flipStart, $0.event) }
        flipCursor = time - flipStart
        due += plan.landingEvents(after: planCursor, through: time - planStart).map { ($0.time + planStart, $0.event) }
        planCursor = time - planStart
        if let d = detail, d.weightSteps != lastWeightSteps { due.append((time, .weightStep)) }
        lastWeightSteps = detail?.weightSteps ?? 0
        var out: [FontHapticEvent] = []
        for e in due.sorted(by: { $0.time < $1.time }) where gate.admit(e.event, at: e.time) {
            out.append(e.event)
            switch e.event {
            case .flipTick: tickCount += 1
            case .settle: settleCount += 1
            case .landing: landingCount += 1
            default: break
            }
        }
        return out
    }

    // MARK: Read-outs for renderers

    /// Flip-board cells now.
    public var headlineCells: [FlipCellState] { flipBoard.cells(at: time - flipStart) }
    public var isHeadlineSettled: Bool { flipBoard.isSettled(at: time - flipStart) }
    public var isRegroupSettled: Bool { plan.isSettled(at: time - planStart) }
    /// True when nothing is animating (renderers can pause their timeline).
    public var isSettled: Bool { isHeadlineSettled && isRegroupSettled }

    /// Pose of every card on screen (including ones fading out), keyed by id.
    public var cardPoses: [String: CardPose] {
        let t = time - planStart
        var poses = plan.poses(at: t)
        if plan.isSettled(at: t) {
            // Drop leavers once gone.
            for f in plan.flights where f.kind == .leave { poses[f.id] = nil }
        }
        return poses
    }

    /// Scroll content height for the current cards.
    public var contentHeight: Double { layout.contentHeight(count: visibleIDs.count) }
}
