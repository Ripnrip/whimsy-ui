import Testing
@testable import EraserDeleteCore

private let card = CardSize(width: 340, height: 80)

@Suite("Auto erase session")
struct AutoSessionTests {
    @Test func fullAutoEraseWipesEverythingAndTicksEachTurn() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        var turns = 0
        for frame in 1...90 { turns += session.advance(to: Double(frame) / 90).turns }
        #expect(session.isFullyWiped)
        #expect(session.coveredFraction == 1)
        #expect(turns == session.path.turnCount)
        #expect(session.turnCount == session.path.turnCount)
        #expect(session.strokes.count == 1)
        #expect(session.progress == 1)
    }

    @Test func halfwayIsPartiallyWiped() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        session.advance(to: 0.5)
        #expect(session.coveredFraction > 0.3 && session.coveredFraction < 0.75)
        #expect(!session.isFullyWiped)
    }

    @Test func thresholdIsReachedBeforeTheVeryEnd() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        var wipedAt: Double?
        for frame in 1...200 {
            let p = Double(frame) / 200
            session.advance(to: p)
            if session.isFullyWiped { wipedAt = p; break }
        }
        let p = try! #require(wipedAt)
        #expect(p < 1)          // the fade can start before the eraser leaves the card
        #expect(p > 0.7)
    }

    @Test func coverageIsFrameRateIndependent() {
        var coarse = EraserSession(cardSize: card, eraserWidth: 32)
        var fine = EraserSession(cardSize: card, eraserWidth: 32)
        for f in 1...10 { coarse.advance(to: Double(f) / 10 * 0.6) }
        for f in 1...120 { fine.advance(to: Double(f) / 120 * 0.6) }
        #expect(abs(coarse.coveredFraction - fine.coveredFraction) < 0.01)
        #expect(coarse.turnCount == fine.turnCount)
    }

    @Test func goingBackwardsIsIgnored() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        session.advance(to: 0.4)
        let snapshot = session.coveredFraction
        let movement = session.advance(to: 0.1)
        #expect(movement == .init())
        #expect(session.progress == 0.4)
        #expect(session.coveredFraction == snapshot)
    }

    @Test func poseFollowsThePath() throws {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        session.advance(to: 0.3)
        let pose = try #require(session.pose)
        #expect(pose == session.path.pose(at: 0.3))
    }

    @Test func movementReportsDistance() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        let move = session.advance(to: 0.25)
        #expect(abs(move.distance - session.path.length * 0.25) / (session.path.length * 0.25) < 0.02)
    }
}

@Suite("Manual scrub session")
struct ManualSessionTests {
    /// Scrubs horizontal passes like a person would, with a little vertical wobble.
    private func scrubRows(_ session: inout EraserSession, rows: [Double]) -> Int {
        var turns = 0
        session.beginScrub(at: Vec2(-10, rows[0]))
        for (i, y) in rows.enumerated() {
            let xs = i.isMultiple(of: 2) ? Array(stride(from: -10.0, through: 350, by: 7)) : Array(stride(from: 350.0, through: -10, by: -7))
            for (j, x) in xs.enumerated() {
                turns += session.scrub(to: Vec2(x, y + (j.isMultiple(of: 2) ? 1.5 : -1.5))).turns
            }
        }
        session.endScrub()
        return turns
    }

    @Test func scrubbingBackAndForthWipesTheCard() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        let turns = scrubRows(&session, rows: [12, 34, 56, 70])
        #expect(session.isFullyWiped)
        #expect(turns == 3)
        #expect(session.turnCount == 3)
        #expect(!session.isScrubbing)
    }

    @Test func partialScrubIsNotWiped() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        _ = scrubRows(&session, rows: [12])
        #expect(session.coveredFraction > 0.2)
        #expect(!session.isFullyWiped)
    }

    @Test func manualAndAutoShareCoverage() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        session.advance(to: 0.5)
        let afterAuto = session.coveredFraction
        _ = scrubRows(&session, rows: [56, 70])
        #expect(session.coveredFraction > afterAuto)
        #expect(session.isFullyWiped)
        #expect(session.strokes.count == 2)     // one auto stroke + one hand stroke
    }

    @Test func scrubWithoutBeginStartsAStroke() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        session.scrub(to: Vec2(100, 40))
        #expect(session.isScrubbing)
        #expect(session.strokes == [[Vec2(100, 40)]])
        #expect(session.coveredFraction > 0)
    }

    @Test func tinyMovesAreIgnored() {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        session.beginScrub(at: Vec2(100, 40))
        let move = session.scrub(to: Vec2(100.2, 40.1))
        #expect(move.distance == 0)
        #expect(session.strokes[0].count == 1)
    }

    @Test func tiltEasesTowardMotion() throws {
        var session = EraserSession(cardSize: card, eraserWidth: 32)
        session.beginScrub(at: Vec2(10, 40))
        var tilts: [Double] = []
        for i in 1...12 {
            session.scrub(to: Vec2(10 + Double(i) * 10, 40))
            tilts.append(try #require(session.pose?.rotation))
        }
        let target = -session.path.maxTilt
        #expect(tilts.first! > target)                      // not snapped instantly
        #expect(abs(tilts.last! - target) < 0.01)           // converges
        #expect(zip(tilts, tilts.dropFirst()).allSatisfy { $1 <= $0 })
    }
}

@Suite("Reversal detector")
struct ReversalDetectorTests {
    @Test func countsRealReversalsOnly() {
        var detector = ReversalDetector(threshold: 10)
        var reversals = 0
        let xs: [Double] = [0, 5, 20, 40, 38, 41, 35, 25, 10, 0, 3, 12, 30]
        for x in xs where detector.update(x: x) { reversals += 1 }
        #expect(reversals == 2)   // right→left at 41, left→right at 0
    }

    @Test func jitterNeverTicks() {
        var detector = ReversalDetector(threshold: 8)
        var reversals = 0
        for i in 0..<100 where detector.update(x: 50 + (i.isMultiple(of: 2) ? 3 : -3)) { reversals += 1 }
        #expect(reversals == 0)
    }

    @Test func resetForgetsDirection() {
        var detector = ReversalDetector(threshold: 5)
        _ = detector.update(x: 0); _ = detector.update(x: 20)
        detector.reset()
        _ = detector.update(x: 20)
        let afterReset = detector.update(x: 0) // first move after reset just sets direction
        #expect(!afterReset)
    }
}

@Suite("Crumb particles")
struct CrumbEmitterTests {
    @Test func spawnsBehindTheEraser() {
        var emitter = CrumbEmitter(seed: 1)
        let eraser = Vec2(100, 50), forward = Vec2(1, 0)
        emitter.emit(count: 50, at: eraser, direction: forward, spread: 16)
        #expect(emitter.crumbs.count == 50)
        #expect(emitter.crumbs.allSatisfy { ($0.position - eraser).dot(forward) < 0 })
        #expect(emitter.crumbs.allSatisfy { $0.velocity.dot(forward) < 0 })   // thrown backwards
        #expect(emitter.crumbs.allSatisfy { $0.velocity.y < 0 })              // with an upward kick
    }

    @Test func seededEmittersAreDeterministic() {
        var a = CrumbEmitter(seed: 42), b = CrumbEmitter(seed: 42), c = CrumbEmitter(seed: 43)
        for e in [0, 1, 2] {
            _ = e
            a.emit(count: 5, at: Vec2(10, 10), direction: Vec2(-1, 0), spread: 8); a.step(dt: 1 / 60)
            b.emit(count: 5, at: Vec2(10, 10), direction: Vec2(-1, 0), spread: 8); b.step(dt: 1 / 60)
            c.emit(count: 5, at: Vec2(10, 10), direction: Vec2(-1, 0), spread: 8); c.step(dt: 1 / 60)
        }
        #expect(a.crumbs == b.crumbs)
        #expect(a.crumbs != c.crumbs)
    }

    @Test func gravityPullsCrumbsDown() throws {
        var emitter = CrumbEmitter(seed: 3)
        emitter.emit(count: 1, at: .zero, direction: Vec2(1, 0), spread: 8)
        let v0 = try #require(emitter.crumbs.first).velocity.y
        emitter.step(dt: 0.1)
        let v1 = try #require(emitter.crumbs.first).velocity.y
        #expect(v1 > v0)
    }

    @Test func crumbsFadeAndDie() {
        var emitter = CrumbEmitter(seed: 4)
        emitter.emit(count: 30, at: .zero, direction: Vec2(1, 0), spread: 8)
        var lastOpacity = emitter.crumbs.map(\.opacity)
        #expect(lastOpacity.allSatisfy { $0 == 1 })
        for _ in 0..<10 {
            emitter.step(dt: 1.0 / 30)
            let ids = Set(emitter.crumbs.map(\.id))
            let now = emitter.crumbs.map(\.opacity)
            #expect(now.count <= lastOpacity.count && ids.count == now.count)
            lastOpacity = now
        }
        // Max lifetime is 0.9 s: everything is gone after a second.
        for _ in 0..<30 { emitter.step(dt: 1.0 / 30) }
        #expect(emitter.isIdle)
    }

    @Test func opacityIsMonotonic() {
        var emitter = CrumbEmitter(seed: 5)
        emitter.emit(count: 1, at: .zero, direction: Vec2(1, 0), spread: 8)
        var previous = 1.0
        while let crumb = emitter.crumbs.first {
            #expect(crumb.opacity <= previous + 1e-12)
            previous = crumb.opacity
            emitter.step(dt: 1.0 / 120)
        }
    }

    @Test func emissionScalesWithTravelAndCarriesFractions() {
        var emitter = CrumbEmitter(seed: 6)   // 0.09 crumbs per point
        var total = 0
        for _ in 0..<100 { total += emitter.emit(forTravel: 5, at: .zero, direction: Vec2(1, 0), spread: 8) }
        #expect(total == 45)                   // 500 pt * 0.09, no crumbs lost to rounding
        #expect(emitter.emit(forTravel: 0, at: .zero, direction: Vec2(1, 0), spread: 8) == 0)
    }

    @Test func crumbCountIsCapped() {
        var emitter = CrumbEmitter(seed: 7)
        emitter.emit(count: 1000, at: .zero, direction: Vec2(1, 0), spread: 8)
        #expect(emitter.crumbs.count == emitter.configuration.maxCrumbs)
        #expect(emitter.crumbs.last?.id == 999)  // newest kept
    }

    @Test func invalidStepIsNoOp() {
        var emitter = CrumbEmitter(seed: 8)
        emitter.emit(count: 3, at: .zero, direction: Vec2(1, 0), spread: 8)
        let before = emitter.crumbs
        emitter.step(dt: 0); emitter.step(dt: -1); emitter.step(dt: .nan)
        #expect(emitter.crumbs == before)
    }
}
