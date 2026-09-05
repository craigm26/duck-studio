import XCTest
@testable import StudioKit

/// The run's four status rules, the two means, the eight parallel arrays, and
/// the numbers this app refuses to make up.
final class EvalRunTests: XCTestCase {

    // MARK: - building one

    private func embodiment() throws -> EvalEmbodiment {
        let health = try DuckBench.readHealth(Data(#"""
        {"bench":"duck-bench/5","plant":"scene.mjb","plantName":"scene.mjb",
         "plantDigest":"3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be",
         "tickHz":50,"cores":4,"policies":[],"trains":false}
        """#.utf8))
        return try EvalEmbodiment.checked(body: .networkBench, health: health,
                                          address: "100.122.199.6:8770",
                                          answeredRoutes: ["/tune", "/reset"])
    }

    private let policy = EvalPolicy(
        kind: .libraryNetwork, title: "Pollen's walking network",
        identity: .parameters("27b1f53d1f26aa9c4b7e0d1a5f83c2e6d4907b1c3e8f5a2d6b0c9e7f4a1d8b35"),
        benchPolicyName: "alpha_walking.onnx", residualIsIdentity: true)

    private func run(scenes: [EvalSceneResult], cancelled: Bool = false,
                     haltedBy: String? = nil, task: EvalTask? = nil) throws -> EvalRun {
        let plan = try task ?? EvalTask.walkForwardOnly()
        return EvalRun(task: plan, policy: policy,
                embodiment: try embodiment(),
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 23.884177),
                scenes: scenes, wasCancelled: cancelled, haltedBy: haltedBy)
    }

    private func scene(_ id: String, values: [Double],
                       errored: Int = 0,
                       reducer: EvalEpochs.Reducer = .median,
                       sceneError: String? = nil) -> EvalSceneResult {
        var trials: [EvalTrial] = []
        for (index, value) in values.enumerated() {
            trials.append(.scored(sceneID: id, epoch: index,
                                  scores: ["travelled_m": value, "success_at_end": 1.0],
                                  terminationReason: "success",
                                  ticks: index == 0 ? 300 : nil, metadata: [:]))
        }
        for index in 0..<errored {
            trials.append(.errored(sceneID: id, epoch: values.count + index,
                                   why: "the bench said: it diverged"))
        }
        return EvalSceneResult(scene: EvalScene(id: id, instruction: "walk"),
                               reducer: reducer, trials: trials, error: sceneError)
    }

    // MARK: - the reduction and the two means

    func testASceneReducesEachScorerAcrossItsOwnEpochs() {
        let result = scene("cmd-forward", values: [1.0, 2.0, 3.0])
        XCTAssertEqual(result.reduced["travelled_m"], 2.0)
        XCTAssertEqual(result.reduced["success_at_end"], 1.0)
        XCTAssertEqual(result.epochValues.count, 3)
    }

    /// `metrics[name]` is the mean over the SCENES that carry it, not over the
    /// trials, so a scene with more epochs does not weigh more. That is
    /// `eval.py`'s rule and this is where it lives, once.
    func testMetricsIsTheMeanOverScenesAndNotOverTrials() throws {
        let run = try run(scenes: [scene("a", values: [1.0]),
                                   scene("b", values: [3.0, 3.0, 3.0, 3.0, 3.0])])
        XCTAssertEqual(try XCTUnwrap(run.metrics["travelled_m"]), 2.0, accuracy: 1e-12,
                       "a mean over trials would be 2.67")
    }

    /// A scorer no scene carries is ABSENT rather than zero.
    func testAScorerNoSceneCarriesIsAbsentFromMetrics() throws {
        let run = try run(scenes: [scene("a", values: [1.0])])
        XCTAssertNil(run.metrics["end_height_m"])
        XCTAssertNil(run.metrics["net_displacement_m"])
        XCTAssertEqual(Set(run.metrics.keys), ["travelled_m", "success_at_end"])
    }

    /// Only the scorers the task declared. A number that arrived under a name
    /// the task never named is not a metric of this task.
    func testMetricsOnlyEverCarriesTheTasksOwnScorerNames() throws {
        let odd = EvalSceneResult(
            scene: EvalScene(id: "a", instruction: "walk"), reducer: .mean,
            trials: [.scored(sceneID: "a", epoch: 0, scores: ["something_else": 4.0],
                             terminationReason: "success", ticks: nil, metadata: [:])])
        let run = try run(scenes: [odd])
        XCTAssertNil(run.metrics["something_else"])
    }

    // MARK: - errored trials

    /// L8 and the account of it. An errored trial is counted, is visible, and
    /// is in no average.
    func testAnErroredTrialIsCountedAndNeverAveraged() throws {
        let run = try run(scenes: [scene("a", values: [1.0, 3.0], errored: 2)])
        XCTAssertEqual(run.totalTrials, 4)
        XCTAssertEqual(run.erroredTrials, 2)
        XCTAssertEqual(try XCTUnwrap(run.metrics["travelled_m"]), 2.0, accuracy: 1e-12)
        XCTAssertEqual(run.scenes[0].epochValues, [["travelled_m": 1.0, "success_at_end": 1.0],
                                                   ["travelled_m": 3.0, "success_at_end": 1.0],
                                                   [:], [:]])
    }

    /// A diverged episode makes the TRIAL an error and the SCENE an error, and
    /// the run goes on: two failed episodes out of twenty-four is data about
    /// the policy rather than a broken run.
    func testADivergedEpisodeDoesNotMakeTheWholeRunAnError() throws {
        let run = try run(scenes: [scene("a", values: [1.0, 3.0], errored: 2)])
        XCTAssertEqual(run.scenes[0].status, .error)
        XCTAssertEqual(run.status, .success)
        XCTAssertNil(run.error)
    }

    // MARK: - the four status rules

    func testAPlainRunIsASuccess() throws {
        XCTAssertEqual(try run(scenes: [scene("a", values: [1.0])]).status, .success)
    }

    func testASceneWithItsOwnErrorMakesTheRunAnError() throws {
        let run = try run(scenes: [scene("a", values: [1.0],
                                         sceneError: "the reducer could not reduce that")])
        XCTAssertEqual(run.status, .error)
        XCTAssertEqual(run.error, "the reducer could not reduce that")
    }

    func testStoppingIsCancelledAndKeepsWhatRan() throws {
        let run = try run(scenes: [scene("a", values: [1.0])], cancelled: true)
        XCTAssertEqual(run.status, .cancelled)
        XCTAssertEqual(run.totalTrials, 1)
        XCTAssertTrue(EvalTask.stopIsNotAFailure.contains("Stopping keeps what already ran"))
    }

    /// L7, in upstream's own wording, so a reader who has seen one of their
    /// logs recognises this one.
    func testEveryTrialErroredIsAnErrorInTheirOwnWords() throws {
        let run = try run(scenes: [scene("a", values: [], errored: 3)])
        XCTAssertEqual(run.status, .error)
        XCTAssertEqual(run.error, "all 3 trial(s) errored; nothing was scored")
        XCTAssertEqual(run.metrics, [:])
        XCTAssertEqual(run.erroredTrials, run.totalTrials)
    }

    func testARunWithNoTrialsAtAllIsNotCalledAnError() throws {
        XCTAssertEqual(try run(scenes: []).status, .success)
        XCTAssertEqual(try run(scenes: []).totalTrials, 0)
        XCTAssertNil(try run(scenes: []).error)
    }

    /// L17 and L18: the two faults that stop everything rather than being one
    /// errored trial.
    func testAHaltStopsTheRunAndSaysWhichFault() throws {
        let changed = EvalRun.plantChangedMidRun(from: "3f8c9ab9b409ba74", to: "aa11bb22cc33dd44")
        let run = try run(scenes: [scene("a", values: [1.0])], haltedBy: changed)
        XCTAssertEqual(run.status, .error)
        XCTAssertEqual(run.error, changed)
        XCTAssertTrue(changed.contains("3f8c9ab9b409"))
        XCTAssertTrue(changed.contains("aa11bb22cc33"))
        XCTAssertTrue(EvalRun.tailNotDeclared(declared: 50, reported: 30).contains("50"))
        XCTAssertTrue(EvalRun.tailNotDeclared(declared: 50, reported: 30).contains("30"))
    }

    func testCancellingBeatsEveryOtherStatusBecauseItIsWhatHappened() throws {
        let run = try run(scenes: [scene("a", values: [], errored: 2)], cancelled: true)
        XCTAssertEqual(run.status, .cancelled)
    }

    // MARK: - L9, the step count

    /// Only ticks a route actually reported. Never seconds times a rate.
    func testTotalStepsCountsOnlyWhatWasReported() throws {
        let run = try run(scenes: [scene("a", values: [1.0, 2.0, 3.0]),
                                   scene("b", values: [1.0, 2.0, 3.0])])
        XCTAssertEqual(run.totalSteps, 600, "one traced episode per scene, 300 ticks each")
        XCTAssertEqual(run.totalTrials, 6)
        XCTAssertTrue(EvalRun.stepCountsSaid.contains("only control ticks a route actually "
                                                    + "reported"))
    }

    func testAGridRunReportsNoStepsRatherThanInventingThem() throws {
        let cells = [DuckBench.Cell(dh: 0, drop: 0.12, fmul: 1, tier: .core)]
        let task = try EvalTask.stairsGrid(cells: cells, rise: 0.06)
        let cell = EvalSceneResult(
            scene: task.scenes[0], reducer: .mean,
            trials: [.scored(sceneID: task.scenes[0].id, epoch: 0,
                             scores: ["success_at_end": 1.0], terminationReason: "success",
                             ticks: nil, metadata: [:])])
        let run = try run(scenes: [cell], task: task)
        XCTAssertEqual(run.totalSteps, 0)
    }

    // MARK: - L10 and L19

    func testNothingTimedTheInferenceAndNothingStoredAFrame() {
        XCTAssertTrue(EvalRun.noLatencySaid.contains("network measurement"))
        XCTAssertTrue(EvalRun.noFramesSaid.contains("No frames were stored"))
    }

    /// L19. Eight arrays, one length, built from one list of trials so a short
    /// one cannot be written.
    func testTheEightParallelArraysAreAlwaysTheSameLength() {
        let result = scene("a", values: [1.0, 2.0], errored: 1)
        let lengths = [result.epochValues.count, result.terminationReasons.count,
                       result.operatorJudgements.count, result.judgementSources.count,
                       result.operatorNotes.count, result.operatorMessages.count,
                       result.trialMetadata.count, result.policyTranscripts.count]
        XCTAssertEqual(Set(lengths), [3])
    }

    func testAVerdictLandsAtTheIndexOfTheTrialItBelongsTo() {
        let trace = EvalTrace(ticks: [DuckBench.Tuned.Tick(
            root: [0, 0, 0.12, 1, 0, 0, 0], qvel: [0, 0, 0, 0, 0, 0],
            twist: [0, 0, 0, 0, 0, 0], joints: [], action: [], command: [0.5, 0, 0])],
                              dropHeight: 0.12, why: nil)
        let watched = EvalTrial.scored(sceneID: "a", epoch: 0, scores: ["travelled_m": 1.0],
                                       terminationReason: "success", ticks: 300, metadata: [:],
                                       verdict: EvalVerdict(answer: .yes, note: "it drifts left"),
                                       trace: trace)
        let unwatched = EvalTrial.scored(sceneID: "a", epoch: 1, scores: ["travelled_m": 2.0],
                                         terminationReason: "success", ticks: nil, metadata: [:])
        let result = EvalSceneResult(scene: EvalScene(id: "a", instruction: "walk"),
                                     reducer: .median, trials: [watched, unwatched])
        XCTAssertEqual(result.operatorJudgements, ["yes", nil])
        XCTAssertEqual(result.judgementSources, ["prompt", nil])
        XCTAssertEqual(result.operatorNotes, ["it drifts left", nil])
        XCTAssertEqual(result.operatorMessages, [[], []])
        XCTAssertEqual(result.policyTranscripts, [.null, .null])
        XCTAssertEqual(result.trialMetadata[0]["traced"], .bool(true))
        XCTAssertEqual(result.trialMetadata[1]["traced"], .bool(false))
        XCTAssertEqual(result.trialMetadata[0]["ticks_reported"], .integer(300))
        XCTAssertEqual(result.trialMetadata[1]["ticks_reported"], .null)
    }

    func testARunKnowsWhetherAnythingWasWatchedAtAll() throws {
        XCTAssertFalse(try run(scenes: [scene("a", values: [1.0])]).anyTrialTraced)
    }

    // MARK: - a non-finite score

    /// `json_log._sanitize` maps a non-finite float to null, which is correct
    /// and also invisible. So the value goes to null in the file the way theirs
    /// does and the scorer's NAME comes back out for the screen.
    func testANonFiniteScoreIsNamedRatherThanQuietlyNulled() throws {
        let odd = EvalSceneResult(
            scene: EvalScene(id: "a", instruction: "walk"), reducer: .mean,
            trials: [.scored(sceneID: "a", epoch: 0,
                             scores: ["travelled_m": .infinity, "success_at_end": 1.0],
                             terminationReason: "success", ticks: nil, metadata: [:])])
        let run = try run(scenes: [odd])
        XCTAssertEqual(run.nonFiniteScores, ["travelled_m"])
        XCTAssertEqual(EvalLogJSON.numbers(["travelled_m": .infinity]),
                       .object(["travelled_m": .null]))
    }

    // MARK: - the waits

    func testTheCallTimeoutIsThePhysicsPlusTheTransport() {
        // Eight six second drops is forty eight seconds of simulation, which
        // still sits under the floor.
        XCTAssertEqual(EvalRun.callTimeout(seconds: 6, episodes: 8), 180)
        XCTAssertEqual(EvalRun.callTimeout(seconds: 10, episodes: 32), 410)
        XCTAssertEqual(EvalRun.probeSeconds, 30)
    }

    func testTheDurationIsTheTwoTimestamps() throws {
        // A `Date` holds seconds since 2001 as a Double, so a 2026 timestamp
        // has about a microsecond of room left in its mantissa. The tolerance
        // is that, and not a hedge.
        XCTAssertEqual(try run(scenes: []).durationSeconds, 23.884177, accuracy: 1e-6)
    }

    // MARK: - who wrote it

    /// L11. Their own report prints this field verbatim in its footer, so a
    /// version number there would say a Python library ran.
    func testTheProducerNamesUsAndDeniesThem() {
        let said = EvalRun.producerSaid(version: "1.1", build: "58")
        XCTAssertEqual(said, "none; written by Microduck Studio 1.1 (58). No inspect-robots ran: "
                           + "an iPhone cannot run Python.")
    }
}
