import Foundation
import Testing
@testable import SpinWatchCore

@Suite("Keyframes")
struct KeyframeTests {
    @Test func clampsOutsideAndHitsKeysExactly() {
        let k = KeyframeTrack([Keyframe(0.2, 10), Keyframe(0.6, 30, .linear), Keyframe(1, -10)])
        #expect(k.value(at: -5) == 10 && k.value(at: 0.2) == 10)
        #expect(k.value(at: 0.6) == 30 && k.value(at: 1) == -10 && k.value(at: 9) == -10)
        #expect(abs(k.value(at: 0.4) - 20) < 1e-12, "linear midpoint")
        #expect(abs(k.value(at: 0.8) - 10) < 1e-12, "easeInOut midpoint is the halfway value")
        #expect(k.value(at: .nan) == 10)
    }

    @Test func easingsShapeTheSegment() {
        for e in [KeyframeEasing.linear, .easeIn, .easeOut, .easeInOut] {
            #expect(e.apply(0) == 0 && e.apply(1) == 1)
            var last = -1.0
            for i in 0...20 { let v = e.apply(Double(i) / 20); #expect(v >= last); last = v }
        }
        #expect(KeyframeEasing.easeIn.apply(0.3) < 0.3 && KeyframeEasing.easeOut.apply(0.3) > 0.3)
        #expect(KeyframeEasing.hold.apply(0.99) == 0 && KeyframeEasing.hold.apply(1) == 1)
        #expect(KeyframeEasing.linear.apply(2) == 1 && KeyframeEasing.linear.apply(-1) == 0)
        let k = KeyframeTrack([Keyframe(0, 0), Keyframe(1, 5, .hold)])
        #expect(k.value(at: 0.999) == 0 && k.value(at: 1) == 5)
    }

    @Test func sortsInputAndHandlesStepsAndEmpties() {
        let k = KeyframeTrack([Keyframe(1, 100), Keyframe(0, 0, .linear), Keyframe(0.5, 50, .linear)])
        #expect(k.keyframes.map(\.at) == [0, 0.5, 1])
        #expect(abs(k.value(at: 0.25) - 25) < 1e-12)
        let step = KeyframeTrack([Keyframe(0, 0), Keyframe(0.5, 0), Keyframe(0.5, 9), Keyframe(1, 9)])
        #expect(step.value(at: 0.4999) == 0 && step.value(at: 0.5) == 9 && step.value(at: 0.7) == 9)
        #expect(KeyframeTrack([]).value(at: 0.3) == 0)
        #expect(KeyframeTrack([Keyframe(0.5, 7)]).value(at: 0.1) == 7)
        #expect(KeyframeTrack([Keyframe(.nan, 1), Keyframe(0, 2)]).keyframes.count == 1)
    }
}

@Suite("Scroll story")
struct StoryTests {
    let s = SpinStory()

    @Test func watchTurnsFrontSideBackFront() {
        #expect(s.yaw(at: 0) == 0 && s.yaw(at: 0.1) == 0)
        #expect(s.yaw(at: 0.3) == 90 && s.yaw(at: 0.35) == 90 && s.yaw(at: 0.4) == 90)
        #expect(s.yaw(at: 0.65) == 180 && s.yaw(at: 0.9) == 360 && s.yaw(at: 1) == 360)
        #expect(abs(s.yaw(at: 0.2) - 45) < 1e-9)
        var last = -1.0
        for i in 0...200 { let y = s.yaw(at: Double(i) / 200); #expect(y >= last - 1e-12); last = y }
    }

    @Test func eachSectionShowsDuringItsHold() {
        for (i, sec) in s.sections.enumerated() {
            let mid = (sec.start + sec.end) / 2
            #expect(s.opacity(ofSection: i, at: mid) == 1, "section \(i)")
            #expect(s.activeSection(at: mid) == i)
            for (j, _) in s.sections.enumerated() where j != i { #expect(s.opacity(ofSection: j, at: mid) == 0) }
        }
        #expect(s.opacity(ofSection: 0, at: 0) == 1, "visible on arrival")
        #expect(s.opacity(ofSection: 3, at: 1) == 1, "the last never leaves")
        #expect(s.opacity(ofSection: 1, at: 0.27) > 0 && s.opacity(ofSection: 1, at: 0.27) < 1)
        #expect(s.opacity(ofSection: 9, at: 0.5) == 0 && s.opacity(ofSection: 1, at: .nan) == 0)
    }

    @Test func blocksRiseInAndLeaveUpwards() {
        #expect(s.offset(ofSection: 1, at: 0.27) > 0, "below while arriving")
        #expect(s.offset(ofSection: 1, at: 0.43) < 0, "above while leaving")
        #expect(s.offset(ofSection: 1, at: 0.35) == 0)
        #expect(abs(s.offset(ofSection: 2, at: 0.2) - 28) < 1e-12)
        #expect(s.sections[0].title == "EVERY SECOND, REIMAGINED" && s.sections[3].body == "Machined, not molded.")
    }

    @Test func statsCountUpAtTheEnd() {
        #expect(s.stats.map(\.value) == [47, 100, 36])
        #expect(s.statValue(0, at: 0.5) == 0)
        #expect(s.statValue(0, at: 1) == 47 && s.statValue(1, at: 0.96) == 100)
        let mid = s.statValue(1, at: 0.86)
        #expect(mid > 0 && mid < 100)
        var last = 0
        for i in 0...100 { let v = s.statValue(2, at: 0.8 + Double(i) * 0.002); #expect(v >= last); last = v }
        #expect(s.statValue(7, at: 1) == 0)
    }
}

@Suite("Watch projection")
struct ProjectionTests {
    @Test func layersSquashAndSlideWithYaw() {
        let p0 = WatchProjection.place(z: 7, yawDegrees: 0)
        #expect(p0.offsetX == 0 && p0.scaleX == 1 && p0.depth == 7)
        let p90 = WatchProjection.place(z: 7, yawDegrees: 90)
        #expect(abs(p90.offsetX + 7) < 1e-9 && abs(p90.scaleX) < 1e-9 && abs(p90.depth) < 1e-9)
        let p180 = WatchProjection.place(z: 7, yawDegrees: 180)
        #expect(abs(p180.scaleX + 1) < 1e-9 && abs(p180.depth + 7) < 1e-9, "mirrored and at the back")
        // The crown side (+x) comes towards you at +90°.
        let crown = WatchProjection.place(x: 90, z: 0, yawDegrees: 90)
        #expect(abs(crown.depth - 90) < 1e-9 && abs(crown.offsetX) < 1e-9)
        let r = WatchProjection.rotate(x: 3, z: 4, yawDegrees: 37)
        #expect(abs(r.x * r.x + r.z * r.z - 25) < 1e-9)
    }

    @Test func paintsFarToNear() {
        let zs = [-7.0, 0, 7]
        #expect(WatchProjection.paintOrder(zs.map { WatchProjection.place(z: $0, yawDegrees: 0).depth }) == [0, 1, 2])
        #expect(WatchProjection.paintOrder(zs.map { WatchProjection.place(z: $0, yawDegrees: 180).depth }) == [2, 1, 0])
        #expect(WatchProjection.paintOrder([1, 1, 0]) == [2, 0, 1], "stable for ties")
        #expect(WatchProjection.frontVisible(yawDegrees: 30) && !WatchProjection.frontVisible(yawDegrees: 120))
        #expect(WatchProjection.frontVisible(yawDegrees: 360))
    }

    @Test func shadingFollowsTheLight() {
        let front = WatchProjection.brightness(normalAngle: 0, yawDegrees: 0)
        #expect(front > 0.9 && front <= 1)
        // Positive yaw turns the dial to the left, towards the light: fully lit at atan(0.45/0.9).
        let lit = WatchProjection.brightness(normalAngle: 0, yawDegrees: 26.565)
        #expect(abs(lit - 1) < 1e-3)
        #expect(WatchProjection.brightness(normalAngle: 0, yawDegrees: 180) == 0.35)
        for y in stride(from: 0.0, through: 360, by: 15) {
            let b = WatchProjection.bandBrightness(yawDegrees: y)
            #expect(b >= 0.35 && b <= 1)
        }
        // Square-on, either side catches the same light; half-turned, the side angled towards the light is brighter.
        #expect(abs(WatchProjection.bandBrightness(yawDegrees: 270) - WatchProjection.bandBrightness(yawDegrees: 90)) < 1e-12)
        #expect(WatchProjection.bandBrightness(yawDegrees: 60) < WatchProjection.bandBrightness(yawDegrees: 120))
    }
}
