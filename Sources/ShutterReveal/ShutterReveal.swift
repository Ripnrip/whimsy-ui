//  ShutterReveal.swift
//  ShutterReveal
//
//  A camera-iris reveal: N dark metallic blades swirl open with a springy overshoot (the
//  content scales from 0.96 to 1), close with a quick snap, and give a light haptic when
//  they shut. When they move fast, faint rotated ghost copies add motion blur. The iris
//  geometry and springs live in ShutterRevealCore; this file drives and draws them.

#if canImport(SwiftUI)
import SwiftUI
import ShutterRevealCore

public extension View {
    /// Covers this view with an N-blade camera iris that opens while `isOpen` is `true`.
    ///
    /// - Parameters:
    ///   - isOpen: open or closed. Changes animate: opening is springy, closing is a snap.
    ///   - blades: blade count (minimum 3).
    ///   - response: opening spring response in seconds (closing uses 55% of it).
    ///
    /// The blades fill this view's bounds. To match a rounded card, apply `.clipShape(...)`
    /// after this modifier so it clips the blades too.
    func shutterReveal(isOpen: Binding<Bool>, blades: Int = 6, response: Double = 0.45) -> some View {
        modifier(ShutterRevealModifier(isOpen: isOpen, blades: blades, response: response, tapToToggle: false))
    }

    /// Same as `shutterReveal(isOpen:blades:response:)`, plus tap anywhere on the view to toggle.
    func shutterRevealOnTap(isOpen: Binding<Bool>, blades: Int = 6, response: Double = 0.45) -> some View {
        modifier(ShutterRevealModifier(isOpen: isOpen, blades: blades, response: response, tapToToggle: true))
    }
}

struct ShutterRevealModifier: ViewModifier {
    @Binding var isOpen: Bool
    let blades: Int
    let response: Double
    let tapToToggle: Bool

    @State private var engine = ShutterEngine()
    @State private var isAnimating = false
    /// Close haptics for the Reduce Motion crossfade (the spring path counts its own).
    @State private var crossfadeCloses = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !isAnimating || reduceMotion)) { timeline in
            let frame = engine.frame(at: timeline.date)
            content
                .scaleEffect(reduceMotion ? 1 : 0.96 + 0.04 * min(frame.progress, 1.15))
                .accessibilityHidden(!isOpen)
                .overlay {
                    ShutterBlades(
                        bladeCount: blades,
                        progress: reduceMotion ? 0 : frame.progress,
                        velocity: reduceMotion ? 0 : frame.velocity
                    )
                    // Reduce Motion: no swirl, the closed iris simply crossfades.
                    .opacity(reduceMotion ? (isOpen ? 0 : 1) : 1)
                    .animation(reduceMotion ? .easeInOut(duration: 0.25) : nil, value: isOpen)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Shutter closed"))
                    .accessibilityHint(Text("Double-tap to open."))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { isOpen = true }
                    .accessibilityHidden(isOpen)
                }
                .sensoryFeedback(trigger: frame.closeEvents) { old, new in
                    new > old ? .impact(weight: .light) : nil
                }
                .onChange(of: frame.isSettled) { _, settled in
                    if settled { isAnimating = false }
                }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: crossfadeCloses)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded { isOpen.toggle() },
            including: tapToToggle ? .all : .subviews
        )
        .accessibilityAction(named: isOpen ? Text("Close shutter") : Text("Open shutter")) {
            isOpen.toggle()
        }
        .onChange(of: isOpen, initial: true) { old, new in
            if old == new {
                // First appearance: start in the bound state, no animation.
                engine.reset(isOpen: new, response: response)
                return
            }
            engine.setOpen(new, response: response, animated: !reduceMotion)
            if reduceMotion {
                if !new { crossfadeCloses &+= 1 }
            } else {
                isAnimating = !engine.motion.isSettled
            }
        }
    }
}

// MARK: - Engine

struct ShutterFrame {
    var progress: Double
    var velocity: Double
    var closeEvents: Int
    var isSettled: Bool
}

/// Holds the spring outside SwiftUI's dependency tracking. The TimelineView redraws every
/// frame, and stepping to the same date twice is a no-op, so extra body evaluations don't matter.
final class ShutterEngine {
    private(set) var motion = ApertureMotion()
    private var response = 0.45
    private var lastDate: Date?

    func reset(isOpen: Bool, response: Double) {
        self.response = response
        motion = ApertureMotion(isOpen: isOpen, response: response)
        lastDate = nil
    }

    func setOpen(_ open: Bool, response: Double, animated: Bool) {
        if response != self.response {
            self.response = response
            motion.setResponse(response) // keeps position, velocity and the close count
        }
        motion.setOpen(open, animated: animated)
        lastDate = nil
    }

    func frame(at date: Date) -> ShutterFrame {
        if let lastDate { motion.step(dt: date.timeIntervalSince(lastDate)) }
        lastDate = date
        return ShutterFrame(
            progress: motion.drawableProgress,
            velocity: motion.velocity,
            closeEvents: motion.closeEvents,
            isSettled: motion.isSettled
        )
    }
}

// MARK: - Blades

/// Draws the iris over its whole bounds: dark metallic blades shaded by orientation, a
/// subtle highlight on each aperture edge, a soft seam where one blade overlaps the next,
/// and faint motion-blur ghosts while the blades are moving fast.
struct ShutterBlades: View {
    let bladeCount: Int
    let progress: Double
    let velocity: Double

    var body: some View {
        Canvas { context, size in
            let geometry = IrisGeometry(bladeCount: bladeCount, width: Double(size.width), height: Double(size.height))
            // Fully open and at rest: the blades are all outside the bounds.
            if geometry.apothem(progress: progress) >= geometry.radius && abs(velocity) < 1e-3 { return }

            let blades = geometry.blades(progress: progress)
            for blade in blades {
                drawBlade(blade, geometry: geometry, in: &context)
            }

            // Motion blur: faint copies of where the blades just were, rotated back by ω·Δt.
            for ghost in MotionBlur.ghosts(progress: progress, velocity: velocity, geometry: geometry) {
                var ghostContext = context
                ghostContext.opacity = ghost.opacity
                for blade in geometry.blades(progress: ghost.progress, rotation: ghost.rotation) {
                    ghostContext.fill(Self.path(blade.polygon), with: .color(Color(white: 0.09)))
                    ghostContext.stroke(edgePath(blade), with: .color(.white.opacity(0.2)), lineWidth: 1)
                }
            }
        }
    }

    private func drawBlade(_ blade: Blade, geometry: IrisGeometry, in context: inout GraphicsContext) {
        let shape = Self.path(blade.polygon)
        // Key light from the top-left (y-down): blades facing it read a little brighter.
        let lit = 0.5 + 0.5 * cos(blade.angle - (-3 * Double.pi / 4))
        let outward = blade.apex + Vec2.unit(blade.angle) * geometry.radius
        context.fill(
            shape,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(white: 0.10 + 0.10 * lit), location: 0),
                    .init(color: Color(white: 0.24 + 0.16 * lit), location: 0.42),
                    .init(color: Color(white: 0.13 + 0.08 * lit), location: 0.7),
                    .init(color: Color(white: 0.06 + 0.06 * lit), location: 1),
                ]),
                startPoint: blade.apex.cgPoint,
                endPoint: outward.cgPoint
            )
        )
        // Seam with the previous blade: a soft shadow plus a hairline highlight, which reads
        // as one blade overlapping the next.
        var seam = Path()
        seam.move(to: blade.apex.cgPoint)
        seam.addLine(to: (blade.apex + blade.trailing * geometry.radius * 3).cgPoint)
        var clipped = context
        clipped.clip(to: shape)
        clipped.stroke(seam, with: .color(.black.opacity(0.55)), lineWidth: 5)
        clipped.stroke(seam, with: .color(.white.opacity(0.10)), lineWidth: 0.75)
        // Aperture edge highlight (the polished leading edge).
        context.stroke(edgePath(blade), with: .color(.white.opacity(0.32)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
    }

    private func edgePath(_ blade: Blade) -> Path {
        var p = Path()
        p.move(to: blade.apex.cgPoint)
        p.addLine(to: blade.edgeEnd.cgPoint)
        return p
    }

    static func path(_ polygon: [Vec2]) -> Path {
        var p = Path()
        guard let first = polygon.first else { return p }
        p.move(to: first.cgPoint)
        for v in polygon.dropFirst() { p.addLine(to: v.cgPoint) }
        p.closeSubpath()
        return p
    }
}

private extension Vec2 {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: - Preview

/// A photo-like sunset card made of gradients.
private struct SunsetPhoto: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.14, green: 0.11, blue: 0.36),
                    Color(red: 0.62, green: 0.25, blue: 0.52),
                    Color(red: 0.98, green: 0.47, blue: 0.42),
                    Color(red: 1.0, green: 0.78, blue: 0.47),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 1, green: 0.97, blue: 0.82), Color(red: 1, green: 0.8, blue: 0.5).opacity(0)],
                        center: .center, startRadius: 0, endRadius: w * 0.3
                    ))
                    .frame(width: w * 0.6, height: w * 0.6)
                    .position(x: w * 0.62, y: h * 0.62)
                Ridge(peaks: [0.78, 0.52, 0.66, 0.44, 0.6, 0.5, 0.72])
                    .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.2, blue: 0.42), Color(red: 0.2, green: 0.1, blue: 0.27)], startPoint: .top, endPoint: .bottom))
                    .frame(height: h * 0.42)
                    .position(x: w / 2, y: h - h * 0.21)
                Ridge(peaks: [0.66, 0.82, 0.58, 0.74, 0.62, 0.86])
                    .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.08, blue: 0.2), Color(red: 0.06, green: 0.03, blue: 0.09)], startPoint: .top, endPoint: .bottom))
                    .frame(height: h * 0.3)
                    .position(x: w / 2, y: h - h * 0.15)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Golden hour").font(.title2.bold())
                Text("Lake Tahoe · 7:42 PM").font(.subheadline).opacity(0.85)
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
            .padding(20)
        }
    }
}

/// A mountain ridge; `peaks` are relative heights from the bottom (0...1) across the width.
private struct Ridge: Shape {
    var peaks: [Double]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for (i, peak) in peaks.enumerated() {
            let x = rect.minX + rect.width * Double(i) / Double(max(peaks.count - 1, 1))
            p.addLine(to: CGPoint(x: x, y: rect.maxY - rect.height * peak))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct ShutterRevealDemo: View {
    @State private var isOpen = false

    var body: some View {
        VStack(spacing: 24) {
            SunsetPhoto()
                .frame(width: 320, height: 420)
                .shutterRevealOnTap(isOpen: $isOpen)
                .clipShape(.rect(cornerRadius: 28))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 10)
            Text(isOpen ? "Tap the photo to close" : "Tap the shutter to reveal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(isOpen ? "Close" : "Open") { isOpen.toggle() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview("Shutter Reveal") {
    ShutterRevealDemo()
}
#endif
