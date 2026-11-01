import Testing
import Foundation
@testable import ColorFigureCore

@Suite struct FigureProjectionTests {
    @Test func cameraBasisIsOrthonormalAndRightHanded() {
        for yaw in stride(from: -180.0, through: 360, by: 37) {
            let c = FigureCamera(yaw: yaw)
            #expect(abs(c.right.length - 1) < 1e-9)
            #expect(abs(c.up.length - 1) < 1e-9)
            #expect(abs(c.toViewer.length - 1) < 1e-9)
            #expect(abs(c.right.dot(c.up)) < 1e-9)
            #expect(abs(c.right.dot(c.toViewer)) < 1e-9)
            let x = c.right.cross(c.up)
            #expect((x - c.toViewer).length < 1e-9)
        }
    }

    @Test func isometricPitchIsTheClassicAngle() {
        #expect(abs(FigureCamera.isoPitch - 35.2644) < 1e-3)
    }

    @Test func frontViewMapsAxesToScreen() {
        let c = FigureCamera(yaw: 0, pitch: 0)
        let a = c.project(Vec3(0, 1, 0))
        let b = c.project(Vec3(0, 0, 1))
        #expect(abs(a.x - 1) < 1e-9 && abs(a.y) < 1e-9)      // +y is screen right
        #expect(abs(b.x) < 1e-9 && abs(b.y + 1) < 1e-9)      // +z is screen up (y down)
    }

    @Test func heightMovesScreenYByCosPitch() {
        let c = FigureCamera(yaw: 20)
        let d = c.project(Vec3(3, 4, 10)).y - c.project(Vec3(3, 4, 0)).y
        #expect(abs(d + 10 * cos(FigureCamera.isoPitch * Double.pi / 180)) < 1e-9)
    }

    @Test func fullTurnOfYawProjectsTheSame() {
        let p = Vec3(12, -7, 30)
        let a = FigureCamera(yaw: 33).project(p)
        let b = FigureCamera(yaw: 33 + 360).project(p)
        #expect((a - b).length < 1e-9)
    }

    @Test func projectionIsOrthographic() {
        let c = FigureCamera(yaw: 51)
        let d = Vec3(2, 3, 4)
        let a = c.project(Vec3(1, 1, 1)), b = c.project(Vec3(1, 1, 1) + d), far = c.project(Vec3(101, 1, 1) + d)
        // Moving along the view direction changes nothing on screen.
        let k = c.project(Vec3(5, 5, 5) + c.toViewer * 80)
        #expect((k - c.project(Vec3(5, 5, 5))).length < 1e-9)
        #expect(((b - a) - (far - c.project(Vec3(101, 1, 1)))).length < 1e-9)
    }

    @Test func nearerPointsHaveMoreDepth() {
        let c = FigureCamera(yaw: 0)
        #expect(c.depth(Vec3(20, 0, 0)) > c.depth(Vec3(-20, 0, 0)))
        let back = FigureCamera(yaw: 180)
        #expect(back.depth(Vec3(20, 0, 0)) < back.depth(Vec3(-20, 0, 0)))
    }

    @Test func faceVisibilityFollowsTheViewer() {
        let c = FigureCamera(yaw: 0)
        #expect(c.faces(Vec3(1, 0, 0)))
        #expect(!c.faces(Vec3(-1, 0, 0)))
        #expect(c.faces(Vec3(0, 0, 1)))     // the top is seen from above
        #expect(!c.faces(Vec3(0, 0, -1)))
    }

    @Test func rotateZTurnsAboutThePivot() {
        let r = FigureCamera.rotateZ(Vec3(2, 0, 5), about: Vec3(1, 0, 0), by: Double.pi / 2)
        #expect((r - Vec3(1, 1, 5)).length < 1e-9)
    }

    @Test func everyYawKeepsTheMachineInsideTheViewExtent() {
        for yaw in stride(from: 0.0, to: 360, by: 15) {
            let b = LabelLayout.figureBounds(FigureCamera(yaw: yaw))
            #expect(b.minX > -40 && b.maxX < 40)
            #expect(b.minY > -92 && b.maxY < 24)
        }
    }
}

@Suite struct FigureBasicsTests {
    @Test func noiseIsDeterministicAndBounded() {
        for i in 0..<200 {
            let a = FigureNoise.signed(7, UInt32(i), 1)
            #expect(a == FigureNoise.signed(7, UInt32(i), 1))
            #expect(a >= -1 && a < 1)
            let u = FigureNoise.unit(7, UInt32(i))
            #expect(u >= 0 && u < 1)
        }
    }

    @Test func noiseVariesWithEveryInput() {
        let a = FigureNoise.signed(7, 1, 1)
        #expect(a != FigureNoise.signed(8, 1, 1))
        #expect(a != FigureNoise.signed(7, 2, 1))
        #expect(a != FigureNoise.signed(7, 1, 2))
    }

    @Test func noiseIsRoughlyCentred() {
        let mean = (0..<2000).map { FigureNoise.signed(3, UInt32($0), 0) }.reduce(0, +) / 2000
        #expect(abs(mean) < 0.08)
    }

    @Test func colourHexAndMix() {
        let c = FigureColor(hex: 0xFF8000)
        #expect(abs(c.r - 1) < 1e-9 && abs(c.g - 128.0 / 255) < 1e-9 && c.b == 0)
        let m = FigureColor.mix(FigureColor(0, 0, 0), FigureColor(1, 1, 1), 0.25)
        #expect(abs(m.r - 0.25) < 1e-9)
    }

    @Test func easingEndpoints() {
        #expect(FigureEase.smoothstep(0, 1, -1) == 0 && FigureEase.smoothstep(0, 1, 2) == 1)
        #expect(abs(FigureEase.smoothstep(0, 1, 0.5) - 0.5) < 1e-12)
        #expect(FigureEase.easeOutCubic(0) == 0 && FigureEase.easeOutCubic(1) == 1)
        #expect(FigureEase.easeInOutCubic(0.5) == 0.5)
    }
}
