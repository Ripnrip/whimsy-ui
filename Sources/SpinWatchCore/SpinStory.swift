import Foundation

/// The scroll story: the watch turns front → side → back → front while text blocks fade and
/// slide up in sync with the rotation's holds, ending on a stats row.
public struct SpinStory: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public var kicker: String
        public var title: String
        public var body: String
        /// Fully visible between these progress values (the watch is holding still).
        public var start: Double
        public var end: Double
    }

    public struct Stat: Equatable, Sendable {
        public var value: Int
        public var unit: String
        public var label: String
    }

    /// Watch yaw in degrees. Positive turns the crown (right) side towards you.
    public let yaw = KeyframeTrack([
        Keyframe(0, 0), Keyframe(0.10, 0), Keyframe(0.30, 90), Keyframe(0.40, 90),
        Keyframe(0.60, 180), Keyframe(0.70, 180), Keyframe(0.88, 360), Keyframe(1, 360),
    ])

    public let sections: [Section] = [
        Section(kicker: "CHRONO / 01", title: "EVERY SECOND, REIMAGINED", body: "Scroll to turn it over.", start: 0, end: 0.10),
        Section(kicker: "PROFILE", title: "11.2 MM. ONE BILLET.", body: "Grade 5 titanium, cut in nine passes.", start: 0.30, end: 0.40),
        Section(kicker: "CASEBACK", title: "SAPPHIRE, BOTH SIDES.", body: "Optical heart sensor and a laser-etched serial.", start: 0.60, end: 0.70),
        Section(kicker: "SPEC SHEET", title: "", body: "Machined, not molded.", start: 0.88, end: 1),
    ]

    public let stats: [Stat] = [
        Stat(value: 47, unit: "mm", label: "Titanium case"),
        Stat(value: 100, unit: "m", label: "Water resistant"),
        Stat(value: 36, unit: "h", label: "Battery life"),
    ]

    /// Width of each fade, in progress.
    public let fade = 0.06
    /// Points a block travels while it fades.
    public let slide = 28.0

    public init() {}

    public func yaw(at p: Double) -> Double { yaw.value(at: p) }

    /// 0…1 opacity of section `i`: in over `fade` before its window, out over `fade` after
    /// (the first starts visible, the last never leaves).
    public func opacity(ofSection i: Int, at p: Double) -> Double {
        guard sections.indices.contains(i), p.isFinite else { return 0 }
        let s = sections[i]
        let inT = i == 0 ? 1 : WhimsyMath.progress(p, from: s.start - fade, to: s.start)
        let outT = i == sections.count - 1 ? 0 : WhimsyMath.progress(p, from: s.end, to: s.end + fade)
        return WhimsyMath.smoothstep(0, 1, inT) * (1 - WhimsyMath.smoothstep(0, 1, outT))
    }

    /// Vertical offset: rises in from below, leaves upwards.
    public func offset(ofSection i: Int, at p: Double) -> Double {
        guard sections.indices.contains(i), p.isFinite else { return 0 }
        let o = opacity(ofSection: i, at: p)
        return (1 - o) * slide * (p < sections[i].start ? 1 : -1)
    }

    /// The section currently most visible.
    public func activeSection(at p: Double) -> Int {
        sections.indices.max { opacity(ofSection: $0, at: p) < opacity(ofSection: $1, at: p) } ?? 0
    }

    /// Stats count up as the last section arrives.
    public func statValue(_ i: Int, at p: Double) -> Int {
        guard stats.indices.contains(i) else { return 0 }
        let s = sections[sections.count - 1]
        let t = WhimsyMath.easeOutCubic(WhimsyMath.progress(p, from: s.start - fade, to: s.start + 0.08))
        return Int((Double(stats[i].value) * t).rounded())
    }
}
