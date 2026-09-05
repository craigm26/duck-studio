import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// The four presets, the horizon, and the two rules a scene id has to keep.
final class EvalTaskTests: XCTestCase {

    // MARK: - the horizon

    /// THE CEILING IS THE BENCH'S TRACE CAP AND NOT A ROUND NUMBER. Five
    /// hundred ticks at fifty a second is ten seconds, so a traced trial's tick
    /// count is never a truncation. A recording that quietly stops before the
    /// episode does is a recording somebody would judge on.
    func testTheSecondsCeilingIsTheTraceCapDividedByTheTickRate() {
        XCTAssertEqual(EvalTask.secondsCeiling, Double(EvalTrace.cap) / DuckModel.tickHz)
        XCTAssertEqual(EvalTask.secondsCeiling, 10.0)
        XCTAssertEqual(EvalTrace.cap, 500)
        XCTAssertEqual(DuckModel.tickHz, 50.0)
    }

    /// `Task.resolve_envelope`: the integer budget the rollout actually uses.
    func testMaxStepsIsTheSecondsResolvedAtTheControlRate() throws {
        XCTAssertEqual(try EvalTask.walkForwardOnly(seconds: 6).maxSteps, 300)
        XCTAssertEqual(try EvalTask.walkForwardOnly(seconds: 0.21).maxSteps, 11,
                       "it rounds up, because a budget is a ceiling")
        XCTAssertEqual(try EvalTask.walkForwardOnly(seconds: 10).maxSteps, 500)
    }

    func testAHorizonOutsideTheRangeIsRefusedWithTheReason() {
        for bad in [0.0, 0.1, 10.1, 30.0] {
            XCTAssertThrowsError(try EvalTask.walkForwardOnly(seconds: bad)) { error in
                XCTAssertEqual(error as? EvalTask.Refusal, .secondsOutOfRange(bad))
            }
        }
        XCTAssertTrue(EvalTask.Refusal.secondsOutOfRange(30).message.contains("500 ticks"))
    }

    /// A grid task's horizon belongs to the harness, per cell, so this app does
    /// not make one up for the whole task.
    func testAGridTaskDeclaresNoHorizonOfItsOwn() throws {
        let task = try EvalTask.stairsGrid(cells: [Self.cell], rise: 0.06)
        XCTAssertNil(task.maxSeconds)
        XCTAssertNil(task.maxSteps)
    }

    // MARK: - the presets

    static let cell = DuckBench.Cell(dh: 0, drop: 0.12, fmul: 1.0, tier: .core)
    static let chaseCell = DuckBench.ChaseCell(bearing: 20, range: 0.7, drop: 0.12,
                                               fmul: 1.0, tier: .core)

    /// THE DEFAULT ASKS FOR ALL THREE COMMANDS, AND THAT IS THE DEFECT FIX.
    /// Four of eight tuner winners collapsed sideways travel while passing
    /// every gate this app had, and one collapsed yaw by 93 per cent with the
    /// reward going up. A walk evaluation that never asks for sideways is the
    /// thing this feature exists to catch.
    func testTheDefaultPresetAsksForForwardSidewaysAndTurning() throws {
        let task = try EvalTask.walkThreeCommands()
        XCTAssertEqual(task.scenes.map(\.id), ["cmd-forward", "cmd-sideways", "cmd-turning"])
        XCTAssertEqual(task.scenes[0].command, DuckBench.walkingCommand)
        XCTAssertEqual(task.scenes[1].command, DuckBench.sidewaysCommand)
        XCTAssertEqual(task.scenes[2].command, DuckBench.turningCommand)
    }

    func testTheWalkPresetsUseTheHeldOutDropsAndTheMedian() throws {
        for task in [try EvalTask.walkThreeCommands(), try EvalTask.walkForwardOnly()] {
            XCTAssertEqual(task.epochs.axis, .dropHeights(DuckTuner.Schedule.onAPhone.heldOutDrops))
            XCTAssertEqual(task.epochs.reducer, .median)
            XCTAssertEqual(task.epochs.count, 8)
            XCTAssertEqual(task.route, .tune)
            XCTAssertTrue(task.wantsTrace)
            XCTAssertEqual(task.scorers.names, EvalScorerSet.walk.names)
        }
    }

    func testTheGridPresetsScoreOneEpisodePerCellAndAskForNoTrace() throws {
        let stairs = try EvalTask.stairsGrid(cells: [Self.cell], rise: 0.06)
        XCTAssertEqual(stairs.epochs.axis, .single)
        XCTAssertEqual(stairs.route, .climb)
        XCTAssertFalse(stairs.wantsTrace, "only /tune answers with a trajectory")
        XCTAssertEqual(stairs.scorers.names, EvalScorerSet.stairs.names)

        let ball = try EvalTask.ballGrid(cells: [Self.chaseCell])
        XCTAssertEqual(ball.epochs.axis, .single)
        XCTAssertEqual(ball.route, .chase)
        XCTAssertFalse(ball.wantsTrace)
        XCTAssertEqual(ball.scorers.names, EvalScorerSet.ball.names)
    }

    /// L11's sibling on the task side: a route that answers one episode per
    /// call cannot be given a list of drop heights, because that would be the
    /// same episode scored several times.
    func testARouteThatDoesNotVaryCannotBeGivenADropList() throws {
        XCTAssertThrowsError(try EvalTask.checked(
            id: "x", name: "x", said: "x", route: .climb,
            scenes: [EvalScene(id: "a", instruction: "a")],
            scorers: .stairs,
            epochs: try EvalEpochs.drops([0.12, 0.13], reducer: .mean),
            maxSeconds: nil)) { error in
            XCTAssertEqual(error as? EvalTask.Refusal, .epochsOnARouteThatDoesNotVary("/climb"))
        }
    }

    // MARK: - scene ids

    /// A scene id becomes a path component in their frame store, and the
    /// harness's own cell label is `0.0/0.12/1.0/core`, which is three
    /// directories.
    func testEverySceneIdInEveryPresetIsFilesystemSafeAndUnique() throws {
        let cells = [DuckBench.Cell(dh: -0.01, drop: 0.12, fmul: 1.0, tier: .core),
                     DuckBench.Cell(dh: 0, drop: 0.12, fmul: 1.0, tier: .core),
                     DuckBench.Cell(dh: 0.01, drop: 0.13, fmul: 0.8, tier: .ext)]
        let chase = [DuckBench.ChaseCell(bearing: -20, range: 0.7, drop: 0.12, fmul: 1,
                                         tier: .core),
                     DuckBench.ChaseCell(bearing: 0, range: 0.5, drop: 0.12, fmul: 1,
                                         tier: .core),
                     DuckBench.ChaseCell(bearing: 20, range: 0.7, drop: 0.12, fmul: 1,
                                         tier: .ext)]
        let tasks = [try EvalTask.walkThreeCommands(),
                     try EvalTask.walkForwardOnly(),
                     try EvalTask.stairsGrid(cells: cells, rise: 0.06),
                     try EvalTask.ballGrid(cells: chase)]
        for task in tasks {
            XCTAssertEqual(Set(task.scenes.map(\.id)).count, task.scenes.count, task.id)
            for scene in task.scenes {
                XCTAssertTrue(scene.idIsFilesystemSafe, scene.id)
                XCTAssertFalse(scene.id.contains("/"), scene.id)
            }
        }
    }

    func testACellsSceneIdReadsLikeTheCell() {
        XCTAssertEqual(EvalScene.id(for: Self.cell, rise: 0.06), "cell-060mm-d120-f10-core")
        XCTAssertEqual(EvalScene.id(for: DuckBench.Cell(dh: -0.01, drop: 0.13, fmul: 0.8,
                                                        tier: .ext), rise: 0.09),
                       "cell-080mm-d130-f8-ext")
        XCTAssertEqual(EvalScene.id(for: Self.chaseCell), "ball-bp20-r070-d120-f10-core")
        XCTAssertEqual(EvalScene.id(for: DuckBench.ChaseCell(bearing: -20, range: 0.7,
                                                             drop: 0.12, fmul: 1, tier: .core)),
                       "ball-bm20-r070-d120-f10-core")
    }

    func testASceneIdWithASlashInItIsRefused() {
        XCTAssertThrowsError(try EvalTask.checked(
            id: "x", name: "x", said: "x", route: .climb,
            scenes: [EvalScene(id: "0.0/0.12/1.0/core", instruction: "a")],
            scorers: .stairs, epochs: .single(reducer: .mean), maxSeconds: nil)) { error in
            XCTAssertEqual(error as? EvalTask.Refusal,
                           .sceneIDNotFilesystemSafe("0.0/0.12/1.0/core"))
        }
    }

    func testTwoScenesCannotShareAnId() {
        XCTAssertThrowsError(try EvalTask.checked(
            id: "x", name: "x", said: "x", route: .climb,
            scenes: [EvalScene(id: "a", instruction: "a"),
                     EvalScene(id: "a", instruction: "b")],
            scorers: .stairs, epochs: .single(reducer: .mean), maxSeconds: nil)) { error in
            XCTAssertEqual(error as? EvalTask.Refusal, .duplicateSceneID("a"))
        }
    }

    func testATaskWithNoScenesIsRefused() {
        XCTAssertThrowsError(try EvalTask.checked(
            id: "x", name: "x", said: "x", route: .tune, scenes: [], scorers: .walk,
            epochs: .single(reducer: .mean), maxSeconds: 6)) { error in
            XCTAssertEqual(error as? EvalTask.Refusal, .noScenes)
        }
    }

    // MARK: - instructions

    /// The instruction and the schedule cannot drift apart, because the
    /// instruction is built from the schedule.
    func testTheInstructionSaysWhatTheScheduleAsksFor() throws {
        let task = try EvalTask.walkThreeCommands(seconds: 6)
        XCTAssertEqual(task.scenes[0].instruction,
                       "Go forward at 0.5 m/s from 0.5 seconds in, and still be standing at 6 "
                     + "seconds.")
        XCTAssertEqual(task.scenes[1].instruction,
                       "Go sideways at 0.3 m/s from 0.5 seconds in, and still be standing at 6 "
                     + "seconds.")
        XCTAssertTrue(task.scenes[2].instruction.contains("turning at 0.6 rad/s"))
        XCTAssertTrue(task.scenes[2].instruction.contains("forward at 0.3 m/s"))
    }

    // MARK: - scene_metadata

    /// E6 in the file rather than in a comment: the axis is written as numbers
    /// so an archived log goes on meaning what it meant if the tuner's held-out
    /// list ever changes.
    func testTheSceneBlockCarriesTheDropHeightsAsNumbers() throws {
        let task = try EvalTask.walkForwardOnly()
        let block = task.sceneMetadata(for: task.scenes[0])
        XCTAssertEqual(block["drop_heights_m"], .numbers(EvalTask.walkDrops))
        XCTAssertEqual(block["reducer"], .string("median"))
        XCTAssertEqual(block["route"], .string("/tune"))
        XCTAssertEqual(block["seconds"], .double(6))
        XCTAssertEqual(block["terms_refused"], .array([]))
        XCTAssertEqual(block["schedule"]?.arrayValue?.count, 2)
        XCTAssertEqual(block["schedule"]?.arrayValue?.last?["vx"], .double(0.5))
    }

    /// C5. The harness's own cell label rides in the metadata, where it can be
    /// read and cannot become a directory.
    func testAGridSceneKeepsTheHarnessesOwnLabelInTheMetadata() throws {
        let task = try EvalTask.stairsGrid(cells: [Self.cell], rise: 0.06)
        let block = task.sceneMetadata(for: task.scenes[0])
        XCTAssertEqual(block["cell_label"], .string(Self.cell.said(rise: 0.06)))
        XCTAssertEqual(block["cell_label"], .string("60/.120/x1.0"))
        XCTAssertEqual(block["rise_m"], .double(0.06))
        XCTAssertEqual(block["cell"]?["tier"], .string("core"))
        XCTAssertNil(block["drop_heights_m"], "a single axis has no drop list")
    }

    func testTheSceneBlockCarriesNoneOfTheirOwnSchemaKeys() throws {
        let task = try EvalTask.walkThreeCommands()
        for scene in task.scenes {
            let block = task.sceneMetadata(for: scene, refusedTerms: ["feet_air_time"])
            for key in EvalLog.Key.all {
                XCTAssertNil(block[key], "\(key) is one of their schema keys")
            }
        }
    }

    // MARK: - the fold, which is what makes "identity residual" true

    /// WITHOUT THIS, "IDENTITY RESIDUAL, SO THE NETWORK IS UNCHANGED" IS PROSE
    /// IN A LOG. Every walk evaluation sends the identity vector to `/tune`,
    /// which folds a gain into the last layer before it runs anything. If the
    /// identity fold moved a single bit, every log this app writes would claim
    /// the network as it was trained and mean something else.
    func testFoldingAtIdentityLeavesTheParameterBytesUnchanged() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "alpha_walking",
                                                  withExtension: "onnx",
                                                  subdirectory: "Fixtures/policies"))
        let base = try DuckPolicy.load(contentsOf: url)
        let folded = try DuckTuner.TuningVector.identity.folded(into: base)
        XCTAssertEqual(base.canonicalParameterBytes, folded.canonicalParameterBytes,
                       "the identity residual changed the network")
        XCTAssertEqual(base.fingerprint, folded.fingerprint)
        // And the vector really is the identity, so the test is not passing
        // because nothing was folded at all.
        XCTAssertEqual(DuckTuner.TuningVector.identity.gain,
                       [Double](repeating: 1, count: DuckModel.policyJointCount))
        XCTAssertEqual(DuckTuner.TuningVector.identity.offset,
                       [Double](repeating: 0, count: DuckModel.policyJointCount))
        XCTAssertTrue(DuckTuner.TuningVector.identity.changedSlots.isEmpty)
    }

    // MARK: - the door

    func testTheRowTitleAndTheDoorDetailAreTheSameSentenceEverywhere() {
        XCTAssertEqual(EvalTask.rowTitle, "Run a formal evaluation")
        XCTAssertEqual(EvalTask.doorDetail, EvalTask.whatAnEvaluationIs)
    }

    /// The two routes this build does not offer say why, under the picker,
    /// rather than being absent and read as an oversight.
    func testTheTwoRoutesThisBuildDoesNotOfferSayWhy() {
        XCTAssertTrue(EvalTask.whyNotMeasure.contains("without saying which"))
        XCTAssertTrue(EvalTask.whyNotPerform.contains("chooses its own rollouts"))
        XCTAssertEqual(EvalTask.Route.allCases.map(\.path), ["/tune", "/climb", "/chase"])
    }

    /// D1. No new bench route: every route this feature uses is already in the
    /// list the phone's own loopback server forwards.
    func testEveryRouteThisFeatureUsesIsAlreadyOneTheBenchListHas() {
        for route in EvalTask.Route.allCases {
            XCTAssertTrue(DuckBench.routes.contains(route.path), route.path)
        }
        XCTAssertTrue(DuckBench.routes.contains("/health"))
    }
}
