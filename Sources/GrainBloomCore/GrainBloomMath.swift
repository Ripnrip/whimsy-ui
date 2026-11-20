import Foundation

/// Pure dither, ripple, grain, and mesh functions. `sin` is the same Taylor
/// polynomial OnAir uses, so the JavaScript port matches at eight decimals.
public enum GrainBloomMath {
    public static let pi = Double.pi
    public static let twoPi = 2 * Double.pi
    public static let halfPi = Double.pi / 2
    static let invTwoPi = 1 / (2 * Double.pi)

    public static func sin(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        let k = (x * invTwoPi + 0.5).rounded(.down)
        var r = x - k * twoPi
        if r > halfPi { r = Double.pi - r } else if r < -halfPi { r = -Double.pi - r }
        let r2 = r * r
        var p = 1.0 / 355_687_428_096_000.0
        p = -1.0 / 1_307_674_368_000.0 + r2 * p
        p = 1.0 / 6_227_020_800.0 + r2 * p
        p = -1.0 / 39_916_800.0 + r2 * p
        p = 1.0 / 362_880.0 + r2 * p
        p = -1.0 / 5040.0 + r2 * p
        p = 1.0 / 120.0 + r2 * p
        p = -1.0 / 6.0 + r2 * p
        p = 1.0 + r2 * p
        return r * p
    }

    public static func cos(_ x: Double) -> Double { sin(x + halfPi) }

    public static func bayer4(row: Int, column: Int) -> Int {
        let size = 4
        let r = positiveMod(row, size)
        let c = positiveMod(column, size)
        return GrainBloomTuning.bayer4[r * size + c]
    }

    /// 8×8 Bayer built by tiling the 4×4. Values are 0...63, each once.
    public static func bayer8(row: Int, column: Int) -> Int {
        let n = 4
        let r = positiveMod(row, 8)
        let c = positiveMod(column, 8)
        let base = bayer4(row: r % n, column: c % n)
        let quadrant: Int
        if r < n && c < n { quadrant = 0 }
        else if r < n && c >= n { quadrant = 2 }
        else if r >= n && c < n { quadrant = 3 }
        else { quadrant = 1 }
        return 4 * base + quadrant
    }

    public static func sliceIndex(for progress: Double) -> Int {
        if progress >= 1 { return GrainBloomTuning.cellSizes.count - 1 }
        if progress <= 0 { return 0 }
        let steps = GrainBloomTuning.cellSizes.count
        var index = 0
        for step in 1..<steps {
            if progress + 1e-12 >= Double(step) / Double(steps) {
                index = step
            }
        }
        return index
    }

    public static func cellSize(for progress: Double) -> Double {
        GrainBloomTuning.cellSizes[sliceIndex(for: progress)]
    }

    public static func isRevealed(x: Double, y: Double, progress: Double) -> Bool {
        let p = min(max(progress, 0), 1)
        if p <= 0 { return false }
        let steps = GrainBloomTuning.cellSizes.count
        for index in 0..<steps {
            let sliceEnd = Double(index + 1) / Double(steps)
            let size = GrainBloomTuning.cellSizes[index]
            if p + 1e-12 >= sliceEnd {
                if passes(x: x, y: y, size: size, progress: sliceEnd) { return true }
            } else {
                return passes(x: x, y: y, size: size, progress: p)
            }
        }
        return true
    }

    public static func coverage(progress: Double) -> Double {
        let n = GrainBloomTuning.lattice
        var on = 0
        for row in 0..<n {
            for column in 0..<n {
                let x = (Double(column) + 0.5) / Double(n) * GrainBloomTuning.stageWidth
                let y = (Double(row) + 0.5) / Double(n) * GrainBloomTuning.stageHeight
                if isRevealed(x: x, y: y, progress: progress) { on += 1 }
            }
        }
        return Double(on) / Double(n * n)
    }

    public static func rippleDelay(x: Double, y: Double) -> Double {
        let dx = x - GrainBloomTuning.stageWidth / 2
        let dy = y - GrainBloomTuning.stageHeight / 2
        let dist = (dx * dx + dy * dy).squareRoot()
        let diagonal = (
            GrainBloomTuning.stageWidth * GrainBloomTuning.stageWidth
                + GrainBloomTuning.stageHeight * GrainBloomTuning.stageHeight
        ).squareRoot()
        if diagonal == 0 { return 0 }
        return dist / diagonal
    }

    public static func dotScale(wakeTime: Double, delay: Double, reduceMotion: Bool) -> Double {
        let t = reduceMotion ? 0.0 : wakeTime
        let local = t - delay * GrainBloomTuning.wakeDuration
        if local < 0 { return 0.35 }
        let pulse = 0.5 + 0.5 * sin(local * 6)
        return 0.6 + 0.4 * pulse
    }

    public static func dotBrightness(wakeTime: Double, delay: Double, reduceMotion: Bool) -> Double {
        0.2 + 0.8 * dotScale(wakeTime: wakeTime, delay: delay, reduceMotion: reduceMotion)
    }

    public static func blob(index: Int, time: Double, reduceMotion: Bool) -> (x: Double, y: Double) {
        let t = reduceMotion ? 0.0 : time
        let phase = Double(index) * 1.7
        let x = GrainBloomTuning.stageWidth * (
            0.5
                + 0.28 * sin(t * 0.35 + phase)
                + 0.08 * sin(t * 0.17 + phase * 2)
        )
        let y = GrainBloomTuning.stageHeight * (
            0.5
                + 0.22 * cos(t * 0.27 + phase)
                + 0.06 * sin(t * 0.13 + phase * 0.5)
        )
        return (x, y)
    }

    public static func grain(x: Int, y: Int, frame: Int, seed: UInt64) -> Double {
        let mixed = seed
            ^ (UInt64(frame) &* 0x9E37_79B9_7F4A_7C15)
            ^ (UInt64(bitPattern: Int64(x)) &* 0xBF58_476D_1CE4_E5B9)
            ^ (UInt64(bitPattern: Int64(y)) &* 0x94D0_49BB_1331_11EB)
        var rng = SeededRandom(seed: mixed)
        return rng.uniform(0...1)
    }

    public static func shimmer(phaseIsWaking: Bool, phaseTime: Double, reduceMotion: Bool) -> Double {
        guard phaseIsWaking, !reduceMotion else { return 0 }
        return min(1, max(0, phaseTime / GrainBloomTuning.wakeDuration))
    }

    public static func blur(progress: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0 }
        let p = min(max(progress, 0), 1)
        return GrainBloomTuning.maxBlur * (1 - p)
    }

    public static func glint(playsSettle: Bool, phaseTime: Double, reduceMotion: Bool) -> Double {
        guard playsSettle, !reduceMotion else { return 0 }
        let u = phaseTime / GrainBloomTuning.settleDuration
        if u <= 0 || u >= 1 { return 0 }
        return sin(u * pi)
    }

    public static func normalizedPalette(_ input: [GrainBloomRGB]) -> [GrainBloomRGB] {
        if input.isEmpty { return GrainBloomTuning.defaultPalette }
        let limit = min(4, input.count)
        var out: [GrainBloomRGB] = []
        for index in 0..<limit {
            let color = input[index]
            if color.r.isFinite, color.g.isFinite, color.b.isFinite {
                out.append(GrainBloomRGB(
                    r: min(1, max(0, color.r)),
                    g: min(1, max(0, color.g)),
                    b: min(1, max(0, color.b))
                ))
            } else {
                out.append(GrainBloomTuning.defaultPalette[index])
            }
        }
        return out
    }

    private static func passes(x: Double, y: Double, size: Double, progress: Double) -> Bool {
        let column = Int((x / size).rounded(.down))
        let row = Int((y / size).rounded(.down))
        let threshold = bayer8(row: row, column: column)
        return progress + 1e-12 >= (Double(threshold) + 0.5) / 64.0
    }

    private static func positiveMod(_ value: Int, _ modulus: Int) -> Int {
        let raw = value % modulus
        return raw >= 0 ? raw : raw + modulus
    }
}
