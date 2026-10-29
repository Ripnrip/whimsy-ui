//  OctoDoneChecklist.swift
//  OctoDoneChecklist
//
//  A to-do list where finished rows get eaten. Tick a row's circle and the checkmark draws in, then a
//  blurred halftone blob (a Canvas dot grid whose dot size follows a radial falloff) swells up from
//  below the row. A tapered, dotted tentacle curls over the top and wraps it, then the blob and row are
//  pulled down together with a springy, volume-preserving squash and stretch, and the row collapses out
//  of the list while the rows below spring up. "Complete all" sends the ink through the remaining rows
//  in turn, and "Reset" brings everything back. The per-row timeline, halftone field, squash, list
//  layout, sweep scheduler, undo-safe state machine and events live in OctoCore. Reduce Motion swaps
//  the ink for a plain fade and collapse.

#if canImport(SwiftUI)
import SwiftUI
import OctoCore

/// A five-row checklist with an octopus-ink "done" animation.
///
/// ```swift
/// OctoDoneChecklist()
/// OctoDoneChecklist(titles: ["Water the ferns", "Fold the laundry"], tentacle: false)
/// ```
public struct OctoDoneChecklist: View {
    @State private var engine: OctoEngine
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tentacle: Bool

    static let ink = Color(red: 0.33, green: 0.20, blue: 0.58)
    static let accent = Color(red: 0.16, green: 0.62, blue: 0.52)
    static let background = LinearGradient(
        colors: [Color(red: 0.99, green: 0.97, blue: 0.93), Color(red: 0.95, green: 0.93, blue: 0.99)],
        startPoint: .top, endPoint: .bottom)

    public init(titles: [String] = OctoCatalog.titles, tentacle: Bool = true) {
        _engine = State(initialValue: OctoEngine(model: OctoModel(titles: titles)))
        self.tentacle = tentacle
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            let frames = m.frames
            VStack(alignment: .leading, spacing: 16) {
                header(m)
                OctoList(model: m, frames: frames, tentacle: tentacle && !reduceMotion, onTap: tap)
                HStack(spacing: 12) {
                    Button { completeAll() } label: {
                        Label("Complete all", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Self.ink)
                    .disabled(!m.canCompleteAll)
                    .accessibilityHint("Completes every remaining task, one after another")
                    Button { reset() } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(Self.ink)
                    .disabled(!m.canReset)
                    .accessibilityHint("Brings every task back")
                }
                .controlSize(.large)
                .frame(width: OctoLayout.rowWidth)
            }
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Self.background.ignoresSafeArea())
            .onChange(of: m.isIdle) { _, idle in if idle { isAnimating = false } }
            .onChange(of: m.announcementCount) { _, _ in
                if let text = m.announcement { AccessibilityNotification.Announcement(text).post() }
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: m.grabHaptics)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: m.goneHaptics)
        }
    }

    private func header(_ m: OctoModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
            Text(m.isAllDone ? "All done. Nothing left." : "\(m.count - m.goneCount) left")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(width: OctoLayout.rowWidth, alignment: .leading)
    }

    private func tap(_ i: Int) {
        engine.tap(i, at: Date())
        isAnimating = true
    }

    private func completeAll() {
        engine.completeAll(at: Date())
        isAnimating = true
    }

    private func reset() {
        engine.reset(at: Date())
        isAnimating = true
    }
}

/// The rows, stacked by their slots, with one ink layer drawn over all of them.
private struct OctoList: View {
    let model: OctoModel
    let frames: [OctoRowFrame]
    let tentacle: Bool
    let onTap: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(frames, id: \.index) { f in
                OctoRow(title: model.titles[f.index], frame: f, checked: model.isChecked(f.index)) { onTap(f.index) }
                    .offset(y: f.top)
            }
            InkLayer(frames: frames, tentacle: tentacle)
                .frame(width: OctoLayout.rowWidth + 2 * InkLayer.pad, height: model.listHeight + 2 * InkLayer.pad, alignment: .topLeading)
                .offset(x: -InkLayer.pad, y: -InkLayer.pad)
                .blur(radius: OctoInk.blurRadius)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: OctoLayout.rowWidth, height: model.listHeight, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tasks")
    }
}

/// One task: a circle that draws its checkmark, the title, and the squash/pull/collapse transform.
private struct OctoRow: View {
    let title: String
    let frame: OctoRowFrame
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 2)
                    Circle().fill(OctoDoneChecklist.accent).opacity(frame.check)
                    CheckShape()
                        .trim(from: 0, to: frame.check)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                }
                .frame(width: 28, height: 28)
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary.opacity(1 - 0.5 * frame.check))
                    .overlay(alignment: .leading) {
                        // Strike-through draws left to right with the check.
                        GeometryReader { g in
                            Rectangle().fill(Color.secondary).frame(width: g.size.width * frame.check, height: 1.5)
                                .position(x: g.size.width * frame.check / 2, y: g.size.height / 2)
                        }
                    }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(width: OctoLayout.rowWidth, height: OctoLayout.rowHeight)
            .background(RoundedRectangle(cornerRadius: OctoLayout.cornerRadius, style: .continuous).fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1))
            .contentShape(RoundedRectangle(cornerRadius: OctoLayout.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        // Collapse (height to 0), then squash/stretch about the centre, then the pull down.
        .scaleEffect(x: 1, y: max(frame.heightScale, 0.001), anchor: .top)
        .scaleEffect(x: frame.scaleX, y: frame.scaleY, anchor: .center)
        .offset(y: frame.offsetY)
        .opacity(frame.opacity)
        .allowsHitTesting(frame.phase != .gone && frame.opacity > 0.5)
        .accessibilityHidden(frame.phase == .gone || frame.opacity < 0.05)
        .accessibilityLabel(title)
        .accessibilityValue(checked ? "Completed" : "Not completed")
        .accessibilityAddTraits([.isButton, .isToggle])
    }
}

private struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.52))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.44, y: r.minY + r.height * 0.67))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.72, y: r.minY + r.height * 0.34))
        return p
    }
}

/// The halftone blobs and tentacles, drawn for every row in the same layer so they can overlap neighbours.
private struct InkLayer: View {
    let frames: [OctoRowFrame]
    let tentacle: Bool
    static let pad = 80.0

    var body: some View {
        Canvas { ctx, _ in
            for f in frames where f.showsInk {
                var c = ctx
                c.opacity = f.opacity
                c.translateBy(x: Self.pad, y: Self.pad + f.top + f.offsetY)
                // Squash and stretch about the row's centre, like the row itself.
                c.translateBy(x: OctoLayout.rowWidth / 2, y: OctoLayout.rowHeight / 2)
                c.scaleBy(x: f.scaleX, y: f.scaleY)
                c.translateBy(x: -OctoLayout.rowWidth / 2, y: -OctoLayout.rowHeight / 2)
                var dots = OctoInk.dots(blob: f.blob)
                if tentacle { dots += OctoInk.tentacle(grab: f.grab) }
                var path = Path()
                for d in dots {
                    path.addEllipse(in: CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2, height: d.r * 2))
                }
                c.fill(path, with: .color(OctoDoneChecklist.ink))
            }
        }
    }
}

/// Owns the model and maps wall-clock dates (timeline frames and taps) to model time.
final class OctoEngine {
    private(set) var model: OctoModel
    private var origin: Date?

    init(model: OctoModel) { self.model = model }

    private func seconds(_ date: Date) -> Double {
        if origin == nil { origin = date }
        return date.timeIntervalSince(origin!)
    }

    func frame(at date: Date, reduceMotion: Bool) -> OctoModel {
        model.config.reduceMotion = reduceMotion
        model.advance(to: seconds(date))
        return model
    }

    func tap(_ i: Int, at date: Date) { model.tap(i, at: seconds(date)) }
    func completeAll(at date: Date) { model.completeAll(at: seconds(date)) }
    func reset(at date: Date) { model.reset(at: seconds(date)) }
}

#Preview {
    OctoDoneChecklist()
}
#endif
