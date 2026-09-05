import XCTest
@testable import StudioKit

/// The body, the world, and the digest that is part of the name rather than a
/// note beside it.
final class EvalEmbodimentTests: XCTestCase {

    private func health(digest: String? = "3f8c9ab9b409ba74c73c30179d5f7c12b025f631693f9eec7"
                                        + "8d80dca242547be",
                        name: String? = "scene.mjb",
                        bench: String = "duck-bench/5") throws -> DuckBench.Health {
        var body = "{\"bench\":\"\(bench)\",\"plant\":\"scene.mjb\",\"tickHz\":50,"
                 + "\"cores\":4,\"policies\":[],\"trains\":false"
        if let name { body += ",\"plantName\":\"\(name)\"" }
        if let digest { body += ",\"plantDigest\":\"\(digest)\"" }
        body += "}"
        return try DuckBench.readHealth(Data(body.utf8))
    }

    private func bench(routes: Set<String> = ["/health", "/reset", "/tune"]) throws
        -> EvalEmbodiment {
        try EvalEmbodiment.checked(body: .networkBench, health: try health(),
                                   address: "100.122.199.6:8770", answeredRoutes: routes)
    }

    // MARK: - identity

    /// L2. The digest is INSIDE the string two logs are compared by, so two
    /// runs against two different worlds cannot read as one on their report or
    /// on ours.
    func testTheIdentityCarriesTheMachineTheBenchAndTheWorldDigest() throws {
        XCTAssertEqual(try bench().identity,
                       "network-bench/duck-bench-5/scene.mjb@3f8c9ab9b409")
    }

    /// L3. The host word is in the identity, because a phone bench number and a
    /// desk bench number are not the same trajectory.
    func testThePhoneBenchAndTheDeskBenchDoNotShareAnIdentity() throws {
        let desk = try bench()
        let phone = try EvalEmbodiment.checked(body: .thisPhoneBench, health: try health(),
                                               address: "127.0.0.1:8770",
                                               answeredRoutes: ["/health"])
        XCTAssertNotEqual(desk.identity, phone.identity)
        XCTAssertTrue(phone.identity.hasPrefix("this-phone-bench/"))
    }

    /// A bench that will not name its world is refused before anything runs,
    /// because a run that gets as far as a log has already spent the minutes.
    func testABenchThatWillNotNameItsWorldIsRefused() throws {
        XCTAssertThrowsError(try EvalEmbodiment.checked(
            body: .networkBench, health: try health(digest: nil),
            address: nil, answeredRoutes: [])) { error in
            XCTAssertEqual(error as? EvalEmbodiment.Refusal, .noDigest)
        }
        XCTAssertThrowsError(try EvalEmbodiment.checked(
            body: .networkBench, health: try health(name: nil),
            address: nil, answeredRoutes: [])) { error in
            XCTAssertEqual(error as? EvalEmbodiment.Refusal, .noDigest)
        }
    }

    /// L6. A real Microduck is a row that says why rather than a row that runs,
    /// and there is no way to build a usable one.
    func testARealMicroduckIsAlwaysUnusableAndAlwaysSaysWhy() {
        XCTAssertFalse(EvalEmbodiment.realMicroduck.isUsable)
        XCTAssertEqual(EvalEmbodiment.realMicroduck.refusal,
                       EvalEmbodiment.realMicroduckRefusal)
        XCTAssertThrowsError(try EvalEmbodiment.checked(
            body: .realMicroduck,
            health: try health(), address: nil, answeredRoutes: [])) { error in
            XCTAssertEqual(error as? EvalEmbodiment.Refusal, .realMicroduck)
        }
    }

    // MARK: - capabilities

    /// L4 and V11. Five of their six words, and never the sixth.
    func testSeedableIsNeverClaimed() throws {
        for traced in [true, false] {
            XCTAssertFalse(try bench().capabilities(traced: traced).contains("seedable"))
        }
    }

    func testTheCapabilitiesAreOnlyWordsTheirVocabularyHas() throws {
        let theirs: Set<String> = ["seedable", "resettable", "auto_reset", "privileged_success",
                                   "renderable", "self_paced"]
        for traced in [true, false] {
            for word in try bench().capabilities(traced: traced) {
                XCTAssertTrue(theirs.contains(word), "\(word) is not one of their six")
            }
        }
    }

    /// `renderable` is a fact about the run and not about the bench: a run that
    /// got no trace is a run nothing could be rendered from.
    func testRenderableIsClaimedOnlyWhenATraceCameBack() throws {
        XCTAssertTrue(try bench().capabilities(traced: true).contains("renderable"))
        XCTAssertFalse(try bench().capabilities(traced: false).contains("renderable"))
    }

    func testResettableIsClaimedOnlyWhenTheBenchAnswersThatRoute() throws {
        XCTAssertTrue(try bench(routes: ["/reset"]).capabilities(traced: false)
            .contains("resettable"))
        XCTAssertFalse(try bench(routes: ["/tune"]).capabilities(traced: false)
            .contains("resettable"))
    }

    func testCapabilitiesComeOutSortedSoTheLogIsStable() throws {
        let words = try bench().capabilities(traced: true)
        XCTAssertEqual(words, words.sorted())
        XCTAssertEqual(words, ["auto_reset", "privileged_success", "renderable", "resettable",
                               "self_paced"])
    }

    // MARK: - embodiment_info

    func testTheInfoBlockCarriesTheWholeDigestAndTheControlRate() throws {
        let info = try bench().info(traced: true)
        XCTAssertEqual(info["plant_sha256"]?.stringValue?.count, 64)
        XCTAssertEqual(info["control_hz"], .double(50))
        XCTAssertEqual(info["is_simulated"], .bool(true))
        XCTAssertEqual(info["bench"], .string("duck-bench/5"))
        XCTAssertEqual(info["bench_address"], .string("100.122.199.6:8770"))
        XCTAssertEqual(info["plant_name"], .string("scene.mjb"))
    }

    /// Their `_video.default_fps` is the only reader of this block, so nothing
    /// a person needs may live here.
    func testTheInfoBlockCarriesNoneOfTheirOwnSchemaKeys() throws {
        let info = try bench().info(traced: true)
        for key in EvalLog.Key.all {
            XCTAssertNil(info[key], "\(key) is one of their schema keys")
        }
    }

    // MARK: - before Start

    func testEverythingThatBlocksAStartIsAnsweredInOnePlace() throws {
        let good = try bench()
        XCTAssertNil(good.refusalBeforeStart(route: "/tune", policyIsNetworkIdentity: true,
                                             policyName: "alpha_walking.onnx",
                                             bundledPolicyNames: []))
        XCTAssertEqual(good.refusalBeforeStart(route: "/climb", policyIsNetworkIdentity: true,
                                               policyName: "alpha_walking.onnx",
                                               bundledPolicyNames: []),
                       "This bench does not answer /climb, so it cannot run this task.")
        XCTAssertEqual(good.refusalBeforeStart(route: "/tune", policyIsNetworkIdentity: false,
                                               policyName: "broken.onnx",
                                               bundledPolicyNames: []),
                       EvalPolicy.canonicalParametersSaid)
        XCTAssertEqual(EvalEmbodiment.realMicroduck.refusalBeforeStart(
            route: "/tune", policyIsNetworkIdentity: true, policyName: "alpha_walking.onnx",
            bundledPolicyNames: []), EvalEmbodiment.realMicroduckRefusal)
    }

    /// B7. The phone bench runs canonical parameter bytes and cannot take an
    /// ONNX, so it can only ever score the networks that ship with the app. A
    /// setup screen that offered it for anything else would dead end on the
    /// bench's own error after the tap.
    func testThePhoneBenchOnlyOffersTheNetworksItShipsWith() throws {
        let phone = try EvalEmbodiment.checked(body: .thisPhoneBench, health: try health(),
                                               address: "127.0.0.1:8770",
                                               answeredRoutes: ["/tune"])
        XCTAssertEqual(phone.refusalBeforeStart(route: "/tune", policyIsNetworkIdentity: true,
                                                policyName: "somebody-elses.onnx",
                                                bundledPolicyNames: ["alpha_walking.onnx"]),
                       EvalEmbodiment.phoneBenchOnlyBundled)
        XCTAssertNil(phone.refusalBeforeStart(route: "/tune", policyIsNetworkIdentity: true,
                                              policyName: "alpha_walking.onnx",
                                              bundledPolicyNames: ["alpha_walking.onnx"]))
    }

    // MARK: - the sentences this app already owns

    func testTheWorldSentenceIsTheOneThisAppAlreadyHas() throws {
        XCTAssertEqual(try bench().plantSaid,
                       DuckBench.plantSaid(name: "scene.mjb",
                                           digest: "3f8c9ab9b409ba74c73c30179d5f7c12b025f6316"
                                                 + "93f9eec78d80dca242547be"))
    }

    func testTheHostSentenceIsTheOneThisAppAlreadyHas() throws {
        XCTAssertEqual(try bench().hostSaid, PhoneBenchReport.ranOn(nil))
    }
}
