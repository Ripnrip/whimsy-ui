//
//  RotaryDialPasscode.swift
//  RotaryDialPasscode
//
//  A four-digit lock drawn as a rotary phone dial. Drag a finger hole clockwise to the
//  finger stop and let go: the wheel springs home, a tick marks each number that passed
//  the stop, and the digit drops into the row of dots. The fourth digit morphs the dial
//  into a check badge when the code matches, or shakes it and then becomes a keypad when
//  it doesn't. Reduce Motion snaps the wheel back and tints it instead of spinning or shaking.
//  The angle, the detents, the spring, the entry and the shake all live in RotaryDialCore.

#if canImport(SwiftUI)
import SwiftUI
import RotaryDialCore

/// A rotary dial that takes a four-digit passcode.
///
/// ```swift
/// RotaryDialPasscode(code: "5216") { unlock() }
/// ```
public struct RotaryDialPasscode: View {
    private let onUnlock: () -> Void
    private let resetToken: Int

    @State private var model: RotaryDialModel
    @State private var lastDate: Date?
    @State private var tickPulse = 0
    @State private var springPulse = 0
    @State private var wrongPulse = 0
    @State private var unlockPulse = 0
    @Namespace private var plateSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(code: String = RotaryDialTuning.defaultCode, resetToken: Int = 0, onUnlock: @escaping () -> Void = {}) {
        self.onUnlock = onUnlock
        self.resetToken = resetToken
        _model = State(initialValue: RotaryDialModel(code: code))
    }

    public var body: some View {
        TimelineView(.animation(paused: model.isSettled)) { timeline in
            ZStack {
                background
                title
                dots
                caption
                plates
                dialChrome
                flyingDigits
                if model.keypadOpacity > 0.02 { keypad }
                if model.badgeOpacity > 0.02 { badgeMark }
                if model.face == .dial {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drag)
                }
            }
            .frame(width: RotaryDialTuning.canvasWidth, height: RotaryDialTuning.canvasHeight)
            .onChange(of: timeline.date) { _, now in advance(to: now) }
        }
        .frame(width: RotaryDialTuning.canvasWidth, height: RotaryDialTuning.canvasHeight)
        .sensoryFeedback(.selection, trigger: tickPulse)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.82), trigger: springPulse)
        .sensoryFeedback(.error, trigger: wrongPulse)
        .sensoryFeedback(.success, trigger: unlockPulse)
        .onAppear { model.setReduceMotion(reduceMotion) }
        .onChange(of: reduceMotion) { _, on in model.setReduceMotion(on) }
        .onChange(of: resetToken) { _, _ in
            model.reset()
            model.setReduceMotion(reduceMotion)
            lastDate = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rotary passcode")
        .accessibilityValue(model.accessibilityValue)
        .accessibilityHint(model.phase == .unlocked
            ? "Unlocked"
            : "Drag a number to the finger stop, or use a digit action")
        .accessibilityAction(named: Text("Digit 1")) { commit(1) }
        .accessibilityAction(named: Text("Digit 2")) { commit(2) }
        .accessibilityAction(named: Text("Digit 3")) { commit(3) }
        .accessibilityAction(named: Text("Digit 4")) { commit(4) }
        .accessibilityAction(named: Text("Digit 5")) { commit(5) }
        .accessibilityAction(named: Text("Digit 6")) { commit(6) }
        .accessibilityAction(named: Text("Digit 7")) { commit(7) }
        .accessibilityAction(named: Text("Digit 8")) { commit(8) }
        .accessibilityAction(named: Text("Digit 9")) { commit(9) }
        .accessibilityAction(named: Text("Digit 0")) { commit(0) }
        .accessibilityAction(named: Text("Delete")) { send(model.deleteDigit()) }
    }

    // MARK: interaction

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let point = Vec2(value.location.x, value.location.y)
                if model.phase != .dragging {
                    send(model.beginDrag(at: point))
                } else {
                    send(model.updateDrag(at: point))
                }
            }
            .onEnded { _ in
                send(model.release())
            }
    }

    private func advance(to now: Date) {
        defer { lastDate = now }
        guard let last = lastDate else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0, dt < 0.05 else { return }
        send(model.step(dt))
    }

    private func commit(_ digit: Int) {
        let before = model.entered.count
        send(model.enterDigit(digit))
        if model.entered.count > before {
            announce(RotaryDialTuning.enteredAnnouncement(model.entered.count))
        }
    }

    private func send(_ events: [RotaryDialEvent]) {
        var ticks = 0
        for event in events {
            switch event {
            case .tick:
                ticks += 1
            case .springBack:
                springPulse += 1
            case .wrong:
                wrongPulse += 1
                announce(RotaryDialTuning.wrongAnnouncement)
            case .unlocked:
                unlockPulse += 1
                announce(RotaryDialTuning.unlockedAnnouncement)
                onUnlock()
            case .committed, .rejected, .deleted, .morphedKeypad:
                break
            }
        }
        if ticks > 0 { tickPulse += ticks }
    }

    private func announce(_ text: String) {
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: chrome

    private var background: some View {
        LinearGradient(
            colors: [
                rgb(RotaryDialPalette.liftR, RotaryDialPalette.liftG, RotaryDialPalette.liftB),
                rgb(RotaryDialPalette.groundR, RotaryDialPalette.groundG, RotaryDialPalette.groundB),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .accessibilityHidden(true)
    }

    private var title: some View {
        Text("ENTER PASSCODE")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .tracking(3.2)
            .foregroundStyle(paper.opacity(0.72))
            .position(x: RotaryDialTuning.centerX, y: 86)
            .accessibilityHidden(true)
    }

    private var dots: some View {
        ForEach(0..<RotaryDialTuning.digitCount, id: \.self) { slot in
            ZStack {
                Circle()
                    .strokeBorder(paper.opacity(0.45), lineWidth: 1.5)
                if model.dotFilled(slot: slot) {
                    Circle().fill(ink)
                    Text("\(model.digits[slot].digit)")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(paper)
                }
            }
            .frame(width: RotaryDialTuning.dotRadius * 2, height: RotaryDialTuning.dotRadius * 2)
            .position(point(RotaryDialTuning.dotCenter(slot)))
            .accessibilityHidden(true)
        }
    }

    private var caption: some View {
        Text(model.caption)
            .font(.system(size: 16, weight: .regular, design: .serif))
            .foregroundStyle(paper.opacity(0.86))
            .position(x: RotaryDialTuning.centerX, y: RotaryDialTuning.captionY)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var plates: some View {
        let shake = model.shakeOffset
        if reduceMotion {
            placedPlate(.dial, paper, opacity: model.dialOpacity, shake: shake, matched: false)
            placedPlate(.keypad, paper, opacity: model.keypadOpacity, shake: shake, matched: false)
            placedPlate(.badge, success, opacity: model.badgeOpacity, shake: 0, matched: false)
        } else {
            // .position, not .offset: matchedGeometryEffect reads the laid-out frame.
            Group {
                switch model.face {
                case .dial:
                    placedPlate(.dial, paper, opacity: 1, shake: shake, matched: true)
                case .keypad:
                    placedPlate(.keypad, paper, opacity: 1, shake: shake, matched: true)
                case .badge:
                    placedPlate(.badge, success, opacity: 1, shake: 0, matched: true)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.86), value: model.face)
        }
    }

    private func placedPlate(_ face: RotaryDialFace, _ fill: Color, opacity: Double, shake: Double, matched: Bool) -> some View {
        let shape = RotaryDialPlate.shape(for: face)
        let body = RoundedRectangle(cornerRadius: shape.corner, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: shape.corner, style: .continuous)
                    .fill(error.opacity(0.55 * model.errorTint))
            }
        return Group {
            if matched {
                body.matchedGeometryEffect(id: "lock-plate", in: plateSpace)
                    .frame(width: shape.width, height: shape.height)
            } else {
                body.frame(width: shape.width, height: shape.height)
            }
        }
        .position(x: RotaryDialTuning.centerX + shake, y: RotaryDialTuning.centerY)
        .opacity(opacity)
        .accessibilityHidden(true)
    }

    private var dialChrome: some View {
        Canvas { context, _ in
            drawDial(&context)
        }
        .frame(width: RotaryDialTuning.canvasWidth, height: RotaryDialTuning.canvasHeight)
        .opacity(model.dialOpacity)
        .offset(x: model.shakeOffset)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var flyingDigits: some View {
        ForEach(0..<model.digits.count, id: \.self) { slot in
            if !model.dotFilled(slot: slot) {
                Text("\(model.digits[slot].digit)")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(ink)
                    .frame(width: 36, height: 36)
                    .background(paper, in: Circle())
                    .position(point(model.glyphPoint(slot: slot)))
                    .accessibilityHidden(true)
            }
        }
    }

    private var keypad: some View {
        ForEach(Array(RotaryDialTuning.keyOrder.enumerated()), id: \.offset) { _, key in
            if key >= 0 {
                Button { commit(key) } label: { keyFace("\(key)") }
                    .buttonStyle(.plain)
                    .position(point(RotaryDialTuning.keyCenter(digit: key)))
            } else if key == -2 {
                Button { send(model.deleteDigit()) } label: { keyFace("del") }
                    .buttonStyle(.plain)
                    .position(point(RotaryDialTuning.keyCenter(digit: -2)))
            }
        }
        .opacity(model.keypadOpacity)
        .allowsHitTesting(model.phase == .keypad)
        .accessibilityHidden(true)
    }

    private func keyFace(_ label: String) -> some View {
        Text(label)
            .font(.system(size: label == "del" ? 16 : 28, weight: .regular, design: .serif))
            .foregroundStyle(paper)
            .frame(width: RotaryDialTuning.keySize, height: RotaryDialTuning.keySize)
            .background(ink, in: Circle())
    }

    private var badgeMark: some View {
        Path { path in
            path.move(to: CGPoint(x: RotaryDialTuning.centerX - 28, y: RotaryDialTuning.centerY + 2))
            path.addLine(to: CGPoint(x: RotaryDialTuning.centerX - 6, y: RotaryDialTuning.centerY + 26))
            path.addLine(to: CGPoint(x: RotaryDialTuning.centerX + 34, y: RotaryDialTuning.centerY - 24))
        }
        .stroke(paper, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        .opacity(model.badgeOpacity)
        .accessibilityHidden(true)
    }

    // MARK: canvas dial

    private func drawDial(_ context: inout GraphicsContext) {
        let center = CGPoint(x: RotaryDialTuning.centerX, y: RotaryDialTuning.centerY)
        let ring = Path(ellipseIn: CGRect(
            x: center.x - RotaryDialTuning.outerRadius + 8,
            y: center.y - RotaryDialTuning.outerRadius + 8,
            width: (RotaryDialTuning.outerRadius - 8) * 2,
            height: (RotaryDialTuning.outerRadius - 8) * 2))
        context.stroke(ring, with: .color(brass.opacity(0.9)), lineWidth: 3)

        let stop = RotaryDialMath.pointOnOrbit(RotaryDialTuning.stopAngle, radius: RotaryDialTuning.outerRadius - 10)
        let peg = CGRect(x: stop.x - 13, y: stop.y - 13, width: 26, height: 26)
        context.fill(Path(ellipseIn: peg), with: .color(brass))
        context.stroke(Path(ellipseIn: peg), with: .color(ink), lineWidth: 2)

        for digit in 0..<RotaryDialTuning.holeCount {
            let at = model.holeCenter(digit)
            let rect = CGRect(x: at.x - RotaryDialTuning.holeRadius, y: at.y - RotaryDialTuning.holeRadius,
                              width: RotaryDialTuning.holeRadius * 2, height: RotaryDialTuning.holeRadius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(rgb(RotaryDialPalette.holeR, RotaryDialPalette.holeG, RotaryDialPalette.holeB)))
            if model.grabbed == digit {
                context.stroke(Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)), with: .color(brass), lineWidth: 2)
            }
            context.draw(
                Text("\(digit)")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundColor(paper),
                at: CGPoint(x: at.x, y: at.y)
            )
        }

        let hub = CGRect(x: center.x - RotaryDialTuning.hubRadius, y: center.y - RotaryDialTuning.hubRadius,
                         width: RotaryDialTuning.hubRadius * 2, height: RotaryDialTuning.hubRadius * 2)
        context.fill(Path(ellipseIn: hub), with: .color(brass))
        let mark = RotaryDialMath.pointOnOrbit(-Double.pi / 2 + model.rotation, radius: RotaryDialTuning.hubRadius - 6)
        let markInner = RotaryDialMath.pointOnOrbit(-Double.pi / 2 + model.rotation, radius: RotaryDialTuning.hubRadius - 14)
        var hand = Path()
        hand.move(to: CGPoint(x: markInner.x, y: markInner.y))
        hand.addLine(to: CGPoint(x: mark.x, y: mark.y))
        context.stroke(hand, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    // MARK: colour

    private var paper: Color { rgb(RotaryDialPalette.paperR, RotaryDialPalette.paperG, RotaryDialPalette.paperB) }
    private var ink: Color { rgb(RotaryDialPalette.inkR, RotaryDialPalette.inkG, RotaryDialPalette.inkB) }
    private var brass: Color { rgb(RotaryDialPalette.brassR, RotaryDialPalette.brassG, RotaryDialPalette.brassB) }
    private var success: Color { rgb(RotaryDialPalette.successR, RotaryDialPalette.successG, RotaryDialPalette.successB) }
    private var error: Color { rgb(RotaryDialPalette.errorR, RotaryDialPalette.errorG, RotaryDialPalette.errorB) }

    private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r, green: g, blue: b)
    }

    private func point(_ value: Vec2) -> CGPoint { CGPoint(x: value.x, y: value.y) }
}

/// The gallery page: the dial, the code it expects, and a reset.
public struct RotaryDialPasscodeDemo: View {
    @State private var resetToken = 0
    @State private var unlocks = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            RotaryDialPasscode(code: "5216", resetToken: resetToken) { unlocks += 1 }
            HStack(spacing: 20) {
                Button("Reset") { resetToken += 1 }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: RotaryDialPalette.brassR, green: RotaryDialPalette.brassG, blue: RotaryDialPalette.brassB))
                    .accessibilityHint("Clears the dial")
                Text(unlocks == 0 ? "Code 5216" : "Unlocked \(unlocks)×")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 12)
    }
}

#Preview("Rotary dial") { RotaryDialPasscodeDemo() }
#endif
