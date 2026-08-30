import XCTest
@testable import StudioKit

/// Fetch, running the steering law that was proven on the bench.
final class FetchRunTests: XCTestCase {

    func testItWalksToABallAheadAndCollectsIt() {
        var run = FetchRun(balls: [.init(1.0, 0)])
        var ticks = 0
        while !run.isFinished && ticks < 5_000 { run.advance(dt: 1.0 / 50); ticks += 1 }
        XCTAssertTrue(run.isFinished, run.summary)
        XCTAssertEqual(run.fetched.count, 1)
        // 1 m at the measured fast walk, less the arrival radius.
        XCTAssertEqual(run.elapsed, (1.0 - FetchRun.arriveWithin) / 0.150, accuracy: 0.4)
    }

    /// Positive bearing is LEFT — the convention the detector, the robot and
    /// the bench all share. Getting this backwards turns the controller into
    /// positive feedback, which is exactly the bug the loop shipped with once.
    func testPositiveBearingMeansLeft() {
        var run = FetchRun(balls: [.init(1.0, 1.0)])
        XCTAssertEqual(run.bearingDegrees ?? 0, 45, accuracy: 1e-9)
        let before = run.duck.heading
        run.advance(dt: 0.1)
        XCTAssertGreaterThan(run.duck.heading, before, "it should turn toward +y")
    }

    /// A ball behind it is still fetched — it arcs round rather than pivoting,
    /// because pivoting is not available.
    func testABallBehindItIsStillFetched() {
        var run = FetchRun(balls: [.init(-0.9, 0.3)])
        var ticks = 0
        while !run.isFinished && ticks < 20_000 { run.advance(dt: 1.0 / 50); ticks += 1 }
        XCTAssertTrue(run.isFinished, run.summary)
    }

    /// Several balls are fetched in the order they were dropped.
    func testBallsAreFetchedInOrder() {
        let balls: [DuckSoccer.Vec2] = [.init(0.8, 0), .init(1.6, 0.6), .init(0.4, -1.1)]
        var run = FetchRun(balls: balls)
        var ticks = 0
        while !run.isFinished && ticks < 40_000 { run.advance(dt: 1.0 / 50); ticks += 1 }
        XCTAssertEqual(run.fetched.count, 3, run.summary)
        XCTAssertEqual(run.fetched.map(\.x), balls.map(\.x))
        XCTAssertTrue(run.summary.hasPrefix("All 3 fetched"), run.summary)
    }

    func testAnEmptyRunIsAlreadyFinished() {
        var run = FetchRun(balls: [])
        XCTAssertTrue(run.isFinished)
        XCTAssertNil(run.bearingDegrees)
        run.advance(dt: 1)
        XCTAssertEqual(run.elapsed, 0, "a finished run does not age")
    }
}
