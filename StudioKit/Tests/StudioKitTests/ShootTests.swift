import XCTest
import DuckKit
@testable import StudioKit

final class ShootTests: XCTestCase {

    /// The pitch is duckbench's `PITCH`, number for number.
    func testThePitchMirrorsTheBench() {
        let p = Shoot.Pitch.canon
        XCTAssertEqual(p.goalX, 1.30)
        XCTAssertEqual(p.goalHalfWidth, 0.30)
        XCTAssertEqual(p.goalHeight, 0.25)
        XCTAssertEqual(p.walls, 1.5)
        XCTAssertEqual(p.duckStart.x, -0.70)
        XCTAssertLessThan(p.goalX, p.walls, "the goal line is inside the room")
    }

    func testNineCoreCellsAndTwoHarderOnes() {
        XCTAssertEqual(Shoot.coreCells.count, 9)
        XCTAssertEqual(Shoot.cells.count, 11)
        for c in Shoot.cells {
            XCTAssertLessThan(abs(c.x), 1.2); XCTAssertLessThan(abs(c.y), 1.2)
        }
    }

    func testTheDefaultsAreTheBenchsAndInsideTheLimits() {
        let d = Shoot.Params.defaults
        XCTAssertEqual(d.value("shootRange"), 0.55)
        XCTAssertEqual(d.value("kickDist"), 0.10)
        XCTAssertEqual(d.clamped, d, "the defaults sit inside every range")
        XCTAssertEqual(Set(d.values.keys), Set(Shoot.Params.limits.map(\.key)))
    }

    func testAMutationStaysInsideTheLimits() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let m = Shoot.Params.defaults.mutated(scale: 0.5, using: &rng)
            for l in Shoot.Params.limits {
                XCTAssertGreaterThanOrEqual(m.value(l.key), l.low)
                XCTAssertLessThanOrEqual(m.value(l.key), l.high)
            }
        }
    }

    func testAShotIsReadWithItsClipBallAndPhases() throws {
        let frame = [Double](repeating: 0, count: 14)
        let json: [String: Any] = [
            "format": "duck-shot/1", "hz": 50.0, "outcome": "goal", "miss_m": 0.0, "foot": "left",
            "phases": [["phase": "approach", "t": 0.0], ["phase": "kick", "t": 1.0]],
            "frames": [frame, frame], "roots": [[0, 0, 0.12, 1, 0, 0, 0], [0.01, 0, 0.12, 1, 0, 0, 0]],
            "ball": [[0.3, 0, 0.05], [1.31, 0.02, 0.05]],
        ]
        let shot = try Shoot.read(JSONSerialization.data(withJSONObject: json),
                                  cell: Shoot.coreCells[4], named: "shot")
        XCTAssertTrue(shot.goal)
        XCTAssertEqual(shot.clip.frames.count, 2)
        XCTAssertEqual(shot.phase(at: 1.2), "kick")
        XCTAssertEqual(shot.ball(at: 0.02)?.x, 1.31)
    }

    func testABenchRefusalIsSaid() {
        let data = Data(#"{"error":"no /shoot here"}"#.utf8)
        XCTAssertThrowsError(try Shoot.read(data, cell: Shoot.coreCells[0], named: "x"))
    }

    /// Goals first; among equal goals, nearer misses.
    func testScoresRankGoalsThenNearMisses() {
        let a = Shoot.Score(goals: 2, shots: 9, meanMissMetres: 0.9)
        let b = Shoot.Score(goals: 1, shots: 9, meanMissMetres: 0.0)
        let c = Shoot.Score(goals: 1, shots: 9, meanMissMetres: 0.4)
        XCTAssertGreaterThan(a, b)
        XCTAssertGreaterThan(b, c)
    }

    /// The search keeps the best it has seen and narrows when nothing beats it.
    func testTheSearchKeepsTheBestAndNarrows() {
        var s = Shoot.Search(children: 3)
        s.seed(Shoot.Score(goals: 1, shots: 9, meanMissMetres: 0.5))
        var better = Shoot.Params.defaults; better.values["kickDist"] = 0.09
        s.finish([(better, Shoot.Score(goals: 3, shots: 9, meanMissMetres: 0.2))])
        XCTAssertEqual(s.best, better)
        XCTAssertEqual(s.bestScore?.goals, 3)
        let scale = s.scale
        s.finish([(Shoot.Params.defaults, Shoot.Score(goals: 0, shots: 9, meanMissMetres: 1))])
        XCTAssertEqual(s.best, better, "a worse child is not kept")
        XCTAssertLessThan(s.scale, scale)
        XCTAssertEqual(s.history.map(\.goals), [1, 3, 3])
    }

    /// Honest words: search, not RL; RLHF only beside human feedback.
    func testTheStepsSayWhatTheTrainingIs() {
        let text = ShootWords.steps.map(\.body).joined(separator: " ")
        XCTAssertTrue(text.contains("not reinforcement learning"))
        XCTAssertTrue(text.contains("never changed"))
        XCTAssertTrue(text.contains("RLHF's human feedback"))
        XCTAssertEqual(ShootWords.steps.count, 6)
    }
}
