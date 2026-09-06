import XCTest
import DuckKit
@testable import StudioKit

/// A published policy is the three files the Community list reads back, the
/// tag it filters on, and a card that admits where the weights came from.
final class PolicyPublicationTests: XCTestCase {

    private func entry(named name: String, origin: PolicyLibrary.Origin) throws
        -> (PolicyLibrary.Entry, Data) {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "alpha_walking", withExtension: "onnx",
                                                  subdirectory: "Fixtures/policies"))
        let data = try Data(contentsOf: url)
        return (PolicyLibrary.entry(for: data, name: name, origin: origin), data)
    }

    func testTheThreeFilesAreTheOnesTheCommunityListReads() throws {
        let (walk, bytes) = try entry(named: "alpha_walking.onnx", origin: .bundled)
        let publication = try PolicyPublication(entry: walk, onnx: bytes, manifest: nil,
                                                whatItDoes: "Walks under a velocity twist.")
        XCTAssertEqual(publication.files.map(\.path), ["policy.onnx", "manifest.json", "README.md"])
        XCTAssertEqual(publication.files[0].contents, bytes)
        XCTAssertFalse(publication.files[0].isText)
        XCTAssertEqual(PolicyPublication.policyPath,
                       PolicyCatalogue.CommunityReference(repository: "a/b", revision: "main",
                                                          file: nil).policyFile)
        let manifest = try PolicyManifest.decode(publication.files[1].contents)
        XCTAssertEqual(manifest.name, walk.title)
        XCTAssertEqual(manifest.summary, "Walks under a velocity twist.")
        XCTAssertEqual(manifest.kind, "alpha_walking")
        XCTAssertTrue(manifest.incompatibilities.isEmpty)
        XCTAssertEqual(publication.totalBytes, publication.files.reduce(0) { $0 + $1.bytes })
        XCTAssertEqual(publication.fingerprint, walk.identity.value)
    }

    func testTheCardCarriesTheTagTheListFiltersOnAndTheFingerprint() throws {
        let (walk, bytes) = try entry(named: "alpha_walking.onnx", origin: .bundled)
        let publication = try PolicyPublication(entry: walk, onnx: bytes, manifest: nil,
                                                whatItDoes: "Walks.")
        let card = String(decoding: publication.files[2].contents, as: UTF8.self)
        XCTAssertTrue(card.hasPrefix("---\nlicense: apache-2.0\n"), card.prefix(60).description)
        XCTAssertTrue(card.contains("tags: [microduck, microduck-policy, onnx]"), card)
        XCTAssertTrue(card.contains(walk.identity.value))
        XCTAssertTrue(card.contains("republished"), "a bundled policy says whose it is")
        XCTAssertFalse(card.contains("hf_"), "no token shape anywhere near a card")
    }

    func testAKeptNetworksManifestTravelsWithItsMakingIntact() throws {
        let (made, bytes) = try entry(named: "alpha_walking-searched.onnx",
                                      origin: .searched(base: "alpha_walking"))
        let search = KeptNetwork.Search(
            baseTitle: "alpha_walking", baseIdentity: "abc", generations: 8, pairs: 10,
            step: 0.05, gained: 1.018, keptElsewhere: 0.86, plantName: "p", plantDigest: "d",
            build: "62")
        let held = try KeptNetwork.manifest(for: search, named: "alpha_walking, searched")
        let publication = try PolicyPublication(entry: made, onnx: bytes, manifest: held,
                                                whatItDoes: "Walks a little further.")
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: publication.files[1].contents)
                                    as? [String: Any])
        XCTAssertEqual((top["made_here"] as? [String: Any])?["how"] as? String, "weight search")
        XCTAssertEqual(top["when_to_use"] as? String, "Walks a little further.")
        XCTAssertEqual(top["name"] as? String, "alpha_walking, searched",
                       "the held manifest's own name is not rewritten")
        let card = String(decoding: publication.files[2].contents, as: UTF8.self)
        XCTAssertTrue(card.contains(KeptNetwork.searchedCaution))
        XCTAssertTrue(card.contains("trains no network"), "the made-here card admits it")
        XCTAssertTrue(card.contains("Searched here from alpha_walking"))
    }

    func testASentenceIsRequiredAndSaidInPolicyWords() throws {
        let (walk, bytes) = try entry(named: "alpha_walking.onnx", origin: .bundled)
        XCTAssertThrowsError(try PolicyPublication(entry: walk, onnx: bytes, manifest: nil,
                                                   whatItDoes: "   ")) { error in
            XCTAssertEqual(error as? HuggingFacePublish.Refusal, .noWhatItDoes)
            XCTAssertTrue(HuggingFacePublish.Refusal.noWhatItDoes.message.contains("network"))
        }
        XCTAssertThrowsError(try PolicyPublication(entry: walk, onnx: Data(), manifest: nil,
                                                   whatItDoes: "x"))
    }

    func testTheRepositoryNameShowsBareOnTheCommunityList() {
        XCTAssertEqual(PolicyPublication.slug(for: "Alpha Walking, searched 09-06"),
                       "microduck-alpha-walking-searched-09-06")
        XCTAssertEqual(PolicyPublication.slug(for: "microduck-x"), "microduck-x")
        XCTAssertEqual(PolicyPublication.slug(for: "***"), "microduck-policy")
        let entry = PolicyCatalogue.CommunityEntry(
            id: "me/" + PolicyPublication.slug(for: "walk two"), author: "me", updated: nil,
            downloads: 0, likes: 0, declaresPolicyTag: true)
        XCTAssertEqual(entry.name, "walk-two")
        XCTAssertEqual(PolicyPublication.repositoryKind, .model)
        XCTAssertEqual(try HuggingFacePublish.repository(namespace: "me", name: PolicyPublication.slug(for: "walk two"),
                                                         kind: .model).webURL,
                       "https://huggingface.co/me/microduck-walk-two")
    }
}
