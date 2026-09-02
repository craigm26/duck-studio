import XCTest
@testable import StudioKit

/// The step ceiling is a measurement with its count attached, and it refuses
/// to say anything about a rise its check cannot see.
final class StepCeilingTests: XCTestCase {
    func testTheShippedCeilingCarriesItsProvenanceAndClearsNothing() {
        let c = StepCeiling.current
        XCTAssertEqual(c.metres, 0)
        XCTAssertEqual(c.cleared, 0)
        XCTAssertEqual(c.of, 54)
        XCTAssertEqual(c.moves.count, 2)
        XCTAssertTrue(c.moves[0].contains("searched"))
        XCTAssertFalse(c.criterion.isEmpty)
        XCTAssertEqual(c.plantDigest, "3f8c9ab9b409")
        XCTAssertEqual(c.measuredOn, "2026-09-01")
        XCTAssertLessThan(c.editorRise, c.resolvableAbove)
        XCTAssertLessThan(c.resolvableAbove, c.triedFrom)
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

    /// ABOVE IT, THE COUNT, THE PLANT AND THE DATE. Never "measured at 10 mm".
    func testARiseTheCheckCanResolveGetsTheMeasurementInWords() {
        let c = StepCeiling.current
        XCTAssertTrue(c.canResolve(rise: 0.193))
        let said = c.verdict(rise: 0.193)
        XCTAssertTrue(said.hasPrefix("A 193 mm rise."), said)
        XCTAssertTrue(said.contains("cleared 0 of 54 audited replays at rises from 20 to 180 mm"), said)
        XCTAssertTrue(said.contains("scene.mjb (3f8c9ab9b409, 2026-09-01)"), said)
        XCTAssertTrue(said.contains("nothing this app has can be shown to get up this one"), said)
        XCTAssertFalse(said.contains("measured at 10"), said)
    }

    /// The scene's own problems list uses the measurement's sentence and is
    /// silent under the resolvable floor.
    func testTheSceneProblemsUseTheMeasurementsSentence() {
        let quiet = DuckScene.staircase(count: 2, rise: 0.010)
        XCTAssertFalse(quiet.problems.contains { $0.severity == .unreachable }, "\(quiet.problems)")
        let flagged = DuckScene.staircase(count: 1, rise: 0.193)
        let unreachable = flagged.problems.filter { $0.severity == .unreachable }
        XCTAssertEqual(unreachable.count, 1)
        XCTAssertTrue(unreachable[0].text.contains("cleared 0 of 54"), unreachable[0].text)
        XCTAssertFalse(unreachable[0].text.contains("has been measured at"), unreachable[0].text)
        // The old alias still names the editor's rise, not a ceiling.
        XCTAssertEqual(DuckScene.measuredStepCeiling, StepCeiling.current.editorRise)
    }

    func testTheFooterSentenceSaysEverythingAtOnce() {
        let s = StepCeiling.current.says
        for piece in ["Measured 2026-09-01", "scene.mjb", "0 of 54", "20 to 180", "under 11 mm", "Criterion:"] {
            XCTAssertTrue(s.contains(piece), "\(piece) missing from: \(s)")
        }
    }

    func testTheEditorSentenceNeverClaimsAMeasuredClear() {
        let s = StepCeiling.current.editorSentence
        XCTAssertTrue(s.hasPrefix("The staircase starts at 10 mm a step."), s)
        XCTAssertTrue(s.contains("not a rise the robot is known to clear"), s)
        XCTAssertFalse(s.contains("measured to clear"), s)
    }
}
