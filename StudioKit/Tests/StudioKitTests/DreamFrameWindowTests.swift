import XCTest
@testable import StudioKit

/// The frame window, held to Dream Labs' own (dreamlabs-client 1.0.14, `dream/_window.py`).
final class DreamFrameWindowTests: XCTestCase {
    func testA30HzCameraKeepsEverySixthEvenWithJitter() {
        var w = DreamFrameWindow()
        var kept: [Int] = []
        for i in 0..<60 {
            let jitter = [0.003, -0.002, 0.001, -0.004][i % 4]
            if w.add("F\(i)", at: 100 + Double(i) / 30 + jitter) { kept.append(i) }
        }
        XCTAssertEqual(kept, [0, 6, 12, 18, 24, 30, 36, 42, 48, 54])
        XCTAssertEqual(w.frames, kept.suffix(9).map { "F\($0)" })
    }

    func testTheDucksFourFpsCameraHasEveryTickKept() {
        var w = DreamFrameWindow()
        for i in 0..<5 { XCTAssertTrue(w.add("F\(i)", at: Double(i) * 0.25)) }
        XCTAssertEqual(w.frames, ["F0", "F1", "F2", "F3", "F4"], "fewer than nine at the start, never padded")
    }

    func testNineAtMostOldestFirst() {
        var w = DreamFrameWindow()
        for i in 0..<20 { w.add("F\(i)", at: Double(i) * 0.2) }
        XCTAssertEqual(w.frames, (11..<20).map { "F\($0)" })
    }

    func testAStalledCameraRestartsTheScheduleFromItsNextTick() {
        var w = DreamFrameWindow()
        w.add("A", at: 0)
        XCTAssertTrue(w.add("B", at: 1.0), "a tick long after its due time is kept")
        XCTAssertFalse(w.add("C", at: 1.05))
        XCTAssertTrue(w.add("D", at: 1.2), "due 0.2 s after B, not on the old schedule")
    }

    func testATickFromThePastOrEmptyIsDropped() {
        var w = DreamFrameWindow()
        w.add("A", at: 5)
        XCTAssertFalse(w.add("B", at: 4))
        XCTAssertFalse(w.add("", at: 6))
        XCTAssertEqual(w.frames, ["A"])
        w.clear()
        XCTAssertTrue(w.add("C", at: 1), "a new run starts a new schedule")
    }
}
