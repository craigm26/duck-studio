import XCTest
@testable import StudioKit

final class StopWordsTests: XCTestCase {

    func testFiresOnAVolatilePartialBeforeTheSentenceEnds() {
        var heard = StopWords()
        XCTAssertFalse(heard.hear("walk the"))
        XCTAssertTrue(heard.hear("walk the duck st... stop"))
    }

    func testFiresOncePerUtterance() {
        var heard = StopWords()
        XCTAssertTrue(heard.hear("stop"))
        XCTAssertFalse(heard.hear("stop"))
        XCTAssertFalse(heard.hear("stop stop freeze"))
        heard.begin()
        XCTAssertTrue(heard.hear("freeze"))
    }

    func testWholeWordsOnly() {
        for miss in ["stopwatch", "I know", "nobody moved", "nose", "freezer", "unstoppable", ""] {
            XCTAssertFalse(StopWords.containsStop(miss), miss)
        }
        for hit in ["Stop", "STOP!", "stop, please", "freeze.", "No", "no-no", "Stóp", "FRÉEZE",
                    "okay\nstop", "duck: stop?"] {
            XCTAssertTrue(StopWords.containsStop(hit), hit)
        }
    }

    func testStopwatchNeverFiresAcrossPartials() {
        var heard = StopWords()
        // The recognizer's partials grow word by word; "stopwatch" never contains "stop" as a word.
        XCTAssertFalse(heard.hear("start the"))
        XCTAssertFalse(heard.hear("start the stopwatch"))
        XCTAssertFalse(heard.hear("start the stopwatch now"))
        XCTAssertFalse(heard.fired)
    }

    func testFiringGoesThroughStopPath() {
        let path = StopPath()
        var heard = StopWords()
        XCTAssertNil(heard.hear("walk forward", stopping: path))
        XCTAssertTrue(path.admits)
        XCTAssertEqual(heard.hear("no no", stopping: path)?.caption, StopPath.Words.stopped)
        XCTAssertFalse(path.admits)
        XCTAssertNil(heard.hear("no", stopping: path))
    }

    func testNoModelIsNamed() throws {
        let src = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/StudioKit/StopWords.swift"), encoding: .utf8)
        let imports = src.split(separator: "\n").filter { $0.hasPrefix("import ") }
        XCTAssertEqual(imports, ["import Foundation"])
        XCTAssertFalse(src.contains("\u{2014}"))
    }
}
