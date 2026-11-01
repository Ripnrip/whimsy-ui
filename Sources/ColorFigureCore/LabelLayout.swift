import Foundation

public struct GumballLabel: Equatable, Sendable {
    public var part: String
    public var text: String
    public var anchor: Vec3
}

public struct PlacedLabel: Equatable, Sendable {
    public enum Side: Equatable, Sendable { case left, right }
    public var part: String
    public var text: String
    public var anchor: Vec2
    public var centre: Vec2
    public var width: Double
    public var height: Double
    public var side: Side
    public var active: Bool
}

/// Names the working parts and places the labels in two columns beside the figure.
public enum LabelLayout {
    public static let all: [GumballLabel] = [
        GumballLabel(part: "coinSlot", text: "Coin slot", anchor: Vec3(18.5, 0, 41.5)),
        GumballLabel(part: "coinMech", text: "Coin mech", anchor: Vec3(14.2, 0, 38)),
        GumballLabel(part: "crank", text: "Crank", anchor: Vec3(21, 0, 24)),
        GumballLabel(part: "shaft", text: "Gear shaft", anchor: Vec3(10, 0, 24)),
        GumballLabel(part: "wheel", text: "Pocket wheel", anchor: Vec3(5.7, 0, 36)),
        GumballLabel(part: "chute", text: "Chute", anchor: Vec3(9.9, 6.4, 18)),
        GumballLabel(part: "spring", text: "Spring", anchor: Vec3(15.9, 0, 16)),
        GumballLabel(part: "flap", text: "Flap", anchor: Vec3(18, 0, 9)),
    ]

    public static let pillHeight = 9.0
    public static let gap = 2.6
    public static let margin = 5.0

    public static func width(of text: String) -> Double { Double(text.count) * 3.2 + 8 }

    /// Places labels for a camera. Each goes in the column on its anchor's side of the figure's centre line, ordered top to
    /// bottom by its anchor so the leader lines do not cross, and pushed apart to keep a gap.
    public static func place(_ labels: [GumballLabel] = all, camera cam: FigureCamera, active: Set<String> = []) -> [PlacedLabel] {
        let bounds = figureBounds(cam)
        let centreX = cam.project(Vec3(0, 0, 50)).x
        var left: [(GumballLabel, Vec2)] = [], right: [(GumballLabel, Vec2)] = []
        for l in labels {
            let a = cam.project(l.anchor)
            if a.x < centreX { left.append((l, a)) } else { right.append((l, a)) }
        }
        // Keep the columns roughly even: the anchors nearest the centre line move over.
        while right.count > left.count + 2 {
            let i = right.indices.min { right[$0].1.x < right[$1].1.x }!
            left.append(right.remove(at: i))
        }
        while left.count > right.count + 2 {
            let i = left.indices.max { left[$0].1.x < left[$1].1.x }!
            right.append(left.remove(at: i))
        }
        var out: [PlacedLabel] = []
        for (side, group) in [(PlacedLabel.Side.left, left), (.right, right)] {
            let sorted = group.sorted { $0.1.y != $1.1.y ? $0.1.y < $1.1.y : $0.0.part < $1.0.part }
            var ys = sorted.map { $0.1.y }
            let step = pillHeight + gap
            for i in 1..<max(ys.count, 1) where ys[i] < ys[i - 1] + step { ys[i] = ys[i - 1] + step }
            // Re-centre the pushed stack on where the anchors wanted to be.
            if !ys.isEmpty {
                let want = sorted.map { $0.1.y }.reduce(0, +) / Double(ys.count)
                let got = ys.reduce(0, +) / Double(ys.count)
                for i in ys.indices { ys[i] += want - got }
                if ys[0] < bounds.minY { let s = bounds.minY - ys[0]; for i in ys.indices { ys[i] += s } }
            }
            for (i, (l, a)) in sorted.enumerated() {
                let w = width(of: l.text)
                let cx = side == .left ? bounds.minX - margin - w / 2 : bounds.maxX + margin + w / 2
                out.append(PlacedLabel(part: l.part, text: l.text, anchor: a, centre: Vec2(cx, ys[i]), width: w, height: pillHeight,
                                       side: side, active: active.contains(l.part)))
            }
        }
        return out
    }

    /// The machine's projected extent for a camera.
    public static func figureBounds(_ cam: FigureCamera) -> (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        var pts: [Vec3] = []
        for x in [GumballLayout.slabMin.x, GumballLayout.slabMax.x] { for y in [GumballLayout.slabMin.y, GumballLayout.slabMax.y] {
            pts.append(Vec3(x, y, 0))
        } }
        pts.append(Vec3(0, 0, 107))
        let ps = pts.map { cam.project($0) } + [
            cam.project(GumballLayout.globeCentre) + Vec2(GumballLayout.globeRadius, 0),
            cam.project(GumballLayout.globeCentre) - Vec2(GumballLayout.globeRadius, 0),
        ]
        return (ps.map { $0.x }.min()!, ps.map { $0.x }.max()!, ps.map { $0.y }.min()!, ps.map { $0.y }.max()!)
    }
}
