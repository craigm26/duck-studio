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
              plantName: "scene.mjb",
              plantDigest: "3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be",
              policy: "alpha_stand.onnx",
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
        XCTAssertEqual(physics!.detail,
                       "16 of 16 — stayed upright. On scene.mjb, sha256 3f8c9ab9b409.",
                       "the plant is part of the result, and it is the plant that ran")
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
        {"format":"duck-intent-clips/3","policy":"alpha_stand.onnx","authored":true,
         "rollouts":8,"achieves":8,"criterion":"stayed upright to the end, over drop heights 0.120-0.130 m",
         "medianHeight":0.0908,"endsUpright":true,"endHeight":0.0911,"peakJointRate":10.765}
        """
        let outcome = try DuckBench.readOutcome(Data(body.utf8),
                                                when: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(outcome.achieves, 8)
        XCTAssertEqual(outcome.peakJointRate, 10.765)
        XCTAssertTrue(outcome.isClean)
        XCTAssertTrue(outcome.endedLow, "8 of 8 upright, and still 25 mm short of standing")
    }

    func testABenchErrorIsNotSilentlyAnEmptyResult() {
        let body = #"{"error":"perform needs a track of keyframes"}"#
        XCTAssertThrowsError(try DuckBench.readOutcome(Data(body.utf8), when: Date()))
    }
}

// MARK: - which world it ran in

extension PipelineTests {

    /// The bench names its own world now, and the outcome keeps both halves of
    /// the name: the file, and which bytes that file was.
    func testAPerformAnswerCarriesThePlantTheBenchActuallyRan() throws {
        let body = """
        {"format":"duck-intent-clips/3","policy":"alpha_stand.onnx","authored":true,
         "plantName":"scene.mjb",
         "plantDigest":"3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be",
         "rollouts":8,"achieves":8,"criterion":"stayed upright","medianHeight":0.116}
        """
        let outcome = try DuckBench.readOutcome(Data(body.utf8), when: Date())
        XCTAssertEqual(outcome.plantName, "scene.mjb")
        XCTAssertEqual(outcome.plantDigest,
                       "3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be")
        XCTAssertEqual(outcome.plantSentence, "On scene.mjb, sha256 3f8c9ab9b409.")
    }

    /// THE BUG THIS FIXES, stated as a test. Every outcome stored before today
    /// carries the literal placeholder "the bench's own plant" under a key this
    /// type no longer has, because `readHealth` on a `/perform` body always
    /// threw and the fallback at the call site always won. Read one back and it
    /// must say nothing was recorded — never the placeholder, and never a
    /// sentence shaped like a fact.
    func testAnOutcomeStoredBeforeAnyBenchNamedItsWorldSaysNothingRecordedIt() throws {
        let stored = """
        {"when":0,"bench":"duck-intent-clips/3","plant":"the bench's own plant",
         "policy":"alpha_stand.onnx","achieves":8,"rollouts":8,
         "criterion":"stayed upright to the end, over drop heights 0.120-0.130 m",
         "medianHeight":0.0908,"peakJointRate":10.765}
        """
        let outcome = try JSONDecoder().decode(Pipeline.BenchOutcome.self,
                                               from: Data(stored.utf8))
        XCTAssertNil(outcome.plantName)
        XCTAssertNil(outcome.plantDigest)
        XCTAssertEqual(outcome.plantSentence,
                       "Nothing recorded which world this ran in, so nothing here can tell you. "
                     + "A result with no world beside it cannot be compared with one that has "
                     + "another.")
        // IT MUST NOT NAME A CAUSE. An outcome stored before the bench reported
        // a plant, a bench on an older build, and a bench that did not answer
        // this time are indistinguishable here — so a sentence picking one of
        // them is the same fabrication as the placeholder this replaced.
        XCTAssertFalse(outcome.plantSentence.contains("predates"))
        XCTAssertFalse(outcome.plantSentence.lowercased().contains("older"))
        XCTAssertFalse(outcome.told.contains("the bench's own plant"))
        XCTAssertEqual(outcome.achieves, 8, "the numbers it did measure survive intact")
    }

    /// THE ONE THAT WOULD DELETE PEOPLE'S WORK IF IT FAILED. `DraftStore.reload`
    /// decodes every file inside `compactMap { try? … }`, so a `keyNotFound`
    /// here is not an error a user sees — it is the draft disappearing from the
    /// list. A non-Optional stored property with a default does NOT rescue a
    /// missing key; synthesised `Decodable` throws regardless of the default.
    /// So both new fields are Optional with no default, and this proves it on
    /// an outcome written by the version that shipped before them.
    func testAnOutcomeWithNoPlantKeysAtAllStillDecodesRatherThanVanishing() throws {
        let stored = """
        {"when":0,"bench":"duck-bench","policy":"unknown","achieves":3,"rollouts":8,
         "criterion":"stayed upright"}
        """
        let outcome = try JSONDecoder().decode(Pipeline.BenchOutcome.self,
                                               from: Data(stored.utf8))
        XCTAssertNil(outcome.plantName)
        XCTAssertEqual(outcome.rollouts, 8)

        // And the same file inside a whole draft, which is the shape on disk.
        var made = draft()
        made.bench = try JSONDecoder().decode(Pipeline.BenchOutcome.self,
                                              from: Data(stored.utf8))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(made)) as? [String: Any])
        var benchJSON = try XCTUnwrap(json["bench"] as? [String: Any])
        benchJSON.removeValue(forKey: "plantName")
        benchJSON.removeValue(forKey: "plantDigest")
        json["bench"] = benchJSON
        let decoded = try JSONDecoder().decode(
            IntentDraft.self, from: try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.bench?.rollouts, 8)
        XCTAssertNil(decoded.bench?.plantName)
    }

    /// A bench that names a file but will not digest it is not lying, it is
    /// silent — and the difference is a sentence. A filename alone does not
    /// identify a world: two files called `scene.mjb` exist in duck-sounds,
    /// same size, different bytes, one running a solver four times stiffer.
    func testABenchThatNamesItsPlantWithoutDigestingItSaysWhatThatCosts() {
        var vague = goodRun
        vague.plantDigest = nil
        XCTAssertEqual(vague.plantSentence,
                       "On scene.mjb. This bench will not say which bytes that was, and two "
                     + "benches can call different worlds by that name — so a result from this "
                     + "one cannot be matched to a result from another.")
    }

    /// The stage line joins a measured claim to a world, so the join is
    /// asserted rather than left to a view's string interpolation.
    func testTheResultAndTheWorldAreOneSentenceEach() {
        var crouched = goodRun
        crouched.medianHeight = 0.0908
        XCTAssertEqual(crouched.told,
                       "16 of 16 — stayed upright. It ends 25 mm below standing height. "
                     + "On scene.mjb, sha256 3f8c9ab9b409.")
    }

    /// The baseline every crouch is measured against names the world it was
    /// measured in. It sits directly under a run that may have recorded no
    /// world at all, so it must not borrow that run's.
    func testTheStandingBaselineNamesThePlantItWasMeasuredOn() {
        XCTAssertEqual(Pipeline.standingHeightSaid,
                       "Standing height is 0.116 m — what the standing policy holds on "
                     + "scene.mjb, the canon plant, when it is simply left alone. A motion "
                     + "that ends much below that stayed up without standing up.")
        XCTAssertFalse(Pipeline.standingHeightSaid.contains("this plant"))
    }

    /// No composed sentence anywhere may contain the placeholder that started
    /// this. It was never measured, and there is no code path left that can
    /// produce it — this asserts the absence rather than trusting it.
    func testThePlaceholderPlantIsNotSayableAnyMore() {
        for name in [nil, "scene.mjb"] as [String?] {
            for digest in [nil, "3f8c9ab9b409ba74"] as [String?] {
                let said = DuckBench.plantSaid(name: name, digest: digest)
                XCTAssertFalse(said.contains("the bench's own plant"), said)
                XCTAssertFalse(said.isEmpty)
            }
        }
        // An empty string from a bench is an absent answer, not a world named "".
        XCTAssertEqual(DuckBench.plantSaid(name: "", digest: "abc"),
                       DuckBench.plantSaid(name: nil, digest: nil))
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

    /// The four states a screen reader gets instead of a colour. Asserted
    /// literally, because the whole point of them is that nobody can check them
    /// by looking at the screen.
    func testEveryPipelineStateSaysWhereItStandsInWords() {
        XCTAssertEqual(Pipeline.State.done.spoken, "done")
        XCTAssertEqual(Pipeline.State.attention.spoken, "done, worth reading")
        XCTAssertEqual(Pipeline.State.waiting.spoken, "not done yet")
        XCTAssertEqual(Pipeline.State.blocked.spoken, "blocked")
        // None of them is "pending", which the Stage doc comment specifically
        // rules out for the printed line and means here too.
        for state: Pipeline.State in [.done, .attention, .waiting, .blocked] {
            XCTAssertFalse(state.spoken.contains("pending"), state.spoken)
            XCTAssertFalse(state.spoken.isEmpty)
        }
    }
}
