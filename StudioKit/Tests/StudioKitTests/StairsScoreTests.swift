import XCTest
@testable import StudioKit

/// The aggregation, against the audit's own published numbers.
///
/// THE FIXTURES ARE REAL CELLS. Each file under `Fixtures/stairs` is the
/// fourteen answers `climb/robust.mjs` produces for one intent at a 60 mm
/// rise, written into the shape the `/climb` contract specifies, on
/// 2026-09-02, in the plant `scene.mjb` (`3f8c9ab9b409…`). Their core-cell
/// verdicts reproduce `climb/r6_judge-results.json` → `phaseG` → `cellsXZ`
/// row for row, so anything this counts is countable against the published
/// table by anybody with both files.
final class StairsScoreTests: XCTestCase {

    struct Fixture {
        let rise: Double
        let sha: String
        let answers: [DuckBench.Climbed]
        let rows: [HarnessJSON]

        /// The same answers with the bench's plant digest swapped, or removed
        /// when nil — done on the row text, so the reader is the shipped one.
        func answers(replacingPlant digest: String?) throws -> [DuckBench.Climbed] {
            try rows.map { row in
                var text = String(decoding: row.encoded(.compact), as: UTF8.self)
                let range = text.range(of: #""plantDigest":"[0-9a-f]+""#, options: .regularExpression)
                guard let range else { return try DuckBench.readClimbed(Data(text.utf8)) }
                text.replaceSubrange(range, with: digest.map { #""plantDigest":"\#($0)""# }
                                                   ?? #""plantDigestRemoved":true"#)
                return try DuckBench.readClimbed(Data(text.utf8))
            }
        }
    }

    /// Read through `HarnessJSON`, the same door the app reads a live bench
    /// through, so the fixture's digits arrive as the digits the harness wrote
    /// rather than as whatever a second parser rounds them to.
    func fixture(_ name: String) throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/stairs/\(name)",
                                                  withExtension: "json"),
                                "\(name) is not in the test bundle")
        let top = try HarnessJSON.parse(try Data(contentsOf: url))
        let rise = try XCTUnwrap(top["rise"]?.doubleValue)
        let sha = try XCTUnwrap(top["sha256"]?.stringValue)
        let rows = try XCTUnwrap(top["answers"]?.arrayValue)
        let answers = try rows.map { try DuckBench.readClimbed($0.encoded(.compact)) }
        return Fixture(rise: rise, sha: sha, answers: answers, rows: rows)
    }

    // MARK: - the record

    /// THE AUDITED NUMBER. `climb/r6_judge-results.json` → `phaseG` →
    /// `best_r6_ceilvaultC_60mm.json`: kCore 5, kCoreStable 5, kExt 5,
    /// kExtStable 5, ceilingCore 5, maxTq 0.6405, at a 60 mm rise. If this
    /// aggregation ever stops reproducing those five numbers from the cells
    /// that produced them, every score the app shows is its own invention.
    func testTheRecordsFourteenCellsReproducePhaseG() throws {
        let fixture = try fixture("best_r6_ceilvaultC_60mm-climb")
        XCTAssertEqual(fixture.answers.count, 14)
        let score = StairsChallenge.Score(rise: fixture.rise, cells: fixture.answers)

        XCTAssertEqual(score.kCore, 5)
        XCTAssertEqual(score.kCoreStable, 5)
        XCTAssertEqual(score.kExt, 5)
        XCTAssertEqual(score.kExtStable, 5)
        XCTAssertEqual(score.ceilingCore, 5)
        XCTAssertEqual(score.maxTorque, 0.6405)
        XCTAssertEqual(score.coreAnswered, 9)
        XCTAssertEqual(score.answered, 14)
        XCTAssertEqual(score.invalidCells, 0)
        XCTAssertEqual(score.hash, fixture.sha)
        XCTAssertEqual(score.hash?.prefix(12), "a56d459fb649")
        XCTAssertEqual(score.plantDigest, StairsChallenge.plantDigest)
        XCTAssertTrue(score.isComplete)
        XCTAssertTrue(score.isPublishable)
        // FIVE IS NOT SEVEN. The record does not meet the bar.
        XCTAssertFalse(score.meetsBar)
    }

    /// The other four rows of the audited set, so the aggregation is checked
    /// against a spread and not against one number it could match by accident.
    func testTheStandingRecordThroughRoundFiveIsFourOfNine() throws {
        let fixture = try fixture("best_r3_vault_60mm-climb")
        let score = StairsChallenge.Score(rise: fixture.rise, cells: fixture.answers)
        XCTAssertEqual(score.hash?.prefix(12), "4b9110c448ec")
        XCTAssertEqual([score.kCore, score.kCoreStable, score.kExt, score.kExtStable],
                       [4, 4, 4, 4])
        // Its ceiling is 5 and it landed 4 — the gap the round-6 search closed.
        XCTAssertEqual(score.ceilingCore, 5)
    }

    /// THE TWO CONTROLS ARE WHAT MAKE THE CRITERION BELIEVABLE. A duck spawned
    /// on the tread passes everything; a duck that stands still passes
    /// nothing. An aggregation that failed either would be measuring something
    /// other than climbing.
    func testThePlacedDuckPassesEverythingAndTheDoNothingDuckPassesNothing() throws {
        let placed = try fixture("r4_ctrl_on_tread_60mm-climb")
        let placedScore = StairsChallenge.Score(rise: placed.rise, cells: placed.answers)
        XCTAssertEqual(placedScore.hash?.prefix(12), "d99589396fcb")
        XCTAssertEqual([placedScore.kCore, placedScore.kCoreStable,
                        placedScore.kExt, placedScore.kExtStable], [9, 9, 14, 14])
        XCTAssertEqual(placedScore.ceilingCore, 9)
        XCTAssertTrue(placedScore.meetsBar)

        let still = try fixture("ctrl_do_nothing-climb")
        let stillScore = StairsChallenge.Score(rise: still.rise, cells: still.answers)
        XCTAssertEqual(stillScore.hash?.prefix(12), "c703ee6f5a14")
        XCTAssertEqual([stillScore.kCore, stillScore.kCoreStable,
                        stillScore.kExt, stillScore.kExtStable], [0, 0, 0, 0])
        XCTAssertEqual(stillScore.ceilingCore, 0)
        XCTAssertFalse(stillScore.meetsBar)
        // It never even crosses the riser line.
        XCTAssertEqual(stillScore.cells.filter(\.reachedFlight).count, 0)
    }

    /// Each fixture's four aggregates equal the leaderboard row for the same
    /// file. The typed table and the arithmetic are checked against each other
    /// rather than both against nothing.
    func testEachFixtureAgreesWithItsPublishedRow() throws {
        let pairs = [("best_r6_ceilvaultC_60mm-climb", "best_r6_ceilvaultC_60mm.json"),
                     ("best_r3_vault_60mm-climb", "best_r3_vault_60mm.json"),
                     ("r4_ctrl_on_tread_60mm-climb", "r4_ctrl_on_tread_60mm.json"),
                     ("ctrl_do_nothing-climb", "ctrl_do_nothing.json")]
        for (name, file) in pairs {
            let fixture = try fixture(name)
            let score = StairsChallenge.Score(rise: fixture.rise, cells: fixture.answers)
            let row = try XCTUnwrap(StairsChallenge.row(file: file))
            XCTAssertEqual(score.kCore, row.kCore, file)
            XCTAssertEqual(score.kCoreStable, row.kCoreStable, file)
            XCTAssertEqual(score.kExt, row.kExt, file)
            XCTAssertEqual(score.kExtStable, row.kExtStable, file)
            XCTAssertEqual(score.ceilingCore, row.ceilingCore, file)
            XCTAssertEqual(score.hash?.prefix(12), Substring(row.hash), file)
        }
    }

    // MARK: - how it counts

    /// `kCoreStable` counts the CORE cells only. Five extended cells added to
    /// the same nine must not move it.
    func testTheExtendedCellsDoNotMoveTheCoreCount() throws {
        let fixture = try fixture("best_r6_ceilvaultC_60mm-climb")
        let coreOnly = fixture.answers.filter { $0.cell.tier == .core }
        let score = StairsChallenge.Score(rise: fixture.rise, cells: coreOnly)
        XCTAssertEqual(score.kCore, 5)
        XCTAssertEqual(score.kCoreStable, 5)
        XCTAssertEqual(score.ceilingCore, 5)
        // But a nine-cell run is NOT a complete score.
        XCTAssertFalse(score.isComplete)
        XCTAssertFalse(score.isPublishable)
        XCTAssertTrue(score.problems.contains { $0.contains("9 of 14 cells answered") })
    }

    /// `honest` and `stable` are different counts, and the leaderboard is
    /// ordered by the second. A cell that reaches the tread and topples inside
    /// the tail counts for `kCore` and not for `kCoreStable`.
    func testAToppleInsideTheTailCostsTheStableCountOnly() {
        let cell = StairsChallenge.Grid.fallback[0]
        let toppled = DuckBench.Climbed(hash: "h", rise: 0.06, cell: cell,
                                        honest: true, stable: false, uprightTailTicks: 8,
                                        aboveMillimetres: 116, xMillimetres: 300,
                                        dyMillimetres: 0, feetOnTread: 2,
                                        peakAboveTreadMillimetres: 130, maxTorque: 0.6405)
        let score = StairsChallenge.Score(rise: 0.06, cells: [toppled])
        XCTAssertEqual(score.kCore, 1)
        XCTAssertEqual(score.kCoreStable, 0)
        XCTAssertEqual(score.ceilingCore, 1)
    }

    /// AN INVALID CELL COUNTS FOR NOTHING. A file outside its own declared
    /// bounds is a search that left its box, and a clear it produced is not a
    /// clear.
    func testAnInvalidCellIsNotACleanClear() {
        let cell = StairsChallenge.Grid.fallback[0]
        let bad = DuckBench.Climbed(hash: "h", rise: 0.06, cell: cell,
                                    honest: true, stable: true, uprightTailTicks: 50,
                                    aboveMillimetres: 116, xMillimetres: 300,
                                    dyMillimetres: 0, feetOnTread: 2,
                                    peakAboveTreadMillimetres: 130, maxTorque: 0.6,
                                    invalid: true, why: "blend outside [0.7, 2.4]")
        let score = StairsChallenge.Score(rise: 0.06, cells: [bad])
        XCTAssertEqual(score.kCore, 0)
        XCTAssertEqual(score.kCoreStable, 0)
        XCTAssertEqual(score.ceilingCore, 0)
        XCTAssertEqual(score.invalidCells, 1)
        XCTAssertFalse(score.isPublishable)
        XCTAssertTrue(score.problems[0].contains("INVALID"))
    }

    /// The bar is exactly 95 mm and the comparison is strict, the way
    /// `rig3.mjs` writes it (`s.above > 0.095`).
    func testTheCeilingBarIsNinetyFiveMillimetresAndStrict() {
        func ceiling(_ peak: Double) -> Int {
            StairsChallenge.Score(rise: 0.06, cells: [
                DuckBench.Climbed(hash: "h", rise: 0.06, cell: StairsChallenge.Grid.fallback[0],
                                  honest: false, stable: false, uprightTailTicks: 0,
                                  aboveMillimetres: 0, xMillimetres: 0, dyMillimetres: 0,
                                  feetOnTread: 0, peakAboveTreadMillimetres: peak,
                                  maxTorque: 0)]).ceilingCore
        }
        XCTAssertEqual(ceiling(95.0), 0)
        XCTAssertEqual(ceiling(95.0000001), 1)
        XCTAssertEqual(StairsChallenge.barMillimetres, 95.0)
    }

    /// Two hashes in one run is not one move's score.
    func testAMixedRunIsCalledOut() {
        let cell = StairsChallenge.Grid.fallback[0]
        func row(_ hash: String) -> DuckBench.Climbed {
            DuckBench.Climbed(hash: hash, rise: 0.06, cell: cell, honest: false, stable: false,
                              uprightTailTicks: 0, aboveMillimetres: 0, xMillimetres: 0,
                              dyMillimetres: 0, feetOnTread: 0, peakAboveTreadMillimetres: 0,
                              maxTorque: 0)
        }
        let score = StairsChallenge.Score(rise: 0.06, cells: [row("a"), row("b")])
        XCTAssertTrue(score.isMixed)
        XCTAssertTrue(score.problems.contains { $0.contains("not one move's score") })
    }

    // MARK: - the sentences

    func testTheVerdictCarriesBothCounts() throws {
        let fixture = try fixture("best_r6_ceilvaultC_60mm-climb")
        let score = StairsChallenge.Score(rise: fixture.rise, cells: fixture.answers)
        XCTAssertEqual(score.verdict,
            "Cleared 5 of 9 stably at 60 mm against a bar of 7; the trunk reached the bar in "
          + "5 of 9.")
        XCTAssertEqual(score.sameCriterion,
            "This is the audit's criterion and grid, scored on this bench's plant 3f8c9ab9b409.")
        XCTAssertEqual(score.extendedSaid,
            "Over all 14 cells, including the five the round-4 audit added: 5 cleared and "
          + "standing, 5 cleared.")
        XCTAssertEqual(score.line,
            "5/9 stable · 5/9 honest · 5/14 extended · ceiling 5/9 · 60 mm")
    }

    /// Matching a record is not beating one, and the sentence must not let a
    /// screen imply it.
    func testTheComparisonAgainstAPublishedRowDoesNotFlatter() throws {
        let fixture = try fixture("best_r6_ceilvaultC_60mm-climb")
        let score = StairsChallenge.Score(rise: fixture.rise, cells: fixture.answers)
        XCTAssertEqual(score.against(StairsChallenge.record),
            "That is the published 5 of 9 for a56d459fb649, reproduced here.")

        // A ROW AT ANOTHER RISE IS NOT COMPARED, however the counts fall: a
        // lower rise is a strictly easier task.
        let weaker = try XCTUnwrap(StairsChallenge.row(file: "best_r2_vault_40mm.json"))
        XCTAssertFalse(score.sameRise(as: weaker))
        XCTAssertEqual(score.against(weaker),
            "Scored at 60 mm; the published row for 86813f9c1ad4 is at 40 mm. A lower rise is a "
          + "strictly easier task, so the two counts are not compared.")
        let sameRiseWeaker = try XCTUnwrap(StairsChallenge.row(file: "best_r3_vault_60mm.json"))
        XCTAssertTrue(score.sameRise(as: sameRiseWeaker))
        XCTAssertEqual(score.against(sameRiseWeaker),
            "That is better than the published 4 of 9 for 4b9110c448ec. Worth submitting.")

        let control = try XCTUnwrap(StairsChallenge.row(file: "r4_ctrl_on_tread_60mm.json"))
        XCTAssertEqual(score.against(control),
            "The published row for d99589396fcb is 9 of 9; this run got 5. Different bench, "
          + "different plant, or an edit — the cells above say which.")
    }

    // MARK: - while it is running

    func testProgressCountsWhatIsLeftAndNamesTheCellItIsOn() throws {
        let fixture = try fixture("best_r6_ceilvaultC_60mm-climb")
        let grid = StairsChallenge.Grid.fallback
        var progress = StairsChallenge.ScoreProgress(grid: grid)
        XCTAssertEqual(progress.remaining, 14)
        XCTAssertFalse(progress.isFinished)
        XCTAssertEqual(progress.said(rise: 0.06), "Cell 1 of 14 — 50/.120/x1.0")

        progress = StairsChallenge.ScoreProgress(grid: grid,
                                                 done: Array(fixture.answers.prefix(4)))
        XCTAssertEqual(progress.remaining, 10)
        XCTAssertEqual(progress.said(rise: 0.06), "Cell 5 of 14 — 60/.130/x0.7")
        XCTAssertEqual(progress.score(rise: 0.06).kCoreStable, 3)

        progress = StairsChallenge.ScoreProgress(grid: grid, done: fixture.answers)
        XCTAssertTrue(progress.isFinished)
        XCTAssertEqual(progress.remaining, 0)
        XCTAssertEqual(progress.said(rise: 0.06), "14 of 14 cells scored.")
    }

    /// A cell that failed for a reason that is not physics still ends the run:
    /// thirteen answers and one dropped request is not a fourteen-cell score.
    func testAFailedCellStillEndsTheRun() throws {
        let fixture = try fixture("best_r6_ceilvaultC_60mm-climb")
        let progress = StairsChallenge.ScoreProgress(
            grid: StairsChallenge.Grid.fallback,
            done: Array(fixture.answers.prefix(13)),
            failures: ["The bench stopped answering."])
        XCTAssertTrue(progress.isFinished)
        XCTAssertFalse(progress.score(rise: 0.06).isComplete)
    }

    /// A score from another plant, or from a bench that named none, is a
    /// problem the submission carries; a run that never reached the flight
    /// is said to be a measurement and not an entry.
    func testAScoreFromAnotherWorldOrNoneIsNotComparable() throws {
        let fixture = try fixture("best_r6_ceilvaultC_60mm-climb")
        let good = StairsChallenge.Score(rise: fixture.rise, cells: fixture.answers)
        XCTAssertTrue(good.problems.isEmpty, "\(good.problems)")
        XCTAssertTrue(good.isPublishable)
        let elsewhere = try fixture.answers(replacingPlant: "deadbeefcafe0000")
        let moved = StairsChallenge.Score(rise: fixture.rise, cells: elsewhere)
        XCTAssertTrue(moved.problems.contains { $0.hasPrefix("Scored in plant deadbeefcafe") }, "\(moved.problems)")
        XCTAssertFalse(moved.isPublishable)
        let unnamed = try fixture.answers(replacingPlant: nil)
        let anon = StairsChallenge.Score(rise: fixture.rise, cells: unnamed)
        XCTAssertTrue(anon.problems.contains { $0.hasPrefix("The bench did not identify its plant") }, "\(anon.problems)")
    }

    /// The edit-score-keep sentence, three ways.
    func testTheChangeSentenceSaysKeepPutBackOrNothingChanged() throws {
        let fixture = try fixture("best_r6_ceilvaultC_60mm-climb")
        let five = StairsChallenge.Score(rise: fixture.rise, cells: fixture.answers)
        let four = try StairsChallenge.Score(rise: 0.060,
            cells: XCTUnwrap(self.fixture("best_r3_vault_60mm-climb")).answers)
        XCTAssertEqual(five.change(from: four), "Better: 5 of 9 stable where it was 4. Keep it.")
        XCTAssertEqual(four.change(from: five),
            "Worse: 4 of 9 stable where it was 5. Put it back, or keep going from here on purpose.")
        XCTAssertEqual(five.change(from: five),
            "The same: 5 of 9 stable before and after. The edit changed nothing the criterion can see.")
    }
}
