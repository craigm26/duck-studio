import XCTest
@testable import StudioKit

/// Hugging Face keeps models, datasets and Spaces in three separate indexes, and this
/// screen wants exactly one of them. Before these tests a pasted dataset address parsed
/// into a repository called "datasets/<owner>" and went on to build a resolve URL under an
/// owner that does not exist — a fetch that could only 404, reported as a protobuf error.
final class PolicyCatalogueKindTests: XCTestCase {

    // MARK: - the listing asks the models index and says so

    func testTheCommunityListingAsksTheModelsIndexAndNoOther() {
        let request = PolicyCatalogue.communityListing(limit: 7)
        XCTAssertEqual(request.displayURL,
                       "https://huggingface.co/api/models?filter=microduck&limit=7")
        XCTAssertEqual(request.host, "huggingface.co")
        XCTAssertFalse(request.displayURL.contains("datasets"),
                       "a dataset holds no network, so this screen never asks that index")
    }

    /// Every entry comes out of the models index, so the bare address is the right one.
    /// A dataset would need the `datasets/` prefix — and without it would not 404, it
    /// would quietly open the model of the same name.
    func testAListedEntryLinksToItsModelPage() {
        let entry = PolicyCatalogue.CommunityEntry(
            id: "RemiFabre/microduck-flamingo-cycle", author: "RemiFabre",
            updated: "2026-08-29", downloads: 3, likes: 1, declaresPolicyTag: true)
        XCTAssertEqual(entry.webURL, "https://huggingface.co/RemiFabre/microduck-flamingo-cycle")
    }

    // MARK: - a dataset is refused by name, never fetched as a policy

    func testADatasetAddressIsRefusedInEveryShapeItArrivesIn() {
        for text in [
            "https://huggingface.co/datasets/craigm26/microduck-recorded-runs",
            "https://www.huggingface.co/datasets/craigm26/microduck-recorded-runs/tree/main",
            "https://huggingface.co/api/datasets/craigm26/microduck-recorded-runs",
            "datasets/craigm26/microduck-recorded-runs",
        ] {
            XCTAssertThrowsError(try PolicyCatalogue.communityReference(from: text), text) {
                XCTAssertEqual($0 as? PolicyCatalogue.ReferenceError,
                               .isADataset("craigm26/microduck-recorded-runs"), text)
            }
        }
    }

    func testTheDatasetRefusalSaysWhatADatasetIsAndWhatToPasteInstead() {
        XCTAssertEqual(
            PolicyCatalogue.ReferenceError.isADataset("craigm26/microduck-recorded-runs").message,
            "craigm26/microduck-recorded-runs is a dataset, not a model. A dataset holds "
          + "files — recordings, vectors, notes — and this screen imports a trained "
          + "network, so there is nothing in it to load here. If the author published the "
          + "network too, paste that repository instead.")
    }

    func testASpaceAddressIsRefusedRatherThanFetched() {
        XCTAssertThrowsError(
            try PolicyCatalogue.communityReference(
                from: "https://huggingface.co/spaces/pollen-robotics/reachy-mini-sim")
        ) {
            XCTAssertEqual($0 as? PolicyCatalogue.ReferenceError,
                           .isASpace("pollen-robotics/reachy-mini-sim"))
        }
        XCTAssertEqual(
            PolicyCatalogue.ReferenceError.isASpace("pollen-robotics/reachy-mini-sim").message,
            "pollen-robotics/reachy-mini-sim is a Space, not a model. A Space is a web app "
          + "hosted on Hugging Face; the network it runs, if it has one, lives in a "
          + "separate repository, and that is the address this screen wants.")
    }

    /// A section word with nothing behind it is malformed, not a dataset — there is no
    /// repository to name in the refusal, so the refusal that names none is the honest one.
    func testASectionWithNoRepositoryBehindItIsMalformed() {
        XCTAssertThrowsError(
            try PolicyCatalogue.communityReference(from: "https://huggingface.co/datasets")
        ) {
            XCTAssertEqual($0 as? PolicyCatalogue.ReferenceError, .malformed("/datasets"))
        }
    }

    // MARK: - and a model still parses exactly as it did

    func testAModelAddressIsUnaffectedByTheNewGuard() throws {
        for text in [
            "RemiFabre/microduck-flamingo-cycle",
            "https://huggingface.co/RemiFabre/microduck-flamingo-cycle",
            "https://huggingface.co/api/models/RemiFabre/microduck-flamingo-cycle",
            "https://huggingface.co/models/RemiFabre/microduck-flamingo-cycle",
        ] {
            let reference = try PolicyCatalogue.communityReference(from: text)
            XCTAssertEqual(reference.repository, "RemiFabre/microduck-flamingo-cycle", text)
            XCTAssertEqual(reference.policyFile, "policy.onnx", text)
        }
    }

    /// An owner genuinely called "datasets" is not reachable through this box any more.
    /// That is a real cost, written down rather than discovered: the Hub reserves
    /// `datasets`, `models` and `spaces` as path segments, so no such owner can exist.
    func testTheReservedSegmentsAreNotUsableAsOwnerNames() {
        XCTAssertThrowsError(try PolicyCatalogue.communityReference(from: "datasets/thing"))
        XCTAssertThrowsError(try PolicyCatalogue.communityReference(from: "spaces/thing"))
    }
}
