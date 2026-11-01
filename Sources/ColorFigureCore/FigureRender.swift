import Foundation

/// One thing for the view to draw, in screen units (the camera's 1:1 projection, y down).
public struct FigureItem: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case fill, stroke, hatch, disc }
    public var kind: Kind
    /// fill/stroke: the outline; hatch: endpoint pairs; disc: the centre.
    public var points: [Vec2]
    public var radius: Double = 0
    public var width: Double = 0
    public var color: FigureColor
    public var alpha: Double = 1
    public var closed: Bool = false
    /// The solid this came from (-1 for the shadow, the globe and sprites use their own ids), for tests and debugging.
    public var source: Int = -1
}

/// A flat round thing with a position in 3D: a gumball, drawn as a shaded disc.
public struct FigureSprite: Sendable {
    public var id: Int
    public var layer: FigureLayer
    public var centre: Vec3
    public var radius: Double
    public var color: FigureColor
    public var alpha: Double = 1
    /// Half-extents of the box used to order it among solids (defaults to the radius in every direction).
    public var half: Vec3?
}

/// A polyline in 3D, drawn as one stroke (the flap's return spring).
public struct FigureWire: Sendable {
    public var id: Int
    public var layer: FigureLayer
    public var points: [Vec3]
    public var width: Double
    public var color: FigureColor
}

/// The glass globe: a circle in any view, with gumballs inside it.
public struct FigureGlobe: Sendable {
    public var id: Int
    public var centre: Vec3
    public var radius: Double
    public var balls: [FigureSprite]
}

public struct FigureScene: Sendable {
    public var solids: [FigureSolid] = []
    public var sprites: [FigureSprite] = []
    public var wires: [FigureWire] = []
    public var globe: FigureGlobe?
    /// World points whose shadow is cast on the ground.
    public var shadowPoints: [Vec3] = []
    /// 0 is the closed machine, 1 is fully see-through.
    public var seeThrough: Double = 0
    public init() {}
}

public struct FigureFrame: Sendable {
    public var items: [FigureItem]
    /// The ids of the sorted nodes in the order they were painted (for tests).
    public var order: [String]
}

/// A thing to be depth-ordered: its box and centre.
public struct SortNode: Sendable {
    public var min: Vec3
    public var max: Vec3
    public var centre: Vec3
    public init(min: Vec3, max: Vec3, centre: Vec3) { self.min = min; self.max = max; self.centre = centre }
}

public enum FigureSorter {
    /// Painter's order, back to front. Two nodes whose boxes are separated along an axis the viewer can see are ordered by that
    /// separation (the one on the viewer's side goes last); everything else falls back on how near the centres are. The result is
    /// a topological order of the separation constraints, nearest-last among the free choices, and still produces an answer if
    /// the constraints form a cycle (the least-near remaining node goes next).
    public static func order(_ nodes: [SortNode], camera cam: FigureCamera) -> [Int] {
        let n = nodes.count
        let v = cam.toViewer
        var before = Array(repeating: [Int](), count: n)   // before[b] = nodes that must be drawn before b
        var indegree = Array(repeating: 0, count: n)
        var after = Array(repeating: [Int](), count: n)
        let eps = 1e-6
        for a in 0..<n {
            for b in (a + 1)..<n {
                var first = -1, second = -1
                for k in 0..<3 where abs(v[k]) > 1e-6 {
                    if nodes[a].max[k] <= nodes[b].min[k] + eps { (first, second) = v[k] > 0 ? (a, b) : (b, a); break }
                    if nodes[b].max[k] <= nodes[a].min[k] + eps { (first, second) = v[k] > 0 ? (b, a) : (a, b); break }
                }
                if first >= 0 { before[second].append(first); after[first].append(second); indegree[second] += 1 }
            }
        }
        let depth = nodes.map { cam.depth($0.centre) }
        var done = Array(repeating: false, count: n)
        var out: [Int] = []
        out.reserveCapacity(n)
        while out.count < n {
            var pick = -1
            for i in 0..<n where !done[i] && indegree[i] == 0 {
                if pick < 0 || depth[i] < depth[pick] || (depth[i] == depth[pick] && i < pick) { pick = i }
            }
            if pick < 0 {
                for i in 0..<n where !done[i] {
                    if pick < 0 || depth[i] < depth[pick] || (depth[i] == depth[pick] && i < pick) { pick = i }
                }
            }
            done[pick] = true
            out.append(pick)
            for s in after[pick] { indegree[s] -= 1 }
        }
        return out
    }
}

public enum FigureRenderer {
    private enum Node { case solid(Int), sprite(Int), wire(Int), globe }

    /// Draws a scene for a camera and style into a list of items, painter's order.
    public static func render(_ scene: FigureScene, camera cam: FigureCamera, style: FigureStyle) -> FigureFrame {
        var items: [FigureItem] = []
        let k = FigureEase.clamp01(scene.seeThrough)
        // Ground shadow first.
        if !scene.shadowPoints.isEmpty {
            let hull = FigureShadow.hull(of: scene.shadowPoints, camera: cam)
            if hull.count >= 3 { items.append(FigureItem(kind: .fill, points: hull, color: .shadowBlue, alpha: 0.5, closed: true, source: -1)) }
        }
        // The case as a ghost, under everything, while see-through.
        if k > 0 {
            for s in scene.solids where s.layer == .shell { drawGhost(s, k, cam, style, &items) }
        }
        var nodes: [Node] = []
        var sortNodes: [SortNode] = []
        for (i, s) in scene.solids.enumerated() {
            if s.layer == .shell && k > 0 { continue }
            if s.layer == .interior && k <= 0 { continue }
            nodes.append(.solid(i)); sortNodes.append(SortNode(min: s.bounds.min, max: s.bounds.max, centre: s.centre))
        }
        for (i, sp) in scene.sprites.enumerated() {
            if sp.layer == .interior && k <= 0 { continue }
            let h = sp.half ?? Vec3(sp.radius, sp.radius, sp.radius)
            nodes.append(.sprite(i)); sortNodes.append(SortNode(min: sp.centre - h, max: sp.centre + h, centre: sp.centre))
        }
        for (i, w) in scene.wires.enumerated() {
            if w.layer == .interior && k <= 0 { continue }
            var lo = w.points[0], hi = w.points[0]
            for p in w.points { lo = Vec3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)); hi = Vec3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)) }
            nodes.append(.wire(i)); sortNodes.append(SortNode(min: lo, max: hi, centre: (lo + hi) * 0.5))
        }
        if let g = scene.globe {
            let r = Vec3(g.radius, g.radius, g.radius)
            nodes.append(.globe); sortNodes.append(SortNode(min: g.centre - r, max: g.centre + r, centre: g.centre))
        }
        var names: [String] = []
        for idx in FigureSorter.order(sortNodes, camera: cam) {
            switch nodes[idx] {
            case .solid(let i):
                let s = scene.solids[i]
                names.append(s.part)
                let a = s.layer == .interior ? k * s.translucency : s.translucency * (1 - k * (1 - s.xrAlpha))
                drawSolid(s, alpha: a, cam, style, &items)
            case .sprite(let i):
                let sp = scene.sprites[i]
                names.append("sprite\(sp.id)")
                drawBall(sp, alphaScale: sp.layer == .interior ? k : 1, cam, style, &items)
            case .wire(let i):
                let w = scene.wires[i]
                names.append("wire\(w.id)")
                items.append(FigureItem(kind: .stroke, points: w.points.map { cam.project($0) }, width: w.width, color: w.color,
                                        alpha: w.layer == .interior ? k : 1, closed: false, source: w.id))
            case .globe:
                names.append("globe")
                drawGlobe(scene.globe!, cam, style, &items)
            }
        }
        return FigureFrame(items: items, order: names)
    }

    // MARK: wobble

    static func solidKey(_ s: FigureSolid, _ style: FigureStyle) -> UInt32 { FigureNoise.hash(style.seed, UInt32(s.id), 3) }

    /// The outline of one face with each edge bent through a seeded midpoint, in screen units.
    static func outline(_ s: FigureSolid, face f: [Int], _ p: [Vec2], key: UInt32, wobble: Double) -> [Vec2] {
        var pts: [Vec2] = []
        for i in 0..<f.count {
            let a = f[i], b = f[(i + 1) % f.count]
            pts.append(p[a])
            pts.append(midpoint(p, a, b, key: key, wobble: wobble))
        }
        return pts
    }

    static func midpoint(_ p: [Vec2], _ a: Int, _ b: Int, key: UInt32, wobble: Double) -> Vec2 {
        let lo = min(a, b), hi = max(a, b)
        let m = (p[lo] + p[hi]) * 0.5
        guard wobble > 0 else { return m }
        let dir = (p[hi] - p[lo]).normalized
        return m + dir.perpendicular * (FigureNoise.signed(key, UInt32(lo), UInt32(hi) &+ 1000) * FigureStyle.edgeAmp * wobble)
    }

    static func projected(_ s: FigureSolid, _ cam: FigureCamera, key: UInt32, wobble: Double) -> [Vec2] {
        var out: [Vec2] = []
        out.reserveCapacity(s.vertices.count)
        for (i, v) in s.vertices.enumerated() {
            var q = cam.project(v)
            if wobble > 0 {
                q = q + Vec2(FigureNoise.signed(key, UInt32(i), 1), FigureNoise.signed(key, UInt32(i), 2)) * (FigureStyle.vertexAmp * wobble)
            }
            out.append(q)
        }
        return out
    }

    // MARK: solids

    static func drawSolid(_ s: FigureSolid, alpha: Double, _ cam: FigureCamera, _ style: FigureStyle, _ items: inout [FigureItem]) {
        guard alpha > 0 else { return }
        let key = solidKey(s, style)
        let p = projected(s, cam, key: key, wobble: style.wobble)
        let light = style.lightDirection(cam)
        var visible = Array(repeating: false, count: s.faces.count)
        for (fi, f) in s.faces.enumerated() where cam.faces(s.normals[fi]) {
            visible[fi] = true
            let d = s.normals[fi].dot(light)
            let outl = outline(s, face: f, p, key: key, wobble: style.wobble)
            items.append(FigureItem(kind: .fill, points: outl, color: FigureTone.color(dot: d, palette: s.palette), alpha: alpha, closed: true, source: s.id))
            hatch(for: s.normals[fi], dot: d, outline: outl, key: FigureNoise.hash(key, UInt32(fi), 5), cam, style, alpha: alpha, source: s.id, &items)
        }
        let variation = 0.3 + 0.7 * style.wobble
        for (ei, e) in s.edges.enumerated() {
            let va = visible[e.faceA], vb = e.faceB >= 0 && visible[e.faceB]
            let silhouette = va != vb
            let crease = va && vb && e.hard
            guard silhouette || crease else { continue }
            let base = silhouette ? FigureStyle.silhouetteWidth : FigureStyle.creaseWidth
            let w = base * (1 + FigureStyle.lineVariation * variation * FigureNoise.signed(key, UInt32(ei), 7))
            let mid = midpoint(p, e.a, e.b, key: key, wobble: style.wobble)
            items.append(FigureItem(kind: .stroke, points: [p[e.a], mid, p[e.b]], width: w, color: .ink, alpha: alpha, closed: false, source: s.id))
        }
    }

    static func hatch(for normal: Vec3, dot d: Double, outline: [Vec2], key: UInt32, _ cam: FigureCamera, _ style: FigureStyle,
                      alpha: Double, source: Int, _ items: inout [FigureItem]) {
        let h = FigureTone.hatchDensity(dot: d)
        guard h > 0.08 else { return }
        let left = normal.dot(cam.right) < 0
        let angle = (left ? 52.0 : -52.0) * Double.pi / 180
        let spacing = 2.6 - 1.3 * h
        var segs = FigureHatch.segments(polygon: outline, angle: angle, spacing: spacing, key: key, jitter: 0.3 * style.wobble)
        if !segs.isEmpty {
            items.append(FigureItem(kind: .hatch, points: segs, width: FigureStyle.hatchWidth, color: .ink, alpha: 0.38 * h * alpha, source: source))
        }
        if d < -0.35 {
            segs = FigureHatch.segments(polygon: outline, angle: -angle, spacing: spacing + 0.4, key: key &+ 1, jitter: 0.3 * style.wobble)
            if !segs.isEmpty {
                items.append(FigureItem(kind: .hatch, points: segs, width: FigureStyle.hatchWidth, color: .ink, alpha: 0.3 * alpha, source: source))
            }
        }
    }

    /// The case while see-through: far walls, then near walls, faint fills and thin ink.
    static func drawGhost(_ s: FigureSolid, _ k: Double, _ cam: FigureCamera, _ style: FigureStyle, _ items: inout [FigureItem]) {
        let key = solidKey(s, style)
        let p = projected(s, cam, key: key, wobble: style.wobble)
        let light = style.lightDirection(cam)
        let fillAlpha = 1 - 0.86 * k
        for pass in 0..<2 {
            for (fi, f) in s.faces.enumerated() where cam.faces(s.normals[fi]) == (pass == 1) {
                let d = s.normals[fi].dot(light)
                let outl = outline(s, face: f, p, key: key, wobble: style.wobble)
                items.append(FigureItem(kind: .fill, points: outl, color: FigureTone.color(dot: d, palette: s.palette), alpha: fillAlpha * (pass == 0 ? 0.7 : 1), closed: true, source: s.id))
            }
        }
        let inkAlpha = 1 - 0.4 * k
        for (ei, e) in s.edges.enumerated() {
            let nearA = cam.faces(s.normals[e.faceA]), nearB = e.faceB >= 0 && cam.faces(s.normals[e.faceB])
            let far = !nearA && !nearB
            let w = (far ? FigureStyle.creaseWidth * 0.8 : FigureStyle.silhouetteWidth * 0.8) * (1 + FigureStyle.lineVariation * FigureNoise.signed(key, UInt32(ei), 7))
            let mid = midpoint(p, e.a, e.b, key: key, wobble: style.wobble)
            items.append(FigureItem(kind: .stroke, points: [p[e.a], mid, p[e.b]], width: w, color: .ink, alpha: inkAlpha * (far ? 0.55 : 1), closed: false, source: s.id))
        }
    }

    // MARK: balls and the globe

    /// A smooth hand-drawn circle: radius perturbed by two seeded sinusoids.
    static func circle(centre c: Vec2, radius r: Double, key: UInt32, wobble: Double, segments n: Int = 40) -> [Vec2] {
        let p1 = FigureNoise.unit(key, 1) * 2 * Double.pi, p2 = FigureNoise.unit(key, 2) * 2 * Double.pi
        return (0..<n).map { i in
            let th = 2 * Double.pi * Double(i) / Double(n)
            let rr = r + wobble * FigureStyle.ringAmp * 0.5 * (0.6 * sin(2 * th + p1) + 0.4 * sin(3 * th + p2))
            return c + Vec2(cos(th), sin(th)) * rr
        }
    }

    static func drawBall(_ b: FigureSprite, alphaScale: Double, _ cam: FigureCamera, _ style: FigureStyle, _ items: inout [FigureItem]) {
        let a = b.alpha * alphaScale
        guard a > 0 else { return }
        let key = FigureNoise.hash(style.seed, UInt32(b.id), 9)
        let c = cam.project(b.centre)
        let r = b.radius
        let dark = FigureColor.mix(b.color, FigureColor(0.16, 0.1, 0.24), 0.45)
        items.append(FigureItem(kind: .fill, points: circle(centre: c, radius: r, key: key, wobble: style.wobble), color: dark, alpha: a, closed: true, source: b.id))
        items.append(FigureItem(kind: .disc, points: [c + Vec2(-0.1 * r, -0.1 * r)], radius: r * 0.86, color: b.color, alpha: a, source: b.id))
        items.append(FigureItem(kind: .disc, points: [c + Vec2(-0.36 * r, -0.4 * r)], radius: r * 0.2, color: FigureColor(1, 1, 1), alpha: 0.7 * a, source: b.id))
        items.append(FigureItem(kind: .stroke, points: circle(centre: c, radius: r, key: key, wobble: style.wobble), width: 0.45, color: .ink, alpha: a, closed: true, source: b.id))
    }

    static func drawGlobe(_ g: FigureGlobe, _ cam: FigureCamera, _ style: FigureStyle, _ items: inout [FigureItem]) {
        let key = FigureNoise.hash(style.seed, UInt32(g.id), 13)
        let c = cam.project(g.centre)
        let ring = circle(centre: c, radius: g.radius, key: key, wobble: style.wobble, segments: 56)
        let tint = FigurePalette.glass.mid
        items.append(FigureItem(kind: .fill, points: ring, color: tint, alpha: 0.22, closed: true, source: g.id))
        for idx in g.balls.indices.sorted(by: { cam.depth(g.balls[$0].centre) < cam.depth(g.balls[$1].centre) }) {
            drawBall(g.balls[idx], alphaScale: 1, cam, style, &items)
        }
        items.append(FigureItem(kind: .fill, points: ring, color: FigurePalette.glass.light, alpha: 0.1, closed: true, source: g.id))
        items.append(FigureItem(kind: .stroke, points: ring, width: FigureStyle.silhouetteWidth, color: .ink, alpha: 1, closed: true, source: g.id))
        // Two white streaks high on the left and a small glint.
        for (a0, a1, w, al) in [(200.0, 240.0, 1.2, 0.75), (252.0, 262.0, 0.9, 0.6)] {
            let pts = (0...6).map { i -> Vec2 in
                let th = (a0 + (a1 - a0) * Double(i) / 6) * Double.pi / 180
                return c + Vec2(cos(th), sin(th)) * (g.radius * 0.8)
            }
            items.append(FigureItem(kind: .stroke, points: pts, width: w, color: FigureColor(1, 1, 1), alpha: al, closed: false, source: g.id))
        }
    }
}
