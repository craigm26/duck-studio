import XCTest
import DuckKit
@testable import StudioKit

final class PipelineTests: XCTestCase {

    private func draft(problems: [IntentDraft.Problem] = []) -> IntentDraft {
        // A two-key draft that resolves cleanly; problems are asserted about
        // separately because they come from the resolver, not the initialiser.
        var made = IntentDraft.blank()
        made.name = "Bow"
        return made
    }

    private var goodRun: Pipeline.BenchOutcome {
        .init(when: Date(timeIntervalSince1970: 0), bench: "duck-bench/2",
              plant: "legs", policy: "BEST_alpha_stand.onnx",
              achieves: 16, rollouts: 16, criterion: "stayed upright", medianHeight: 0.116)
    }

    func testAFreshDraftIsWrittenAndCheckedAndNothingElse() {
        let pipeline = Pipeline.of(draft())
        XCTAssertEqual(pipeline.stages.map(\.name),
                       ["Written", "Checked", "Run in physics", "Attested", "On the robot"])
        XCTAssertEqual(pipeline.stages[0].state, .done)
        XCTAssertEqual(pipeline.next?.name, "Run in physics")
    }

    /// The one that matters: a preview on the phone is not a run. An iPhone has
    /// no physics engine, and a stage that let the two blur would be the app
    /// implying a motion works when nothing has tried it.
    func testAPreviewIsNotARun() {
        let pipeline = Pipeline.of(draft(), bench: nil, hasBench: true)
        let physics = pipeline.stages.first { $0.name == "Run in physics" }
        XCTAssertEqual(physics?.state, .waiting)
        XCTAssertTrue(physics!.detail.contains("no physics engine on an iPhone"))
    }

    func testWithoutABenchTheStageSaysHowToGetOne() {
        let physics = Pipeline.of(draft(), hasBench: false)
            .stages.first { $0.name == "Run in physics" }
        XCTAssertTrue(physics!.detail.contains("duckbench"))
    }

    func testACleanRunFinishesTheStageAndOffersAttestation() {
        let pipeline = Pipeline.of(draft(), bench: goodRun, hasBench: true)
        let physics = pipeline.stages.first { $0.name == "Run in physics" }
        XCTAssertEqual(physics?.state, .done)
        XCTAssertTrue(physics!.detail.contains("16 of 16"))
        XCTAssertTrue(physics!.detail.contains("legs"), "the plant is part of the result")
        let attested = pipeline.stages.first { $0.name == "Attested" }
        XCTAssertEqual(attested?.state, .waiting)
        XCTAssertTrue(attested!.detail.contains("real run to attest"))
    }

    /// A partial run is not a pass. 12 of 16 is a result worth keeping and a
    /// result worth reading, and the difference has to be visible.
    func testAPartialRunAsksToBeRead() {
        var partial = goodRun
        partial.achieves = 12
        let physics = Pipeline.of(draft(), bench: partial, hasBench: true)
            .stages.first { $0.name == "Run in physics" }
        XCTAssertEqual(physics?.state, .attention)
        XCTAssertFalse(partial.isClean)
    }

    /// Signing a motion nobody ran would certify the drawing, not the robot.
    func testThereIsNothingToAttestBeforeARun() {
        let attested = Pipeline.of(draft()).stages.first { $0.name == "Attested" }
        XCTAssertEqual(attested?.state, .waiting)
        XCTAssertTrue(attested!.detail.contains("certify the drawing"))
    }

    /// The last stage is blocked by the world, not by the person, and it says
    /// so. It must never read as something they forgot to do.
    func testTheRobotStageIsBlockedAndHonestAboutWhy() {
        let last = Pipeline.of(draft(), bench: goodRun, isAttested: true).stages.last
        XCTAssertEqual(last?.state, .blocked)
        XCTAssertTrue(last!.detail.contains("no output channel"))
    }

    /// A blocked stage is not progress withheld. Counting it would peg every
    /// finished motion at four fifths forever.
    func testProgressIgnoresWhatCannotBeDone() {
        let finished = Pipeline.of(draft(), bench: goodRun, hasBench: true, isAttested: true)
        XCTAssertEqual(finished.fractionDone, 1.0, accuracy: 1e-9)
        XCTAssertNil(finished.next)
        let fresh = Pipeline.of(draft())
        XCTAssertEqual(fresh.fractionDone, 0.5, accuracy: 1e-9)   // written + checked of four
    }

    /// A run survives being written down and read back, because a result that
    /// does not persist is a result nobody can check later.
    /// Staying up is not standing up. MEASURED: an authored bow keeps 8 of 8
    /// rollouts upright and ends at 0.091 m, twenty-five millimetres below the
    /// 0.116 m the standing policy holds on the same plant. The preview draws
    /// a clean return to standing, because a preview draws the request.
    func testAMotionThatStaysUpButEndsInACrouchIsFlagged() {
        var crouched = goodRun
        crouched.medianHeight = 0.0908
        XCTAssertTrue(crouched.isClean, "every rollout did stay upright")
        XCTAssertTrue(crouched.endedLow)
        XCTAssertTrue(crouched.summary.contains("25 mm below standing"))
        let physics = Pipeline.of(draft(), bench: crouched, hasBench: true)
            .stages.first { $0.name == "Run in physics" }
        XCTAssertEqual(physics?.state, .attention, "clean but crouched still asks to be read")
    }

    /// And the baseline itself must not trip it.
    func testAMotionEndingAtStandingHeightIsNotFlagged() {
        var upright = goodRun
        upright.medianHeight = Pipeline.standingHeight
        XCTAssertFalse(upright.endedLow)
        XCTAssertEqual(Pipeline.of(draft(), bench: upright, hasBench: true)
            .stages.first { $0.name == "Run in physics" }?.state, .done)
    }

    func testAnOutcomeRoundTrips() throws {
        let data = try JSONEncoder().encode(goodRun)
        XCTAssertEqual(try JSONDecoder().decode(Pipeline.BenchOutcome.self, from: data), goodRun)
    }

    /// Every draft saved before this field existed still decodes.
    func testOlderDraftsWithoutABenchStillDecode() throws {
        var made = draft()
        made.bench = nil
        let data = try JSONEncoder().encode(made)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "bench")
        let older = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(IntentDraft.self, from: older)
        XCTAssertNil(decoded.bench)
        XCTAssertEqual(decoded.name, made.name)
    }
}

extension PipelineTests {

    /// The call the bench actually accepts. Proved against a running bench:
    /// an authored bow came back 8 of 8 upright, peak rate 10.765 rad/s.
    func testThePerformCallCarriesTheTrack() throws {
        let address = try DuckBench.address("localhost:8771")
        let call = try DuckBench.perform(
            address,
            keys: [(at: 0, pose: Array(repeating: 0, count: 14)),
                   (at: 0.8, pose: Array(repeating: 0.1, count: 14))],
            seconds: 3, rollouts: 8)
        XCTAssertEqual(call.url.absoluteString, "http://localhost:8771/perform")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: call.body!) as? [String: Any])
        XCTAssertEqual(body["rollouts"] as? Int, 8)
        let track = try XCTUnwrap(body["track"] as? [[String: Any]])
        XCTAssertEqual(track.count, 2)
        XCTAssertEqual((track[1]["pose"] as? [Double])?.count, 14)
    }

    /// The real answer from the bench, read into something a draft keeps.
    func testAPerformAnswerBecomesAnOutcome() throws {
        let body = """
        {"format":"duck-intent-clips/3","policy":"BEST_alpha_stand.onnx","authored":true,
         "rollouts":8,"achieves":8,"criterion":"stayed upright to the end, over drop heights 0.120-0.130 m",
         "medianHeight":0.0908,"endsUpright":true,"endHeight":0.0911,"peakJointRate":10.765}
        """
        let outcome = try DuckBench.readOutcome(Data(body.utf8),
                                                when: Date(timeIntervalSince1970: 0),
                                                plant: "legs")
        XCTAssertEqual(outcome.achieves, 8)
        XCTAssertEqual(outcome.peakJointRate, 10.765)
        XCTAssertTrue(outcome.isClean)
        XCTAssertTrue(outcome.endedLow, "8 of 8 upright, and still 25 mm short of standing")
    }

    func testABenchErrorIsNotSilentlyAnEmptyResult() {
        let body = #"{"error":"perform needs a track of keyframes"}"#
        XCTAssertThrowsError(try DuckBench.readOutcome(Data(body.utf8), when: Date(), plant: "legs"))
    }
}

extension PipelineTests {

    /// Sending fifteen joints where fourteen are expected shifts everything
    /// after the mouth by one, so the right leg gets driven by the left leg's
    /// neighbours. It would look like bad physics rather than bad indexing.
    func testTheMouthIsDroppedBeforeTheBenchSeesIt() {
        var made = IntentDraft.blank()
        var pose = Array(repeating: 0.0, count: DuckModel.jointCount)
        pose[DuckModel.mouthIndex] = 0.5          // mouth wide open
        pose[DuckModel.mouthIndex + 1] = 0.25     // the joint that must survive
        made.keys = [.init(time: 0.4, pose: pose)]
        let track = made.benchTrack
        XCTAssertEqual(track.count, 1)
        XCTAssertEqual(track[0].pose.count, 14)
        XCTAssertEqual(track[0].at, 0.4)
        XCTAssertFalse(track[0].pose.contains(0.5), "the mouth must not reach the bench")
        XCTAssertEqual(track[0].pose[DuckModel.mouthIndex], 0.25,
                       "the joint after the mouth closes the gap, not shifts past it")
    }

    func testKeysReachTheBenchInTimeOrder() {
        var made = IntentDraft.blank()
        let pose = Array(repeating: 0.0, count: DuckModel.jointCount)
        made.keys = [.init(time: 1.2, pose: pose), .init(time: 0.3, pose: pose)]
        XCTAssertEqual(made.benchTrack.map(\.at), [0.3, 1.2])
    }
}
