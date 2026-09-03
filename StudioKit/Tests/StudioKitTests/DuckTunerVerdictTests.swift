import XCTest
@testable import StudioKit

/// The verdict a tuned policy is judged by, and the defect that made the old
/// one a coin flip.
///
/// THE NUMBERS HERE ARE MEASURED, NOT INVENTED. Eight seeds of the shipped
/// schedule were replayed on a real bench: every one of the eight winners beat
/// the unchanged network on all eight held-out drops under the command it was
/// searched under, and every one passed every gate this app had. Four of the
/// eight had collapsed sideways travel to 1.6-2.0% of the baseline's while
/// gaining +0.92 to +0.98 of reward. The old verdict could not see it, because
/// it only ever looked forwards.
final class DuckTunerVerdictTests: XCTestCase {

    // MARK: - pairing

    func testPairingSubtractsOnTheSameDropAndRefusesAMismatch() throws {
        let paired = try DuckTuner.pairedDifferences(candidate: [1.0, 2.0, 3.0, 4.0],
                                                     baseline: [0.5, 1.0, 3.5, 4.0])
        XCTAssertEqual(paired, [0.5, 1.0, -0.5, 0.0])
        XCTAssertThrowsError(try DuckTuner.pairedDifferences(candidate: [1, 2, 3, 4],
                                                             baseline: [1, 2, 3])) { error in
            XCTAssertEqual(error as? DuckTuner.PairedRefusal,
                           .differentDropCount(candidate: 4, base: 3))
        }
    }

    /// Three drops is not a spread, and a NaN refuses the whole comparison
    /// rather than being carried around — the same rule `noiseFloor` learned.
    func testTooFewDropsAndANotANumberAreBothRefused() {
        XCTAssertThrowsError(try DuckTuner.pairedDifferences(candidate: [1, 2, 3],
                                                             baseline: [0, 0, 0])) { error in
            XCTAssertEqual(error as? DuckTuner.PairedRefusal, .tooFewDrops(3))
        }
        XCTAssertThrowsError(try DuckTuner.pairedDifferences(candidate: [1, 2, 3, .nan],
                                                             baseline: [0, 0, 0, 0])) { error in
            XCTAssertEqual(error as? DuckTuner.PairedRefusal, .notANumber)
        }
    }

    // MARK: - the verdict

    func testAWinnerOnEveryDropThatKeepsTheWalkSurvives() {
        let verdict = DuckTuner.verdict(paired: [0.6, 0.62, 0.58, 0.61, 0.64, 0.59, 0.63, 0.60],
                                        walkKept: 1.17, command: "vx 0.5")
        XCTAssertEqual(verdict.positive, 8)
        XCTAssertTrue(verdict.survived)
        XCTAssertTrue(verdict.sentence.contains("all 8 drop heights"))
        XCTAssertTrue(verdict.sentence.contains("117%"))
    }

    /// THE DEFECT, AS A TEST. The seed-A winner's real numbers: a large gain
    /// under the sideways command, on every drop, with travel at 2% of the
    /// baseline's. The old rule saw a gain on every drop and passed it.
    func testAWinnerThatGainsRewardByNotMovingSidewaysIsRefused() {
        let farmed = DuckTuner.verdict(
            paired: [0.62, 0.61, 0.60, 0.63, 0.59, 0.64, 0.62, 0.60],
            walkKept: 0.02, command: "vy 0.3")
        XCTAssertEqual(farmed.positive, 8, "it gained on every single drop")
        XCTAssertFalse(farmed.survived, "and it is still refused, because it stopped moving")
        XCTAssertTrue(farmed.sentence.contains("kept 2%"))
        XCTAssertTrue(farmed.sentence.contains("hole in the reward"))
    }

    /// And the whole point: a winner has to survive EVERY command it was
    /// checked under. This is the pair of verdicts four of the eight measured
    /// winners produced.
    func testSurvivingForwardsIsNotSurvivingIfSidewaysCollapsed() {
        let forwards = DuckTuner.verdict(paired: Array(repeating: 0.64, count: 8),
                                         walkKept: 1.17, command: "vx 0.5")
        let sideways = DuckTuner.verdict(paired: Array(repeating: 0.62, count: 8),
                                         walkKept: 0.018, command: "vy 0.3")
        XCTAssertTrue(forwards.survived)
        XCTAssertFalse(DuckTuner.survived([forwards, sideways]))
        let said = DuckTuner.verdictSentence([forwards, sideways])
        XCTAssertTrue(said.contains("vy 0.3"), said)
        XCTAssertTrue(said.contains("It did survive under vx 0.5"), said)
        XCTAssertTrue(said.contains("paid for in another"), said)
    }

    func testAWinnerThatSurvivesBothIsSaidTwice() {
        let forwards = DuckTuner.verdict(paired: Array(repeating: 0.64, count: 8),
                                         walkKept: 1.17, command: "vx 0.5")
        let sideways = DuckTuner.verdict(paired: Array(repeating: 0.10, count: 8),
                                         walkKept: 0.84, command: "vy 0.3")
        XCTAssertTrue(DuckTuner.survived([forwards, sideways]))
        let said = DuckTuner.verdictSentence([forwards, sideways])
        XCTAssertTrue(said.contains("vx 0.5"))
        XCTAssertTrue(said.contains("vy 0.3"))
    }

    /// Seven of eight is not a result, and the sentence says which number it
    /// was rather than only that it failed.
    func testNotEveryDropIsNotAResult() {
        let mixed = DuckTuner.verdict(paired: [0.1, 0.2, -0.05, 0.3, 0.1, 0.2, 0.15, 0.1],
                                      walkKept: 1.0, command: "vx 0.5")
        XCTAssertEqual(mixed.positive, 7)
        XCTAssertFalse(mixed.survived)
        XCTAssertTrue(mixed.sentence.contains("7 of 8"))
    }

    /// No verdicts at all is the aggregate-only bench, and it says so in the
    /// sentence that already existed for it.
    func testNoVerdictsSaysWhatTheOldFloorSaid() {
        XCTAssertFalse(DuckTuner.survived([]))
        XCTAssertEqual(DuckTuner.verdictSentence([]), DuckTuner.noNoiseFloor)
    }

    // MARK: - the commands

    func testTheHeldOutCommandsAreTheOnesTheDefectNeeded() {
        XCTAssertEqual(DuckBench.walkingCommand.last?.vx, 0.5)
        XCTAssertEqual(DuckBench.sidewaysCommand.last?.vy, 0.3)
        XCTAssertEqual(DuckBench.sidewaysCommand.last?.vx, 0)
        XCTAssertEqual(DuckBench.turningCommand.last?.vyaw, 0.6)
        for command in [DuckBench.walkingCommand, DuckBench.sidewaysCommand,
                        DuckBench.turningCommand] {
            XCTAssertEqual(command.first?.at, 0)
            XCTAssertEqual(command.count, 2, "half a second of nothing, then the command")
        }
    }
}
