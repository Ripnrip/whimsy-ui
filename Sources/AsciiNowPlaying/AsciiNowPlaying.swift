//  AsciiNowPlaying.swift
//  AsciiNowPlaying
//
//  A "now playing" card whose album art is drawn entirely in ASCII. A procedural cover (a dusk with a
//  slatted sun) is box-filtered down to a grid of cells, each cell's luminance picks a glyph from the
//  ramp " .:-=+*#%@", and a Canvas draws the glyphs in a monospaced font tinted by the cell's colour.
//  A slow sine wave makes the brightness breathe, with a different phase across the art. Tap the art
//  and the glyphs scramble, then resolve back cell by cell in a wave from your finger, with a light
//  haptic when it's done. Drag vertically on the art to change the grid between 24 and 72 columns, from
//  crunchy to fine. The image sampling, ramp mapping, shimmer, scramble timeline, density mapping, player
//  and events live in AsciiCore. Reduce Motion turns off the shimmer and resolves instantly.

#if canImport(SwiftUI)
import SwiftUI
import AsciiCore

/// A now-playing card with ASCII album art.
///
/// ```swift
/// AsciiNowPlaying()
/// AsciiNowPlaying(track: AsciiTrack(title: "Static Lullaby", artist: "Mira & the Quiet Arcades", duration: 214))
/// ```
public struct AsciiNowPlaying: View {
    @State private var engine: AsciiEngine
    @State private var isAnimating = true
    @State private var dragStart: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let artSide = 300.0
    static let accent = Color(red: 1.0, green: 0.45, blue: 0.62)
    static let background = LinearGradient(
        colors: [Color(red: 0.10, green: 0.07, blue: 0.20), Color(red: 0.03, green: 0.03, blue: 0.08)],
        startPoint: .top, endPoint: .bottom)

    public init(track: AsciiTrack = .sample) {
        _engine = State(initialValue: AsciiEngine(model: AsciiModel(track: track)))
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            VStack {
                card(m)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Self.background.ignoresSafeArea())
            .onChange(of: timeline.date) { _, _ in if m.isIdle { isAnimating = false } }
            .onChange(of: m.announcementCount) { _, _ in
                if let text = m.announcement { AccessibilityNotification.Announcement(text).post() }
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.8), trigger: m.resolveHaptics)
        }
    }

    private func card(_ m: AsciiModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            art(m)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.track.title).font(.title2.bold()).foregroundStyle(.white)
                Text(m.track.artist).font(.subheadline).foregroundStyle(.white.opacity(0.6))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(m.accessibilityLabel)
            .accessibilityValue(m.player.isPlaying ? "Playing" : "Paused")

            VStack(spacing: 2) {
                Slider(value: Binding(get: { m.player.position }, set: { seek($0) }), in: 0...max(m.player.duration, 1))
                    .tint(Self.accent)
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(AsciiPlayer.format(m.player.position)) of \(AsciiPlayer.format(m.player.duration))")
                HStack {
                    Text(AsciiPlayer.format(m.player.position))
                    Spacer()
                    Text("-" + AsciiPlayer.format(m.player.remaining))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
                .accessibilityHidden(true)
            }

            HStack {
                Spacer()
                Button { toggle() } label: {
                    Image(systemName: m.player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(Color(red: 0.10, green: 0.07, blue: 0.20))
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(.white))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.player.isPlaying ? "Pause" : "Play")
                Spacer()
            }

            Text("Tap the art to scramble it. Drag it up or down for detail: \(m.cols) columns, \(AsciiDensity.label(m.cols)).")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
        }
        .padding(20)
        .frame(width: Self.artSide + 40)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color(red: 0.11, green: 0.10, blue: 0.17))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 12))
    }

    private func art(_ m: AsciiModel) -> some View {
        AsciiArt(cells: m.cells(), cols: m.cols)
            .frame(width: Self.artSide, height: Self.artSide)
            .background(Color(red: 0.03, green: 0.02, blue: 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { v in
                tapArt(at: Vec2(v.location.x / Self.artSide, v.location.y / Self.artSide))
            })
            .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { g in
                let start = dragStart ?? engine.model.cols
                dragStart = start
                engine.setColumns(AsciiDensity.columns(start: start, translation: g.translation.height), at: Date())
                isAnimating = true
            }.onEnded { _ in dragStart = nil })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ASCII album art")
            .accessibilityValue("\(m.cols) columns, \(AsciiDensity.label(m.cols))")
            .accessibilityAddTraits(.isImage)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: engine.stepDensity(up: true, at: Date())
                case .decrement: engine.stepDensity(up: false, at: Date())
                @unknown default: break
                }
                isAnimating = true
            }
            .accessibilityAction(named: "Scramble") { tapArt(at: Vec2(0.5, 0.5)) }
    }

    private func tapArt(at p: Vec2) { engine.tap(at: p, date: Date()); isAnimating = true }
    private func toggle() { engine.togglePlay(at: Date()); isAnimating = true }
    private func seek(_ p: Double) { engine.seek(p, at: Date()); isAnimating = true }
}

/// The glyph grid. Glyphs are drawn once in white, then each cell's colour is applied with a
/// source-atop fill, so a few dozen resolved glyphs serve thousands of cells.
private struct AsciiArt: View {
    let cells: [AsciiCell]
    let cols: Int

    var body: some View {
        Canvas { ctx, size in
            let n = cols, cell = size.width / Double(n)
            let font = Font.system(size: AsciiDensity.fontSize(columns: n, side: size.width), weight: .bold, design: .monospaced)
            ctx.drawLayer { layer in
                var resolved: [Character: GraphicsContext.ResolvedText] = [:]
                for (i, c) in cells.enumerated() where c.glyph != " " {
                    let text: GraphicsContext.ResolvedText
                    if let r = resolved[c.glyph] { text = r } else {
                        text = layer.resolve(Text(String(c.glyph)).font(font).foregroundColor(.white))
                        resolved[c.glyph] = text
                    }
                    layer.draw(text, at: CGPoint(x: (Double(i % n) + 0.5) * cell, y: (Double(i / n) + 0.5) * cell), anchor: .center)
                }
                layer.blendMode = .sourceAtop
                for (i, c) in cells.enumerated() where c.glyph != " " {
                    layer.fill(Path(CGRect(x: Double(i % n) * cell, y: Double(i / n) * cell, width: cell, height: cell)),
                               with: .color(Color(red: c.r, green: c.g, blue: c.b)))
                }
            }
        }
    }
}

/// Owns the model and maps wall-clock dates (timeline frames and input) to model time.
final class AsciiEngine {
    private(set) var model: AsciiModel
    private var origin: Date?

    init(model: AsciiModel) { self.model = model }

    private func seconds(_ date: Date) -> Double {
        if origin == nil { origin = date }
        return date.timeIntervalSince(origin!)
    }

    func frame(at date: Date, reduceMotion: Bool) -> AsciiModel {
        model.config.reduceMotion = reduceMotion
        model.advance(to: seconds(date))
        return model
    }

    func tap(at p: Vec2, date: Date) { model.tap(at: p, time: seconds(date)) }
    func togglePlay(at date: Date) { model.togglePlay(at: seconds(date)) }
    func seek(_ p: Double, at date: Date) { model.seek(to: p, at: seconds(date)) }
    func setColumns(_ n: Int, at date: Date) { model.setColumns(n, at: seconds(date)) }
    func stepDensity(up: Bool, at date: Date) { model.stepDensity(up: up, at: seconds(date)) }
}

#Preview {
    AsciiNowPlaying()
}
#endif
