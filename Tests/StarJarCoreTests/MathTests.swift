import Testing
import Foundation
@testable import StarJarCore

@Suite("StarJarMath") struct MathTests {
    @Test(arguments: [-1000.0, -50.5, -7, -3.14159, -1, -0.25, 0, 0.1, 0.5, 1, 1.5707963, 2, 3, 3.14159265, 4.7, 6.28, 10, 33.3, 123.456, 999.9])
    func sinMatchesFoundation(_ x: Double) {
        #expect(abs(StarJarMath.sin(x) - Foundation.sin(x)) < 1e-12)
    }
    @Test(arguments: [-20.0, -3, -1, 0, 0.7, 1.5707963, 2, 3.14159265, 5, 40])
    func cosMatchesFoundation(_ x: Double) {
        #expect(abs(StarJarMath.cos(x) - Foundation.cos(x)) < 1e-12)
    }
    @Test(arguments: [-59.0, -30, -10, -3, -1, -0.5, -1e-9, 0, 0.3, 1, 2.5, 7, 20, 45, 59])
    func expMatchesFoundationRelatively(_ x: Double) {
        #expect(abs(StarJarMath.exp(x) / Foundation.exp(x) - 1) < 1e-12)
    }
    @Test func nonFiniteInputsAreSafe() {
        #expect(StarJarMath.sin(.nan) == 0)
        #expect(StarJarMath.sin(.infinity) == 0)
        #expect(StarJarMath.exp(.nan) == 0)
        #expect(StarJarMath.exp(1000).isFinite)
        #expect(StarJarMath.exp(-1000) >= 0)
    }
    @Test func sinIsOddAndBounded() {
        for k in 0..<500 {
            let x = Double(k) * 0.37 - 90
            #expect(abs(StarJarMath.sin(x) + StarJarMath.sin(-x)) < 1e-12)
            #expect(abs(StarJarMath.sin(x)) <= 1 + 1e-12)
        }
    }
    @Test func hashIsDeterministicAndSpreads() {
        #expect(StarJarMath.hash32(0) == StarJarMath.hash32(0))
        #expect(StarJarMath.value(1, 2) != StarJarMath.value(1, 3))
        #expect(StarJarMath.value(1, 2) != StarJarMath.value(2, 2))
        var buckets = [Int](repeating: 0, count: 10)
        for i in 0..<5000 { buckets[min(9, Int(StarJarMath.unit(0x57A2, i) * 10))] += 1 }
        #expect(buckets.allSatisfy { $0 > 400 && $0 < 600 })
    }
    @Test(arguments: 0..<64)
    func unitIsInHalfOpenRange(_ salt: Int) {
        let u = StarJarMath.unit(UInt32(salt * 7919), salt)
        #expect(u >= 0 && u < 1)
    }
    @Test func easingEndpointsAndMonotone() {
        #expect(StarJarMath.easeOutCubic(0) == 0 && StarJarMath.easeOutCubic(1) == 1)
        #expect(StarJarMath.easeInOutCubic(0) == 0 && StarJarMath.easeInOutCubic(1) == 1)
        #expect(abs(StarJarMath.easeInOutCubic(0.5) - 0.5) < 1e-12)
        #expect(StarJarMath.easeOutCubic(-1) == 0 && StarJarMath.easeOutCubic(3) == 1)
        var a = 0.0, b = 0.0
        for k in 1...100 {
            let t = Double(k) / 100
            #expect(StarJarMath.easeOutCubic(t) >= a); a = StarJarMath.easeOutCubic(t)
            #expect(StarJarMath.easeInOutCubic(t) >= b); b = StarJarMath.easeInOutCubic(t)
        }
    }
    @Test func lerpAndClamp() {
        #expect(StarJarMath.lerp(2, 4, 0.5) == 3)
        #expect(StarJarMath.clamp01(-2) == 0 && StarJarMath.clamp01(2) == 1 && StarJarMath.clamp01(0.4) == 0.4)
    }
}
