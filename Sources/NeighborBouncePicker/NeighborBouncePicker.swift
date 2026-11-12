//
//  NeighborBouncePicker.swift
//  NeighborBouncePicker
//
//  A segmented control of five to seven ticks. Choosing one sends its neighbours up and out
//  in a spring wave: later and smaller the further they sit, with a light haptic as they land.
//  A second choice keeps the springs where they are and aims them again, so nothing pops.
//  Reduce Motion moves the pill and leaves the ticks seated.
//  The stagger, the kick and the landing gate live in NeighborBounceCore.

#if canImport(SwiftUI)
import SwiftUI
@_exported import NeighborBounceCore

/// A segmented control whose neighbours hop when the selection changes.
///
/// ```swift
/// @State private var choice = 2
/// NeighborBouncePicker(selection: $choice)                 // Ink … Tide
/// NeighborBouncePicker(selection: $choice, ticks: mine)    // 5…7; extras dropped, short lists padded
/// ```
public struct NeighborBouncePicker: View {
    @Binding private var selection: Int
    private let ticks: [NeighborTick]

    @State private var model: NeighborBounceModel
    @State private var lastDate: Date? = nil
    @State private var landPulse = 0
    @State private var selectPulse = 0
    @State private var changedDuringDrag = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(selection: Binding<Int>) {
        self.init(selection: selection, ticks: NeighborTick.demo)
    }

    public init(selection: Binding<Int>, ticks: [NeighborTick]) {
        let fitted = NeighborTick.fitted(ticks)
        self.ticks = fitted
        self._selection = selection
        let index = min(max(selection.wrappedValue, 0), fitted.count - 1)
        _model = State(initialValue: NeighborBounceModel(count: fitted.count, selection: index))
    }

    public var body: some View {
        TimelineView(.animation(paused: model.isResting && model.pendingCount == 0)) { timeline in
            ZStack {
                track
                indicator
                ForEach(Array(ticks.enumerated()), id: \.element.id) { index, tick in
                    tickView(index, tick)
                }
            }
            .frame(width: NeighborBounceLayout.canvasWidth, height: NeighborBounceLayout.canvasHeight)
            .contentShape(Rectangle())
            .gesture(drag)
            .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
        .frame(width: NeighborBounceLayout.canvasWidth, height: NeighborBounceLayout.canvasHeight)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: landPulse)
        .sensoryFeedback(.selection, trigger: selectPulse)
        .onAppear {
            model.setReduceMotion(reduceMotion)
            if selection != model.selection { selection = model.selection }
        }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .onChange(of: selection) { _, newValue in
            guard newValue != model.selection else { return }
            send(model.select(newValue))
            if selection != model.selection { selection = model.selection }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Neighbor bounce picker")
        .accessibilityValue(model.spokenSelection(titles: ticks.map(\.title)))
    }

    // MARK: drawing

    private var track: some View {
        RoundedRectangle(cornerRadius: NeighborBounceLayout.trackHeight / 2, style: .continuous)
            .fill(Color(red: NeighborBouncePalette.trackR, green: NeighborBouncePalette.trackG, blue: NeighborBouncePalette.trackB))
            .frame(width: NeighborBounceLayout.trackWidth, height: NeighborBounceLayout.trackHeight)
            .position(x: NeighborBounceLayout.canvasWidth / 2, y: NeighborBounceLayout.restY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var indicator: some View {
        let tick = ticks[model.selection]
        return RoundedRectangle(cornerRadius: NeighborBounceLayout.indicatorHeight / 2, style: .continuous)
            .fill(Color(red: tick.red, green: tick.green, blue: tick.blue))
            .frame(width: NeighborBounceLayout.indicatorWidth, height: NeighborBounceLayout.indicatorHeight)
            .position(x: model.indicatorX, y: NeighborBounceLayout.restY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func tickView(_ index: Int, _ tick: NeighborTick) -> some View {
        let pose = model.pose(index)
        let on = model.selection == index
        let ink = Color(red: NeighborBouncePalette.inkR, green: NeighborBouncePalette.inkG, blue: NeighborBouncePalette.inkB)
        let swatch = Color(red: tick.red, green: tick.green, blue: tick.blue)
        let shadow = min(1, pose.lift / 48)
        return ZStack {
            Circle()
                .fill(on ? swatch : Color(red: NeighborBouncePalette.tickR, green: NeighborBouncePalette.tickG, blue: NeighborBouncePalette.tickB))
            Circle()
                .strokeBorder(on ? Color.white.opacity(0.7) : swatch.opacity(0.85), lineWidth: on ? 1.5 : 2)
            VStack(spacing: 2) {
                Circle()
                    .fill(on ? Color.white : swatch)
                    .frame(width: 6, height: 6)
                Text(tick.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(on ? Color.white : ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: NeighborBounceLayout.tickDiameter, height: NeighborBounceLayout.tickDiameter)
        .scaleEffect(x: pose.scaleX, y: pose.scaleY)
        .shadow(color: .black.opacity(0.10 + 0.22 * shadow), radius: 5 + pose.lift * 0.12, y: 3 + pose.lift * 0.04)
        .position(x: pose.center.x, y: pose.center.y)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tick.title)
        .accessibilityValue(on ? "Selected" : "Not selected")
        .accessibilityHint("Bounces the neighboring ticks")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityAction { choose(index, nudge: true) }
    }

    // MARK: input

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let index = NeighborBounceLayout.index(atX: value.location.x, count: model.count)
                guard index != model.selection else { return }
                changedDuringDrag = true
                choose(index, nudge: false)
            }
            .onEnded { value in
                let index = NeighborBounceLayout.index(atX: value.location.x, count: model.count)
                // A press that never crossed into another tick still nudges the one under the finger.
                if !changedDuringDrag {
                    choose(index, nudge: true)
                }
                changedDuringDrag = false
            }
    }

    private func choose(_ index: Int, nudge: Bool) {
        if !nudge && index == model.selection { return }
        send(model.select(index))
        if selection != model.selection { selection = model.selection }
    }

    private func send(_ events: [NeighborBounceEvent]) {
        for event in events {
            switch event {
            case .landed:
                landPulse &+= 1
            case .selected, .nudged:
                if model.reduceMotion { selectPulse &+= 1 }
                AccessibilityNotification.Announcement(model.spokenSelection(titles: ticks.map(\.title))).post()
            case .launched, .settled:
                break
            }
        }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0, dt < 0.25 else { return }
        send(model.step(dt))
    }
}

/// A page that binds the picker to a word set in the selected colour.
public struct NeighborBouncePickerDemo: View {
    @State private var selection = 2
    private let ticks = NeighborTick.demo

    public init() {}

    public var body: some View {
        let index = min(max(selection, 0), ticks.count - 1)
        let tick = ticks[index]
        ZStack {
            Color(red: NeighborBouncePalette.paperR, green: NeighborBouncePalette.paperG, blue: NeighborBouncePalette.paperB)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Text("SEGMENTED")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(Color(red: NeighborBouncePalette.inkR, green: NeighborBouncePalette.inkG, blue: NeighborBouncePalette.inkB).opacity(0.55))
                Text(tick.title)
                    .font(.system(size: 64, weight: .bold, design: .serif))
                    .foregroundStyle(Color(red: tick.red, green: tick.green, blue: tick.blue))
                    .accessibilityAddTraits(.isHeader)
                Text("Tap a tick. Its neighbours spring up and outward.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(red: NeighborBouncePalette.inkR, green: NeighborBouncePalette.inkG, blue: NeighborBouncePalette.inkB).opacity(0.7))
                    .multilineTextAlignment(.center)
                NeighborBouncePicker(selection: $selection, ticks: ticks)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
        }
    }
}

#Preview { NeighborBouncePickerDemo() }
#endif
