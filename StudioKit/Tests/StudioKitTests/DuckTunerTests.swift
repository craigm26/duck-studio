import XCTest
import DuckKit
@testable import StudioKit

/// The tuning screen's whole value is that it refuses to run a search it cannot
/// score honestly, so what these tests guard is the refusals and the arithmetic
/// behind them — not the search, which is somebody else's optimiser wearing a
/// different hat.
final class DuckTunerTests: XCTestCase {

    private func realBytes(_ name: String = "alpha_walking") throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "onnx",
                                                  subdirectory: "Fixtures/policies"),
                                "missing fixture \(name).onnx")
        return try Data(contentsOf: url)
    }

    private func realPolicy(_ name: String = "alpha_walking") throws -> DuckPolicy {
        try DuckPolicy.load(from: try realBytes(name))
    }

    // MARK: - what is searched

    func testIdentityIsTheUntouchedNetwork() {
        let identity = DuckTuner.TuningVector.identity
        XCTAssertEqual(identity.gain, [Double](repeating: 1, count: DuckModel.policyJointCount))
        XCTAssertEqual(identity.offset, [Double](repeating: 0, count: DuckModel.policyJointCount))
        XCTAssertTrue(identity.isIdentity)
        XCTAssertTrue(identity.changedSlots.isEmpty)
        XCTAssertEqual(identity.described, "Nothing changed: gain 1, trim 0 on every slot.")
    }

    /// THE OFF-BY-ONE THIS WHOLE INDEXING SCHEME EXISTS TO PREVENT. Fifteen
    /// joints, fourteen policy outputs: a 15-wide array handed straight in
    /// would shift every joint past the mouth by one, which is catastrophic and
    /// completely silent. It is refused, and the message says which index to
    /// drop and what lives there.
    func testAFifteenWideArrayIsRefusedByName() {
        let fifteen = [Double](repeating: 1, count: DuckModel.jointCount)
        let fourteen = [Double](repeating: 0, count: DuckModel.policyJointCount)
        XCTAssertThrowsError(try DuckTuner.TuningVector.checked(gain: fifteen,
                                                               offset: fourteen)) {
            let refusal = $0 as? DuckTuner.TuningVector.Refusal
            XCTAssertEqual(refusal, .wrongWidth(field: "gain", was: 15))
            let message = try? XCTUnwrap(refusal?.message)
            XCTAssertTrue(message?.contains("mouth") == true,
                          "it names the joint that has no policy output")
            XCTAssertTrue(message?.contains("index 9") == true,
                          "and the index to drop, so the fix is in the message")
        }
        XCTAssertThrowsError(try DuckTuner.TuningVector.checked(gain: fourteen,
                                                               offset: fifteen)) {
            XCTAssertEqual($0 as? DuckTuner.TuningVector.Refusal,
                           .wrongWidth(field: "trim", was: 15))
        }
    }

    func testANaNIsRefusedRatherThanFolded() {
        var gain = DuckTuner.TuningVector.identity.gain
        gain[3] = .nan
        XCTAssertThrowsError(try DuckTuner.TuningVector.checked(
            gain: gain, offset: DuckTuner.TuningVector.identity.offset)) {
            XCTAssertEqual($0 as? DuckTuner.TuningVector.Refusal, .notANumber(field: "gain"))
        }
    }

    func testTheEnvelopeIsEnforcedAndNamesTheJoint() {
        var gain = DuckTuner.TuningVector.identity.gain
        gain[0] = 1.9
        XCTAssertThrowsError(try DuckTuner.TuningVector.checked(
            gain: gain, offset: DuckTuner.TuningVector.identity.offset)) {
            let refusal = $0 as? DuckTuner.TuningVector.Refusal
            XCTAssertEqual(refusal, .outsideTheEnvelope(field: "gain", slot: 0, was: 1.9))
            XCTAssertTrue(refusal?.message.contains("left_hip_yaw") == true,
                          "a person reading this has to know which joint")
        }
    }

    /// THE TRIM LIMIT COMES OUT OF THE MODEL, AND ON THIS ROBOT IT NEVER BINDS
    /// — which is a measurement and is stated rather than assumed either way.
    /// The tightest joint is the hip roll, 0.2967 rad from its home pose to its
    /// nearer stop, so its half-room is 0.1483 against a flat envelope of 0.05.
    /// Every other slot has more room than that. A first version of this rule
    /// used a tenth of each joint's TRAVEL and this test caught it doing
    /// nothing at all; what follows asserts both halves — that the rule is the
    /// derivation, and that it is currently slack.
    func testTheTrimLimitIsReadOutOfTheModelAndIsSlackOnThisRobot() {
        var tightest = Double.infinity, tightestName = ""
        for slot in 0..<DuckModel.policyJointCount {
            let joint = DuckModel.jointOfPolicySlot(slot)
            let range = DuckModel.jointRanges[joint]
            let home = DuckModel.homePose[joint]
            let room = min(range.upper - home, home - range.lower)
            XCTAssertEqual(DuckTuner.TuningVector.offsetLimit(forSlot: slot),
                           min(DuckTuner.TuningVector.offsetLimit, room / 2), accuracy: 1e-12,
                           "slot \(slot) — \(DuckModel.jointNames[joint])")
            // Slack today: the flat envelope is what actually bounds the search.
            XCTAssertEqual(DuckTuner.TuningVector.offsetLimit(forSlot: slot),
                           DuckTuner.TuningVector.offsetLimit, accuracy: 1e-12,
                           "\(DuckModel.jointNames[joint]) has room to spare")
            if room / 2 < tightest { tightest = room / 2; tightestName = DuckModel.jointNames[joint] }
        }
        XCTAssertTrue(tightestName.contains("hip_roll"), "the tightest joint, named")
        XCTAssertEqual(tightest, 0.1483, accuracy: 0.0002,
                       "and its number, so widening the envelope past it is a visible change")
    }

    /// PROOF THAT THE GUARD CAN FIRE. A rule that has never been observed to
    /// bind is a rule nobody has checked, and the one above is slack on every
    /// joint of this robot. Handed a flat envelope wider than the hip roll's
    /// half-room, the model has to win — and it does.
    func testTheModelWinsWhenTheFlatEnvelopeIsWiderThanTheJointsRoom() {
        let hipRoll = 1   // left_hip_roll, the tightest slot
        XCTAssertEqual(DuckTuner.TuningVector.offsetLimit(forSlot: hipRoll, within: 0.5),
                       0.1483, accuracy: 0.0002,
                       "the joint's own room bounds it, not the number that was asked for")
        XCTAssertLessThan(DuckTuner.TuningVector.offsetLimit(forSlot: hipRoll, within: 0.5), 0.5)
        // And the roomiest joint still takes the flat number at that width.
        let headYaw = 7
        XCTAssertEqual(DuckTuner.TuningVector.offsetLimit(forSlot: headYaw, within: 0.5), 0.5,
                       accuracy: 1e-12)
    }

    /// The mouth never appears. Not skipped — absent, because there is no row
    /// of the last layer that belongs to it.
    func testNoSlotMapsToTheMouth() {
        let joints = (0..<DuckModel.policyJointCount).map(DuckModel.jointOfPolicySlot)
        XCTAssertFalse(joints.contains(DuckModel.mouthIndex))
        XCTAssertEqual(Set(joints).count, DuckModel.policyJointCount, "and none is doubled")
    }

    func testClampingPutsThingsBackAndNeverProducesANaN() throws {
        let wild = DuckTuner.TuningVector(
            gain: [Double](repeating: 9, count: DuckModel.policyJointCount),
            offset: [Double](repeating: .nan, count: DuckModel.policyJointCount)).clamped()
        XCTAssertEqual(wild.gain, [Double](repeating: DuckTuner.TuningVector.gainUpper,
                                          count: DuckModel.policyJointCount))
        XCTAssertTrue(wild.offset.allSatisfy { $0 == 0 }, "a NaN clamps to no trim, not to a limit")
        // AND A CLAMPED VECTOR PASSES THE DOOR THAT REFUSES. If it did not, the
        // mutator would be producing candidates the exporter would reject.
        XCTAssertNoThrow(try DuckTuner.TuningVector.checked(gain: wild.gain,
                                                           offset: wild.offset))
    }

    // MARK: - the schedule and the mutation

    func testTheHeadIsNotSearched() {
        let schedule = DuckTuner.Schedule.onAPhone
        XCTAssertEqual(schedule.searchedSlots.count, 10, "ten leg slots of fourteen")
        for head in DuckTuner.Schedule.headSlots {
            XCTAssertFalse(schedule.searchedSlots.contains(head))
        }
        // The four excluded slots ARE the head joints, checked against the
        // model rather than against the numbers 5 to 8.
        let names = DuckTuner.Schedule.headSlots
            .map { DuckModel.jointNames[DuckModel.jointOfPolicySlot($0)] }
        XCTAssertEqual(names, ["neck_pitch", "head_pitch", "head_yaw", "head_roll"])
    }

    func testAMutationMovesOnlyLegSlotsAndIsReproducibleFromItsSeed() {
        let schedule = DuckTuner.Schedule.onAPhone
        var a = DuckTuner.Seeded(seed: 7)
        var b = DuckTuner.Seeded(seed: 7)
        let first = DuckTuner.mutate(.identity, with: schedule, using: &a)
        let again = DuckTuner.mutate(.identity, with: schedule, using: &b)
        XCTAssertEqual(first, again, "same seed, same child — or a run cannot be reproduced")

        var other = DuckTuner.Seeded(seed: 8)
        XCTAssertNotEqual(first, DuckTuner.mutate(.identity, with: schedule, using: &other),
                          "and a different seed is a different search")

        for head in DuckTuner.Schedule.headSlots {
            XCTAssertEqual(first.gain[head], 1)
            XCTAssertEqual(first.offset[head], 0)
        }
        XCTAssertFalse(first.changedSlots.isEmpty, "it did move something")
        XCTAssertNoThrow(try DuckTuner.TuningVector.checked(gain: first.gain,
                                                           offset: first.offset))
    }

    /// THE COUNT INCLUDES THE TWO RUNS THAT MAKE THE ANSWER MEAN ANYTHING. A
    /// schedule that counted only the children would under-report the cost by
    /// the baseline and the held-out check — which are exactly the episodes a
    /// person is tempted to skip.
    func testTheEpisodeCountIncludesTheBaselineAndTheHeldOutCheck() {
        let s = DuckTuner.Schedule.onAPhone
        let children = s.generations * s.lambda * s.searchDrops.count
        XCTAssertEqual(s.episodes,
                       s.searchDrops.count + s.heldOutDrops.count + children + s.heldOutDrops.count)
        XCTAssertGreaterThan(s.episodes, children, "the baseline and the check are in it")
        XCTAssertEqual(s.simSeconds, Double(s.episodes) * s.seconds)
    }

    // MARK: - the reward

    /// THE WEIGHTS ARE THE ONES THE REST OF THE APP GRADES A CLIP BY. If these
    /// ever drift from `RunMetrics`, a search would be climbing a hill nothing
    /// else can see.
    func testTheSixTermsCarryTheVelocityConfigsOwnWeights() {
        let byKey = Dictionary(uniqueKeysWithValues: DuckTuner.terms.map { ($0.key, $0.weight) })
        XCTAssertEqual(DuckTuner.terms.count, 6)
        XCTAssertEqual(byKey["upright"], RunMetrics.Task.velocity.upright.weight)
        XCTAssertEqual(byKey["body_ang_vel"], RunMetrics.Task.velocity.bodyAngularVelocityWeight)
        XCTAssertEqual(byKey["action_rate_l2"], RunMetrics.Task.velocity.actionRateWeight)
        XCTAssertEqual(byKey["track_linear_velocity"],
                       RunMetrics.Task.trackLinearVelocityWeight)
        XCTAssertEqual(byKey["track_angular_velocity"],
                       RunMetrics.Task.trackAngularVelocityWeight)
        XCTAssertEqual(byKey["pose"], RunMetrics.Task.poseWeight)
        XCTAssertEqual(DuckTuner.configFile, "microduck_velocity_env_cfg.py")
        XCTAssertEqual(DuckTuner.terms.filter(\.isPenalty).map(\.key),
                       ["body_ang_vel", "action_rate_l2"],
                       "two of the six are penalties, which is why a missing term is dangerous")
    }

    private var everyTerm: [String: Double] {
        Dictionary(uniqueKeysWithValues: DuckTuner.terms.map { ($0.key, 0.5) })
    }

    func testTheRewardIsTheWeightedSum() throws {
        let total = try DuckTuner.reward(everyTerm)
        XCTAssertEqual(total, DuckTuner.terms.reduce(0) { $0 + 0.5 * $1.weight }, accuracy: 1e-12)
    }

    /// THE TRAP, PROVEN RATHER THAN ASSERTED AWAY. `action_rate_l2` is worth
    /// −1.0, so a bench that omitted it and a client that summed with `?? 0`
    /// would hand every candidate a BETTER score than any real measurement of
    /// that term could give it — silently, and in the direction that selects
    /// for the jerkiest duck in the envelope. The test shows the wrong answer
    /// is higher, then shows the right answer is a throw.
    func testAMissingPenaltyTermWouldScoreBetterThanAnyRealValue() {
        var short = everyTerm
        short["action_rate_l2"] = nil
        let ifItHadBeenTreatedAsZero = DuckTuner.terms
            .reduce(0.0) { $0 + (short[$1.key] ?? 0) * $1.weight }
        let honest = (try? DuckTuner.reward(everyTerm)) ?? 0
        XCTAssertGreaterThan(ifItHadBeenTreatedAsZero, honest,
                             "the omission flatters the candidate — that is the whole danger")
        XCTAssertThrowsError(try DuckTuner.reward(short)) {
            XCTAssertEqual($0 as? DuckTuner.Refusal, .termMissing("action_rate_l2"))
            XCTAssertTrue(($0 as? DuckTuner.Refusal)?.message.contains("negative") == true)
        }
    }

    func testANonNumberTermIsRefused() {
        var bad = everyTerm
        bad["pose"] = .infinity
        XCTAssertThrowsError(try DuckTuner.reward(bad)) {
            XCTAssertEqual($0 as? DuckTuner.Refusal, .termNotANumber("pose"))
        }
    }

    /// The refusal list is the config's own, reused rather than retyped.
    func testTheUnansweredTermsAreRunMetricsOwnList() {
        XCTAssertEqual(DuckTuner.refusedByThePlant.map(\.key),
                       RunMetrics.Task.velocity.unevaluable.map(\.0))
        XCTAssertFalse(DuckTuner.refusedByThePlant.isEmpty)
        XCTAssertTrue(DuckTuner.refusedByThePlant.allSatisfy { !$0.why.isEmpty },
                      "a name with no reason is a shorter list pretending to be information")
    }

    // MARK: - whether a search may run at all

    /// THE MEASUREMENT THAT DECIDES THE SCREEN. A loop over `/state` answers
    /// can see two of the six terms, and both are terms a duck standing still
    /// maximises — measured at 2.9812 for the standing policy against 2.5287
    /// for the walking one, on the same bench under the same command, having
    /// travelled 1 mm against 1231.
    func testAStateLoopCannotHonestlyScoreASearch() {
        let readiness = DuckTuner.readiness(for: .aLoopOverStates)
        XCTAssertFalse(readiness.canSearch)
        XCTAssertEqual(readiness.missing.map(\.key).sorted(),
                       ["action_rate_l2", "body_ang_vel",
                        "track_angular_velocity", "track_linear_velocity"])
        XCTAssertEqual(DuckTuner.scorableByAStateLoop.map(\.key), ["upright", "pose"])
        // AND THE TWO THAT SURVIVE ARE BOTH REWARDS RATHER THAN PENALTIES,
        // which is why the standing policy wins: it maximises them by doing
        // nothing.
        XCTAssertTrue(DuckTuner.scorableByAStateLoop.allSatisfy { !$0.isPenalty })
        XCTAssertGreaterThan(DuckTuner.inertScore, DuckTuner.walkingScore,
                             "the measurement is the argument")
        XCTAssertLessThan(DuckTuner.inertTravelMillimetres,
                          DuckTuner.walkingTravelMillimetres / 100)
    }

    /// A BLOCKED SURFACE SHIPS AS AN EXPLICIT NOT-YET, so the sentence has to
    /// name the missing endpoint and carry the numbers. A refusal that only
    /// said "not supported" would teach somebody the app is small, where this
    /// is a specific and fixable gap in a bench.
    func testTheNotYetNamesTheEndpointAndTheNumbers() {
        let sentence = DuckTuner.notYet
        XCTAssertTrue(sentence.contains("/tune"), "it names what the bench has to grow")
        XCTAssertTrue(sentence.contains("2.9812") && sentence.contains("2.5287"),
                      "with the measurement, not an assertion")
        XCTAssertTrue(sentence.contains("1231"), "and the distance that makes it damning")
        XCTAssertTrue(sentence.contains("no velocity and no action"),
                      "and the reason, which is about the answers and not about the phone")
        XCTAssertFalse(DuckTuner.whatStillWorksWithoutTune.isEmpty,
                       "and what the bench CAN do is said in the same breath")
    }

    func testABenchThatScoresIsAllowedToSearch() {
        let readiness = DuckTuner.readiness(for: .benchComputesThem)
        XCTAssertTrue(readiness.canSearch)
        XCTAssertTrue(readiness.missing.isEmpty)
        XCTAssertEqual(readiness.sentence, DuckTuner.ready)
    }

    // MARK: - the farming guard

    /// `PolicyBlend`'s own check, reused. The shape it catches is the measured
    /// one: a candidate that stands up every time and travels a fraction of the
    /// distance the network it came from covers.
    func testTheInertGuardCatchesTheMeasuredShapeAndNotAWalk() {
        XCTAssertTrue(DuckTuner.wentInert(travelled: 0.002, baselineTravelled: 1.207,
                                          standing: 16, of: 16))
        XCTAssertFalse(DuckTuner.wentInert(travelled: 1.180, baselineTravelled: 1.207,
                                           standing: 16, of: 16),
                       "a duck that walked is not inert")
        XCTAssertFalse(DuckTuner.wentInert(travelled: 0.002, baselineTravelled: 1.207,
                                           standing: 2, of: 16),
                       "one that fell over is a different failure and is scored, not rejected")
        XCTAssertFalse(DuckTuner.wentInert(travelled: 0.001, baselineTravelled: 0.001,
                                           standing: 16, of: 16),
                       "and blending two motions that both stand still cannot be 'going inert'")
    }

    // MARK: - the export

    func testAFoldedPolicyIsANewNetworkThatStillLoads() throws {
        let baseBytes = try realBytes()
        let base = try DuckPolicy.load(from: baseBytes)
        var gain = DuckTuner.TuningVector.identity.gain
        var trim = DuckTuner.TuningVector.identity.offset
        for slot in DuckTuner.Schedule.legSlots { gain[slot] = 1.08; trim[slot] = 0.01 }
        let vector = try DuckTuner.TuningVector.checked(gain: gain, offset: trim)

        let export = try DuckTuner.export(
            baseFile: baseBytes, basePolicy: "alpha_walking.onnx", declaredActionScale: 1.0,
            vector: vector, schedule: .onAPhone, seed: 7, bench: "This iPhone",
            measuredTerms: everyTerm, travelled: 1.2, elapsed: 300)

        // IT IS A POLICY IN THE SENSE EVERYTHING ELSE MEANS IT.
        let reloaded = try DuckPolicy.load(from: export.onnx)
        XCTAssertEqual(reloaded.fingerprint, export.fingerprint)
        XCTAssertNotEqual(export.fingerprint, base.fingerprint,
                          "a fold that changed nothing would not be worth writing")
        XCTAssertEqual(export.baseFingerprint, base.fingerprint)
        XCTAssertEqual(export.filename, "tuned-\(reloaded.fingerprint.prefix(12)).onnx")
        XCTAssertEqual(PolicyReport.of(export.onnx, name: export.filename).outcome, .runnable,
                       "and the app's own refusal screen accepts it")
    }

    /// THE ARITHMETIC, CHECKED AGAINST THE DEFINITION RATHER THAN AGAINST
    /// ITSELF. Row `j` of the last layer scaled by `gain[j]`; bias `j` scaled
    /// and shifted. Everything before the last layer untouched — fold anywhere
    /// else and an ELU sits between it and the output, and ELU does not commute
    /// with a scale.
    func testTheFoldTouchesTheLastLayerAndOnlyTheLastLayer() throws {
        let baseBytes = try realBytes()
        let base = try DuckPolicy.load(from: baseBytes)
        var gain = DuckTuner.TuningVector.identity.gain
        var trim = DuckTuner.TuningVector.identity.offset
        gain[0] = 1.25; trim[0] = 0.03
        let folded = try DuckTuner.TuningVector.checked(gain: gain, offset: trim).folded(into: base)

        XCTAssertEqual(folded.parameters.mean, base.parameters.mean)
        XCTAssertEqual(folded.parameters.std, base.parameters.std)
        for index in 0..<(base.parameters.layers.count - 1) {
            XCTAssertEqual(folded.parameters.layers[index].weights,
                           base.parameters.layers[index].weights,
                           "layer \(index) is untouched")
        }
        let was = try XCTUnwrap(base.parameters.layers.last)
        let now = try XCTUnwrap(folded.parameters.layers.last)
        for i in 0..<was.inputs {
            XCTAssertEqual(now.weights[i], was.weights[i] * 1.25, accuracy: 1e-5,
                           "row 0 is scaled")
        }
        XCTAssertEqual(now.biases[0], was.biases[0] * 1.25 + 0.03, accuracy: 1e-6)
        for j in 1..<was.outputs {
            XCTAssertEqual(now.biases[j], was.biases[j], "and no other row moved")
        }
    }

    /// THE PROVENANCE HAS TO SURVIVE THE FILE BEING SENT SOMEWHERE ALONE, which
    /// is what `metadata_props` is for and why it is written onto the ONNX and
    /// not only into the manifest beside it.
    func testTheProvenanceIsInTheOnnxAndTheFileStillLoads() throws {
        let baseBytes = try realBytes()
        let base = try DuckPolicy.load(from: baseBytes)
        var gain = DuckTuner.TuningVector.identity.gain
        gain[0] = 1.1
        let vector = try DuckTuner.TuningVector.checked(
            gain: gain, offset: DuckTuner.TuningVector.identity.offset)
        let export = try DuckTuner.export(
            baseFile: baseBytes, basePolicy: "alpha_walking.onnx", declaredActionScale: 1.0,
            vector: vector, schedule: .onAPhone, seed: 42, bench: "This iPhone",
            measuredTerms: everyTerm, travelled: 1.1, elapsed: 240)

        let metadata = DuckTuner.metadata(of: export.onnx)
        XCTAssertEqual(metadata["microduck_studio.kind"], "tuned")
        XCTAssertEqual(metadata["microduck_studio.base_policy"], "alpha_walking.onnx")
        XCTAssertEqual(metadata["microduck_studio.base_fingerprint"], base.fingerprint)
        XCTAssertEqual(metadata["microduck_studio.seed"], "42")
        XCTAssertEqual(metadata["microduck_studio.reward_config"], DuckTuner.configFile)
        XCTAssertEqual(metadata["microduck_studio.never_on_hardware"], DuckTuner.neverOnHardware)
        for term in DuckTuner.terms {
            XCTAssertTrue(metadata["microduck_studio.terms"]?.contains(term.key) == true,
                          "\(term.key) is named in the file itself")
        }
        // AND ADDING THE FIELD DID NOT BREAK THE FILE, which is the half a
        // hand-written protobuf append could plausibly get wrong.
        XCTAssertNoThrow(try DuckPolicy.load(from: export.onnx))
    }

    /// THE BUG THAT AN OUTSIDE PARSER FOUND, AND THE ONLY ONE HERE THAT COULD
    /// HAVE SHIPPED A WORKING-LOOKING FILE THAT DRIVES A ROBOT WRONGLY.
    ///
    /// `DuckPolicyWriter.encoded` writes a graph and no `metadata_props`, which
    /// is right for a writer of parameters and wrong for an exporter of
    /// policies: the first version of `export` assembled a folded file out of
    /// parameters alone and it arrived with NOTHING — no `default_joint_pos`,
    /// no `action_scale`, no joint names. `default_joint_pos` is the neutral
    /// pose the actions are offsets from; duck-sounds carries a whole file
    /// whose reason for existing is that ignoring it lied to a community policy
    /// by nineteen degrees on the head. So the base file's own account of
    /// itself is carried forward, and this is where that is held.
    func testTheBaseFilesOwnMetadataIsCarriedForward() throws {
        let baseBytes = try realBytes()
        let inherited = DuckTuner.metadata(of: baseBytes)
        XCTAssertTrue(inherited.keys.contains("default_joint_pos"),
                      "the fixture has to carry the key this test is about")

        let export = try DuckTuner.export(
            baseFile: baseBytes, basePolicy: "alpha_walking.onnx", declaredActionScale: nil,
            vector: .identity, schedule: .onAPhone, seed: 3, bench: "This iPhone",
            measuredTerms: everyTerm, travelled: 1.2, elapsed: 300)
        let out = DuckTuner.metadata(of: export.onnx)
        for (key, value) in inherited where key != "producer" {
            XCTAssertEqual(out[key], value, "\(key) was dropped on the way through the fold")
        }
        // AND OURS WINS WHERE THEY MEET, which is only `producer`.
        XCTAssertEqual(out["producer"], "Microduck Studio")
        XCTAssertEqual(out["microduck_studio.kind"], "tuned")
        XCTAssertTrue(
            out["microduck_studio.inherited_keys"]?.contains("default_joint_pos") == true,
            "and the file says what it inherited, so a reader can tell carried from written")
    }

    /// THE FILE'S OWN `action_scale` IS A SOURCE, AND A MANIFEST OUTRANKS IT.
    /// Pollen's networks declare 1.0 in their metadata; a manifest is what the
    /// person sharing a policy wrote down for a reader, so it wins. There is no
    /// third fallback: when neither exists the key is omitted.
    func testTheActionScaleComesFromTheManifestThenTheFileAndThenNowhere() throws {
        let baseBytes = try realBytes()
        XCTAssertEqual(DuckTuner.metadata(of: baseBytes)["action_scale"], "1.0",
                       "the fixture declares one, which is what makes this test possible")

        let fromFile = try DuckTuner.export(
            baseFile: baseBytes, basePolicy: "alpha_walking.onnx", declaredActionScale: nil,
            vector: .identity, schedule: .onAPhone, seed: 1, bench: "b",
            measuredTerms: everyTerm, travelled: 1, elapsed: 1)
        XCTAssertEqual(try PolicyManifest.decode(fromFile.manifest).actionScale, 1.0)

        let fromManifest = try DuckTuner.export(
            baseFile: baseBytes, basePolicy: "alpha_walking.onnx", declaredActionScale: 0.85,
            vector: .identity, schedule: .onAPhone, seed: 1, bench: "b",
            measuredTerms: everyTerm, travelled: 1, elapsed: 1)
        XCTAssertEqual(try PolicyManifest.decode(fromManifest.manifest).actionScale, 0.85,
                       "a manifest outranks the file")
    }

    /// THE CHECK THAT THE METADATA READER CAN FAIL. A reader that returned an
    /// empty dictionary for everything would pass every assertion above.
    func testAPolicyWithNoMetadataReadsAsNone() throws {
        let bare = try DuckPolicyWriter.encoded(
            mean: try realPolicy().parameters.mean,
            std: try realPolicy().parameters.std,
            layers: try realPolicy().parameters.layers)
        XCTAssertTrue(DuckTuner.metadata(of: bare).isEmpty,
                      "duckkit's writer emits no metadata_props, so there is none to find")
    }

    func testTheManifestDecodesAndIsRunnableHere() throws {
        let baseBytes = try realBytes()
        var gain = DuckTuner.TuningVector.identity.gain
        gain[1] = 0.95
        let export = try DuckTuner.export(
            baseFile: baseBytes, basePolicy: "alpha_walking.onnx", declaredActionScale: 1.0,
            vector: try .checked(gain: gain, offset: DuckTuner.TuningVector.identity.offset),
            schedule: .onAPhone, seed: 1, bench: "This iPhone",
            measuredTerms: everyTerm, travelled: 1.0, elapsed: 200)

        let manifest = try PolicyManifest.decode(export.manifest)
        XCTAssertTrue(manifest.isRunnableHere,
                      "a manifest this app writes must pass this app's own compatibility check")
        XCTAssertEqual(manifest.observationLength, DuckObservation.length)
        XCTAssertEqual(manifest.actionLength, DuckModel.policyJointCount)
        XCTAssertEqual(manifest.controlHz, DuckModel.tickHz)
        XCTAssertEqual(manifest.actionScale, 1.0, "carried through from the base, not invented")
        XCTAssertTrue(manifest.cautions.contains(DuckTuner.neverOnHardware))
        XCTAssertTrue(manifest.cautions.contains(DuckTuner.notTraining))
        XCTAssertTrue(manifest.cautions.contains(DuckTuner.actionScaleIsNotFolded))
    }

    /// THE MANIFEST'S `base_fingerprint` IS THE BASE'S, AND SAYING SO OUT LOUD
    /// IS WORTH A TEST BECAUSE THE FIRST VERSION GOT IT WRONG. It read the
    /// digest off the FOLDED policy, so the file's own account of what it was
    /// made from named itself — in the one field that exists to make a result
    /// reproducible, looking entirely normal. The two digests differ by
    /// construction, which is what makes this checkable at all.
    func testTheManifestNamesWhatItWasFoldedIntoAndNotItself() throws {
        let baseBytes = try realBytes()
        var gain = DuckTuner.TuningVector.identity.gain
        gain[0] = 1.2
        let export = try DuckTuner.export(
            baseFile: baseBytes, basePolicy: "alpha_walking.onnx", declaredActionScale: nil,
            vector: try .checked(gain: gain, offset: DuckTuner.TuningVector.identity.offset),
            schedule: .onAPhone, seed: 5, bench: "b",
            measuredTerms: everyTerm, travelled: 1.0, elapsed: 100)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: export.manifest) as? [String: Any])
        let tuning = try XCTUnwrap(json["tuning"] as? [String: Any])
        XCTAssertEqual(tuning["base_fingerprint"] as? String, export.baseFingerprint)
        XCTAssertEqual(tuning["fingerprint"] as? String, export.fingerprint)
        XCTAssertNotEqual(export.baseFingerprint, export.fingerprint,
                          "and the two are genuinely different, or this proves nothing")
        XCTAssertEqual(tuning["base_policy"] as? String, "alpha_walking.onnx")
    }

    /// A RUN SCORED BY A BENCH THAT ANSWERED ALL SIX TERMS MUST NOT RECORD THE
    /// FOUR A DIFFERENT ARRANGEMENT WOULD HAVE MISSED. The first version listed
    /// `refusedByAStateLoop` in the manifest unconditionally, which told every
    /// future reader that four terms had been left out of a reward they were
    /// in. The refusals a RESULT carries are the plant's; the ones a BENCH
    /// carries belong to the screen.
    func testTheManifestRefusesOnlyWhatThePlantCannotAnswer() throws {
        let export = try DuckTuner.export(
            baseFile: try realBytes(), basePolicy: "alpha_walking.onnx",
            declaredActionScale: nil, vector: .identity, schedule: .onAPhone,
            seed: 1, bench: "b", measuredTerms: everyTerm, travelled: 1, elapsed: 1)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: export.manifest) as? [String: Any])
        let tuning = try XCTUnwrap(json["tuning"] as? [String: Any])
        let refused = try XCTUnwrap(tuning["refused"] as? [[String: String]])
            .compactMap { $0["name"] }
        XCTAssertEqual(refused, DuckTuner.refusedByThePlant.map(\.key))
        for scored in DuckTuner.terms.map(\.key) {
            XCTAssertFalse(refused.contains(scored),
                           "\(scored) was in the reward and must not be listed as refused")
        }
    }

    /// NIL IS NOT 1.0, AND A MANIFEST MUST NOT PRETEND OTHERWISE. A base policy
    /// that arrived with no manifest told this app nothing about its action
    /// scale; writing a plausible one is how a policy comes to be driven 10%
    /// short on somebody's robot.
    func testAnUnknownActionScaleIsOmittedAndSaidOutLoud() throws {
        // A BASE WITH NO METADATA AT ALL, which is what duckkit's own writer
        // produces — so this is the shape of a policy blended on this phone and
        // then tuned, not a hypothetical.
        let real = try realPolicy()
        let bare = try DuckPolicyWriter.encoded(mean: real.parameters.mean,
                                                std: real.parameters.std,
                                                layers: real.parameters.layers)
        XCTAssertTrue(DuckTuner.metadata(of: bare).isEmpty)
        let export = try DuckTuner.export(
            baseFile: bare, basePolicy: "somebody-elses.onnx", declaredActionScale: nil,
            vector: .identity, schedule: .onAPhone, seed: 1, bench: "This iPhone",
            measuredTerms: everyTerm, travelled: 1.0, elapsed: 200)
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: export.manifest) as? [String: Any])
        XCTAssertNil(json["action_scale"], "the key is absent, not defaulted")
        let manifest = try PolicyManifest.decode(export.manifest)
        XCTAssertTrue(manifest.cautions.contains { $0.contains("does not guess one") },
                      "and the omission is stated rather than left to be noticed")
        XCTAssertTrue(manifest.cautions.contains { $0.contains("neutral pose") },
                      "and so is the bigger loss: nothing declared what the actions offset from")
    }

    /// THE ROBOTD EXCERPT KEEPS `SimDuckConfig.robotdToml()`'s REFUSAL. That
    /// function declines to write `action_scale` because this app holds no
    /// value for the robot's; a fold changes nothing about that, and a tuned
    /// file arriving with a live scale key would be the same invention through
    /// a new door.
    func testTheRobotdExcerptRefusesToInventTheActionScale() {
        let excerpt = DuckTuner.robotdExcerpt(filename: "tuned-abc123.onnx",
                                              basePolicy: "alpha_walking.onnx",
                                              story: "tuned here")
        XCTAssertTrue(excerpt.contains("[policy]"))
        XCTAssertTrue(excerpt.contains("walk = \"tuned-abc123.onnx\""))
        for line in excerpt.split(separator: "\n") where line.contains("action_scale") {
            XCTAssertTrue(line.hasPrefix("#"),
                          "action_scale may be discussed and never assigned: \(line)")
        }
        XCTAssertTrue(excerpt.contains("action_scale"),
                      "and it IS discussed — silence would read as 'this does not matter'")
    }

    /// A NAME PER RUN, NOT PER BASE. Three searches against one policy produce
    /// three networks, and one filename for all of them is how the second
    /// overwrites the first on somebody's robot.
    func testTwoDifferentResidualsGetTwoDifferentFilenames() throws {
        let baseBytes = try realBytes()
        let base = try DuckPolicy.load(from: baseBytes)
        var a = DuckTuner.TuningVector.identity.gain; a[0] = 1.10
        var b = DuckTuner.TuningVector.identity.gain; b[0] = 1.11
        let zero = DuckTuner.TuningVector.identity.offset
        let first = DuckTuner.filename(
            for: try DuckTuner.TuningVector.checked(gain: a, offset: zero).folded(into: base))
        let second = DuckTuner.filename(
            for: try DuckTuner.TuningVector.checked(gain: b, offset: zero).folded(into: base))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasPrefix("tuned-") && first.hasSuffix(".onnx"))
    }

    // MARK: - the sentences

    func testTheProvenanceLineCarriesEverythingAResultNeeds() {
        let line = DuckTuner.provenance(episodes: 276, seconds: 6, bench: "This iPhone",
                                        basePolicy: "alpha_walking.onnx",
                                        baseFingerprint: "abcdef0123456789", seed: 7)
        XCTAssertTrue(line.contains("276 episodes"), "how many")
        XCTAssertTrue(line.contains("This iPhone"), "on what")
        XCTAssertTrue(line.contains("alpha_walking.onnx"), "out of what")
        XCTAssertTrue(line.contains("abcdef012345"), "identified by digest, not by filename")
        XCTAssertTrue(line.contains("seed 7"), "reproducibly")
        XCTAssertTrue(line.contains(DuckTuner.configFile), "against which reward")
        XCTAssertTrue(line.hasSuffix(DuckTuner.neverOnHardware), "and it ends where it must")
        for term in DuckTuner.terms {
            XCTAssertTrue(line.contains(term.key), "\(term.key) is named")
        }
    }

    func testNotTrainingSaysWhatItIsRatherThanOnlyWhatItIsNot() {
        XCTAssertTrue(DuckTuner.notTraining.contains("No gradient is computed here"))
        XCTAssertTrue(DuckTuner.notTraining.contains("twenty-eight numbers"))
        XCTAssertTrue(DuckTuner.notTraining.contains("The walk is still theirs."),
                      "the credit is the point of the sentence")
    }

    // MARK: - duration, measured and never promised

    func testADurationIsNotQuotedBeforeAnythingHasRun() {
        XCTAssertEqual(DuckTuner.durationSoFar(episodesDone: 0, elapsed: 0, schedule: .onAPhone),
                       DuckTuner.durationNotMeasuredYet)
        XCTAssertTrue(DuckTuner.durationNotMeasuredYet.contains("has not been measured"))
        XCTAssertTrue(DuckTuner.durationNotMeasuredYet.contains("somebody else's machine"),
                      "which is the failure this refuses to repeat")
    }

    func testTheRemainderIsCalledAnExtrapolation() {
        let line = DuckTuner.durationSoFar(episodesDone: 10, elapsed: 20, schedule: .onAPhone)
        XCTAssertTrue(line.contains("measured here"))
        XCTAssertTrue(line.contains("extrapolation"),
                      "a remainder printed as a fact is the same move as quoting a Pi's tick "
                    + "as a phone's")
        XCTAssertFalse(line.contains("will take"), "nothing here promises")
    }

    func testAFinishedRunReportsWhatItCost() {
        let line = DuckTuner.durationMeasured(episodes: 276, elapsed: 900)
        XCTAssertTrue(line.contains("276 episodes"))
        XCTAssertTrue(line.contains("15 min"))
        XCTAssertTrue(line.contains("measured"))
    }

    // MARK: - the generation line

    /// THE REWARD NEVER APPEARS WITHOUT THE DISTANCE. A generation where the
    /// reward climbed while the walk stopped is the failure this whole screen
    /// is arranged against, and a line that printed only the reward would draw
    /// it as progress.
    func testEveryGenerationLineCarriesTheDistanceBesideTheReward() {
        let line = DuckTuner.generationLine(.init(
            index: 4,
            best: .init(reward: 2.9812, travelled: 0.001, standing: 3, episodes: 3, terms: [:]),
            rejectedAsInert: 2))
        XCTAssertTrue(line.contains("2.9812"))
        XCTAssertTrue(line.contains("1 mm"), "the distance is right there beside it")
        XCTAssertTrue(line.contains("3 of 3"))
        XCTAssertTrue(line.contains("2 rejected as inert"))
    }

    /// THE FLOOR IS A SPREAD AND A SPREAD CANNOT COME OUT OF A MEAN. A bench
    /// that reports one number for a whole batch has thrown away the only thing
    /// that decides whether a gain is a gain, and the honest answer is nil —
    /// followed by a screen that withholds the verdict rather than computing
    /// one against a number nobody measured.
    func testTheNoiseFloorIsMeasuredOrRefused() throws {
        XCTAssertEqual(try XCTUnwrap(DuckTuner.noiseFloor([2.50, 2.61, 2.44, 2.58])),
                       0.17, accuracy: 1e-12)
        XCTAssertNil(DuckTuner.noiseFloor([2.50]), "one episode is not a spread")
        XCTAssertNil(DuckTuner.noiseFloor([]), "and neither is none")
        XCTAssertNil(DuckTuner.noiseFloor([2.5, .nan]))
        XCTAssertTrue(DuckTuner.noNoiseFloor.contains("one number for the whole batch"))
        XCTAssertTrue(DuckTuner.noNoiseFloor.contains("the verdict is not"),
                      "the result is kept and the verdict withheld, which is the honest pair")
    }

    func testTheHeldOutVerdictRefusesAGainUnderTheNoiseFloor() {
        let short = DuckTuner.heldOutVerdict(gain: 0.01, noiseFloor: 0.04)
        XCTAssertTrue(short.contains("did not survive"))
        XCTAssertTrue(short.contains("noise floor"))
        XCTAssertTrue(short.contains("is a real answer"),
                      "a negative result is a result, and the screen says so")
        let good = DuckTuner.heldOutVerdict(gain: 0.09, noiseFloor: 0.04)
        XCTAssertTrue(good.contains("It survived"))
        XCTAssertTrue(good.contains("bigger than the wobble"))
    }

    // MARK: - the objective keeps the walk; the guards are unconditional

    /// THE FARM THE REVIEW BUILT, REFUSED BY THE OBJECTIVE. A left/right gain
    /// asymmetry inside the envelope scored 4.1817 against the identity's
    /// 3.8863 while travelling 533 mm against 1155 mm. Scaled by the walk kept
    /// it ranks below the unchanged network, which is the whole point.
    func testTheMeasuredFarmRanksBelowTheBaselineOnTheObjective() {
        let baseline = DuckTuner.objective(reward: 3.8863, travelled: 1.155, baselineTravelled: 1.155)
        let farm = DuckTuner.objective(reward: 4.1817, travelled: 0.533, baselineTravelled: 1.155)
        XCTAssertEqual(baseline, 3.8863, accuracy: 1e-9)
        XCTAssertLessThan(farm, baseline)
        // A candidate that keeps the whole walk is scored on its reward alone,
        // and walking FURTHER than the baseline buys nothing.
        XCTAssertEqual(DuckTuner.objective(reward: 4.0, travelled: 1.4, baselineTravelled: 1.155), 4.0)
        // A circle — a negative projection onto the command — scores nothing.
        XCTAssertEqual(DuckTuner.objective(reward: 4.5, travelled: -0.074, baselineTravelled: 1.155), 0)
        // No baseline walk, no objective.
        XCTAssertEqual(DuckTuner.objective(reward: 4.5, travelled: 1, baselineTravelled: 0), 0)
    }

    /// The walk floor asks every drop, not the median, and does not care
    /// whether the candidate ended standing.
    func testTheWalkFloorIsOnTheWeakestDropAndUnconditional() {
        XCTAssertTrue(DuckTuner.keptTheWalk(minTravelled: 0.30, baselineMinTravelled: 1.134))
        XCTAssertFalse(DuckTuner.keptTheWalk(minTravelled: 0.28, baselineMinTravelled: 1.134))
        // One dead episode in three is what the median hid; the minimum sees it.
        XCTAssertFalse(DuckTuner.keptTheWalk(minTravelled: 0.002, baselineMinTravelled: 1.134))
        // A baseline that does not walk either cannot fail anyone on the walk.
        XCTAssertTrue(DuckTuner.keptTheWalk(minTravelled: 0, baselineMinTravelled: 0.001))
        XCTAssertFalse(DuckTuner.rejectedForLosingTheWalk.isEmpty)
        XCTAssertTrue(DuckTuner.rejectedForLosingTheWalk.contains("whether or not it ended standing"))
        XCTAssertTrue(DuckTuner.rejectedAsDiverged.contains("stopped being a duck"))
    }

    /// A spread of exactly zero is the absence of a floor, not a floor of zero.
    func testANoiseFloorOfExactlyZeroIsRefused() {
        XCTAssertNil(DuckTuner.noiseFloor([2.5, 2.5, 2.5]))
        XCTAssertEqual(try XCTUnwrap(DuckTuner.noiseFloor([2.5, 2.6])), 0.1, accuracy: 1e-12)
    }

    /// The held-out verdict asks about the walk before it asks about the gain.
    func testTheHeldOutVerdictThrowsOutAWinnerThatLostTheWalk() {
        let lost = DuckTuner.heldOutVerdict(gain: 0.5, noiseFloor: 0.01, walkKept: 0.46)
        XCTAssertTrue(lost.hasPrefix("It did not keep the walk"), lost)
        XCTAssertTrue(lost.contains("46% of the unchanged network's distance"), lost)
        XCTAssertFalse(lost.contains("It survived"), lost)
        let kept = DuckTuner.heldOutVerdict(gain: 0.5, noiseFloor: 0.01, walkKept: 0.98)
        XCTAssertTrue(kept.hasPrefix("It survived"), kept)
    }

    /// The not-yet no longer claims the endpoint is the whole fix, and the
    /// companion sentence says what still holds the line.
    func testTheNotYetNoLongerCallsTheEndpointTheWholeFix() {
        XCTAssertFalse(DuckTuner.notYet.contains("The fix is one endpoint"), DuckTuner.notYet)
        XCTAssertTrue(DuckTuner.notYet.contains("Part of the fix is one endpoint"), DuckTuner.notYet)
        XCTAssertTrue(DuckTuner.whatTuneChanges.contains("by 35% here, measured"))
        XCTAssertTrue(DuckTuner.whatTuneChanges.contains("scaled by how much of the walk it kept"))
        XCTAssertTrue(DuckTuner.whatTuneChanges.contains("three quarters of the walk"))
    }

    /// A score without the new fields keeps the old meaning: the minimum is
    /// the median and nothing diverged.
    func testAScoreDefaultsItsWeakestDropToTheMedian() {
        let score = DuckTuner.Score(reward: 3, travelled: 1.1, standing: 3, episodes: 3, terms: [:])
        XCTAssertEqual(score.minTravelled, 1.1)
        XCTAssertEqual(score.diverged, 0)
        XCTAssertEqual(score.objective(baselineTravelled: 2.2), 1.5, accuracy: 1e-12)
    }
}
