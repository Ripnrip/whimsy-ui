import Foundation

public enum ShelfEvent: Equatable, Sendable {
    /// The pull has just passed the commit distance (a light tick).
    case armed(Int)
    /// The book was let go past the threshold (or flicked), or activated by VoiceOver.
    case committed(Int)
    /// The card has started to open.
    case opened(Int)
    /// The book has landed back in its slot: the soft thunk. Exactly once per return.
    case seated(Int)
}

/// The shelf state machine: resting, dragging, lifting, turning, open, returning, seating.
public struct ShelfPullModel: Equatable, Sendable {
    public let layout: ShelfLayout
    public private(set) var phase = ShelfPhase.resting
    public private(set) var book: Int?
    /// Running clock, and the time spent in the current phase.
    public private(set) var time = 0.0
    public private(set) var phaseTime = 0.0
    /// The pull in points (upward positive) and whether it is past the commit distance.
    public private(set) var drag = 0.0
    public private(set) var isArmed = false
    public private(set) var returnKind = ShelfReturnKind.card
    public private(set) var releaseRise = 0.0
    public private(set) var lastRelease: ShelfRelease = .none
    public private(set) var reduceMotion: Bool
    public private(set) var seats = 0
    public private(set) var opens = 0
    public private(set) var commits = 0
    public private(set) var springBacks = 0
    private var dragBase = 0.0
    private var tracker = ShelfVelocityTracker()

    /// Longest step taken at once.
    public static let maxStep = 0.25

    public init(count: Int = ShelfLayout.defaultBooks, seed: UInt32 = ShelfLayout.defaultSeed, reduceMotion: Bool = false) {
        layout = ShelfLayout.make(count: count, seed: seed)
        self.reduceMotion = reduceMotion
    }

    public init(layout: ShelfLayout, reduceMotion: Bool = false) {
        self.layout = layout
        self.reduceMotion = reduceMotion
    }

    public var frame: ShelfFrame {
        ShelfTimeline.frame(layout: layout, phase: phase, book: book, time: phaseTime, drag: drag,
                            releaseRise: releaseRise, kind: returnKind, reduceMotion: reduceMotion)
    }

    /// A pull can start now (nothing is mid-flight, apart from a settling book or one springing back).
    public var canGrab: Bool { phase == .resting || phase == .seating || (phase == .returning && returnKind == .springBack) }
    /// The card is open long enough to be closed.
    public var canClose: Bool { phase == .open && phaseTime >= ShelfTimeline.closeLockout(reduceMotion: reduceMotion) }
    /// Whether anything is moving (the view pauses its timeline when false).
    public var isAnimating: Bool { phase != .resting && phase != .dragging && phase != .open }

    private func currentRise() -> Double { frame.book.map { frame.spines[$0].rise } ?? 0 }

    // MARK: input

    /// A finger lands on book `i`. Returns false if it can't be grabbed now.
    @discardableResult
    public mutating func pointerDown(book i: Int) -> Bool {
        guard i >= 0, i < layout.count, canGrab else { return false }
        var base = 0.0
        if phase == .returning {
            // grabbing the book that is springing back: carry on from where it is
            guard i == book else { return false }
            base = ShelfResistance.drag(forRise: currentRise(), height: layout.spines[i].height)
        }
        phase = .dragging; book = i; phaseTime = 0
        dragBase = base; drag = base; isArmed = false
        releaseRise = 0; lastRelease = .none
        tracker.reset()
        return true
    }

    /// The finger is `upward` points above where it landed (negative = below). Not-a-number is ignored.
    @discardableResult
    public mutating func pointerMoved(upward: Double, at timestamp: Double? = nil) -> [ShelfEvent] {
        guard phase == .dragging, let i = book, upward.isFinite else { return [] }
        drag = max(0, dragBase + upward)
        tracker.add(upward: upward, at: timestamp ?? time)
        let past = drag >= ShelfResistance.commitDistance(height: layout.spines[i].height)
        defer { isArmed = past }
        return past && !isArmed ? [.armed(i)] : []
    }

    /// The finger lifts: commit (the book comes out) or spring back (or nothing, for a tap).
    @discardableResult
    public mutating func pointerUp(at timestamp: Double? = nil) -> [ShelfEvent] {
        guard phase == .dragging, let i = book else { return [] }
        let h = layout.spines[i].height
        let rise = ShelfResistance.rise(forDrag: drag, height: h)
        let release = ShelfResistance.decide(drag: drag, velocity: tracker.velocity(at: timestamp ?? time), height: h)
        lastRelease = release
        isArmed = false
        switch release {
        case .none:
            reset()
            return []
        case .springBack:
            springBacks += 1
            releaseRise = rise
            enter(.returning, kind: .springBack)
            return []
        case .commitDrag, .commitFlick:
            return commit(i, fromRise: rise)
        }
    }

    /// The gesture was cancelled: always springs back.
    @discardableResult
    public mutating func pointerCancel() -> [ShelfEvent] {
        guard phase == .dragging, let i = book else { return [] }
        let rise = ShelfResistance.rise(forDrag: drag, height: layout.spines[i].height)
        isArmed = false
        if rise < ShelfResistance.tapRise { reset(); return [] }
        lastRelease = .springBack
        springBacks += 1
        releaseRise = rise
        enter(.returning, kind: .springBack)
        return []
    }

    /// Opens a book without a pull (VoiceOver, a tap). Refused unless the shelf is at rest.
    @discardableResult
    public mutating func activate(book i: Int) -> [ShelfEvent] {
        guard i >= 0, i < layout.count, phase == .resting || phase == .seating else { return [] }
        book = i; drag = 0; lastRelease = .commitDrag
        return commit(i, fromRise: 0)
    }

    /// Closes the open card (tap outside, the close button). Refused until the card has finished opening.
    @discardableResult
    public mutating func close() -> Bool {
        guard canClose else { return false }
        enter(.returning, kind: reduceMotion ? .fade : .card)
        return true
    }

    /// Changes Reduce Motion. A book in flight (lifting, turning, open or returning) is put straight back.
    public mutating func setReduceMotion(_ value: Bool) {
        guard value != reduceMotion else { return }
        reduceMotion = value
        switch phase {
        case .lifting, .turning, .open, .returning: reset()
        default: break
        }
    }

    // MARK: time

    /// Advances by `dt` seconds (clamped to 0 ... `maxStep`; not-a-number counts as 0) and returns what happened.
    @discardableResult
    public mutating func step(_ dt: Double) -> [ShelfEvent] {
        let d = dt.isFinite ? min(max(dt, 0), Self.maxStep) : 0
        guard d > 0 else { return [] }
        time += d
        var remaining = d
        var events: [ShelfEvent] = []
        while remaining > 0 {
            guard let length = ShelfTimeline.duration(phase, kind: returnKind, reduceMotion: reduceMotion) else {
                phaseTime += remaining
                break
            }
            let left = length - phaseTime
            if remaining < left { phaseTime += remaining; break }
            remaining -= left
            events += advance()
        }
        return events
    }

    // MARK: private

    private mutating func enter(_ next: ShelfPhase, kind: ShelfReturnKind = .card) {
        phase = next; phaseTime = 0; returnKind = kind
    }

    private mutating func reset() {
        phase = .resting; book = nil; phaseTime = 0; drag = 0; dragBase = 0; isArmed = false; releaseRise = 0
        returnKind = .card
    }

    private mutating func commit(_ i: Int, fromRise rise: Double) -> [ShelfEvent] {
        commits += 1
        releaseRise = rise
        if reduceMotion {
            opens += 1
            enter(.open)
            return [.committed(i), .opened(i)]
        }
        enter(.lifting)
        return [.committed(i)]
    }

    /// The current timed phase has run its course.
    private mutating func advance() -> [ShelfEvent] {
        switch phase {
        case .lifting:
            enter(.turning)
            return []
        case .turning:
            opens += 1
            enter(.open)
            return book.map { [.opened($0)] } ?? []
        case .returning:
            seats += 1
            let i = book
            enter(.seating)
            return i.map { [.seated($0)] } ?? []
        case .seating:
            reset()
            return []
        default:
            return []
        }
    }
}
