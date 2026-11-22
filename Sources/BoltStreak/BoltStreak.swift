//
//  BoltStreak.swift
//  BoltStreak
//
//  A gold weekly bolt over seven zinc day bolts, Monday through Sunday.
//  A completed day burns along the zigzag: trim on a bright stroke, a white head
//  riding the centreline, and a blurred plusLighter bloom. Tapping today ignites
//  that bolt and moves the weekly fill. Reduce Motion snaps the fill, parks the
//  head, and holds the glow still. The path, the clock and the week live in BoltStreakCore.

#if canImport(SwiftUI)
import SwiftUI
@_exported import BoltStreakCore

/// A weekly streak of bevelled zinc bolts.
///
/// ```swift
/// BoltStreak(completedDays: $days)
/// BoltStreak(completedDays: $days, today: .thursday)
/// ```
///
/// The control fills its parent. Tapping today's bolt marks it and lights the tube.
public struct BoltStreak: View {
    @Binding private var completedDays: Set<Weekday>
    private let today: Weekday
    @State private var model: BoltStreakModel
    @State private var lastDate: Date?
    @State private var hapticTick = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(completedDays: Binding<Set<Weekday>>, today: Weekday = .current) {
        _completedDays = completedDays
        self.today = today
        _model = State(initialValue: BoltStreakModel(completed: completedDays.wrappedValue, today: today))
    }

    public var body: some View {
        TimelineView(.animation(paused: !model.needsClock)) { timeline in
            GeometryReader { geo in
                let scale = fitScale(in: geo.size)
                let originX = (geo.size.width - BoltStreakTuning.sceneWidth * scale) / 2
                let originY = (geo.size.height - BoltStreakTuning.sceneHeight * scale) / 2
                ZStack(alignment: .topLeading) {
                    rgb(BoltStreakTuning.backgroundBottom)
                    scene
                        .frame(width: BoltStreakTuning.sceneWidth, height: BoltStreakTuning.sceneHeight)
                        .scaleEffect(scale, anchor: .topLeading)
                        .offset(x: originX, y: originY)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(tap(scale: scale, originX: originX, originY: originY))
                .onChange(of: timeline.date) { _, now in advance(to: now) }
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.72), trigger: hapticTick)
        .onAppear {
            model.setReduceMotion(reduceMotion)
            if completedDays != model.completed {
                note(model.setCompleted(completedDays))
            }
        }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .onChange(of: completedDays) { _, newValue in
            guard newValue != model.completed else { return }
            note(model.setCompleted(newValue))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.accessibilityValue)
        .accessibilityHint(model.canMarkToday ? BoltStreakTuning.accessibilityHint : "Today is already lit.")
        .modifier(BoltStreakAccess(canMark: model.canMarkToday, perform: { note(model.igniteToday()) }))
    }

    private var scene: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                drawGround(&context)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            weeklyBolt
            readout
            dayRow
        }
        .frame(width: BoltStreakTuning.sceneWidth, height: BoltStreakTuning.sceneHeight, alignment: .topLeading)
    }

    private var weeklyBolt: some View {
        let rect = BoltStreakTuning.weeklyRect
        return BoltMark(
            progress: model.weeklyProgress,
            glow: model.weeklyGlow,
            showsHead: model.weeklyHead != nil,
            stroke: BoltStreakTuning.weeklyStroke,
            headDiameter: BoltStreakTuning.weeklyHead,
            bevel: BoltStreakTuning.weeklyBevel
        )
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .accessibilityHidden(true)
    }

    private var readout: some View {
        ZStack {
            Text(BoltStreakTuning.wordmark)
                .font(.system(size: 34, weight: .medium, design: .serif))
                .tracking(8)
                .foregroundStyle(rgb(BoltStreakTuning.wordmarkColor))
                .position(x: BoltStreakTuning.sceneWidth / 2, y: BoltStreakTuning.wordmarkY)
            Text(BoltStreakTuning.caption)
                .font(.system(size: 12, weight: .semibold))
                .tracking(3.4)
                .foregroundStyle(rgb(BoltStreakTuning.captionColor))
                .position(x: BoltStreakTuning.sceneWidth / 2, y: BoltStreakTuning.captionY)
            Text("\(model.completed.count)")
                .font(.system(size: 72, weight: .medium, design: .serif))
                .foregroundStyle(rgb(model.completed.isEmpty ? BoltStreakTuning.zinc : BoltStreakTuning.gold))
                .position(x: BoltStreakTuning.sceneWidth / 2, y: BoltStreakTuning.readoutY)
            Text(BoltStreakTuning.ofSeven)
                .font(.system(size: 13, weight: .semibold))
                .tracking(3)
                .foregroundStyle(rgb(BoltStreakTuning.captionColor))
                .position(x: BoltStreakTuning.sceneWidth / 2, y: BoltStreakTuning.ofSevenY)
        }
        .accessibilityHidden(true)
    }

    private var dayRow: some View {
        let plateWidth = BoltStreakTuning.dayRowWidth + 36
        let plateHeight = BoltStreakTuning.dayHeight + 64
        let rowCenterY = BoltStreakTuning.dayOriginY + BoltStreakTuning.dayHeight / 2 + 10
        let rowOriginX = BoltStreakTuning.sceneWidth / 2 - plateWidth / 2
        let rowOriginY = rowCenterY - plateHeight / 2
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(rgb(BoltStreakTuning.plate).opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(rgb(BoltStreakTuning.plate).opacity(0.08), lineWidth: 1)
                )
            ForEach(Weekday.allCases, id: \.rawValue) { day in
                let rect = BoltStreakTuning.dayRect(for: day)
                BoltMark(
                    progress: model.dayProgress(day),
                    glow: model.glow(for: day),
                    showsHead: model.head(for: day) != nil,
                    stroke: BoltStreakTuning.dayStroke,
                    headDiameter: BoltStreakTuning.dayHead,
                    bevel: BoltStreakTuning.dayBevel
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX - rowOriginX, y: rect.midY - rowOriginY)
                Text(day.label)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(rgb(model.completed.contains(day) ? BoltStreakTuning.labelLit : BoltStreakTuning.labelDim))
                    .position(x: rect.midX - rowOriginX, y: BoltStreakTuning.labelY() - rowOriginY)
            }
        }
        .frame(width: plateWidth, height: plateHeight, alignment: .topLeading)
        .rotation3DEffect(
            .degrees(BoltStreakTuning.tiltDegrees),
            axis: (x: 1, y: 0, z: 0),
            anchor: .center,
            perspective: BoltStreakTuning.tiltPerspective
        )
        .position(x: BoltStreakTuning.sceneWidth / 2, y: rowCenterY)
        .accessibilityHidden(true)
    }

    private func fitScale(in size: CGSize) -> CGFloat {
        guard size.width > 1, size.height > 1 else { return 1 }
        return min(size.width / BoltStreakTuning.sceneWidth, size.height / BoltStreakTuning.sceneHeight)
    }

    private func tap(scale: CGFloat, originX: CGFloat, originY: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                guard scale > 0 else { return }
                let x = (value.location.x - originX) / scale
                let y = (value.location.y - originY) / scale
                let rect = BoltStreakTuning.dayRect(for: today)
                guard rect.contains(Vec2(Double(x), Double(y)), slop: BoltStreakTuning.hitSlop) else { return }
                note(model.igniteToday())
            }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        _ = model.step(now.timeIntervalSince(last))
    }

    private func note(_ events: [BoltStreakEvent]) {
        let ticks = events.reduce(into: 0) { count, event in
            if case .tick = event { count += 1 }
        }
        if ticks > 0 { hapticTick += ticks }
        if completedDays != model.completed { completedDays = model.completed }
    }

    private func drawGround(_ ctx: inout GraphicsContext) {
        let width = BoltStreakTuning.sceneWidth
        let height = BoltStreakTuning.sceneHeight
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: height)),
            with: .linearGradient(
                Gradient(colors: [rgb(BoltStreakTuning.backgroundTop), rgb(BoltStreakTuning.backgroundBottom)]),
                startPoint: CGPoint(x: width / 2, y: 0),
                endPoint: CGPoint(x: width / 2, y: height)
            )
        )
        let spill = model.weeklyProgress
        guard spill > 0 else { return }
        let rect = BoltStreakTuning.weeklyRect
        var glow = Path()
        glow.addEllipse(in: CGRect(
            x: rect.midX - 90,
            y: rect.y + rect.height - 24,
            width: 180,
            height: 70
        ))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 18))
            layer.fill(glow, with: .color(rgb(BoltStreakTuning.spill).opacity(0.18 + 0.55 * spill)))
        }
    }

    private func rgb(_ color: BoltRGB) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
    }
}

/// One bevelled tube: zinc edges, a trimmed gold burn, a blurred bloom, a white head, and a reflection.
private struct BoltMark: View {
    var progress: Double
    var glow: Double
    var showsHead: Bool
    var stroke: Double
    var headDiameter: Double
    var bevel: Double

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        GeometryReader { geo in
            let rect = BoltRect(x: 0, y: 0, width: geo.size.width, height: geo.size.height)
            let head = BoltPath.sample(progress: clamped, in: rect)
            ZStack {
                mark(progress: clamped, glow: glow, showsHead: showsHead, head: head)
                mark(progress: clamped, glow: glow * 0.65, showsHead: false, head: head)
                    .scaleEffect(x: 1, y: -0.42, anchor: .bottom)
                    .offset(y: BoltStreakTuning.reflectionGap)
                    .opacity(BoltStreakTuning.reflectionOpacity * (0.35 + 0.65 * clamped))
                    .mask(
                        LinearGradient(
                            colors: [Color.white.opacity(0.85), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
    }

    private func mark(progress: Double, glow: Double, showsHead: Bool, head: Vec2) -> some View {
        let line = stroke
        return ZStack {
            BoltShape()
                .stroke(Color(red: BoltStreakTuning.zincShadow.red, green: BoltStreakTuning.zincShadow.green, blue: BoltStreakTuning.zincShadow.blue), style: strokeStyle(line))
                .offset(x: bevel, y: bevel)
            BoltShape()
                .stroke(Color(red: BoltStreakTuning.zincHighlight.red, green: BoltStreakTuning.zincHighlight.green, blue: BoltStreakTuning.zincHighlight.blue), style: strokeStyle(line * 0.55))
                .offset(x: -bevel * 0.65, y: -bevel * 0.65)
            BoltShape()
                .stroke(Color(red: BoltStreakTuning.zinc.red, green: BoltStreakTuning.zinc.green, blue: BoltStreakTuning.zinc.blue), style: strokeStyle(line))
            BoltShape()
                .trim(from: 0, to: progress)
                .stroke(Color(red: BoltStreakTuning.gold.red, green: BoltStreakTuning.gold.green, blue: BoltStreakTuning.gold.blue), style: strokeStyle(line * 1.7))
                .blur(radius: BoltStreakTuning.glowBlur * max(glow, 0))
                .blendMode(.plusLighter)
                .opacity(glow > 0 ? 1 : 0)
            BoltShape()
                .trim(from: 0, to: progress)
                .stroke(Color(red: BoltStreakTuning.gold.red, green: BoltStreakTuning.gold.green, blue: BoltStreakTuning.gold.blue), style: strokeStyle(line))
            BoltShape()
                .trim(from: 0, to: progress)
                .stroke(Color(red: BoltStreakTuning.goldCore.red, green: BoltStreakTuning.goldCore.green, blue: BoltStreakTuning.goldCore.blue), style: strokeStyle(line * 0.42))
            if showsHead {
                Circle()
                    .fill(Color(red: BoltStreakTuning.gold.red, green: BoltStreakTuning.gold.green, blue: BoltStreakTuning.gold.blue))
                    .frame(width: headDiameter * 2.4, height: headDiameter * 2.4)
                    .blur(radius: headDiameter * 0.45)
                    .blendMode(.plusLighter)
                    .position(x: head.x, y: head.y)
                Circle()
                    .fill(Color.white)
                    .frame(width: headDiameter, height: headDiameter)
                    .position(x: head.x, y: head.y)
            }
        }
    }

    private func strokeStyle(_ width: Double) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

/// The zigzag, in the view's own rect. Trim walks this path; the head samples the same points.
private struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let bolt = BoltRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        let points = BoltPath.scenePoints(in: bolt)
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        return path
    }
}

private struct BoltStreakAccess: ViewModifier {
    var canMark: Bool
    var perform: () -> Void

    func body(content: Content) -> some View {
        if canMark {
            content.accessibilityAction(named: Text(BoltStreakTuning.markTodayAction)) { perform() }
        } else {
            content
        }
    }
}

/// Gallery page. Monday through Wednesday start lit, and Thursday is the bolt you can tap.
public struct BoltStreakDemo: View {
    @State private var days: Set<Weekday> = [.monday, .tuesday, .wednesday]

    public init() {}

    public var body: some View {
        BoltStreak(completedDays: $days, today: .thursday)
    }
}

#Preview("Bolt Streak") {
    BoltStreakDemo()
}
#endif
