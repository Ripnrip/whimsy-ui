import Foundation

/// The kinetic-type intro: phrases cut in one word at a time, hard-cut to the next phrase,
/// then the type vanishes and the grid takes over.
public struct KineticIntro: Equatable, Sendable {
    public var phrases: [[String]]
    /// Seconds between word cuts.
    public var wordInterval: Double
    /// How long a complete phrase holds before the next one cuts in.
    public var hold: Double
    public var startDelay: Double
    /// Length of the vanish (the grid starts revealing as it begins).
    public var outro: Double

    public init(phrases: [String] = ["WHIMSY STUDIO", "PHOTO ALBUM 2026", "2026 SHOWCASE APERTURE"],
                wordInterval: Double = 0.14, hold: Double = 0.5, startDelay: Double = 0.25, outro: Double = 0.45) {
        self.phrases = phrases.map { $0.split(separator: " ").map(String.init) }.filter { !$0.isEmpty }
        self.wordInterval = max(wordInterval, 1e-3)
        self.hold = max(hold, 0)
        self.startDelay = max(startDelay, 0)
        self.outro = max(outro, 1e-3)
    }

    /// When phrase `i` cuts in.
    public func start(ofPhrase i: Int) -> Double {
        startDelay + phrases.prefix(max(i, 0)).reduce(0) { $0 + Double($1.count) * wordInterval + hold }
    }

    /// When the type starts to vanish (and the grid starts to reveal).
    public var outroStart: Double { start(ofPhrase: phrases.count) }
    public var duration: Double { outroStart + outro }
    /// Total word cuts (one haptic tick each).
    public var totalCuts: Int { phrases.reduce(0) { $0 + $1.count } }

    public struct Frame: Equatable, Sendable {
        /// The phrase on screen, nil before the first cut and after the intro.
        public var phrase: Int?
        /// Words of that phrase visible so far.
        public var words: Int
        /// Cuts so far over the whole intro (drives the haptic).
        public var cuts: Int
        /// Seconds since the latest cut.
        public var sinceCut: Double
        /// 0…1 through the vanish.
        public var outro: Double
        /// Seconds since the grid started revealing (negative before).
        public var reveal: Double
        public var isFinished: Bool
    }

    public func frame(at t: Double) -> Frame {
        let t = t.isFinite ? t : 0
        let reveal = t - outroStart
        if t < startDelay || phrases.isEmpty {
            return Frame(phrase: nil, words: 0, cuts: 0, sinceCut: 0, outro: phrases.isEmpty ? 1 : 0, reveal: reveal, isFinished: phrases.isEmpty)
        }
        var cutsBefore = 0
        for (i, words) in phrases.enumerated() {
            let s = start(ofPhrase: i), e = start(ofPhrase: i + 1)
            if t < e {
                let n = min(Int(((t - s) / wordInterval).rounded(.down)) + 1, words.count)
                let lastCut = s + Double(n - 1) * wordInterval
                return Frame(phrase: i, words: n, cuts: cutsBefore + n, sinceCut: t - lastCut, outro: 0, reveal: reveal, isFinished: false)
            }
            cutsBefore += words.count
        }
        let last = phrases.count - 1
        let lastCut = start(ofPhrase: last) + Double(phrases[last].count - 1) * wordInterval
        let o = WhimsyMath.clamp01(reveal / outro)
        return Frame(phrase: o < 1 ? last : nil, words: phrases[last].count, cuts: totalCuts, sinceCut: t - lastCut,
                     outro: o, reveal: reveal, isFinished: o >= 1)
    }

    /// A word slams in slightly oversized and drops to 1 within 90 ms.
    public static func slamScale(sinceCut s: Double) -> Double {
        guard s.isFinite, s >= 0 else { return 1 }
        let u = max(0, 1 - s / 0.09)
        return 1 + 0.22 * u * u
    }

    /// The vanish: type shrinks a little, rises and fades (eased).
    public static func vanish(_ outro: Double) -> (scale: Double, opacity: Double, rise: Double) {
        let e = WhimsyMath.easeInOutCubic(WhimsyMath.clamp01(outro))
        return (1 - 0.12 * e, 1 - e, -60 * e)
    }
}
