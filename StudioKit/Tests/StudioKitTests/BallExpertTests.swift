import XCTest
@testable import StudioKit

/// The scripted driver, checked on a kinematic duck: the command integrated as a unicycle at
/// 10 Hz. This proves the steering, not the walking; whether the physics duck follows it is the
/// Mac step's check (the plan's T8), with the same seeds.
final class BallExpertTests: XCTestCase {
    /// Seeded starts across the practice mat, ball where the practice world puts it.
    private func run(seed: UInt64, limit: Double = 30) -> (arrived: Bool, seconds: Double) {
        var rng = SplitMix64(seed: seed &* 7919 &+ 1)
        let style = BallExpert.Style(seed: seed)
        let (bx, by) = (0.90, -0.45)
        var x = -0.6 + 1.2 * rng.next(), y = -0.9 + 1.8 * rng.next(), yaw = 2 * .pi * rng.next()
        // Never start on top of the ball.
        if hypot(bx - x, by - y) < 0.4 { x -= 0.6 }
        var t = 0.0
        while t < limit {
            let c = BallExpert.command(x: x, y: y, yaw: yaw, bx: bx, by: by, t: t, style: style)
            if c == .still { return (true, t) }
            XCTAssertLessThanOrEqual(c.vx, DuckDrive.maxForward + 1e-12)
            XCTAssertLessThanOrEqual(abs(c.vyaw), DuckDrive.maxTurn + 1e-12)
            XCTAssertFalse(c.standsStill, "a moving command the walker would read as standing")
            x += 0.1 * (c.vx * cos(yaw) - c.vy * sin(yaw))
            y += 0.1 * (c.vx * sin(yaw) + c.vy * cos(yaw))
            yaw += 0.1 * c.vyaw
            t += 0.1
        }
        return (false, t)
    }

    func testItReachesTheBallFrom95PercentOf200SeededStarts() {
        let results = (0..<200).map { run(seed: UInt64($0)) }
        let arrived = results.filter(\.arrived).count
        XCTAssertGreaterThanOrEqual(arrived, 190, "\(arrived)/200")
        let mean = results.filter(\.arrived).map(\.seconds).reduce(0, +) / Double(max(arrived, 1))
        XCTAssertLessThan(mean, 15, "takes should be seconds long, not minutes")
    }

    func testInsideReachItStandsStillAndOtherwiseItMoves() {
        XCTAssertEqual(BallExpert.command(x: 0, y: 0, yaw: 0, bx: 0.15, by: 0, t: 0), .still)
        let ahead = BallExpert.command(x: 0, y: 0, yaw: 0, bx: 1, by: 0, t: 0)
        XCTAssertEqual(ahead.vx, DuckDrive.maxForward, accuracy: 1e-9)
        XCTAssertEqual(ahead.vyaw, 0, accuracy: 1e-9)
        let behind = BallExpert.command(x: 0, y: 0, yaw: 0, bx: -1, by: 0.01, t: 0)
        XCTAssertEqual(behind.vx, BallExpert.arcForward, "turns on an arc: the sim's walker cannot turn in place")
        XCTAssertEqual(behind.vyaw, DuckDrive.maxTurn)
        XCTAssertGreaterThan(behind.vyaw, 0, "ball slightly to the left behind: turns left")
    }

    func testASeedIsTheSameTakeEverywhere() {
        XCTAssertEqual(BallExpert.Style(seed: 17), BallExpert.Style(seed: 17))
        XCTAssertNotEqual(BallExpert.Style(seed: 17), BallExpert.Style(seed: 18))
        var a = SplitMix64(seed: 0)
        XCTAssertEqual(a.next(), Double(UInt64(0xE220_A839_7B1D_CDAF) >> 11) / 9007199254740992.0,
                       "SplitMix64's published first output for seed 0")
    }

    /// The Pi-side recorder (scripts/record_ball_takes.py) carries a port of this expert. The
    /// recorded takes are only this expert's if the two decide identically.
    func testThePythonPortDecidesExactlyAsThisDoes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/ball-expert-vectors", withExtension: "json"))
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let styles = try XCTUnwrap(file["styles"] as? [String: [String: Double]])
        for (key, s) in styles {
            let mine = BallExpert.Style(seed: UInt64(key)!)
            XCTAssertEqual(mine.speed, s["speed"]!, accuracy: 1e-12)
            XCTAssertEqual(mine.turnGain, s["turnGain"]!, accuracy: 1e-12)
            XCTAssertEqual(mine.weave, s["weave"]!, accuracy: 1e-12)
            XCTAssertEqual(mine.weavePeriod, s["weavePeriod"]!, accuracy: 1e-12)
        }
        let cases = try XCTUnwrap(file["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 60)
        for c in cases {
            func d(_ k: String) -> Double { (c[k] as? NSNumber)?.doubleValue ?? .nan }
            let seed = (c["styleSeed"] as? NSNumber)?.uint64Value ?? 0
            let style = seed == 0 ? BallExpert.Style.plain : BallExpert.Style(seed: seed)
            let got = BallExpert.command(x: d("x"), y: d("y"), yaw: d("yaw"), bx: d("bx"), by: d("by"), t: d("t"), style: style)
            let want = (c["command"] as? [NSNumber])!.map(\.doubleValue)
            XCTAssertEqual(got.vx, want[0], accuracy: 1e-12)
            XCTAssertEqual(got.vy, want[1], accuracy: 1e-12)
            XCTAssertEqual(got.vyaw, want[2], accuracy: 1e-12)
        }
    }
}
