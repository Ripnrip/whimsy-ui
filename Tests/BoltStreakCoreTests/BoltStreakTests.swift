import Foundation
import Testing
@testable import BoltStreakCore

private func arcMidpoint(_ points: [Vec2]) -> Vec2 {
    var total = 0.0
    var segments: [(Vec2, Vec2, Double)] = []
    for index in 1..<points.count {
        let length = points[index].distance(to: points[index - 1])
        segments.append((points[index - 1], points[index], length))
        total += length
    }
    var remain = total * 0.5
    for (start, end, length) in segments {
        if remain <= length || end == points[points.count - 1] {
            let u = length > 0 ? remain / length : 0
            return Vec2.lerp(start, end, min(max(u, 0), 1))
        }
        remain -= length
    }
    return points[points.count - 1]
}

@Suite("Bolt path") struct BoltPathTests {
    @Test func theCentrelineIsLocked() {
        let points = BoltPath.normalizedPoints
        #expect(points.count == 6)
        #expect(points[0] == Vec2(0.72, 0.06))
        #expect(points[1] == Vec2(0.30, 0.34))
        #expect(points[2] == Vec2(0.78, 0.44))
        #expect(points[3] == Vec2(0.22, 0.70))
        #expect(points[4] == Vec2(0.58, 0.78))
        #expect(points[5] == Vec2(0.18, 0.94))
    }

    @Test func lengthIsTheSumOfTheSegmentsAndLongerThanTheChord() {
        let points = BoltPath.normalizedPoints
        var sum = 0.0
        for index in 1..<points.count {
            sum += points[index].distance(to: points[index - 1])
        }
        #expect(abs(BoltPath.length - sum) < 1e-12)
        #expect(BoltPath.length > points[0].distance(to: points[5]))
        #expect(BoltPath.length > 1)
        let scaled = BoltRect(x: 3, y: -4, width: 2, height: 2)
        #expect(abs(BoltPath.length(in: scaled) - BoltPath.length * 2) < 1e-9)
    }

    @Test func theHeadSitsOnTheEndsAndTheArcLengthMidpoint() {
        let points = BoltPath.normalizedPoints
        #expect(BoltPath.sample(0) == points[0])
        #expect(BoltPath.sample(1) == points[5])
        #expect(BoltPath.sample(-0.4) == points[0])
        #expect(BoltPath.sample(1.7) == points[5])
        #expect(BoltPath.sample(.nan) == points[0])
        #expect(BoltPath.sample(.infinity) == points[0])
        let mid = BoltPath.sample(0.5)
        let walked = arcMidpoint(points)
        #expect(mid.distance(to: walked) < 1e-12)
        #expect(mid.distance(to: points[0]) > 0.2)
        #expect(mid.distance(to: points[5]) > 0.2)
        #expect(BoltPath.sample(0.5) == BoltPath.sample(0.5))
    }

    @Test func aTallBoltSamplesByItsOwnArcLength() {
        let rect = BoltStreakTuning.weeklyRect
        let scene = BoltPath.sample(progress: 0.5, in: rect)
        let unit = BoltPath.sample(0.5)
        let scaled = Vec2(rect.x + unit.x * rect.width, rect.y + unit.y * rect.height)
        #expect(scene.distance(to: scaled) > 1)
        #expect(BoltPath.sample(progress: 0, in: rect) == BoltPath.scenePoints(in: rect)[0])
        #expect(BoltPath.sample(progress: 1, in: rect) == BoltPath.scenePoints(in: rect)[5])
        #expect(abs(rect.width - 150) < 1e-9)
        #expect(rect.height > rect.width)
    }
}

@Suite("Ignition") struct BoltIgnitionTests {
    @Test func todayTicksOnceAndASecondTapDoesNothing() {
        var model = BoltStreakModel(today: .friday)
        let events = model.igniteToday()
        #expect(events == [.ignited(.friday), .tick])
        #expect(model.completed == [.friday])
        #expect(model.active == .friday)
        #expect(model.dayProgress(.friday) == 0)
        #expect(model.elapsed == 0)
        #expect(model.head(for: .friday) == BoltPath.sample(0))
        #expect(model.headTravels(for: .friday))
        #expect(model.igniteToday().isEmpty)
        #expect(model.ignite(.friday).isEmpty)
        #expect(model.weeklyTarget == 1.0 / 7.0)
        #expect(model.weeklyProgress == 0)
    }

    @Test func dayProgressFollowsTheSmoothstepAndFinishesAtOne() {
        var model = BoltStreakModel(today: .monday)
        #expect(model.ignite(.monday) == [.ignited(.monday), .tick])
        var last = -1.0
        var rose = false
        for step in 1...80 {
            #expect(model.step(1.0 / 60.0).isEmpty)
            let progress = model.dayProgress(.monday)
            #expect(progress + 1e-12 >= last)
            if progress > last + 1e-6 { rose = true }
            last = progress
            if model.active == .monday {
                let elapsed = Double(step) / 60.0
                let eased = WhimsyMath.smoothstep(0, BoltStreakTuning.ignitionDuration, elapsed)
                #expect(abs(progress - eased) < 1e-12)
                #expect(model.head(for: .monday) == BoltPath.sample(progress))
                #expect(model.weeklyProgress == progress / 7.0)
            } else {
                break
            }
        }
        #expect(rose)
        #expect(model.dayProgress(.monday) == 1)
        #expect(model.active == nil)
        #expect(abs(model.weeklyProgress - 1.0 / 7.0) < 1e-12)
        #expect(abs(model.weeklyTarget - model.weeklyProgress) < 1e-12)
        #expect(model.head(for: .monday) == BoltPath.sample(1))
        #expect(!model.headTravels(for: .monday))
    }

    @Test func aSecondDayWaitsThenBurnsAndTheWeekKeepsRising() {
        var model = BoltStreakModel(today: .monday)
        #expect(model.ignite(.monday).count == 2)
        #expect(model.ignite(.wednesday) == [.ignited(.wednesday), .tick])
        #expect(model.queue == [.wednesday])
        #expect(abs(model.weeklyTarget - 2.0 / 7.0) < 1e-12)
        #expect(model.weeklyProgress == 0)
        var previous = 0.0
        var guardCount = 0
        while model.active == .monday && guardCount < 50 {
            #expect(model.step(1.0 / 60.0).isEmpty)
            #expect(model.weeklyProgress + 1e-12 >= previous)
            previous = model.weeklyProgress
            guardCount += 1
        }
        #expect(guardCount == BoltStreakTuning.burnFrames)
        #expect(model.active == .wednesday)
        #expect(model.dayProgress(.monday) == 1)
        #expect(model.dayProgress(.wednesday) == 0)
        #expect(model.queue.isEmpty)
        #expect(model.head(for: .wednesday) == BoltPath.sample(0))
        #expect(model.step(1.0 / 60.0).isEmpty)
        #expect(model.dayProgress(.wednesday) > 0)
        #expect(model.weeklyProgress > 1.0 / 7.0)
        #expect(model.weeklyProgress < 2.0 / 7.0)
    }

    @Test func theSameInputsStayOnTheSamePath() {
        var left = BoltStreakModel(completed: [.monday], today: .thursday)
        var right = BoltStreakModel(completed: [.monday], today: .thursday)
        #expect(left.igniteToday() == right.igniteToday())
        for _ in 0..<24 {
            #expect(left.step(1.0 / 60.0) == right.step(1.0 / 60.0))
            #expect(left.dayProgress(.thursday) == right.dayProgress(.thursday))
            #expect(left.head(for: .thursday) == right.head(for: .thursday))
            #expect(left.glow(for: .thursday) == right.glow(for: .thursday))
            #expect(left.weeklyProgress == right.weeklyProgress)
        }
        #expect(left == right)
        #expect(BoltStreakReel.model(atFrame: 48) == BoltStreakReel.model(atFrame: 48))
    }

    @Test func aLongFrameOnlyAdvancesByTheCap() {
        var model = BoltStreakModel(today: .monday)
        #expect(model.step(.nan).isEmpty)
        #expect(model.step(0).isEmpty)
        #expect(model.step(-0.2).isEmpty)
        #expect(model.ignite(.monday).count == 2)
        #expect(model.step(1).isEmpty)
        #expect(abs(model.elapsed - BoltStreakTuning.maxFrame) < 1e-12)
        #expect(model.dayProgress(.monday) > 0)
        #expect(model.dayProgress(.monday) < 0.2)
    }

    @Test func weeklyTargetIsJustTheSet() {
        #expect(BoltStreakMath.weeklyTarget(completed: [] as [Weekday]) == 0)
        #expect(abs(BoltStreakMath.weeklyTarget(completed: [.monday, .monday, .friday]) - 2.0 / 7.0) < 1e-12)
        #expect(BoltStreakMath.weeklyTarget(completed: Weekday.allCases) == 1)
        let seeded = BoltStreakModel(completed: [.tuesday, .friday], today: .sunday)
        #expect(seeded.dayProgress(.tuesday) == 1)
        #expect(seeded.dayProgress(.monday) == 0)
        #expect(abs(seeded.weeklyProgress - seeded.weeklyTarget) < 1e-12)
        #expect(abs(seeded.weeklyTarget - 2.0 / 7.0) < 1e-12)
        #expect(seeded.head(for: .tuesday) == BoltPath.sample(1))
        #expect(!seeded.needsClock)
    }
}

@Suite("Glow and Reduce Motion") struct BoltGlowTests {
    @Test func thePulseMovesWhileTheBoltIsIgniting() {
        let early = BoltStreakMath.glow(progress: 0.4, elapsed: 0.1, igniting: true, reduceMotion: false)
        let later = BoltStreakMath.glow(progress: 0.4, elapsed: 0.2, igniting: true, reduceMotion: false)
        let steady = BoltStreakMath.glow(progress: 0.4, elapsed: 0.2, igniting: false, reduceMotion: false)
        let reduced = BoltStreakMath.glow(progress: 0.4, elapsed: 0.2, igniting: true, reduceMotion: true)
        #expect(early != later)
        #expect(abs(early - later) > 0.02)
        #expect(abs(steady - BoltStreakTuning.glowSettled * 0.4) < 1e-12)
        #expect(abs(reduced - steady) < 1e-12)
        #expect(BoltStreakMath.glow(progress: 0, elapsed: 0.4, igniting: true, reduceMotion: false) == 0)
        #expect(BoltStreakMath.glow(progress: .nan, elapsed: 0.1, igniting: true, reduceMotion: false) == 0)

        var model = BoltStreakModel(today: .monday)
        #expect(model.ignite(.monday).count == 2)
        for _ in 0..<12 { _ = model.step(1.0 / 60.0) }
        let glow = model.glow(for: .monday)
        let expected = BoltStreakMath.glow(
            progress: model.dayProgress(.monday),
            elapsed: model.elapsed,
            igniting: true,
            reduceMotion: false
        )
        #expect(abs(glow - expected) < 1e-12)
        #expect(model.weeklyGlow > 0)
    }

    @Test func reduceMotionSnapsAndDoesNotTravel() {
        var model = BoltStreakModel(today: .thursday, reduceMotion: true)
        let events = model.igniteToday()
        #expect(events == [.ignited(.thursday), .tick])
        #expect(model.dayProgress(.thursday) == 1)
        #expect(model.active == nil)
        #expect(model.needsClock == false)
        #expect(!model.headTravels(for: .thursday))
        #expect(model.head(for: .thursday) == BoltPath.sample(1))
        #expect(model.weeklyHead == BoltPath.sample(1.0 / 7.0))
        #expect(!model.weeklyHeadTravels)
        let glow = model.glow(for: .thursday)
        let weekly = model.weeklyProgress
        #expect(model.step(0.4).isEmpty)
        #expect(model.step(1.0 / 60.0).isEmpty)
        #expect(model.head(for: .thursday) == BoltPath.sample(1))
        #expect(model.glow(for: .thursday) == glow)
        #expect(model.weeklyProgress == weekly)
        #expect(model.dayProgress(.thursday) == 1)
        #expect(abs(glow - BoltStreakTuning.glowSettled) < 1e-12)
    }

    @Test func turningReduceMotionOnMidBurnParksEveryQueuedDay() {
        var model = BoltStreakModel(today: .monday)
        #expect(model.ignite(.monday).count == 2)
        #expect(model.ignite(.tuesday).count == 2)
        for _ in 0..<10 { _ = model.step(1.0 / 60.0) }
        #expect(model.dayProgress(.monday) > 0)
        #expect(model.dayProgress(.monday) < 1)
        #expect(model.headTravels(for: .monday))
        model.setReduceMotion(true)
        #expect(model.reduceMotion)
        #expect(model.active == nil)
        #expect(model.queue.isEmpty)
        #expect(model.dayProgress(.monday) == 1)
        #expect(model.dayProgress(.tuesday) == 1)
        #expect(model.head(for: .monday) == BoltPath.sample(1))
        #expect(!model.headTravels(for: .monday))
        let glow = model.glow(for: .monday)
        #expect(model.step(0.3).isEmpty)
        #expect(model.glow(for: .monday) == glow)
        #expect(abs(model.weeklyProgress - 2.0 / 7.0) < 1e-12)
        model.setReduceMotion(true)
        #expect(model.dayProgress(.tuesday) == 1)
    }
}

@Suite("Week and voice") struct BoltWeekTests {
    @Test func theBindingAddsInWeekdayOrderAndRemovalGoesDark() {
        var model = BoltStreakModel(today: .friday)
        let events = model.setCompleted([.friday, .monday])
        #expect(events == [.ignited(.monday), .tick, .ignited(.friday), .tick])
        #expect(model.active == .monday)
        #expect(model.queue == [.friday])
        #expect(model.setCompleted([.friday, .monday]).isEmpty)
        let removed = model.setCompleted([.friday])
        #expect(removed.isEmpty)
        #expect(!model.completed.contains(.monday))
        #expect(model.dayProgress(.monday) == 0)
        #expect(model.active == .friday)
        #expect(model.head(for: .friday) == BoltPath.sample(0))
    }

    @Test func labelsAndAKnownSunday() {
        #expect(Weekday.allCases.map(\.label) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(Weekday.monday < Weekday.sunday)
        #expect(Weekday.allCases.contains(.current))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var parts = DateComponents()
        parts.calendar = calendar
        parts.year = 2026
        parts.month = 11
        parts.day = 22
        parts.hour = 15
        let sunday = calendar.date(from: parts)!
        #expect(Weekday.on(sunday, calendar: calendar) == .sunday)
        parts.day = 23
        let monday = calendar.date(from: parts)!
        #expect(Weekday.on(monday, calendar: calendar) == .monday)
        parts.day = 16
        let previousMonday = calendar.date(from: parts)!
        #expect(Weekday.on(previousMonday, calendar: calendar) == .monday)
    }

    @Test func voiceOverNamesTheLitDaysAndToday() {
        let empty = BoltStreakModel(today: .sunday)
        #expect(empty.accessibilityLabel == "Weekly bolt streak")
        #expect(empty.accessibilityValue == "0 of 7 days. No days lit. Sunday is today.")
        #expect(empty.canMarkToday)
        let mid = BoltStreakModel(completed: [.wednesday, .monday], today: .thursday)
        #expect(mid.accessibilityValue == "2 of 7 days. Monday, Wednesday lit. Thursday is today.")
        var marked = mid
        #expect(marked.igniteToday() == [.ignited(.thursday), .tick])
        #expect(marked.accessibilityValue == "3 of 7 days. Monday, Wednesday, Thursday lit. Thursday is lit.")
        #expect(!marked.canMarkToday)
    }

    @Test func theReelIdlesBurnsAndThenSnaps() {
        #expect(BoltStreakTuning.burnFrames == 39)
        let steps = 39.0 / 60.0
        #expect(steps >= BoltStreakTuning.ignitionDuration)
        #expect(steps - 1.0 / 60.0 < BoltStreakTuning.ignitionDuration)

        let idle = BoltStreakReel.model(at: 0.2)
        #expect(idle.completed.isEmpty)
        #expect(idle.weeklyProgress == 0)
        #expect(idle.weeklyHead == nil)
        #expect(!idle.reduceMotion)

        let midFrame = BoltStreakReel.ignitionFrame(0) + 18
        let mid = BoltStreakReel.model(atFrame: midFrame)
        #expect(mid.active == .monday)
        #expect(mid.headTravels(for: .monday))
        #expect(mid.dayProgress(.monday) > 0.3)
        #expect(mid.dayProgress(.monday) < 0.7)
        let head = mid.head(for: .monday)!
        #expect(head.distance(to: BoltPath.sample(0)) > 0.05)
        #expect(head.distance(to: BoltPath.sample(1)) > 0.05)
        #expect(head == BoltPath.sample(mid.dayProgress(.monday)))
        #expect(mid.weeklyHeadTravels)
        #expect(BoltStreakReel.model(at: Double(midFrame) / 60.0) == mid)

        let three = BoltStreakReel.model(atFrame: BoltStreakReel.ignitionFrame(3) - 4)
        #expect(three.dayProgress(.monday) == 1)
        #expect(three.dayProgress(.tuesday) == 1)
        #expect(three.dayProgress(.wednesday) == 1)
        #expect(three.dayProgress(.thursday) == 0)
        #expect(abs(three.weeklyProgress - 3.0 / 7.0) < 1e-12)
        #expect(abs(three.weeklyTarget - 3.0 / 7.0) < 1e-12)

        let today = BoltStreakReel.model(atFrame: BoltStreakReel.ignitionFrame(6) + 18)
        #expect(today.today == .sunday)
        #expect(today.active == .sunday)
        #expect(today.headTravels(for: .sunday))
        #expect(today.dayProgress(.saturday) == 1)
        #expect(today.weeklyProgress > 6.0 / 7.0)
        #expect(today.weeklyProgress < 1)

        let full = BoltStreakReel.model(atFrame: BoltStreakReel.reduceStart - 8)
        #expect(full.completed.count == 7)
        #expect(full.weeklyProgress == 1)
        #expect(full.active == nil)
        #expect(!full.reduceMotion)

        let reduced = BoltStreakReel.model(atFrame: BoltStreakReel.reduceStart + BoltStreakReel.reduceLead + 8)
        #expect(reduced.reduceMotion)
        #expect(reduced.dayProgress(.monday) == 1)
        #expect(reduced.dayProgress(.wednesday) == 1)
        #expect(reduced.dayProgress(.thursday) == 0)
        #expect(!reduced.headTravels(for: .monday))
        #expect(reduced.head(for: .monday) == BoltPath.sample(1))
        var held = reduced
        #expect(held.step(0.25).isEmpty)
        #expect(held.head(for: .monday) == reduced.head(for: .monday))
        #expect(held.glow(for: .monday) == reduced.glow(for: .monday))
        #expect(held.dayProgress(.monday) == 1)

        let snapped = BoltStreakReel.model(atFrame: BoltStreakReel.totalFrames - 8)
        #expect(snapped.reduceMotion)
        #expect(snapped.weeklyProgress == 1)
        #expect(snapped.completed.count == 7)
        #expect(!snapped.headTravels(for: .sunday))
        #expect(BoltStreakReel.duration > 7)
        #expect(BoltStreakReel.duration < 8)
    }
}
