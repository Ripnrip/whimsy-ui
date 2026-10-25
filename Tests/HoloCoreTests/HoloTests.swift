import Testing
import Foundation
@testable import HoloCore

private let card = Vec2(300, 420)
private func near(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

/// Steps a model at 60 Hz for `seconds`, collecting events.
private func run(_ m: inout HoloModel, _ seconds: Double) -> [HoloEvent] {
    var out: [HoloEvent] = []
    for _ in 0..<Int((seconds * 60).rounded()) { out += m.step(1.0 / 60) }
    return out
}

@Suite struct TiltMappingTests {
    @Test func softClampIsLinearNearZeroAndNeverPassesTheLimit() {
        #expect(near(HoloTilt.softClamp(0), 0))
        #expect(near(HoloTilt.softClamp(0.5), 0.5, 1e-3))
        #expect(near(HoloTilt.softClamp(-3), -HoloTilt.softClamp(3)))
        var last = -Double.infinity
        for v in stride(from: -400.0, through: 400.0, by: 2.5) {
            let c = HoloTilt.softClamp(v)
            #expect(abs(c) <= HoloTilt.maxAngle)
            #expect(c >= last)
            last = c
        }
        #expect(HoloTilt.softClamp(1e6) <= 15 && HoloTilt.softClamp(1e6) > 14.999)
        #expect(HoloTilt.softClamp(.infinity) == 15)
        #expect(HoloTilt.softClamp(.nan) == 0)
    }

    @Test func dragDirectionsMapToYawAndPitch() {
        let right = HoloTilt.tilt(forDrag: Vec2(40, 0))
        #expect(right.x > 0 && near(right.y, 0))
        #expect(near(right.x, HoloTilt.softClamp(40 * 0.12)))
        let up = HoloTilt.tilt(forDrag: Vec2(0, -40))
        #expect(up.y > 0 && near(up.x, 0))
        let far = HoloTilt.tilt(forDrag: Vec2(-5000, 5000))
        #expect(far.x < -14.9 && far.x >= -15 && far.y < -14.9 && far.y >= -15)
        let n = HoloTilt.normalized(Vec2(30, -7.5))
        #expect(n == Vec2(1, -0.5))
    }
}

@Suite struct SpringTests {
    @Test func dragTracksTheFingerAndReleaseSpringsBackWithAWobble() {
        var m = HoloModel()
        #expect(m.isIdle)
        m.dragChanged(translation: Vec2(200, -60))
        _ = run(&m, 0.6)
        #expect(m.isDragging && !m.isIdle)
        #expect((m.tilt - m.target).length < 0.05)
        #expect(m.tilt.x <= 15 && m.tilt.y <= 15)
        m.dragEnded()
        var minYaw = Double.infinity
        for _ in 0..<60 { m.step(1.0 / 60); minYaw = min(minYaw, m.tilt.x) }
        #expect(minYaw < -0.5)            // underdamped: overshoots past flat
        #expect(minYaw > -HoloTilt.maxAngle)
        _ = run(&m, 2)
        #expect(m.isIdle)
        #expect(m.tilt == .zero)
    }

    @Test func reduceMotionReturnsWithoutOvershoot() {
        var c = HoloModel.Config(); c.reduceMotion = true
        var m = HoloModel(config: c)
        m.dragChanged(translation: Vec2(200, 0))
        _ = run(&m, 0.8)
        m.dragEnded()
        var minYaw = Double.infinity
        for _ in 0..<120 { m.step(1.0 / 60); minYaw = min(minYaw, m.tilt.x) }
        #expect(minYaw >= -1e-6)
        #expect(m.isIdle)
    }

    @Test func heldYawForAccessibilityStaysPut() {
        var m = HoloModel()
        m.setHeldYaw(40)
        _ = run(&m, 1.5)
        #expect(near(m.tilt.x, HoloTilt.softClamp(40), 0.02))
        #expect(m.isIdle)        // settled and not dragging, so the view can pause
        #expect(m.displayTilt.x <= 15)
    }
}

@Suite struct BandTests {
    @Test func bandPositionFollowsTilt() {
        #expect(HoloShading.bandPosition(tilt: .zero) == 0)
        #expect(near(HoloShading.bandPosition(tilt: Vec2(1, -1)), 0.7))
        #expect(near(HoloShading.bandPosition(tilt: Vec2(-1, 1)), -0.7))
        #expect(HoloShading.bandPosition(tilt: Vec2(0.5, 0)) > HoloShading.bandPosition(tilt: Vec2(0.2, 0)))
        // At full yaw the band reaches past the card's far corner (corner axis coordinate ≈ 0.69).
        let corner = HoloShading.axisCoordinate(Vec2(1, 1))
        #expect(near(corner, (0.5 + 0.3) / Vec2(1, 0.6).length))
        #expect(HoloShading.bandPosition(tilt: Vec2(1, -1)) > corner)
    }

    @Test func bandIsBrightestWhereItSits() {
        let n = Vec2(0.5, 0)
        let b = HoloShading.bandPosition(tilt: n)
        // A pixel on the band axis through the centre, at the band position.
        let a = HoloShading.bandAxis
        let onUV = Vec2(0.5, 0.5) + a * b
        let offUV = Vec2(0.5, 0.5) - a * 0.4
        #expect(HoloShading.bandIntensity(offset: 0) == 1)
        #expect(HoloShading.bandIntensity(offset: 1) < 0.37)
        func lum(_ uv: Vec2) -> Double {
            let l = HoloShading.foilLight(at: Vec2(uv.x * card.x, uv.y * card.y) + Vec2(0.37, 0.21), size: card, tilt: n)
            return l.r + l.g + l.b
        }
        // Ignore sparkles by sampling a few nearby points and taking the minimum.
        func floorLum(_ uv: Vec2) -> Double { [-0.004, 0, 0.004].map { lum(uv + Vec2($0, -$0)) }.min()! }
        #expect(floorLum(onUV) > floorLum(offUV) + 0.4)
    }

    @Test func rainbowPaletteIsPeriodicAndBounded() {
        for h in stride(from: -1.0, through: 2.0, by: 0.05) {
            let c = HoloShading.rainbow(h), d = HoloShading.rainbow(h + 1)
            #expect(near(c.r, d.r, 1e-12) && near(c.g, d.g, 1e-12) && near(c.b, d.b, 1e-12))
            for v in [c.r, c.g, c.b] { #expect(v >= 0 && v <= 1) }
        }
        let red = HoloShading.rainbow(0)
        #expect(red.r == 1 && red.r > red.g && red.r > red.b)
    }
}

@Suite struct SparkleTests {
    @Test func hashMatchesLowbias32() {
        #expect(HoloShading.hash32(0) == 0)
        #expect(HoloShading.hash32(1) == 0x6889_90C0)   // same value as the JS port (Math.imul)
        #expect(HoloShading.hash32(0x9E37) == 0xD889_4C5C)
        #expect(HoloShading.hash32(12345) == HoloShading.hash32(12345))
        #expect(HoloShading.unit(0xFFFF_FFFF) < 1)
    }

    @Test func sparkleFieldIsDeterministicWithAboutHalfTheCellsLit() {
        var lit = 0, total = 0
        for y in 0..<30 { for x in 0..<22 {
            total += 1
            guard let s = HoloShading.sparkle(cellX: x, cellY: y) else { continue }
            lit += 1
            #expect(s == HoloShading.sparkle(cellX: x, cellY: y))
            #expect(s.window.x >= -1 && s.window.x < 1 && s.window.y >= -1 && s.window.y < 1)
            #expect(s.radius >= 3 && s.radius < 6)
            let cx = Double(x) * 14, cy = Double(y) * 14
            #expect(s.point.x >= cx + 2.8 - 1e-9 && s.point.x <= cx + 11.2 + 1e-9)
            #expect(s.point.y >= cy + 2.8 - 1e-9 && s.point.y <= cy + 11.2 + 1e-9)
        } }
        let f = Double(lit) / Double(total)
        #expect(f > 0.4 && f < 0.6)
        #expect(HoloShading.sparkle(cellX: -1, cellY: 0) == nil)
    }

    @Test func sparklesOnlyLightInsideTheirAngleWindow() {
        let w = Vec2(0.3, -0.2)
        #expect(HoloShading.sparkleGate(window: w, tilt: w) == 1)
        #expect(HoloShading.sparkleGate(window: w, tilt: w + Vec2(0.1, 0)) == 1)   // flat top inside 0.4 × window
        let mid = HoloShading.sparkleGate(window: w, tilt: w + Vec2(0.25, 0))
        #expect(mid > 0 && mid < 1)
        #expect(HoloShading.sparkleGate(window: w, tilt: w + Vec2(0.36, 0)) == 0)

        // Find a sparkle and check it shines at its own window but not at the opposite tilt.
        var found: HoloShading.Sparkle?
        outer: for y in 1..<29 { for x in 1..<20 {
            if let s = HoloShading.sparkle(cellX: x, cellY: y), s.window.length > 0.6 { found = s; break outer }
        } }
        let s = try! #require(found)
        let on = HoloShading.sparkleLight(at: s.point, tilt: s.window)
        let off = HoloShading.sparkleLight(at: s.point, tilt: s.window * -1)
        #expect(on >= 1)
        #expect(off < on - 0.9)
    }

    @Test func glintHasABrightCoreAndArms() {
        #expect(near(HoloShading.glint(offset: .zero, radius: 5), 1 + 0.6 * 2))
        #expect(HoloShading.glint(offset: Vec2(3, 0), radius: 5) > HoloShading.glint(offset: Vec2(2.2, 2.2), radius: 5))
        #expect(HoloShading.glint(offset: Vec2(8, 8), radius: 5) < 1e-3)
    }
}

@Suite struct CrossingTests {
    @Test func detectorUsesHysteresisAndDebounce() {
        var d = CenterCrossingDetector()
        #expect(d.update(band: 0.3, dt: 0) == nil)          // first sighting just sets the side
        #expect(d.side == 1)
        #expect(d.update(band: 0.01, dt: 0.5) == nil)       // inside the dead zone
        #expect(d.update(band: -0.03, dt: 0.5) == nil)
        #expect(d.update(band: -0.05, dt: 0.5) == -1)       // clearly crossed
        #expect(d.update(band: 0.05, dt: 0.05) == nil)      // too soon: dropped, but the side updates
        #expect(d.side == 1)
        #expect(d.update(band: -0.2, dt: 0.2) == -1)
        #expect(d.update(band: -0.3, dt: 0.2) == nil)
    }

    @Test func modelEmitsCrossingsAsTheBandSweeps() {
        var m = HoloModel()
        m.dragChanged(translation: Vec2(150, 0))
        // Leaving the resting centre isn't a crossing; it only picks a side.
        let right = run(&m, 0.5)
        #expect(right.isEmpty)
        m.dragChanged(translation: Vec2(-150, 0))
        let left = run(&m, 0.5)
        #expect(left == [.bandCrossedCenter(-1)])
        m.dragChanged(translation: Vec2(150, 0))
        let back = run(&m, 0.5)
        #expect(back == [.bandCrossedCenter(1)])
        #expect(m.crossings == 2)
        m.dragChanged(translation: Vec2(150, 2))
        #expect(run(&m, 0.3).isEmpty)
        // Releasing from full right: the wobble swings the band just past centre once.
        m.dragEnded()
        let release = run(&m, 2)
        #expect(release == [.bandCrossedCenter(-1)])
        #expect(m.isIdle)
    }
}

@Suite struct ShadingTests {
    @Test func shadeIsPremultipliedAndCapped() {
        let base = HoloRGB(0.2, 0.1, 0.3)
        #expect(HoloShading.shade(base, alpha: 0, at: Vec2(150, 210), size: card, tilt: .zero) == base)
        #expect(HoloShading.shade(base, alpha: 1, at: Vec2(150, 210), size: card, tilt: .zero, strength: 0) == base)
        let half = HoloShading.shade(HoloRGB(0.45, 0.45, 0.45), alpha: 0.5, at: Vec2(150, 210), size: card, tilt: .zero)
        for v in [half.r, half.g, half.b] { #expect(v <= 0.5 && v >= 0.45) }
        let lit = HoloShading.shade(base, alpha: 1, at: Vec2(150, 210), size: card, tilt: .zero)
        #expect(lit.r > base.r && lit.g > base.g && lit.b > base.b)
        // Out-of-range tilt is clamped like the shader's clamp(tilt, -1, 1).
        #expect(HoloShading.foilLight(at: Vec2(40, 50), size: card, tilt: Vec2(3, -2))
                == HoloShading.foilLight(at: Vec2(40, 50), size: card, tilt: Vec2(1, -1)))
    }

    @Test func metalShaderConstantsMatchTheCore() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/HoloFoilCard/Resources/HoloFoil.metal")
        let src = try String(contentsOf: url, encoding: .utf8)
        var consts: [String: Double] = [:]
        for line in src.split(separator: "\n") where line.hasPrefix("constant float ") {
            let parts = line.dropFirst("constant float ".count).split(separator: "=")
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            consts[name] = Double(parts[1].trimmingCharacters(in: CharacterSet(charactersIn: " ;")))
        }
        let expected: [String: Double] = [
            "kSweep": HoloShading.sweep, "kYawWeight": HoloShading.yawWeight, "kPitchWeight": HoloShading.pitchWeight,
            "kBandWidth": HoloShading.bandWidth, "kBandStrength": HoloShading.bandStrength, "kHueSpread": HoloShading.hueSpread,
            "kFoilStrength": HoloShading.foilStrength, "kGlareStrength": HoloShading.glareStrength, "kGlareSize": HoloShading.glareSize,
            "kSparkleCell": HoloShading.sparkleCell, "kSparkleDensity": HoloShading.sparkleDensity,
            "kSparkleWindow": HoloShading.sparkleWindow, "kSparkleStrength": HoloShading.sparkleStrength,
        ]
        #expect(consts == expected)
        #expect(src.contains("[[ stitchable ]] half4 holoFoil(float2 position, half4 color, float2 size, float2 tilt, float strength)"))
        #expect(src.contains("0x7feb352du") && src.contains("0x846ca68bu") && src.contains("0x9E37u"))
    }
}
