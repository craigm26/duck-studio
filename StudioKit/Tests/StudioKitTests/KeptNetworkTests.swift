import XCTest
import DuckKit
@testable import StudioKit

/// A kept network's manifest is Pollen's format, reads back through this
/// app's own reader, and carries the making of it where an older reader
/// cannot trip over it.
final class KeptNetworkTests: XCTestCase {

    private let search = KeptNetwork.Search(
        baseTitle: "alpha_walking", baseIdentity: String(repeating: "ab", count: 32),
        generations: 8, pairs: 10, step: 0.05, gained: 1.018, keptElsewhere: 0.86,
        plantName: "scene_physics", plantDigest: "3f8c9ab9", build: "62")

    func testASearchedManifestReadsBackThroughTheAppsOwnReader() throws {
        let data = try KeptNetwork.manifest(for: search, named: "alpha_walking, searched")
        let manifest = try PolicyManifest.decode(data)
        XCTAssertEqual(manifest.name, "alpha_walking, searched")
        XCTAssertEqual(manifest.observationLength, DuckObservation.length)
        XCTAssertEqual(manifest.actionLength, DuckModel.policyJointCount)
        XCTAssertEqual(manifest.authorCautions, [KeptNetwork.searchedCaution])
        XCTAssertTrue(manifest.summary?.contains("8 generations of 10 pairs") == true, manifest.summary ?? "")
        XCTAssertTrue(manifest.summary?.contains("1.8% further") == true, manifest.summary ?? "")
        XCTAssertTrue(manifest.summary?.contains("86% kept") == true, manifest.summary ?? "")
        XCTAssertTrue(manifest.incompatibilities.isEmpty, "a manifest this app wrote must run here")
    }

    func testTheMakingOfItIsUnderOneAdditiveKey() throws {
        let data = try KeptNetwork.manifest(for: search, named: "x")
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let made = try XCTUnwrap(top["made_here"] as? [String: Any])
        XCTAssertEqual(made["how"] as? String, "weight search")
        XCTAssertEqual(made["base_sha256"] as? String, search.baseIdentity)
        XCTAssertEqual(made["generations"] as? Int, 8)
        XCTAssertEqual(made["bench_plant"] as? String, "scene_physics")
        XCTAssertEqual(made["bench_plant_sha256"] as? String, "3f8c9ab9")
        XCTAssertEqual(made["build"] as? String, "62")
        // OMITTED, NOT DEFAULTED: no scale is claimed for a searched network.
        XCTAssertNil(top["action_scale"])
    }

    func testAPlantTheBenchDidNotNameIsAbsentRatherThanBlank() throws {
        let unnamed = KeptNetwork.Search(
            baseTitle: "b", baseIdentity: "id", generations: 1, pairs: 3, step: 0.05,
            gained: 1, keptElsewhere: 1, plantName: nil, plantDigest: nil, build: "1")
        let top = try XCTUnwrap(JSONSerialization.jsonObject(
            with: try KeptNetwork.manifest(for: unnamed, named: "b")) as? [String: Any])
        let made = try XCTUnwrap(top["made_here"] as? [String: Any])
        XCTAssertNil(made["bench_plant"])
        XCTAssertNil(made["bench_plant_sha256"])
    }

    func testATunedManifestCarriesTheTunersOwnThreeSentences() throws {
        let tune = KeptNetwork.Tune(baseTitle: "alpha_walking", verdict: "It walked further.",
                                    residual: "gain 1.02, trim 0.01", provenance: "seed 7",
                                    build: "62")
        let data = try KeptNetwork.manifest(for: tune, named: "alpha_walking, tuned")
        let manifest = try PolicyManifest.decode(data)
        XCTAssertEqual(manifest.authorCautions, [KeptNetwork.tunedCaution])
        XCTAssertTrue(manifest.summary?.hasPrefix("Tuned from alpha_walking.") == true)
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let made = try XCTUnwrap(top["made_here"] as? [String: Any])
        XCTAssertEqual(made["how"] as? String, "tune")
        XCTAssertEqual(made["residual"] as? String, "gain 1.02, trim 0.01")
    }

    func testANameIsRequiredAndTheTitleCarriesTheBaseAndTheClock() {
        XCTAssertThrowsError(try KeptNetwork.manifest(for: search, named: "  "))
        let when = Date(timeIntervalSince1970: 0)
        let title = KeptNetwork.title(from: "alpha_walking", how: "searched", at: when)
        XCTAssertTrue(title.hasPrefix("alpha_walking, searched "), title)
        XCTAssertTrue(KeptNetwork.keptSaid(title).contains(title))
    }

    func testTheButtonsSayKeepFirstAndShareSecond() {
        XCTAssertEqual(KeptNetwork.keepTheTunedSaid, "Keep the tuned policy")
        XCTAssertEqual(KeptNetwork.shareTheFileSaid, "Share the file")
        XCTAssertEqual(WeightSearch.keepThisNetworkSaid, "Keep this network")
    }

    func testTheTwoCautionsAreDifferentClaimsAndNeitherHedges() {
        XCTAssertNotEqual(KeptNetwork.searchedCaution, KeptNetwork.tunedCaution)
        for line in [KeptNetwork.searchedCaution, KeptNetwork.tunedCaution] {
            XCTAssertFalse(line.contains("probably"))
            XCTAssertTrue(line.contains("never run on hardware"))
        }
        XCTAssertEqual(PolicyLibrary.Origin.searched(base: "b").author, "you")
        XCTAssertTrue(PolicyLibrary.Origin.searched(base: "b").caveat?.contains("weights of b") == true)
        XCTAssertTrue(PolicyLibrary.Origin.tuned(base: "b") < PolicyLibrary.Origin.searched(base: "a"),
                      "a searched network shelves after a tuned one, which is also newest")
    }
}
