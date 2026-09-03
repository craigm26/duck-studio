import XCTest
@testable import StudioKit

/// The objective, against the four climb fixtures this app ships.
///
/// THIS IS THE FIXTURE-ORDERING GATE. There is nothing upstream to pin the
/// arithmetic to — `robust.objective` lives in the intent files and nowhere in
/// the kit — so what is pinned instead is the ORDER: the four shipped fixtures
/// come out of `MoveSearch.cellScore` in the same order their `kCoreStable`
/// puts them. That is a FLOOR and not parity with `BenchTuneParityTests`: two
/// of the four are degenerate controls, and the 0.022 gap between the two real
/// vaults is well inside the 1.84 paired core spread between them. An objective
/// that got the controls the wrong way round is broken; one that swaps the two
/// vaults is inside the noise this screen prints before the button.
final class MoveSearchObjectiveTests: XCTestCase {

    struct Fixture {
        let rise: Double
        let cells: [DuckBench.Climbed]
        var core: [DuckBench.Climbed] { cells.filter { $0.cell.tier == .core } }
        var extended: [DuckBench.Climbed] { cells.filter { $0.cell.tier == .ext } }
    }

    /// Read through `HarnessJSON`, the same door the app reads a live bench
    /// through, so the fixture's digits arrive as the digits the harness wrote.
    func fixture(_ name: String) throws -> Fixture {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/stairs/\(name)",
                                                  withExtension: "json"),
                                "\(name) is not in the test bundle")
        let top = try HarnessJSON.parse(try Data(contentsOf: url))
        let rise = try XCTUnwrap(top["rise"]?.doubleValue)
        let rows = try XCTUnwrap(top["answers"]?.arrayValue)
        return Fixture(rise: rise,
                       cells: try rows.map { try DuckBench.readClimbed($0.encoded(.compact)) })
    }

    func coreMean(_ f: Fixture) -> Double {
        f.core.map(MoveSearch.cellScore).reduce(0, +) / Double(f.core.count)
    }

    // MARK: - the ordering

    func testTheObjectiveOrdersTheFourShippedClimbFixturesTheWayTheAuditsColumnDoes() throws {
        let doNothing = try fixture("ctrl_do_nothing-climb")
        let r3 = try fixture("best_r3_vault_60mm-climb")
        let r6 = try fixture("best_r6_ceilvaultC_60mm-climb")
        let onTread = try fixture("r4_ctrl_on_tread_60mm-climb")

        // The audit's own column, read out of the leaderboard this app carries.
        XCTAssertEqual(StairsChallenge.row(file: "ctrl_do_nothing.json")?.kCoreStable, 0)
        XCTAssertEqual(StairsChallenge.row(file: "best_r3_vault_60mm.json")?.kCoreStable, 4)
        XCTAssertEqual(StairsChallenge.row(file: "best_r6_ceilvaultC_60mm.json")?.kCoreStable, 5)
        XCTAssertEqual(StairsChallenge.row(file: "r4_ctrl_on_tread_60mm.json")?.kCoreStable, 9)

        XCTAssertEqual(coreMean(doNothing), 0.000000, accuracy: 1e-6)
        XCTAssertEqual(coreMean(r3), 0.742023, accuracy: 1e-6)
        XCTAssertEqual(coreMean(r6), 0.764007, accuracy: 1e-6)
        XCTAssertEqual(coreMean(onTread), 1.000000, accuracy: 1e-6)

        XCTAssertLessThan(coreMean(doNothing), coreMean(r3))
        XCTAssertLessThan(coreMean(r3), coreMean(r6))
        XCTAssertLessThan(coreMean(r6), coreMean(onTread))
    }

    // MARK: - the gate that is the whole objective

    /// MUST FAIL IF THE FLIGHT GATE IS REMOVED. This is the check that proves
    /// the gate is load-bearing rather than decorative: without it, a duck that
    /// never moves scores 0.592345 on reach × stability alone, which is above
    /// three of the nine core cells of the published 4-of-9 vault and above six
    /// of the fourteen cells of the 5-of-9 one.
    ///
    /// THE PLAN THIS WAS BUILT FROM SAID "six of the nine core cells" OF THE
    /// 4-of-9 VAULT. Recomputed here over the shipped fixtures it is THREE of
    /// nine: the ungated mean clears 0.160000, 0.566838 and 0.536049 and
    /// nothing else. The headline number — 0.592345 — reproduces the plan
    /// exactly; the cell count did not, and the fixture wins.
    func testWithoutTheFlightGateTheDoNothingControlWouldOutscoreThreeOfTheVaultsNineCells()
        throws {
        let doNothing = try fixture("ctrl_do_nothing-climb")

        // `cellScore` WITHOUT ITS FIRST LINE, written out here rather than
        // reached for, because the point is to compare the gated function
        // against the ungated arithmetic it is built on.
        func ungated(_ c: DuckBench.Climbed) -> Double {
            let reach = min(max(c.peakAboveTreadMillimetres, 0),
                            StairsChallenge.barMillimetres) / StairsChallenge.barMillimetres
            let stability = min(max(Double(c.uprightTailTicks) / Double(max(c.tailTicks, 1)),
                                    0), 1)
            return reach * stability
        }
        let ungatedMean = doNothing.core.map(ungated).reduce(0, +) / 9
        XCTAssertEqual(ungatedMean, 0.592345, accuracy: 1e-4)

        // And the gate takes it to nothing, on every single cell.
        XCTAssertEqual(coreMean(doNothing), 0, accuracy: 1e-12)
        XCTAssertTrue(doNothing.cells.allSatisfy { !$0.reachedFlight })

        let r3 = try fixture("best_r3_vault_60mm-climb")
        let beaten = r3.core.map(MoveSearch.cellScore).filter { $0 < ungatedMean }
        XCTAssertEqual(beaten.count, 3,
                       "the ungated do-nothing mean sits above three of the 4-of-9 vault's nine")

        let r6 = try fixture("best_r6_ceilvaultC_60mm-climb")
        let beatenAcrossFourteen = r6.cells.map(MoveSearch.cellScore).filter { $0 < ungatedMean }
        XCTAssertEqual(beatenAcrossFourteen.count, 6,
                       "and above six of the 5-of-9 vault's fourteen")
    }

    func testTheDoNothingControlScoresExactlyZeroBecauseItNeverReachesFlight() throws {
        let doNothing = try fixture("ctrl_do_nothing-climb")
        let reading = try MoveSearch.reading(doNothing.cells)
        XCTAssertEqual(reading.objective, 0)
        XCTAssertEqual(reading.reachedFlightCells, 0)
        XCTAssertEqual(reading.audit.kCoreStable, 0)
        // The audit's count travels beside this app's number, every time.
        XCTAssertTrue(reading.line.contains("Cleared 0 of 9"))
    }

    // MARK: - what a reading refuses

    func testAnInvalidCellRefusesTheWholeReadingRatherThanScoringZero() throws {
        let r3 = try fixture("best_r3_vault_60mm-climb")
        var cells = r3.cells
        let first = cells[0]
        cells[0] = DuckBench.Climbed(
            hash: first.hash, rise: first.rise, cell: first.cell, honest: false, stable: false,
            uprightTailTicks: first.uprightTailTicks, tailTicks: first.tailTicks,
            aboveMillimetres: first.aboveMillimetres, xMillimetres: first.xMillimetres,
            dyMillimetres: first.dyMillimetres, feetOnTread: first.feetOnTread,
            peakAboveTreadMillimetres: first.peakAboveTreadMillimetres,
            maxTorque: first.maxTorque, reachedFlight: first.reachedFlight, invalid: true)
        XCTAssertThrowsError(try MoveSearch.reading(cells)) { error in
            XCTAssertEqual(error as? MoveSearch.Refusal, .leftItsBox(cells: 1))
        }
    }

    func testAPartialGridIsRefusedRatherThanAveraged() throws {
        let r3 = try fixture("best_r3_vault_60mm-climb")
        XCTAssertThrowsError(try MoveSearch.reading(Array(r3.cells.dropLast()))) { error in
            XCTAssertEqual(error as? MoveSearch.Refusal, .partialGrid(answered: 13, of: 14))
        }
    }

    // MARK: - the spread the screen prints before the button

    func testThePairedSpreadOfTheTwoPublishedVaultsIsTheNumberTheSentenceQuotes() throws {
        let r3 = try fixture("best_r3_vault_60mm-climb")
        let r6 = try fixture("best_r6_ceilvaultC_60mm-climb")

        let extended = zip(r6.extended, r3.extended)
            .map { MoveSearch.cellScore($0) - MoveSearch.cellScore($1) }
        let core = zip(r6.core, r3.core)
            .map { MoveSearch.cellScore($0) - MoveSearch.cellScore($1) }

        let spread = try XCTUnwrap(MoveSearch.conditionSpread(extended))
        XCTAssertEqual(spread, 0.9087, accuracy: 1e-4)
        XCTAssertEqual(extended.reduce(0, +) / 5, 0.0036, accuracy: 1e-4)

        XCTAssertEqual(try XCTUnwrap(MoveSearch.conditionSpread(core)), 1.8400, accuracy: 1e-4)
        XCTAssertEqual(core.reduce(0, +) / 9, 0.0220, accuracy: 1e-4)

        // And the sentence quotes the numbers the fixtures produce.
        XCTAssertTrue(MoveSearch.howMuchTheConditionsMove.contains("0.91"))
        XCTAssertTrue(MoveSearch.howMuchTheConditionsMove.contains("0.004"))
    }

    func testASpreadOfExactlyZeroIsRefusedTheWayTheTunerRefusesOne() {
        XCTAssertNil(MoveSearch.conditionSpread([0.5, 0.5]))
        XCTAssertNil(MoveSearch.conditionSpread([0.5, .nan]))
        XCTAssertNil(MoveSearch.conditionSpread([0.5]))
        XCTAssertNil(MoveSearch.conditionSpread([]))
        XCTAssertEqual(try XCTUnwrap(MoveSearch.conditionSpread([0.1, 0.4])), 0.3, accuracy: 1e-12)
    }

    func testAWinnerThatStoppedReachingFlightIsRefusedWhateverItsGain() {
        let said = MoveSearch.heldOutVerdict(meanGain: 5, conditionSpread: 0.1,
                                             flightKept: 2, baselineFlight: 5)
        XCTAssertTrue(said.contains("stopped getting off the floor"))
        XCTAssertFalse(said.contains("It survived"))
    }

    func testAGainUnderTheSpreadIsTheUsualOutcomeAndSaysSo() {
        let said = MoveSearch.heldOutVerdict(meanGain: 0.01, conditionSpread: 0.9,
                                             flightKept: 5, baselineFlight: 5)
        XCTAssertTrue(said.contains("did not survive the conditions"))
        XCTAssertTrue(said.contains("usual outcome"))
        let cleared = MoveSearch.heldOutVerdict(meanGain: 1.2, conditionSpread: 0.9,
                                                flightKept: 5, baselineFlight: 5)
        XCTAssertTrue(cleared.hasPrefix("It survived"))
    }

    // MARK: - the measurement that deleted a rejection

    /// TORQUE SATURATION IS THE NORMAL OPERATING STATE OF A WORKING VAULT.
    /// `maxTq` is exactly 0.6405 in fourteen of fourteen cells for both
    /// published vaults; only the two non-climbing controls sit near 0.09. A
    /// rejection on that basis would throw out the parent move before
    /// generation 1 and every child after it, and the screen could never
    /// produce a number.
    func testThereIsNoTorqueRejection() throws {
        for name in ["best_r3_vault_60mm-climb", "best_r6_ceilvaultC_60mm-climb"] {
            let f = try fixture(name)
            XCTAssertTrue(f.core.allSatisfy { $0.maxTorque == 0.6405 }, name)
            XCTAssertTrue(f.cells.allSatisfy { $0.maxTorque == 0.6405 }, name)
            XCTAssertNil(MoveSearch.rejected(f.cells), name)
        }
        let doNothing = try fixture("ctrl_do_nothing-climb")
        XCTAssertEqual(MoveSearch.rejected(doNothing.cells), .neverReachedFlight)
        XCTAssertTrue(doNothing.cells.allSatisfy { $0.maxTorque < 0.11 })
    }
}
