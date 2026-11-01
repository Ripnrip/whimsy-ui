import Foundation

/// Which colours a solid is shaded with.
public struct FigurePalette: Equatable, Sendable {
    public var light: FigureColor
    public var mid: FigureColor
    public var dark: FigureColor
    public init(light: FigureColor, mid: FigureColor, dark: FigureColor) { self.light = light; self.mid = mid; self.dark = dark }

    /// Builds the three tones from one base colour: a touch lighter, the base, and a violet-tinted shade.
    public init(base: UInt32) {
        let b = FigureColor(hex: base)
        light = .mix(b, FigureColor(1, 1, 1), 0.2)
        mid = b
        dark = .mix(b, FigureColor(0.16, 0.1, 0.24), 0.55)
    }

    public static let metal = FigurePalette(light: FigureColor(hex: 0xF1F0EA), mid: FigureColor(hex: 0xC9CDCA), dark: FigureColor(hex: 0x8E959A))
    public static let charcoal = FigurePalette(light: FigureColor(hex: 0x5C564F), mid: FigureColor(hex: 0x433E39), dark: FigureColor(hex: 0x28241F))
    public static let glass = FigurePalette(light: FigureColor(hex: 0xE6F4F5), mid: FigureColor(hex: 0xC6E1E5), dark: FigureColor(hex: 0x9CBFC6))
    public static let ceramic = FigurePalette(light: FigureColor(hex: 0xFBF7EA), mid: FigureColor(hex: 0xE6DFC9), dark: FigureColor(hex: 0xB9AF94))
    public static let brass = FigurePalette(light: FigureColor(hex: 0xF2D58A), mid: FigureColor(hex: 0xD2AA4C), dark: FigureColor(hex: 0x7C5E22))
}

/// What a solid is, which decides when it is drawn.
public enum FigureLayer: Equatable, Sendable {
    /// The machine's case: opaque normally, a ghost in see-through.
    case shell
    /// Fixtures on the outside (crank, coin plate, flap): always drawn, on top of the ghost.
    case hardware
    /// Working parts inside: drawn only in see-through, fading in with it.
    case interior
}

/// A convex solid: vertices, faces (counter-clockwise seen from outside) and the data the inker needs.
public struct FigureSolid: Sendable {
    public var id: Int
    public var part: String
    public var layer: FigureLayer
    public var palette: FigurePalette
    public var vertices: [Vec3]
    public var faces: [[Int]]
    public var normals: [Vec3] = []
    /// Per-edge records, for silhouette and crease inking: vertex pair, adjacent faces (-1 if none), whether it is a hard edge.
    public var edges: [FigureEdge] = []
    /// Draw this solid as a see-through plate (the chute tube): its alpha is multiplied by this.
    public var translucency: Double = 1
    /// For hardware: how opaque it stays at full see-through (mounting plates fade so the works behind them show).
    public var xrAlpha: Double = 1
    public var bounds: (min: Vec3, max: Vec3) = (.zero, .zero)

    public init(id: Int, part: String, layer: FigureLayer, palette: FigurePalette, vertices: [Vec3], faces: [[Int]]) {
        self.id = id
        self.part = part
        self.layer = layer
        self.palette = palette
        self.vertices = vertices
        self.faces = faces
        finalize()
    }

    public var centre: Vec3 {
        var s = Vec3.zero
        for v in vertices { s = s + v }
        return s * (1 / Double(max(vertices.count, 1)))
    }

    /// Recomputes normals (pointing away from the centre), edges and bounds. Call after moving vertices.
    public mutating func finalize() {
        let c = centre
        normals = faces.map { f in
            // Newell's method, then flipped to point outward.
            var n = Vec3.zero
            for i in 0..<f.count {
                let a = vertices[f[i]], b = vertices[f[(i + 1) % f.count]]
                n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
            }
            n = n.normalized
            var fc = Vec3.zero
            for i in f { fc = fc + vertices[i] }
            fc = fc * (1 / Double(f.count))
            return n.dot(fc - c) < 0 ? -n : n
        }
        var table: [Int: Int] = [:]
        var list: [FigureEdge] = []
        let stride = vertices.count + 1
        for (fi, f) in faces.enumerated() {
            for i in 0..<f.count {
                let a = f[i], b = f[(i + 1) % f.count]
                let lo = min(a, b), hi = max(a, b), key = lo * stride + hi
                if let k = table[key] {
                    list[k].faceB = fi
                } else {
                    table[key] = list.count
                    list.append(FigureEdge(a: lo, b: hi, faceA: fi, faceB: -1, hard: true))
                }
            }
        }
        for k in list.indices where list[k].faceB >= 0 {
            list[k].hard = normals[list[k].faceA].dot(normals[list[k].faceB]) < FigureSolid.hardEdgeCos
        }
        edges = list
        var lo = vertices[0], hi = vertices[0]
        for v in vertices {
            lo = Vec3(min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z))
            hi = Vec3(max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z))
        }
        bounds = (lo, hi)
    }

    /// Two faces whose normals differ by more than ~35 degrees make a hard edge (inked even when both are visible).
    public static let hardEdgeCos = 0.82

    public func rotated(_ axis: Axis, about pivot: Vec3, by angle: Double) -> FigureSolid {
        var s = self
        let c = cos(angle), sn = sin(angle)
        s.vertices = vertices.map { v in
            let d = v - pivot
            switch axis {
            case .x: return Vec3(v.x, pivot.y + d.y * c - d.z * sn, pivot.z + d.y * sn + d.z * c)
            case .y: return Vec3(pivot.x + d.x * c + d.z * sn, v.y, pivot.z - d.x * sn + d.z * c)
            case .z: return Vec3(pivot.x + d.x * c - d.y * sn, pivot.y + d.x * sn + d.y * c, v.z)
            }
        }
        s.finalize()
        return s
    }

    public func translated(_ t: Vec3) -> FigureSolid {
        var s = self
        s.vertices = vertices.map { $0 + t }
        s.finalize()
        return s
    }
}

public struct FigureEdge: Equatable, Sendable {
    public var a: Int
    public var b: Int
    public var faceA: Int
    public var faceB: Int
    public var hard: Bool
}

/// Builders for the convex solids a figure is made from.
public enum FigureShapes {
    public static func box(id: Int, part: String, layer: FigureLayer, palette: FigurePalette, min lo: Vec3, max hi: Vec3) -> FigureSolid {
        var v: [Vec3] = []
        for i in 0..<8 { v.append(Vec3(i & 1 == 0 ? lo.x : hi.x, i & 2 == 0 ? lo.y : hi.y, i & 4 == 0 ? lo.z : hi.z)) }
        let f = [[0, 2, 3, 1], [4, 5, 7, 6], [0, 1, 5, 4], [2, 6, 7, 3], [0, 4, 6, 2], [1, 3, 7, 5]]
        return FigureSolid(id: id, part: part, layer: layer, palette: palette, vertices: v, faces: f)
    }

    /// A cylinder (or cone frustum when the radii differ) along `axis` from `t0` to `t1`, centred at the lateral point `centre`
    /// (the other two coordinates, in world order).
    public static func cylinder(id: Int, part: String, layer: FigureLayer, palette: FigurePalette, axis: Axis, centre: (Double, Double),
                                from t0: Double, to t1: Double, radius r0: Double, radiusEnd r1: Double? = nil, segments n: Int = 14) -> FigureSolid {
        let rEnd = r1 ?? r0
        func point(_ t: Double, _ a: Double, _ b: Double) -> Vec3 {
            switch axis {
            case .x: return Vec3(t, a, b)
            case .y: return Vec3(a, t, b)
            case .z: return Vec3(a, b, t)
            }
        }
        var v: [Vec3] = []
        for i in 0..<n { let th = 2 * Double.pi * Double(i) / Double(n); v.append(point(t0, centre.0 + r0 * cos(th), centre.1 + r0 * sin(th))) }
        for i in 0..<n { let th = 2 * Double.pi * Double(i) / Double(n); v.append(point(t1, centre.0 + rEnd * cos(th), centre.1 + rEnd * sin(th))) }
        var f: [[Int]] = []
        for i in 0..<n { f.append([i, (i + 1) % n, n + (i + 1) % n, n + i]) }
        f.append(Array((0..<n).reversed()))
        f.append(Array(n..<2 * n))
        return FigureSolid(id: id, part: part, layer: layer, palette: palette, vertices: v, faces: f)
    }

    /// A square-section rod from `a` to `b` with half-width `w`.
    public static func rod(id: Int, part: String, layer: FigureLayer, palette: FigurePalette, from a: Vec3, to b: Vec3, halfWidth w: Double) -> FigureSolid {
        let d = (b - a).normalized
        let ref = abs(d.z) > 0.95 ? Vec3(1, 0, 0) : Vec3(0, 0, 1)
        let u = d.cross(ref).normalized * w
        let s = d.cross(u).normalized * w
        var v: [Vec3] = []
        for e in [a, b] { for (su, ss) in [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)] { v.append(e + u * su + s * ss) } }
        let f = [[0, 1, 2, 3], [7, 6, 5, 4], [0, 4, 5, 1], [1, 5, 6, 2], [2, 6, 7, 3], [3, 7, 4, 0]]
        return FigureSolid(id: id, part: part, layer: layer, palette: palette, vertices: v, faces: f)
    }
}
