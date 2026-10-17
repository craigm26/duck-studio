import Foundation
import XCTest
@testable import StudioKit

/// duck-card-loop/3's drift calibration: the vectors cardreader's `DriftCal` writes, op by op.
final class DuckDriftCalTests: XCTestCase {
    struct Vector: Decodable {
        let calibrate: DuckCardLoop.Spec.Calibrate
        let ops: [[Op]]
    }
    enum Op: Decodable {
        case word(String), number(Double), list([Double]), pairs([[Double]])
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .word(s) }
            else if let d = try? c.decode(Double.self) { self = .number(d) }
            else if let l = try? c.decode([Double].self) { self = .list(l) }
            else { self = .pairs(try c.decode([[Double]].self)) }
        }
    }

    func testEveryVector() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/DuckCards/vectors/driftcal", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertGreaterThanOrEqual(files.count, 7)
        for f in files {
            let v = try JSONDecoder().decode(Vector.self, from: Data(contentsOf: f))
            var cal = DuckCardLoop.DriftCal(v.calibrate)
            let name = f.lastPathComponent
            for op in v.ops {
                switch (op[0], op[1], op[2]) {
                case (.word("still"), .pairs(let samples), .number(let rate)):
                    cal.beginStill()
                    for s in samples { cal.sampleStill(t: s[0], yaw: s[1]) }
                    cal.endStill()
                    XCTAssertEqual(cal.rate, rate, accuracy: 1e-8, name)
                case (.word("correct"), .list(let raw), .list(let want)):
                    let p = cal.correct(t: raw[0], DuckCardLoop.Pose(x: raw[1], y: raw[2], h: raw[3]))
                    XCTAssertEqual(p.x, want[0], accuracy: 1e-8, name)
                    XCTAssertEqual(p.y, want[1], accuracy: 1e-8, name)
                    XCTAssertEqual(p.h, want[2], accuracy: 1e-8, name)
                default:
                    XCTFail("\(name): an op that is neither still nor correct")
                }
            }
        }
    }

    func testAThreeSpecReadsAndTheShippedSpecDoesNotCalibrate() throws {
        let shipped = try Data(contentsOf: XCTUnwrap(DuckCardLoop.specURL))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: shipped) as? [String: Any])
        XCTAssertNil(DuckCardLoop.spec.calibrate)
        XCTAssertFalse(DuckCardLoop.spec.enabledOnRobot)
        json["format"] = "duck-card-loop/3"
        json["calibrate"] = ["before_s": 5.0, "still_after_s": 0.3, "max_dps": 1.0]
        let three = try DuckCardLoop.Spec.read(JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(three.calibrate?.beforeS, 5.0)
        json["format"] = "duck-card-loop/2"
        XCTAssertThrowsError(try DuckCardLoop.Spec.read(JSONSerialization.data(withJSONObject: json)))
    }
}
