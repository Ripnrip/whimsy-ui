import Foundation
import Testing
@testable import LiquidCompassCore

private func close(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }

/// Steps at 60 fps for `seconds`, calling `each` after every frame.
@discardableResult
private func run(_ m: inout LiquidCompassModel, _ seconds: Double,
                 _ each: (LiquidCompassModel) -> Void = { _ in }) -> LiquidCompassModel {
    for _ in 0..<Int((seconds * 60).rounded()) { m.step(1.0 / 60); each(m) }
    return m
}

@Suite("Angle wrapping and bearings")
struct AngleTests {
    @Test func wrap360CoversAllRanges() {
        #expect(CompassMath.wrap360(0) == 0)
        #expect(CompassMath.wrap360(360) == 0)
        #expect(CompassMath.wrap360(725) == 5)
        #expect(CompassMath.wrap360(-10) == 350)
        #expect(CompassMath.wrap360(-720) == 0)
        #expect(close(CompassMath.wrap360(-1e-15), 0, 1e-9) || CompassMath.wrap360(-1e-15) < 360)
        #expect(CompassMath.wrap360(.nan) == 0 && CompassMath.wrap360(.infinity) == 0)
        for d in stride(from: -1000.0, through: 1000, by: 37.3) {
            let w = CompassMath.wrap360(d)
            #expect(w >= 0 && w < 360)
        }
    }

    @Test func wrap180IsHalfOpenAtMinus180() {
        #expect(CompassMath.wrap180(180) == 180)
        #expect(CompassMath.wrap180(-180) == 180)
        #expect(CompassMath.wrap180(190) == -170)
        #expect(CompassMath.wrap180(-190) == 170)
        #expect(CompassMath.wrap180(540) == 180)
        for d in stride(from: -900.0, through: 900, by: 13.7) {
            let w = CompassMath.wrap180(d)
            #expect(w > -180 && w <= 180)
        }
    }

    @Test func shortestDeltaTakesTheShortWayAcrossNorth() {
        #expect(CompassMath.shortestDelta(from: 350, to: 10) == 20)
        #expect(CompassMath.shortestDelta(from: 10, to: 350) == -20)
        #expect(CompassMath.shortestDelta(from: 90, to: 270) == 180) // half turn: reported +180
        #expect(CompassMath.shortestDelta(from: 0, to: 179) == 179)
        #expect(CompassMath.shortestDelta(from: 0, to: 181) == -179)
        #expect(CompassMath.shortestDelta(from: -720, to: 45) == 45)
        // Antisymmetric except at exactly 180.
        for (a, b) in [(12.0, 97.0), (300.0, 20.0), (5.0, 200.0)] {
            #expect(close(CompassMath.shortestDelta(from: a, to: b), -CompassMath.shortestDelta(from: b, to: a)))
        }
    }

    @Test func relativeBearingIsFriendMinusHeading() {
        #expect(CompassMath.relativeBearing(heading: 0, friendBearing: 90) == 90)    // to the right
        #expect(CompassMath.relativeBearing(heading: 90, friendBearing: 0) == -90)   // to the left
        #expect(CompassMath.relativeBearing(heading: 355, friendBearing: 5) == 10)
    }

    @Test func screenVectorUsesCompassConvention() {
        let up = CompassMath.screenVector(degrees: 0), right = CompassMath.screenVector(degrees: 90)
        #expect(close(up.x, 0) && close(up.y, -1))
        #expect(close(right.x, 1) && close(right.y, 0, 1e-12))
        let down = CompassMath.screenVector(degrees: 180)
        #expect(close(down.y, 1))
    }

    @Test func greatCircleBearingAndDistance() {
        let a = GeoCoordinate(latitude: 0, longitude: 0)
        #expect(close(CompassMath.bearing(from: a, to: .init(latitude: 1, longitude: 0)), 0))
        #expect(close(CompassMath.bearing(from: a, to: .init(latitude: 0, longitude: 1)), 90))
        #expect(close(CompassMath.bearing(from: a, to: .init(latitude: -1, longitude: 0)), 180))
        #expect(close(CompassMath.bearing(from: a, to: .init(latitude: 0, longitude: -1)), 270))
        // One degree of latitude ≈ 111.2 km on the mean sphere.
        let d = CompassMath.distance(from: a, to: .init(latitude: 1, longitude: 0))
        #expect(close(d, CompassMath.earthRadius * .pi / 180, 1e-6))
        // London → Paris ≈ 343.5 km, initial bearing ≈ 148°.
        let london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278)
        let paris = GeoCoordinate(latitude: 48.8566, longitude: 2.3522)
        #expect(abs(CompassMath.distance(from: london, to: paris) - 343_500) < 1_500)
        #expect(abs(CompassMath.bearing(from: london, to: paris) - 148.1) < 0.5)
        #expect(CompassMath.distance(from: paris, to: paris) == 0)
    }

    @Test func spokenDirection() {
        #expect(CompassMath.spokenDirection(relative: 2) == "dead ahead")
        #expect(CompassMath.spokenDirection(relative: -3.9) == "dead ahead")
        #expect(CompassMath.spokenDirection(relative: 30.4) == "30° to your right")
        #expect(CompassMath.spokenDirection(relative: -95) == "95° to your left")
        #expect(CompassMath.spokenDirection(relative: 170) == "behind you")
        #expect(CompassMath.spokenDirection(relative: 350) == "10° to your left")
    }

    @Test func fakeHeadingDragTurnsRightWhenDraggingRight() {
        var drag = FakeHeadingDrag(sensitivity: 0.5)
        drag.begin(at: 350)
        #expect(drag.heading(forTranslation: 40) == 10) // wraps through north
        #expect(drag.heading(forTranslation: -100) == 300)
        #expect(drag.heading(forTranslation: .nan) == 350)
    }
}

@Suite("Spring integrator")
struct SpringTests {
    @Test func underdampedSpringOvershootsByTheTheoreticalAmount() {
        var s = DampedSpring(value: 0, stiffness: 70, dampingRatio: 0.38)
        var peak = 0.0
        for _ in 0..<600 { s.step(toward: 1, dt: 1.0 / 60); peak = max(peak, s.value) }
        #expect(peak > 1.2)
        #expect(abs((peak - 1) - s.theoreticalOvershoot) < 0.02)
        #expect(s.isSettled(at: 1))
    }

    @Test func criticallyDampedSpringNeverOvershoots() {
        var s = DampedSpring(value: 0, stiffness: 120, dampingRatio: 1)
        var peak = 0.0
        for _ in 0..<300 { s.step(toward: 1, dt: 1.0 / 60); peak = max(peak, s.value) }
        #expect(peak <= 1 + 1e-9)
        #expect(s.theoreticalOvershoot == 0)
        #expect(abs(s.value - 1) < 1e-3)
    }

    @Test func frameRateIndependent() {
        var a = DampedSpring(value: 0, stiffness: 140, dampingRatio: 0.28)
        var b = a
        for _ in 0..<120 { a.step(toward: 5, dt: 1.0 / 120) }
        for _ in 0..<30 { b.step(toward: 5, dt: 1.0 / 30) }
        #expect(abs(a.value - b.value) < 1e-9) // both are 240 Hz substeps underneath
    }

    @Test func badInputIsIgnoredAndHugeStepsClamped() {
        var s = DampedSpring(value: 2, velocity: 1, stiffness: 50, dampingRatio: 0.5)
        let before = s
        s.step(toward: 0, dt: .nan); s.step(toward: 0, dt: -1); s.step(toward: .infinity, dt: 0.1)
        #expect(s == before)
        var big = before, capped = before
        big.step(toward: 0, dt: 5); capped.step(toward: 0, dt: 0.1)
        #expect(big == capped)
        s.snap(to: 3)
        #expect(s.value == 3 && s.velocity == 0)
    }

    @Test func energyDecays() {
        var s = DampedSpring(value: 1, stiffness: 100, dampingRatio: 0.2)
        func energy(_ s: DampedSpring) -> Double { 0.5 * s.stiffness * s.value * s.value + 0.5 * s.velocity * s.velocity }
        var last = energy(s)
        for _ in 0..<120 {
            s.step(toward: 0, dt: 1.0 / 60)
            let e = energy(s)
            #expect(e <= last * (1 + 1e-3))
            last = e
        }
        #expect(last < 0.01 * 50)
    }
}

@Suite("Blob geometry")
struct BlobTests {
    let g = BlobGeometry(radius: 68, samples: 120)

    @Test func zeroStretchIsTheCircle() {
        let pts = g.outline(angle: 37, stretch: 0, center: Vec2(10, 20))
        #expect(pts.count == 120)
        for p in pts { #expect(close(p.distance(to: Vec2(10, 20)), 68, 1e-9)) }
        #expect(close(pts[0].x, 10, 1e-9) && close(pts[0].y, 20 - 68, 1e-9)) // vertex 0 points up
    }

    @Test func areaIsConservedAtAnyStretch() {
        let circle = BlobGeometry.area(of: g.outline(angle: 0, stretch: 0))
        for s in [0.1, 0.34, 0.6, 0.8, 1.5] {
            for a in [0.0, 45, 133, -90, 180] {
                let area = BlobGeometry.area(of: g.outline(angle: a, stretch: s))
                #expect(abs(area - circle) / circle < 1e-9)
            }
        }
        #expect(abs(circle - .pi * 68 * 68) / (.pi * 68 * 68) < 1e-3) // 120-gon ≈ circle
    }

    @Test func tipPointsAlongTheLeanAngle() {
        for a in [0.0, 30, 90, 135, 180, -60] {
            let pts = g.outline(angle: a, stretch: 0.5)
            let dir = CompassMath.screenVector(degrees: a)
            let tip = pts.max { $0.dot(dir) < $1.dot(dir) }!
            let tipAngle = atan2(tip.x, -tip.y) * 180 / .pi
            #expect(abs(CompassMath.shortestDelta(from: a, to: tipAngle)) <= 3.0 + 1e-9) // one sample
            // The tip reaches further than the resting radius, the far side less.
            #expect(tip.dot(dir) > 68 * 1.2)
            let tail = pts.min { $0.dot(dir) < $1.dot(dir) }!
            #expect(-tail.dot(dir) < 68)
        }
    }

    @Test func stretchElongatesAlongTheAxis() {
        func extents(_ s: Double) -> (along: Double, across: Double) {
            let pts = g.outline(angle: 90, stretch: s)
            let xs = pts.map(\.x), ys = pts.map(\.y)
            return (xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        }
        let a = extents(0.2), b = extents(0.6)
        #expect(a.along > a.across)
        #expect(b.along / b.across > a.along / a.across)
    }

    @Test func outlineIsSymmetricAboutTheLeanAxis() {
        let pts = g.outline(angle: 0, stretch: 0.5) // axis = vertical
        let n = pts.count
        for k in 1..<(n / 2) {
            let p = pts[k], q = pts[n - k]
            #expect(close(p.x, -q.x, 1e-9) && close(p.y, q.y, 1e-9))
        }
    }

    @Test func centroidLeansTowardTheFriend() {
        let pts = g.outline(angle: 90, stretch: 0.5)
        let c = BlobGeometry.centroid(of: pts)
        #expect(c.x > 5 && abs(c.y) < 1e-6)
        #expect(close(BlobGeometry.centroid(of: g.outline(angle: 0, stretch: 0)).x, 0, 1e-9))
    }

    @Test func degenerateInputsAreSafe() {
        let neg = g.outline(angle: 0, stretch: -1), zero = g.outline(angle: 0, stretch: 0)
        #expect(neg == zero)
        #expect(g.outline(angle: 0, stretch: .nan) == zero)
        #expect(BlobGeometry(samples: 3).samples == 8)
        #expect(BlobGeometry.area(of: [Vec2(0, 0), Vec2(1, 1)]) == 0)
    }
}

@Suite("Alignment detector")
struct AlignmentTests {
    @Test func entersInsideFourDegreesAndTicksOnce() {
        var d = AlignmentDetector()
        let ticked1 = d.update(relativeBearing: 6, time: 0)
        #expect(!ticked1)
        #expect(!d.isAligned)
        let ticked2 = d.update(relativeBearing: 3.5, time: 0.1)
        #expect(ticked2)
        #expect(d.isAligned && d.tickCount == 1)
        for i in 0..<20 { d.update(relativeBearing: Double(i % 3) - 1, time: 0.2 + Double(i) * 0.05) }
        #expect(d.tickCount == 1) // staying aligned is silent
    }

    @Test func hysteresisBandDoesNotChatter() {
        var d = AlignmentDetector(enter: 4, exit: 8)
        // Never entered: wobbling between 5 and 7.5 does nothing.
        for i in 0..<40 { d.update(relativeBearing: i.isMultiple(of: 2) ? 5 : 7.5, time: Double(i)) }
        #expect(!d.isAligned && d.tickCount == 0)
        // Entered: the same wobble keeps it aligned.
        d.update(relativeBearing: 0, time: 50)
        for i in 0..<40 { d.update(relativeBearing: i.isMultiple(of: 2) ? -5 : 7.9, time: 51 + Double(i)) }
        #expect(d.isAligned && d.tickCount == 1)
        d.update(relativeBearing: 8.1, time: 100)
        #expect(!d.isAligned)
        d.update(relativeBearing: -3, time: 101)
        #expect(d.isAligned && d.tickCount == 2)
    }

    @Test func cooldownSuppressesRapidRetriggers() {
        var d = AlignmentDetector(enter: 4, exit: 8, cooldown: 0.35)
        d.update(relativeBearing: 0, time: 1.0)
        d.update(relativeBearing: 20, time: 1.1)
        let ticked1 = d.update(relativeBearing: 0, time: 1.2)
        #expect(ticked1 == false) // re-aligned, but too soon
        #expect(d.isAligned && d.tickCount == 1)
        d.update(relativeBearing: 20, time: 1.3)
        let ticked2 = d.update(relativeBearing: 0, time: 1.5)
        #expect(ticked2) // 0.5 s since the last tick
        #expect(d.tickCount == 2)
    }

    @Test func wrapsAndIgnoresNaN() {
        var d = AlignmentDetector()
        d.update(relativeBearing: 358, time: 0) // = -2°
        #expect(d.isAligned && d.tickCount == 1)
        d.update(relativeBearing: .nan, time: 1)
        #expect(d.isAligned)
        var e = AlignmentDetector(enter: 10, exit: 3)
        #expect(e.exit == 10) // exit is never tighter than enter
        e.reset()
        #expect(!e.isAligned)
    }

    @Test func suppressedFirstAlignmentDoesNotTick() {
        var d = AlignmentDetector()
        d.suppressNextAlignmentTick()
        let ticked1 = d.update(relativeBearing: 1, time: 0)
        #expect(!ticked1)
        #expect(d.isAligned && d.tickCount == 0)
        d.update(relativeBearing: 30, time: 1); d.update(relativeBearing: 0, time: 2)
        #expect(d.tickCount == 1)
    }
}

@Suite("Distance formatting")
struct DistanceTests {
    private func m(_ x: Double) -> String { DistanceFormatting.format(metres: x).description }
    private func i(_ x: Double) -> String { DistanceFormatting.format(metres: x, units: .imperial).description }

    @Test func metricBands() {
        #expect(m(0) == "0 m")
        #expect(m(7.4) == "7 m")
        #expect(m(99.4) == "99 m")
        #expect(m(99.6) == "100 m")
        #expect(m(853) == "850 m")
        #expect(m(994) == "990 m")
        #expect(m(996) == "1.0 km") // rounds up into the next band
        #expect(m(1_234) == "1.2 km")
        #expect(m(9_949) == "9.9 km")
        #expect(m(9_960) == "10 km")
        #expect(m(12_600) == "13 km")
        #expect(m(1_234_567) == "1,235 km")
    }

    @Test func imperialBands() {
        #expect(i(30) == "100 ft")         // 98.4 ft → 100
        #expect(i(76) == "250 ft")         // 249.3 ft → 250
        #expect(i(150) == "0.1 mi")        // 0.093 mi rounds to 0.1 mi
        #expect(i(1_609.344) == "1.0 mi")
        #expect(i(2_000) == "1.2 mi")
        #expect(i(20_000) == "12 mi")
        #expect(i(2_000_000) == "1,243 mi")
    }

    @Test func numberValueUnitAndSpeech() {
        let d = DistanceFormatting.format(metres: 1_234)
        #expect(d.value == 1.2 && d.number == "1.2" && d.unit == "km")
        #expect(d.spoken == "1.2 kilometres")
        #expect(DistanceFormatting.format(metres: 76, units: .imperial).spoken == "250 feet")
    }

    @Test func badInputBecomesZero() {
        #expect(m(-5) == "0 m")
        #expect(m(.nan) == "0 m")
        #expect(m(.infinity) == "0 m")
        #expect(DistanceFormatting.grouped(-1234) == "-1,234")
        #expect(DistanceFormatting.grouped(999) == "999")
    }
}

@Suite("Compass model")
struct ModelTests {
    @Test func blobPointsAtTheFriendRelativeToHeading() {
        var m = LiquidCompassModel(heading: 0, friendBearing: 60)
        #expect(close(m.leanAngle, 60))
        m.setHeading(100)
        run(&m, 4)
        #expect(abs(m.leanAngle - (-40)) < 0.05) // friend is now 40° to the left
        #expect(m.isSettled)
    }

    @Test func headingChangeOvershootsAndWobbles() {
        var m = LiquidCompassModel(heading: 0, friendBearing: 0)
        m.setHeading(-60) // friend now 60° to the right
        var peak = 0.0, crossings = 0, last = m.leanAngle - 60
        run(&m, 3) { s in
            peak = max(peak, s.leanAngle)
            let e = s.leanAngle - 60
            if (e > 0) != (last > 0) { crossings += 1 }
            last = e
        }
        #expect(peak > 60 * 1.15)   // overshoots
        #expect(crossings >= 2)     // swings back and forth
        #expect(abs(m.leanAngle - 60) < 0.5)
    }

    @Test func swingStretchesTheBlobThenItRelaxes() {
        var m = LiquidCompassModel(heading: 0, friendBearing: 0)
        let rest = m.stretch
        m.setHeading(120)
        var maxStretch = 0.0
        run(&m, 0.6) { maxStretch = max(maxStretch, $0.stretch) }
        #expect(maxStretch > rest + 0.1)
        #expect(maxStretch <= m.tuning.maxStretch)
        run(&m, 4)
        #expect(abs(m.stretch - m.tuning.baseStretch) < 1e-3)
    }

    @Test func turnsTheShortWayAcrossTheSeam() {
        // Friend at 170° relative → heading changes so it's at -170°: 20° turn, not 340°.
        var m = LiquidCompassModel(heading: 0, friendBearing: 170)
        m.setHeading(20) // relative 150
        run(&m, 3)
        m.setHeading(340) // relative 190 = -170
        var minRaw = Double.infinity, maxRaw = -Double.infinity
        run(&m, 3) { minRaw = min(minRaw, $0.angleSpring.value); maxRaw = max(maxRaw, $0.angleSpring.value) }
        #expect(maxRaw - minRaw < 60) // swung ~40° (plus overshoot), never the long way round
        #expect(abs(CompassMath.shortestDelta(from: m.leanAngle, to: -170)) < 0.5)
    }

    @Test func ticksWhenTurningOntoTheFriend() {
        var m = LiquidCompassModel(heading: 0, friendBearing: 90)
        #expect(m.tickCount == 0 && !m.isAligned)
        for h in stride(from: 0.0, through: 92, by: 1) { m.setHeading(h); m.step(1.0 / 60) }
        #expect(m.isAligned && m.tickCount == 1)
        run(&m, 1)
        #expect(m.glow > 0.95)
        m.setHeading(70); m.step(1.0 / 60)
        #expect(!m.isAligned)
    }

    @Test func startingAlignedDoesNotTick() {
        var m = LiquidCompassModel(heading: 45, friendBearing: 46)
        #expect(m.isAligned && m.tickCount == 0 && m.glow == 1)
        run(&m, 1)
        #expect(m.tickCount == 0)
    }

    @Test func reduceMotionTurnsWithoutOvershootOrSwingStretch() {
        var m = LiquidCompassModel(heading: 0, friendBearing: 0, reduceMotion: true)
        m.setHeading(-60)
        var peak = 0.0, maxStretch = 0.0
        run(&m, 3) { peak = max(peak, $0.leanAngle); maxStretch = max(maxStretch, $0.stretch) }
        #expect(peak <= 60 + 1e-6)
        #expect(abs(maxStretch - m.tuning.baseStretch) < 1e-9)
        #expect(abs(m.leanAngle - 60) < 0.05)
    }

    @Test func outlineFollowsTheModel() {
        var m = LiquidCompassModel(heading: 0, friendBearing: 90)
        run(&m, 2)
        let pts = m.outline(center: Vec2(200, 300))
        #expect(BlobGeometry.centroid(of: pts).x > 200)
        let geo = m.tuning.geometry
        #expect(pts == geo.outline(angle: m.leanAngle, stretch: m.stretch, center: Vec2(200, 300)))
    }

    @Test func manySpinsStayBoundedAndBadInputIsIgnored() {
        var m = LiquidCompassModel(heading: 0, friendBearing: 0)
        for k in 0..<400 { m.setHeading(Double(k) * -15); m.step(1.0 / 60) } // 16 full turns
        #expect(abs(m.angleSpring.value) <= 720 + 400)
        let before = m
        m.setHeading(.nan); m.setFriendBearing(.infinity); m.step(.nan); m.step(-1)
        #expect(m == before)
        m.setFriendBearing(-90)
        #expect(m.friendBearing == 270)
    }
}
