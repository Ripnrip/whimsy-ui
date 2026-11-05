//
//  HoldToFanDock.swift
//  HoldToFanDock
//
//  A bottom floating action button that fans four tabs out along a quarter-circle when you
//  press and hold. Hold past about 0.2 s and the tabs spring out into the upper-left arc above
//  the FAB, staggered; drag toward one to highlight it, lift over it to select (a soft haptic),
//  or lift elsewhere / drag off the arc to snap them shut. A short tap never arms and only
//  pulses. Reduce Motion snaps open and closed with no springs.
//  The arm timer, open spring, angle layout, nearest-tab hit test and the select/cancel/seat
//  events all live in HoldToFanCore.

#if canImport(SwiftUI)
import SwiftUI
import HoldToFanCore

/// One tab on the fan: a system-image name and a short label.
public struct FanItem: Identifiable, Equatable, Sendable {
    public var id: String { icon + "|" + label }
    public var icon: String
    public var label: String
    public init(icon: String, label: String) {
        self.icon = icon
        self.label = label
    }
}

/// A floating action button that fans tabs out on a press-and-hold.
///
/// ```swift
/// HoldToFanDock()                                    // four demo tabs
/// HoldToFanDock(items: [
///     FanItem(icon: "house.fill", label: "Home"),
///     FanItem(icon: "safari", label: "Explore"),
///     FanItem(icon: "bell", label: "Alerts"),
///     FanItem(icon: "person", label: "You"),
/// ]) { index in print("picked", index) }
/// ```
public struct HoldToFanDock: View {
    public static let demoItems: [FanItem] = [
        FanItem(icon: "house.fill", label: "Home"),
        FanItem(icon: "safari.fill", label: "Explore"),
        FanItem(icon: "bell.fill", label: "Alerts"),
        FanItem(icon: "person.fill", label: "You"),
    ]

    private let items: [FanItem]
    private let onSelect: (Int) -> Void
    private let tint: Color

    @State private var model: HoldToFanModel
    @State private var lastDate: Date? = nil
    @State private var hSelection = 0
    @State private var hArmed = 0
    @State private var hPulse = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {
        self.init(items: Self.demoItems, tint: Color(red: 0.35, green: 0.45, blue: 1.0), onSelect: { _ in })
    }

    public init(items: [FanItem], tint: Color = Color(red: 0.35, green: 0.45, blue: 1.0), onSelect: @escaping (Int) -> Void) {
        let n = HoldToFanLayout.clampedCount(items.isEmpty ? HoldToFanModel.defaultTabs : items.count)
        self.items = Array(items.prefix(n))
        self.tint = tint
        self.onSelect = onSelect
        _model = State(initialValue: HoldToFanModel(count: n))
    }

    private var size: CGSize { CGSize(width: HoldToFanLayout.width, height: HoldToFanLayout.height) }

    public var body: some View {
        TimelineView(.animation(paused: model.phase == .idle && model.open == 0)) { timeline in
            ZStack(alignment: .topLeading) {
                // Dim the world a little while the fan is out.
                if model.isExpanded {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.black.opacity(0.18 * model.open))
                        .allowsHitTesting(false)
                }
                Canvas { ctx, _ in
                    drawArcGuide(&ctx)
                }
                .allowsHitTesting(false)
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    tabView(i, item)
                }
                fabView
            }
            .frame(width: size.width, height: size.height)
            .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .gesture(dragGesture)
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: hArmed)
        .sensoryFeedback(.selection, trigger: hSelection)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.4), trigger: hPulse)
        .onAppear { model.setReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Action menu")
        .accessibilityHint("Press and hold to open tabs")
    }

    // MARK: pieces

    private var fabView: some View {
        let c = HoldToFanLayout.fab
        let r = HoldToFanLayout.fabRadius
        return ZStack {
            Circle()
                .fill(tint.gradient)
                .shadow(color: tint.opacity(0.45), radius: 12, y: 6)
            Image(systemName: model.isExpanded ? "xmark" : "plus")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(model.isExpanded ? 90 * model.open : 0))
            // Arm ring: a light stroke that fills while holding.
            Circle()
                .trim(from: 0, to: model.armProgress)
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3)
                .opacity(model.phase == .arming ? 1 : 0)
        }
        .frame(width: r * 2, height: r * 2)
        .scaleEffect(model.phase == .arming ? 1 + 0.04 * model.armProgress : (model.isExpanded ? 0.92 : 1))
        .position(x: c.x, y: c.y)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(model.isExpanded ? "Close" : "Open menu")
    }

    private func tabView(_ i: Int, _ item: FanItem) -> some View {
        let p = model.tabPosition(i)
        let s = model.tabScale(i)
        let on = model.highlighted == i
        let progress = model.tabProgress(i)
        return HStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.system(size: 15, weight: .semibold))
            if progress > 0.55 {
                Text(item.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .opacity(Double((progress - 0.55) / 0.45))
            }
        }
        .foregroundStyle(on ? .white : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(on ? tint : Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.18 * progress), radius: 10, y: 4)
        )
        .scaleEffect(s)
        .opacity(Double(min(1, progress * 1.4)))
        .position(x: p.x, y: p.y)
        .allowsHitTesting(false)
        .accessibilityHidden(progress < 0.5)
        .accessibilityLabel(item.label)
    }

    private func drawArcGuide(_ ctx: inout GraphicsContext) {
        guard model.isExpanded, model.open > 0.05 else { return }
        var path = Path()
        let r = HoldToFanLayout.arcRadius
        let start = Angle(radians: HoldToFanLayout.startAngle)
        let end = Angle(radians: HoldToFanLayout.startAngle - HoldToFanLayout.arcSpan)
        path.addArc(center: CGPoint(x: HoldToFanLayout.fab.x, y: HoldToFanLayout.fab.y),
                    radius: r, startAngle: start, endAngle: end, clockwise: true)
        ctx.stroke(path, with: .color(.white.opacity(0.12 * model.open)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 6]))
    }

    // MARK: input

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { g in
                if model.phase == .idle || model.phase == .closing {
                    // Only start a press if the touch began on the FAB.
                    let d = hypot(g.startLocation.x - HoldToFanLayout.fab.x, g.startLocation.y - HoldToFanLayout.fab.y)
                    if d <= HoldToFanLayout.fabRadius + 8 {
                        send(model.pressBegan(at: Vec2(g.startLocation.x, g.startLocation.y)))
                    }
                }
                if model.isHolding {
                    model.pressMoved(to: Vec2(g.location.x, g.location.y))
                }
            }
            .onEnded { _ in send(model.pressEnded()) }
    }

    private func send(_ events: [HoldToFanEvent]) {
        for e in events {
            switch e {
            case .armed: hArmed &+= 1
            case .selected(let i):
                hSelection &+= 1
                onSelect(i)
            case .pulsed: hPulse &+= 1
            default: break
            }
        }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        send(model.step(now.timeIntervalSince(last)))
    }
}

/// A short phone-style page with the dock sitting over a list, so the fan has room to open.
public struct HoldToFanDockDemo: View {
    @State private var picked: String = "Hold the + button"
    public init() {}
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.14), Color(red: 0.12, green: 0.10, blue: 0.22)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("Today").font(.largeTitle.bold()).foregroundStyle(.white)
                Text(picked).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(height: 72)
                        .overlay(alignment: .leading) {
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.2)).frame(width: 120, height: 8)
                                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.12)).frame(width: 180, height: 8)
                            }
                            .padding()
                        }
                        .opacity(1 - Double(i) * 0.08)
                }
                Spacer()
            }
            .padding()
            HoldToFanDock { i in
                picked = HoldToFanDock.demoItems[i].label
            }
            .frame(width: HoldToFanLayout.width, height: HoldToFanLayout.height)
            .offset(x: 20, y: 40)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview { HoldToFanDockDemo() }
#endif
