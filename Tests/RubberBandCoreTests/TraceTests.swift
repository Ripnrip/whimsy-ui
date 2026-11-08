import Testing
import Foundation
@testable import RubberBandCore

/// A fixed script the web port replays. Line labels must stay stable; numbers are compared
/// with an absolute tolerance in the parity check, because `printf` and `toFixed` can
/// round a halfway case differently.
enum RubberBandTrace {
    static func canonical() -> String {
        var lines: [String] = []
        func add(_ s: String) { lines.append(s) }
        func f(_ x: Double) -> String {
            guard x.isFinite else { return "nan" }
            let y = x == 0 ? 0.0 : x
            return String(format: "%.6f", y)
        }
        add("rubberScale \(f(RubberBandResistance.scale))")
        add("rubberLength \(f(RubberBandResistance.length))")
        add("hoverLift \(f(RubberBandLayout.hoverLift))")
        add("commitRise \(f(RubberBandLayout.commitRise))")
        add("flickSpeed \(f(RubberBandLayout.flickSpeed))")
        add("flickMin \(f(RubberBandLayout.flickMin))")
        add("grabSlop \(f(RubberBandLayout.grabSlop))")
        add("stickiness \(f(RubberBandLayout.stickiness))")
        add("dismissRise \(f(RubberBandLayout.dismissRise))")
        add("dismissFlick \(f(RubberBandLayout.dismissFlick))")
        add("presentedScale \(f(RubberBandLayout.presentedScale))")
        add("width \(f(RubberBandLayout.width))")
        add("height \(f(RubberBandLayout.height))")
        add("cardWidth \(f(RubberBandLayout.cardWidth))")
        add("cardHeight \(f(RubberBandLayout.cardHeight))")
        add("arcRadius \(f(RubberBandLayout.arcRadius))")
        add("halfSpan \(f(RubberBandLayout.halfSpan))")
        add("bottomMargin \(f(RubberBandLayout.bottomMargin))")
        add("stage \(f(RubberBandLayout.stage.x)) \(f(RubberBandLayout.stage.y))")
        add("origin \(f(RubberBandLayout.origin.x)) \(f(RubberBandLayout.origin.y))")
        for i in 0..<5 {
            let c = RubberBandLayout.restCenter(i)
            add("rest \(i) \(f(c.x)) \(f(c.y)) \(f(RubberBandLayout.restRotation(i)))")
        }
        for x in [-400.0, -100, 0, 20, 100, 180, 300, 600, 1000] {
            add("resist \(f(x)) \(f(RubberBandResistance.resist(x))) \(f(RubberBandResistance.slope(at: x)))")
        }
        for card in RubberBandCatalog.cards {
            add("card \(card.index) \(card.title) \(card.kicker) \(card.marks.count) \(f(card.paper.r)) \(f(card.paper.g)) \(f(card.paper.b)) \(f(card.ink.r)) \(f(card.ink.g)) \(f(card.ink.b))")
            for mark in card.marks {
                switch mark {
                case let .ellipse(cx, cy, rx, ry, color, alpha):
                    add("mark ellipse \(f(cx)) \(f(cy)) \(f(rx)) \(f(ry)) \(f(0)) \(f(color.r)) \(f(color.g)) \(f(color.b)) \(f(alpha))")
                case let .roundRect(cx, cy, width, height, corner, color, alpha):
                    add("mark rect \(f(cx)) \(f(cy)) \(f(width)) \(f(height)) \(f(corner)) \(f(color.r)) \(f(color.g)) \(f(color.b)) \(f(alpha))")
                case let .capsule(cx, cy, width, height, rotation, color, alpha):
                    add("mark capsule \(f(cx)) \(f(cy)) \(f(width)) \(f(height)) \(f(rotation)) \(f(color.r)) \(f(color.g)) \(f(color.b)) \(f(alpha))")
                }
            }
        }

        func phaseName(_ p: RubberBandPhase) -> String {
            switch p {
            case .resting: "resting"
            case .browsing: "browsing"
            case .dragging: "dragging"
            case .presenting: "presenting"
            case .presented: "presented"
            case .dismissing: "dismissing"
            case .returning: "returning"
            }
        }
        func eventName(_ e: RubberBandEvent) -> String {
            switch e {
            case .lifted(let i): "lifted \(i)"
            case .grabbed(let i): "grabbed \(i)"
            case .armed(let i): "armed \(i)"
            case .committed(let i): "committed \(i)"
            case .presented(let i): "presented \(i)"
            case .dismissed(let i): "dismissed \(i)"
            case .restored(let i): "restored \(i)"
            }
        }
        func dump(_ m: RubberBandModel, _ tag: String) {
            let focus = m.focusIndex.map(String.init) ?? "-"
            let active = m.activeIndex.map(String.init) ?? "-"
            add("state \(tag) \(phaseName(m.phase)) \(focus) \(active) \(f(m.pullUp)) \(f(m.pullRight)) \(m.isArmed ? 1 : 0) \(f(m.openness))")
            for i in 0..<5 {
                let p = m.pose(i)
                add("pose \(tag) \(i) \(f(p.center.x)) \(f(p.center.y)) \(f(p.rotation)) \(f(p.lift)) \(f(p.scale)) \(f(p.flip)) \(f(p.opacity)) \(p.z)")
            }
        }
        func note(_ events: [RubberBandEvent], _ tag: String) {
            if events.isEmpty { add("events \(tag) -") }
            else { add("events \(tag) " + events.map(eventName).joined(separator: ",")) }
        }
        func pump(_ m: inout RubberBandModel, _ seconds: Double, _ tag: String) {
            var left = seconds
            var bucket: [RubberBandEvent] = []
            var slice = 0
            while left > 1e-9 {
                let d = min(1.0 / 60, left)
                bucket += m.step(d)
                left -= d
                slice += 1
                if slice % 6 == 0 {
                    note(bucket, "\(tag).\(slice)")
                    dump(m, "\(tag).\(slice)")
                    bucket = []
                }
            }
            if !bucket.isEmpty {
                note(bucket, "\(tag).end")
                dump(m, "\(tag).end")
            }
        }

        var m = RubberBandModel()
        dump(m, "start")
        let c0 = RubberBandLayout.restCenter(0)
        note(m.pointerDown(at: c0, at: 0), "down0")
        dump(m, "down0")
        pump(&m, 0.3, "hover0")
        for i in 1..<5 {
            let c = RubberBandLayout.restCenter(i)
            note(m.pointerMoved(to: c, at: 0.3 + Double(i) * 0.05), "slide\(i)")
            dump(m, "slide\(i)")
        }
        note(m.pointerUp(at: RubberBandLayout.restCenter(4), at: 1), "upSlide")
        dump(m, "upSlide")
        pump(&m, 0.4, "settle")

        let c2 = RubberBandLayout.restCenter(2)
        note(m.pointerDown(at: c2, at: 2), "down2")
        pump(&m, 0.4, "hover2")
        let dragged = Vec2(c2.x, c2.y - 180)
        note(m.pointerMoved(to: dragged, at: 2.6), "drag")
        dump(m, "drag")
        note(m.pointerUp(at: dragged, at: 2.6), "release")
        dump(m, "release")
        pump(&m, 1.2, "flight")
        note(m.dismiss(), "dismiss")
        dump(m, "dismiss")
        pump(&m, 1.2, "home")

        var flick = RubberBandModel()
        let c1 = RubberBandLayout.restCenter(1)
        let tip = Vec2(c1.x, c1.y - 40)
        note(flick.pointerDown(at: c1, at: 0), "flickDown")
        note(flick.pointerMoved(to: tip, at: 0.03), "flickMove")
        note(flick.pointerUp(at: tip, at: 0.03), "flickUp")
        dump(flick, "flick")

        var early = RubberBandModel()
        note(early.pointerDown(at: c2, at: 0), "earlyDown")
        let short = Vec2(c2.x, c2.y - 36)
        note(early.pointerMoved(to: short, at: 0.5), "earlyMove")
        note(early.pointerUp(at: short, at: 0.8), "earlyUp")
        dump(early, "early")

        var rm = RubberBandModel(reduceMotion: true)
        note(rm.activate(3), "rmOpen")
        dump(rm, "rmOpen")
        note(rm.dismiss(), "rmClose")
        dump(rm, "rmClose")
        return lines.joined(separator: "\n") + "\n"
    }
}

@Suite("Trace") struct TraceTests {
    @Test func canonicalTraceIsStable() throws {
        let text = RubberBandTrace.canonical()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count > 80)
        #expect(text.hasPrefix("rubberScale 0.550000\n"))
        #expect(text.contains("rubberLength 300.000000"))
        #expect(text.contains("hoverLift 20.000000"))
        #expect(text.contains("events flickUp committed 1"))
        #expect(text.contains("events rmOpen committed 3,presented 3"))
        if let path = ProcessInfo.processInfo.environment["RUBBER_TRACE_OUT"], !path.isEmpty {
            try text.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        }
    }
}
