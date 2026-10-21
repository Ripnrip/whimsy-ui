import Foundation

/// A grid of specimen cards: `columns` across, fixed card height, row-major slots.
/// Points, origin top-left, y down.
public struct SpecimenGridLayout: Equatable, Sendable {
    public var columns: Int
    public var width: Double
    public var cardHeight: Double
    public var spacing: Double
    public var inset: Double

    public init(columns: Int = 2, width: Double, cardHeight: Double = 196, spacing: Double = 14, inset: Double = 16) {
        self.columns = max(columns, 1)
        self.width = max(width, 0)
        self.cardHeight = max(cardHeight, 0)
        self.spacing = max(spacing, 0)
        self.inset = max(inset, 0)
    }

    public var cardWidth: Double {
        max((width - 2 * inset - spacing * Double(columns - 1)) / Double(columns), 0)
    }

    /// Centre of slot `index`.
    public func center(_ index: Int) -> Vec2 {
        let i = max(index, 0)
        let c = i % columns, r = i / columns
        return Vec2(inset + cardWidth / 2 + Double(c) * (cardWidth + spacing),
                    inset + cardHeight / 2 + Double(r) * (cardHeight + spacing))
    }

    /// Total height needed for `count` cards (insets included).
    public func contentHeight(count: Int) -> Double {
        guard count > 0 else { return 2 * inset }
        let rows = (count + columns - 1) / columns
        return 2 * inset + Double(rows) * cardHeight + Double(rows - 1) * spacing
    }
}

/// Spring + choreography constants for the regroup.
public struct RegroupTuning: Equatable, Sendable {
    /// Spring response (period of the undamped oscillation), seconds.
    public var response = 0.52
    /// Damping ratio (< 1 bounces a little).
    public var dampingRatio = 0.72
    /// Extra delay per destination slot, seconds: cards land in reading order.
    public var stagger = 0.045
    /// Peak tilt while flying, degrees (sign and size seeded per card).
    public var maxTilt = 9.0
    /// Arc height per point travelled (cards hop over each other), capped at `maxHop`.
    public var hopPerPoint = 0.12
    public var maxHop = 36.0
    /// Entering cards start this far below their slot, at `enterScale`, fully transparent.
    public var enterOffset = 42.0
    public var enterScale = 0.6
    /// Leaving cards shrink and fade over this long, seconds.
    public var leaveDuration = 0.24
    /// Spring progress at which a card counts as "landed" (haptic).
    public var landingThreshold = 0.985
    public init() {}
    public static let `default` = RegroupTuning()

    /// Closed-form step response of the spring, 0 at t ≤ 0 → 1 (with overshoot when ζ < 1).
    public func spring(_ t: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega = 2 * .pi / max(response, 1e-6)
        let z = max(dampingRatio, 0)
        if z < 1 {
            let wd = omega * (1 - z * z).squareRoot()
            return 1 - exp(-z * omega * t) * (cos(wd * t) + z * omega / wd * sin(wd * t))
        }
        // Critically damped (ζ ≥ 1 treated as 1).
        return 1 - exp(-omega * t) * (1 + omega * t)
    }

    /// First time the spring reaches `landingThreshold`, found on a fixed 1 ms grid so every
    /// platform (and the web port) gets the same answer.
    public var landingTime: Double {
        var t = 0.0
        while t < 10 {
            if spring(t) >= landingThreshold { return t }
            t += 0.001
        }
        return 10
    }
}

/// How a card moves during a regroup.
public enum RegroupKind: String, Equatable, Sendable {
    /// Visible before and after (may change slot).
    case move
    /// Appears (it passes the new filter, didn't pass the old one).
    case enter
    /// Disappears.
    case leave
}

/// One card's planned flight.
public struct CardFlight: Equatable, Sendable {
    public var id: String
    public var kind: RegroupKind
    public var from: Vec2
    public var to: Vec2
    public var delay: Double
    /// Peak tilt, degrees (signed).
    public var tilt: Double
    /// Peak arc height, points (the card rises by this much mid-flight).
    public var hop: Double
    /// Slot index after the regroup (leaving cards keep their old slot).
    public var slot: Int
}

/// Where a card is drawn at one moment.
public struct CardPose: Equatable, Sendable {
    public var center: Vec2
    public var scale: Double
    public var opacity: Double
    /// Degrees.
    public var rotation: Double
    /// Draw order (cards in the air above cards on the ground).
    public var zIndex: Double
}

/// The choreography for one filter change: every card visible before or after gets a flight
/// from its old slot to its new one, staggered by destination slot, hopping on an arc with a
/// seeded tilt, driven by a closed-form spring so any renderer gets identical frames.
public struct RegroupPlan: Equatable, Sendable {
    public let layout: SpecimenGridLayout
    public let tuning: RegroupTuning
    public let flights: [CardFlight]
    public let reduceMotion: Bool

    /// - Parameters:
    ///   - from: ids visible before, in slot order.
    ///   - to: ids visible after, in slot order.
    public init(from: [String], to: [String], layout: SpecimenGridLayout, seed: UInt64,
                tuning: RegroupTuning = .default, reduceMotion: Bool = false) {
        self.layout = layout
        self.tuning = tuning
        self.reduceMotion = reduceMotion
        var rng = SeededRandom(seed: seed)
        let oldSlot = Dictionary(from.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let newSlot = Dictionary(to.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var flights: [CardFlight] = []
        var seen = Set<String>()
        for id in to where seen.insert(id).inserted {
            let s = newSlot[id]!
            let dest = layout.center(s)
            let tilt = rng.uniform(-tuning.maxTilt...tuning.maxTilt)
            if let o = oldSlot[id] {
                let src = layout.center(o)
                let hop = min(src.distance(to: dest) * tuning.hopPerPoint, tuning.maxHop)
                flights.append(CardFlight(id: id, kind: .move, from: src, to: dest,
                                          delay: Double(s) * tuning.stagger, tilt: o == s ? 0 : tilt, hop: hop, slot: s))
            } else {
                flights.append(CardFlight(id: id, kind: .enter, from: dest + Vec2(0, tuning.enterOffset), to: dest,
                                          delay: Double(s) * tuning.stagger, tilt: tilt * 0.5, hop: 0, slot: s))
            }
        }
        for id in from where seen.insert(id).inserted {
            let o = oldSlot[id]!
            let src = layout.center(o)
            flights.append(CardFlight(id: id, kind: .leave, from: src, to: src, delay: 0,
                                      tilt: rng.uniform(-tuning.maxTilt...tuning.maxTilt), hop: 0, slot: o))
        }
        self.flights = flights
    }

    public func flight(id: String) -> CardFlight? { flights.first { $0.id == id } }

    /// Seconds until every card is at rest.
    public var duration: Double {
        if reduceMotion { return tuning.leaveDuration }
        let land = flights.filter { $0.kind != .leave }.map { $0.delay + settleTime }.max() ?? 0
        let leave = flights.contains { $0.kind == .leave } ? tuning.leaveDuration : 0
        return max(land, leave)
    }

    /// When the spring is within 0.1% of rest for good (fixed 2 ms scan from the end).
    var settleTime: Double {
        let omega = 2 * .pi / max(tuning.response, 1e-6)
        let z = min(max(tuning.dampingRatio, 0.05), 1)
        // Envelope e^{-ζωt}·(1/√(1−ζ²)) < 1e-3.
        let k = z < 1 ? 1 / (1 - z * z).squareRoot() : 1
        return log(1000 * k) / (z * omega)
    }

    public func isSettled(at t: Double) -> Bool { t >= duration }

    /// The pose of `flight` at `t` seconds after the plan started.
    public func pose(_ f: CardFlight, at t: Double) -> CardPose {
        if reduceMotion {
            // Crossfade: everything sits in its final slot; leavers fade out, enterers fade in.
            let u = tuning.leaveDuration > 0 ? min(max(t / tuning.leaveDuration, 0), 1) : 1
            switch f.kind {
            case .leave: return CardPose(center: f.from, scale: 1, opacity: 1 - u, rotation: 0, zIndex: 0)
            case .enter: return CardPose(center: f.to, scale: 1, opacity: u, rotation: 0, zIndex: 1)
            case .move: return CardPose(center: f.to, scale: 1, opacity: 1, rotation: 0, zIndex: 1)
            }
        }
        switch f.kind {
        case .leave:
            let u = tuning.leaveDuration > 0 ? min(max(t / tuning.leaveDuration, 0), 1) : 1
            let e = u * u
            return CardPose(center: f.from + Vec2(0, 10 * e), scale: 1 - (1 - tuning.enterScale) * e,
                            opacity: 1 - u, rotation: f.tilt * e, zIndex: 0)
        case .enter:
            let p = tuning.spring(t - f.delay)
            let pos = Vec2.lerp(f.from, f.to, p)
            let arc = sin(.pi * min(max(p, 0), 1))
            return CardPose(center: pos, scale: tuning.enterScale + (1 - tuning.enterScale) * p,
                            opacity: min(max(p * 1.6, 0), 1), rotation: f.tilt * arc, zIndex: 1 + arc)
        case .move:
            let p = tuning.spring(t - f.delay)
            let arc = sin(.pi * min(max(p, 0), 1))
            let pos = Vec2.lerp(f.from, f.to, p) + Vec2(0, -f.hop * arc)
            let lift = f.hop > 0 ? arc : 0
            return CardPose(center: pos, scale: 1 + 0.06 * lift, opacity: 1, rotation: f.tilt * arc, zIndex: 1 + 2 * lift)
        }
    }

    /// Poses for every flight at `t`, keyed by id.
    public func poses(at t: Double) -> [String: CardPose] {
        Dictionary(flights.map { ($0.id, pose($0, at: t)) }, uniquingKeysWith: { a, _ in a })
    }

    /// When each moving/entering card that changes slot "lands" (spring passes the threshold).
    /// Cards that stay put don't land. Sorted by time.
    public var landings: [(time: Double, id: String)] {
        guard !reduceMotion else { return [] }
        let lt = tuning.landingTime
        return flights
            .filter { $0.kind == .enter || ($0.kind == .move && $0.from != $0.to) }
            .map { ($0.delay + lt, $0.id) }
            .sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
    }

    /// Landing haptics in `(t0, t1]`.
    public func landingEvents(after t0: Double, through t1: Double) -> [(time: Double, event: FontHapticEvent)] {
        landings.filter { $0.time > t0 && $0.time <= t1 }.map { ($0.time, .landing) }
    }
}
