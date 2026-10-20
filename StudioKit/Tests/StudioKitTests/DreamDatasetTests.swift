import XCTest
import DuckKit
@testable import StudioKit

/// The duck's dataset. What Dream Labs reads is proved by its own validator: set
/// `DREAM_DATASET_OUT` to a folder and this writes a dataset there, which
/// `scripts/check_dream_dataset.py` gives videos and hands to
/// `dream.datasets.validate_dataset`.
final class DreamDatasetTests: XCTestCase {
    private func take(_ task: String, _ n: Int) -> DreamDataset.Take {
        var t = DreamDataset.Take(task: task)
        for i in 0..<n { t.tick(command: DuckDrive.Twist(vx: 0.01 * Double(i % 30), vy: 0, vyaw: i < 10 ? 0.5 : 0)) }
        return t
    }

    func testStateIsTheLastCommandAndActionTheNext() {
        var t = DreamDataset.Take(task: "x")
        let a = DuckDrive.Twist(vx: 0.2, vy: 0, vyaw: 0), b = DuckDrive.Twist(vx: 0, vy: 0, vyaw: 1)
        t.tick(command: a); t.tick(command: b); t.tick(command: nil)
        XCTAssertEqual(t.rows.map(\.state), [.still, a, b])
        XCTAssertEqual(t.rows.map(\.action), [a, b, .still])
    }

    func testShortRunsAndEmptyTasksAreRefusedByName() {
        XCTAssertThrowsError(try DreamDataset.files([])) { XCTAssertEqual($0 as? DreamDataset.Refusal, .noEpisodes) }
        XCTAssertThrowsError(try DreamDataset.files([take("walk", 16).episode])) {
            XCTAssertEqual($0 as? DreamDataset.Refusal, .tooShort(0, 16))
        }
        XCTAssertThrowsError(try DreamDataset.files([take("  ", 40).episode])) {
            XCTAssertEqual($0 as? DreamDataset.Refusal, .emptyTask(0))
        }
        XCTAssertEqual(DreamDataset.minimumRows, 17)
    }

    func testTheLayoutIsLeRobots() throws {
        let files = try DreamDataset.files([take("walk to the red mat", 40).episode, take("turn left", 25).episode,
                                            take("walk to the red mat", 30).episode])
        XCTAssertEqual(Set(files.keys), ["meta/info.json", "meta/episodes.jsonl", "meta/tasks.jsonl",
                                         "data/chunk-000/episode_000000.parquet",
                                         "data/chunk-000/episode_000001.parquet",
                                         "data/chunk-000/episode_000002.parquet"])
        let info = try XCTUnwrap(JSONSerialization.jsonObject(with: files["meta/info.json"]!) as? [String: Any])
        XCTAssertEqual(info["total_frames"] as? Int, 95)
        XCTAssertEqual(info["fps"] as? Int, 10)
        XCTAssertEqual(String(decoding: files["meta/tasks.jsonl"]!, as: UTF8.self),
                       #"{"task":"walk to the red mat","task_index":0}"# + "\n" + #"{"task":"turn left","task_index":1}"# + "\n")
        XCTAssertEqual(DreamDataset.videoPath(2), "videos/chunk-000/observation.images.head/episode_000002.mp4")
        let parquet = files["data/chunk-000/episode_000000.parquet"]!
        XCTAssertEqual(parquet.prefix(4), Data("PAR1".utf8))
        XCTAssertEqual(parquet.suffix(4), Data("PAR1".utf8))
    }

    func testThriftVarintsAndZigzag() {
        XCTAssertEqual(Thrift.varint(300), Data([0xAC, 0x02]))
        XCTAssertEqual(Thrift.zigzag32(-1), 1)
        XCTAssertEqual(Thrift.zigzag32(1), 2)
        XCTAssertEqual(Thrift.zigzag64(-3), 5)
    }

    func testWriteADatasetForDreamLabsChecks() throws {
        guard let out = ProcessInfo.processInfo.environment["DREAM_DATASET_OUT"] else {
            throw XCTSkip("set DREAM_DATASET_OUT to write a dataset for scripts/check_dream_dataset.py")
        }
        let root = URL(fileURLWithPath: out).appendingPathComponent("microduck-test")
        try? FileManager.default.removeItem(at: root)
        let files = try DreamDataset.files([take("walk to the red mat", 40).episode, take("turn left", 25).episode])
        for (path, data) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }
}

/// The simulated head camera's pose, from DuckKit's kinematics.
final class SimHeadCameraTests: XCTestCase {
    func testAtHomeItSitsOnTheHeadAndLooksAhead() {
        let p = SimHeadCamera.pose(rootPosition: DuckVector(0, 0, 0.12), rootOrientation: DuckQuaternion(w: 1, x: 0, y: 0, z: 0),
                                   jointAngles: DuckModel.homePose)
        // DuckKinematics: "the camera site 24 cm up" on a 25 cm duck.
        XCTAssertEqual(p.position.z, 0.24, accuracy: 0.03)
        // Ahead, and somewhat down at most: a duck that looked behind itself would be Pollen's MJCF bug.
        XCTAssertGreaterThan(p.forward.x, 0.8, "forward \(p.forward)")
        XCTAssertGreaterThan(p.up.z, 0.8, "up \(p.up)")
        XCTAssertEqual(p.forward.x * p.up.x + p.forward.y * p.up.y + p.forward.z * p.up.z, 0, accuracy: 1e-6)
    }

    func testTurningTheRootTurnsTheView() {
        let s = 0.5.squareRoot()
        let p = SimHeadCamera.pose(rootPosition: DuckVector(1, 2, 0.12), rootOrientation: DuckQuaternion(w: s, x: 0, y: 0, z: s),
                                   jointAngles: DuckModel.homePose)
        XCTAssertGreaterThan(p.forward.y, 0.8, "a quarter turn left looks along +y: \(p.forward)")
        XCTAssertEqual(p.position.x, 1, accuracy: 0.05)
    }

    func testThePracticeWorldHasTheThingsItsTasksName() {
        for task in DreamPracticeWorld.tasks.prefix(3) {
            XCTAssertTrue(DreamPracticeWorld.things.contains { task.hasSuffix($0.name) }, task)
        }
        XCTAssertEqual(DreamPracticeWorld.tape.count, 6 + 4)
    }
}
