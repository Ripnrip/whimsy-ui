//  WiggleMatchSearch.swift
//  WiggleMatchSearch
//
//  A settings search where the matches wiggle. Type into the field and the rows are fuzzy-matched
//  (subsequence, preferring word starts and consecutive runs), sorted by score, and non-matches
//  disappear. Every matched letter in a title gets its own little sine-wave underline, phase-shifted
//  by the letter's index so a run of matches reads as one travelling squiggle. Newly matched letters
//  jiggle in on a spring, a light haptic ticks (debounced), and ~0.5 s after the last keystroke the
//  waves ease down to a flat line until you type again. Matching, diffing, the envelope, wave
//  sampling, the jiggle spring and the events all live in WiggleCore.

#if canImport(SwiftUI)
import SwiftUI
import WiggleCore

/// A searchable settings list with wiggly match underlines.
///
/// ```swift
/// WiggleMatchSearch()
/// WiggleMatchSearch(rows: myRows)
/// ```
public struct WiggleMatchSearch: View {
    @State private var engine: WiggleEngine
    @State private var query = ""
    @State private var isAnimating = false
    @State private var ticks = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let accent = Color(red: 0.93, green: 0.27, blue: 0.47)
    static let background = Color(red: 0.95, green: 0.95, blue: 0.97)

    public init(rows: [SettingsRow] = SettingsCatalog.rows) {
        _engine = State(initialValue: WiggleEngine(rows: rows))
    }

    public var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.largeTitle.bold())
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
                SearchField(query: $query)
                    .padding(.horizontal, 16)
                Text(Self.countText(m))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 24)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(m.results.enumerated()), id: \.element.row.id) { i, r in
                            WiggleRow(ranked: r, model: m, query: m.query)
                            if i < m.results.count - 1 { Divider().padding(.leading, 57) }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
                    .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: m.results.map(\.row.id))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    if m.results.isEmpty {
                        Text("No settings match \u{201C}\(m.query)\u{201D}")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Self.background.ignoresSafeArea())
            .onChange(of: m.ticks) { _, n in ticks = n }
            .onChange(of: m.isIdle) { _, idle in if idle { isAnimating = false } }
        }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: ticks)
        .onChange(of: query) { _, q in
            let before = engine.model.resultCount
            engine.setQuery(q, at: Date())
            isAnimating = true
            let n = engine.model.resultCount
            if n != before { AccessibilityNotification.Announcement(Self.countText(engine.model)).post() }
        }
    }

    static func countText(_ m: WiggleModel) -> String {
        if m.query.trimmingCharacters(in: .whitespaces).isEmpty { return "\(m.resultCount) settings" }
        return m.resultCount == 1 ? "1 result" : "\(m.resultCount) results"
    }
}

/// The rounded search field with a clear button.
private struct SearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search", text: $query)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.search)
                .accessibilityLabel("Search settings")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .font(.body)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.06)))
    }
}

/// One settings row: icon tile, wiggly title, subtitle, chevron.
private struct WiggleRow: View {
    let ranked: RankedRow
    let model: WiggleModel
    let query: String

    var body: some View {
        let row = ranked.row
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Self.tileColor(row.hue))
                .frame(width: 29, height: 29)
                .overlay(Image(systemName: row.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 3) {
                WiggleTitle(title: Array(row.title), matched: Set(ranked.match.indices), rowID: row.id, model: model)
                Text(row.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(row.subtitle)
        .accessibilityCustomContent("Matched letters", Self.matchedLetters(row.title, ranked.match.indices))
    }

    /// Hue 0 is the grey "system" tile; everything else is a saturated tile like the real Settings app.
    static func tileColor(_ hue: Double) -> Color {
        hue == 0 ? Color(white: 0.56) : Color(hue: hue, saturation: 0.72, brightness: 0.92)
    }

    static func matchedLetters(_ title: String, _ idx: [Int]) -> Text {
        let t = Array(title)
        return Text(idx.isEmpty ? "None" : idx.map { String(t[$0]) }.joined(separator: ", "))
    }
}

/// A title laid out letter by letter so each matched letter can jiggle and carry its own wave.
private struct WiggleTitle: View {
    let title: [Character]
    let matched: Set<Int>
    let rowID: Int
    let model: WiggleModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(title.enumerated()), id: \.offset) { i, ch in
                let on = matched.contains(i)
                let j = model.jiggle(row: rowID, index: i)
                Text(String(ch))
                    .foregroundStyle(on ? WiggleMatchSearch.accent : Color.primary)
                    .scaleEffect(j.scale, anchor: .bottom)
                    .offset(y: j.offsetY)
                    // After the offset, so the underline stays put while the letter bounces.
                    .overlay(alignment: .bottom) {
                        if on {
                            WaveLine(amplitude: model.amplitude, time: model.time, letterIndex: i)
                                .frame(height: 2 * WaveUnderline.maxAmplitude + 2 * WaveUnderline.lineWidth)
                                .offset(y: 5)
                        }
                    }
            }
        }
        .font(.body)
        .lineLimit(1)
    }
}

/// The sampled sine underline for one letter (straight when the amplitude is 0).
private struct WaveLine: View {
    let amplitude: Double
    let time: Double
    let letterIndex: Int

    var body: some View {
        Canvas { ctx, size in
            let mid = Double(size.height) / 2
            let pts = WaveUnderline.samples(width: Double(size.width), amplitude: amplitude, time: time, letterIndex: letterIndex)
            var path = Path()
            for (k, p) in pts.enumerated() {
                let q = CGPoint(x: p.x, y: mid + p.y)
                if k == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            ctx.stroke(path, with: .color(WiggleMatchSearch.accent),
                       style: StrokeStyle(lineWidth: WaveUnderline.lineWidth, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Owns the model and maps wall-clock dates (timeline frames and keystrokes) to model time.
final class WiggleEngine {
    var model: WiggleModel
    private var origin: Date?

    init(rows: [SettingsRow]) { model = WiggleModel(rows: rows) }

    private func seconds(_ date: Date) -> Double {
        if origin == nil { origin = date }
        return date.timeIntervalSince(origin!)
    }

    func frame(at date: Date, reduceMotion: Bool) -> WiggleModel {
        model.config.reduceMotion = reduceMotion
        model.advance(to: seconds(date))
        return model
    }

    func setQuery(_ q: String, at date: Date) { model.setQuery(q, at: seconds(date)) }
}

#Preview {
    WiggleMatchSearch()
}
#endif
