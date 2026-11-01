import Foundation

/// How long a channel change lasts and how strong it is.
public struct FlipSpec: Equatable, Sendable {
    public var duration: Double
    public var strength: Double
    public init(duration: Double, strength: Double) { self.duration = duration; self.strength = strength }
}

/// Time, in the discrete frames an old TV would show: the intensity envelope, frame quantization,
/// the swap moment and the per-frame seed. Everything is deterministic; the web port mirrors it.
public enum ChannelFlipTiming {
    /// The effect updates at this many frames per second, whatever the display rate, so it jitters instead of gliding.
    public static let fps = 15.0
    /// Envelope exponent: `sin(pi p) ^ shape`.
    public static let envelopeShape = 1.2
    /// Progress at which the picture is swapped: the peak of the envelope.
    public static let swapProgress = 0.5
    /// A tap: about a third of a second, medium strength.
    public static let tap = FlipSpec(duration: 0.35, strength: 0.6)
    /// Reduce Motion: a short crossfade with no jitter.
    public static let reducedDuration = 0.2

    /// Intensity 0…1 across a transition, peaking at `swapProgress` and zero at both ends.
    public static func envelope(_ progress: Double) -> Double {
        if !(progress > 0) || progress >= 1 { return 0 }
        return pow(sin(Double.pi * progress), envelopeShape)
    }

    /// How many frames a transition of `duration` seconds shows: at least 3, and always odd so the
    /// middle frame sits exactly at `swapProgress`.
    public static func frameCount(duration: Double) -> Int {
        let d = duration.isFinite ? max(0, duration) : 0
        var n = Int((d * fps).rounded())
        if n < 3 { n = 3 }
        if n % 2 == 0 { n += 1 }
        return n
    }

    /// The frame (0-based) showing at `elapsed` seconds, or nil once the transition is over.
    public static func frameIndex(elapsed: Double, duration: Double) -> Int? {
        guard duration > 0, elapsed.isFinite else { return nil }
        if elapsed >= duration { return nil }
        let n = frameCount(duration: duration)
        let f = Int((max(0, elapsed) / duration * Double(n)).rounded(.down))
        return min(n - 1, f)
    }

    /// Progress of a frame, strictly inside (0, 1): frame `i` of `n` sits at `(i + 1) / (n + 1)`.
    public static func quantizedProgress(frame: Int, count: Int) -> Double {
        Double(frame + 1) / Double(count + 1)
    }

    /// The frame on which the picture is swapped (the middle one).
    public static func swapFrame(count: Int) -> Int { count / 2 }

    /// Whether the swap has happened by `elapsed` (true for good once the transition is over).
    public static func hasSwapped(elapsed: Double, duration: Double) -> Bool {
        guard let f = frameIndex(elapsed: elapsed, duration: duration) else { return elapsed >= duration }
        return f >= swapFrame(count: frameCount(duration: duration))
    }

    /// Whether moving from `a` to `b` seconds crosses the swap moment.
    public static func crossesSwap(from a: Double, to b: Double, duration: Double) -> Bool {
        !hasSwapped(elapsed: a, duration: duration) && hasSwapped(elapsed: b, duration: duration)
    }

    /// Intensity of a frame, 0…1: the envelope at the frame's progress times the strength.
    public static func intensity(frame: Int, count: Int, strength: Double) -> Double {
        envelope(quantizedProgress(frame: frame, count: count)) * WhimsyMath.clamp01(strength)
    }

    /// A seed for one transition, from its running number. Below 2^14 so the frame seed stays exact in a Float.
    public static func transitionSeed(_ epoch: Int) -> UInt32 {
        ChannelHash.hash32(UInt32(truncatingIfNeeded: epoch) &+ 0x5EED) & 0x3FFF
    }

    /// The seed the shader gets on one frame (below 2^19, exact in a Float): new noise every frame.
    public static func frameSeed(transition: UInt32, frame: Int) -> Double {
        Double(transition &* 32 &+ UInt32(truncatingIfNeeded: frame & 31))
    }
}

/// lowbias32, the same in Swift (wrapping UInt32), Metal (uint) and JS (Math.imul).
public enum ChannelHash {
    public static func hash32(_ v: UInt32) -> UInt32 {
        var x = v
        x ^= x >> 16; x = x &* 0x7feb_352d
        x ^= x >> 15; x = x &* 0x846c_a68b
        x ^= x >> 16
        return x
    }
    public static func unit(_ x: UInt32) -> Double { Double(x & 0xFF_FFFF) / 16_777_216 }
}
