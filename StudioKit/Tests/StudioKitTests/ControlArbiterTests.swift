import XCTest
@testable import StudioKit

final class ControlArbiterTests: XCTestCase {

    let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    /// Hand-back must never move the duck: the only effects allowed on an ending are these.
    func assertStopOnly(_ d: ControlArbiter.Decision, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(d.effects.first, .stopPath, file: file, line: line)
        XCTAssertFalse(d.effects.contains(.rearm), file: file, line: line)
        XCTAssertFalse(d.passInput, file: file, line: line)
    }

    func goal(_ a: inout ControlArbiter, duck: DuckIdentity.Kind = .sim, owner: ControlArbiter.Owner = .app) {
        let d = a.handle(.start(.goal, duck: duck, owner: owner), at: t0)
        XCTAssertEqual(d.effects.last, .rearm)
    }

    func testEveryTakeoverInputCancelsTellAndAuto() {
        for input in [ControlArbiter.Event.stickTouch, .padInput, .movePress] {
            for kind in [ControlArbiter.RunKind.tell, .goal] {
                var a = ControlArbiter(mode: kind == .goal ? .auto : .tell)
                _ = a.handle(.start(kind, duck: .real, owner: .app), at: t0)
                let d = a.handle(input, at: at(1))
                XCTAssertEqual(d.effects, [.stopPath, .rearm, .setMode(.drive),
                                           .caption(ControlArbiter.Words.tookOver)], "\(input) \(kind)")
                XCTAssertTrue(d.passInput)
                XCTAssertNil(a.running)
                XCTAssertEqual(a.mode, .drive)
                XCTAssertEqual(a.lastEnding, .tookOver)
            }
        }
    }

    func testStopIsTheFirstEffectOfATakeover() {
        var a = ControlArbiter(mode: .auto)
        goal(&a)
        XCTAssertEqual(a.handle(.padInput, at: at(2)).effects.first, .stopPath)
    }

    func testHandBackAfterAStopEmitsNoMotion() {
        var a = ControlArbiter(mode: .auto)
        goal(&a, duck: .real)
        let d = a.handle(.stop, at: at(3))
        assertStopOnly(d)
        XCTAssertEqual(d.effects, [.stopPath])
        XCTAssertEqual(a.mode, .auto)
        // Stop with nothing running still reaches the wire, and still moves nothing.
        let again = a.handle(.stop, at: at(4))
        XCTAssertEqual(again.effects, [.stopPath])
        XCTAssertFalse(again.passInput)
    }

    func testCapsThirtyOnTheRealDuckSixtyOnThePracticeDuck() {
        var real = ControlArbiter(mode: .auto)
        goal(&real, duck: .real)
        XCTAssertEqual(real.handle(.tick, at: at(29.9)), .init(effects: [], passInput: false))
        let d = real.handle(.tick, at: at(30))
        assertStopOnly(d)
        XCTAssertEqual(d.effects.last, .caption(ControlArbiter.Words.capped(30)))
        XCTAssertEqual(real.lastEnding, .capped)

        var practice = ControlArbiter(mode: .auto)
        goal(&practice, duck: .sim)
        XCTAssertTrue(practice.handle(.tick, at: at(59.9)).effects.isEmpty)
        assertStopOnly(practice.handle(.tick, at: at(60)))
    }

    func testCapsCanBeLengthenedButNotSwitchedOff() {
        XCTAssertEqual(ControlArbiter.Caps(realDuck: 45).seconds(on: .real), 45)
        XCTAssertEqual(ControlArbiter.Caps(realDuck: .infinity).seconds(on: .real), 30)
        XCTAssertEqual(ControlArbiter.Caps(realDuck: 0, practiceDuck: -1).seconds(on: .sim), 60)
        XCTAssertEqual(ControlArbiter.Caps(practiceDuck: .nan).seconds(on: .sim), 60)
    }

    func testTellChainsHaveNoGoalCap() {
        var a = ControlArbiter(mode: .tell)
        _ = a.handle(.start(.tell, duck: .real, owner: .app), at: t0)
        XCTAssertTrue(a.handle(.tick, at: at(120)).effects.isEmpty)
        XCTAssertNotNil(a.running)
    }

    func testAStoppedGoalNeverReArmsItself() {
        var a = ControlArbiter(mode: .auto)
        goal(&a, duck: .real)
        _ = a.handle(.stop, at: at(1))
        for (i, e) in [ControlArbiter.Event.tick, .foreground, .background, .foreground,
                       .connectionLost, .finished, .tick].enumerated() {
            let d = a.handle(e, at: at(Double(2 + i)))
            XCTAssertFalse(d.effects.contains(.rearm), "\(e)")
            XCTAssertNil(a.running, "\(e)")
        }
        XCTAssertEqual(a.lastEnding, .stopped)
        // Only a person's start begins one again.
        goal(&a, duck: .real)
        XCTAssertNotNil(a.running)
    }

    func testBackgroundEndsRuns() {
        for owner in [ControlArbiter.Owner.app, .intent] {
            var a = ControlArbiter(mode: .tell)
            _ = a.handle(.start(.tell, duck: .sim, owner: owner), at: t0)
            let d = a.handle(.background, at: at(1))
            assertStopOnly(d)
            XCTAssertEqual(a.lastEnding, .leftForeground)
        }
    }

    /// Siri or a Control starting a run while the app is off screen: the `.background` that
    /// would have ended it has passed, so it is refused unless it holds a Live Activity.
    func testAStartOffScreenWithoutALiveActivityIsRefused() {
        for owner in [ControlArbiter.Owner.app, .intent] {
            for kind in [ControlArbiter.RunKind.tell, .goal] {
                var a = ControlArbiter(mode: .tell)
                _ = a.handle(.background, at: t0)
                let d = a.handle(.start(kind, duck: .real, owner: owner), at: at(1))
                XCTAssertEqual(d.effects, [.caption(ControlArbiter.Words.notOnScreen)])
                XCTAssertFalse(d.effects.contains(.rearm), "the latch stays shut")
                XCTAssertFalse(d.passInput)
                XCTAssertNil(a.running, "\(owner) \(kind)")
            }
        }
        var a = ControlArbiter(mode: .auto)
        _ = a.handle(.background, at: t0)
        let d = a.handle(.start(.goal, duck: .real, owner: .intentWithLiveActivity), at: at(1))
        XCTAssertEqual(d.effects.last, .rearm)
        XCTAssertNotNil(a.running)
        // Back on screen, an intent run starts as before.
        var b = ControlArbiter(mode: .tell)
        _ = b.handle(.background, at: t0)
        _ = b.handle(.foreground, at: at(1))
        XCTAssertEqual(b.handle(.start(.tell, duck: .sim, owner: .intent), at: at(2)).effects.last, .rearm)
    }

    func testAnIntentRunWithALiveActivityOutlivesTheForegroundButNotTheConnection() {
        var a = ControlArbiter(mode: .auto)
        goal(&a, duck: .sim, owner: .intentWithLiveActivity)
        XCTAssertTrue(a.handle(.background, at: at(1)).effects.isEmpty)
        XCTAssertNotNil(a.running)
        let d = a.handle(.connectionLost, at: at(2))
        assertStopOnly(d)
        XCTAssertEqual(d.effects, [.stopPath, .endLiveActivity,
                                   .caption(ControlArbiter.Words.connectionLost)])
        XCTAssertEqual(a.lastEnding, .connectionLost)
        // Back on screen: nothing starts.
        XCTAssertTrue(a.handle(.foreground, at: at(3)).effects.isEmpty)
        XCTAssertNil(a.running)
    }

    func testTheLiveActivityRunIsStillCapped() {
        var a = ControlArbiter(mode: .auto)
        goal(&a, duck: .sim, owner: .intentWithLiveActivity)
        _ = a.handle(.background, at: at(1))
        let d = a.handle(.tick, at: at(60))
        XCTAssertEqual(Array(d.effects.prefix(2)), [.stopPath, .endLiveActivity])
    }

    /// Build 93: a resting or drifting game controller in Auto with nothing running keeps Auto
    /// and moves nothing. Only a running goal is taken over by the stick.
    func testStickInAutoWithNothingRunningStaysInAutoAndMovesNothing() {
        var a = ControlArbiter(mode: .auto)
        let d = a.handle(.stickTouch, at: t0)
        XCTAssertEqual(d.effects, [.caption(ControlArbiter.Words.sticksRestInAuto)])
        XCTAssertFalse(d.passInput)
        XCTAssertEqual(a.mode, .auto)
        // A pad press or a move press in idle Auto is the person's own and passes.
        XCTAssertTrue(a.handle(.padInput, at: t0).passInput)
        XCTAssertEqual(a.mode, .auto)
        var drive = ControlArbiter(mode: .drive)
        XCTAssertEqual(drive.handle(.padInput, at: t0), .init(effects: [], passInput: true))
    }

    func testOneShotTellInDriveIsCancelledByTheStickWithoutAModeChange() {
        var a = ControlArbiter(mode: .drive)
        _ = a.handle(.start(.tell, duck: .real, owner: .app), at: t0)
        XCTAssertEqual(a.mode, .drive)
        XCTAssertEqual(a.handle(.stickTouch, at: at(1)).effects,
                       [.stopPath, .rearm, .caption(ControlArbiter.Words.tookOver)])
    }

    func testANewStartStopsTheOldRunFirst() {
        var a = ControlArbiter(mode: .tell)
        _ = a.handle(.start(.tell, duck: .real, owner: .app), at: t0)
        let d = a.handle(.start(.goal, duck: .real, owner: .app), at: at(1))
        XCTAssertEqual(d.effects, [.stopPath, .setMode(.auto), .rearm])
        XCTAssertEqual(a.running?.endsBy, at(31))
    }

    func testSwitchingModeStopsAndNeverMoves() {
        var a = ControlArbiter(mode: .auto)
        goal(&a)
        let d = a.handle(.selectMode(.tell), at: at(1))
        XCTAssertEqual(d.effects, [.stopPath, .setMode(.tell)])
        XCTAssertFalse(d.passInput)
    }

    func testWordsHaveNoEmDash() {
        for s in ControlArbiter.Words.all { XCTAssertFalse(s.contains("\u{2014}"), s) }
    }

    /// Build 93: an order from Siri or a real duck's face button is a run, so the cap, Stop and a
    /// stick take-over cover it, and it never moves the switch.
    func testAnOrderIsCappedAndTakenOverWithoutMovingTheSwitch() {
        var a = ControlArbiter(mode: .tell)
        let d = a.handle(.start(.order, duck: .real, owner: .intent), at: t0)
        XCTAssertEqual(d.effects, [.rearm])
        XCTAssertEqual(a.mode, .tell)
        XCTAssertEqual(a.running?.endsBy, at(ControlArbiter.Caps.realDuckDefault))
        XCTAssertEqual(a.handle(.tick, at: at(29)), .init(effects: [], passInput: false))
        XCTAssertEqual(a.handle(.tick, at: at(30)).effects,
                       [.stopPath, .caption(ControlArbiter.Words.capped(30))])
        XCTAssertEqual(a.lastEnding, .capped)

        var practice = ControlArbiter(mode: .drive)
        _ = practice.handle(.start(.order, duck: .sim, owner: .app), at: t0)
        XCTAssertEqual(practice.running?.endsBy, at(ControlArbiter.Caps.practiceDuckDefault))
        let took = practice.handle(.stickTouch, at: at(1))
        XCTAssertEqual(took.effects, [.stopPath, .rearm, .caption(ControlArbiter.Words.tookOver)])
        XCTAssertTrue(took.passInput)

        // A Tell run keeps no cap: a sequence or a plan may be long, and Stop ends it.
        var tell = ControlArbiter()
        _ = tell.handle(.start(.tell, duck: .real, owner: .app), at: t0)
        XCTAssertNil(tell.running?.endsBy)
        XCTAssertTrue(ControlArbiter.RunKind.order.isCapped)
        XCTAssertFalse(ControlArbiter.RunKind.tell.isCapped)
    }
}
