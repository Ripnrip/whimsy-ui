import Foundation
import Testing
@testable import LouvreVentCore

private let span = LouvreVentTuning.defaultLower...LouvreVentTuning.defaultUpper

@Suite("Mapping") struct LouvreVentMappingTests {
    @Test func endpointsAreClosedAndOpen() {
        #expect(LouvreVentMath.angle(temperature: 60, range: span) == 0)
        #expect(LouvreVentMath.angle(temperature: 85, range: span) == 70)
        #expect(LouvreVentMath.unit(temperature: 60, range: span) == 0)
        #expect(LouvreVentMath.unit(temperature: 85, range: span) == 1)
        let cool = LouvreVentMath.glow(temperature: 60, range: span)
        let hot = LouvreVentMath.glow(temperature: 85, range: span)
        #expect(cool.red == LouvreVentTuning.coolRed)
        #expect(cool.green == LouvreVentTuning.coolGreen)
        #expect(cool.blue == LouvreVentTuning.coolBlue)
        #expect(cool.intensity == LouvreVentTuning.coolIntensity)
        #expect(hot.red == LouvreVentTuning.hotRed)
        #expect(hot.green == LouvreVentTuning.hotGreen)
        #expect(hot.blue == LouvreVentTuning.hotBlue)
        #expect(hot.intensity == LouvreVentTuning.hotIntensity)
        #expect(cool.red > cool.green)
        #expect(cool.green > cool.blue)
        #expect(hot.red - hot.blue < 0.12)
    }

    @Test func angleAndGlowAreStrictlyMonotonic() {
        var previousAngle = LouvreVentMath.angle(temperature: 60, range: span)
        var previous = LouvreVentMath.glow(temperature: 60, range: span)
        for temperature in 61...85 {
            let angle = LouvreVentMath.angle(temperature: temperature, range: span)
            let glow = LouvreVentMath.glow(temperature: temperature, range: span)
            #expect(angle > previousAngle)
            #expect(glow.red > previous.red)
            #expect(glow.green > previous.green)
            #expect(glow.blue > previous.blue)
            #expect(glow.intensity > previous.intensity)
            previousAngle = angle
            previous = glow
        }
    }

    @Test func theSameSetPointMapsTheSameWayTwice() {
        let first = LouvreVentMath.angle(temperature: 73, range: span)
        let second = LouvreVentMath.angle(temperature: 73, range: span)
        #expect(first == second)
        #expect(LouvreVentMath.glow(temperature: 73, range: span) == LouvreVentMath.glow(temperature: 73, range: span))
        let left = LouvreVentMath.slots(unit: 0.48, sweep: 0.2, reduceMotion: false)
        let right = LouvreVentMath.slots(unit: 0.48, sweep: 0.2, reduceMotion: false)
        #expect(left == right)
    }

    @Test func aCustomRangeUsesTheSameAngleSpan() {
        let range = 0...20
        #expect(LouvreVentMath.angle(temperature: 0, range: range) == 0)
        #expect(LouvreVentMath.angle(temperature: 10, range: range) == 35)
        #expect(LouvreVentMath.angle(temperature: 20, range: range) == 70)
        #expect(LouvreVentMath.angle(temperature: -5, range: range) == 0)
        #expect(LouvreVentMath.angle(temperature: 40, range: range) == 70)
    }

    @Test func aSingleDegreeRangeStaysClosed() {
        let range = 4...4
        #expect(LouvreVentMath.unit(temperature: 4, range: range) == 0)
        #expect(LouvreVentMath.angle(temperature: 4, range: range) == 0)
        #expect(LouvreVentMath.temperature(forSceneY: 0, range: range) == 4)
        #expect(LouvreVentMath.temperature(forSceneY: 900, range: range) == 4)
        let model = LouvreVentModel(temperature: 9, range: range)
        #expect(model.temperature == 4)
        #expect(model.displayAngle == 0)
    }

    @Test func specularStaysOnTheFaceAndDiffersPerBlade() {
        let offsets = (0..<LouvreVentTuning.bladeCount).map {
            LouvreVentMath.specular(blade: $0, unit: 0.45, sweep: 0, reduceMotion: false)
        }
        #expect(Set(offsets).count == LouvreVentTuning.bladeCount)
        for offset in offsets {
            #expect(offset >= 0)
            #expect(offset <= 1)
        }
        let outside = LouvreVentMath.specular(blade: 99, unit: 0.45, sweep: 0, reduceMotion: false)
        #expect(outside == offsets[LouvreVentTuning.bladeCount - 1])
    }

    @Test func specularSlidesDownTheFaceAsTheBladeOpens() {
        for blade in 0..<LouvreVentTuning.bladeCount {
            var previous = LouvreVentMath.specular(blade: blade, unit: 0, sweep: 0, reduceMotion: false)
            for step in 1...70 {
                let next = LouvreVentMath.specular(blade: blade, unit: Double(step) / 70, sweep: 0, reduceMotion: false)
                #expect(next >= previous)
                previous = next
            }
            #expect(previous > LouvreVentMath.specular(blade: blade, unit: 0, sweep: 0, reduceMotion: false))
        }
    }

    @Test func reduceMotionDropsTheSweep() {
        let rest = LouvreVentMath.specular(blade: 2, unit: 0.4, sweep: 0, reduceMotion: false)
        let moved = LouvreVentMath.specular(blade: 2, unit: 0.4, sweep: 1, reduceMotion: false)
        let ignored = LouvreVentMath.specular(blade: 2, unit: 0.4, sweep: 1, reduceMotion: true)
        #expect(moved > rest)
        #expect(ignored == rest)
        #expect(moved <= 1)
        let negative = LouvreVentMath.specular(blade: 2, unit: 0.4, sweep: -1, reduceMotion: false)
        #expect(negative < rest)
        #expect(negative >= 0)
    }

    @Test func theFaceShrinksAsItTurns() {
        let closed = LouvreVentMath.faceScale(angleDegrees: 0)
        #expect(abs(closed - 1) < 1e-8)
        var previous = closed
        for degree in 1...70 {
            let scale = LouvreVentMath.faceScale(angleDegrees: Double(degree))
            #expect(scale < previous)
            previous = scale
        }
        let open = LouvreVentMath.faceScale(angleDegrees: 70)
        #expect(open > 0.33)
        #expect(open < 0.36)
    }

    @Test func gapsWidenWhenTheBladesOpen() {
        let closed = LouvreVentMath.slots(unit: 0, sweep: 0, reduceMotion: true)
        let open = LouvreVentMath.slots(unit: 1, sweep: 0, reduceMotion: true)
        #expect(closed.count == 7)
        #expect(open.count == 7)
        #expect(closed[0].angle == 0)
        #expect(open[0].angle == 70)
        #expect(open[0].projectedHeight < closed[0].projectedHeight)
        #expect(open[0].gap > closed[0].gap)
        #expect(closed[0].gap > 0)
        #expect(closed[0].gap < closed[0].slotHeight * 0.1)
        #expect(open[0].gap > open[0].slotHeight * 0.25)
        for slot in closed {
            #expect(abs(slot.projectedHeight + slot.gap * 2 - slot.slotHeight) < 1e-9)
        }
        #expect(closed[1].slotTop > closed[0].slotTop)
        #expect(closed[6].centerY > closed[0].centerY)
        let glints = Set(open.map(\.specular))
        #expect(glints.count == 1)
        let staggered = Set(closed.map(\.specular))
        #expect(staggered.count == 7)
    }
}

@Suite("Set point") struct LouvreVentSetPointTests {
    @Test func valuesOutsideTheRangeClamp() {
        #expect(LouvreVentMath.clamp(59, to: span) == 60)
        #expect(LouvreVentMath.clamp(85, to: span) == 85)
        #expect(LouvreVentMath.clamp(86, to: span) == 85)
        #expect(LouvreVentMath.clamp(72, to: span) == 72)
        #expect(LouvreVentModel(temperature: -4).temperature == 60)
        #expect(LouvreVentModel(temperature: 300).temperature == 85)
        #expect(LouvreVentModel(temperature: 12, range: 10...30).temperature == 12)
        #expect(LouvreVentModel(temperature: 0, range: 10...30).temperature == 10)
    }

    @Test func everyDegreeTicksAndANoOpDoesNot() {
        var model = LouvreVentModel(temperature: 60)
        #expect(model.setTemperature(63) == [.tick(61), .tick(62), .tick(63)])
        #expect(model.temperature == 63)
        #expect(model.setTemperature(63).isEmpty)
        #expect(model.setTemperature(90).count == 22)
        #expect(model.temperature == 85)
        #expect(model.setTemperature(99).isEmpty)
        #expect(model.setTemperature(10).count == 25)
        #expect(model.temperature == 60)
        #expect(model.setTemperature(10).isEmpty)
    }

    @Test func adjustStepsOneDegreeAndStopsAtTheEnds() {
        var model = LouvreVentModel(temperature: 84)
        #expect(model.adjust(by: 0).isEmpty)
        #expect(model.temperature == 84)
        #expect(model.adjust(by: 1) == [.tick(85)])
        #expect(model.adjust(by: 1).isEmpty)
        #expect(model.adjust(by: -2) == [.tick(84), .tick(83)])
        var floor = LouvreVentModel(temperature: 60)
        #expect(floor.adjust(by: -1).isEmpty)
        #expect(floor.temperature == 60)
    }

    @Test func sceneYRoundTripsAndTheEndsStop() {
        for temperature in 60...85 {
            let y = LouvreVentMath.sceneY(forTemperature: temperature, range: span)
            #expect(LouvreVentMath.temperature(forSceneY: y, range: span) == temperature)
        }
        #expect(LouvreVentMath.temperature(forSceneY: 0, range: span) == 85)
        #expect(LouvreVentMath.temperature(forSceneY: 800, range: span) == 60)
        #expect(LouvreVentMath.temperature(forSceneY: .nan, range: span) == 60)
        #expect(LouvreVentMath.temperature(forSceneY: .infinity, range: span) == 60)
        let cool = LouvreVentMath.sceneY(forTemperature: 60, range: span)
        let hot = LouvreVentMath.sceneY(forTemperature: 85, range: span)
        #expect(hot < cool)
    }

    @Test func draggingUpHeatsAndASampleInsideOneDegreeIsQuiet() {
        var model = LouvreVentModel(temperature: 70)
        let y = LouvreVentMath.sceneY(forTemperature: 70, range: model.range)
        #expect(model.beginDrag(sceneY: y).isEmpty)
        #expect(model.isDragging)
        let band = LouvreVentTuning.openingHeight / 25
        #expect(model.updateDrag(sceneY: y + band * 0.15).isEmpty)
        #expect(model.temperature == 70)
        let hotter = LouvreVentMath.sceneY(forTemperature: 74, range: model.range)
        #expect(hotter < y)
        #expect(model.updateDrag(sceneY: hotter) == [.tick(71), .tick(72), .tick(73), .tick(74)])
        #expect(model.temperature == 74)
        model.endDrag()
        #expect(!model.isDragging)
        #expect(model.updateDrag(sceneY: hotter).isEmpty)
    }

    @Test func aNonFiniteDragDoesNotMoveTheSetPoint() {
        var model = LouvreVentModel(temperature: 66)
        #expect(model.beginDrag(sceneY: .nan).isEmpty)
        #expect(!model.isDragging)
        #expect(model.temperature == 66)
        #expect(model.beginDrag(sceneY: .infinity).isEmpty)
        let y = LouvreVentMath.sceneY(forTemperature: 66, range: model.range)
        #expect(model.beginDrag(sceneY: y).isEmpty)
        #expect(model.isDragging)
        #expect(model.updateDrag(sceneY: .nan).isEmpty)
        #expect(model.temperature == 66)
        model.step(.nan)
        model.step(-0.2)
        model.step(0)
        #expect(model.temperature == 66)
        #expect(model.displayAngle == model.targetAngle)
    }

    @Test func theReadoutNamesTheThermostatAndTheDegree() {
        let model = LouvreVentModel(temperature: 72)
        #expect(model.readout == "72")
        #expect(model.accessibilityLabel == "Louvre vent thermostat")
        #expect(model.accessibilityValue == "72 degrees")
        #expect(model.accessibilityHint == LouvreVentTuning.accessibilityHint)
    }
}

@Suite("Motion") struct LouvreVentMotionTests {
    @Test func fullMotionLagsThenSettlesAndTheHighlightSweeps() {
        var model = LouvreVentModel(temperature: 60)
        let start = model.displayAngle
        #expect(model.setTemperature(85).count == 25)
        #expect(model.targetAngle == 70)
        #expect(model.displayAngle == start)
        #expect(model.glow == LouvreVentMath.glow(unit: 0))
        model.step(1.0 / 60.0)
        #expect(model.displayAngle > start)
        #expect(model.displayAngle < 70)
        #expect(model.glow.intensity > LouvreVentTuning.coolIntensity)
        #expect(model.glow.intensity < LouvreVentTuning.hotIntensity)
        var sawSweep = false
        for _ in 0..<40 {
            model.step(1.0 / 60.0)
            if abs(model.sweepSignal) > 0.02 { sawSweep = true }
        }
        #expect(sawSweep)
        #expect(model.sweepEnvelope > 0.5)
        for _ in 0..<300 {
            model.step(1.0 / 60.0)
        }
        #expect(abs(model.displayAngle - 70) < 0.05)
        #expect(abs(model.glow.intensity - LouvreVentTuning.hotIntensity) < 0.01)
        #expect(model.sweepEnvelope < 0.02)
        #expect(!model.animates)
    }

    @Test func twoRunsOfTheSameDragMatch() {
        func run() -> (Double, LouvreGlow, Double) {
            var model = LouvreVentModel(temperature: 61)
            _ = model.setTemperature(77)
            model.step(0.016)
            model.step(0.016)
            return (model.displayAngle, model.glow, model.specularOffset(blade: 4))
        }
        let first = run()
        let second = run()
        #expect(first.0 == second.0)
        #expect(first.1 == second.1)
        #expect(first.2 == second.2)
    }

    @Test func reduceMotionSnapsAndDoesNotSweep() {
        var model = LouvreVentModel(temperature: 60, reduceMotion: true)
        #expect(model.setTemperature(85).count == 25)
        #expect(model.displayAngle == 70)
        #expect(model.glow == model.targetGlow)
        #expect(model.sweepEnvelope == 0)
        #expect(model.sweepSignal == 0)
        #expect(model.displayVelocity == 0)
        let spec = model.specularOffset(blade: 3)
        #expect(spec == LouvreVentMath.specular(blade: 3, unit: 1, sweep: 0.8, reduceMotion: true))
        model.step(0.5)
        #expect(model.displayAngle == 70)
        #expect(model.sweepEnvelope == 0)
        #expect(model.sweepPhase == 0)
        #expect(!model.animates)
        _ = model.beginDrag(sceneY: LouvreVentMath.sceneY(forTemperature: 64, range: span))
        #expect(model.displayAngle == LouvreVentMath.angle(temperature: 64, range: span))
        #expect(model.sweepSignal == 0)
        model.step(1.0 / 30.0)
        #expect(model.sweepEnvelope == 0)

        var live = LouvreVentModel(temperature: 60)
        _ = live.setTemperature(85)
        live.step(0.05)
        #expect(live.displayAngle < 70)
        #expect(live.sweepEnvelope > 0)
        live.setReduceMotion(true)
        #expect(live.displayAngle == 70)
        #expect(live.sweepEnvelope == 0)
        #expect(live.sweepPhase == 0)
        #expect(live.glow == live.targetGlow)
        live.setReduceMotion(true)
        #expect(live.displayAngle == 70)
    }

    @Test func aDragHoldsTheSweepOpen() {
        var model = LouvreVentModel(temperature: 60)
        let bottom = LouvreVentMath.sceneY(forTemperature: 60, range: span)
        #expect(model.beginDrag(sceneY: bottom).isEmpty)
        #expect(model.isDragging)
        model.step(1.0 / 60.0)
        #expect(model.sweepEnvelope > 0)
        for _ in 0..<24 {
            model.step(1.0 / 60.0)
        }
        #expect(abs(model.sweepSignal) > 0.02)
        let before = model.specularOffset(blade: 1)
        let rest = LouvreVentMath.restingSpecular(blade: 1, unit: model.displayedUnit)
        #expect(before != rest)
        model.endDrag()
        for _ in 0..<360 {
            model.step(1.0 / 60.0)
        }
        #expect(model.sweepEnvelope == 0)
        #expect(model.specularOffset(blade: 1) == LouvreVentMath.restingSpecular(blade: 1, unit: model.displayedUnit))
    }
}
