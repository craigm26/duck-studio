import XCTest
@testable import StudioKit

/// The thing being evaluated, and the spec strip that has to travel with it.
final class EvalPolicyTests: XCTestCase {

    private let digest = "27b1f53d1f26aa9c4b7e0d1a5f83c2e6d4907b1c3e8f5a2d6b0c9e7f4a1d8b35"

    private func policy(identity: PolicyLibrary.Identity? = nil,
                        residualIsIdentity: Bool = true) -> EvalPolicy {
        EvalPolicy(kind: .libraryNetwork, title: "Pollen's walking network",
                   identity: identity ?? .parameters(digest),
                   benchPolicyName: "alpha_walking.onnx",
                   residualIsIdentity: residualIsIdentity)
    }

    private func embodiment() throws -> EvalEmbodiment {
        let health = try DuckBench.readHealth(Data(#"""
        {"bench":"duck-bench/5","plant":"scene.mjb","plantName":"scene.mjb",
         "plantDigest":"3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec78d80dca242547be",
         "tickHz":50,"cores":4,"policies":[],"trains":false}
        """#.utf8))
        return try EvalEmbodiment.checked(body: .networkBench, health: health,
                                          address: "100.122.199.6:8770",
                                          answeredRoutes: ["/tune"])
    }

    // MARK: - the name in the log

    /// Two files can carry one filename and be two networks, and a reader
    /// comparing two logs by `eval.policy` would never find out.
    func testTheLogNameCarriesTheDigest() {
        XCTAssertEqual(policy().logName, "alpha_walking.onnx@27b1f53d1f26")
    }

    func testAPolicyWithNoIdentityIsNamedByTheBenchsOwnName() {
        let move = EvalPolicy(kind: .authoredMotion, title: "Vault",
                              identity: nil, benchPolicyName: "vault",
                              residualIsIdentity: true)
        XCTAssertEqual(move.logName, "vault")
        XCTAssertFalse(move.isNetworkIdentity)
    }

    func testAFileOnlyDigestIsNotANetworkIdentity() {
        XCTAssertFalse(policy(identity: .fileOnly(digest)).isNetworkIdentity)
        XCTAssertTrue(policy(identity: .parameters(digest)).isNetworkIdentity)
    }

    // MARK: - the spec strip

    func testTheSpecStripHasTheElevenKeysTheirViewerRenders() throws {
        let config = policy().config(embodiment: try embodiment(),
                                     epochs: try EvalEpochs.drops(EvalTask.walkDrops,
                                                                  reducer: .median),
                                     criterion: "ends standing: something the bench said",
                                     tracing: true)
        XCTAssertEqual(Set(config.keys),
                       ["action_horizon", "bench_host", "bench_world", "criterion",
                        "epoch_axis", "replan_interval", "residual", "seed_note",
                        "step_counts", "temperature", "trace_note"])
    }

    /// Three of the eleven are their own `PolicyConfig` fields, so a log from
    /// this app has the shape their reference log has. `action_horizon: 1` is
    /// literally true: the bench asks the network for an action every tick.
    func testTheirThreeOwnFieldsAreTheirThreeOwnFields() throws {
        let config = policy().config(embodiment: try embodiment(),
                                     epochs: .single(reducer: .mean), criterion: "x",
                                     tracing: false)
        XCTAssertEqual(config["action_horizon"], .integer(1))
        XCTAssertEqual(config["replan_interval"], .null)
        XCTAssertEqual(config["temperature"], .null)
    }

    /// L4. `eval.seed` is invisible in their report when it is null, so the
    /// explanation goes where their report does render it.
    ///
    /// AND IT IS THE AXIS'S OWN SENTENCE. The note used to be the walk's
    /// wording whatever the run was, so a grid log carried "what varies between
    /// the epochs of a scene is the height the duck is dropped from" two keys
    /// away from an `epoch_axis` saying the grid is the axis and no drop height
    /// anywhere in the file.
    func testTheSeedExplanationIsTheOneThisAxisEarns() throws {
        let bench = try embodiment()
        let grid = policy().config(embodiment: bench, epochs: .single(reducer: .mean),
                                   criterion: "x", tracing: false)
        XCTAssertEqual(grid["seed_note"], .string(EvalEpochs.noSeedOnAGridSaid))
        let walk = policy().config(embodiment: bench,
                                   epochs: try EvalEpochs.drops(EvalTask.walkDrops,
                                                                reducer: .median),
                                   criterion: "x", tracing: true)
        XCTAssertEqual(walk["seed_note"], .string(EvalEpochs.noSeedSaid))
    }

    /// A route that records nothing says so, in both keys that describe a
    /// recording. A grid trial is scored by the harness and answers with no
    /// ticks at all, so `traced` is false on every trial and `total_steps` is
    /// zero: a log claiming a trajectory was returned and a verdict offered on
    /// it would be describing a mechanism the run never used.
    func testARouteThatRecordsNothingSaysSoInBothKeys() throws {
        let bench = try embodiment()
        let grid = policy().config(embodiment: bench, epochs: .single(reducer: .mean),
                                   criterion: "x", tracing: false)
        XCTAssertEqual(grid["trace_note"], .string(EvalTrace.noTraceOnAGridSaid))
        XCTAssertEqual(grid["step_counts"], .string(EvalRun.noStepsOnAGridSaid))
        let walk = policy().config(embodiment: bench,
                                   epochs: try EvalEpochs.drops(EvalTask.walkDrops,
                                                                reducer: .median),
                                   criterion: "x", tracing: true)
        XCTAssertEqual(walk["trace_note"], .string(EvalTrace.firstDropOnlySaid))
        XCTAssertEqual(walk["step_counts"], .string(EvalRun.stepCountsSaid))
    }

    /// L3. The machine that ran it, in the words this app already owns.
    func testTheHostAndTheWorldAreTheSentencesThisAppAlreadyHas() throws {
        let bench = try embodiment()
        let config = policy().config(embodiment: bench, epochs: .single(reducer: .mean),
                                     criterion: "x", tracing: false)
        XCTAssertEqual(config["bench_host"], .string(PhoneBenchReport.ranOn(nil)))
        XCTAssertEqual(config["bench_world"], .string(bench.plantSaid))
    }

    /// THE CRITERION IS CARRIED VERBATIM, EM DASHES AND ALL. It is the bench's
    /// own account of what standing means, and paraphrasing a measurement is
    /// how a placeholder gets shipped.
    func testTheCriterionIsCarriedExactlyAsTheBenchSaidIt() throws {
        let said = "ends standing: at the last tick the trunk's own up is still up \u{2014} "
                 + "gravity projects past \u{2212}0.5 into the body's \u{2212}z."
        let config = policy().config(embodiment: try embodiment(),
                                     epochs: .single(reducer: .mean), criterion: said,
                                     tracing: false)
        XCTAssertEqual(config["criterion"], .string(said))
    }

    func testAFileOnlyPolicyGetsTheExtraNoteAndANetworkOneDoesNot() throws {
        let bench = try embodiment()
        let epochs = EvalEpochs.single(reducer: .mean)
        XCTAssertNil(policy().config(embodiment: bench, epochs: epochs, criterion: "x",
                                     tracing: false)["identity_note"])
        XCTAssertEqual(policy(identity: .fileOnly(digest))
            .config(embodiment: bench, epochs: epochs, criterion: "x",
                    tracing: false)["identity_note"],
                       .string(EvalPolicy.fileOnlySaid))
    }

    func testARefusedTermIsNamedWithTheBenchsReason() throws {
        let config = policy().config(embodiment: try embodiment(),
                                     epochs: .single(reducer: .mean), criterion: "x",
                                     tracing: false,
                                     refusedTerms: [("feet_air_time", "this bench knows no "
                                                                   + "reward term by that name")])
        XCTAssertEqual(config["refused_terms"]?.stringValue,
                       "feet_air_time: this bench knows no reward term by that name")
    }

    func testTheResidualSaysWhetherTheNetworkWasChanged() throws {
        let bench = try embodiment()
        let epochs = EvalEpochs.single(reducer: .mean)
        XCTAssertEqual(policy().config(embodiment: bench, epochs: epochs,
                                       criterion: "x", tracing: false)["residual"],
                       .string(EvalPolicy.identityResidualSaid))
        XCTAssertEqual(policy(residualIsIdentity: false)
            .config(embodiment: bench, epochs: epochs, criterion: "x",
                    tracing: false)["residual"],
                       .string(EvalPolicy.foldedResidualSaid))
    }

    /// A CANDIDATE'S FILE IS ALREADY A FOLD. The tuner and the weight search
    /// save their winner by folding a per joint gain and trim into the last
    /// layer, so a run of one of those with an identity residual has folded
    /// nothing in today and is still not running the network as it was trained.
    /// The log said "so the network the bench ran is the network as it was
    /// trained" about exactly that file, and nothing else in the log recorded
    /// that the file was a fold at all.
    func testACandidateIsNotDescribedAsTheNetworkItWasTrainedAs() throws {
        let bench = try embodiment()
        let epochs = EvalEpochs.single(reducer: .mean)
        let candidate = EvalPolicy(kind: .tunedCandidate, title: "A candidate from a search",
                                   identity: .parameters(digest),
                                   benchPolicyName: "alpha_walking_tuned.onnx",
                                   residualIsIdentity: true)
        let said = candidate.config(embodiment: bench, epochs: epochs, criterion: "x",
                                    tracing: true)["residual"]
        XCTAssertEqual(said, .string(EvalPolicy.identityOverACandidateSaid))
        XCTAssertFalse(EvalPolicy.identityOverACandidateSaid
            .contains("is the network as it was trained"))
        XCTAssertTrue(EvalPolicy.identityOverACandidateSaid.hasPrefix("Identity."))
        // A candidate the bench folded for THIS run says the folded sentence,
        // the way any other policy does.
        let folded = EvalPolicy(kind: .tunedCandidate, title: "A candidate from a search",
                                identity: .parameters(digest),
                                benchPolicyName: "alpha_walking_tuned.onnx",
                                residualIsIdentity: false)
        XCTAssertEqual(folded.residualSaid, EvalPolicy.foldedResidualSaid)
        // And a library network is still described as what it is.
        XCTAssertEqual(policy().residualSaid, EvalPolicy.identityResidualSaid)
    }

    /// A2: the digest a person is looking at on the policy row is the
    /// network's, and the sentence beside it has to be about the network. The
    /// row borrowed the embodiment's sentence, which is about the world's
    /// sha256, so VoiceOver read out a paragraph about the plant instead of the
    /// identity of the thing being evaluated.
    func testThePolicyHasItsOwnDigestSentenceAndItsOwnSpokenName() {
        XCTAssertNotEqual(EvalPolicy.digestIsIdentitySaid, EvalEmbodiment.digestIsIdentitySaid)
        XCTAssertTrue(EvalPolicy.digestIsIdentitySaid.contains("network's parameters"))
        XCTAssertFalse(EvalPolicy.digestIsIdentitySaid.contains("world"))
        XCTAssertEqual(policy().spokenLogName, "alpha_walking.onnx, digest 27b1f53d1f26")
        XCTAssertEqual(policy().logName, "alpha_walking.onnx@27b1f53d1f26")
        let move = EvalPolicy(kind: .authoredMotion, title: "Vault", identity: nil,
                              benchPolicyName: "vault", residualIsIdentity: true)
        XCTAssertEqual(move.spokenLogName, "vault")
    }

    /// Nothing app specific may collide with one of their schema keys, because
    /// their reader builds a frozen dataclass by keyword and refuses the rest.
    func testTheSpecStripCarriesNoneOfTheirOwnSchemaKeys() throws {
        let config = policy().config(embodiment: try embodiment(),
                                     epochs: .single(reducer: .mean), criterion: "x",
                                     tracing: false,
                                     refusedTerms: [("a", "b")])
        for key in EvalLog.Key.all {
            XCTAssertNil(config[key], "\(key) is one of their schema keys")
        }
    }
}
