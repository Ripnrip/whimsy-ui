//
//  RubberBandCardHand.swift
//  RubberBandCardHand
//
//  Five generated cards fanned along the bottom. Slide a finger across them and the nearest
//  one lifts about 20 points, with a light haptic each time the lift moves to a new card.
//  Drag that card upward and it follows through a rubber band (offset × 0.55 / (1 + |offset| / 300)).
//  Past the line, or on a fast flick, it springs to the centre and turns over in 3D to its detail.
//  Let go early and it springs back into the fan. Drag the open card down, tap outside, or
//  press Done to put it away. Reduce Motion skips the flight and the 3D turn.
//  Geometry, the band, the gesture and the phase machine live in RubberBandCore.

#if canImport(SwiftUI)
import SwiftUI
import RubberBandCore

/// Words for one slot. The picture stays the generated design for that slot.
public struct RubberBandCard: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var kicker: String
    public var detail: String

    public init(title: String, kicker: String, detail: String) {
        self.title = title
        self.kicker = kicker
        self.detail = detail
        self.id = title + "|" + kicker
    }
}

/// A hand of five cards along the bottom of the screen.
///
/// ```swift
/// RubberBandCardHand()
/// RubberBandCardHand(cards: [
///     RubberBandCard(title: "Lumen", kicker: "FIELD NOTES", detail: "After the lamps go out."),
///     RubberBandCard(title: "Terrace", kicker: "AFTERNOON", detail: "Steps that keep the heat."),
///     RubberBandCard(title: "Citrus", kicker: "MARKET", detail: "Three fruits and a leaf."),
///     RubberBandCard(title: "Night Train", kicker: "PLATFORM 4", detail: "Windows with the lamp on."),
///     RubberBandCard(title: "Botanic", kicker: "GLASSHOUSE", detail: "A plant remembered by a stencil."),
/// ]) { card in print(card.title) }
/// ```
///
/// The hand is always five cards. A shorter list is filled from the built-in designs; extras are dropped.
/// The view is 390 × 700 points and scales down to fit, pinned to the bottom.
public struct RubberBandCardHand: View {
    public static var samples: [RubberBandCard] {
        RubberBandCatalog.cards.map {
            RubberBandCard(title: $0.title, kicker: $0.kicker, detail: $0.detail)
        }
    }

    private let cards: [(copy: RubberBandCard, spec: RubberBandCardSpec)]
    private let onOpen: (RubberBandCard) -> Void

    @State private var model = RubberBandModel()
    @State private var touching = false
    @State private var wasOpen = false
    @State private var lastDate: Date?
    @State private var hLift = 0
    @State private var hArm = 0
    @State private var hCommit = 0
    @State private var hRestored = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(onOpen: @escaping (RubberBandCard) -> Void = { _ in }) {
        self.init(cards: Self.samples, onOpen: onOpen)
    }

    public init(cards: [RubberBandCard], onOpen: @escaping (RubberBandCard) -> Void = { _ in }) {
        let provided = cards.isEmpty ? Self.samples : cards
        self.cards = (0..<RubberBandLayout.count).map { i in
            let spec = RubberBandCatalog.spec(i)
            let copy = i < provided.count
                ? provided[i]
                : RubberBandCard(title: spec.title, kicker: spec.kicker, detail: spec.detail)
            return (copy, spec)
        }
        self.onOpen = onOpen
    }

    public var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / RubberBandLayout.width, geo.size.height / RubberBandLayout.height)
            scene
                .frame(width: RubberBandLayout.width, height: RubberBandLayout.height)
                .scaleEffect(max(scale, 0.01), anchor: .bottom)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(backdrop.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sensoryFeedback(.selection, trigger: hLift)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.4), trigger: hArm)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: hCommit)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: hRestored)
        .onAppear { send(model.setReduceMotion(reduceMotion)) }
        .onChange(of: reduceMotion) { _, on in send(model.setReduceMotion(on)) }
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.08),
                Color(red: 0.11, green: 0.09, blue: 0.14),
                Color(red: 0.16, green: 0.11, blue: 0.12),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var scene: some View {
        TimelineView(.animation(paused: !model.needsDisplayLink && !touching)) { timeline in
            ZStack(alignment: .top) {
                if model.scrim > 0.001 {
                    Color.black.opacity(model.scrim)
                        .allowsHitTesting(false)
                }
                table
                ForEach(model.drawOrder, id: \.self) { i in
                    card(i)
                }
                hint
            }
            .frame(width: RubberBandLayout.width, height: RubberBandLayout.height)
            .contentShape(Rectangle())
            .gesture(drag)
            .onChange(of: timeline.date) { _, now in advance(to: now) }
            .accessibilityElement(children: .contain)
        }
    }

    private var table: some View {
        Ellipse()
            .fill(Color.black.opacity(0.35))
            .frame(width: 320, height: 36)
            .blur(radius: 8)
            .position(x: RubberBandLayout.width / 2, y: RubberBandLayout.height - 28)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var hint: some View {
        Text(hintText)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .padding(.top, 28)
            .opacity(model.phase == .presented || model.phase == .dismissing ? 0 : 1)
            .accessibilityHidden(true)
    }

    private var hintText: String {
        switch model.phase {
        case .dragging: return model.isArmed ? "Let go to open" : "Drag up to open"
        case .presenting, .returning: return ""
        case .browsing: return "Drag a card upward"
        default: return "Slide across the hand"
        }
    }

    private func card(_ index: Int) -> some View {
        let pose = model.pose(index)
        let item = cards[index]
        let showingDetail = pose.flip >= 0.5
        return ZStack {
            if reduceMotion {
                face(item).opacity(showingDetail ? 0 : 1)
                detail(item).opacity(showingDetail ? 1 : 0)
            } else {
                face(item).opacity(showingDetail ? 0 : 1)
                detail(item)
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                    .opacity(showingDetail ? 1 : 0)
            }
        }
        .frame(width: RubberBandLayout.cardWidth, height: RubberBandLayout.cardHeight)
        .rotation3DEffect(
            .degrees(reduceMotion ? 0 : pose.flip * 180),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
        )
        .overlay {
            RoundedRectangle(cornerRadius: RubberBandLayout.cornerRadius, style: .continuous)
                .fill(Color.black.opacity(1 - pose.opacity))
                .allowsHitTesting(false)
        }
        .scaleEffect(pose.scale)
        .rotationEffect(.radians(pose.rotation))
        .position(x: pose.center.x, y: pose.center.y)
        .shadow(color: .black.opacity(0.22 + 0.25 * min(pose.lift / 90, 1)), radius: 10 + pose.lift * 0.12, y: 10)
        .accessibilityElement(children: showingDetail ? .contain : .ignore)
        .accessibilityLabel(showingDetail ? item.copy.title : "\(item.copy.title), card \(index + 1) of 5")
        .accessibilityValue(showingDetail ? item.copy.detail : (model.focusIndex == index ? "Lifted" : "In the hand"))
        .accessibilityHint(showingDetail ? "Drag down or use Done to put it back." : "Drag up to open. Or use the Open action.")
        .accessibilityAddTraits(showingDetail ? .isModal : .isButton)
        .accessibilityAction(named: "Open") { send(model.activate(index)) }
        .accessibilityAction(.escape) { send(model.dismiss()) }
        .accessibilityHidden(model.openness > 0.5 && model.activeIndex != index)
    }

    private func face(_ item: (copy: RubberBandCard, spec: RubberBandCardSpec)) -> some View {
        let spec = item.spec
        return ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: RubberBandLayout.cornerRadius, style: .continuous)
                .fill(spec.paper.color)
            marks(spec.marks)
                .padding(.bottom, 46)
            LinearGradient(colors: [spec.ink.color.opacity(0.0), spec.ink.color.opacity(0.05)], startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: RubberBandLayout.cornerRadius, style: .continuous))
                .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.copy.kicker)
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(spec.ink.color.opacity(0.62))
                Text(item.copy.title)
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(spec.ink.color)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: RubberBandLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RubberBandLayout.cornerRadius, style: .continuous)
                .stroke(spec.ink.color.opacity(0.18), lineWidth: 1)
        )
    }

    private func detail(_ item: (copy: RubberBandCard, spec: RubberBandCardSpec)) -> some View {
        let spec = item.spec
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: RubberBandLayout.cornerRadius, style: .continuous)
                .fill(spec.paper.color)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(item.copy.kicker)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(spec.ink.color.opacity(0.62))
                        .padding(.top, 6)
                    Spacer(minLength: 0)
                    Button { send(model.dismiss()) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(spec.ink.color)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(spec.ink.color.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Done")
                    .highPriorityGesture(TapGesture().onEnded { send(model.dismiss()) })
                }
                Text(item.copy.title)
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(spec.ink.color)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.copy.detail)
                    .font(.system(size: 12, weight: .regular, design: .serif))
                    .foregroundStyle(spec.ink.color.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: RubberBandLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: RubberBandLayout.cornerRadius, style: .continuous)
                .stroke(spec.ink.color.opacity(0.18), lineWidth: 1)
        )
    }

    private func marks(_ marks: [RubberBandMark]) -> some View {
        Canvas { ctx, size in
            for mark in marks {
                draw(mark, in: &ctx, size: size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ mark: RubberBandMark, in ctx: inout GraphicsContext, size: CGSize) {
        switch mark {
        case let .ellipse(cx, cy, rx, ry, color, alpha):
            let rect = CGRect(
                x: (cx - rx) * size.width,
                y: (cy - ry) * size.height,
                width: 2 * rx * size.width,
                height: 2 * ry * size.height
            )
            ctx.fill(Path(ellipseIn: rect), with: .color(color.color.opacity(alpha)))
        case let .roundRect(cx, cy, width, height, corner, color, alpha):
            let rect = CGRect(
                x: (cx - width / 2) * size.width,
                y: (cy - height / 2) * size.height,
                width: width * size.width,
                height: height * size.height
            )
            let radius = corner * min(size.width, size.height)
            ctx.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(color.color.opacity(alpha)))
        case let .capsule(cx, cy, width, height, rotation, color, alpha):
            let rect = CGRect(
                x: -width * size.width / 2,
                y: -height * size.height / 2,
                width: width * size.width,
                height: height * size.height
            )
            ctx.drawLayer { layer in
                layer.translateBy(x: cx * size.width, y: cy * size.height)
                layer.rotate(by: .radians(rotation))
                layer.fill(
                    Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) / 2),
                    with: .color(color.color.opacity(alpha))
                )
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = Vec2(value.location.x, value.location.y)
                let t = value.time.timeIntervalSinceReferenceDate
                if !touching {
                    touching = true
                    send(model.pointerDown(at: point, at: t))
                } else {
                    send(model.pointerMoved(to: point, at: t))
                }
            }
            .onEnded { value in
                let point = Vec2(value.location.x, value.location.y)
                let t = value.time.timeIntervalSinceReferenceDate
                touching = false
                send(model.pointerUp(at: point, at: t))
            }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0 else { return }
        send(model.step(dt))
    }

    private func send(_ events: [RubberBandEvent]) {
        for event in events {
            switch event {
            case .lifted:
                hLift &+= 1
            case .armed:
                hArm &+= 1
            case .committed:
                hCommit &+= 1
            case .presented(let index):
                wasOpen = true
                onOpen(cards[index].copy)
                AccessibilityNotification.Announcement("\(cards[index].copy.title), open").post()
            case .restored:
                hRestored &+= 1
                if wasOpen {
                    wasOpen = false
                    AccessibilityNotification.Announcement("Back in the hand").post()
                }
            case .grabbed, .dismissed:
                break
            }
        }
    }
}

private extension RubberBandRGB {
    var color: Color { Color(red: r, green: g, blue: b) }
}

#Preview("Rubber Band Card Hand") {
    RubberBandCardHand()
}
#endif
