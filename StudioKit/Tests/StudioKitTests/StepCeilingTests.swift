import XCTest
@testable import StudioKit

/// The step ceiling is a measurement with its count attached, and it refuses
/// to say anything about a rise its check cannot see.
final class StepCeilingTests: XCTestCase {
    func testTheShippedCeilingCarriesItsProvenanceAndClearsNothingAsShipped() {
        let c = StepCeiling.current
        XCTAssertEqual(c.metres, 0)
        XCTAssertEqual(c.repairedMetres, 0.060)
        XCTAssertEqual(c.clearedRises, [0.040, 0.060])
        XCTAssertEqual(c.rounds, 2)
        XCTAssertEqual(c.episodes, 21_000)
        XCTAssertFalse(c.criterion.isEmpty)
        XCTAssertTrue(c.evidence.contains("audit_r2"))
        XCTAssertEqual(c.measuredOn, "2026-09-02")
        XCTAssertLessThan(c.editorRise, c.resolvableAbove)
        XCTAssertLessThan(c.resolvableAbove, c.clearedRises[0])
        XCTAssertGreaterThan(c.shippedFlightSoundAbove, c.repairedMetres,
                             "the clears live below the rise where the shipped flight is sound")
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

    /// ABOVE THE REPAIRED CEILING: the count, the rounds, and "as shipped".
    func testARiseAboveEverythingGetsTheSearchCountInWords() {
        let c = StepCeiling.current
        XCTAssertTrue(c.canResolve(rise: 0.193))
        let said = c.verdict(rise: 0.193)
        XCTAssertTrue(said.hasPrefix("A 193 mm rise."), said)
        XCTAssertTrue(said.contains("Nothing above 60 mm has cleared in roughly 21,000 searched attempts over 2 rounds"), said)
        XCTAssertTrue(said.contains("on the staircase as shipped nothing has cleared at all"), said)
        XCTAssertTrue(said.contains("nothing this app has can be shown to get up this one"), said)
        XCTAssertFalse(said.contains("measured at 10"), said)
        XCTAssertFalse(said.contains("0 of 54"), said)
    }

    /// AT A CLEARED RISE: once, from one exact start, dead 10 mm either side,
    /// zero as shipped. Never "the robot can climb 40 mm".
    func testAClearedRiseIsCalledACoincidenceNotAClimb() {
        let c = StepCeiling.current
        XCTAssertTrue(c.clearedOnRepairedFlight(rise: 0.040))
        XCTAssertFalse(c.clearedOnRepairedFlight(rise: 0.045))
        let said = c.verdict(rise: 0.040)
        XCTAssertTrue(said.hasPrefix("A 40 mm rise. In simulation, on a staircase repaired"), said)
        XCTAssertTrue(said.contains("got up this rise once, from one exact start, and not at 10 mm either side"), said)
        XCTAssertTrue(said.contains("On the staircase as shipped it scores zero"), said)
        XCTAssertTrue(said.contains("One coincidence is not a climb"), said)
        XCTAssertFalse(said.contains("can climb"), said)
    }

    /// BETWEEN THE FLOOR AND THE REPAIRED CEILING, but not a cleared rise:
    /// the two clears are named and the gap between them is said to be empty.
    func testARiseBetweenTheClearsNamesThemAndTheGap() {
        let said = StepCeiling.current.verdict(rise: 0.050)
        XCTAssertTrue(said.contains("got up a 40 mm step and a 60 mm step once each and nothing in between"), said)
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
        XCTAssertTrue(unreachable[0].text.contains("as shipped nothing has cleared"), unreachable[0].text)
        XCTAssertFalse(unreachable[0].text.contains("has been measured at"), unreachable[0].text)
        // The old alias still names the editor's rise, not a ceiling.
        XCTAssertEqual(DuckScene.measuredStepCeiling, StepCeiling.current.editorRise)
    }

    func testTheFooterSentenceSaysEverythingAtOnce() {
        let s = StepCeiling.current.says
        for piece in ["In simulation only", "repaired so its step blocks stop colliding", "21,000",
                      "a beak-strut vault onto a 40 mm step and a 60 mm step", "audit_r2", "2026-09-02",
                      "1 of 7", "3 of 7", "Nothing above 60 mm has cleared", "as shipped both score zero",
                      "under 11 mm", "Criterion:"] {
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
