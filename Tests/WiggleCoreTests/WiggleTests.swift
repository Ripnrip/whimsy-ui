import Foundation
import Testing
@testable import WiggleCore

private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }
private func titles(_ q: String) -> [String] { FuzzyMatcher.rank(q, rows: SettingsCatalog.rows).map(\.row.title) }

@Suite struct MatcherTests {
    @Test func subsequenceCaseAndWhitespace() {
        #expect(FuzzyMatcher.match("wifi", in: "Wi-Fi")?.indices == [0, 1, 3, 4])
        #expect(FuzzyMatcher.match("W I f i", in: "Wi-Fi") == FuzzyMatcher.match("wifi", in: "Wi-Fi"))
        #expect(FuzzyMatcher.match("fiwi", in: "Wi-Fi") == nil)          // order matters
        #expect(FuzzyMatcher.match("wifiwifi", in: "Wi-Fi") == nil)      // longer than the title
        #expect(FuzzyMatcher.match("", in: "Battery") == FuzzyMatch(score: 0, indices: []))
        #expect(FuzzyMatcher.match("   ", in: "Battery")?.indices == [])
    }

    @Test func wordStartsAndCamelCase() {
        #expect(FuzzyMatcher.isWordStart(Array("Wi-Fi"), 3))
        #expect(FuzzyMatcher.isWordStart(Array("iPhone"), 1))
        #expect(!FuzzyMatcher.isWordStart(Array("Wi-Fi"), 1))
        #expect(!FuzzyMatcher.isWordStart(Array("Wi-Fi"), 2))           // the hyphen itself
        // "s" in "Home Screen" lands on the word start, not "Home"'s… (it has no s) and costs 5 lead.
        #expect(FuzzyMatcher.match("s", in: "Home Screen") == FuzzyMatch(score: 16 + 24 - 5, indices: [5]))
        // A word start beats an earlier mid-word letter: "sec" is Security, not "Privacy"'s letters.
        #expect(FuzzyMatcher.match("sec", in: "Privacy & Security")?.indices == [10, 11, 12])
        #expect(FuzzyMatcher.match("ss", in: "Siri & Search")?.indices == [0, 7])
    }

    @Test func scoringArithmetic() {
        // S-O-S at a word start, two consecutive links, 10 letters of lead (capped at 9).
        #expect(FuzzyMatcher.match("sos", in: "Emergency SOS")?.score == (16 + 24 - 9) + (16 + 20) + (16 + 20))
        // "Sounds": S (start + first) o (consecutive) then a 3-letter gap to the s.
        #expect(FuzzyMatcher.match("sos", in: "Sounds & Haptics") == FuzzyMatch(score: 48 + 36 + (16 - 9), indices: [0, 1, 5]))
        #expect(FuzzyMatcher.match("ss", in: "Sounds & Haptics")?.indices == [0, 5])  // the near s, not Haptics'
    }

    @Test func consecutiveRunsWin() {
        #expect(titles("so").first == "Sounds & Haptics")
        #expect(titles("sos").first == "Emergency SOS")
        #expect(titles("dsp") == ["Display & Brightness", "Sounds & Haptics"])
        #expect(FuzzyMatcher.match("dsp", in: "Sounds & Haptics")?.indices == [4, 5, 11])
    }

    @Test func rankingHidesNonMatchesAndBreaksTies() {
        #expect(titles("").count == 20 && titles("") == SettingsCatalog.rows.map(\.title))
        // Three 48s for "s": shorter title first.
        #expect(Array(titles("s").prefix(3)) == ["Screen Time", "Siri & Search", "Sounds & Haptics"])
        for q in ["s", "pr", "bt", "sec", "zz"] {
            let r = FuzzyMatcher.rank(q, rows: SettingsCatalog.rows)
            #expect(zip(r, r.dropFirst()).allSatisfy { $0.match.score >= $1.match.score })
            let hits = Set(r.map(\.row.id))
            for row in SettingsCatalog.rows { #expect(hits.contains(row.id) == (FuzzyMatcher.match(q, in: row.title) != nil)) }
        }
        #expect(titles("zz").isEmpty)
    }
}

@Suite struct CatalogTests {
    @Test func twentyASCIIRowsWithUniqueIDs() {
        let rows = SettingsCatalog.rows
        #expect(rows.count == 20)
        #expect(rows.map(\.id) == Array(0..<20))
        #expect(Set(rows.map(\.title)).count == 20 && Set(rows.map(\.symbol)).count == 20)
        #expect(rows.allSatisfy { r in r.title.allSatisfy(\.isASCII) && !r.subtitle.isEmpty && (0...1).contains(r.hue) })
    }

    @Test func matchedIndicesSpellTheQuery() {
        for q in ["a", "se", "sos", "dsp", "pri", "on", "ac", "hot", "fid", "wall", "ctr", "sc t"] {
            for r in FuzzyMatcher.rank(q, rows: SettingsCatalog.rows) {
                let t = Array(r.row.title)
                #expect(zip(r.match.indices, r.match.indices.dropFirst()).allSatisfy { $0 < $1 })
                #expect(String(r.match.indices.map { FuzzyMatcher.fold(t[$0]) }) == String(FuzzyMatcher.normalize(q)))
            }
        }
    }
}

@Suite struct DiffTests {
    @Test func newlyMatchedLetters() {
        let d = MatchDiff.newlyMatched(previous: [1: [0, 1], 2: [3]], current: [1: [0, 1, 5], 2: [3], 7: [2, 4]])
        #expect(d == [1: [5], 7: [2, 4]])
        #expect(MatchDiff.newlyMatched(previous: [1: [0, 4]], current: [1: [0, 1]]) == [1: [1]])   // moved letter is new
        #expect(MatchDiff.newlyMatched(previous: [1: [0]], current: [:]).isEmpty)
    }
}

@Suite struct EnvelopeTests {
    @Test func calmsToFlatAfterHalfASecond() {
        var e = WaveEnvelope()
        #expect(e.level(at: 3) == 0 && e.isCalm(at: 3))
        e.energize(at: 1)
        #expect(e.level(at: 1) == 0)
        #expect(near(e.level(at: 1 + WaveEnvelope.attack), 1))
        let ts = stride(from: 1.08, through: 1.5, by: 0.01).map { e.level(at: $0) }
        #expect(zip(ts, ts.dropFirst()).allSatisfy { $0 >= $1 - 1e-12 })
        #expect(near(e.level(at: 1.5), 0) && e.isCalm(at: 1.5) && !e.isCalm(at: 1.49))
        #expect(near(e.level(at: 1.29), 0.5) && e.level(at: 1.2) > 0.75)   // halfway through the eased calm
    }

    @Test func reEnergizesWithoutAJump() {
        var e = WaveEnvelope()
        e.energize(at: 0)
        let mid = e.level(at: 0.35)
        e.energize(at: 0.35)
        #expect(near(e.level(at: 0.35), mid))
        #expect(e.level(at: 0.37) > mid)
        #expect(near(e.level(at: 0.43), 1))
        #expect(e.isCalm(at: 0.85) && !e.isCalm(at: 0.84))
    }
}

@Suite struct MotionTests {
    @Test func waveSamplesAreTaperedAndPhaseShifted() {
        let s = WaveUnderline.samples(width: 9, amplitude: 2.2, time: 0.13, letterIndex: 3)
        #expect(s.count == WaveUnderline.samplesPerLetter + 1)
        #expect(near(s.first!.x, 0) && near(s.last!.x, 9) && abs(s.first!.y) < 1e-12 && abs(s.last!.y) < 1e-9)
        #expect(s.allSatisfy { abs($0.y) <= 2.2 } && s.contains { abs($0.y) > 0.5 })
        // Letter k is letter 0 shifted in time by k·phase / (2π·speed).
        let k = 5, dt = WaveUnderline.letterPhase * Double(k) / (2 * .pi * WaveUnderline.speed)
        for x in stride(from: 0.0, through: 8, by: 0.7) {
            #expect(near(WaveUnderline.offset(x: x, width: 8, amplitude: 2, time: 0.4, letterIndex: k),
                         WaveUnderline.offset(x: x, width: 8, amplitude: 2, time: 0.4 + dt, letterIndex: 0), 1e-9))
        }
        #expect(WaveUnderline.samples(width: 9, amplitude: 0, time: 1, letterIndex: 2).allSatisfy { $0.y == 0 })
    }

    @Test func jiggleSpringPopsAndSettles() {
        #expect(LetterJiggle.displacement(at: -0.01) == 0)
        #expect(near(LetterJiggle.displacement(at: 0), 1))
        let t0 = LetterJiggle.transform(at: 0)
        #expect(near(t0.scale, 1.35) && near(t0.offsetY, -5))
        let ds = stride(from: 0.0, to: 1.0, by: 0.005).map(LetterJiggle.displacement)
        #expect(ds.min()! < -0.2)                         // it wobbles past rest
        #expect(abs(LetterJiggle.displacement(at: 0.99)) < 0.01 && LetterJiggle.displacement(at: 1) == 0)
        let late = LetterJiggle.transform(at: 2)
        #expect(late.scale == 1 && late.offsetY == 0)
    }
}

@Suite struct ModelTests {
    @Test func eventsForAKeystroke() {
        var m = WiggleModel()
        m.setQuery("so", at: 1)
        let e = m.advance(to: 1)
        #expect(e == [.queryChanged("so"), .resultsChanged(4),
                      .lettersMatched(row: 6, indices: [0, 1]), .lettersMatched(row: 17, indices: [10, 11]),
                      .lettersMatched(row: 4, indices: [3, 4]), .lettersMatched(row: 16, indices: [13, 15]), .tick])
        #expect(m.resultCount == 4 && m.ticks == 1)
        let e2 = m.advance(to: 1.2)
        #expect(e2.isEmpty)
        let e3 = m.advance(to: 1.5)
        #expect(e3 == [.calmed])
        let e4 = m.advance(to: 2)
        #expect(e4.isEmpty && !m.isIdle)                          // Face ID's letters (rank 3) still wobbling
        _ = m.advance(to: 2.1)
        #expect(m.isIdle)
    }

    @Test func onlyNewLettersJiggleStaggeredByRank() {
        var m = WiggleModel()
        m.setQuery("so", at: 1)
        #expect(m.jiggleStarts[6] == [0: 1, 1: 1])                  // rank 0
        #expect(m.jiggleStarts[17] == [10: 1.03, 11: 1.03])        // rank 1
        m.setQuery("sos", at: 1.4)
        #expect(m.jiggleStarts[17] == [10: 1.03, 11: 1.03, 12: 1.4])   // now rank 0: only the new S
        #expect(m.jiggleStarts[16] == nil)                         // Face ID no longer matches
        #expect(m.jiggle(row: 17, index: 12) == LetterJiggle.transform(at: 0))
        m.setQuery("so", at: 1.6)
        #expect(m.jiggleStarts[16] != nil)                         // it reappears and jiggles again
        #expect(m.jiggleStarts[17]?[12] == nil)
        var e = WiggleModel()
        e.setQuery("", at: 1)
        #expect(e.advance(to: 1).isEmpty)                          // no change, no events
    }

    @Test func hapticTicksAreDebounced() {
        var m = WiggleModel()
        for (i, q) in ["w", "wi", "wif", "wifi"].enumerated() { m.setQuery(q, at: Double(i) * 0.05) }
        #expect(m.ticks == 2)                                      // at 0; .05 and .10 too soon; .15 ≥ .12
        m.setQuery("wifi", at: 0.3)                                // unchanged query
        #expect(m.ticks == 2)
        var n = WiggleModel()
        for (i, q) in ["w", "wi", "wif", "wifi", "wif"].enumerated() { n.setQuery(q, at: Double(i) * 0.2) }
        #expect(n.ticks == 4)                                      // deleting a letter matches nothing new
        let fast = (0..<6).reduce(into: WiggleModel()) { mm, i in mm.setQuery(String("bluetooth".prefix(i + 1)), at: Double(i) * 0.05) }
        #expect(fast.ticks == 2)                                   // at 0 and 0.15
    }

    @Test func amplitudeIdleAndReduceMotion() {
        var m = WiggleModel()
        #expect(m.amplitude == 0 && m.isIdle)
        m.setQuery("b", at: 2)
        _ = m.advance(to: 2.08)
        #expect(near(m.amplitude, WaveUnderline.maxAmplitude))
        #expect(!m.isIdle)
        _ = m.advance(to: 3.1)
        #expect(m.amplitude == 0 && m.isIdle)
        var c = WiggleModel.Config()
        c.reduceMotion = true
        var r = WiggleModel(config: c)
        r.setQuery("b", at: 0)
        let ev = r.advance(to: 0.05)
        #expect(ev.contains(.tick) && r.ticks == 1)               // haptics still play
        #expect(r.amplitude == 0 && r.jiggle(row: 1, index: 0) == (1, 0) && !r.isJiggling)
        #expect(ev.last == .tick && r.isIdle == false)            // calmed is still owed…
        let late = r.advance(to: 0.6)
        #expect(late == [.calmed] && r.isIdle)
    }
}
