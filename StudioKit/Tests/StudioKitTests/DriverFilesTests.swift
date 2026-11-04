import XCTest
@testable import StudioKit

/// A phone driver's files, read without trusting them: the weights, the manifest, the prep.
final class DriverFilesTests: XCTestCase {
    // MARK: - safetensors

    func testTensorsRoundTripByNameAndShape() throws {
        let a = SafeTensors.Tensor(shape: [2, 3], values: [1, -2, 3.5, 0, .leastNonzeroMagnitude, 6])
        let b = SafeTensors.Tensor(shape: [3], values: [7, 8, 9])
        let read = try SafeTensors(SafeTensors.encode(["w": a, "b": b], metadata: ["arch": "ducknet-s1"]))
        XCTAssertEqual(read.tensors["w"], a)
        XCTAssertEqual(read.tensors["b"], b)
        XCTAssertEqual(read.metadata["arch"], "ducknet-s1")
    }

    private func file(header: String, body: [UInt8] = Array(repeating: 0, count: 16)) -> Data {
        let json = Array(header.utf8)
        var out = (0..<8).map { UInt8(UInt64(json.count) >> (8 * UInt64($0)) & 0xFF) }
        out += json + body
        return Data(out)
    }

    private func refusal(_ data: Data) -> SafeTensors.Problem? {
        do { _ = try SafeTensors(data); return nil } catch { return error as? SafeTensors.Problem }
    }

    func testEveryLieInAHeaderIsRefusedByName() {
        XCTAssertEqual(refusal(Data([1, 2, 3])), .tooShort)
        var huge = Data((0..<8).map { _ in UInt8(0xFF) }); huge.append(0)
        XCTAssertEqual(refusal(huge), .headerLength(UInt64.max))
        XCTAssertEqual(refusal(file(header: "not json")), .headerNotJSON)
        XCTAssertEqual(refusal(file(header: #"{"w":{"dtype":"F16","shape":[2],"data_offsets":[0,4]}}"#)), .dtype("w", "F16"))
        XCTAssertEqual(refusal(file(header: #"{"w":{"dtype":"F32","shape":[8],"data_offsets":[0,32]}}"#)), .outOfRange("w"))
        XCTAssertEqual(refusal(file(header: #"{"w":{"dtype":"F32","shape":[3],"data_offsets":[0,8]}}"#)), .shapeMismatch("w"))
        XCTAssertEqual(refusal(file(header: #"{"w":{"dtype":"F32","shape":[2],"data_offsets":[0,8]},"v":{"dtype":"F32","shape":[2],"data_offsets":[4,12]}}"#)).map { if case .overlap = $0 { return true } else { return false } }, true)
        XCTAssertEqual(refusal(file(header: #"{"w":{"dtype":"F32","shape":[2]}}"#)), .badEntry("w"))
        // A header that says it is longer than the file.
        var short = file(header: "{}"); short[0] = 200
        XCTAssertEqual(refusal(short), .tooShort)
    }

    // MARK: - the manifest

    static func manifest(_ edit: (inout [String: Any]) -> Void = { _ in }) -> Data {
        var m: [String: Any] = [
            "arch": "ducknet-s1", "format": "safetensors", "task": "walk to the ball", "label": "walk to the ball",
            "input": [6, 88, 160], "frame_offsets": [0, -4], "chunk": 48, "uses_state": false, "trained_on": "sim",
            "img_mean": [0.5, 0.5, 0.5], "img_std": [0.25, 0.25, 0.25],
            "act_mean": [0.1, 0, 0], "act_std": [0.2, 0.1, 0.5],
            "files": ["model.safetensors": ["sha256": String(repeating: "a", count: 64), "bytes": 4_400_000],
                      "golden.json": ["sha256": String(repeating: "b", count: 64), "bytes": 9000]],
        ]
        edit(&m)
        return try! JSONSerialization.data(withJSONObject: m)
    }

    private func problem(_ edit: (inout [String: Any]) -> Void) -> DriverManifest.Problem? {
        do { _ = try DriverManifest.read(Self.manifest(edit)); return nil } catch { return error as? DriverManifest.Problem }
    }

    func testAGoodManifestReads() throws {
        let m = try DriverManifest.read(Self.manifest())
        XCTAssertEqual(m.frameOffsets, [0, -4])
        XCTAssertEqual(m.task, "walk to the ball")
    }

    func testEachWrongFieldIsRefusedByName() {
        XCTAssertEqual(problem { $0["arch"] = "act" }, .arch("act"))
        XCTAssertEqual(problem { $0["format"] = "pt" }, .format("pt"))
        XCTAssertEqual(problem { $0["input"] = [3, 88, 160] }, .shape)
        XCTAssertEqual(problem { $0["frame_offsets"] = [0, -3] }, .shape)
        XCTAssertEqual(problem { $0["chunk"] = 47 }, .chunk(47))
        XCTAssertEqual(problem { $0["uses_state"] = true }, .usesState)
        XCTAssertEqual(problem { $0["trained_on"] = "real" }, .notSim("real"))
        XCTAssertEqual(problem { $0["act_std"] = [0.2, 0, 0.5] }, .stats)
        XCTAssertEqual(problem { $0["files"] = ["../model.safetensors": ["sha256": String(repeating: "a", count: 64), "bytes": 1]] }, .path("../model.safetensors"))
        XCTAssertEqual(problem { $0["files"] = ["/etc/x": ["sha256": String(repeating: "a", count: 64), "bytes": 1]] }, .path("/etc/x"))
        XCTAssertEqual(problem { $0["files"] = ["model.safetensors": ["sha256": String(repeating: "a", count: 64), "bytes": 99_000_000]] }, .tooBig("model.safetensors"))
        XCTAssertEqual(problem { $0["files"] = ["model.safetensors": ["sha256": "abc", "bytes": 1]] }, .hash("model.safetensors"))
        XCTAssertEqual(problem { $0["files"] = ["model.safetensors": ["sha256": String(repeating: "a", count: 64), "bytes": 1]] }, .missing("golden.json"))
        XCTAssertEqual(problem { $0["task"] = "walk\tthere" }, .task(DreamDataset.Refusal.taskHasControl(0).message))
        XCTAssertEqual(problem { $0["arch"] = nil }, .notJSON)
    }

    func testAFileMatchesOnlyByItsHashAndSize() throws {
        let data = Data("weights".utf8)
        let m = try DriverManifest.read(Self.manifest {
            $0["files"] = ["model.safetensors": ["sha256": DriverHash.hex(data), "bytes": data.count],
                           "golden.json": ["sha256": String(repeating: "b", count: 64), "bytes": 1]]
        })
        XCTAssertTrue(m.matches(data, path: "model.safetensors"))
        XCTAssertFalse(m.matches(Data("weightz".utf8), path: "model.safetensors"))
        XCTAssertFalse(m.matches(data, path: "golden.json"))
        XCTAssertEqual(DriverHash.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    // MARK: - prep

    func testTheInputReadsNowAndTwoPlacesBackOrTheOldest() {
        XCTAssertEqual(DriverPrep.places(offsets: [0, -4], count: 9), [8, 6])
        XCTAssertEqual(DriverPrep.places(offsets: [0, -4], count: 3), [2, 0])
        XCTAssertEqual(DriverPrep.places(offsets: [0, -4], count: 2), [1, 0], "the oldest stands in")
        XCTAssertEqual(DriverPrep.places(offsets: [0, -4], count: 1), [0, 0])
    }

    private func picture(_ value: (Int, Int, Int) -> UInt8) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 320 * 176 * 3)
        for y in 0..<176 { for x in 0..<320 { for c in 0..<3 { p[(y * 320 + x) * 3 + c] = value(x, y, c) } } }
        return p
    }

    func testPicturesArePooledNormalisedAndStackedNewestFirst() throws {
        let m = try DriverManifest.read(Self.manifest())
        let old = picture { _, _, _ in 0 }
        // Newest: red channel 255 on even columns, 0 on odd, so each 2x2 block averages 127.5.
        let new = picture { x, _, c in c == 0 && x % 2 == 0 ? 255 : 0 }
        let input = try DriverPrep.input(pictures: [old, old, new], manifest: m)
        let plane = 88 * 160
        XCTAssertEqual(input.values.count, 6 * plane)
        XCTAssertEqual(input.values[0], (0.5 - 0.5) / 0.25, accuracy: 1e-6, "slot 0, red: the newest picture")
        XCTAssertEqual(input.values[plane], (0 - 0.5) / 0.25, accuracy: 1e-6, "slot 0, green")
        XCTAssertEqual(input.values[3 * plane], (0 - 0.5) / 0.25, accuracy: 1e-6, "slot 1, red: the oldest")
        XCTAssertThrowsError(try DriverPrep.input(pictures: [], manifest: m)) { XCTAssertEqual($0 as? DriverPrep.Problem, .noPicture) }
        XCTAssertThrowsError(try DriverPrep.input(pictures: [[1, 2]], manifest: m)) { XCTAssertEqual($0 as? DriverPrep.Problem, .badPicture(0)) }
    }

    func testOutputsBecomeCommandsOrAreRefusedWhole() throws {
        let m = try DriverManifest.read(Self.manifest())
        var flat = [Float](repeating: 0, count: 144)
        flat[0] = 1; flat[143] = -2
        let rows = try DriverPrep.rows(flat, rows: 48, manifest: m)
        XCTAssertEqual(rows.count, 48)
        XCTAssertEqual(rows[0].vx, 0.3, accuracy: 1e-6)
        XCTAssertEqual(rows[47].vyaw, -1.0, accuracy: 1e-6)
        XCTAssertThrowsError(try DriverPrep.rows(Array(flat.prefix(143)), rows: 48, manifest: m))
        flat[5] = .nan
        XCTAssertThrowsError(try DriverPrep.rows(flat, rows: 48, manifest: m)) { XCTAssertEqual($0 as? DriverPrep.Problem, .badOutput(5)) }
    }
}
