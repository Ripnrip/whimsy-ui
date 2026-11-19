import Foundation

public enum GrainBloomPhase: String, Equatable, Sendable {
    case idle
    case waking
    case resolving
    case done
}

/// Phase timeline for the image-generation placeholder. The view owns the
/// picture; this model only stores whether one is present.
public struct GrainBloomModel: Equatable, Sendable {
    public private(set) var phase: GrainBloomPhase
    public private(set) var phaseTime: Double
    public private(set) var hasImage: Bool
    public private(set) var epoch: Int
    public private(set) var isGenerating: Bool
    public private(set) var reduceMotion: Bool
    public private(set) var resolveProgress: Double
    public private(set) var crossfade: Double
    public private(set) var playsSettle: Bool
    public private(set) var palette: [GrainBloomRGB]
    public private(set) var seed: UInt64
    public private(set) var elapsed: Double
    public private(set) var frozenCellSize: Double

    public init(
        generating: Bool = false,
        hasImage: Bool = false,
        reduceMotion: Bool = false,
        palette: [GrainBloomRGB] = [],
        seed: UInt64 = GrainBloomTuning.defaultSeed
    ) {
        self.phase = .idle
        self.phaseTime = 0
        self.hasImage = false
        self.epoch = 0
        self.isGenerating = false
        self.reduceMotion = reduceMotion
        self.resolveProgress = 0
        self.crossfade = 0
        self.playsSettle = false
        self.palette = GrainBloomMath.normalizedPalette(palette)
        self.seed = seed
        self.elapsed = 0
        self.frozenCellSize = GrainBloomTuning.cellSizes[0]
        isGenerating = generating
        if hasImage {
            self.hasImage = true
            epoch = 1
            if generating {
                enterResolving(resetProgress: true)
            } else {
                phase = .done
                phaseTime = 0
                playsSettle = false
                resolveProgress = 1
                crossfade = 1
            }
        } else if generating {
            enterWaking()
        }
    }

    public mutating func setGenerating(_ on: Bool) {
        guard on != isGenerating else { return }
        isGenerating = on
        if on {
            if !hasImage, phase == .idle {
                enterWaking()
            }
        } else if phase == .waking, !hasImage {
            enterIdle()
        }
    }

    public mutating func setImagePresent(_ present: Bool) {
        guard present != hasImage else { return }
        epoch += 1
        hasImage = present
        if present {
            enterResolving(resetProgress: true)
        } else if isGenerating {
            enterWaking()
        } else {
            enterIdle()
        }
    }

    public mutating func setPalette(_ colors: [GrainBloomRGB]) {
        palette = GrainBloomMath.normalizedPalette(colors)
    }

    public mutating func setReduceMotion(_ on: Bool) {
        if on, !reduceMotion {
            frozenCellSize = GrainBloomMath.cellSize(for: resolveProgress)
            crossfade = max(crossfade, GrainBloomMath.coverage(progress: resolveProgress))
        }
        reduceMotion = on
    }

    @discardableResult
    public mutating func replay() -> Bool {
        guard phase == .done, hasImage else { return false }
        seed &+= 1
        epoch += 1
        enterWaking()
        return true
    }

    public mutating func step(_ dt: Double) {
        let delta = max(0, dt)
        elapsed += delta
        phaseTime += delta
        if reduceMotion {
            guard hasImage else { return }
            let duration = GrainBloomTuning.reduceDuration
            if duration <= 0 {
                crossfade = 1
            } else {
                crossfade = min(1, crossfade + delta / duration)
            }
            resolveProgress = max(resolveProgress, crossfade)
            if crossfade >= 1, phase != .done {
                phase = .done
                phaseTime = 0
                playsSettle = false
            }
            return
        }
        switch phase {
        case .waking:
            if hasImage, phaseTime >= GrainBloomTuning.wakeDuration {
                enterResolving(resetProgress: true)
            }
        case .resolving:
            resolveProgress = min(1, phaseTime / GrainBloomTuning.resolveDuration)
            if resolveProgress >= 1 {
                phase = .done
                phaseTime = 0
                playsSettle = true
                crossfade = 1
            }
        case .idle, .done:
            break
        }
    }

    public var cellSize: Double {
        if reduceMotion { return frozenCellSize }
        return GrainBloomMath.cellSize(for: resolveProgress)
    }

    public var revealCoverage: Double {
        if reduceMotion { return crossfade }
        return GrainBloomMath.coverage(progress: resolveProgress)
    }

    public var blur: Double {
        GrainBloomMath.blur(progress: resolveProgress, reduceMotion: reduceMotion)
    }

    public var shimmer: Double {
        GrainBloomMath.shimmer(
            phaseIsWaking: phase == .waking,
            phaseTime: phaseTime,
            reduceMotion: reduceMotion
        )
    }

    public var glint: Double {
        GrainBloomMath.glint(
            playsSettle: playsSettle && phase == .done,
            phaseTime: phaseTime,
            reduceMotion: reduceMotion
        )
    }

    public var accessibilityValue: String {
        phase == .done ? GrainBloomTuning.readyValue : GrainBloomTuning.generatingValue
    }

    public func blob(_ index: Int) -> (x: Double, y: Double) {
        GrainBloomMath.blob(index: index, time: elapsed, reduceMotion: reduceMotion)
    }

    private mutating func enterIdle() {
        phase = .idle
        phaseTime = 0
        playsSettle = false
        resolveProgress = 0
        crossfade = 0
    }

    private mutating func enterWaking() {
        phase = .waking
        phaseTime = 0
        playsSettle = false
        if !reduceMotion {
            resolveProgress = 0
            crossfade = 0
        }
    }

    private mutating func enterResolving(resetProgress: Bool) {
        phase = .resolving
        phaseTime = 0
        playsSettle = false
        if resetProgress, !reduceMotion {
            resolveProgress = 0
            crossfade = 0
        }
        if reduceMotion {
            frozenCellSize = GrainBloomTuning.cellSizes[0]
        }
    }
}
