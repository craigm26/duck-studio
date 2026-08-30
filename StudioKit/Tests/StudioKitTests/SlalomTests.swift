import XCTest
@testable import StudioKit

final class SlalomTests: XCTestCase {

    /// The whole game in one number, twice.
    func testMinimumTurnRadiusIsSpeedOverTurnRate() {
        XCTAssertEqual(Slalom.minimumTurnRadius(.measured), 0.106 / 0.34, accuracy: 1e-9)
        XCTAssertEqual(Slalom.minimumTurnRadius(.measured), 0.312, accuracy: 0.005)
        XCTAssertEqual(Slalom.minimumTurnRadius(.skates), 0.90, accuracy: 0.005)
    }

    /// The course is set to exactly what the legs can hold — and the skates
    /// cannot, at any steering angle, without slowing down.
    func testCourseIsTunedToTheLegsAndBeatsTheSkates() {
        let required = Slalom.requiredRadius(Slalom.course)
        XCTAssertEqual(required, 0.31, accuracy: 0.02)
        XCTAssertLessThanOrEqual(Slalom.minimumTurnRadius(.measured), required + 0.01)
        XCTAssertGreaterThan(Slalom.minimumTurnRadius(.skates), required * 2)
    }

    /// The claim the mode is built on: the skates' straight-line advantage
    /// collapses through gates. Asserted, not just written in prose.
    func testTheSkatesAdvantageCollapsesThroughGates() {
        let legs = DuckSoccer.Capabilities.measured
        let required = Slalom.requiredRadius(Slalom.course)
        let skateSpeed = Slalom.topSpeed(forRadius: required, .skates)
        let legSpeed = Slalom.topSpeed(forRadius: required, legs)

        // The legs give up nothing: the course was cut to their radius.
        XCTAssertEqual(legSpeed, legs.walkSpeed, accuracy: 0.005)
        // The skates give up most of it — but they are still the faster robot.
        XCTAssertEqual(skateSpeed, 0.155, accuracy: 0.01)
        XCTAssertGreaterThan(skateSpeed, legSpeed)
        XCTAssertEqual(DuckSoccer.Capabilities.skates.walkSpeed / legs.walkSpeed,
                       4.2, accuracy: 0.1)
        XCTAssertEqual(skateSpeed / legSpeed, 1.5, accuracy: 0.1)
    }

    func testDrivingThroughAGateCountsIt() {
        var run = Slalom(gates: [.init(center: .init(0.5, 0), heading: 0)],
                         start: .init(position: .init(0, 0), heading: 0))
        for _ in 0..<400 { run.advance(dt: 0.02, forward: 1, turn: 0) }
        XCTAssertEqual(run.next, 1)
        XCTAssertEqual(run.missed, 0)
        XCTAssertTrue(run.isFinished)
    }

    func testGoingPastTheOutsideOfAPostIsAMiss() {
        var run = Slalom(gates: [.init(center: .init(0.5, 0), heading: 0, halfWidth: 0.2)],
                         start: .init(position: .init(0, 0.6), heading: 0))
        for _ in 0..<400 { run.advance(dt: 0.02, forward: 1, turn: 0) }
        XCTAssertEqual(run.missed, 1)
        XCTAssertEqual(run.time, run.elapsed + Slalom.missPenalty, accuracy: 1e-9)
        XCTAssertEqual(run.cleared, 0)
    }

    /// Reversing over the line neither earns the gate nor loses it.
    func testBackingOverAGateDoesNothing() {
        var run = Slalom(gates: [.init(center: .init(0.5, 0), heading: 0)],
                         start: .init(position: .init(1.0, 0), heading: 0))
        for _ in 0..<400 { run.advance(dt: 0.02, forward: -1, turn: 0) }
        XCTAssertEqual(run.next, 0)
        XCTAssertEqual(run.missed, 0)
        XCTAssertFalse(run.isFinished)
    }

    /// A full course, driven by a steering law that just aims at the next
    /// gate, cleans it on legs. If this ever fails the course has drifted out
    /// of the envelope it was cut to fit.
    func testTheLegsCanCleanTheCourse() {
        var run = Slalom()
        var ticks = 0
        while !run.isFinished && ticks < 6000 {
            ticks += 1
            let gate = run.gates[run.next]
            let to = gate.center - run.duck.position
            var bearing = atan2(to.y, to.x) - run.duck.heading
            bearing = atan2(sin(bearing), cos(bearing))
            let turn = max(-1, min(1, bearing / (DuckSoccer.Capabilities.measured.turnRate * 0.5)))
            run.advance(dt: 0.02, forward: 1, turn: turn)
        }
        XCTAssertTrue(run.isFinished)
        XCTAssertEqual(run.missed, 0, "the course should be cleanable on legs")
        XCTAssertEqual(run.cleared, Slalom.course.count)
    }
}
