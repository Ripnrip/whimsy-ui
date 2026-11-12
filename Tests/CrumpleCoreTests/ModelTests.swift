import Testing
@testable import CrumpleCore

/// Card center (100, 70). Bin is wide enough that progress 0.4 on the axis is inside,
/// and a point with the same progress but a large y offset is outside.
private let card = CrumpleRect(x: 0, y: 0, width: 200, height: 140)
private let bin = CrumpleRect(x: 150, y: 40, width: 220, height: 60)

private func model(reduceMotion: Bool = false) -> CrumpleModel {
    CrumpleModel(card: card, bin: bin, reduceMotion: reduceMotion)
}

private func finger(_ progress: Double, y: Double? = nil) -> Vec2 {
    let axis = bin.center - card.center
    let point = card.center + axis * progress
    guard let y else { return point }
    return Vec2(point.x, y)
}

@Suite("Crumple gesture") struct ModelTests {
    @Test func earlyReleaseSpringsFlat() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.5, y: 0))
        #expect(m.progress > 0.49 && m.progress < 0.51)
        #expect(m.end().isEmpty)
        let ev = m.run(2)
        #expect(m.phase == .idle)
        #expect(m.progress < 0.01)
        #expect(m.shape < 0.01)
        #expect(!ev.contains(.committed) && !m.log.contains(.committed))
    }

    @Test func releaseAtCommitLineTosses() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.8, y: 0))
        #expect(m.bin.contains(m.center) == false)
        let end = m.end()
        #expect(end == [.committed])
        let ev = m.run(2)
        #expect(ev.contains(.arrived))
        #expect(ev.contains(.lidBump))
        #expect(m.phase == .gone)
        #expect(m.log.contains(.committed))
    }

    @Test func releaseJustBelowOutsideDoesNotCommit() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.799, y: 0))
        #expect(m.end().isEmpty)
        _ = m.run(2)
        #expect(m.phase == .idle)
        #expect(!m.log.contains(.committed))
    }

    @Test func droppingBelowTheLineDisarms() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.9, y: 0))
        _ = m.drag(to: finger(0.799, y: 0))
        #expect(m.end().isEmpty)
        _ = m.run(2)
        #expect(!m.log.contains(.committed))
    }

    @Test func releaseInsideTheBinCommitsBelowTheLine() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.4))
        #expect(m.progress < 0.8)
        #expect(m.bin.contains(m.center))
        #expect(m.end() == [.committed])
    }

    @Test func leavingTheBinSpringsFlat() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.4))
        #expect(m.bin.contains(m.center))
        _ = m.drag(to: finger(0.5, y: 0))
        #expect(m.bin.contains(m.center) == false)
        #expect(m.progress < 0.8)
        #expect(m.end().isEmpty)
        _ = m.run(2)
        #expect(m.phase == .idle)
        #expect(!m.log.contains(.committed))
    }

    @Test func eachEdgeCreasesOncePerGesture() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        let first = m.drag(to: finger(1))
        let ids = first.compactMap { if case .crease(let id) = $0 { return id } else { return nil } }
        #expect(!ids.isEmpty)
        #expect(Set(ids).count == ids.count)
        let before = m.log.filter { if case .crease = $0 { return true } else { return false } }.count
        _ = m.drag(to: finger(0.2))
        _ = m.drag(to: finger(1))
        let after = m.log.filter { if case .crease = $0 { return true } else { return false } }.count
        #expect(after == before)
        #expect(m.end() == [.committed] || m.progress >= 0.8)
        _ = m.run(2)
        #expect(m.reset() == true)
        _ = m.run(2)
        #expect(m.phase == .idle)
        #expect(m.begin(at: card.center) == true)
        let again = m.drag(to: finger(1))
        #expect(!again.isEmpty)
    }

    @Test func oneStepEmitsEveryEdgeItCrossesInOrder() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        let ev = m.drag(to: finger(1))
        let ids = ev.compactMap { if case .crease(let id) = $0 { return id } else { return nil } }
        #expect(ids == ids.sorted())
        #expect(ids.count >= 3)
    }

    @Test func springAndTossDoNotCrease() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.4, y: 0))
        #expect(m.end().isEmpty)
        let back = m.run(2)
        #expect(back.allSatisfy { if case .crease = $0 { return false } else { return true } })
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.8, y: 0))
        _ = m.end()
        let flight = m.run(2)
        #expect(flight.allSatisfy { if case .crease = $0 { return false } else { return true } })
    }

    @Test func cancelSpringsFlat() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.85, y: 0))
        _ = m.cancel()
        _ = m.run(2)
        #expect(m.phase == .idle)
        #expect(!m.log.contains(.committed))
    }

    @Test func pressDuringSpringBackClearsLatches() {
        var m = model()
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.4, y: 0))
        #expect(m.end().isEmpty)
        #expect(m.phase == .springing)
        _ = m.step(1.0 / 60)
        #expect(m.phase == .springing)
        let point = m.center
        #expect(m.begin(at: point) == true)
        #expect(m.zoneLatched == m.bin.contains(m.center))
        let creases = m.drag(to: finger(1))
        #expect(!creases.isEmpty)
    }

    @Test func pressDuringTossIsIgnored() {
        var m = model()
        #expect(m.commit() == [.committed])
        #expect(m.begin(at: card.center) == false)
        #expect(m.phase == .tossing)
    }

    @Test func resetBeforeArrivalSkipsTheBin() {
        var m = model()
        _ = m.commit()
        #expect(m.reset() == true)
        let ev = m.run(2)
        #expect(!ev.contains(.arrived) && !m.log.contains(.arrived))
        #expect(!m.log.contains(.lidBump))
        #expect(m.phase == .idle)
        #expect(ev.contains(.restored))
    }

    @Test func resetAfterArrivalReturnsOnce() {
        var m = model()
        _ = m.commit()
        _ = m.run(2)
        #expect(m.phase == .gone)
        #expect(m.reset() == true)
        #expect(m.reset() == false)
        _ = m.run(2)
        #expect(m.phase == .idle)
    }

    @Test func reduceMotionFadesWithoutALid() {
        var m = model(reduceMotion: true)
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: finger(0.8, y: 0))
        #expect(m.end() == [.committed])
        let ev = m.run(1)
        #expect(ev.contains(.arrived))
        #expect(!ev.contains(.lidBump))
        #expect(!m.log.contains(.lidBump))
        #expect(m.phase == .gone)
    }

    @Test func zeroAreaBinNeverZones() {
        var m = CrumpleModel(card: card, bin: CrumpleRect(x: 10, y: 10, width: 0, height: 20))
        #expect(m.begin(at: card.center) == true)
        _ = m.drag(to: card.center + Vec2(12, 0))
        #expect(m.zoneLatched == false)
        #expect(m.progress < 0.8)
        #expect(m.end().isEmpty)
    }

    @Test func voiceOverCommitsFromIdleAndNotDuringToss() {
        var m = model()
        #expect(m.commit() == [.committed])
        let ev = m.run(2)
        #expect(ev.contains(.arrived) && ev.contains(.lidBump))
        var mid = model()
        #expect(mid.begin(at: card.center) == true)
        _ = mid.drag(to: finger(0.3, y: 0))
        #expect(mid.progress < 0.8)
        #expect(mid.commit() == [.committed])
        #expect(mid.commit().isEmpty)
        #expect(mid.phase == .tossing)
    }

    @Test func outsideTouchDoesNotBegin() {
        var m = model()
        #expect(m.begin(at: Vec2(-10, -10)) == false)
        #expect(m.phase == .idle)
    }
}
