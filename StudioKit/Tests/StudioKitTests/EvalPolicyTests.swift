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
                                     criterion: "ends standing: something the bench said")
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
                                     epochs: .single(reducer: .mean), criterion: "x")
        XCTAssertEqual(config["action_horizon"], .integer(1))
        XCTAssertEqual(config["replan_interval"], .null)
        XCTAssertEqual(config["temperature"], .null)
    }

    /// L4. `eval.seed` is invisible in their report when it is null, so the
    /// explanation goes where their report does render it.
    func testTheSeedExplanationIsInTheBlockTheirViewerRenders() throws {
        let config = policy().config(embodiment: try embodiment(),
                                     epochs: .single(reducer: .mean), criterion: "x")
        XCTAssertEqual(config["seed_note"], .string(EvalEpochs.noSeedSaid))
    }

    /// L3. The machine that ran it, in the words this app already owns.
    func testTheHostAndTheWorldAreTheSentencesThisAppAlreadyHas() throws {
        let bench = try embodiment()
        let config = policy().config(embodiment: bench, epochs: .single(reducer: .mean),
                                     criterion: "x")
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
                                     epochs: .single(reducer: .mean), criterion: said)
        XCTAssertEqual(config["criterion"], .string(said))
    }

    func testAFileOnlyPolicyGetsTheExtraNoteAndANetworkOneDoesNot() throws {
        let bench = try embodiment()
        let epochs = EvalEpochs.single(reducer: .mean)
        XCTAssertNil(policy().config(embodiment: bench, epochs: epochs,
                                     criterion: "x")["identity_note"])
        XCTAssertEqual(policy(identity: .fileOnly(digest))
            .config(embodiment: bench, epochs: epochs, criterion: "x")["identity_note"],
                       .string(EvalPolicy.fileOnlySaid))
    }

    func testARefusedTermIsNamedWithTheBenchsReason() throws {
        let config = policy().config(embodiment: try embodiment(),
                                     epochs: .single(reducer: .mean), criterion: "x",
                                     refusedTerms: [("feet_air_time", "this bench knows no "
                                                                   + "reward term by that name")])
        XCTAssertEqual(config["refused_terms"]?.stringValue,
                       "feet_air_time: this bench knows no reward term by that name")
    }

    func testTheResidualSaysWhetherTheNetworkWasChanged() throws {
        let bench = try embodiment()
        let epochs = EvalEpochs.single(reducer: .mean)
        XCTAssertEqual(policy().config(embodiment: bench, epochs: epochs,
                                       criterion: "x")["residual"],
                       .string(EvalPolicy.identityResidualSaid))
        XCTAssertEqual(policy(residualIsIdentity: false)
            .config(embodiment: bench, epochs: epochs, criterion: "x")["residual"],
                       .string(EvalPolicy.foldedResidualSaid))
    }

    /// Nothing app specific may collide with one of their schema keys, because
    /// their reader builds a frozen dataclass by keyword and refuses the rest.
    func testTheSpecStripCarriesNoneOfTheirOwnSchemaKeys() throws {
        let config = policy().config(embodiment: try embodiment(),
                                     epochs: .single(reducer: .mean), criterion: "x",
                                     refusedTerms: [("a", "b")])
        for key in EvalLog.Key.all {
            XCTAssertNil(config[key], "\(key) is one of their schema keys")
        }
    }
}
