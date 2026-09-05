import XCTest
@testable import StudioKit

/// Two logs side by side, and the four cases where side by side is the lie.
final class EvalCompareTests: XCTestCase {

    /// Two runs of the same task in the same world, which is the only shape
    /// this screen is allowed to draw.
    private func pair() throws -> (EvalLogFile, EvalLogFile) {
        let task = try EvalTask.walkForwardOnly()
        let slow = EvalFixtures.walkScene("cmd-forward", task: task,
                                          travelled: [0.8, 0.82, 0.79, 0.81,
                                                      0.78, 0.83, 0.80, 0.81])
        let quick = EvalFixtures.walkScene("cmd-forward", task: task,
                                           travelled: [1.19, 1.22, 1.18, 1.20,
                                                       1.17, 1.21, 1.19, 1.20])
        return (EvalFixtures.file(try EvalFixtures.run(task: task, scenes: [slow]),
                                  runID: "aaaa0001"),
                EvalFixtures.file(try EvalFixtures.run(task: task, scenes: [quick]),
                                  runID: "aaaa0002"))
    }

    // MARK: - the refusals

    func testALogComparedWithItselfIsRefused() throws {
        let (left, _) = try pair()
        XCTAssertThrowsError(try EvalCompare.checked(left, left)) {
            guard case EvalCompare.Refusal.sameLog(let name) = $0 else { return XCTFail("\($0)") }
            XCTAssertEqual(name, left.name)
        }
    }

    /// L2 at the screen: the world's digest is part of what a run is called, so
    /// two worlds is two scales and the refusal names both.
    func testTwoWorldsAreRefusedAndBothAreNamed() throws {
        let (left, right) = try pair()
        let elsewhere = EvalCompare.Side(
            name: right.name,
            log: EvalLog(status: right.log.status,
                         eval: EvalLog.Spec(task: right.log.eval.task,
                                            policy: right.log.eval.policy,
                                            embodiment: "network-bench/duck-bench-5/other.mjb@ff00",
                                            created: right.log.eval.created,
                                            producer: right.log.eval.inspectRobotsVersion,
                                            policyConfig: [:], embodimentInfo: [:],
                                            maxSteps: nil, maxSeconds: nil),
                         results: right.log.results, stats: right.log.stats,
                         samples: right.log.samples, error: nil))
        XCTAssertThrowsError(try EvalCompare.checked(EvalCompare.Side(name: left.name,
                                                                     log: left.log),
                                                     elsewhere)) {
            guard case EvalCompare.Refusal.differentEmbodiment(let a, let b) = $0 else {
                return XCTFail("\($0)")
            }
            XCTAssertEqual(a, left.log.eval.embodiment)
            XCTAssertTrue(b.contains("other.mjb"))
            let message = EvalCompare.Refusal.differentEmbodiment(a, b).message
            XCTAssertTrue(message.contains(a))
            XCTAssertTrue(message.contains(b))
        }
    }

    /// The scenes decide what a scorer is measuring, so the same name on two
    /// tasks is two different questions.
    func testTwoTasksAreRefused() throws {
        let (left, _) = try pair()
        let three = try EvalFixtures.walkClean()
        XCTAssertThrowsError(try EvalCompare.checked(left, three)) {
            guard case EvalCompare.Refusal.differentTask(let a, let b) = $0 else {
                return XCTFail("\($0)")
            }
            XCTAssertNotEqual(a, b)
        }
    }

    func testTwoLogsWithNoScorerInCommonAreRefused() throws {
        let (left, _) = try pair()
        let foreign = EvalCompare.Side(
            name: "foreign.json",
            log: EvalLog(status: .success,
                         eval: EvalLog.Spec(task: left.log.eval.task,
                                            policy: "another.onnx",
                                            embodiment: left.log.eval.embodiment,
                                            created: "c", producer: "p",
                                            policyConfig: [:], embodimentInfo: [:],
                                            maxSteps: nil, maxSeconds: nil),
                         results: EvalLog.Results(totalScenes: 1, totalTrials: 1,
                                                  metrics: ["episode_length": 44.0],
                                                  erroredTrials: 0),
                         stats: left.log.stats, samples: [], error: nil))
        XCTAssertThrowsError(try EvalCompare.checked(EvalCompare.Side(name: left.name,
                                                                     log: left.log), foreign)) {
            XCTAssertEqual($0 as? EvalCompare.Refusal, .nothingInCommon)
        }
    }

    // MARK: - the rows

    func testEveryRowCarriesTwoNumbersAndNoThirdOne() throws {
        let (left, right) = try pair()
        let compare = try EvalCompare.checked(left, right)
        let rows = compare.rows
        XCTAssertEqual(rows.map(\.name), ["success_at_end", "net_displacement_m",
                                          "travelled_m", "end_height_m"])
        let travelled = try XCTUnwrap(rows.first { $0.name == EvalScorer.travelled.name })
        XCTAssertEqual(try XCTUnwrap(travelled.left), 0.805, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(travelled.right), 1.195, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(travelled.difference), 0.39, accuracy: 1e-9)
        XCTAssertEqual(travelled.better, .right)
        XCTAssertEqual(travelled.higherIsBetter, true)
        XCTAssertEqual(travelled.unit, "m")
    }

    /// A cost scorer prefers the other direction, and the app knows which way
    /// round only for the scorers it defines.
    func testDirectionComesFromTheScorerAndNeverFromAGuess() {
        let cheap = EvalCompare.Row(name: EvalScorer.maxTorque.name, said: nil,
                                    left: 0.6, right: 0.4, higherIsBetter: false, unit: "N m")
        XCTAssertEqual(cheap.better, .right)
        let unknown = EvalCompare.Row(name: "episode_length", said: nil,
                                      left: 40, right: 44, higherIsBetter: nil, unit: "")
        XCTAssertNil(unknown.better, "an opinion about somebody else's scorer is not a result")
        XCTAssertEqual(unknown.difference, 4)
    }

    func testASideWithNoNumberIsABlankAndNeverAZero() throws {
        let row = EvalCompare.Row(name: EvalScorer.travelled.name, said: nil,
                                  left: 1.0, right: nil, higherIsBetter: true, unit: "m")
        XCTAssertNil(row.difference)
        XCTAssertNil(row.better)
    }

    func testTwoIdenticalNumbersHaveNoBetterSide() {
        let row = EvalCompare.Row(name: EvalScorer.travelled.name, said: nil,
                                  left: 1.0, right: 1.0, higherIsBetter: true, unit: "m")
        XCTAssertEqual(row.difference, 0)
        XCTAssertNil(row.better)
    }

    /// The whole point of the type: no row, and no property anywhere on it,
    /// combines the two runs into one number.
    func testThereIsNoCombinedMetricAnywhere() throws {
        let (left, right) = try pair()
        let compare = try EvalCompare.checked(left, right)
        XCTAssertEqual(compare.rows.count, 4)
        XCTAssertFalse(EvalCompare.neverCombinedSaid.isEmpty)
        // Every row's numbers are the two logs' own, unchanged.
        for row in compare.rows {
            XCTAssertEqual(row.left, left.log.results.metrics[row.name])
            XCTAssertEqual(row.right, right.log.results.metrics[row.name])
        }
    }

    /// Comparing a run from this phone with one somebody published is the whole
    /// reason import exists, so an imported log is allowed on either side.
    func testAnImportedLogMayBeComparedWhenTheWorldAndTheTaskAgree() throws {
        let (left, right) = try pair()
        let asImported = try EvalLogFile.imported(right.bytes, named: "theirs.json",
                                                  runID: "bbbb0002")
        let compare = try EvalCompare.checked(left, asImported)
        XCTAssertEqual(compare.rows.count, 4)
        XCTAssertEqual(asImported.origin, .imported)
    }

    // MARK: - how much of each run there is

    /// A CANCELLED RUN IS COMPARABLE AND THE SCREEN HAS TO SAY SO. A run
    /// somebody stopped is filed with the scenes that finished and none of the
    /// ones that never started, so one column can be a mean over one scene and
    /// the other a mean over three, with a coloured winner between them and the
    /// word "cancelled" nowhere on the screen. The status is not refused here,
    /// because a partial run is real data; it is named.
    func testAPartialRunIsNamedRatherThanQuietlyCompared() throws {
        let task = try EvalTask.walkThreeCommands()
        let whole = EvalFixtures.file(
            try EvalFixtures.run(task: task, scenes: [
                EvalFixtures.walkScene("cmd-forward", task: task, travelled: [1.19]),
                EvalFixtures.walkScene("cmd-sideways", task: task, travelled: [0.42]),
                EvalFixtures.walkScene("cmd-turning", task: task, travelled: [0.11]),
            ]), runID: "cccc0001")
        let stopped = EvalFixtures.file(
            try EvalFixtures.run(task: task, scenes: [
                EvalFixtures.walkScene("cmd-forward", task: task, travelled: [1.30]),
            ], cancelled: true), runID: "cccc0002")
        let compare = try EvalCompare.checked(whole, stopped)
        XCTAssertTrue(compare.eitherIsPartial)
        let said = try XCTUnwrap(compare.partialSideSaid())
        XCTAssertTrue(said.hasPrefix("The log on the right is not a finished run"), said)
        XCTAssertTrue(EvalCompare.statusSaid(stopped.log).hasPrefix("Cancelled."),
                      EvalCompare.statusSaid(stopped.log))
        XCTAssertTrue(EvalCompare.statusSaid(whole.log).contains("3 scenes"))
        XCTAssertTrue(EvalCompare.statusSaid(stopped.log).contains("1 scene,"))
    }

    func testTwoFinishedRunsSayNothingAboutBeingPartial() throws {
        let (left, right) = try pair()
        let compare = try EvalCompare.checked(left, right)
        XCTAssertFalse(compare.eitherIsPartial)
        XCTAssertNil(compare.partialSideSaid())
        XCTAssertEqual(compare.statusSaid(compare.left), EvalCompare.statusSaid(left.log))
    }

    func testBothSidesBeingPartialNamesBothOfThem() throws {
        let task = try EvalTask.walkForwardOnly()
        let one = EvalFixtures.file(
            try EvalFixtures.run(task: task,
                                 scenes: [EvalFixtures.walkScene("cmd-forward", task: task,
                                                                 travelled: [1.1])],
                                 cancelled: true), runID: "dddd0001")
        let two = EvalFixtures.file(
            try EvalFixtures.run(task: task,
                                 scenes: [EvalFixtures.walkScene("cmd-forward", task: task,
                                                                 travelled: [1.2])],
                                 cancelled: true), runID: "dddd0002")
        let said = try XCTUnwrap(try EvalCompare.checked(one, two).partialSideSaid())
        XCTAssertTrue(said.hasPrefix("Neither of these two is a finished run"), said)
    }

    // MARK: - one row, out loud

    /// A11: which side a scorer prefers is carried on screen by colour and by
    /// nothing else, so the finding of the whole screen is unavailable to a
    /// screen reader and to anybody who cannot separate teal from ink.
    func testARowIsSpokenWithBothNumbersAndThePreference() throws {
        let (left, right) = try pair()
        let compare = try EvalCompare.checked(left, right)
        let travelled = try XCTUnwrap(compare.rows.first { $0.name == EvalScorer.travelled.name })
        let said = compare.spoken(travelled)
        XCTAssertTrue(said.hasPrefix("Left "), said)
        XCTAssertTrue(said.contains("Right "), said)
        XCTAssertTrue(said.contains("difference"), said)
        XCTAssertTrue(said.hasSuffix("Right is the better of the two here."), said)

        // Less is better on torque, so the preference is the other way round.
        let quieter = EvalCompare.Row(name: EvalScorer.maxTorque.name, said: nil,
                                      left: 0.5, right: 0.9, higherIsBetter: false, unit: "N m")
        XCTAssertTrue(compare.spoken(quieter).hasSuffix("Left is the better of the two here."))
    }

    /// A scorer this app does not know gets no opinion about direction, and a
    /// blank is a blank rather than a zero.
    func testARowThisAppCannotJudgeSaysSoOutLoud() throws {
        let (left, right) = try pair()
        let compare = try EvalCompare.checked(left, right)
        let unknown = EvalCompare.Row(name: "episode_length", said: nil,
                                      left: 44, right: nil, higherIsBetter: nil, unit: "")
        let said = compare.spoken(unknown)
        XCTAssertTrue(said.contains(EvalCompare.blankSaid), said)
        XCTAssertTrue(said.hasSuffix(EvalCompare.noDirectionSaid), said)
        let level = EvalCompare.Row(name: EvalScorer.travelled.name, said: nil,
                                    left: 1.0, right: 1.0, higherIsBetter: true, unit: "m")
        XCTAssertTrue(compare.spoken(level).hasSuffix(EvalCompare.noPreferenceSaid))
    }

    /// A13: the Compare row is disabled with fewer than two logs on the shelf,
    /// and the sentence under it has to answer that question rather than the
    /// one about which two may be compared.
    func testTheRowSaysWhyItCannotOpenYet() {
        XCTAssertTrue(EvalCompare.notEnoughLogsSaid(0).contains("no log here yet"),
                      EvalCompare.notEnoughLogsSaid(0))
        XCTAssertTrue(EvalCompare.notEnoughLogsSaid(1).contains("one log here"),
                      EvalCompare.notEnoughLogsSaid(1))
        XCTAssertNotEqual(EvalCompare.notEnoughLogsSaid(0), EvalCompare.notEnoughLogsSaid(1))
    }
}
