//
//  ReededGlassSyncHero.swift
//  ReededGlassSyncHero
//
//  A sync hero for Halo Vault. Eleven horizontal slats of reeded glass sit on a deep
//  indigo field. Behind them an aurora of cobalt, teal and lime — a MeshGradient on
//  iOS 18 / macOS 15, blurred circles before that — grows from a small core in the
//  middle five slats to the full width. Each slat masks the light with its own blur,
//  sideways offset and a slight rotation3DEffect, and keeps a 1 pt lit top edge.
//  The percentage rolls with numericText. At 100% the label becomes "All synced"
//  and one soft haptic fires. Tip the phone and the slats wobble; pass roll and pitch
//  to drive that without CoreMotion. Reduce Motion fades the finished aurora and
//  does not wobble.
//  Spread, reeds, rounding, the label and the haptic live in SlatSyncCore.

#if canImport(SwiftUI)
import SwiftUI
import SlatSyncCore
#if canImport(CoreMotion)
import CoreMotion
#endif

/// A reeded-glass sync hero.
///
/// ```swift
/// ReededGlassSyncHero(progress: $progress)
/// ReededGlassSyncHero(progress: $progress, roll: 0.1, pitch: -0.05, useDeviceMotion: false)
/// ```
///
/// `progress` runs from 0 to 1. VoiceOver reads it as a progress indicator:
/// "Syncing, 42 percent" while it is underway, and "All synced" at 100%.
/// Pass `useDeviceMotion: false` to ignore the accelerometer. `roll` and `pitch`
/// are radians and are used only when device motion is off, so a preview can inject a tilt.
public struct ReededGlassSyncHero: View {
    @Binding private var progress: Double
    private let title: String
    private let subtitle: String
    private let detail: String
    private let roll: Double
    private let pitch: Double
    private let useDeviceMotion: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motionRoll = 0.0
    @State private var motionPitch = 0.0
    @State private var hapticTick = 0

    public init(progress: Binding<Double>,
                title: String = SlatSyncTuning.title,
                subtitle: String = SlatSyncTuning.subtitle,
                detail: String = SlatSyncTuning.detail,
                roll: Double = 0,
                pitch: Double = 0,
                useDeviceMotion: Bool = true) {
        _progress = progress
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.roll = roll
        self.pitch = pitch
        self.useDeviceMotion = useDeviceMotion
    }

    public var body: some View {
        let attitude = currentAttitude
        let scene = SlatSyncScene.make(progress: progress, roll: attitude.roll, pitch: attitude.pitch,
                                       reduceMotion: reduceMotion)
        ZStack(alignment: .topLeading) {
            background
            header
            slats(scene)
            readout(scene)
            cornerMark
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.ignoresSafeArea())
        .accessibilityElement(children: .ignore)
        .accessibilityRepresentation {
            ProgressView(value: Double(scene.percent), total: 100) {
                Text(scene.voiceOver)
            }
        }
        .onChange(of: progress) { old, new in
            if SlatSyncMath.crossedHundred(from: old, to: new) {
                hapticTick += 1
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.55), trigger: hapticTick)
        .onAppear { startMotion() }
        .onDisappear { stopMotion() }
    }

    private var currentAttitude: (roll: Double, pitch: Double) {
        if useDeviceMotion { return (motionRoll, motionPitch) }
        return (roll, pitch)
    }

    private var background: some View {
        LinearGradient(
            colors: [rgb(SlatSyncTuning.backgroundTop), rgb(SlatSyncTuning.backgroundBottom)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(rgb(SlatSyncTuning.muted).opacity(0.85))
        }
        .padding(.leading, 28)
        .padding(.top, 72)
        .accessibilityHidden(true)
    }

    private var cornerMark: some View {
        CornerBrackets()
            .stroke(Color.white.opacity(0.55), lineWidth: 1.2)
            .frame(width: 18, height: 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 28)
            .padding(.top, 74)
            .accessibilityHidden(true)
    }

    private func slats(_ scene: SlatSyncScene) -> some View {
        let stackHeight = SlatSyncTuning.slatHeight * Double(SlatSyncTuning.slatCount)
            + SlatSyncTuning.slatGap * Double(SlatSyncTuning.slatCount - 1)
        return VStack(spacing: SlatSyncTuning.slatGap) {
            ForEach(scene.bands, id: \.index) { band in
                SlatWindow(band: band, stackHeight: stackHeight, reduceMotion: reduceMotion)
            }
        }
        .overlay {
            PlusMark()
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: 16, height: 16)
                .allowsHitTesting(false)
        }
        .padding(.top, SlatSyncTuning.stackTop)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func readout(_ scene: SlatSyncScene) -> some View {
        VStack(spacing: 6) {
            Text("\(scene.percent)%")
                .font(.system(size: 56, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .contentTransition(reduceMotion ? .opacity : .numericText())
                .animation(reduceMotion ? .easeInOut(duration: 0.35) : .snappy(duration: 0.28), value: scene.percent)
            Text(scene.label.rawValue)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(scene.label == .synced ? rgb(SlatSyncTuning.lime) : rgb(SlatSyncTuning.muted))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: reduceMotion ? 0.35 : 0.22), value: scene.label)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(rgb(SlatSyncTuning.muted).opacity(0.7))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 78)
        .accessibilityHidden(true)
    }

    private func rgb(_ color: SlatRGB) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
    }

    private func startMotion() {
        #if os(iOS) && !targetEnvironment(simulator)
        guard useDeviceMotion else { return }
        SlatMotion.shared.start { roll, pitch in
            motionRoll = roll
            motionPitch = pitch
        }
        #endif
    }

    private func stopMotion() {
        #if os(iOS) && !targetEnvironment(simulator)
        SlatMotion.shared.stop()
        #endif
    }
}

/// The gallery page: the hero runs 0 → 1, then Replay plays it again.
public struct ReededGlassSyncHeroDemo: View {
    @State private var progress = 0.0
    @State private var run = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public var body: some View {
        ReededGlassSyncHero(progress: $progress)
            .overlay(alignment: .bottom) {
                Button("Replay") { run += 1 }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(.white.opacity(0.12), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 28)
            }
            .onAppear { play() }
            .onChange(of: run) { _, _ in play() }
    }

    private func play() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { progress = 0 }
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.45)
            : .easeInOut(duration: SlatSyncTuning.demoRun).delay(SlatSyncTuning.demoDelay)
        withAnimation(animation) { progress = 1 }
    }
}

// MARK: - Slat

private struct SlatWindow: View {
    let band: SlatBand
    let stackHeight: Double
    let reduceMotion: Bool

    var body: some View {
        let localY = band.y - SlatSyncTuning.stackTop
        return ZStack {
            RoundedRectangle(cornerRadius: SlatSyncTuning.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.045))
            Color.clear
                .overlay {
                    aurora
                        .frame(width: band.width, height: stackHeight)
                        .offset(x: band.offsetX, y: -localY)
                        .blur(radius: band.blur)
                        .mask(spreadMask.frame(width: band.width, height: stackHeight))
                        .opacity(band.opacity)
                }
                .clipShape(RoundedRectangle(cornerRadius: SlatSyncTuning.cornerRadius, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: SlatSyncTuning.cornerRadius, style: .continuous))
            Rectangle()
                .fill(edgeColor)
                .frame(height: SlatSyncTuning.edgeThickness)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .opacity(band.edge)
        }
        .frame(width: band.width, height: band.height)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : band.tilt), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
    }

    private var spreadMask: some View {
        let half = max(band.spread, 0) / 2
        let feather = min(0.08, half)
        let inner = max(0, 0.5 - half)
        let solid = min(0.5, inner + feather)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: inner),
                .init(color: .white, location: solid),
                .init(color: .white, location: 1 - solid),
                .init(color: .clear, location: 1 - inner),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }

    @ViewBuilder private var aurora: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            MeshGradient(width: 3, height: 3, points: meshPoints, colors: meshColors)
        } else {
            ZStack {
                Circle().fill(rgb(SlatSyncTuning.cobalt)).frame(width: 280, height: 280).offset(y: -stackHeight * 0.32)
                Circle().fill(rgb(SlatSyncTuning.teal)).frame(width: 260, height: 260)
                Circle().fill(rgb(SlatSyncTuning.lime)).frame(width: 280, height: 280).offset(y: stackHeight * 0.32)
            }
            .blur(radius: 28)
        }
    }

    private var meshPoints: [SIMD2<Float>] {
        [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5), SIMD2(0.5, 0.5), SIMD2(1, 0.5),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
        ]
    }

    private var meshColors: [Color] {
        let cobalt = rgb(SlatSyncTuning.cobalt)
        let teal = rgb(SlatSyncTuning.teal)
        let lime = rgb(SlatSyncTuning.lime)
        let hot = Color(red: 0.75, green: 0.95, blue: 1)
        return [cobalt, hot, cobalt, teal, Color.white, teal, lime, lime, lime]
    }

    private var edgeColor: Color {
        Color(red: min(1, band.red + 0.35), green: min(1, band.green + 0.25), blue: min(1, band.blue + 0.2))
    }

    private func rgb(_ color: SlatRGB) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
    }
}

private struct PlusMark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

private struct CornerBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let a = min(rect.width, rect.height) * 0.38
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + a))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + a, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - a, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + a))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - a))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - a, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + a, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - a))
        return path
    }
}

#if os(iOS) && !targetEnvironment(simulator)
/// CoreMotion attitude, shared so a second hero does not start a second manager.
@MainActor
final class SlatMotion {
    static let shared = SlatMotion()
    private let manager = CMMotionManager()
    private var consumers = 0

    func start(_ handler: @escaping @MainActor (Double, Double) -> Void) {
        consumers += 1
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30
        manager.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let attitude = data?.attitude else { return }
            let roll = attitude.roll
            let pitch = attitude.pitch
            MainActor.assumeIsolated { handler(roll, pitch) }
        }
    }

    func stop() {
        consumers = max(0, consumers - 1)
        if consumers == 0 { manager.stopDeviceMotionUpdates() }
    }
}
#endif

#Preview("Reeded glass sync") {
    ReededGlassSyncHeroDemo()
}
#endif
