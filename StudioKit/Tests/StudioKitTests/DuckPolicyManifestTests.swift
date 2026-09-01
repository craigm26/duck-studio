import XCTest
import DuckKit
@testable import StudioKit

/// Read against a REAL published policy, not a hand-written sample.
///
/// The fixture is `manifest.json` from `joanfox/microduck-happy-hop`, fetched
/// from the Hub on 2026-09-01. A convention this project does not own is one it
/// can only get wrong quietly, so the test data is somebody else's file.
final class DuckPolicyManifestTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)",
                                                  withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func happyHop() throws -> DuckPolicyManifest {
        try DuckPolicyManifest.read(try fixture("hub/happy-hop-manifest"))
    }

    func testARealPublishedManifestReads() throws {
        let m = try happyHop()
        XCTAssertEqual(m.schemaVersion, 2)
        XCTAssertEqual(m.modelAPI, 1)
        XCTAssertEqual(m.name, "happy-hop")
        XCTAssertEqual(m.kind, "episodic")
        XCTAssertEqual(m.obsLength, 61)
        XCTAssertEqual(m.actionLength, 14)
        XCTAssertEqual(m.durationSeconds, 3.0)
        XCTAssertEqual(m.entryPose, "standing")
    }

    /// THE FIELD THIS TYPE EXISTS FOR. Guessing by filename gives a community
    /// policy walking's 0.9; this one says 1.0, and the difference is 10% of
    /// every joint target.
    func testTheActionScaleComesFromTheFileRatherThanTheFilename() throws {
        let m = try happyHop()
        XCTAssertEqual(m.actionScale, 1.0)
        let (value, fromManifest) = m.scale(orGuessed: DuckModel.actionScale)
        XCTAssertEqual(value, 1.0)
        XCTAssertTrue(fromManifest)
        XCTAssertNotEqual(value, DuckModel.actionScale, "0.9 is what the guess would have given")
    }

    func testAManifestWithNoScaleFallsBackAndSaysSo() throws {
        let bare = Data(#"{"schema_version":2,"name":"x","obs_len":61,"action_len":14}"#.utf8)
        let m = try DuckPolicyManifest.read(bare)
        let (value, fromManifest) = m.scale(orGuessed: 0.9)
        XCTAssertEqual(value, 0.9)
        XCTAssertFalse(fromManifest, "a fallback must never be reported as the author's number")
    }

    func testTheWidthsAreCheckedAgainstThisRobot() throws {
        XCTAssertTrue(try happyHop().claimsTheRightShape)
        XCTAssertNil(try happyHop().shapeComplaint)
        let wrong = Data(#"{"schema_version":2,"name":"x","obs_len":51,"action_len":14}"#.utf8)
        let m = try DuckPolicyManifest.read(wrong)
        XCTAssertFalse(m.claimsTheRightShape)
        XCTAssertTrue(try XCTUnwrap(m.shapeComplaint).contains("51"))
        XCTAssertTrue(try XCTUnwrap(m.shapeComplaint).contains("61"))
    }

    /// "Trained unfiltered … for a matched runtime test, action low-pass
    /// filters must be pass-through."
    func testAnUnfilteredPolicyAsksForPassThrough() throws {
        let m = try happyHop()
        XCTAssertEqual(m.headLowpass, 1.0)
        XCTAssertEqual(m.legsLowpass, 1.0)
        XCTAssertTrue(m.wantsUnfilteredActions)
        XCTAssertTrue(m.honesty.contains("pass-through"))
    }

    /// The author's caveats are quoted, not paraphrased.
    func testTheAuthorsOwnLimitsAreCarried() throws {
        let m = try happyHop()
        XCTAssertEqual(m.status, "sim-only-hardware-candidate")
        XCTAssertTrue(try XCTUnwrap(m.knownLimits).contains("never tested on hardware"))
        XCTAssertTrue(m.honesty.contains("never tested on hardware"),
                      "the sentence the author wrote must reach the screen")
        XCTAssertTrue(m.honesty.contains("sim-only-hardware-candidate"))
        XCTAssertTrue(m.honesty.contains("standing"))
    }

    func testAManifestThatSaysNothingSaysThatRatherThanNothing() throws {
        let bare = Data(#"{"schema_version":2,"name":"x","obs_len":61,"action_len":14}"#.utf8)
        let m = try DuckPolicyManifest.read(bare)
        XCTAssertTrue(m.honesty.contains("records no status"))
    }

    func testProvenanceAndPreviewSurvive() throws {
        let m = try happyHop()
        XCTAssertEqual(m.trainingRepo, "pollen-robotics/microduck_rl")
        XCTAssertEqual(m.previewPath, "media/preview.mp4")
        XCTAssertTrue(try XCTUnwrap(m.trainingTask).contains("HappyHop"))
        // `repo@sha`, not a bare sha — the pin names WHICH repository it pins.
        let base = try XCTUnwrap(m.upstreamBase)
        XCTAssertTrue(base.hasPrefix("pollen-robotics/microduck_rl@"), base)
        XCTAssertEqual(base.split(separator: "@").last?.count, 40, "a full commit sha")
        XCTAssertEqual(try XCTUnwrap(m.sourceDigest).count, 64)
    }

    func testSomethingWithoutTheWidthsIsNotAPolicyManifest() {
        let notOne = Data(#"{"schema_version":2,"name":"x"}"#.utf8)
        XCTAssertThrowsError(try DuckPolicyManifest.read(notOne)) {
            XCTAssertEqual($0 as? DuckPolicyManifest.ReadError, .missing("obs_len"))
        }
        XCTAssertThrowsError(try DuckPolicyManifest.read(Data("nope".utf8))) {
            XCTAssertEqual($0 as? DuckPolicyManifest.ReadError, .notJSON)
        }
    }

    /// The tag is how a policy is found on the Hub at all.
    func testTheHubTagIsTheOneThePublishedRepositoryCarries() {
        XCTAssertEqual(DuckPolicyManifest.hubTag, "microduck-policy")
        XCTAssertEqual(DuckPolicyManifest.path, "manifest.json",
                       "a policy repo puts it at the root, unlike our motion datasets")
    }
}

extension DuckPolicyManifestTests {

    /// The comparison IS the point — a community policy declaring 1.0 where the
    /// app would have guessed 0.9 is one that would have run 10% short.
    func testTheScaleRowNamesTheGuessItReplaces() throws {
        let line = try XCTUnwrap(try happyHop().scaleLine)
        XCTAssertEqual(line.title, "Action scale")
        XCTAssertTrue(line.value.hasPrefix("1"), line.value)
        XCTAssertTrue(line.value.contains("would have guessed"), line.value)
        XCTAssertTrue(line.value.contains("0.9"), line.value)
    }

    func testAScaleThatMatchesTheGuessIsNotDressedUpAsADisagreement() throws {
        let same = Data(#"{"schema_version":2,"name":"x","obs_len":61,"action_len":14,"action_scale":0.9}"#.utf8)
        let line = try XCTUnwrap(try DuckPolicyManifest.read(same).scaleLine)
        XCTAssertEqual(line.value, "0.9")
        XCTAssertFalse(line.value.contains("guessed"))
    }
}
