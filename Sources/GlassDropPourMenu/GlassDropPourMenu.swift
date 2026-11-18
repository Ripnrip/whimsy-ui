//  GlassDropPourMenu.swift
//  GlassDropPourMenu
//
//  A glass drop you press and hold. Four rows pour out of it, one after another, joined to the
//  drop by metaball necks (a Canvas blur, then an alpha threshold). They settle as crisp glass
//  pills. Tap outside and they suck back up. Delete lands with a red tint and a small wobble.
//  The state machine, stagger, springs, neck geometry and wobble live in GlassPourCore.
//  Reduce Motion crossfades the rows in place: no pour, no necks, no wobble.
//  There is no Metal shader. The goo is the same Canvas filter PourOpenMenu uses.

#if canImport(SwiftUI)
import SwiftUI
import GlassPourCore

/// A long-press glass drop that pours open into a menu.
///
/// ```swift
/// GlassDropPourMenu { item in
///     if item.destructive { deleteNote() }
/// }
/// GlassDropPourMenu(items: [
///     GlassDropItem(title: "Share", symbol: "square.and.arrow.up"),
///     GlassDropItem(title: "Delete", symbol: "trash", destructive: true),
/// ]) { item in
///     print(item.title)
/// }
/// ```
public struct GlassDropPourMenu: View {
    private let onSelect: (GlassDropItem) -> Void
    @State private var model: GlassPourModel
    @State private var lastDate: Date?
    @State private var holding = false
    @State private var haptics = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(items: [GlassDropItem] = GlassDropItem.defaults, onSelect: @escaping (GlassDropItem) -> Void = { _ in }) {
        self.onSelect = onSelect
        _model = State(initialValue: GlassPourModel(items: items))
    }

    public var body: some View {
        GeometryReader { geo in
            let origin = menuOrigin(in: geo.size)
            let height = GlassPourLayout.height(count: model.count)
            ZStack(alignment: .topLeading) {
                if model.isExpanded {
                    Color.black.opacity(0.22)
                        .ignoresSafeArea()
                        .onTapGesture { send(model.pressOutside()) }
                        .accessibilityHidden(true)
                }
                menu(origin: origin, height: height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { model.setReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.75), trigger: haptics)
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) {
            if model.isExpanded { send(model.pressOutside()) }
        }
    }

    private func menuOrigin(in size: CGSize) -> CGPoint {
        let x = (size.width - GlassPourLayout.width) / 2
        let y = min(max(size.height * 0.36, 160), 360)
        return CGPoint(x: x, y: y)
    }

    private func menu(origin: CGPoint, height: Double) -> some View {
        TimelineView(.animation(paused: !model.animates)) { timeline in
            ZStack(alignment: .topLeading) {
                GooLayer(model: model)
                    .frame(width: GlassPourLayout.width + pad * 2, height: height + pad * 2)
                    .offset(x: -pad, y: -pad)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                ForEach(model.rows, id: \.index) { row in
                    rowButton(row)
                }
                dropButton
            }
            .frame(width: GlassPourLayout.width, height: height, alignment: .topLeading)
            .position(x: origin.x + GlassPourLayout.width / 2, y: origin.y + height / 2)
            .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
    }

    private var pad: Double { 28 }

    private var dropButton: some View {
        let diameter = GlassPourLayout.dropRadius * 2
        let highlight = GlassPourLayout.dropHighlight(scale: model.dropScale)
        return ZStack {
            if !model.usesGoo {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(Color.white.opacity(0.42))
            }
            Circle()
                .fill(RadialGradient(
                    colors: [Color.white.opacity(0.95), Color.white.opacity(0.08), Color.clear],
                    center: UnitPoint(x: 0.32, y: 0.28),
                    startRadius: 0,
                    endRadius: GlassPourLayout.dropRadius
                ))
                .opacity(model.usesGoo ? 0.85 : 1)
            Circle().stroke(Color.white.opacity(0.82), lineWidth: 1.4)
            // The highlight's centre is in menu coordinates; this circle is the drop, so place it locally.
            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: highlight.radius * 2, height: highlight.radius * 1.35)
                .offset(
                    x: highlight.center.x - GlassPourLayout.dropCenter.x,
                    y: highlight.center.y - GlassPourLayout.dropCenter.y
                )
                .blur(radius: 0.4)
                .allowsHitTesting(false)
        }
        .frame(width: diameter, height: diameter)
        .scaleEffect(model.dropScale)
        .shadow(color: .black.opacity(model.usesGoo ? 0 : 0.22), radius: 14, y: 8)
        .contentShape(Circle())
        .position(x: GlassPourLayout.dropCenter.x, y: GlassPourLayout.dropCenter.y)
        .gesture(press)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(model.dropAccessibilityLabel)
        .accessibilityHint(model.dropAccessibilityHint)
        .accessibilityValue(model.dropAccessibilityValue)
        .accessibilityAction { send(model.activateDrop()) }
    }

    private func rowButton(_ row: GlassPourRow) -> some View {
        let item = model.items[row.index]
        let width = GlassPourLayout.pillWidth * row.scale
        let height = GlassPourLayout.pillHeight * row.scale
        return Button {
            send(model.selectRow(row.index))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 22)
                Text(item.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .foregroundStyle(rowInk(item, row))
            .padding(.horizontal, 16)
            .frame(width: width, height: height)
            .background { pillChrome(row, item: item) }
            .clipShape(Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .rotationEffect(.radians(row.wobble))
        .opacity(row.opacity)
        .position(x: row.center.x, y: row.center.y)
        .allowsHitTesting(row.isInteractive)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.destructive ? "Deletes" : "Chooses \(item.title)")
        .accessibilityHidden(!row.isInteractive)
    }

    @ViewBuilder
    private func pillChrome(_ row: GlassPourRow, item: GlassDropItem) -> some View {
        if model.usesGoo {
            Capsule(style: .continuous)
                .fill(Self.deleteFill.opacity(item.destructive ? 0.55 * row.pinch : 0))
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
            Capsule(style: .continuous)
                .fill(item.destructive ? Self.deleteFill.opacity(0.92) : Color.white.opacity(0.55))
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.78), lineWidth: 1)
        }
    }

    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !holding else { return }
                holding = true
                lastDate = nil
                send(model.pressDrop())
            }
            .onEnded { _ in
                holding = false
                send(model.releaseDrop())
            }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        send(model.step(now.timeIntervalSince(last)))
    }

    private func send(_ events: [GlassPourEvent]) {
        for event in events {
            switch event {
            case .opened:
                AccessibilityNotification.Announcement(GlassPourTuning.openedAnnouncement).post()
            case .closed:
                AccessibilityNotification.Announcement(GlassPourTuning.closedAnnouncement).post()
            case .selected(let index):
                guard model.items.indices.contains(index) else { continue }
                let item = model.items[index]
                onSelect(item)
                AccessibilityNotification.Announcement(item.title).post()
            case .haptic:
                haptics += 1
            case .opening, .closing, .pulsed:
                break
            }
        }
    }

    private func rowInk(_ item: GlassDropItem, _ row: GlassPourRow) -> Color {
        guard item.destructive else { return Self.ink }
        if !model.usesGoo || row.pinch > 0.45 { return .white }
        return Self.deleteInk
    }

    static let ink = Color(red: 0.11, green: 0.10, blue: 0.14)
    static let deleteInk = Color(red: 0.55, green: 0.04, blue: 0.10)
    static let deleteFill = Color(red: 0.89, green: 0.24, blue: 0.31)
    static let milk = Color(red: 0.97, green: 0.97, blue: 0.99)
}

/// Blobs and necks. While pouring, blur then alpha-threshold so the rows stay fused to the drop.
/// At rest the pills are drawn by the buttons, crisp, and this layer is empty.
private struct GooLayer: View {
    let model: GlassPourModel

    var body: some View {
        Canvas { context, _ in
            let pad = 28.0
            context.translateBy(x: pad, y: pad)
            guard model.usesGoo else { return }
            var goo = context
            goo.addFilter(.alphaThreshold(min: GlassPourLayout.gooThreshold, color: GlassDropPourMenu.milk))
            goo.addFilter(.blur(radius: GlassPourLayout.gooBlur))
            goo.drawLayer { layer in
                fill(&layer, GlassPourLayout.dropBlob(scale: model.dropScale))
                for row in model.rows where row.isVisible {
                    fill(&layer, GlassPourLayout.pillBlob(center: row.center, scale: row.scale))
                }
                for neck in model.necks {
                    var path = Path()
                    for (index, point) in neck.polygon.enumerated() {
                        let cg = CGPoint(x: point.x, y: point.y)
                        if index == 0 { path.move(to: cg) } else { path.addLine(to: cg) }
                    }
                    path.closeSubpath()
                    layer.fill(path, with: .color(.white))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func fill(_ context: inout GraphicsContext, _ blob: GlassPourBlob) {
        let rect = CGRect(
            x: blob.center.x - blob.halfWidth, y: blob.center.y - blob.radius,
            width: blob.halfWidth * 2, height: blob.radius * 2
        )
        context.fill(Path(roundedRect: rect, cornerRadius: blob.radius, style: .continuous), with: .color(.white))
    }
}

/// The gallery page: a note under a sunset, the drop sitting on the card, and the last choice.
public struct GlassDropPourMenuDemo: View {
    @State private var status = "Long-press the drop"

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.62, blue: 0.42),
                    Color(red: 0.86, green: 0.34, blue: 0.48),
                    Color(red: 0.28, green: 0.18, blue: 0.42),
                    Color(red: 0.09, green: 0.08, blue: 0.16),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("Notes")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                note
                Spacer()
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .allowsHitTesting(false)
            GlassDropPourMenu { item in
                status = item.destructive ? "Deleted" : item.title
            }
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SUNDAY MARKET")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.8))
            Text("Peaches, cold brew, a table in the shade.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Hold the glass drop for Share, Duplicate, Rename or Delete.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Glass drop") {
    GlassDropPourMenuDemo()
}
#endif
