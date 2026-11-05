import XCTest
@testable import StudioKit

/// The M1 harness's own half: the shipped pilot on a lockstep bench, against a fake bench.
final class DriverTrialTests: XCTestCase {
    /// A bench that walks a point by the command in force, and records every request.
    final class FakeBench: @unchecked Sendable {
        private let lock = NSLock()
        var starts: Int
        private(set) var log: [[String: Any]] = []
        private var t = 0.0, x = 0.0, y = 0.0
        init(starts: Int) { self.starts = starts }

        func state() -> [String: Any] {
            ["t": t, "position": [x, y, 0.11], "quaternion": [1.0, 0, 0, 0], "upright": true,
             "joints": Array(repeating: 0.0, count: 14), "ball": [0.8, 0, 0.05], "ballRadius": 0.05]
        }

        func answer(_ r: [String: Any]) -> [String: Any] {
            lock.lock(); defer { lock.unlock() }
            log.append(r)
            switch r["op"] as? String {
            case "begin":
                if starts == 0 { return ["done": true] }
                starts -= 1; t = 0; x = 0; y = 0
                return ["seed": 1, "state": state()]
            case "step":
                let hold = r["hold"] as! Double
                x += (r["vx"] as! Double) * hold; y += (r["vy"] as! Double) * hold
                t = ((t + hold) * 1e6).rounded() / 1e6
                return ["state": state()]
            default:
                return ["ok": true]
            }
        }
        var ops: [String] { lock.lock(); defer { lock.unlock() }; return log.compactMap { $0["op"] as? String } }
        var steps: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return log.filter { $0["op"] as? String == "step" } }
    }

    struct Forward: DreamRows {
        func act(checkpoint: String, prompt: String, frames: [String: [String]],
                 state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
            DuckDream.Chunk(rows: Array(repeating: DuckDrive.Twist(vx: 0.5, vy: 0, vyaw: 0), count: 48), sessionID: nil)
        }
        func end() async {}
    }

    final class Shots: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var times: [Double] = []
        func add(_ t: Double) { lock.lock(); times.append(t); lock.unlock() }
    }

    func testTheJobIsADriverFolderOrZero() {
        XCTAssertEqual(DriverTrial.job(arguments: ["app", "-driver-trial", "/d"]), .init(driver: "/d"))
        XCTAssertEqual(DriverTrial.job(arguments: ["app", "-driver-trial", "zero"]), .init(driver: nil))
        XCTAssertNil(DriverTrial.job(arguments: ["app", "-driver-trial"]))
        XCTAssertNil(DriverTrial.job(arguments: ["app"]))
    }

    func testRGBADropsAlpha() {
        XCTAssertEqual(DriverTrial.rgb(rgba: [1, 2, 3, 255, 4, 5, 6, 255]), [1, 2, 3, 4, 5, 6])
    }

    func testOneRunIsThePilotsRunInSimTimeEndingStopThenEnd() async throws {
        let bench = FakeBench(starts: 1)
        let shots = Shots()
        let ran = try await DriverTrial.runAll(rows: Forward(), modelID: "m", task: "walk to the ball",
                                               wire: { bench.answer($0) },
                                               render: { live in shots.add(live.t); return "J" })
        XCTAssertEqual(ran, 1)
        let ops = bench.ops
        XCTAssertEqual(ops.first, "begin")
        XCTAssertEqual(Array(ops.suffix(4)), ["stop", "end", "ended", "begin"])
        let steps = bench.steps
        // 1.2 s standing, then 60 s of rows at 10 a second.
        XCTAssertEqual(steps.count, 12 + 600)
        XCTAssertTrue(steps.prefix(12).allSatisfy { ($0["vx"] as! Double) == 0 })
        // Clamped to the sticks' forward limit, not the 0.5 asked for.
        XCTAssertEqual(steps[12]["vx"] as! Double, DuckDrive.maxForward, accuracy: 1e-9)
        XCTAssertEqual(ops.filter { $0 == "ask" }.count, 30)
        // The camera every 0.2 s of sim time, from the run's first instant.
        XCTAssertEqual(shots.times.count, 1 + 306)
        XCTAssertEqual(shots.times[1], 0.2, accuracy: 1e-6)
    }

    func testTheZeroBaselineNeverMovesTheDuck() async throws {
        let bench = FakeBench(starts: 2)
        let ran = try await DriverTrial.runAll(rows: StillRows(), modelID: "zero", task: "walk to the ball",
                                               wire: { bench.answer($0) }, render: { _ in "J" })
        XCTAssertEqual(ran, 2)
        XCTAssertTrue(bench.steps.allSatisfy { ($0["vx"] as! Double) == 0 && ($0["vyaw"] as! Double) == 0 })
    }
}
