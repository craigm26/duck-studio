import XCTest
@testable import StudioKit

/// The rules are the flamingo-cycle manifest's published limits, verbatim.
final class FlamingoHoldTests: XCTestCase {

    func testAnythingUnderTheStatedThresholdSimplyHolds() {
        for direction in FlamingoHold.Direction.allCases {
            let result = FlamingoHold.outcome(
                of: .init(direction: direction, speed: 0.15), side: .leftLifted, braced: false)
            XCTAssertEqual(result, .held, "\(direction) at the stated 0.15 m/s")
        }
    }

    /// "backward >= 0.18 m/s it falls" — the one limit the author calls out.
    func testBackwardAtTheStatedSpeedIsTheOneItCannotTake() {
        XCTAssertEqual(FlamingoHold.outcome(of: .init(direction: .backward, speed: 0.18),
                                            side: .leftLifted, braced: false), .fell)
        // Just under, it is a touch-down rather than a fall.
        XCTAssertEqual(FlamingoHold.outcome(of: .init(direction: .backward, speed: 0.17),
                                            side: .leftLifted, braced: false),
                       .touchedDownAndRecovered)
    }

    /// The same shove has different consequences by side — which is the game.
    func testTheSameShoveDiffersByWhichFootIsDown() {
        let hard = FlamingoHold.Push(direction: .towardLifted, speed: 0.3)
        XCTAssertEqual(FlamingoHold.outcome(of: hard, side: .leftLifted, braced: false),
                       .touchedDownAndRecovered, "toward the lifted side it recovers")
        let other = FlamingoHold.Push(direction: .towardStanding, speed: 0.3)
        XCTAssertEqual(FlamingoHold.outcome(of: other, side: .leftLifted, braced: false),
                       .steppedDown, "toward the standing side it steps down")
    }

    /// A touch-down is survivable and the run continues; a step-down is not.
    func testRecoveringKeepsTheRunAliveAndSteppingDownEndsIt() {
        var hold = FlamingoHold()
        hold.take(.init(direction: .towardLifted, speed: 0.3), braced: false)
        XCTAssertFalse(hold.over)
        XCTAssertEqual(hold.survived, 1)
        hold.take(.init(direction: .towardStanding, speed: 0.3), braced: false)
        XCTAssertTrue(hold.over)
        XCTAssertEqual(hold.survived, 1, "the one that ended it does not count")
    }

    /// Bracing halves the push — the only rule here that is a game rule rather
    /// than a measurement, and it is labelled as such in the source.
    func testBracingTurnsAFallIntoAHold() {
        let shove = FlamingoHold.Push(direction: .backward, speed: 0.28)
        XCTAssertEqual(FlamingoHold.outcome(of: shove, side: .leftLifted, braced: false), .fell)
        XCTAssertEqual(FlamingoHold.outcome(of: shove, side: .leftLifted, braced: true), .held)
    }

    func testSwitchingSidesChangesWhichShoveIsWhich() {
        var hold = FlamingoHold(side: .leftLifted)
        XCTAssertEqual(hold.side.standingFoot, "right")
        XCTAssertEqual(hold.side.liftedLeg, "left")
        hold.switchSide()
        XCTAssertEqual(hold.side, .rightLifted)
        XCTAssertEqual(hold.side.standingFoot, "left")
        // The policy's own command value, so a driver can send it unchanged.
        XCTAssertEqual(hold.side.rawValue, -1)
    }

    func testAFinishedHoldStopsTakingPushes() {
        var hold = FlamingoHold()
        hold.take(.init(direction: .backward, speed: 0.5), braced: false)
        XCTAssertTrue(hold.over)
        let survived = hold.survived
        hold.take(.init(direction: .forward, speed: 0.01), braced: false)
        XCTAssertEqual(hold.survived, survived)
        XCTAssertTrue(hold.summary.contains("backwards"), hold.summary)
    }
}
