import XCTest
@testable import StudioKit

/// Parsed against a real Hub response, captured 2026-09-01.
final class PolicyHubTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)",
                                                  withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testTheQueryAsksForTheTagThePublishedRepositoriesCarry() {
        let url = PolicyHub.searchURL().absoluteString
        XCTAssertTrue(url.contains("filter=microduck-policy"), url)
        XCTAssertTrue(url.contains("sort=lastModified"),
                      "a handful of repositories sorts by what changed, not by downloads")
        XCTAssertFalse(url.contains("mlx-community"),
                       "that scope is the language-model picker's and finds no policies")
    }

    func testSearchTextIsCarried() {
        XCTAssertTrue(PolicyHub.searchURL(matching: "walk").absoluteString.contains("search=walk"))
        XCTAssertFalse(PolicyHub.searchURL(matching: "   ").absoluteString.contains("search="))
    }

    func testARealListingReads() throws {
        let found = try PolicyHub.read(try fixture("hub/policy-search"))
        XCTAssertGreaterThanOrEqual(found.count, 5)
        let ids = found.map(\.repository)
        XCTAssertTrue(ids.contains("joanfox/microduck-happy-hop"), "\(ids)")
        // Published by Pollen's own co-founder, and by other owners: the point
        // is that the list spans authors rather than one account.
        XCTAssertGreaterThan(Set(found.map(\.author)).count, 1)
        let hop = try XCTUnwrap(found.first { $0.repository == "joanfox/microduck-happy-hop" })
        XCTAssertEqual(hop.author, "joanfox")
        XCTAssertEqual(hop.name, "microduck-happy-hop")
        XCTAssertFalse(hop.gated)
    }

    /// The clip this app already ships names `community/flamingo-cycle` — and
    /// the repository it came from is in this listing.
    func testTheFlamingoWeAlreadyShipIsDiscoverable() throws {
        let found = try PolicyHub.read(try fixture("hub/policy-search"))
        XCTAssertTrue(found.contains { $0.repository.hasSuffix("microduck-flamingo-cycle") },
                      "\(found.map(\.repository))")
    }

    /// `resolve`, not `blob` — the bytes, not a page about the bytes.
    func testFileURLsPointAtBytes() throws {
        let url = try XCTUnwrap(PolicyHub.fileURL(repository: "joanfox/microduck-happy-hop",
                                                  path: PolicyHub.policyPath))
        XCTAssertEqual(url.absoluteString,
                       "https://huggingface.co/joanfox/microduck-happy-hop/resolve/main/policy.onnx")
        XCTAssertFalse(url.absoluteString.contains("/blob/"))
        let manifest = try XCTUnwrap(PolicyHub.fileURL(repository: "a/b",
                                                       path: PolicyHub.manifestPath))
        XCTAssertTrue(manifest.absoluteString.hasSuffix("/resolve/main/manifest.json"))
    }

    func testAnEmptyAnswerSaysWhichKindOfEmpty() {
        XCTAssertThrowsError(try PolicyHub.read(Data("[]".utf8))) {
            XCTAssertTrue(($0 as! PolicyHub.ReadError).message.contains("did not reach it"))
        }
        XCTAssertThrowsError(try PolicyHub.read(Data("[]".utf8), matching: "zzz")) {
            XCTAssertTrue(($0 as! PolicyHub.ReadError).message.contains("\"zzz\""))
        }
        XCTAssertThrowsError(try PolicyHub.read(Data("<html>".utf8))) {
            XCTAssertEqual($0 as? PolicyHub.ReadError, .notJSON)
        }
    }

    func testTheBrowserSaysTheseAreNotPollens() {
        XCTAssertTrue(PolicyHub.provenanceNote.contains("not releases from Pollen Robotics"))
        XCTAssertTrue(PolicyHub.provenanceNote.contains("only a bench answers"))
    }
}
