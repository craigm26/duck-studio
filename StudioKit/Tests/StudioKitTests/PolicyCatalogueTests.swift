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

    /// THIS TEST USED TO ASSERT THE OPPOSITE, and the change is the point.
    ///
    /// Four of the nine were vendored here under upstream's TRAINING-RUN names
    /// — `BEST_alpha_stand.onnx`, `BEST_alpha_sitstand.onnx`, `BEST_roller.onnx`
    /// and `BEST_roller_crouch.onnx` — while `pollen-robotics/microduck` ships
    /// them under ROLE names. Their `policies/README.md` is explicit that the
    /// distinction is deliberate: "The names here are the *roles* — what
    /// `deploy/robotd.toml` asks for — not the training runs", so that swapping
    /// which run is "the walking policy" does not mean editing config on every
    /// robot. Carrying the run names meant this app named a policy something no
    /// Microduck owner would ever see on their own robot.
    ///
    /// Now they match, and this asserts that they do — including for
    /// `roller_crouch`, which upstream spells `BEST_roller_crounch.onnx` and
    /// Pollen fixed on the way through.
    func testThisAppNamesThePoliciesExactlyAsTheRobotDoes() throws {
        let entries = try PolicyCatalogue.parse(fixture("microduck-tree"),
                                                source: PolicyCatalogue.officialPolicies,
                                                extensions: ["onnx"])
        let theirs = Set(entries.map(\.filename))
        let ours = Set(DuckOfficialPolicies.releases.map(\.filename))
        XCTAssertTrue(ours.isSubset(of: theirs),
                      "we ship a name the robot does not: \(ours.subtracting(theirs).sorted())")
        for name in ["alpha_stand.onnx", "alpha_sitstand.onnx",
                     "roller.onnx", "roller_crouch.onnx"] {
            XCTAssertTrue(theirs.contains(name), "upstream lost \(name)")
            XCTAssertTrue(ours.contains(name), "we lost \(name)")
        }
        XCTAssertFalse(ours.contains { $0.hasPrefix("BEST_") },
                       "a training-run name is not a role name")
    }

    /// Nothing in Pollen's own folder is a strange name any more.
    ///
    /// THIS ASSERTED THE OPPOSITE UNTIL THE ROLE RENAME, and it was right to:
    /// four of the nine were vendored here under training-run names, so a scan
    /// of upstream's `policies/` reported four names this build had never seen
    /// and told somebody to open each one to find out whether the network was
    /// new. All four were networks the app already had. That is the confusion
    /// the rename removes, and this is where it shows.
    func testUpstreamsOwnFolderIsAllFamiliarNamesNow() throws {
        let entries = try PolicyCatalogue.parse(fixture("microduck-tree"),
                                                source: PolicyCatalogue.officialPolicies,
                                                extensions: ["onnx"])
        XCTAssertEqual(PolicyCatalogue.headline(entries),
                       "9 files, all under names this app already knows.")
    }

    /// The headline must still count NAMES and say that is what it counted —
    /// which needs a name the app genuinely does not know, and upstream's
    /// folder no longer supplies one.
    func testTheHeadlineClaimsNamesAndNeverNetworks() throws {
        let strange = String(data: try fixture("microduck-tree"), encoding: .utf8)!
            .replacingOccurrences(of: "policies/roulade.onnx",
                                  with: "policies/somebody_elses_gait.onnx")
        let entries = try PolicyCatalogue.parse(Data(strange.utf8),
                                                source: PolicyCatalogue.officialPolicies,
                                                extensions: ["onnx"])
        let headline = PolicyCatalogue.headline(entries)
        XCTAssertTrue(headline.contains("a name this build has not seen"), headline)
        XCTAssertFalse(headline.lowercased().contains("new polic"),
                       "a listing cannot tell whether a network is new: \(headline)")
        let unfamiliar = try XCTUnwrap(
            entries.first { $0.filename == "somebody_elses_gait.onnx" })
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
