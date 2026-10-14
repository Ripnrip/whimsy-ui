//  EraserDelete.swift
//  EraserDelete
//
//  "Delete by erasing": a pink eraser zig-zags across a card, wipes it away stroke by stroke
//  (a real mask: the card minus the erased stroke), sheds crumbs and ticks a light haptic at
//  every turn. At ~96% coverage the last bits fade, then `onErased` runs inside an animation
//  so a List row collapses smoothly. You can also scrub the card by hand (`.manual`).
//  Geometry, coverage and particles live in EraserDeleteCore; this file drives and draws them.

#if canImport(SwiftUI)
import SwiftUI
import EraserDeleteCore

/// How the card gets erased.
public enum EraseStyle: Sendable, Hashable {
    /// The eraser zig-zags across the card by itself.
    case automatic
    /// While `isErasing` is true, the user scrubs the card with a finger. With VoiceOver
    /// on, this falls back to `.automatic`.
    case manual
}

public extension View {
    /// Erases this view with a zig-zagging eraser when `isErasing` becomes `true`, then calls
    /// `onErased` inside an animation. Remove the item there so its row collapses.
    ///
    /// - Parameters:
    ///   - isErasing: set to `true` to start. It is set back to `false` once erased. Setting it
    ///     to `false` mid-erase cancels and restores the card.
    ///   - style: `.automatic` (default) or `.manual` scrubbing.
    ///   - eraserWidth: width of the erased stroke; defaults to a size based on the card height.
    ///   - duration: duration of the automatic sweep; defaults to one based on the path length.
    func eraserDelete(
        isErasing: Binding<Bool>,
        style: EraseStyle = .automatic,
        eraserWidth: CGFloat? = nil,
        duration: TimeInterval? = nil,
        onErased: @escaping () -> Void
    ) -> some View {
        ErasableCard(isErasing: isErasing, style: style, eraserWidth: eraserWidth,
                     duration: duration, onErased: onErased) { self }
    }
}

/// Container form of `.eraserDelete(...)`.
public struct ErasableCard<Content: View>: View {
    @Binding private var isErasing: Bool
    private let style: EraseStyle
    private let eraserWidth: CGFloat?
    private let duration: TimeInterval?
    private let onErased: () -> Void
    private let content: Content

    private enum Phase { case idle, erasing, finishing, done }

    @State private var engine = EraseEngine()
    @State private var phase = Phase.idle
    @State private var cardSize = CGSize.zero
    @State private var opacity = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    public init(
        isErasing: Binding<Bool>,
        style: EraseStyle = .automatic,
        eraserWidth: CGFloat? = nil,
        duration: TimeInterval? = nil,
        onErased: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        _isErasing = isErasing
        self.style = style
        self.eraserWidth = eraserWidth
        self.duration = duration
        self.onErased = onErased
        self.content = content()
    }

    private var isAutomatic: Bool { style == .automatic || voiceOverEnabled }
    private var isAnimating: Bool { phase == .erasing || phase == .finishing }
    private var acceptsScrubbing: Bool { !isAutomatic && phase == .erasing }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let frame = engine.frame(at: timeline.date, automatic: isAutomatic && isAnimating)
            content
                .mask { EraseMask(frame: frame) }
                .overlay { EraseEffects(frame: frame) }
                .sensoryFeedback(trigger: frame.turnCount) { old, new in
                    new > old ? .impact(weight: .light) : nil
                }
                .onChange(of: frame.isFullyWiped) { _, wiped in
                    if wiped { finish() }
                }
        }
        .opacity(opacity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { cardSize = proxy.size }
                    .onChange(of: proxy.size) { _, size in cardSize = size }
            }
        }
        .contentShape(Rectangle())
        .gesture(scrubGesture, including: acceptsScrubbing ? .all : .subviews)
        .onChange(of: isErasing, initial: true) { _, erasing in
            erasing ? begin() : cancel()
        }
        .accessibilityAction(named: "Erase") { isErasing = true }
        .accessibilityHint(acceptsScrubbing ? Text("Scrub with one finger to erase.") : Text(""))
    }

    // MARK: Flow

    private func begin() {
        guard phase == .idle || phase == .done else { return }
        opacity = 1
        if reduceMotion {
            // No eraser, no crumbs: a quick fade.
            phase = .finishing
            withAnimation(.easeOut(duration: 0.2)) { opacity = 0 } completion: { complete() }
            return
        }
        engine.start(size: cardSize, eraserWidth: eraserWidth, duration: duration)
        phase = .erasing
        AccessibilityNotification.Announcement("Erasing").post()
    }

    private func cancel() {
        guard phase == .erasing else { return }
        engine.stop()
        phase = .idle
        opacity = 1
    }

    /// Coverage reached the threshold: fade what's left (the eraser keeps going while it fades).
    private func finish() {
        guard phase == .erasing else { return }
        phase = .finishing
        withAnimation(.easeOut(duration: 0.3)) { opacity = 0 } completion: { complete() }
    }

    private func complete() {
        guard phase == .finishing else { return }
        phase = .done
        engine.stop()
        withAnimation(.snappy) { onErased() }
        isErasing = false
    }

    // MARK: Manual scrubbing

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard acceptsScrubbing else { return }
                engine.scrub(to: value.location, size: cardSize, eraserWidth: eraserWidth)
            }
            .onEnded { _ in engine.endScrub() }
    }
}

// MARK: - Engine

/// What one rendered frame needs: a value snapshot of the simulation.
struct EraseFrame {
    var strokes: [[Vec2]] = []
    var eraserWidth: Double = 0
    var pose: EraserPose?
    var crumbs: [Crumb] = []
    var turnCount = 0
    var isFullyWiped = false
}

/// Holds the mutable simulation outside SwiftUI's dependency tracking. The TimelineView
/// already redraws every frame, so stepping it while rendering doesn't trigger extra updates.
/// Advancing to the same date twice is a no-op, so repeated body evaluations are harmless.
final class EraseEngine {
    private(set) var session: EraserSession?
    private var crumbs = CrumbEmitter()
    private var startDate: Date?
    private var lastDate: Date?
    private var duration: TimeInterval = 1.5

    /// Default sweep speed in points per second.
    static let speed: Double = 950

    static func defaultEraserWidth(for size: CGSize) -> Double {
        min(max(Double(size.height) / 2.6, 22), 56)
    }

    func start(size: CGSize, eraserWidth: CGFloat?, duration: TimeInterval?) {
        let width = eraserWidth.map { Double($0) } ?? Self.defaultEraserWidth(for: size)
        let session = EraserSession(
            cardSize: CardSize(width: Double(size.width), height: Double(size.height)),
            eraserWidth: max(width, 1)
        )
        self.session = session
        self.duration = duration ?? min(max(session.path.length / Self.speed, 0.9), 2.4)
        crumbs = CrumbEmitter(seed: UInt64.random(in: 0...UInt64.max))
        startDate = nil
        lastDate = nil
    }

    func stop() {
        session = nil
        crumbs.removeAll()
        startDate = nil
        lastDate = nil
    }

    func frame(at date: Date, automatic: Bool) -> EraseFrame {
        let dt = lastDate.map { date.timeIntervalSince($0) } ?? 0
        lastDate = date
        if automatic, session != nil {
            let start = startDate ?? date
            startDate = start
            let progress = duration > 0 ? date.timeIntervalSince(start) / duration : 1
            if let movement = session?.advance(to: progress), let pose = session?.pose {
                emitCrumbs(distance: movement.distance, pose: pose)
            }
        }
        crumbs.step(dt: dt)
        return snapshot
    }

    func scrub(to location: CGPoint, size: CGSize, eraserWidth: CGFloat?) {
        if session == nil { start(size: size, eraserWidth: eraserWidth, duration: nil) }
        let point = Vec2(Double(location.x), Double(location.y))
        if session?.isScrubbing == true {
            if let movement = session?.scrub(to: point), let pose = session?.pose {
                emitCrumbs(distance: movement.distance, pose: pose)
            }
        } else {
            session?.beginScrub(at: point)
        }
    }

    func endScrub() {
        session?.endScrub()
    }

    private func emitCrumbs(distance: Double, pose: EraserPose) {
        guard let radius = session?.eraserRadius else { return }
        crumbs.emit(forTravel: distance, at: pose.position, direction: pose.direction, spread: radius)
    }

    private var snapshot: EraseFrame {
        guard let session else { return EraseFrame(crumbs: crumbs.crumbs) }
        return EraseFrame(
            strokes: session.strokes,
            eraserWidth: session.eraserWidth,
            pose: session.pose,
            crumbs: crumbs.crumbs,
            turnCount: session.turnCount,
            isFullyWiped: session.isFullyWiped
        )
    }
}

// MARK: - Mask

/// The card minus the erased stroke. The Canvas renders into its own layer, so it fills
/// opaque black and then cuts the stroke out with `.destinationOut`. The result is opaque
/// where the card stays and transparent where it's been erased; `.mask` uses that alpha.
private struct EraseMask: View {
    let frame: EraseFrame

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            guard !frame.strokes.isEmpty else { return }
            var erased = Path()
            for stroke in frame.strokes {
                guard let first = stroke.first else { continue }
                erased.move(to: first.cgPoint)
                if stroke.count == 1 {
                    erased.addLine(to: first.cgPoint) // zero-length segment + round cap = a dot
                } else {
                    for point in stroke.dropFirst() { erased.addLine(to: point.cgPoint) }
                }
            }
            context.blendMode = .destinationOut
            context.stroke(
                erased,
                with: .color(.black),
                style: StrokeStyle(lineWidth: frame.eraserWidth, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

// MARK: - Eraser + crumbs

private struct EraseEffects: View {
    let frame: EraseFrame

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for crumb in frame.crumbs {
                    var c = context
                    c.opacity = crumb.opacity
                    c.translateBy(x: crumb.position.x, y: crumb.position.y)
                    c.rotate(by: .radians(crumb.rotation))
                    let s = crumb.size
                    c.fill(
                        Path(roundedRect: CGRect(x: -s / 2, y: -s * 0.4, width: s, height: s * 0.8), cornerRadius: s * 0.3),
                        with: .color(Color(hue: 0.96, saturation: 0.3 + 0.25 * crumb.shade, brightness: 0.97 - 0.2 * crumb.shade))
                    )
                }
            }

            if let pose = frame.pose, frame.eraserWidth > 0 {
                let width = frame.eraserWidth
                let height = EraserGlyph.height(forWidth: width)
                // Rubbing face (bottom of the glyph) sits on the stroke; the body tilts around it.
                EraserGlyph(width: width)
                    .rotationEffect(.radians(pose.rotation), anchor: .bottom)
                    .position(x: pose.position.x, y: pose.position.y - height / 2 + width * 0.3)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A pink eraser with a blue cardboard sleeve.
struct EraserGlyph: View {
    let width: Double

    static func height(forWidth width: Double) -> Double { width * 1.9 }

    var body: some View {
        let w = width * 1.05
        let h = Self.height(forWidth: width)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: w * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 1.0, green: 0.74, blue: 0.80), Color(red: 0.93, green: 0.48, blue: 0.60)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(alignment: .bottom) {
                    // Worn, slightly darker rubbing face.
                    RoundedRectangle(cornerRadius: w * 0.22, style: .continuous)
                        .fill(Color(red: 0.86, green: 0.42, blue: 0.53))
                        .frame(height: h * 0.12)
                }
            UnevenRoundedRectangle(topLeadingRadius: w * 0.2, topTrailingRadius: w * 0.2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.36, green: 0.55, blue: 0.95), Color(red: 0.18, green: 0.33, blue: 0.75)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay {
                    VStack(spacing: h * 0.06) {
                        Capsule().fill(.white.opacity(0.75)).frame(height: max(h * 0.025, 1))
                        Capsule().fill(.white.opacity(0.75)).frame(height: max(h * 0.025, 1))
                    }
                    .padding(.horizontal, w * 0.12)
                }
                .frame(height: h * 0.56)
        }
        .frame(width: w, height: h)
        .shadow(color: .black.opacity(0.25), radius: 3, x: 1, y: 2)
    }
}

private extension Vec2 {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - Preview

private struct DemoNote: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var detail: String
    var hue: Double
}

private struct DemoNoteCard: View {
    let note: DemoNote

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hue: note.hue, saturation: 0.55, brightness: 0.9))
                .frame(width: 36, height: 36)
                .overlay { Image(systemName: "doc.text.fill").foregroundStyle(.white) }
            VStack(alignment: .leading, spacing: 2) {
                Text(note.title).font(.headline)
                Text(note.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72)
        .background(Color(hue: note.hue, saturation: 0.12, brightness: 1.0), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private struct DemoRow: View {
    let note: DemoNote
    let style: EraseStyle
    let onDelete: () -> Void
    @State private var isErasing = false

    var body: some View {
        DemoNoteCard(note: note)
            .overlay(alignment: .trailing) {
                if style == .manual && !isErasing {
                    Button("Scrub", systemImage: "hand.draw") { isErasing = true }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.bordered)
                        .padding(.trailing, 12)
                }
            }
            .eraserDelete(isErasing: $isErasing, style: style, onErased: onDelete)
            .swipeActions(edge: .trailing) {
                Button("Erase", systemImage: "eraser") { isErasing = true }
                    .tint(.pink)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

private struct EraserDeleteDemo: View {
    private static func sampleNotes() -> [DemoNote] {
        [
            DemoNote(title: "Groceries", detail: "Oat milk, limes, basil", hue: 0.33),
            DemoNote(title: "Ideas", detail: "Bubble wrap… but for code review", hue: 0.58),
            DemoNote(title: "Old password hint", detail: "Definitely erase this one", hue: 0.0),
            DemoNote(title: "Meeting notes", detail: "Ship it Friday 🚢", hue: 0.12),
        ]
    }
    private static func sampleScrubNotes() -> [DemoNote] {
        [DemoNote(title: "Scrub me", detail: "Tap the hand, then rub it out", hue: 0.8)]
    }

    @State private var notes = EraserDeleteDemo.sampleNotes()
    @State private var scrubNotes = EraserDeleteDemo.sampleScrubNotes()

    var body: some View {
        NavigationStack {
            List {
                Section("Swipe → Erase") {
                    ForEach(notes) { note in
                        DemoRow(note: note, style: .automatic) {
                            notes.removeAll { $0.id == note.id }
                        }
                    }
                }
                Section("Manual scrub") {
                    ForEach(scrubNotes) { note in
                        DemoRow(note: note, style: .manual) {
                            scrubNotes.removeAll { $0.id == note.id }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Eraser Delete")
            .toolbar {
                Button("Reset") {
                    withAnimation {
                        notes = Self.sampleNotes()
                        scrubNotes = Self.sampleScrubNotes()
                    }
                }
            }
        }
    }
}

#Preview("Eraser Delete") {
    EraserDeleteDemo()
}
#endif
