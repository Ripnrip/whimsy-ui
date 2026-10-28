//  PourOpenMenu.swift
//  PourOpenMenu
//
//  A sort pill that pours open. Tap "Sort: Newest" and the pill melts downward into four options,
//  drawn as metaball drops in a Canvas (blur, then an alpha threshold: the goo filter), staggered so
//  they drip out of the pill, stretch into thin necks and pinch off into separate pills. Pick one and
//  the label crossfades while everything pours back up. While it travels the pill lifts (shadow and a
//  1.04x scale on a sin(progress * pi) curve) and a soft haptic plays on landing. The timeline, drop
//  positions, neck geometry, lift, label fade, selection state machine and events live in PourCore.
//  Reduce Motion swaps all of it for a plain fade.

#if canImport(SwiftUI)
import SwiftUI
import PourCore

/// A "Sort: …" pill that pours open into a goo menu, over a small list it sorts.
///
/// ```swift
/// PourOpenMenu()
/// PourOpenMenu(options: ["Newest", "Oldest", "Popular", "A to Z"], selected: 2)
/// ```
public struct PourOpenMenu: View {
    @State private var engine: PourEngine
    @State private var isAnimating = false
    @State private var haptics = 0
    @State private var sorted = "Newest"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let tint = Color(red: 0.36, green: 0.30, blue: 0.93)
    static let background = LinearGradient(
        colors: [Color(red: 0.96, green: 0.95, blue: 1.0), Color(red: 0.90, green: 0.93, blue: 1.0)],
        startPoint: .top, endPoint: .bottom)

    public init(options: [String] = PourLayout.defaultOptions, selected: Int = 0) {
        let model = PourModel(options: options, selected: selected)
        _engine = State(initialValue: PourEngine(model: model))
        _sorted = State(initialValue: model.options[model.selected])
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Library")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            PourMenuControl(engine: engine, isAnimating: $isAnimating, haptics: $haptics, sorted: $sorted)
                .zIndex(1)                        // the open menu pours over the list
            PourList(order: PourCatalog.sorted(PourCatalog.items, by: sorted))
                .padding(.top, PourMenuControl.pillHeight)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Self.background.ignoresSafeArea())
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: haptics)
    }
}

/// The pill plus its goo menu.
struct PourMenuControl: View {
    let engine: PourEngine
    @Binding var isAnimating: Bool
    @Binding var haptics: Int
    @Binding var sorted: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let pillHeight = PourLayout.pillSize.y
    /// Room around the goo so the blur isn't clipped at the canvas edge.
    static let pad = 24.0

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { timeline in
            let m = engine.frame(at: timeline.date, reduceMotion: reduceMotion)
            let h = PourLayout.height(optionCount: m.options.count)
            let lift = m.lift
            ZStack(alignment: .topLeading) {
                GooCanvas(drops: m.drops, necks: m.necks, reduceMotion: reduceMotion, menuOpacity: m.menuOpacity,
                          lift: lift)
                    .frame(width: PourLayout.width + 2 * Self.pad, height: h + 2 * Self.pad)
                    .offset(x: -Self.pad, y: -Self.pad)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                optionRows(m)
                pillLabel(m)
            }
            .frame(width: PourLayout.width, height: Self.pillHeight, alignment: .topLeading)
            // The pill (not the wider coordinate space) defines the control's size, so it lines up with the title.
            .offset(x: -(PourLayout.width - PourLayout.pillSize.x) / 2)
            .frame(width: PourLayout.pillSize.x, height: Self.pillHeight, alignment: .topLeading)
            // Lift: the whole pour scales about the pill while it travels, and casts a shadow.
            .scaleEffect(PourLift.scale(lift))
            .shadow(color: .black.opacity(PourLift.opacity(lift) * (reduceMotion ? 0 : 1)),
                    radius: PourLift.radius(lift), y: PourLift.offsetY(lift))
            .zIndex(lift > 0 || m.isExpanded ? 1 : 0)
            .onChange(of: m.landings) { _, n in haptics = n }
            .onChange(of: m.isIdle) { _, idle in if idle { isAnimating = false } }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Sort menu")
            .accessibilityAction(.escape) { if m.isExpanded { toggle() } }
        }
    }

    // MARK: Pieces

    private func pillLabel(_ m: PourModel) -> some View {
        let l = m.label
        return Button(action: toggle) {
            ZStack {
                labelText(m.options[l.from]).opacity(l.fromOpacity)
                labelText(m.options[l.to]).opacity(l.toOpacity)
                HStack {
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(m.chevronAngle))
                        .padding(.trailing, 16)
                }
            }
            .foregroundStyle(.white)
            .frame(width: PourLayout.pillSize.x, height: PourLayout.pillSize.y)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .position(x: PourLayout.pillCenter.x, y: PourLayout.pillCenter.y)
        .accessibilityLabel("Sort, \(m.options[m.selected])")
        .accessibilityValue(m.isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(m.isExpanded ? "Closes the sort menu" : "Opens the sort menu")
    }

    private func labelText(_ option: String) -> some View {
        Text("Sort: \(option)")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .padding(.trailing, 12)                 // keep clear of the chevron
    }

    private func optionRows(_ m: PourModel) -> some View {
        ForEach(m.drops, id: \.index) { d in
            let isSelected = d.index == m.selected
            Button { pick(d.index) } label: {
                HStack(spacing: 6) {
                    Text(m.options[d.index])
                    if isSelected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)) }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: PourLayout.dropHalfWidth * 2, height: PourLayout.dropRadius * 2)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(m.config.reduceMotion ? m.menuOpacity : d.labelOpacity)
            .position(x: d.blob.center.x, y: d.blob.center.y)
            .allowsHitTesting(m.acceptsPick && (m.config.reduceMotion ? m.menuOpacity > 0.5 : d.labelOpacity > 0.5))
            .accessibilityHidden(!m.isExpanded)
            .accessibilityLabel(m.options[d.index])
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
    }

    // MARK: Actions

    private func toggle() {
        engine.tapPill(at: Date())
        isAnimating = true
    }

    private func pick(_ i: Int) {
        guard engine.pick(i, at: Date()) else { return }
        isAnimating = true
        let name = engine.model.options[i]
        sorted = name
        AccessibilityNotification.Announcement("Sorted by \(name)").post()
    }
}

/// The metaballs: blobs and necks drawn into a layer, blurred, then cut with an alpha threshold.
private struct GooCanvas: View {
    let drops: [PourDrop]
    let necks: [PourNeck]
    let reduceMotion: Bool
    let menuOpacity: Double
    let lift: Double

    var body: some View {
        Canvas { ctx, _ in
            ctx.translateBy(x: PourMenuControl.pad, y: PourMenuControl.pad)
            if reduceMotion {
                // No goo: separate pills that fade in place.
                fill(&ctx, PourLayout.pillBlob)
                var faded = ctx
                faded.opacity = menuOpacity
                for d in drops { fill(&faded, d.blob) }
            } else {
                var goo = ctx
                // Filters apply last-added first: blur the layer, then threshold the blur.
                goo.addFilter(.alphaThreshold(min: PourLayout.gooThreshold, color: PourOpenMenu.tint))
                goo.addFilter(.blur(radius: PourLayout.gooBlur))
                goo.drawLayer { layer in
                    fill(&layer, PourLayout.pillBlob, color: .black)
                    for d in drops where d.isVisible { fill(&layer, d.blob, color: .black) }
                    for n in necks {
                        var p = Path()
                        for (k, v) in n.polygon.enumerated() {
                            let q = CGPoint(x: v.x, y: v.y)
                            if k == 0 { p.move(to: q) } else { p.addLine(to: q) }
                        }
                        p.closeSubpath()
                        layer.fill(p, with: .color(.black))
                    }
                }
            }
        }
    }

    private func fill(_ ctx: inout GraphicsContext, _ b: PourBlob, color: Color = PourOpenMenu.tint) {
        let r = CGRect(x: b.center.x - b.halfWidth, y: b.center.y - b.radius, width: b.halfWidth * 2, height: b.radius * 2)
        ctx.fill(Path(roundedRect: r, cornerRadius: b.radius, style: .continuous), with: .color(color))
    }
}

/// The sorted list under the menu; rows glide to their new places.
private struct PourList: View {
    let order: [PourItem]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            ForEach(order) { item in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hue: Double(item.id) / 6.5, saturation: 0.45, brightness: 0.95))
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.body.weight(.semibold))
                        Text("\(item.age) days ago · \(item.likes) likes").font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: order.map(\.id))
    }
}

/// Owns the model and maps wall-clock dates (timeline frames and taps) to model time.
final class PourEngine {
    private(set) var model: PourModel
    private var origin: Date?

    init(model: PourModel) { self.model = model }

    private func seconds(_ date: Date) -> Double {
        if origin == nil { origin = date }
        return date.timeIntervalSince(origin!)
    }

    func frame(at date: Date, reduceMotion: Bool) -> PourModel {
        model.config.reduceMotion = reduceMotion
        model.advance(to: seconds(date))
        return model
    }

    func tapPill(at date: Date) { model.tapPill(at: seconds(date)) }
    func pick(_ i: Int, at date: Date) -> Bool { model.pick(i, at: seconds(date)) }
}

#Preview {
    PourOpenMenu()
}
#endif
