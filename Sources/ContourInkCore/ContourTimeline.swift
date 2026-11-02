import Foundation

public enum ContourPhase: Int, CaseIterable, Sendable {
    /// The rings are sketched one after another.
    case draw
    /// A red dot climbs the route to the peak, leaving a dashed trail.
    case climb
    /// The sheet tilts back and rests.
    case tilt
    /// The sheet fades out.
    case fade
    /// A blank sheet fades back in, then the loop starts again.
    case loop
}

/// Where the pen is: the ring it is drawing and how far round it has got (0 ... 1 of the ring's length).
public struct ContourNib: Equatable, Sendable {
    public var ring: Int
    public var fraction: Double
}

/// Everything the view needs at one moment.
public struct ContourFrame: Equatable, Sendable {
    public var phase: ContourPhase
    /// 0 ... 1 through the current phase.
    public var phaseProgress: Double
    /// Time inside the loop, 0 ..< period.
    public var time: Double
    public var loopIndex: Int
    /// `trim(from: 0, to:)` of each ring, outermost first.
    public var ringTrims: [Double]
    public var nib: ContourNib?
    /// How far the dot is along the route (0 ... 1), nil while it is hidden. The dashed trail is drawn to the same value.
    public var routeFraction: Double?
    /// 0 ... 1, an expanding ripple where the dot reaches the peak; nil otherwise.
    public var pulse: Double?
    /// Rotation about the x axis, in degrees.
    public var tiltDegrees: Double
    public var opacity: Double
    /// A finished map with the dot at the peak: Reduce Motion, or not animating.
    public var isStatic: Bool
}

/// The loop as a pure function of time: draw, climb, tilt, fade, loop.
public enum ContourInkTimeline {
    /// Each ring starts this long after the one outside it ...
    public static let stagger = 0.12
    /// ... and takes this long to draw, eased in and out.
    public static let ringDuration = 0.5
    public static let climbDuration = 1.2
    /// The sheet takes `tiltRise` seconds to reach its angle, then rests until `tiltDuration` is up.
    public static let tiltDuration = 1.2
    public static let tiltRise = 0.8
    public static let tiltDegrees = 25.0
    /// `rotation3DEffect` perspective.
    public static let perspective = 0.7
    public static let fadeDuration = 0.6
    public static let loopDuration = 0.35
    /// The ripple at the peak lasts this long.
    public static let pulseDuration = 0.5

    public static func drawDuration(rings: Int) -> Double {
        Double(ContourInkGeometry.clampedCount(rings) - 1) * stagger + ringDuration
    }

    /// One full loop.
    public static func period(rings: Int) -> Double {
        drawDuration(rings: rings) + climbDuration + tiltDuration + fadeDuration + loopDuration
    }

    /// When each phase begins inside the loop, in `ContourPhase` order.
    public static func phaseStarts(rings: Int) -> [Double] {
        var s = [0.0]
        s.append(s[0] + drawDuration(rings: rings))
        s.append(s[1] + climbDuration)
        s.append(s[2] + tiltDuration)
        s.append(s[3] + fadeDuration)
        return s
    }

    /// When ring `k` has just closed (inside the loop).
    public static func closeTime(ring k: Int) -> Double { Double(k) * stagger + ringDuration }

    /// When the dot reaches the peak (inside the loop).
    public static func arrivalTime(rings: Int) -> Double { drawDuration(rings: rings) + climbDuration }

    /// How much of ring `k` has been drawn `t` seconds into the loop.
    public static func ringTrim(ring k: Int, at t: Double) -> Double {
        WhimsyMath.easeInOutCubic((t - Double(k) * stagger) / ringDuration)
    }

    /// Splits running time into the whole loops done and the time inside the loop (`0 ..< period`).
    /// Robust to rounding at the loop boundary; non-finite time counts as 0.
    public static func split(_ t: Double, rings: Int) -> (loop: Int, time: Double) {
        let p = period(rings: rings)
        guard t.isFinite else { return (0, 0) }
        var loop = Int((t / p).rounded(.down))
        var r = t - p * Double(loop)
        if r < 0 { loop -= 1; r += p }
        if r >= p - 1e-9 { loop += 1; r = max(0, r - p) }
        return (loop, max(0, r))
    }

    /// Wraps any time (even negative or non-finite) into `0 ..< period`.
    public static func wrap(_ t: Double, rings: Int) -> Double { split(t, rings: rings).time }

    /// The tilt angle `x` seconds into the tilt phase.
    public static func tilt(inPhase x: Double) -> Double {
        tiltDegrees * WhimsyMath.easeInOutCubic(x / tiltRise)
    }

    public static func frame(at time: Double, rings requested: Int) -> ContourFrame {
        let n = ContourInkGeometry.clampedCount(requested)
        let p = period(rings: n)
        let (loop, t) = split(time, rings: n)
        let loopIndex = max(0, loop)
        let s = phaseStarts(rings: n)
        var phase = ContourPhase.loop
        for (i, ph) in ContourPhase.allCases.enumerated() where t >= s[i] { phase = ph }
        let starts = s + [p]
        let local = t - s[phase.rawValue]
        let span = starts[phase.rawValue + 1] - s[phase.rawValue]
        let u = WhimsyMath.clamp01(local / span)

        var trims: [Double] = []
        for k in 0..<n {
            switch phase {
            case .draw: trims.append(ringTrim(ring: k, at: t))
            case .climb, .tilt, .fade: trims.append(1)
            case .loop: trims.append(0)
            }
        }
        var nib: ContourNib?
        if phase == .draw {
            for k in stride(from: n - 1, through: 0, by: -1) where trims[k] > 0 && trims[k] < 1 {
                nib = ContourNib(ring: k, fraction: trims[k]); break
            }
        }
        var route: Double?
        switch phase {
        case .draw, .loop: route = nil
        case .climb: route = WhimsyMath.easeInOutCubic(u)
        case .tilt, .fade: route = 1
        }
        var pulse: Double?
        if phase == .tilt, local < pulseDuration { pulse = local / pulseDuration }
        var tiltDeg = 0.0, opacity = 1.0
        switch phase {
        case .draw, .climb, .loop: break
        case .tilt: tiltDeg = tilt(inPhase: local)
        case .fade: tiltDeg = tiltDegrees
        }
        if phase == .fade { opacity = 1 - WhimsyMath.smoothstep(0, 1, u) }
        if phase == .loop { opacity = WhimsyMath.smoothstep(0, 1, u) }
        return ContourFrame(phase: phase, phaseProgress: u, time: t, loopIndex: loopIndex, ringTrims: trims, nib: nib,
                            routeFraction: route, pulse: pulse, tiltDegrees: tiltDeg, opacity: opacity, isStatic: false)
    }

    /// The finished map: every ring drawn, the dot at the peak, the sheet flat.
    public static func staticFrame(rings requested: Int) -> ContourFrame {
        let n = ContourInkGeometry.clampedCount(requested)
        return ContourFrame(phase: .tilt, phaseProgress: 0, time: arrivalTime(rings: n), loopIndex: 0,
                            ringTrims: Array(repeating: 1, count: n), nib: nil, routeFraction: 1, pulse: nil,
                            tiltDegrees: 0, opacity: 1, isStatic: true)
    }

    // MARK: events

    /// Things that happen at an instant of the loop.
    public static func moments(rings requested: Int) -> [(offset: Double, event: ContourEvent)] {
        let n = ContourInkGeometry.clampedCount(requested)
        var m: [(Double, ContourEvent)] = [(0, .looped)]
        var closes: [(Double, ContourEvent)] = (0..<n).map { (closeTime(ring: $0), .ringClosed($0)) }
        closes.append((arrivalTime(rings: n), .dotArrived))
        closes.sort { $0.0 < $1.0 }
        m += closes
        return m
    }

    /// The events in the half-open interval `(from, to]` of running time, in order. Each ring closes
    /// exactly once per loop however the interval is cut; a wrap of the loop is `.looped` (not at time 0).
    public static func events(from t0: Double, to t1: Double, rings requested: Int) -> [ContourEvent] {
        guard t0.isFinite, t1.isFinite, t1 > t0, t1 > 0 else { return [] }
        let n = ContourInkGeometry.clampedCount(requested)
        let p = period(rings: n)
        let from = max(t0, 0)
        let firstLoop = max(0, Int((from / p).rounded(.down)))
        let lastLoop = Int((t1 / p).rounded(.down))
        let ms = moments(rings: n)
        var out: [ContourEvent] = []
        for j in firstLoop...max(firstLoop, lastLoop) {
            for (off, ev) in ms {
                if ev == .looped && j == 0 { continue }
                let at = Double(j) * p + off
                if at > t0 && at <= t1 { out.append(ev) }
            }
        }
        return out
    }
}

public enum ContourEvent: Equatable, Sendable {
    /// Ring `k` has just closed: the haptic tick.
    case ringClosed(Int)
    /// The red dot reached the peak.
    case dotArrived
    /// The loop started again.
    case looped
}
