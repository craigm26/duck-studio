import XCTest
@testable import StudioKit

/// The stage-overlay rule as numbers: a line over the live picture is one row, 60 points at most,
/// and expands into a quarter of the stage at most, so it cannot reach the pad.
///
/// The case is build 96's screenshot of Play > Drive: a run's report drawn in full, twice.
final class StageLineTests: XCTestCase {

    private func outcome(achieves: Int = 1, rollouts: Int = 1,
                     height: Double? = nil) -> Pipeline.BenchOutcome {
        Pipeline.BenchOutcome(when: Date(timeIntervalSince1970: 0), bench: "duck-bench",
                              plantName: "scene.mjb", plantDigest: String(repeating: "a", count: 64),
                              policy: "alpha_walking", achieves: achieves, rollouts: rollouts,
                              criterion: "stayed upright to the end, dropped from 0.120 m",
                              medianHeight: height, askedForWorld: false)
    }

    func testTheCollapsedLineFitsTheOverlayBudget() {
        XCTAssertLessThanOrEqual(StageLine.collapsedMaxHeight, 60)
        XCTAssertLessThanOrEqual(StageLine.expandedMaxShare, 0.25,
                                 "an expanded line at the top must not reach the pad at the bottom")
        XCTAssertEqual(StageLine.expandedMaxHeight(stage: 800), 200)
        XCTAssertEqual(StageLine.expandedMaxHeight(stage: 100), StageLine.collapsedMaxHeight,
                       "never smaller than one collapsed line")
    }

    /// The screenshot's line, collapsed to what Craig asked for and nothing more.
    func testARunsReportCollapsesToOneShortLine() {
        let ran = outcome()
        let full = [ran.told, ControlShelf.thisIsTheRun].joined(separator: " ")
        let line = StageLine(full, short: ran.short)
        XCTAssertEqual(line.short, "Stayed upright to the end, dropped from 0.120 m")
        XCTAssertTrue(line.hasMore)
        XCTAssertEqual(line.full, full, "the whole report is still one tap away")
        XCTAssertLessThanOrEqual(line.short.count, StageLine.shortMaxCharacters)
        XCTAssertFalse(line.short.contains("\n"))
        XCTAssertFalse(line.short.contains("sha256"))
    }

    func testARunThatDidNotAlwaysMeetItSaysTheCount() {
        XCTAssertEqual(outcome(achieves: 3, rollouts: 8).short,
                       "3 of 8 stayed upright to the end, dropped from 0.120 m")
        XCTAssertTrue(outcome(height: 0.05).short.hasSuffix(", ends low"))
    }

    /// With no short form given, the first sentence, held to the budget.
    func testAnyLongLineFallsBackToItsFirstSentenceHeldToTheBudget() {
        let line = StageLine("Loaded the walk. It is on the servos now, and the sticks drive it.")
        XCTAssertEqual(line.short, "Loaded the walk")
        let long = StageLine(String(repeating: "word ", count: 40))
        XCTAssertLessThanOrEqual(long.short.count, StageLine.shortMaxCharacters)
        XCTAssertTrue(long.short.hasSuffix("\u{2026}"))
        XCTAssertFalse(StageLine("Stopped").hasMore, "a short line has nothing to expand")
        XCTAssertEqual(StageLine("Stopped.").short, "Stopped")
    }

    func testAnEmptyShortFormIsIgnored() {
        XCTAssertEqual(StageLine("One. Two.", short: "  ").short, "One")
    }
}
