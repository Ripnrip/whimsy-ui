import Foundation

/// One drop at this instant. `center` is the simulated point. `renderCenter` adds the
/// goo stretch and the idle bob the view draws.
public struct GooBody: Equatable, Sendable {
    public var index: Int
    public var id: String
    public var name: String
    public var value: Double
    public var radius: Double
    public var home: Vec2
    public var center: Vec2
    public var renderCenter: Vec2
    public var stretch: Double
    public var cluster: Int
}

/// Five file drops on a ring. Drag one near another and they stretch, then snap into
/// one cluster. Combine springs every drop into the dashed well; the smooth-min field
/// there climbs until the drops are one blob, which then morphs into Binder-01.pdf.
/// Reduce Motion skips the stretch and the spring and crossfades to the card.
public struct GooMergeModel: Sendable {
    public let drops: [GooDrop]
    public let seed: UInt64
    public private(set) var phase = GooMergePhase.ready
    public private(set) var time = 0.0
    public private(set) var reduceMotion: Bool
    public private(set) var morphElapsed = 0.0

    private var radii: [Double]
    private var homes: [Vec2]
    private var anchors: [Vec2]
    private var springs: [WhimsySpring2D]
    private var parent: [Int]
    private var omegas: [Double]
    private var stretchAmount: [Double]
    private var stretchDir: [Vec2]
    private var dragIndex: Int? = nil
    private let restInside: Double
    private let stackedInside: Double
    private let restMeta: Double
    private let stackedMeta: Double

    public init(drops: [GooDrop] = GooDrop.samples, seed: UInt64 = 1, reduceMotion: Bool = false) {
        let resolved = Self.resolved(drops)
        self.drops = resolved
        self.seed = seed
        self.reduceMotion = reduceMotion
        let count = resolved.count
        let localRadii = resolved.map { GooMergeField.radius(for: $0.value) }
        let localHomes = (0..<count).map { GooMergeField.ringPoint(index: $0, count: count) }
        radii = localRadii
        homes = localHomes
        anchors = localHomes
        springs = localHomes.map {
            WhimsySpring2D(value: $0, stiffness: GooMergeTuning.stiffness, dampingRatio: GooMergeTuning.dampingRatio)
        }
        parent = Array(0..<count)
        omegas = Self.bobOmegas(count: count, seed: seed)
        stretchAmount = Array(repeating: 0, count: count)
        stretchDir = Array(repeating: .zero, count: count)
        let homeCircles = (0..<count).map { GooCircle(center: localHomes[$0], radius: localRadii[$0]) }
        let stacked = localRadii.map { GooCircle(center: GooMergeTuning.well, radius: $0) }
        restInside = -GooMergeField.sdf(at: GooMergeTuning.well, circles: homeCircles)
        stackedInside = -GooMergeField.sdf(at: GooMergeTuning.well, circles: stacked)
        restMeta = GooMergeField.metaball(at: GooMergeTuning.well, circles: homeCircles)
        stackedMeta = GooMergeField.metaball(at: GooMergeTuning.well, circles: stacked)
    }

    public static func resolved(_ drops: [GooDrop]) -> [GooDrop] {
        if drops.count > GooMergeTuning.maxDrops {
            return Array(drops.prefix(GooMergeTuning.maxDrops))
        }
        if drops.count < GooMergeTuning.minDrops {
            return GooDrop.samples
        }
        return drops
    }

    public var count: Int { drops.count }
    public var well: Vec2 { GooMergeTuning.well }
    public var documentName: String { GooMergeTuning.documentName }
    public var isDragging: Bool { dragIndex != nil }
    public var bobOmegas: [Double] { omegas }

    public var morphProgress: Double {
        switch phase {
        case .ready, .combining: return 0
        case .merged: return 1
        case .morphing:
            let duration = reduceMotion ? GooMergeTuning.reducedFade : GooMergeTuning.morphDuration
            let t = duration > 0 ? min(1, max(0, morphElapsed / duration)) : 1
            return Self.easeInOut(t)
        }
    }

    public var mergeProgress: Double {
        if phase == .morphing || phase == .merged { return 1 }
        return GooMergeField.mergeProgress(
            logical: logicalCircles(),
            restInside: restInside,
            stackedInside: stackedInside,
            restMeta: restMeta,
            stackedMeta: stackedMeta
        )
    }

    public var blobOpacity: Double {
        switch phase {
        case .ready, .combining: return 1
        case .morphing: return 1 - morphProgress
        case .merged: return 0
        }
    }

    public var cardOpacity: Double {
        switch phase {
        case .ready, .combining: return 0
        case .morphing: return morphProgress
        case .merged: return 1
        }
    }

    /// The folded corner grows through the second half of the morph.
    public var fold: Double { WhimsyMath.smoothstep(0.4, 1, morphProgress) }

    public var animates: Bool {
        switch phase {
        case .combining, .morphing: return true
        case .merged: return false
        case .ready: return !reduceMotion
        }
    }

    public var accessibilityLabel: String { "Goo merge, \(count) files" }
    public var accessibilityValue: String {
        switch phase {
        case .ready: return GooMergeTuning.readyValue
        case .combining, .morphing: return GooMergeTuning.mergingValue
        case .merged: return GooMergeTuning.mergedValue
        }
    }

    public var bodies: [GooBody] {
        drops.indices.map { index in
            GooBody(
                index: index,
                id: drops[index].id,
                name: drops[index].name,
                value: drops[index].value,
                radius: radii[index],
                home: homes[index],
                center: springs[index].value,
                renderCenter: renderCenter(index),
                stretch: reduceMotion ? 0 : stretchAmount[index],
                cluster: find(index)
            )
        }
    }

    public func stretch(of index: Int) -> Double {
        guard drops.indices.contains(index), !reduceMotion else { return 0 }
        return stretchAmount[index]
    }

    public func isSnapped(_ a: Int, _ b: Int) -> Bool {
        guard drops.indices.contains(a), drops.indices.contains(b), a != b else { return false }
        return find(a) == find(b)
    }

    public func sdf(at point: Vec2) -> Double {
        GooMergeField.sdf(at: point, circles: renderCircles())
    }

    public func metaball(at point: Vec2) -> Double {
        GooMergeField.metaball(at: point, circles: renderCircles())
    }

    public var connectedPairCount: Int {
        let circles = renderCircles()
        var n = 0
        for i in drops.indices {
            for j in (i + 1)..<count {
                let mid = (renderCenter(i) + renderCenter(j)) * 0.5
                if GooMergeField.sdf(at: mid, circles: circles) <= GooMergeTuning.connectSDF {
                    n += 1
                }
            }
        }
        return n
    }

    public func hitIndex(at point: Vec2) -> Int? {
        guard phase == .ready else { return nil }
        var best: Int?
        var bestD = Double.greatestFiniteMagnitude
        for index in drops.indices {
            let d = renderCenter(index).distance(to: point)
            if d <= radii[index] + GooMergeTuning.hitSlop, d < bestD {
                best = index
                bestD = d
            }
        }
        return best
    }

    // MARK: input

    @discardableResult
    public mutating func beginDrag(at point: Vec2) -> Bool {
        guard let index = hitIndex(at: point) else { return false }
        return beginDrag(index: index)
    }

    @discardableResult
    public mutating func beginDrag(index: Int) -> Bool {
        guard phase == .ready, drops.indices.contains(index) else { return false }
        dragIndex = index
        refreshStretch()
        return true
    }

    @discardableResult
    public mutating func updateDrag(to point: Vec2) -> [GooMergeEvent] {
        guard let index = dragIndex, phase == .ready else { return [] }
        let lead = find(index)
        let desired = clamp(point, radius: radii[index])
        let delta = desired - springs[index].value
        for i in drops.indices where find(i) == lead {
            springs[i].snap(to: springs[i].value + delta)
        }
        let events = resolveSnaps()
        refreshStretch()
        return events
    }

    @discardableResult
    public mutating func endDrag() -> [GooMergeEvent] {
        guard let index = dragIndex else { return [] }
        dragIndex = nil
        let lead = find(index)
        var members: [Int] = []
        for i in drops.indices where find(i) == lead { members.append(i) }
        if members.count > 1 {
            for i in members { anchors[i] = springs[i].value }
        } else if reduceMotion {
            springs[index].snap(to: homes[index])
            anchors[index] = homes[index]
        } else {
            anchors[index] = homes[index]
        }
        refreshStretch()
        return []
    }

    @discardableResult
    public mutating func combine() -> [GooMergeEvent] {
        guard phase == .ready else { return [] }
        dragIndex = nil
        clearStretch()
        if reduceMotion {
            for i in drops.indices { springs[i].snap(to: well) }
            phase = .morphing
            morphElapsed = 0
            return [.combining, .morphing, .haptic]
        }
        phase = .combining
        return [.combining]
    }

    public mutating func setReduceMotion(_ on: Bool) {
        guard on != reduceMotion else { return }
        reduceMotion = on
        if on {
            clearStretch()
            if phase == .combining {
                for i in drops.indices { springs[i].snap(to: well) }
                phase = .morphing
                morphElapsed = 0
            }
        }
    }

    public mutating func reset() {
        self = GooMergeModel(drops: drops, seed: seed, reduceMotion: reduceMotion)
    }

    /// Advances by up to `GooMergeTuning.maxFrame` seconds, in fixed 1/240 s substeps.
    @discardableResult
    public mutating func step(_ dt: Double) -> [GooMergeEvent] {
        guard dt > 0, dt.isFinite else { return [] }
        var remaining = min(dt, GooMergeTuning.maxFrame)
        var events: [GooMergeEvent] = []
        while remaining > 1e-12 {
            let h = min(remaining, GooMergeTuning.substep)
            events += integrate(h)
            remaining -= h
        }
        return events
    }

    // MARK: sim

    private mutating func integrate(_ h: Double) -> [GooMergeEvent] {
        time += h
        switch phase {
        case .ready:
            attract(h)
            let events = resolveSnaps()
            let held = dragIndex.map { find($0) }
            for i in drops.indices {
                if let held, find(i) == held { continue }
                springs[i].step(toward: anchors[i], dt: h)
            }
            refreshStretch()
            return events
        case .combining:
            for i in drops.indices { springTowardWell(i, h: h) }
            let arrived = drops.indices.allSatisfy {
                springs[$0].value.distance(to: well) <= GooMergeTuning.arrival
            }
            if arrived {
                phase = .morphing
                morphElapsed = 0
                clearStretch()
                return [.morphing, .haptic]
            }
            return []
        case .morphing:
            morphElapsed += h
            let duration = reduceMotion ? GooMergeTuning.reducedFade : GooMergeTuning.morphDuration
            if morphElapsed + 1e-9 >= duration {
                morphElapsed = duration
                phase = .merged
                return [.merged(GooMergeTuning.documentName), .haptic]
            }
            return []
        case .merged:
            return []
        }
    }

    /// Semi-implicit Euler toward the well. If a substep steps back outward, pin the
    /// centre on the previous radius so the approach, and the field, never reverse.
    private mutating func springTowardWell(_ index: Int, h: Double) {
        let before = springs[index].value
        let beforeD = before.distance(to: well)
        springs[index].step(toward: well, dt: h)
        let after = springs[index].value
        let afterD = after.distance(to: well)
        if afterD > beforeD, afterD > 0 {
            let pulled = well + (after - well) * (beforeD / afterD)
            springs[index].x.value = pulled.x
            springs[index].y.value = pulled.y
            springs[index].x.velocity = 0
            springs[index].y.velocity = 0
        }
    }

    private mutating func attract(_ h: Double) {
        guard let index = dragIndex, !reduceMotion, h > 0 else { return }
        let lead = find(index)
        for j in drops.indices where find(j) != lead {
            var bestGap = Double.greatestFiniteMagnitude
            var bestI = index
            for i in drops.indices where find(i) == lead {
                let gap = surfaceGap(i, j)
                if gap < bestGap {
                    bestGap = gap
                    bestI = i
                }
            }
            guard bestGap < GooMergeTuning.stretchReach, bestGap > GooMergeTuning.snapGap else { continue }
            let span = GooMergeTuning.stretchReach - GooMergeTuning.snapGap
            let amount = span > 0 ? (GooMergeTuning.stretchReach - bestGap) / span : 1
            let dir = (springs[bestI].value - springs[j].value).normalized
            let next = springs[j].value + dir * (GooMergeTuning.attractSpeed * amount * h)
            springs[j].snap(to: next)
        }
    }

    private mutating func resolveSnaps() -> [GooMergeEvent] {
        guard let index = dragIndex, !reduceMotion, phase == .ready else { return [] }
        var events: [GooMergeEvent] = []
        var passes = 0
        while passes < count {
            passes += 1
            let lead = find(index)
            var didSnap = false
            for i in drops.indices where find(i) == lead {
                for j in drops.indices where find(j) != lead {
                    if surfaceGap(i, j) <= GooMergeTuning.snapGap {
                        let delta = springs[j].value - springs[i].value
                        for k in drops.indices where find(k) == lead {
                            springs[k].snap(to: springs[k].value + delta)
                        }
                        parent[lead] = find(j)
                        events.append(.snapped(min(i, j), max(i, j)))
                        events.append(.haptic)
                        didSnap = true
                        break
                    }
                }
                if didSnap { break }
            }
            if !didSnap { break }
        }
        return events
    }

    private mutating func refreshStretch() {
        for i in drops.indices {
            stretchAmount[i] = 0
            stretchDir[i] = .zero
        }
        guard phase == .ready, !reduceMotion else { return }
        let span = GooMergeTuning.stretchReach - GooMergeTuning.snapGap
        for i in drops.indices {
            var bestGap = Double.greatestFiniteMagnitude
            var bestJ = -1
            for j in drops.indices where find(j) != find(i) {
                let gap = surfaceGap(i, j)
                if gap < bestGap {
                    bestGap = gap
                    bestJ = j
                }
            }
            guard bestJ >= 0, bestGap < GooMergeTuning.stretchReach else { continue }
            let amount: Double
            if bestGap <= GooMergeTuning.snapGap || span <= 0 {
                amount = 1
            } else {
                amount = (GooMergeTuning.stretchReach - bestGap) / span
            }
            stretchAmount[i] = amount
            stretchDir[i] = (springs[bestJ].value - springs[i].value).normalized
        }
    }

    private mutating func clearStretch() {
        for i in drops.indices {
            stretchAmount[i] = 0
            stretchDir[i] = .zero
        }
    }

    private func surfaceGap(_ i: Int, _ j: Int) -> Double {
        springs[i].value.distance(to: springs[j].value) - radii[i] - radii[j]
    }

    private func find(_ index: Int) -> Int {
        var index = index
        while parent[index] != index { index = parent[index] }
        return index
    }

    private func renderCenter(_ index: Int) -> Vec2 {
        springs[index].value + stretchDir[index] * (stretchAmount[index] * GooMergeTuning.stretchShift) + bob(index)
    }

    private func bob(_ index: Int) -> Vec2 {
        guard phase == .ready, !reduceMotion else { return .zero }
        if let dragIndex, find(index) == find(dragIndex) { return .zero }
        let amp = GooMergeTuning.bobAmplitude * sin(time * omegas[index])
        return (homes[index] - well).normalized * amp
    }

    private func logicalCircles() -> [GooCircle] {
        drops.indices.map { GooCircle(center: springs[$0].value, radius: radii[$0]) }
    }

    private func renderCircles() -> [GooCircle] {
        drops.indices.map { GooCircle(center: renderCenter($0), radius: radii[$0]) }
    }

    private func clamp(_ point: Vec2, radius: Double) -> Vec2 {
        let x = min(max(point.x, radius), GooMergeTuning.pageWidth - radius)
        let y = min(max(point.y, radius), GooMergeTuning.pageHeight - radius)
        return Vec2(x, y)
    }

    private static func bobOmegas(count: Int, seed: UInt64) -> [Double] {
        var rng = SeededRandom(seed: seed)
        return (0..<count).map { _ in
            let unit = rng.uniform(0...1)
            return GooMergeTuning.bobOmega * (0.75 + 0.5 * unit)
        }
    }

    /// Cubic in-out written with multiplies so the web port matches bit for bit.
    static func easeInOut(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        if t < 0.5 { return 4 * t * t * t }
        let u = -2 * t + 2
        return 1 - (u * u * u) / 2
    }
}
