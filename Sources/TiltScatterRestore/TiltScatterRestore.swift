//
//  TiltScatterRestore.swift
//  TiltScatterRestore
//
//  A paper to-do list. Completing a row fades its title into letter chips, which tumble
//  under gravity. On iPhone the gravity follows the device; everywhere else, drag in the
//  tray. Restore springs each chip back onto its own letter. Reduce Motion keeps the
//  chips seated in the word. Physics and layout live in TiltScatterCore.

#if canImport(SwiftUI)
import SwiftUI
import TiltScatterCore
#if os(iOS) && !targetEnvironment(simulator)
import CoreMotion
#endif

/// A paper list whose completed lines scatter into letter chips and spring back.
///
/// ```swift
/// TiltScatterRestore()
/// TiltScatterRestore(tasks: [
///     TiltScatterTask(id: "fern", title: "Water the fern"),
///     TiltScatterTask(id: "ink", title: "Buy walnut ink"),
/// ])
/// ```
public struct TiltScatterRestore: View {
    private let useDeviceMotion: Bool
    @State private var model: TiltScatterModel
    @State private var lastDate: Date?
    @State private var animating = false
    @State private var dragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    #if os(iOS) && !targetEnvironment(simulator)
    @State private var motion = TiltScatterMotion()
    #endif

    public init(tasks: [TiltScatterTask] = TiltScatterCatalog.tasks, seed: UInt64 = 0x71C75CA7, useDeviceMotion: Bool = true) {
        self.useDeviceMotion = useDeviceMotion
        _model = State(initialValue: TiltScatterModel(tasks: tasks, seed: seed))
    }

    public var body: some View {
        TimelineView(.animation(paused: !animating)) { timeline in
            sheet
                .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette(TiltScatterPalette.paper).ignoresSafeArea())
        .onAppear {
            model.setReduceMotion(reduceMotion)
            startMotion()
        }
        .onDisappear { stopMotion() }
        .onChange(of: reduceMotion) { _, on in
            model.setReduceMotion(on)
            animating = model.needsFrame
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: model.completeHaptics)
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.45), trigger: model.landHaptics)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.55), trigger: model.restoreHaptics)
        .onChange(of: model.announcementCount) { _, _ in
            if let text = model.announcement {
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }

    private var sheet: some View {
        let width = TiltScatterLayout.cardWidth
        let height = TiltScatterLayout.cardHeight
        return ZStack(alignment: .topLeading) {
            grain
            tray
            header
            ForEach(model.rows, id: \.index) { row in
                rowCard(row)
                    .offset(y: TiltScatterLayout.rowTop(row.index))
            }
            restoreButton
            titleGlyphs
            chips
            gravityArrow
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .padding(.top, 8)
    }

    // MARK: Pieces

    private var grain: some View {
        Canvas { context, _ in
            for speck in TiltScatterLayout.grain() {
                let rect = CGRect(x: speck.x, y: speck.y, width: 1.2, height: 1.2)
                context.fill(Path(ellipseIn: rect), with: .color(palette(TiltScatterPalette.ink).opacity(0.045)))
            }
        }
        .frame(width: TiltScatterLayout.cardWidth, height: TiltScatterLayout.cardHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Paper tray")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundStyle(palette(TiltScatterPalette.ink))
                .accessibilityAddTraits(.isHeader)
            Text(reduceMotion ? "Completed lines become letter chips." : "Complete a line. Tip the tray.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(palette(TiltScatterPalette.ink).opacity(0.62))
            level
        }
        .padding(.horizontal, 4)
        .offset(x: TiltScatterLayout.rowX, y: 14)
    }

    private var tray: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape.fill(palette(TiltScatterPalette.tray))
            Path { path in
                // Sits just under a chip resting on the physics floor.
                let y = TiltScatterLayout.boundBottom - TiltScatterLayout.trayTop - 2
                path.move(to: CGPoint(x: 16, y: y))
                path.addLine(to: CGPoint(x: TiltScatterLayout.rowWidth - 16, y: y))
            }
            .stroke(palette(TiltScatterPalette.rule).opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        }
        .frame(width: TiltScatterLayout.rowWidth, height: TiltScatterLayout.trayHeight)
        .offset(x: TiltScatterLayout.rowX, y: TiltScatterLayout.trayTop)
        .gesture(trayDrag)
        .accessibilityHidden(true)
    }

    private var level: some View {
        let travel = 28.0
        return ZStack {
            Capsule().fill(palette(TiltScatterPalette.ink).opacity(0.08))
            Capsule().strokeBorder(palette(TiltScatterPalette.ink).opacity(0.2), lineWidth: 1)
            Circle()
                .fill(palette(TiltScatterPalette.wax))
                .frame(width: 8, height: 8)
                .offset(x: model.tilt.x * travel, y: model.tilt.y * 3)
        }
        .frame(width: 72, height: 16)
        .accessibilityElement()
        .accessibilityLabel("Tray tilt")
        .accessibilityValue(model.tiltDescription)
        .accessibilityAdjustableAction { direction in
            var next = model.tilt
            let step = 0.25
            if direction == .increment { next.x = min(1, next.x + step) }
            else { next.x = max(-1, next.x - step) }
            model.setTilt(next)
            animating = true
        }
        .accessibilityAction(named: "Level the tray") {
            model.setTilt(.zero)
            animating = true
        }
        .accessibilityHint("Swipe up to tip right, down to tip left")
    }

    private func rowCard(_ row: TiltScatterRow) -> some View {
        let done = row.phase != .idle
        return Button {
            _ = model.toggle(row.index)
            animating = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(palette(TiltScatterPalette.ink).opacity(0.55), lineWidth: 1.5)
                    if done {
                        Circle().fill(palette(TiltScatterPalette.wax)).padding(3)
                        CheckMark()
                            .stroke(palette(TiltScatterPalette.card), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .padding(6)
                    }
                }
                .frame(width: TiltScatterLayout.checkbox, height: TiltScatterLayout.checkbox)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: TiltScatterLayout.rowWidth, height: TiltScatterLayout.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: TiltScatterLayout.rowCorner, style: .continuous)
                    .fill(palette(TiltScatterPalette.card))
                    .shadow(color: .black.opacity(0.06), radius: 5, y: 2)
            )
        }
        .buttonStyle(.plain)
        .offset(x: TiltScatterLayout.rowX)
        .accessibilityLabel(row.title)
        .accessibilityValue(model.accessibilityValue(for: row.index))
        .accessibilityAddTraits(.isToggle)
        .accessibilityHint(done ? "Puts the letters back into the line" : "The letters fall into the tray")
    }

    private var titleGlyphs: some View {
        ZStack {
            ForEach(model.rows, id: \.index) { row in
                let glyphs = TiltScatterLayout.glyphs(title: row.title, row: row.index)
                ForEach(glyphs, id: \.index) { glyph in
                    Text(glyph.glyph)
                        .font(.system(size: TiltScatterLayout.fontSize, weight: .medium, design: .serif))
                        .foregroundStyle(palette(TiltScatterPalette.ink))
                        .position(x: glyph.home.x, y: glyph.home.y)
                        .opacity(row.titleOpacity)
                }
            }
        }
        .frame(width: TiltScatterLayout.cardWidth, height: TiltScatterLayout.cardHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var chips: some View {
        ZStack {
            ForEach(model.chips) { chip in
                chipView(chip)
            }
        }
        .frame(width: TiltScatterLayout.cardWidth, height: TiltScatterLayout.cardHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func chipView(_ chip: TiltScatterChip) -> some View {
        let scale = chip.scale * TiltScatterTuning.flightScale(speed: chip.speed)
        return Text(chip.glyph)
            .font(.system(size: TiltScatterLayout.fontSize, weight: .semibold, design: .serif))
            .foregroundStyle(palette(TiltScatterPalette.ink))
            .frame(width: chip.width, height: TiltScatterLayout.chipHeight)
            .background(
                RoundedRectangle(cornerRadius: TiltScatterLayout.chipCorner, style: .continuous)
                    .fill(palette(TiltScatterPalette.chip))
                    .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TiltScatterLayout.chipCorner, style: .continuous)
                    .strokeBorder(palette(TiltScatterPalette.ink).opacity(0.28), lineWidth: 0.6)
            )
            .rotationEffect(.radians(chip.angle))
            .scaleEffect(scale)
            .position(x: chip.position.x, y: chip.position.y)
            .opacity(chip.opacity)
    }

    private var restoreButton: some View {
        Button {
            _ = model.restoreAll()
            animating = true
        } label: {
            Text("Restore")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(palette(TiltScatterPalette.card))
                .frame(width: 148, height: TiltScatterLayout.buttonHeight)
                .background(Capsule(style: .continuous).fill(palette(TiltScatterPalette.ink)))
        }
        .buttonStyle(.plain)
        .disabled(!model.canRestore)
        .opacity(model.canRestore ? 1 : 0.38)
        .offset(x: TiltScatterLayout.rowX, y: TiltScatterLayout.buttonTop)
        .accessibilityLabel("Restore")
        .accessibilityHint("Springs every letter back into its line")
    }

    private var gravityArrow: some View {
        let g = model.gravity
        let length = max(g.length, 1)
        let dx = g.x / length * 16
        let dy = g.y / length * 16
        let origin = CGPoint(x: TiltScatterLayout.rowX + TiltScatterLayout.rowWidth - 36, y: TiltScatterLayout.trayTop + 28)
        return Path { path in
            path.move(to: origin)
            path.addLine(to: CGPoint(x: origin.x + dx, y: origin.y + dy))
        }
        .stroke(palette(TiltScatterPalette.ink).opacity(abs(model.tilt.x) > 0.08 || abs(model.tilt.y) > 0.08 ? 0.45 : 0),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var trayDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragging = true
                let local = Vec2(Double(value.location.x), Double(value.location.y))
                let size = Vec2(TiltScatterLayout.rowWidth, TiltScatterLayout.trayHeight)
                model.setTilt(TiltScatterMotionMap.tilt(fromFinger: local, in: size))
                animating = true
            }
            .onEnded { _ in
                dragging = false
                model.setTilt(.zero)
                animating = true
            }
    }

    // MARK: Clock

    private func advance(to now: Date) {
        model.setReduceMotion(reduceMotion)
        defer { lastDate = now }
        guard let last = lastDate else { return }
        _ = model.step(dt: now.timeIntervalSince(last))
        if !model.needsFrame && !dragging { animating = false }
    }

    private func palette(_ rgb: RGB) -> Color {
        Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    private func startMotion() {
        #if os(iOS) && !targetEnvironment(simulator)
        guard useDeviceMotion else { return }
        motion.start { sample in
            guard !dragging else { return }
            model.setTilt(sample)
            animating = true
        }
        #endif
    }

    private func stopMotion() {
        #if os(iOS) && !targetEnvironment(simulator)
        motion.stop()
        #endif
    }
}

/// The same list, for previews and the gallery.
public struct TiltScatterRestoreDemo: View {
    public init() {}
    public var body: some View { TiltScatterRestore() }
}

private struct CheckMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.maxY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.08, y: rect.minY + rect.height * 0.2))
        return path
    }
}

#if os(iOS) && !targetEnvironment(simulator)
/// Device attitude, mapped with ``TiltScatterMotionMap`` so the core never imports CoreMotion.
@MainActor
final class TiltScatterMotion {
    private let manager = CMMotionManager()

    func start(_ handler: @escaping @MainActor (Vec2) -> Void) {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let attitude = data?.attitude else { return }
            let sample = TiltScatterMotionMap.tilt(pitch: attitude.pitch, roll: attitude.roll)
            MainActor.assumeIsolated { handler(sample) }
        }
    }

    func stop() { manager.stopDeviceMotionUpdates() }
}
#endif

#Preview { TiltScatterRestoreDemo() }
#endif
