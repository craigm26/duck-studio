import XCTest
import DuckKit
@testable import StudioKit

/// The scripted expert's takes, read back into a dataset plan. The real file is checked too when
/// `BALL_TAKES` names it (160 takes, 19,314 rows on 2026-11-04).
final class BallTakesTests: XCTestCase {
    /// One bench state block exactly as duckbench answered it in takes-v2 (row 0 of seed 1), with
    /// the integer 1 in the quaternion that JSON gives back.
    private func bench(t: Double, x: Double, ball: [Double]? = [-0.5056, -0.5805, 0.05]) -> [String: Any] {
        var b: [String: Any] = [
            "duck": "duck", "t": t, "position": [x, -0.0001, 0.1162], "quaternion": [1, 0.0004, 0.0001, 0.0094],
            "height": 0.1162, "upright": true,
            "joints": [-0.0044, -0.0976, -0.4309, 0.0394, 0.4699, 0.232, 0.4464, -0.0436, 0.0385, -0.0046,
                       0.1002, 0.4008, -0.0393, -0.4325],
            "policy": "alpha_walking.onnx", "command": ["vx": 0, "vy": 0, "vyaw": 0],
            "ballRadius": 0.05, "battery": NSNull(),
        ]
        b["ball"] = ball ?? NSNull()
        return b
    }

    private func line(seed: Int, rows n: Int, task: String = "walk to the ball") -> String {
        var rows: [[String: Any]] = []
        var previous: [Double] = [0, 0, 0]
        for i in 0..<n {
            let action: [Double] = [0.25, 0, i < n / 2 ? -1 : 0]
            rows.append(["state": previous, "action": action, "bench": bench(t: 0.5 + 0.1 * Double(i), x: 0.01 * Double(i))])
            previous = action
        }
        let top: [String: Any] = ["seed": seed, "task": task, "rows": rows]
        return String(decoding: try! JSONSerialization.data(withJSONObject: top), as: UTF8.self)
    }

    func testATakeReadsAsRowsAndOneStatePerRow() throws {
        let takes = try BallTakes.read(jsonl: Data((line(seed: 1, rows: 20) + "\n\n" + line(seed: 2, rows: 30) + "\n").utf8))
        XCTAssertEqual(takes.map(\.seed), [1, 2])
        XCTAssertEqual(takes.map(\.rows.count), [20, 30])
        XCTAssertEqual(takes.map(\.states.count), [20, 30])
        let first = takes[0]
        XCTAssertEqual(first.rows[0].state, .still)
        XCTAssertEqual(first.rows[0].action, DuckDrive.Twist(vx: 0.25, vy: 0, vyaw: -1))
        XCTAssertEqual(first.rows[1].state, first.rows[0].action, "state is the command in force before")
        // Frame n is drawn from row n's own state block, the moment the action was chosen.
        XCTAssertEqual(first.states[3].stance.root.x, 0.03, accuracy: 1e-12)
        XCTAssertEqual(first.states[3].t, 0.8, accuracy: 1e-12)
        XCTAssertEqual(first.states[0].ball, DuckWorld.Point(x: -0.5056, y: -0.5805, z: 0.05))
        XCTAssertEqual(first.states[0].ballRadius, 0.05)
        XCTAssertEqual(first.states[0].stance.root.quaternion.0, 1)
        XCTAssertEqual(first.episode, DreamDataset.Episode(task: "walk to the ball", rows: first.rows))
    }

    func testBadLinesAreRefusedByLineAndRow() {
        XCTAssertThrowsError(try BallTakes.read(jsonl: Data("not json\n".utf8))) {
            XCTAssertEqual($0 as? BallTakes.Refusal, .notJSON(line: 1))
        }
        XCTAssertThrowsError(try BallTakes.read(jsonl: Data("\n".utf8))) {
            XCTAssertEqual($0 as? BallTakes.Refusal, .noTakes)
        }
        XCTAssertThrowsError(try BallTakes.read(jsonl: Data((line(seed: 1, rows: 20) + "\n{\"task\":\"x\",\"rows\":[]}").utf8))) {
            XCTAssertEqual($0 as? BallTakes.Refusal, .noRows(line: 2))
        }
        var b = bench(t: 0, x: 0)
        b["joints"] = [0.0, 0.0]
        let badState: [String: Any] = ["task": "x", "rows": [["state": [0, 0, 0], "action": [0, 0, 0], "bench": b]]]
        XCTAssertThrowsError(try BallTakes.read(line: try JSONSerialization.data(withJSONObject: badState), number: 7)) {
            XCTAssertEqual($0 as? BallTakes.Refusal, .badState(line: 7, row: 0))
        }
        let badTwist: [String: Any] = ["task": "x", "rows": [["state": [0, 0], "action": [0, 0, 0], "bench": bench(t: 0, x: 0)]]]
        XCTAssertThrowsError(try BallTakes.read(line: try JSONSerialization.data(withJSONObject: badTwist), number: 3)) {
            XCTAssertEqual($0 as? BallTakes.Refusal, .badTwist(line: 3, row: 0))
        }
        for r in [BallTakes.Refusal.notJSON(line: 1), .noRows(line: 1), .badTwist(line: 1, row: 0),
                  .badState(line: 1, row: 0), .noTakes] {
            XCTAssertFalse(r.message.contains("\u{2014}"))
        }
    }

    func testThePlanPairsOneFramePerRowAndWritesTheDataset() throws {
        let takes = try BallTakes.read(jsonl: Data((line(seed: 1, rows: 20) + "\n" + line(seed: 2, rows: 30)).utf8))
        let plan = try BallTakes.plan(takes, pictures: [BallTakes.Picture(episode: 1, frame: 29)])
        XCTAssertEqual(plan.videos.map(\.path), [DreamDataset.videoPath(0), DreamDataset.videoPath(1)])
        XCTAssertEqual(plan.videos.map(\.states.count), [20, 30])
        XCTAssertEqual(plan.videos.map(\.states.count), takes.map { DreamDataset.videoFrames($0.episode) })
        XCTAssertEqual(plan.frames, 50)
        XCTAssertEqual(plan.videos[1].states[7], takes[1].states[7])
        XCTAssertEqual(Set(plan.files.keys), [DreamDataset.dataPath(0), DreamDataset.dataPath(1), "meta/info.json",
                                              "meta/episodes.jsonl", "meta/tasks.jsonl"])
        let info = try JSONSerialization.jsonObject(with: plan.files["meta/info.json"]!) as! [String: Any]
        XCTAssertEqual(info["total_frames"] as? Int, 50)
        XCTAssertEqual(info["total_episodes"] as? Int, 2)
        XCTAssertEqual(plan.pictures.count, 1)
        XCTAssertEqual(plan.pictures[0].1, takes[1].states[29])
        XCTAssertEqual(plan.pictures[0].0.fileName, "episode1-frame29.png")
        XCTAssertThrowsError(try BallTakes.plan(takes, pictures: [BallTakes.Picture(episode: 0, frame: 20)])) {
            XCTAssertEqual($0 as? BallTakes.PlanRefusal, .pictureOutOfRange(BallTakes.Picture(episode: 0, frame: 20)))
        }
        XCTAssertThrowsError(try BallTakes.plan(takes, pictures: [BallTakes.Picture(episode: 2, frame: 0)]))
        // Dream Labs' own minimum still holds: a take shorter than 17 rows is refused by name.
        XCTAssertThrowsError(try BallTakes.plan(try BallTakes.read(jsonl: Data(line(seed: 3, rows: 16).utf8)))) {
            XCTAssertEqual($0 as? DreamDataset.Refusal, .tooShort(0, 16))
        }
    }

    func testTheJobIsReadFromLaunchArguments() {
        XCTAssertNil(BallTakes.job(arguments: ["/app/DuckStudio"]))
        XCTAssertNil(BallTakes.job(arguments: ["/app/DuckStudio", "-render-takes", "in.jsonl"]))
        XCTAssertEqual(BallTakes.job(arguments: ["/app/DuckStudio", "-render-takes", "in.jsonl", "out"]),
                       BallTakes.Job(input: "in.jsonl", output: "out", pictures: []))
        XCTAssertEqual(BallTakes.job(arguments: ["x", "-render-png", "0:0,3:40,bad,1:-2", "-render-takes", "a", "b"])?.pictures,
                       [BallTakes.Picture(episode: 0, frame: 0), BallTakes.Picture(episode: 3, frame: 40)])
    }

    func testTheCameraDrawsTheBenchBallNotTheFixedOne() throws {
        let take = try BallTakes.read(line: Data(line(seed: 1, rows: 1).utf8), number: 1)
        let ball = DreamPracticeWorld.ball(in: take.states[0])
        XCTAssertEqual(ball.x, -0.5056); XCTAssertEqual(ball.y, -0.5805)
        XCTAssertEqual(ball.z, 0.05); XCTAssertEqual(ball.radius, 0.05)
        // No ball on the bench: the practice world's own, sitting on the floor.
        let none = try DuckDrive.readLive(try JSONSerialization.data(withJSONObject: bench(t: 0, x: 0, ball: nil)))
        XCTAssertNil(none.ball)
        let home = DreamPracticeWorld.ball(in: none)
        XCTAssertEqual(home, DreamPracticeWorld.ball(in: nil))
        XCTAssertEqual(home.x, 0.90); XCTAssertEqual(home.y, -0.45); XCTAssertEqual(home.radius, 0.035)
        XCTAssertEqual(home.z, home.radius)
        // The fixed things never include the ball, so it is never drawn twice.
        XCTAssertEqual(DreamPracticeWorld.fixedThings.map(\.name), ["the red mat", "the blue mat"])
    }

    /// The real takes, when `BALL_TAKES` names the file.
    func testTheRecordedTakesPlanWhenPresent() throws {
        guard let path = ProcessInfo.processInfo.environment["BALL_TAKES"] else {
            throw XCTSkip("set BALL_TAKES to a takes .jsonl to check it")
        }
        let takes = try BallTakes.read(jsonl: try Data(contentsOf: URL(fileURLWithPath: path)))
        let plan = try BallTakes.plan(takes)
        print("BALL_TAKES:", BallTakes.Words.read(takes.count, plan.frames))
        XCTAssertEqual(plan.videos.count, takes.count)
        XCTAssertEqual(plan.frames, takes.reduce(0) { $0 + $1.rows.count })
        XCTAssertTrue(takes.allSatisfy { $0.states.allSatisfy { $0.ball != nil && $0.ballRadius != nil } })
    }
}
