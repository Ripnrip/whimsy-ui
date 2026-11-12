import Foundation

public struct Vec3: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }

    public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    public func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    public var length: Double { (x * x + y * y + z * z).squareRoot() }
    public var normalized: Vec3 {
        let l = length
        return l > 1e-12 ? self * (1 / l) : .zero
    }
}

public struct CrumpleFacet: Equatable, Sendable {
    public var i0: Int
    public var i1: Int
    public var i2: Int
    public var normal: Vec3
    public var shade: Double
    public var color: CrumpleColor

    public init(i0: Int, i1: Int, i2: Int, normal: Vec3, shade: Double, color: CrumpleColor) {
        self.i0 = i0
        self.i1 = i1
        self.i2 = i2
        self.normal = normal
        self.shade = shade
        self.color = color
    }
}

/// An undirected mesh edge shared by two triangles. `index` is the crease id.
public struct CrumpleEdge: Equatable, Sendable {
    public var index: Int
    public var a: Int
    public var b: Int
    public var left: Int
    public var right: Int

    public init(index: Int, a: Int, b: Int, left: Int, right: Int) {
        self.index = index
        self.a = a
        self.b = b
        self.left = left
        self.right = right
    }
}

public struct CrumpleSample: Equatable, Sendable {
    public var vertices: [Vec3]
    public var facets: [CrumpleFacet]
    public var edges: [CrumpleEdge]

    public init(vertices: [Vec3], facets: [CrumpleFacet], edges: [CrumpleEdge]) {
        self.vertices = vertices
        self.facets = facets
        self.edges = edges
    }
}

public enum CrumpleShade {
    public static func unitLight(_ rules: CrumpleRules) -> Vec3 {
        Vec3(rules.lightX, rules.lightY, rules.lightZ).normalized
    }

    /// Lambert term. A normal facing the light is 1; the opposite facing is 0.
    public static func lambert(normal: Vec3, light: Vec3) -> Double {
        let n = normal.normalized
        let l = light.normalized
        guard n.length > 0, l.length > 0 else { return 0 }
        return max(0, n.dot(l))
    }

    public static func color(shade: Double, rules: CrumpleRules) -> CrumpleColor {
        let t = rules.ambient + (1 - rules.ambient) * WhimsyMath.clamp01(shade)
        return rules.paper.scaled(t)
    }
}

public enum CrumpleMesh {
    /// `shape` 0 is the flat card. `shape` 1 sits on the ball. Above 1 the ball grows, so a spring can overshoot.
    public static func sample(card: CrumpleRect, shape: Double, pull: Vec2 = .zero, rules: CrumpleRules = CrumpleRules()) -> CrumpleSample {
        let s = max(shape, 0)
        let amps = amplitudes(rules)
        let ballR = ballRadius(card, rules)
        let center = card.center
        var vertices: [Vec3] = []
        vertices.reserveCapacity(rules.vertexCount)
        for j in 0..<rules.vertexRows {
            for i in 0..<rules.vertexColumns {
                let rest = Vec2(
                    card.x + card.width * Double(i) / Double(rules.columns),
                    card.y + card.height * Double(j) / Double(rules.rows)
                )
                let offset = rest - center
                let dist = offset.length
                let dir = dist > 1e-9 ? offset * (1 / dist) : Vec2(1, 0)
                let radius = s <= 1 ? WhimsyMath.lerp(dist, ballR, s) : ballR * s
                let xy = center + dir * radius + pull
                let z = amps[j * rules.vertexColumns + i] * min(s, 1.25) * ballR * rules.buckle
                vertices.append(Vec3(xy.x, xy.y, z))
            }
        }

        let light = CrumpleShade.unitLight(rules)
        var facets: [CrumpleFacet] = []
        facets.reserveCapacity(rules.triangleCount)
        let stride = rules.vertexColumns
        for row in 0..<rules.rows {
            for col in 0..<rules.columns {
                let v00 = row * stride + col
                let v10 = v00 + 1
                let v01 = v00 + stride
                let v11 = v01 + 1
                facets.append(facet(v00, v10, v01, vertices, light, rules))
                facets.append(facet(v10, v11, v01, vertices, light, rules))
            }
        }
        return CrumpleSample(vertices: vertices, facets: facets, edges: sharedEdges(facets))
    }

    public static func ballRadius(_ card: CrumpleRect, _ rules: CrumpleRules = CrumpleRules()) -> Double {
        min(abs(card.width), abs(card.height)) * rules.ballRadiusFraction
    }

    /// Fold angle in radians for each shared edge, in crease-id order.
    public static func foldAngles(_ sample: CrumpleSample) -> [Double] {
        sample.edges.map { edge in
            let a = sample.facets[edge.left].normal
            let b = sample.facets[edge.right].normal
            let d = WhimsyMath.clamp(a.normalized.dot(b.normalized), -1, 1)
            return acos(d)
        }
    }

    /// SplitMix64 uniforms in vertex order. `SeededRandom.uniform` is the bit-stable helper.
    public static func amplitudes(_ rules: CrumpleRules) -> [Double] {
        var rng = SeededRandom(seed: rules.seed)
        return (0..<rules.vertexCount).map { _ in rng.uniform(-1...1) }
    }

    private static func facet(_ i0: Int, _ i1: Int, _ i2: Int, _ vertices: [Vec3], _ light: Vec3, _ rules: CrumpleRules) -> CrumpleFacet {
        let normal = (vertices[i1] - vertices[i0]).cross(vertices[i2] - vertices[i0])
        let shade = CrumpleShade.lambert(normal: normal, light: light)
        return CrumpleFacet(i0: i0, i1: i1, i2: i2, normal: normal.normalized, shade: shade, color: CrumpleShade.color(shade: shade, rules: rules))
    }

    private static func sharedEdges(_ facets: [CrumpleFacet]) -> [CrumpleEdge] {
        struct Key: Hashable { var a: Int; var b: Int }
        var owners: [Key: [Int]] = [:]
        for (index, facet) in facets.enumerated() {
            for pair in [(facet.i0, facet.i1), (facet.i1, facet.i2), (facet.i2, facet.i0)] {
                let key = Key(a: min(pair.0, pair.1), b: max(pair.0, pair.1))
                owners[key, default: []].append(index)
            }
        }
        let shared = owners.filter { $0.value.count == 2 }.sorted { lhs, rhs in
            lhs.key.a == rhs.key.a ? lhs.key.b < rhs.key.b : lhs.key.a < rhs.key.a
        }
        return shared.enumerated().map { offset, item in
            CrumpleEdge(index: offset, a: item.key.a, b: item.key.b, left: item.value[0], right: item.value[1])
        }
    }
}
