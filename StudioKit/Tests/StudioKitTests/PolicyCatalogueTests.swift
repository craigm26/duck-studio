import XCTest
import DuckEvidence
@testable import StudioKit

/// Parsed against responses captured from the real repositories, not against
/// JSON written to match the parser.
final class PolicyCatalogueTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)",
                                                  withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testItListsThePoliciesFolderAndNothingElse() throws {
        let entries = try PolicyCatalogue.parse(fixture("microduck-tree"),
                                                source: PolicyCatalogue.officialPolicies,
                                                extensions: ["onnx"])
        XCTAssertEqual(entries.count, 9, "the repository publishes nine")
        XCTAssertTrue(entries.allSatisfy { $0.path.hasPrefix("policies/") })
        // duck-detect and pet-detect are .onnx and are not policies. A scan
        // that swept the whole repository would offer a vision model as a gait.
        XCTAssertFalse(entries.contains { $0.filename.contains("detect") })
        XCTAssertTrue(entries.allSatisfy { $0.bytes > 0 })
    }

    /// The point of the whole type: upstream names are NOT this app's names.
    func testUpstreamNamesTwoOfThemDifferently() throws {
        let entries = try PolicyCatalogue.parse(fixture("microduck-tree"),
                                                source: PolicyCatalogue.officialPolicies,
                                                extensions: ["onnx"])
        let names = Set(entries.map(\.filename))
        XCTAssertTrue(names.contains("alpha_stand.onnx"))
        XCTAssertTrue(names.contains("roller.onnx"))
        // …while this app carries the same two under BEST_ names.
        let bundled = Set(DuckOfficialPolicies.releases.map(\.filename))
        XCTAssertTrue(bundled.contains("BEST_alpha_stand.onnx"))
        XCTAssertFalse(bundled.contains("alpha_stand.onnx"))
    }

    /// So the headline must count NAMES and say that is what it counted.
    func testTheHeadlineClaimsNamesAndNeverNetworks() throws {
        let entries = try PolicyCatalogue.parse(fixture("microduck-tree"),
                                                source: PolicyCatalogue.officialPolicies,
                                                extensions: ["onnx"])
        let headline = PolicyCatalogue.headline(entries)
        XCTAssertTrue(headline.contains("names this build has not seen"), headline)
        XCTAssertFalse(headline.lowercased().contains("new polic"),
                       "a listing cannot tell whether a network is new: \(headline)")
        let unfamiliar = try XCTUnwrap(entries.first { $0.filename == "alpha_stand.onnx" })
        XCTAssertTrue(PolicyCatalogue.summary(of: unfamiliar).contains("only the weights decide"))
    }

    func testAKnownNameCarriesTheReleasePurpose() throws {
        let entries = try PolicyCatalogue.parse(fixture("microduck-tree"),
                                                source: PolicyCatalogue.officialPolicies,
                                                extensions: ["onnx"])
        let roulade = try XCTUnwrap(entries.first { $0.filename == "roulade.onnx" })
        guard case .knownName(let purpose) = PolicyCatalogue.familiarity(of: roulade) else {
            return XCTFail("roulade.onnx is in the release table")
        }
        XCTAssertTrue(purpose.contains("forward roll"))
    }

    /// The training repository is the other half of the answer: it is where
    /// every weight in the reward panel is read from.
    func testItListsTheTrainingConfigsTheRewardPanelQuotes() throws {
        let entries = try PolicyCatalogue.parse(fixture("microduck-rl-tree"),
                                                source: PolicyCatalogue.trainingConfigs,
                                                extensions: ["py"])
        let names = Set(entries.map(\.filename))
        for task in [RunMetrics.Task.velocity, .ballKick, .roulade,
                     .sitstand, .groundPick, .rollerCrouch] {
            XCTAssertTrue(names.contains(task.configFile),
                          "\(task.configFile) is quoted by the reward panel and must be listed")
        }
        // The assets tree is enormous and is not in this directory.
        XCTAssertFalse(entries.contains { $0.path.contains("/assets/") })
    }

    func testAWrongBranchIsReportedVerbatim() throws {
        let refusal = Data(#"{"message":"Not Found","status":"404"}"#.utf8)
        XCTAssertThrowsError(try PolicyCatalogue.parse(
            refusal, source: PolicyCatalogue.officialPolicies, extensions: ["onnx"])) {
            XCTAssertEqual($0 as? PolicyCatalogue.ScanError, .refused("Not Found"))
        }
    }

    func testDownloadsGoThroughTheSameChecksAsAnyOtherFetch() throws {
        let entry = PolicyCatalogue.Entry(path: "policies/alpha_walking.onnx",
                                          bytes: 793_000, blob: "abc")
        let request = try PolicyCatalogue.download(entry, from: PolicyCatalogue.officialPolicies)
        XCTAssertEqual(request.displayURL,
                       "https://raw.githubusercontent.com/pollen-robotics/microduck/main/policies/alpha_walking.onnx")
        XCTAssertEqual(request.host, "raw.githubusercontent.com")

        let huge = PolicyCatalogue.Entry(path: "policies/x.onnx",
                                         bytes: PolicySource.byteCap + 1, blob: "d")
        XCTAssertThrowsError(try PolicyCatalogue.download(huge, from: PolicyCatalogue.officialPolicies))
    }

    /// There is no upstream intent feed, and the app says why rather than
    /// scanning an address nobody publishes to.
    func testItDoesNotInventAnIntentSource() {
        XCTAssertTrue(PolicyCatalogue.sources.allSatisfy { $0.owner == "pollen-robotics" })
        XCTAssertEqual(PolicyCatalogue.sources.count, 2)
        XCTAssertTrue(PolicyCatalogue.intentsNote.contains("Pollen publish policies, not motions"))
    }
}
