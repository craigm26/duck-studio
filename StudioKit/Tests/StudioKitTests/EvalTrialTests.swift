import XCTest
@testable import StudioKit

/// The two things a trial cannot carry, and the vocabulary a verdict is written
/// in.
final class EvalTrialTests: XCTestCase {

    private func tick() -> DuckBench.Tuned.Tick {
        DuckBench.Tuned.Tick(root: [0, 0, 0.12, 1, 0, 0, 0],
                             qvel: [0, 0, 0, 0, 0, 0],
                             twist: [0, 0, 0, 0, 0, 0],
                             joints: [Double](repeating: 0, count: 14),
                             action: [Double](repeating: 0, count: 14),
                             command: [0.5, 0, 0])
    }

    private func trace(_ ticks: Int = 100) -> EvalTrace {
        EvalTrace(ticks: (0..<ticks).map { _ in tick() }, dropHeight: 0.12, why: nil)
    }

    // MARK: - L8, a score an errored trial cannot carry

    func testAnErroredTrialCannotCarryAScoreEvenIfOneIsHandedIn() {
        let trial = EvalTrial(sceneID: "a", epoch: 0, status: .error,
                              scores: ["success_at_end": 1.0],
                              terminationReason: "success", ticks: 300, error: "it diverged",
                              metadata: [:], verdict: nil, trace: nil)
        XCTAssertEqual(trial.scores, [:])
        XCTAssertNil(trial.terminationReason)
        XCTAssertFalse(trial.wasScored)
    }

    func testACancelledTrialCannotCarryAScoreEither() {
        let trial = EvalTrial(sceneID: "a", epoch: 0, status: .cancelled,
                              scores: ["success_at_end": 1.0], terminationReason: "success",
                              ticks: nil, error: nil, metadata: [:], verdict: nil, trace: nil)
        XCTAssertEqual(trial.scores, [:])
    }

    func testAScoredTrialKeepsWhatItWasGiven() {
        let trial = EvalTrial.scored(sceneID: "a", epoch: 1,
                                     scores: ["travelled_m": 1.19],
                                     terminationReason: "success", ticks: 300,
                                     metadata: ["drop_m": .double(0.12)])
        XCTAssertEqual(trial.scores, ["travelled_m": 1.19])
        XCTAssertEqual(trial.terminationReason, "success")
        XCTAssertEqual(trial.ticks, 300)
        XCTAssertTrue(trial.wasScored)
    }

    func testAnErroredTrialCarriesTheBenchsOwnWords() {
        let trial = EvalTrial.errored(sceneID: "a", epoch: 2,
                                      why: "the bench said: it diverged at tick 41",
                                      metadata: ["diverged": .bool(true)])
        XCTAssertEqual(trial.error, "the bench said: it diverged at tick 41")
        XCTAssertEqual(trial.metadata["diverged"], .bool(true))
        XCTAssertNil(trial.ticks)
    }

    // MARK: - L21, a verdict on a run nobody could watch

    func testAVerdictWithoutATraceIsDropped() {
        let verdict = EvalVerdict(answer: .yes, note: "it walked")
        let unwatched = EvalTrial.scored(sceneID: "a", epoch: 1, scores: [:],
                                         terminationReason: "success", ticks: nil,
                                         metadata: [:], verdict: verdict, trace: nil)
        XCTAssertNil(unwatched.verdict)
        let watched = EvalTrial.scored(sceneID: "a", epoch: 0, scores: [:],
                                       terminationReason: "success", ticks: 100,
                                       metadata: [:], verdict: verdict, trace: trace())
        XCTAssertEqual(watched.verdict, verdict)
    }

    // MARK: - the trace

    func testTheTraceKnowsWhetherItRanIntoTheBenchsCap() {
        XCTAssertFalse(trace(100).wasCapped)
        XCTAssertTrue(trace(EvalTrace.cap).wasCapped)
    }

    func testTheTraceKnowsWhichDropItBelongsTo() {
        XCTAssertEqual(trace().dropHeight, 0.12)
    }

    // MARK: - the verdict vocabulary

    /// Their `_OPERATOR_SUCCESS` treats `yes` as a success and neither of the
    /// other two, so a fourth word would make a log written here read
    /// differently in their own tools.
    func testTheAnswersAndSourcesAreTheirWordsAndOnlyTheirs() {
        XCTAssertEqual(EvalVerdict.Answer.allCases.map(\.rawValue), ["yes", "no", "partial"])
        XCTAssertEqual(EvalVerdict.Source.allCases.map(\.rawValue),
                       ["console", "prompt", "embodiment", "vlm"])
    }

    /// The only path on this phone is a person answering a question on a
    /// screen, which is their word `prompt`.
    func testTheDefaultSourceIsTheOneThisAppActuallyUses() {
        XCTAssertEqual(EvalVerdict(answer: .partial, note: nil).source, .prompt)
    }

    func testTheThreeAnswersReadAsSentences() {
        XCTAssertEqual(EvalVerdict.Answer.yes.said, "It did what the scene asked")
        XCTAssertEqual(EvalVerdict.Answer.no.said, "It did not")
        XCTAssertEqual(EvalVerdict.Answer.partial.said, "Partly")
    }

    /// L22 as a sentence: a verdict is recorded and is not a metric, and the
    /// reason is that only one trial in a scene is watchable at all.
    func testTheVerdictSentenceSaysWhyItIsNotAScore() {
        XCTAssertTrue(EvalVerdict.recordedNotScoredSaid.contains("is not turned into a score"))
        XCTAssertTrue(EvalTrace.firstDropOnlySaid.contains("first drop"))
        XCTAssertTrue(EvalTrace.firstDropOnlySaid.contains("500"))
    }
}
