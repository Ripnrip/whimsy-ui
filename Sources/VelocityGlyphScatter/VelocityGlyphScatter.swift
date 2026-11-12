//
//  VelocityGlyphScatter.swift
//  VelocityGlyphScatter
//
//  A price slider from $40 to $600 in $5 steps. The formatted price is one Text per character.
//  While the thumb moves, each glyph takes a seeded vertical offset and a lean of a few degrees,
//  both scaled by the smoothed speed, and a fast drag blurs them slightly. On release every glyph
//  springs back to the baseline and overshoots it. Reduce Motion keeps the price flat: no scatter,
//  no lean, no blur. Step snapping, glyph identity, velocity smoothing and the return spring live
//  in VelocityGlyphCore.

#if canImport(SwiftUI)
import SwiftUI
import VelocityGlyphCore

/// A price control whose glyphs scatter with thumb speed.
///
/// ```swift
/// VelocityGlyphScatter(value: $price)                              // $40...$600, step $5
/// VelocityGlyphScatter(value: $price, range: 20...200, step: 5)
/// ```
///
/// VoiceOver treats the control as adjustable. The value is the formatted price (`"$180"`), and
/// swiping up or down moves one step. Reduce Motion (`accessibilityReduceMotion`) draws the price
/// on the baseline with no blur.
public struct VelocityGlyphScatter: View {
    @Binding private var value: Int
    private let title: String

    @State private var model: VelocityGlyphModel
    @State private var lastDate: Date? = nil
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Binding<Int>,
                range: ClosedRange<Int> = VelocityGlyphTuning.defaultLower...VelocityGlyphTuning.defaultUpper,
                step: Int = VelocityGlyphTuning.defaultStep,
                title: String = "Price") {
        _value = value
        self.title = title
        _model = State(initialValue: VelocityGlyphModel(value: value.wrappedValue, range: range, step: step))
    }

    public var body: some View {
        TimelineView(.animation(paused: model.phase == .idle && model.isVisuallySettled)) { timeline in
            VStack(spacing: 18) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(ink.opacity(0.45))
                glyphRow
                    .frame(height: 88)
                track
                HStack {
                    Text(PriceGlyphs.string(for: model.span.lower))
                    Spacer(minLength: 0)
                    Text(PriceGlyphs.string(for: model.span.last))
                }
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(ink.opacity(0.45))
                .frame(width: VelocityGlyphTuning.trackWidth)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
            .background(paper, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
        .sensoryFeedback(.selection, trigger: ticks)
        .onAppear {
            model.setReduceMotion(reduceMotion)
            push(model.setValue(value))
        }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .onChange(of: value) { _, new in push(model.setValue(new)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(model.formattedPrice)
        .accessibilityHint("Swipe up or down to change the price.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: push(model.adjust(by: 1))
            case .decrement: push(model.adjust(by: -1))
            @unknown default: break
            }
        }
    }

    // MARK: pieces

    private var glyphRow: some View {
        HStack(spacing: 0) {
            ForEach(model.poses) { pose in
                Text(pose.character)
                    .font(.system(size: 64, weight: .semibold, design: .serif).monospacedDigit())
                    .foregroundStyle(ink)
                    .fixedSize()
                    .offset(y: pose.offsetY)
                    .rotationEffect(.degrees(pose.leanDegrees))
                    .blur(radius: model.blurRadius)
            }
        }
        .animation(nil, value: model.value)
    }

    private var track: some View {
        let width = VelocityGlyphTuning.trackWidth
        let x = model.interactionX
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(ink.opacity(0.12))
                .frame(width: width, height: 4)
            Capsule(style: .continuous)
                .fill(accent)
                .frame(width: max(4, x), height: 4)
            Circle()
                .fill(paper)
                .overlay(Circle().stroke(accent, lineWidth: 3))
                .frame(width: 28, height: 28)
                .shadow(color: ink.opacity(0.16), radius: 5, y: 2)
                .position(x: x, y: 22)
        }
        .frame(width: width, height: 44)
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { sample in
                let x = sample.location.x
                if model.phase != .dragging {
                    push(model.beginDrag(atX: x))
                } else {
                    push(model.updateDrag(atX: x))
                }
            }
            .onEnded { _ in
                model.endDrag()
                push([])
            }
    }

    // MARK: colours

    private var ink: Color { Color(red: 0.14, green: 0.11, blue: 0.09) }
    private var accent: Color { Color(red: 0.70, green: 0.22, blue: 0.16) }
    private var paper: Color { Color(red: 0.98, green: 0.96, blue: 0.92) }

    // MARK: clock and binding

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        model.step(now.timeIntervalSince(last))
    }

    /// Writes the snapped price back to the binding and asks for one light tick per step event.
    private func push(_ events: [VelocityGlyphEvent]) {
        if model.value != value { value = model.value }
        if !events.isEmpty { ticks += events.count }
    }
}

/// A market card around ``VelocityGlyphScatter`` for the gallery.
public struct VelocityGlyphScatterDemo: View {
    @State private var price = VelocityGlyphTuning.defaultValue

    public init() {}

    public var body: some View {
        ZStack {
            Color(red: 0.93, green: 0.89, blue: 0.82).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Saturday market")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .foregroundStyle(Color(red: 0.16, green: 0.12, blue: 0.09))
                Text("Linen overshirt")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                VelocityGlyphScatter(value: $price, title: "Price")
                    .frame(maxWidth: 360)
                Text("Drag the price. Faster moves toss the glyphs.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
    }
}

#Preview("Velocity Glyph Scatter") {
    VelocityGlyphScatterDemo()
}
#endif
