import XCTest
@testable import StudioKit

/// Bow Bridge at duck scale, built out of the two things the robot is worst at.
final class BridgeCrossingTests: XCTestCase {

    /// The arch is a ramp with no lip, because the duck tops out at a 10 mm
    /// step. Height must be zero at both ends and peak in the middle.
    func testTheArchHasNoStepAtEitherEnd() {
        let deck = BridgeCrossing.Deck()
        XCTAssertEqual(deck.height(at: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(deck.height(at: deck.length), 0, accuracy: 1e-12)
        XCTAssertEqual(deck.height(at: deck.length / 2), deck.rise, accuracy: 1e-12)
        // Monotonic up to the crown, so there is nowhere to trip.
        var previous = -1.0
        for step in 0...50 {
            let h = deck.height(at: deck.length * Double(step) / 100)
            XCTAssertGreaterThanOrEqual(h, previous - 1e-12)
            previous = h
        }
    }

    /// The gradient a 4 m, 0.22 m arch actually asks the duck to climb.
    func testTheGradientIsGentleEnoughToBeWalkable() {
        let deck = BridgeCrossing.Deck()
        // pi * rise / length — about 17%, a ramp rather than a stair.
        XCTAssertEqual(deck.steepestGradient, .pi * 0.22 / 4.0, accuracy: 1e-12)
        XCTAssertLessThan(deck.steepestGradient, 0.25)
    }

    /// Held straight at walking speed, the crossing takes the time the measured
    /// envelope says it should — not a number chosen to feel right.
    func testCrossingStraightTakesTheMeasuredTime() {
        var run = BridgeCrossing()
        var ticks = 0
        while run.outcome == .crossing && ticks < 10_000 {
            run.advance(dt: 1.0 / 50, forward: 1.0, steer: 0)
            ticks += 1
        }
        guard case .across(let seconds) = run.outcome else {
            return XCTFail("did not get across: \(run.outcome)")
        }
        // 4 m at the measured fast walk of 0.150 m/s.
        XCTAssertEqual(seconds, 4.0 / 0.150, accuracy: 0.1)
    }

    /// STEERING ONLY WORKS WHILE WALKING. A player who lets go of forward
    /// cannot pivot out of trouble, because the robot cannot either.
    func testAStationaryDuckCannotTurn() {
        var run = BridgeCrossing()
        let before = run.heading
        for _ in 0..<200 { run.advance(dt: 1.0 / 50, forward: 0, steer: 1.0) }
        XCTAssertEqual(run.heading, before, accuracy: 1e-12)
        XCTAssertEqual(run.x, 0, accuracy: 1e-12, "and it covers no ground either")
    }

    /// Below the walking command the policy marches in place — so a gentle
    /// squeeze on the stick must not creep the duck forward.
    func testTheDeadBandIsModelled() {
        var run = BridgeCrossing()
        for _ in 0..<100 { run.advance(dt: 1.0 / 50, forward: 0.3, steer: 0) }
        XCTAssertEqual(run.x, 0, accuracy: 1e-12)
        for _ in 0..<100 { run.advance(dt: 1.0 / 50, forward: 0.5, steer: 0) }
        XCTAssertGreaterThan(run.x, 0.1, "at a walking command it does move")
    }

    /// Steer hard enough for long enough and you go in the lake, which is the
    /// whole tension: an arc you cannot cancel by stopping.
    func testHoldingTheSteerWalksItOffTheSide() {
        var run = BridgeCrossing()
        var ticks = 0
        while run.outcome == .crossing && ticks < 10_000 {
            run.advance(dt: 1.0 / 50, forward: 1.0, steer: 1.0)
            ticks += 1
        }
        guard case .inTheLake = run.outcome else {
            return XCTFail("expected a swim, got \(run.outcome)")
        }
        XCTAssertGreaterThan(run.edgeProximity, 0.99)
    }

    /// A correction that is caught in time still gets across.
    func testADriftCaughtInTimeIsRecoverable() {
        var run = BridgeCrossing()
        for _ in 0..<40 { run.advance(dt: 1.0 / 50, forward: 1.0, steer: 0.8) }
        XCTAssertEqual(run.outcome, .crossing)
        // 0.8 s of hard steer at the measured walk drifts about 13 mm — half
            // way to the rail is 125 mm, so this is a correctable wobble.
        XCTAssertGreaterThan(run.y, 0.01)
        XCTAssertLessThan(run.y, run.deck.halfWidth / 2)
        // Steer back until square, then hold straight.
        while run.heading > 0.001 && run.outcome == .crossing {
            run.advance(dt: 1.0 / 50, forward: 1.0, steer: -1.0)
        }
        while run.y > 0.001 && run.outcome == .crossing {
            run.advance(dt: 1.0 / 50, forward: 1.0, steer: -0.15)
        }
        while run.outcome == .crossing {
            run.advance(dt: 1.0 / 50, forward: 1.0, steer: run.y > 0 ? -0.05 : 0.05)
        }
        guard case .across = run.outcome else {
            return XCTFail("a caught drift should still cross: \(run.summary)")
        }
    }

    func testBackingOffTheNearEndIsALakeToo() {
        var run = BridgeCrossing()
        // Turn most of the way round, then walk.
        for _ in 0..<400 { run.advance(dt: 1.0 / 50, forward: 1.0, steer: 1.0) }
        XCTAssertNotEqual(run.outcome, .crossing)
    }

    func testTheSummarySaysWhereYouAre() {
        var run = BridgeCrossing()
        XCTAssertTrue(run.summary.contains("across"), run.summary)
        for _ in 0..<2000 { run.advance(dt: 1.0 / 50, forward: 1.0, steer: 0) }
        XCTAssertTrue(run.summary.hasPrefix("Across in"), run.summary)
    }
}
