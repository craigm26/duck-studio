import XCTest
@testable import StudioKit

/// Reading one `/chase` answer, and counting fourteen of them.
///
/// THE ANSWERS HERE ARE HAND-WRITTEN TO THE CONTRACT, not captured from a
/// bench — `sim/chase_score.mjs` does not exist yet. That makes this test the
/// specification of the wire format as much as a test of the reader: every
/// field name below is one the bench has to write, and a bench that writes a
/// different one will fail `BallFixtureTests` the moment it exists.
final class BallScoreTests: XCTestCase {

    /// One `/chase` answer, exactly as the contract says the bench writes it.
    static func answer(cell: DuckBench.ChaseCell,
                       hash: String = "2f1c0d9ab4e6",
                       seconds: Double = 4,
                       travel: Double = 214.37158662135791,
                       /// The exact number token to write, when the point of a
                       /// test is the digits rather than the value. Swift's own
                       /// interpolation writes the SHORTEST round-tripping form
                       /// (214.37158662135791 comes out as …92), so a test that
                       /// pins the bench's digits has to write them itself.
                       travelLiteral: String? = nil,
                       net: Double = 220.5,
                       closest: Double = 1.25,
                       final: Double = 180.0,
                       touched: Bool = true,
                       peak: Double = 0.83,
                       upright: Bool = true,
                       uprightTail: Int = 50,
                       chased: Bool = true,
                       stable: Bool = true,
                       source: String = "policy raw output",
                       plantDigest: String = BallChallenge.plantDigest,
                       criterion: String = BallChallenge.criterionSentence,
                       invalid: Bool = false) -> Data {
        Data("""
        {
          "hash": "\(hash)",
          "cell": {"bearing": \(cell.bearing), "range": \(cell.range), "drop": \(cell.drop),
                   "fmul": \(cell.fmul), "tier": "\(cell.tier.rawValue)"},
          "seconds": \(seconds),
          "ballTravel_mm": \(travelLiteral ?? "\(travel)"),
          "ballNet_mm": \(net),
          "closest_mm": \(closest),
          "final_mm": \(final),
          "touched": \(touched),
          "ballPeakSpeed_mps": \(peak),
          "upright": \(upright),
          "uprightTailTicks": \(uprightTail),
          "tailTicks": 50,
          "chased": \(chased),
          "stable": \(stable),
          "terms": [
            {"term": "ball_forward_velocity", "weight": 12, "value": 0.4212},
            {"term": "ball_speed_overshoot", "weight": -4, "value": 0},
            {"term": "upright", "weight": 2, "value": 0.9611},
            {"term": "pose_stand_legs", "weight": 2, "value": 0.7402},
            {"term": "pose_stand_neck", "weight": 1, "value": 0.8815},
            {"term": "height_stand", "weight": 1, "value": 0.6103},
            {"term": "body_ang_vel", "weight": -0.05, "value": 1.2044},
            {"term": "action_rate_l2", "weight": -1, "value": 0.0182,
             "action_rate_l2_source": "\(source)"},
            {"term": "angular_momentum", "weight": -0.02, "value": 0.0031}
          ],
          "refused": [
            {"term": "support_foot_grounded", "weight": 2,
             "reason": "Reads a contact sensor; this plant has six sensors and none is one."},
            {"term": "self_collisions", "weight": -1,
             "reason": "Reads the self_collision sensor; no collision sensor in this plant."},
            {"term": "dof_pos_limits", "weight": -1,
             "reason": "Scores against soft joint limits, which this bench does not ship."}
          ],
          "invalid": \(invalid),
          "plantName": "scene.mjb",
          "plantDigest": "\(plantDigest)",
          "criterion": "\(criterion)",
          "actionRateSource": "\(source)",
          "drivenTicks": 200,
          "rateTicks": 199,
          "entrant": "\(String(hash.prefix(12)))",
          "kind": "policy",
          "policy": "alpha_walking.onnx",
          "elapsedSeconds": 1.42
        }
        """.utf8)
    }

    // MARK: - one cell

    func testOneAnswerIsReadFieldForField() throws {
        let cell = BallChallenge.Grid.centre
        let read = try DuckBench.readChased(Self.answer(cell: cell))
        XCTAssertEqual(read.hash, "2f1c0d9ab4e6")
        XCTAssertEqual(read.cell, cell)
        XCTAssertEqual(read.seconds, 4)
        XCTAssertEqual(read.ballNetMillimetres, 220.5)
        XCTAssertEqual(read.closestMillimetres, 1.25)
        XCTAssertEqual(read.finalMillimetres, 180.0)
        XCTAssertTrue(read.touched)
        XCTAssertEqual(read.ballPeakSpeed, 0.83)
        XCTAssertTrue(read.upright)
        XCTAssertEqual(read.uprightTailTicks, 50)
        XCTAssertEqual(read.tailTicks, 50)
        XCTAssertTrue(read.chased)
        XCTAssertTrue(read.stable)
        XCTAssertEqual(read.plantName, "scene.mjb")
        XCTAssertEqual(read.plantDigest, BallChallenge.plantDigest)
        XCTAssertEqual(read.criterion, BallChallenge.criterionSentence)
        XCTAssertEqual(read.elapsedSeconds, 1.42)
        XCTAssertEqual(read.drivenTicks, 200)
        XCTAssertEqual(read.rateTicks, 199)
        XCTAssertEqual(read.shortHash, "2f1c0d9ab4e6")
        XCTAssertEqual(read.kind, "policy")
        XCTAssertEqual(read.policy, "alpha_walking.onnx")
        XCTAssertFalse(read.invalid)
    }

    /// THE BENCH'S OWN DIGITS, NOT FOUNDATION'S. `swift-corelibs-foundation`'s
    /// JSON number parsing is not correctly rounded, and the whole claim of a
    /// submission bundle is that it carries the per-cell answers unrounded.
    func testABallTravelKeepsEveryDigitTheBenchWrote() throws {
        let read = try DuckBench.readChased(
            Self.answer(cell: BallChallenge.Grid.centre,
                        travelLiteral: "214.37158662135791"))
        XCTAssertEqual(read.ballTravelMillimetres, Double("214.37158662135791")!)
        // THE TOKEN THE BENCH WROTE, not a re-formatted Double. Swift would
        // print this value as 214.37158662135792, one unit in the last place
        // away, and a submission bundle that claims to carry the per-cell
        // answers unrounded would quietly stop being true there.
        XCTAssertEqual(read.literal("ballTravel_mm")?.encoded(.compact),
                       Data("214.37158662135791".utf8))
    }

    func testTheNineTermsArriveWithTheirWeightsAndTheActionRateSource() throws {
        let read = try DuckBench.readChased(Self.answer(cell: BallChallenge.Grid.centre))
        XCTAssertEqual(read.terms.count, 9)
        XCTAssertEqual(read.terms.map(\.term), [
            "ball_forward_velocity", "ball_speed_overshoot", "upright",
            "pose_stand_legs", "pose_stand_neck", "height_stand",
            "body_ang_vel", "action_rate_l2", "angular_momentum",
        ])
        let forward = try XCTUnwrap(read.terms.first)
        XCTAssertEqual(forward.weight, 12)
        XCTAssertEqual(forward.value, 0.4212)
        XCTAssertEqual(forward.weighted, 0.4212 * 12, accuracy: 1e-12)
        XCTAssertEqual(forward.weightSaid, "+12")
        XCTAssertEqual(read.actionRateSource, "policy raw output")
    }

    /// THE THREE DELETED TERMS MUST NOT APPEAR. `track_linear_velocity`,
    /// `track_angular_velocity` and `pose` are deleted by the kick config, and
    /// reporting them would be answering the wrong config under the right
    /// name.
    func testTheTermsTheKickConfigDeletesAreNotInTheAnswer() throws {
        let read = try DuckBench.readChased(Self.answer(cell: BallChallenge.Grid.centre))
        let names = Set(read.terms.map(\.term))
        XCTAssertFalse(names.contains("track_linear_velocity"))
        XCTAssertFalse(names.contains("track_angular_velocity"))
        XCTAssertFalse(names.contains("pose"))
    }

    /// REFUSED BY NAME, NEVER DROPPED. Three terms with weights and reasons is
    /// what makes the nine reported ones a transcription rather than a
    /// selection.
    func testTheThreeRefusalsArriveByNameWithWeightsAndReasons() throws {
        let read = try DuckBench.readChased(Self.answer(cell: BallChallenge.Grid.centre))
        XCTAssertEqual(read.refused.map(\.term),
                       ["support_foot_grounded", "self_collisions", "dof_pos_limits"])
        XCTAssertEqual(read.refused[0].weight, 2)
        XCTAssertEqual(read.refused[1].weight, -1)
        for refusal in read.refused {
            XCTAssertFalse(refusal.reason.isEmpty, refusal.term)
        }
    }

    func testTheActionRateSentenceSaysWhichActionTheRateIsOver() {
        XCTAssertTrue(BallChallenge.actionRateSaid("policy raw output")
            .contains("raw 14-vector"))
        XCTAssertTrue(BallChallenge.actionRateSaid("keyframe pose target")
            .contains("pose target"))
        XCTAssertTrue(BallChallenge.actionRateSaid(nil).contains("not comparable"))
    }

    /// THE THREE CLAUSES, SEPARATELY. "It failed" is not usable; "it never
    /// touched the ball" is.
    func testAFailedCellSaysWhichClauseFailed() throws {
        let cell = BallChallenge.Grid.fallback[12]  // +40°
        let read = try DuckBench.readChased(Self.answer(
            cell: cell, travel: 4.2, closest: 431.8, touched: false,
            upright: false, uprightTail: 3, chased: false, stable: false))
        XCTAssertEqual(read.whyNotChased.count, 3)
        XCTAssertTrue(read.whyNotChased[0].contains("Never touched the ball"))
        XCTAssertTrue(read.whyNotChased[0].contains("431.8"))
        XCTAssertTrue(read.whyNotChased[1].contains("100.0 mm"))
        XCTAssertTrue(read.whyNotChased[2].contains("not upright"))
    }

    func testAChasedCellHasNothingToExplain() throws {
        let read = try DuckBench.readChased(Self.answer(cell: BallChallenge.Grid.centre))
        XCTAssertTrue(read.whyNotChased.isEmpty)
    }

    func testABenchWithoutChaseArrivesAsItsOwnWords() {
        XCTAssertThrowsError(try DuckBench.readChased(Data(#"{"error":"no /chase here"}"#.utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .bench("no /chase here"))
        }
        XCTAssertTrue(BallChallenge.noChaseHere(bench: "the Pi").contains("No /chase on the Pi"))
        XCTAssertTrue(BallChallenge.noChaseHere(bench: "the Pi")
            .contains("systemctl --user restart duckbench"))
    }

    func testAnAnswerWithoutAHashIsEmpty() {
        XCTAssertThrowsError(try DuckBench.readChased(Data(#"{"chased":true}"#.utf8))) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .empty)
        }
    }

    // MARK: - the request

    func testTheRequestCarriesTheEntrantVerbatimAndTheCellAndTheSeconds() throws {
        let address = DuckBench.Address(host: "127.0.0.1", port: 8770)
        let entrant = BallChallenge.Entrants.alphaWalking
        let call = try DuckBench.chase(address, entrant: entrant,
                                       cell: BallChallenge.Grid.centre)
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url.path, "/chase")
        let body = try HarnessJSON.parse(XCTUnwrap(call.body))
        XCTAssertEqual(body["seconds"]?.doubleValue, 4)
        XCTAssertEqual(body["tail"]?.stringValue, "policy")
        XCTAssertEqual(body["cell"]?["bearing"]?.doubleValue, 0)
        XCTAssertEqual(body["cell"]?["range"]?.doubleValue, 0.70)
        XCTAssertEqual(body["cell"]?["drop"]?.doubleValue, 0.120)
        XCTAssertEqual(body["cell"]?["fmul"]?.doubleValue, 1.0)
        // THE ENTRANT GOES ACROSS WHOLE. The bench hashes what it receives.
        XCTAssertEqual(body["entrant"], entrant.json)
        XCTAssertEqual(body["entrant"]?["policy"]?.stringValue, "alpha_walking.onnx")
        XCTAssertEqual(body["entrant"]?["note"]?.stringValue, entrant.note)
    }

    func testARequestFromSomethingThatIsNotAnEntrantObjectIsRefused() {
        let address = DuckBench.Address(host: "127.0.0.1", port: 8770)
        XCTAssertThrowsError(try DuckBench.chase(address, entrant: Data("[1]".utf8), seconds: 4,
                                                 cell: BallChallenge.Grid.centre))
    }

    // MARK: - fourteen of them

    /// A full grid where the bearing-0 cells chase and nothing else does —
    /// which is what `ctrl_alpha_walking` is predicted to do, and the shape
    /// the counts have to get right.
    func grid(chasedAtBearingZero: Bool = true) throws -> [DuckBench.Chased] {
        try BallChallenge.Grid.fallback.map { cell in
            let ahead = cell.bearing == 0 && chasedAtBearingZero
            return try DuckBench.readChased(Self.answer(
                cell: cell,
                travel: ahead ? 214.37158662135791 : 3.5,
                closest: ahead ? 1.25 : 402.0,
                touched: ahead,
                peak: ahead ? 0.83 : 0,
                uprightTail: 50,
                chased: ahead, stable: ahead))
        }
    }

    func testTheCountsAreTheCoreNineAndTheExtendedFiveSeparately() throws {
        let score = BallChallenge.Score(cells: try grid())
        // Three core cells are at bearing 0 (0.45, 0.70, 0.95).
        XCTAssertEqual(score.kChased, 3)
        XCTAssertEqual(score.kStable, 3)
        // Three extended cells are at bearing 0: the two plants and the far one.
        XCTAssertEqual(score.kExt, 3)
        XCTAssertEqual(score.kExtStable, 3)
        XCTAssertEqual(score.coreAnswered, 9)
        XCTAssertEqual(score.extendedAnswered, 5)
        XCTAssertEqual(score.answered, 14)
        XCTAssertTrue(score.isComplete)
        XCTAssertEqual(score.touchedCells, 6)
        XCTAssertEqual(score.uprightCells, 14)
        XCTAssertEqual(score.bestBallTravelMillimetres, 214.37158662135791)
        XCTAssertEqual(score.closestMillimetres, 1.25)
        XCTAssertEqual(score.ballPeakSpeed, 0.83)
    }

    func testTheVerdictSaysBothNumbers() throws {
        let score = BallChallenge.Score(cells: try grid())
        XCTAssertEqual(score.verdict,
            "Chased the ball in 3 of 9 core cells, 3 of them still standing.")
        XCTAssertEqual(score.line,
            "3/9 chased · 3/9 stable · 3/5 extended · touched 6/14")
        XCTAssertTrue(score.extendedSaid.contains("±40°"))
        XCTAssertTrue(score.factsSaid.contains("214.4 mm"))
        XCTAssertTrue(score.sameCriterion.contains("chase_robust"))
        XCTAssertTrue(score.sameCriterion.contains(BallChallenge.plantDigest.prefix(12)))
    }

    func testACompleteRunOnTheRightPlantHasNoProblems() throws {
        let score = BallChallenge.Score(cells: try grid())
        XCTAssertEqual(score.problems, [])
        XCTAssertTrue(score.isPublishable)
        XCTAssertTrue(score.criterionMatches)
    }

    /// A RUN THAT TOUCHED NOTHING IS A MEASUREMENT AND NOT AN ENTRY — which is
    /// exactly what `ctrl_do_nothing` and the two kick policies are predicted
    /// to produce.
    func testARunThatNeverTouchedTheBallSaysSo() throws {
        let score = BallChallenge.Score(cells: try grid(chasedAtBearingZero: false))
        XCTAssertEqual(score.kChased, 0)
        XCTAssertEqual(score.touchedCells, 0)
        XCTAssertFalse(score.isPublishable)
        XCTAssertTrue(score.problems.contains { $0.contains("never touched the ball") })
    }

    func testAPartialGridCannotBeComparedWithAPublishedRow() throws {
        let score = BallChallenge.Score(cells: Array(try grid().prefix(6)))
        XCTAssertFalse(score.isComplete)
        XCTAssertTrue(score.problems.contains { $0.contains("6 of 14 cells answered") })
    }

    func testAScoreFromAnotherPlantIsNotComparable() throws {
        let cells = try BallChallenge.Grid.fallback.map {
            try DuckBench.readChased(Self.answer(cell: $0, plantDigest: "deadbeefdeadbeef"))
        }
        let score = BallChallenge.Score(cells: cells)
        XCTAssertTrue(score.problems.contains { $0.contains("different world") })
    }

    /// A BENCH CAN MEAN SOMETHING ELSE BY THE SAME WORD. `chased` from an
    /// older `chase_score.mjs` is a different verdict wearing this one's name.
    func testABenchWithADifferentCriterionSentenceIsFlagged() throws {
        let cells = try BallChallenge.Grid.fallback.map {
            try DuckBench.readChased(Self.answer(cell: $0, criterion: "chased: it moved a bit."))
        }
        let score = BallChallenge.Score(cells: cells)
        XCTAssertFalse(score.criterionMatches)
        XCTAssertTrue(score.problems.contains { $0.contains("criterion sentence") })
    }

    func testTwoHashesAreNotOneEntrantsScore() throws {
        var cells = try grid()
        cells[3] = try DuckBench.readChased(
            Self.answer(cell: BallChallenge.Grid.fallback[3], hash: "aaaaaaaaaaaa"))
        let score = BallChallenge.Score(cells: cells)
        XCTAssertTrue(score.isMixed)
        XCTAssertTrue(score.problems.contains { $0.contains("same entrant hash") })
    }

    func testAnInvalidCellIsNotAFailedCell() throws {
        var cells = try grid()
        cells[0] = try DuckBench.readChased(
            Self.answer(cell: BallChallenge.Grid.fallback[0], invalid: true))
        let score = BallChallenge.Score(cells: cells)
        XCTAssertEqual(score.invalidCells, 1)
        XCTAssertTrue(score.problems.first?.contains("INVALID") ?? false)
    }

    func testTheRefusalsAreDeduplicatedAcrossTheGrid() throws {
        let score = BallChallenge.Score(cells: try grid())
        XCTAssertEqual(score.refused.map(\.term),
                       ["support_foot_grounded", "self_collisions", "dof_pos_limits"])
    }

    /// A TERM'S MEAN OVER THE GRID IS HONEST — a term is a per-tick reward
    /// already averaged over an episode — WHERE A BALL TRAVEL'S IS NOT, which
    /// is why the facts are extremes and counts.
    func testTheTermsAreAveragedAndTheFactsAreNot() throws {
        let score = BallChallenge.Score(cells: try grid())
        XCTAssertEqual(score.terms.count, 9)
        XCTAssertEqual(score.terms.first?.term, "ball_forward_velocity")
        XCTAssertEqual(try XCTUnwrap(score.terms.first).value, 0.4212, accuracy: 1e-12)
        XCTAssertEqual(score.bestBallTravelMillimetres, 214.37158662135791)
    }

    // MARK: - the edit-score-keep loop

    func testTheChangeSentenceSaysKeepItOrPutItBack() throws {
        let better = BallChallenge.Score(cells: try grid())
        let worse = BallChallenge.Score(cells: try grid(chasedAtBearingZero: false))
        XCTAssertTrue(better.change(from: worse).hasPrefix("Better: 3 of 9 chased where it was 0"))
        XCTAssertTrue(worse.change(from: better).hasPrefix("Worse: 0 of 9 chased where it was 3"))
        XCTAssertTrue(better.change(from: better).hasPrefix("The same"))
    }

    /// TWO RUNS CAN CHASE THE SAME COUNT AND DIFFER IN EVERY FACT UNDERNEATH.
    /// An edit that moved the ball 40 mm further without crossing the bar is
    /// an edit worth keeping going from, and a flat "the edit changed nothing"
    /// would send somebody to undo it.
    func testAnEditThatMovedTheBallWithoutCrossingTheBarIsSaidSo() throws {
        let before = try BallChallenge.Grid.fallback.map {
            try DuckBench.readChased(Self.answer(cell: $0, travel: 20, touched: false,
                                                 chased: false, stable: false))
        }
        let after = try BallChallenge.Grid.fallback.map {
            try DuckBench.readChased(Self.answer(cell: $0, travel: 60, touched: false,
                                                 chased: false, stable: false))
        }
        let sentence = BallChallenge.Score(cells: after)
            .change(from: BallChallenge.Score(cells: before))
        XCTAssertTrue(sentence.contains("40.0 mm further"), sentence)
        XCTAssertTrue(sentence.contains("the criterion cannot see but you can"), sentence)
    }

    // MARK: - against a published row

    static func row(kChased: Int, seconds: Double = 4) -> BallChallenge.Row {
        BallChallenge.Row(rank: 1, hash: "2f1c0d9ab4e6",
                          sha256: String(repeating: "2f1c0d9ab4e6", count: 5) + "abcd",
                          file: "x.json", entrantName: "x",
                          kind: .policy, policy: "alpha_walking.onnx",
                          seconds: seconds, commandSaid: "vx 0.5",
                          kChased: kChased, kStable: kChased, kExt: 0, kExtStable: 0,
                          touchedCells: kChased, maxBallTravelMillimetres: 0,
                          who: "test", scored: "2026-09-02", note: "", isControl: false)
    }

    func testAgainstAPublishedRowNeverImpliesARecordThatWasMatched() throws {
        let score = BallChallenge.Score(cells: try grid())
        XCTAssertTrue(score.against(Self.row(kChased: 2)).contains("Worth submitting"))
        XCTAssertTrue(score.against(Self.row(kChased: 3)).contains("reproduced here"))
        XCTAssertTrue(score.against(Self.row(kChased: 5)).contains("this run got 3"))
    }

    /// A LONGER EPISODE IS A DIFFERENT TASK. Five seconds of walking reaches
    /// further than four, so two counts at different lengths are not one
    /// comparison and the sentence says both lengths and stops.
    func testTwoEpisodeLengthsAreNotOneComparison() throws {
        let score = BallChallenge.Score(cells: try grid())
        let said = score.against(Self.row(kChased: 9, seconds: 5))
        XCTAssertTrue(said.contains("4 s"), said)
        XCTAssertTrue(said.contains("5 s"), said)
        XCTAssertTrue(said.contains("not compared"), said)
    }

    // MARK: - progress

    func testProgressCountsCellsAndNamesTheOneInFlight() throws {
        let cells = try grid()
        let progress = BallChallenge.ScoreProgress(grid: BallChallenge.Grid.fallback,
                                                   done: Array(cells.prefix(4)))
        XCTAssertEqual(progress.remaining, 10)
        XCTAssertFalse(progress.isFinished)
        XCTAssertEqual(progress.said, "Cell 5 of 14 — 0°/0.70/.120/x1.0")
        XCTAssertEqual(progress.score.kChased, 1)
        let finished = BallChallenge.ScoreProgress(grid: BallChallenge.Grid.fallback, done: cells)
        XCTAssertTrue(finished.isFinished)
        XCTAssertEqual(finished.said, "14 of 14 cells scored.")
    }
}
