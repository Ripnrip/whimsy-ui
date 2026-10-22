//  FollowBlobHero.swift
//  FollowBlobHero
//
//  A white landing-page hero with a bold headline over a blurred neon blob. The blob follows
//  your finger (or pointer) on a delayed two-stage spring, squashes and stretches along its
//  velocity with its area preserved, wobbles with slow travelling lobes, and idles on a lazy
//  orbit when you let go. Its colour is a 3 × 3 MeshGradient on iOS 18 / macOS 15, falling back
//  to nine soft circles at the same control points on iOS 17 / macOS 14. Palette chips
//  crossfade the colours. Chase, morph, mesh and palettes live in FollowBlobCore.

#if canImport(SwiftUI)
import SwiftUI
import FollowBlobCore

/// A hero section whose gradient blob chases your finger.
///
/// ```swift
/// FollowBlobHero()
/// FollowBlobHero(headline: "Ship delightful apps.", subhead: "…", primary: "Start free") { signUp() }
/// ```
public struct FollowBlobHero: View {
    private let eyebrow: String
    private let headline: String
    private let subhead: String
    private let primary: String
    private let secondary: String
    private let onPrimary: () -> Void
    private let onSecondary: () -> Void

    @State private var engine = BlobEngine()
    @State private var palette = 0
    @State private var isAnimating = true
    @State private var blobOrigin: CGPoint = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(eyebrow: String = "New in motion",
                headline: String = "Interfaces that move with your finger.",
                subhead: String = "A hero that follows you around and melts into colour, built entirely from springs.",
                primary: String = "Get started", secondary: String = "See it live",
                onPrimary: @escaping () -> Void = {}, onSecondary: @escaping () -> Void = {}) {
        self.eyebrow = eyebrow; self.headline = headline; self.subhead = subhead
        self.primary = primary; self.secondary = secondary; self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white.ignoresSafeArea()
            GeometryReader { proxy in
                TimelineView(.animation(paused: !isAnimating)) { timeline in
                    let frame = engine.frame(at: timeline.date, size: proxy.size, reduceMotion: reduceMotion)
                    BlobLayer(frame: frame)
                        .onChange(of: frame.isResting) { _, resting in
                            if resting && reduceMotion { isAnimating = false }
                        }
                }
                .onAppear { blobOrigin = proxy.frame(in: .global).origin }
                .onChange(of: proxy.frame(in: .global).origin) { _, o in blobOrigin = o }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                copy
                Spacer(minLength: 24)
                chips
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 24)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in follow(v.location) }
                .onEnded { _ in follow(nil) }
        )
        #if os(macOS)
        .onContinuousHover(coordinateSpace: .global) { phase in
            switch phase {
            case .active(let p): follow(p)
            case .ended: follow(nil)
            }
        }
        #endif
        .onChange(of: reduceMotion) { _, _ in isAnimating = true }
        .sensoryFeedback(.selection, trigger: palette)
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(white: 0.35))
            Text(headline)
                .font(.system(size: 40, weight: .bold))
                .tracking(-1)
                .foregroundStyle(.black)
                .fixedSize(horizontal: false, vertical: true)
            Text(subhead)
                .font(.system(size: 19))
                .foregroundStyle(Color(white: 0.25))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(action: onPrimary) {
                    Text("\(primary)  →")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 18).frame(height: 44)
                        .background(.black, in: Capsule())
                        .foregroundStyle(.white)
                }
                Button(action: onSecondary) {
                    Text(secondary)
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 18).frame(height: 44)
                        .overlay(Capsule().strokeBorder(Color(white: 0.8), lineWidth: 1))
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    private var chips: some View {
        HStack(spacing: 8) {
            ForEach(Array(BlobPalette.all.enumerated()), id: \.offset) { i, p in
                Button {
                    palette = i
                    engine.setPalette(i)
                    isAnimating = true
                } label: {
                    Text(p.name)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 16).frame(height: 36)
                        .background(i == palette ? Color.black : Color.white, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(white: i == palette ? 0 : 0.85), lineWidth: 1))
                        .foregroundStyle(i == palette ? Color.white : Color.black)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.name) colours")
                .accessibilityAddTraits(i == palette ? .isSelected : [])
            }
        }
    }

    private func follow(_ global: CGPoint?) {
        engine.setFinger(global.map { CGPoint(x: $0.x - blobOrigin.x, y: $0.y - blobOrigin.y) })
        isAnimating = true
    }
}

// MARK: - Blob

struct BlobFrame {
    var center: CGPoint
    /// Outline points relative to the centre.
    var outline: [CGPoint]
    /// Mesh control points in unit space.
    var mesh: [SIMD2<Float>]
    var colors: [Color]
    var isResting: Bool
}

struct BlobLayer: View {
    let frame: BlobFrame
    /// The gradient's square; big enough for the most stretched outline (1.45 × 1.14 × 130 pt).
    static let box: CGFloat = 440
    static let blur: CGFloat = 44

    var body: some View {
        fill
            .frame(width: Self.box, height: Self.box)
            .mask(BlobOutline(points: frame.outline))
            .blur(radius: Self.blur)
            .opacity(0.92)
            .position(frame.center)
    }

    @ViewBuilder private var fill: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            MeshGradient(width: 3, height: 3, points: frame.mesh, colors: frame.colors)
        } else {
            // iOS 17 / macOS 14: nine soft spots at the same control points.
            ZStack {
                ForEach(0..<9, id: \.self) { i in
                    Circle()
                        .fill(frame.colors[i])
                        .frame(width: Self.box * 0.6, height: Self.box * 0.6)
                        .position(x: CGFloat(frame.mesh[i].x) * Self.box, y: CGFloat(frame.mesh[i].y) * Self.box)
                }
            }
            .blur(radius: 36)
        }
    }
}

/// A closed curve through the outline's midpoints (each sample is a quadratic control point).
struct BlobOutline: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        func p(_ i: Int) -> CGPoint { let q = points[i % points.count]; return CGPoint(x: c.x + q.x, y: c.y + q.y) }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        path.move(to: mid(p(0), p(1)))
        for i in 1...points.count { path.addQuadCurve(to: mid(p(i), p(i + 1)), control: p(i)) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Engine

/// Owns the model outside SwiftUI's dependency tracking; the TimelineView steps it by date.
final class BlobEngine {
    private var model = FollowBlobModel(size: Vec2(393, 852))
    private var lastDate: Date?

    func setFinger(_ p: CGPoint?) { model.setFinger(p.map { Vec2(Double($0.x), Double($0.y)) }) }
    func setPalette(_ i: Int) { model.setPalette(i) }

    func frame(at date: Date, size: CGSize, reduceMotion: Bool) -> BlobFrame {
        if model.reduceMotion != reduceMotion { model.reduceMotion = reduceMotion }
        model.setSize(Vec2(Double(size.width), Double(size.height)))
        if let lastDate { model.step(date.timeIntervalSince(lastDate)) }
        lastDate = date
        let resting = model.chase.isSettled(at: model.target) && model.paletteProgress >= 1
        if resting && reduceMotion { lastDate = nil }
        return BlobFrame(
            center: CGPoint(x: model.center.x, y: model.center.y),
            outline: model.outline().map { CGPoint(x: $0.x, y: $0.y) },
            mesh: model.meshPoints.map { SIMD2(Float($0.x), Float($0.y)) },
            colors: model.meshColors.map { Color(red: $0.r, green: $0.g, blue: $0.b) },
            isResting: resting)
    }
}

// MARK: - Preview

#Preview("Follow Blob Hero") {
    FollowBlobHero()
}
#endif
