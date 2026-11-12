//  CrumpleToDelete.swift
//
//  Drag a card toward the trash. It folds into about forty shaded triangles, and letting go
//  past the line — or inside the bin — snaps it into a ball and tosses it in. Letting go
//  earlier springs it flat. The triangles are generated paper; the view you pass is the
//  face people see while the card is still flat.

#if canImport(SwiftUI)
import SwiftUI
import CrumpleCore

/// A card that crumples into the trash.
///
/// ```swift
/// CrumpleToDelete {
///     Text("Grocery list")
/// } onDeleted: {
///     // fired once, when the ball lands
/// }
/// ```
public struct CrumpleToDelete<Content: View>: View {
    private var content: () -> Content
    private var onDeleted: () -> Void
    private var restoreToken: Int
    @State private var engine = CrumpleEngine()
    @State private var animating = true
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(restoreToken: Int = 0, @ViewBuilder content: @escaping () -> Content, onDeleted: @escaping () -> Void = {}) {
        self.restoreToken = restoreToken
        self.content = content
        self.onDeleted = onDeleted
    }

    public var body: some View {
        TimelineView(.animation(paused: !animating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            stage(m)
                .onChange(of: timeline.date) { _, _ in
                    if m.phase == .idle, !dragging { animating = false }
                }
                .onChange(of: engine.arrivalCount) { _, _ in
                    onDeleted()
                    AccessibilityNotification.Announcement("Card deleted").post()
                }
                .onChange(of: engine.restoreCount) { _, _ in
                    AccessibilityNotification.Announcement("Card restored").post()
                }
                .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: engine.hapticTick)
                .onChange(of: restoreToken) { _, _ in
                    _ = engine.reset()
                    animating = true
                }
        }
    }

    private func stage(_ m: CrumpleModel) -> some View {
        let layout = CrumpleStageLayout.standard
        return ZStack(alignment: .topLeading) {
            bin(m, layout: layout)
            face(m, layout: layout)
            if !reduceMotion {
                meshLayer(m, layout: layout)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: layout.stage.width, height: layout.stage.height)
        .coordinateSpace(name: "crumple")
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("crumple")).onChanged { g in
            let point = Vec2(g.location.x, g.location.y)
            if !dragging {
                dragging = true
                animating = true
                _ = engine.begin(at: point)
            } else {
                _ = engine.drag(to: point)
            }
        }.onEnded { _ in
            dragging = false
            _ = engine.end()
            animating = true
        })
        .accessibilityElement(children: .contain)
    }

    private func face(_ m: CrumpleModel, layout: CrumpleStageLayout) -> some View {
        let fade = faceOpacity(m)
        let scale = faceScale(m)
        return content()
            .frame(width: layout.card.width, height: layout.card.height)
            .opacity(fade)
            .scaleEffect(scale)
            .position(x: m.center.x, y: m.center.y)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Card")
            .accessibilityValue(m.phase == .gone ? "Deleted" : "Ready")
            .accessibilityHint("Drag toward the trash to crumple and delete")
            .accessibilityAction(named: "Delete") {
                _ = engine.commit()
                animating = true
            }
    }

    private func faceOpacity(_ m: CrumpleModel) -> Double {
        if reduceMotion {
            switch m.phase {
            case .tossing: return 1 - m.toss
            case .gone: return 0
            default: return 1 - m.progress
            }
        }
        switch m.phase {
        case .tossing, .gone: return 0
        default: return 1 - m.progress
        }
    }

    private func faceScale(_ m: CrumpleModel) -> Double {
        guard reduceMotion else { return 1 }
        switch m.phase {
        case .tossing: return (1 - 0.06 * m.progress) * (1 - m.toss)
        case .gone: return 0
        default: return 1 - 0.06 * m.progress
        }
    }

    private func meshLayer(_ m: CrumpleModel, layout: CrumpleStageLayout) -> some View {
        Canvas { ctx, _ in
            guard m.phase != .gone else { return }
            let sample = m.sample
            let shift: Vec2 = (m.phase == .tossing || m.phase == .gone) ? (m.center - m.card.center) : .zero
            let alpha = m.phase == .tossing ? 1.0 : m.progress
            guard alpha > 0.001 else { return }
            ctx.opacity = alpha
            ctx.translateBy(x: shift.x, y: shift.y)
            for facet in sample.facets {
                var path = Path()
                let points = [facet.i0, facet.i1, facet.i2].map { sample.vertices[$0] }
                path.move(to: CGPoint(x: points[0].x, y: points[0].y))
                path.addLine(to: CGPoint(x: points[1].x, y: points[1].y))
                path.addLine(to: CGPoint(x: points[2].x, y: points[2].y))
                path.closeSubpath()
                ctx.fill(path, with: .color(Color(red: facet.color.r, green: facet.color.g, blue: facet.color.b)))
            }
        }
        .frame(width: layout.stage.width, height: layout.stage.height)
    }

    private func bin(_ m: CrumpleModel, layout: CrumpleStageLayout) -> some View {
        let open = m.phase == .tossing || m.phase == .gone ? 0.7 : 0
        let bump: Double = m.phase == .gone && !reduceMotion ? 1 : 0
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(red: 0.22, green: 0.24, blue: 0.28))
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.12, green: 0.13, blue: 0.15))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .padding(.top, 16)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.45, green: 0.48, blue: 0.52))
                .frame(height: 8)
                .offset(y: -layout.bin.height / 2 + 4)
                .rotationEffect(.radians(-open * 0.9 - bump * 0.25), anchor: .bottom)
            Image(systemName: "trash")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .offset(y: 6)
        }
        .frame(width: layout.bin.width, height: layout.bin.height)
        .position(x: layout.bin.center.x, y: layout.bin.center.y)
        .accessibilityLabel("Trash")
    }
}

/// The demo card, the trash, and an undo control.
public struct CrumpleToDeleteDemo: View {
    @State private var restore = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 18) {
            CrumpleToDelete(restoreToken: restore) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GROCERY LIST")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(Color(red: 0.45, green: 0.32, blue: 0.18))
                    Text("Peaches, oats,\nand a lemon.")
                        .font(.system(size: 20, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(red: 0.16, green: 0.12, blue: 0.08))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(red: 0.98, green: 0.96, blue: 0.91))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
            }
            Button("Undo") { restore += 1 }
                .buttonStyle(.bordered)
                .accessibilityHint("Restores the card so you can crumple it again")
            Text("Drag the card into the trash. Let go early and it flattens.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct CrumpleStageLayout: Equatable {
    var stage: CrumpleRect
    var card: CrumpleRect
    var bin: CrumpleRect

    static let standard = CrumpleStageLayout(
        stage: CrumpleRect(x: 0, y: 0, width: 320, height: 230),
        card: CrumpleRect(x: 24, y: 46, width: 200, height: 140),
        bin: CrumpleRect(x: 248, y: 78, width: 56, height: 64)
    )
}

private final class CrumpleEngine {
    var model = CrumpleModel(
        card: CrumpleStageLayout.standard.card,
        bin: CrumpleStageLayout.standard.bin
    )
    private var last: Date?
    private var seenCreases = 0
    private(set) var hapticTick = 0
    private var lastHaptic: Date?
    private(set) var arrivalCount = 0
    private(set) var restoreCount = 0
    private var seenArrivals = 0
    private var seenRestores = 0

    func frame(at date: Date, reduceMotion: Bool) -> CrumpleModel {
        model.reduceMotion = reduceMotion
        if let last {
            var remaining = min(date.timeIntervalSince(last), 0.1)
            while remaining > 1e-4 {
                let dt = min(remaining, 1.0 / 60)
                _ = model.step(dt)
                remaining -= dt
            }
            note()
        }
        last = date
        return model
    }

    func begin(at point: Vec2) -> Bool { model.begin(at: point) }
    func drag(to point: Vec2) -> [CrumpleEvent] {
        let events = model.drag(to: point)
        note()
        return events
    }
    func end() { _ = model.end() }
    func commit() { _ = model.commit() }
    func reset() { _ = model.reset() }

    private func note() {
        let creases = model.log.reduce(into: 0) { count, event in
            if case .crease = event { count += 1 }
        }
        if creases > seenCreases {
            seenCreases = creases
            let now = Date()
            if lastHaptic == nil || now.timeIntervalSince(lastHaptic!) >= model.rules.hapticInterval {
                lastHaptic = now
                hapticTick += 1
            }
        }
        if model.log.contains(.arrived) {
            let arrivals = model.log.filter { $0 == .arrived }.count
            if arrivals > seenArrivals {
                seenArrivals = arrivals
                arrivalCount += 1
            }
        }
        let restores = model.log.filter { $0 == .restored }.count
        if restores > seenRestores {
            seenRestores = restores
            restoreCount += 1
        }
    }
}

#Preview("Crumple to delete") {
    CrumpleToDeleteDemo()
}
#endif
