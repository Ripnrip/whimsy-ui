import Foundation
import Testing
@testable import NeighborBounceCore

@Suite("Layout and ticks") struct LayoutTests {
    @Test func countClampsToFiveThroughSeven() {
        #expect(NeighborBounceLayout.clampedCount(0) == 5)
        #expect(NeighborBounceLayout.clampedCount(4) == 5)
        #expect(NeighborBounceLayout.clampedCount(5) == 5)
        #expect(NeighborBounceLayout.clampedCount(6) == 6)
        #expect(NeighborBounceLayout.clampedCount(7) == 7)
        #expect(NeighborBounceLayout.clampedCount(80) == 7)
        #expect(NeighborBounceModel(count: 1).count == 5)
        #expect(NeighborBounceModel(count: 9, selection: 40).count == 7)
        #expect(NeighborBounceModel(count: 9, selection: 40).selection == 6)
        #expect(NeighborBounceModel(count: 6, selection: -4).selection == 0)
    }

    @Test func rowIsCentredWithAConstantPitch() {
        let pitch = NeighborBounceLayout.tickDiameter + NeighborBounceLayout.gap
        #expect(pitch == 56)
        for n in 5...7 {
            let xs = (0..<n).map { NeighborBounceLayout.restCenter(index: $0, count: n).x }
            for i in 1..<n {
                #expect(abs(xs[i] - xs[i - 1] - pitch) < 1e-9)
            }
            let mid = (xs[0] + xs[n - 1]) / 2
            #expect(abs(mid - NeighborBounceLayout.canvasWidth / 2) < 1e-9)
            for i in 0..<n {
                #expect(NeighborBounceLayout.restCenter(index: i, count: n).y == NeighborBounceLayout.restY)
            }
        }
    }

    @Test func sixTickRowSitsOnKnownCentres() {
        #expect(NeighborBounceLayout.restCenter(index: 0, count: 6).x == 62)
        #expect(NeighborBounceLayout.restCenter(index: 1, count: 6).x == 118)
        #expect(NeighborBounceLayout.restCenter(index: 5, count: 6).x == 62 + 5 * 56)
        #expect(NeighborBounceLayout.restCenter(index: -1, count: 6).x == 62)
        #expect(NeighborBounceLayout.restCenter(index: 9, count: 6).x == 62 + 5 * 56)
    }

    @Test func hitTestPicksTheNearestSlotAndGivesTiesLeft() {
        #expect(NeighborBounceLayout.index(atX: 62, count: 6) == 0)
        #expect(NeighborBounceLayout.index(atX: -100, count: 6) == 0)
        #expect(NeighborBounceLayout.index(atX: 10_000, count: 6) == 5)
        #expect(NeighborBounceLayout.index(atX: .nan, count: 6) == 0)
        let mid = (62.0 + 118.0) / 2
        #expect(NeighborBounceLayout.index(atX: mid, count: 6) == 0)
        #expect(NeighborBounceLayout.index(atX: mid + 0.1, count: 6) == 1)
        #expect(NeighborBounceLayout.index(atX: 118, count: 5) == NeighborBounceLayout.index(atX: 118, count: 5))
    }

    @Test func fittedTicksStayInsideFiveToSeven() {
        #expect(NeighborTick.fitted([]).map(\.id) == NeighborTick.demo.map(\.id))
        let eight = (0..<8).map { NeighborTick(id: "t\($0)", title: "T\($0)", red: 0, green: 0, blue: 0) }
        let capped = NeighborTick.fitted(eight)
        #expect(capped.count == 7)
        #expect(capped.map(\.id) == (0..<7).map { "t\($0)" })
        let three = Array(eight.prefix(3))
        let padded = NeighborTick.fitted(three)
        #expect(padded.count == 5)
        #expect(padded[0].id == "t0")
        #expect(padded[3].id == "tick-4")
        #expect(padded[3].title == "4")
        #expect(padded[3].red == NeighborTick.demo[3].red)
        let six = NeighborTick.fitted(NeighborTick.demo)
        #expect(six.count == 6)
    }

    @Test func spokenSelectionUsesTheTitleOrANumber() {
        var model = NeighborBounceModel(count: 6, selection: 3)
        #expect(model.spokenSelection(titles: NeighborTick.demo.map(\.title)) == "Gold, selected")
        _ = model.select(0)
        #expect(model.spokenSelection(titles: ["", "Sage"]) == "Tick 1, selected")
        #expect(model.spokenSelection(titles: []) == "Tick 1, selected")
    }
}

@Suite("Wave impulse") struct WaveTests {
    @Test func distanceOneIsAThreeFourFiveKick() {
        let right = NeighborBounceWave.impulse(distance: 1, sign: 1)
        let left = NeighborBounceWave.impulse(distance: 1, sign: -1)
        #expect(right.x == 720)
        #expect(right.y == -960)
        #expect(left.x == -720)
        #expect(left.y == -960)
    }

    @Test func amplitudeDecaysByFiveEighthsAndZeroDistanceIsStill() {
        let d2 = NeighborBounceWave.impulse(distance: 2, sign: 1)
        let d3 = NeighborBounceWave.impulse(distance: 3, sign: 1)
        #expect(d2.x == 450)
        #expect(d2.y == -600)
        #expect(d3.x == 281.25)
        #expect(d3.y == -375)
        #expect(NeighborBounceWave.impulse(distance: 0, sign: 1) == .zero)
        #expect(NeighborBounceWave.impulse(distance: 2, sign: 0) == .zero)
        #expect(NeighborBounceWave.impulse(distance: 2, sign: .nan) == .zero)
        var previous = NeighborBounceWave.impulse(distance: 1, sign: 1).y
        for d in 2...6 {
            let y = NeighborBounceWave.impulse(distance: d, sign: 1).y
            #expect(y < 0)
            #expect(abs(y) < abs(previous))
            previous = y
        }
    }
}
