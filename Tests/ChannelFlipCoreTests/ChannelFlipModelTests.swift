import Testing
import Foundation
@testable import ChannelFlipCore

private func run(_ m: inout ChannelFlipModel, seconds: Double, dt: Double = 1.0 / 60) -> [ChannelFlipModel.Event] {
    var out: [ChannelFlipModel.Event] = []
    var t = 0.0
    while t < seconds { out += m.step(dt); t += dt }
    return out
}

@Suite struct ModelBasicsTests {
    @Test func startsIdleOnTheFirstPhoto() {
        let m = ChannelFlipModel(count: 6)
        #expect(m.index == 0 && m.shown == 0 && m.transition == nil)
        #expect(m.frame.isActive == false && m.frame.intensity == 0 && m.frame.crossfade == 1)
        #expect(m.isIdle && m.osdAlpha == 0)
        #expect(m.channelLabel == "CH 01")
    }

    @Test func startIndexIsWrapped() {
        #expect(ChannelFlipModel(count: 6, startAt: 8).index == 2)
        #expect(ChannelFlipModel(count: 6, startAt: -1).index == 5)
        #expect(ChannelFlipModel(count: 0).index == 0)
    }

    @Test func oneOrNoPhotosCannotFlip() {
        var one = ChannelFlipModel(count: 1)
        let r1 = one.tap()
        #expect(r1 == false && one.transition == nil && one.switches == 0)
        var none = ChannelFlipModel(count: 0)
        let r0 = none.flip(.previous)
        #expect(r0 == false)
    }

    @Test func aTapStartsATransitionToTheNextPhoto() {
        var m = ChannelFlipModel(count: 6)
        let ok = m.tap()
        #expect(ok)
        #expect(m.index == 1 && m.shown == 0)
        #expect(m.transition?.from == 0 && m.transition?.to == 1)
        #expect(m.transition?.spec == ChannelFlipTiming.tap)
        #expect(m.channelLabel == "CH 02")
    }

    @Test func tappingWrapsAfterTheLastPhoto() {
        var m = ChannelFlipModel(count: 3, startAt: 2)
        m.tap(); _ = run(&m, seconds: 1)
        #expect(m.shown == 0 && m.index == 0 && m.channelLabel == "CH 01")
    }
}

@Suite struct SwapTimingTests {
    @Test func theSwapIsOneEventAtThePeakFrame() {
        var m = ChannelFlipModel(count: 6)
        m.tap()
        var swappedAt: Double?
        var finishedAt: Double?
        var t = 0.0
        while m.transition != nil || t == 0 {
            let before = m.frame
            let ev = m.step(1.0 / 120); t += 1.0 / 120
            for e in ev {
                if case .swapped(let a, let b) = e { swappedAt = t; #expect(a == 0 && b == 1) }
                if e == .finished { finishedAt = t }
            }
            if before.isActive && before.shown == 0 && m.frame.shown == 1 { #expect(before.frameIndex < m.frame.frameIndex || m.frame.frameIndex == before.frameIndex) }
            if t > 2 { break }
        }
        let s = try! #require(swappedAt), f = try! #require(finishedAt)
        #expect(s > 0.12 && s < 0.23)
        #expect(abs(f - 0.35) < 0.02)
    }

    @Test func photoOnScreenChangesOnlyAtTheSwapAndTheSwapFrameIsThePeak() {
        var m = ChannelFlipModel(count: 6)
        m.tap()
        var peakFrame: ChannelFlipModel.Frame?
        var changedWhere: ChannelFlipModel.Frame?
        while m.transition != nil {
            let was = m.shown
            m.step(1.0 / 240)
            if m.shown != was { changedWhere = m.frame }
            if m.frame.isActive, m.frame.intensity >= (peakFrame?.intensity ?? 0) { peakFrame = m.frame }
        }
        let c = try! #require(changedWhere), p = try! #require(peakFrame)
        #expect(c.frameIndex == p.frameIndex && c.intensity == p.intensity)
        #expect(p.intensity == ChannelFlipTiming.tap.strength)
    }

    @Test func swapsExactlyOnceAtAnyFrameRate() {
        for dt in [1.0 / 30, 1.0 / 60, 1.0 / 120, 0.05, 0.1] {
            var m = ChannelFlipModel(count: 6)
            m.tap()
            let ev = run(&m, seconds: 0.6, dt: dt)
            #expect(ev.filter { if case .swapped = $0 { return true } else { return false } }.count == 1)
            #expect(ev.filter { $0 == .finished }.count == 1)
            #expect(m.shown == 1 && m.transition == nil)
        }
    }

    @Test func aHugeFrameTimeStillSwapsOnce() {
        var m = ChannelFlipModel(count: 6)
        m.tap()
        let ev = m.step(10)    // clamped to maxStep, then more steps
        _ = ev
        let rest = run(&m, seconds: 1)
        #expect(m.shown == 1 && m.transition == nil)
        #expect(m.switches == 1)
        _ = rest
    }

    @Test func nonFiniteStepsDoNothing() {
        var m = ChannelFlipModel(count: 6)
        m.tap()
        m.step(.nan); m.step(-1); m.step(.infinity)
        #expect(m.transition?.elapsed == 0)   // NaN, infinity and negative steps count as zero
    }
}

@Suite struct IntensityOverTimeTests {
    @Test func risesToThePeakThenFalls() {
        var m = ChannelFlipModel(count: 6)
        m.tap()
        var seq: [Double] = []
        while m.transition != nil {
            m.step(1.0 / 240)
            if m.frame.isActive, seq.last != m.frame.intensity { seq.append(m.frame.intensity) }
        }
        #expect(seq.count == ChannelFlipTiming.frameCount(duration: 0.35))
        let peak = seq.max()!
        let pi = seq.firstIndex(of: peak)!
        #expect(pi == seq.count / 2)
        #expect(zip(seq[..<pi], seq[1...pi]).allSatisfy { $0 < $1 })
        #expect(zip(seq[pi...], seq[(pi + 1)...]).allSatisfy { $0 > $1 })
    }

    @Test func eachFrameHasItsOwnSeedAndHoldsItForTheWholeFrame() {
        var m = ChannelFlipModel(count: 6)
        m.tap()
        var bySeed: [Double: Set<Int>] = [:]
        while m.transition != nil { m.step(1.0 / 240); if m.frame.isActive { bySeed[m.frame.seed, default: []].insert(m.frame.frameIndex) } }
        #expect(bySeed.count == 5)
        #expect(bySeed.values.allSatisfy { $0.count == 1 })
    }

    @Test func differentTransitionsTearDifferently() {
        var a = ChannelFlipModel(count: 6), b = ChannelFlipModel(count: 6)
        a.tap(); _ = run(&a, seconds: 1)
        b.tap(); _ = run(&b, seconds: 1); b.tap()
        a.tap()
        #expect(a.transition?.seed != nil)
        a.step(0.01); b.step(0.01)
        #expect(a.frame.seed == b.frame.seed)   // same flip number → same look (deterministic)
        var c = ChannelFlipModel(count: 6)
        c.tap(); _ = run(&c, seconds: 1); c.tap(); _ = run(&c, seconds: 1); c.tap()
        c.step(0.01)
        #expect(c.frame.seed != a.frame.seed)
    }
}

@Suite struct SwipeTests {
    @Test func slowSwipeIsShortAndMildFastFlickIsLongAndStrong() {
        var slow = ChannelFlipModel(count: 6), fast = ChannelFlipModel(count: 6)
        slow.handle(.swipe(.next, speed: 100)); fast.handle(.swipe(.next, speed: 5000))
        #expect(slow.transition?.spec == FlipSpec(duration: 0.35, strength: 0.45))
        #expect(fast.transition?.spec == FlipSpec(duration: 0.7, strength: 1))
        func peak(_ m: ChannelFlipModel) -> Double {
            var m = m; var p = 0.0
            while m.transition != nil { m.step(1.0 / 240); p = max(p, m.frame.intensity) }
            return p
        }
        #expect(peak(slow) < peak(fast))
        #expect(peak(fast) == 1)
    }

    @Test func fastFlickTakesTwiceAsLong() {
        var m = ChannelFlipModel(count: 6)
        m.handle(.swipe(.next, speed: 5000))
        var t = 0.0
        while m.transition != nil { m.step(1.0 / 240); t += 1.0 / 240 }
        #expect(abs(t - 0.7) < 0.02)
    }

    @Test func directionPicksNextOrPrevious() {
        var m = ChannelFlipModel(count: 6)
        m.handle(.swipe(.previous, speed: 800)); _ = run(&m, seconds: 1)
        #expect(m.shown == 5)
        m.handle(.swipe(.next, speed: 800)); _ = run(&m, seconds: 1)
        #expect(m.shown == 0)
    }

    @Test func handleTapAndNone() {
        var m = ChannelFlipModel(count: 6)
        let n = m.handle(FlipGesture.none)
        #expect(n == false && m.transition == nil)
        let t = m.handle(.tap)
        #expect(t && m.index == 1)
    }
}

@Suite struct HapticTests {
    @Test func oneLightHapticPerSwitch() {
        var m = ChannelFlipModel(count: 6)
        m.tap()
        #expect(m.switches == 0)
        _ = run(&m, seconds: 1)
        #expect(m.switches == 1)
        m.tap(); _ = run(&m, seconds: 1)
        #expect(m.switches == 2)
    }

    @Test func rapidTapsStillMakeProgressAndDoNotBuzzEveryTime() {
        var m = ChannelFlipModel(count: 6)
        for _ in 0..<5 { m.tap(); m.step(0.016) }
        #expect(m.index == 5)
        #expect(m.switches < 5)
        _ = run(&m, seconds: 1)
        #expect(m.shown == 5 && m.transition == nil)
        #expect(m.switches >= 1)
    }

    @Test func tappingMidTransitionSwapsTheOldOneFirst() {
        var m = ChannelFlipModel(count: 6)
        m.tap(); m.step(0.05)
        #expect(m.shown == 0)
        m.tap()
        #expect(m.shown == 1)                       // the unfinished change was completed
        #expect(m.transition?.from == 1 && m.transition?.to == 2 && m.transition?.elapsed == 0)
        let ev = m.step(0.001)
        #expect(ev.contains(.swapped(from: 0, to: 1)))   // reported, in order
    }

    @Test func tappingAfterTheSwapJustRestartsFromTheShownPhoto() {
        var m = ChannelFlipModel(count: 6)
        m.tap(); _ = run(&m, seconds: 0.25)
        #expect(m.shown == 1 && m.transition != nil)
        m.tap()
        #expect(m.transition?.from == 1 && m.transition?.to == 2)
    }
}

@Suite struct ReduceMotionTests {
    @Test func noEffectJustAShortCrossfade() {
        var m = ChannelFlipModel(count: 6)
        m.reduceMotion = true
        m.tap()
        #expect(m.transition?.spec.duration == ChannelFlipTiming.reducedDuration)
        var maxI = 0.0, seen: [Double] = []
        while m.transition != nil {
            m.step(1.0 / 120)
            maxI = max(maxI, m.frame.intensity)
            if m.frame.isActive { seen.append(m.frame.crossfade) }
        }
        #expect(maxI == 0)
        #expect(seen.first! < 0.1 && seen.last! > 0.9)
        #expect(zip(seen, seen.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(m.shown == 1)
    }

    @Test func swipeSpeedDoesNotMakeItLongerOrStronger() {
        var m = ChannelFlipModel(count: 6)
        m.reduceMotion = true
        m.handle(.swipe(.next, speed: 5000))
        #expect(m.transition?.spec.duration == ChannelFlipTiming.reducedDuration)
        _ = run(&m, seconds: 1)
        #expect(m.shown == 1)
    }

    @Test func crossfadeIsStepOnlyWithMotion() {
        var m = ChannelFlipModel(count: 6)
        m.tap()
        m.step(0.05)
        #expect(m.frame.crossfade == 0)
        _ = run(&m, seconds: 0.1)
        #expect(m.frame.crossfade == 1)
    }
}

@Suite struct OSDTests {
    @Test func alphaCurve() {
        #expect(ChannelFlipModel.osdAlpha(age: -1) == 0)
        #expect(ChannelFlipModel.osdAlpha(age: 0) == 0)
        #expect(ChannelFlipModel.osdAlpha(age: ChannelFlipModel.osdFadeIn) == 1)
        #expect(ChannelFlipModel.osdAlpha(age: 1.0) == 1)
        #expect(ChannelFlipModel.osdAlpha(age: ChannelFlipModel.osdHold) == 1)
        #expect(ChannelFlipModel.osdAlpha(age: ChannelFlipModel.osdHold + ChannelFlipModel.osdFadeOut) == 0)
        #expect(ChannelFlipModel.osdAlpha(age: 50) == 0)
        #expect(ChannelFlipModel.osdAlpha(age: .nan) == 0)
        let mid = ChannelFlipModel.osdAlpha(age: ChannelFlipModel.osdHold + ChannelFlipModel.osdFadeOut / 2)
        #expect(abs(mid - 0.5) < 1e-9)
    }

    @Test func fadesInAfterATapHoldsAndFadesOut() {
        var m = ChannelFlipModel(count: 6)
        m.tap()
        #expect(m.osdAlpha == 0 && !m.isIdle)
        m.step(0.2); #expect(m.osdAlpha == 1)
        _ = run(&m, seconds: 1.2); #expect(m.osdAlpha == 1)
        _ = run(&m, seconds: 0.3); #expect(m.osdAlpha < 1 && m.osdAlpha > 0)
        _ = run(&m, seconds: 1.0)
        #expect(m.osdAlpha == 0 && m.isIdle)
    }

    @Test func aNewFlipRestartsTheOverlay() {
        var m = ChannelFlipModel(count: 6)
        m.tap(); _ = run(&m, seconds: 1.9)
        let before = m.osdAlpha
        m.tap()
        #expect(m.osdAlpha == 0 && before < 1)
        #expect(m.channelLabel == "CH 03")
    }

    @Test func notIdleWhileTransitioning() {
        var m = ChannelFlipModel(count: 6)
        m.tap(); m.step(0.1)
        #expect(!m.isIdle)
    }
}

@Suite struct AnnouncementTests {
    @Test func everyFlipAnnouncesTheNewChannel() {
        var m = ChannelFlipModel(count: 6)
        #expect(m.announcement == nil && m.announcementCount == 0)
        m.tap()
        #expect(m.announcement == "Channel 2 of 6" && m.announcementCount == 1)
        m.handle(.swipe(.previous, speed: 0)); m.handle(.swipe(.previous, speed: 0))
        #expect(m.announcement == "Channel 6 of 6" && m.announcementCount == 3)
    }
}
