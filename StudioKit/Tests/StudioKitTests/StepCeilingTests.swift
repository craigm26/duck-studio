import XCTest
@testable import StudioKit

/// The step ceiling is a measurement with its count attached, and it refuses
/// to say anything about a rise its check cannot see.
final class StepCeilingTests: XCTestCase {
    func testTheShippedCeilingCarriesItsProvenanceAndClearsNothingReliably() {
        let c = StepCeiling.current
        XCTAssertEqual(c.metres, 0)
        XCTAssertEqual(c.attempts.map(\.rise), [0.040, 0.050, 0.060, 0.070, 0.080])
        XCTAssertEqual(c.attempts.map(\.cleared), [2, 2, 4, 2, 1])
        XCTAssertEqual(c.oneVectorFrom, 0.060)
        XCTAssertEqual(c.stableClears, 10)
        XCTAssertEqual(c.clearsInAll, 11)
        XCTAssertTrue(c.attempts.allSatisfy { $0.of == 9 && $0.cleared < c.reliableCleared },
                      "nothing reaches the reliable bar: \(c.attempts)")
        XCTAssertEqual(c.tallestAnyCell, 0.080)
        XCTAssertEqual(c.rounds, 4)
        XCTAssertEqual(c.episodes, 48_000)
        XCTAssertFalse(c.criterion.isEmpty)
        XCTAssertTrue(c.evidence.contains("r4_judge"))
        XCTAssertEqual(c.measuredOn, "2026-09-02")
        XCTAssertLessThan(c.editorRise, c.resolvableAbove)
        XCTAssertLessThan(c.resolvableAbove, c.attempts[0].rise)
    }

    /// BELOW THE FLOOR, NO VERDICT. A foot on the floor passes the check's
    /// height test for any rise under about 11 mm, so a number there would be
    /// a number about the check, not about the robot.
    func testARiseTheCheckCannotResolveGetsNoVerdictEitherWay() {
        let c = StepCeiling.current
        XCTAssertFalse(c.canResolve(rise: 0.010))
        let said = c.verdict(rise: 0.010)
        XCTAssertTrue(said.contains("cannot tell a foot on the tread from a foot on the floor"), said)
        XCTAssertFalse(said.contains("measured at"), said)
        XCTAssertFalse(said.contains("will not get up"), said)
    }

    /// ABOVE EVERY CELL: the search count, the rounds, and 0 of 9.
    func testARiseAboveEverythingGetsTheSearchCountInWords() {
        let c = StepCeiling.current
        XCTAssertTrue(c.canResolve(rise: 0.193))
        let said = c.verdict(rise: 0.193)
        XCTAssertTrue(said.hasPrefix("A 193 mm rise."), said)
        XCTAssertTrue(said.contains("Nothing has got up 90 mm or taller in any of roughly 48,000 searched attempts over 4 rounds"), said)
        XCTAssertTrue(said.contains("(0 of 9 perturbed attempts)"), said)
        XCTAssertTrue(said.contains("nothing this app has can be shown to get up this one"), said)
        XCTAssertFalse(said.contains("measured at 10"), said)
        XCTAssertFalse(said.contains("0 of 54"), said)
    }

    /// AT A RISE ON THE GRID: k of 9, never reliably, with both controls.
    /// Never "the robot can climb 60 mm".
    func testARiseOnTheGridIsCalledUnreliableNotAClimb() {
        let c = StepCeiling.current
        XCTAssertEqual(c.attempt(at: 0.060)?.cleared, 4)
        XCTAssertNil(c.attempt(at: 0.065))
        let said = c.verdict(rise: 0.060)
        XCTAssertTrue(said.hasPrefix("A 60 mm rise. In simulation, on the simulator's four-step staircase, repaired"), said)
        XCTAssertTrue(said.contains("gets up this rise in 4 of 9 perturbed attempts"), said)
        XCTAssertTrue(said.contains("never reliably"), said)
        XCTAssertTrue(said.contains("a duck placed on the tread passes 9 of 9 and doing nothing 0 of 9"), said)
        XCTAssertTrue(said.contains("Unreliable at every height is not a climb"), said)
        XCTAssertFalse(said.contains("can climb"), said)
    }

    /// BETWEEN THE GRID'S RISES: the whole row is named and nothing is reliable.
    func testARiseBetweenTheGridsRisesNamesTheWholeRow() {
        let said = StepCeiling.current.verdict(rise: 0.045)
        XCTAssertTrue(said.contains("gets up 40 mm in 2 of 9, 50 mm in 2 of 9, 60 mm in 4 of 9, 70 mm in 2 of 9 and 80 mm in 1 of 9 perturbed attempts"), said)
        XCTAssertTrue(said.contains("(the 60, 70 and 80 mm figures are one move scored at 3 heights)"), said)
        XCTAssertTrue(said.contains("and nothing reliably"), said)
        XCTAssertTrue(said.contains("nothing this app has can be shown to get up this one"), said)
    }

    /// The scene's own problems list uses the measurement's sentence and is
    /// silent under the resolvable floor.
    func testTheSceneProblemsUseTheMeasurementsSentence() {
        let quiet = DuckScene.staircase(count: 2, rise: 0.010)
        XCTAssertFalse(quiet.problems.contains { $0.severity == .unreachable }, "\(quiet.problems)")
        let flagged = DuckScene.staircase(count: 1, rise: 0.193)
        let unreachable = flagged.problems.filter { $0.severity == .unreachable }
        XCTAssertEqual(unreachable.count, 1)
        XCTAssertTrue(unreachable[0].text.contains("Nothing has got up 90 mm or taller"), unreachable[0].text)
        XCTAssertFalse(unreachable[0].text.contains("has been measured at"), unreachable[0].text)
        // The old alias still names the editor's rise, not a ceiling.
        XCTAssertEqual(DuckScene.measuredStepCeiling, StepCeiling.current.editorRise)
    }

    func testTheFooterSentenceSaysEverythingAtOnce() {
        let s = StepCeiling.current.says
        for piece in ["In simulation only", "4 rounds", "48,000", "unreliable at every height",
                      "a beak-strut vault", "40 mm in 2 of 9", "60 mm in 4 of 9", "70 mm in 2 of 9",
                      "80 mm in 1 of 9", "one move scored at 3 heights",
                      "0 of 9 at 90 mm or taller", "10 of those 11 clears still upright fifty ticks later",
                      "9 of 9 for a duck placed on the tread",
                      "0 of 9 for doing nothing", "r4_judge", "2026-09-02", "under 11 mm"] {
            XCTAssertTrue(s.contains(piece), "\(piece) missing from: \(s)")
        }
        XCTAssertFalse(s.contains("0 of 54"), s)
    }

    /// Anyone who saw the old count is told why it is gone, with the number
    /// the instrument was broken below.
    func testTheOldCountIsExplainedNotErased() {
        let s = StepCeiling.current.whyTheOldCountIsGone
        XCTAssertTrue(s.contains("0 of 54"), s)
        XCTAssertTrue(s.contains("under 150 mm"), s)
        XCTAssertTrue(s.contains("measured the staircase, not the robot"), s)
    }

    func testTheEditorSentenceNeverClaimsAMeasuredClear() {
        let s = StepCeiling.current.editorSentence
        XCTAssertTrue(s.hasPrefix("The staircase starts at 10 mm a step."), s)
        XCTAssertTrue(s.contains("not a rise the robot is known to clear"), s)
        XCTAssertFalse(s.contains("measured to clear"), s)
    }
}
