import Testing
@testable import VelocityGlyphCore

private extension VelocityGlyphModel {
    mutating func frames(_ count: Int, dt: Double = 1.0 / 60) {
        for _ in 0..<count { step(dt) }
    }

    func pose(_ role: GlyphRole) -> GlyphPose? {
        poses.first { $0.id == role }
    }
}

private func values(_ events: [VelocityGlyphEvent]) -> [Int] {
    events.map { event in
        guard case .step(let value) = event else { return -1 }
        return value
    }
}

@Suite("Drag, steps and springs") struct ModelTests {
    @Test func startsSnappedAndQuiet() {
        let model = VelocityGlyphModel(value: 42)
        #expect(model.value == 40)
        #expect(model.formattedPrice == "$40")
        #expect(model.phase == .idle)
        #expect(model.smoothedSpeed == 0)
        #expect(model.blurRadius == 0)
        #expect(model.isVisuallySettled)
        #expect(model.poses.allSatisfy { $0.offsetY == 0 && $0.leanDegrees == 0 })
        let halfway = VelocityGlyphModel(value: 43, range: 40...600, step: 5)
        #expect(halfway.value == 45)
    }

    @Test func aJumpEmitsEveryCrossingOnce() {
        var model = VelocityGlyphModel(value: 40)
        let events = model.setValue(60)
        #expect(values(events) == [45, 50, 55, 60])
        #expect(model.value == 60 && model.formattedPrice == "$60")
        #expect(model.setValue(60).isEmpty)
        #expect(model.setValue(61).isEmpty) // still snaps to 60
    }

    @Test func draggingAcrossTheTrackTicksEachStepOncePerDirection() {
        var model = VelocityGlyphModel(value: 100)
        let width = VelocityGlyphTuning.trackWidth
        _ = model.beginDrag(atX: model.span.x(for: 100, width: width))
        #expect(model.phase == .dragging)
        let up = model.updateDrag(atX: model.span.x(for: 200, width: width))
        #expect(values(up) == Array(stride(from: 105, through: 200, by: 5)))
        let held = model.updateDrag(atX: model.span.x(for: 200, width: width))
        #expect(held.isEmpty)
        model.frames(8)
        #expect(model.updateDrag(atX: model.span.x(for: 200, width: width)).isEmpty)
        let down = model.updateDrag(atX: model.span.x(for: 100, width: width))
        #expect(values(down) == Array(stride(from: 195, through: 100, by: -5)))
    }

    @Test func wigglingOneBoundaryTicksOnEveryCrossing() {
        var model = VelocityGlyphModel(value: 100)
        let width = VelocityGlyphTuning.trackWidth
        _ = model.beginDrag(atX: model.span.x(for: 100, width: width))
        var seen: [Int] = []
        for price in [105, 100, 105, 100] {
            seen += values(model.updateDrag(atX: model.span.x(for: price, width: width)))
        }
        #expect(seen == [105, 100, 105, 100])
        #expect(model.value == 100)
    }

    @Test func thumbSpeedIsSmoothedAndClampedIntoTheScatter() {
        let role = GlyphRole.currency
        let unit = VelocityGlyphMath.signedAmplitude(for: role)
        var paced = VelocityGlyphModel(value: 40)
        _ = paced.beginDrag(atX: 0)
        // 4 pt per 1/60 s = 240 pt/s, half of fullSpeed, for long enough that the spring catches.
        for x in stride(from: 4.0, through: 200, by: 4) {
            _ = paced.updateDrag(atX: x)
            paced.step(1.0 / 60)
        }
        #expect(abs(paced.smoothedSpeed - 240) < 8)
        let pose = paced.pose(role)!
        let expected = unit * VelocityGlyphTuning.maxOffset * 0.5
        #expect(abs(pose.offsetY - expected) < 0.6)
        #expect(abs(pose.leanDegrees - unit * VelocityGlyphTuning.maxLean * 0.5) < 0.25)
        #expect(abs(pose.offsetY) <= VelocityGlyphTuning.maxOffset + 0.01)
        #expect(paced.blurRadius > 0.35)
        #expect(paced.blurRadius <= VelocityGlyphTuning.maxBlur + 0.01)

        // A spike past fullSpeed still cannot push a settled glyph past the clamp.
        var fast = VelocityGlyphModel(value: 40)
        _ = fast.beginDrag(atX: 0)
        var x = 0.0
        for _ in 0..<18 {
            x += 12 // 720 pt/s, above fullSpeed, and still on the track
            _ = fast.updateDrag(atX: x)
            fast.step(1.0 / 60)
        }
        #expect(fast.smoothedSpeed > VelocityGlyphTuning.fullSpeed)
        let saturated = abs(fast.pose(role)!.offsetY)
        // The target is clamped; the under-damped chase may ring a little past it.
        #expect(saturated <= abs(unit) * VelocityGlyphTuning.maxOffset * 1.25 + 0.05)
        #expect(fast.blurRadius <= VelocityGlyphTuning.maxBlur * 1.25 + 0.05)
    }

    @Test func releaseSpringsPastTheBaseline() {
        var model = VelocityGlyphModel(value: 40)
        let role = GlyphRole.digit(place: 0)
        let unit = VelocityGlyphMath.signedAmplitude(for: role)
        _ = model.beginDrag(atX: 20)
        for _ in 0..<36 {
            _ = model.updateDrag(atX: model.interactionX + 6)
            model.step(1.0 / 60)
        }
        let released = model.pose(role)!.offsetY
        let speed = 6.0 * 60
        let target = unit * VelocityGlyphTuning.maxOffset * min(1, speed / VelocityGlyphTuning.fullSpeed)
        #expect(abs(target) > 1)
        #expect(abs(released - target) < abs(target) * 0.4)
        model.endDrag()
        #expect(model.phase == .settling)
        #expect(model.smoothedSpeed == 0)
        var crossed = false
        for _ in 0..<120 {
            model.step(1.0 / 60)
            let later = model.pose(role)!.offsetY
            if released * later < 0, abs(later) > 0.05 * abs(released) { crossed = true }
        }
        #expect(crossed)
        #expect(model.phase == .idle)
        #expect(model.isVisuallySettled)
        #expect(abs(model.pose(role)!.offsetY) < 0.02)
        #expect(model.blurRadius < 0.02)
    }

    @Test func glyphSpringsKeepTheirIdentityWhenADigitAppears() {
        var model = VelocityGlyphModel(value: 40)
        _ = model.beginDrag(atX: 0)
        for _ in 0..<24 {
            _ = model.updateDrag(atX: model.interactionX + 8)
            model.step(1.0 / 60)
        }
        // Drop to a two-digit price. The ones and tens springs stay; the hundreds glyph leaves.
        #expect(model.setValue(80).isEmpty == false)
        #expect(model.pose(.digit(place: 2)) == nil)
        let ones = model.pose(.digit(place: 0))!
        let tens = model.pose(.digit(place: 1))!
        #expect(ones.offsetY != 0 && tens.offsetY != 0)
        let events = model.setValue(600)
        #expect(values(events) == PriceSpan(range: 40...600, step: 5).steps(from: 80, to: 600))
        #expect(model.pose(.digit(place: 0))!.offsetY == ones.offsetY)
        #expect(model.pose(.digit(place: 0))!.leanDegrees == ones.leanDegrees)
        #expect(model.pose(.digit(place: 1))!.offsetY == tens.offsetY)
        let hundreds = model.pose(.digit(place: 2))!
        #expect(hundreds.character == "6")
        #expect(hundreds.offsetY == 0 && hundreds.leanDegrees == 0)
        #expect(model.formattedPrice == "$600")
    }

    @Test func adjustStepsOnceAndStopsAtTheEnds() {
        var model = VelocityGlyphModel(value: 40)
        #expect(values(model.adjust(by: 1)) == [45])
        #expect(values(model.adjust(by: 3)) == [50, 55, 60])
        #expect(model.adjust(by: 0).isEmpty)
        var top = VelocityGlyphModel(value: 600)
        #expect(top.adjust(by: 1).isEmpty && top.value == 600)
        #expect(values(top.adjust(by: -1)) == [595])
        var bottom = VelocityGlyphModel(value: 40)
        #expect(bottom.adjust(by: -4).isEmpty && bottom.value == 40)
    }

    @Test func reduceMotionUpdatesThePriceWithoutScatterOrBlur() {
        var model = VelocityGlyphModel(value: 80, reduceMotion: true)
        _ = model.beginDrag(atX: 0)
        var ticks: [Int] = []
        for x in stride(from: 20.0, through: 200, by: 20) {
            ticks += values(model.updateDrag(atX: x))
            model.step(1.0 / 60)
            #expect(model.poses.allSatisfy { $0.offsetY == 0 && $0.leanDegrees == 0 })
            #expect(model.blurRadius == 0)
        }
        #expect(ticks.count > 1)
        #expect(Set(ticks).count == ticks.count)
        model.endDrag()
        #expect(model.phase == .idle)
        model.setReduceMotion(false)
        _ = model.beginDrag(atX: model.interactionX)
        _ = model.updateDrag(atX: model.interactionX + 30)
        model.frames(12)
        #expect(model.poses.contains { $0.offsetY != 0 })
        model.setReduceMotion(true)
        #expect(model.poses.allSatisfy { $0.offsetY == 0 && $0.leanDegrees == 0 })
        #expect(model.blurRadius == 0)
        #expect(model.phase == .dragging)
    }

    @Test func nonFiniteInputIsIgnoredAndALongFrameDoesNotExplode() {
        var model = VelocityGlyphModel(value: 180)
        #expect(model.beginDrag(atX: .nan).isEmpty)
        #expect(model.phase == .idle)
        _ = model.beginDrag(atX: 70)
        #expect(model.updateDrag(atX: .infinity).isEmpty)
        model.step(.nan)
        model.step(-1)
        let before = model.time
        model.step(2)
        #expect(abs(model.time - before - VelocityGlyphTuning.maxFrame) < 1e-12)
        #expect(model.poses.allSatisfy { $0.offsetY.isFinite && $0.leanDegrees.isFinite })
        #expect(model.smoothedSpeed.isFinite)
        model.endDrag()
        model.endDrag()
        #expect(model.phase == .idle || model.phase == .settling)
    }

    @Test func beginDragFromRestTicksTheJump() {
        var model = VelocityGlyphModel(value: 40)
        let events = model.beginDrag(atX: VelocityGlyphTuning.trackWidth)
        #expect(model.value == 600)
        #expect(values(events).count == 112)
        #expect(model.interactionX == VelocityGlyphTuning.trackWidth)
    }
}
