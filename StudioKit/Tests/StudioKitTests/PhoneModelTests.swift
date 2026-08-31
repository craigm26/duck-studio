import XCTest
@testable import StudioKit

/// A catalogue of things to download onto a phone is a catalogue of ways to
/// waste somebody's evening, unless the sizes are real and the fit is checked.
final class PhoneModelTests: XCTestCase {

    // MARK: - the sizes are real

    /// EVERY SIZE HERE WAS MEASURED against the Hugging Face tree API on
    /// 2026-08-31, not estimated. This pins the two that matter most — the
    /// smallest, and the first one that will not fit a 4 GB phone — so a
    /// careless edit that rounds them cannot pass.
    func testTheMeasuredSizesAreTheMeasuredSizes() throws {
        let byRepo = Dictionary(uniqueKeysWithValues:
            PhoneModel.catalogue.map { ($0.repository, $0) })
        XCTAssertEqual(byRepo["mlx-community/Qwen3-0.6B-4bit"]?.downloadBytes, 351_000_000)
        XCTAssertEqual(byRepo["mlx-community/Qwen3-4B-Instruct-2507-4bit"]?.downloadBytes,
                       2_279_000_000)
    }

    func testTheCatalogueIsOrderedSmallestFirst() {
        let sizes = PhoneModel.catalogue.map(\.downloadBytes)
        XCTAssertEqual(sizes, sizes.sorted(), "the smallest that works is the right answer")
    }

    func testEveryEntryNamesAnMLXRepositoryAndSaysWhatItIsLike() {
        for model in PhoneModel.catalogue {
            XCTAssertTrue(model.repository.hasPrefix("mlx-community/"),
                          "\(model.repository) is not a format this phone can open")
            XCTAssertGreaterThan(model.note.count, 60, model.name)
            XCTAssertGreaterThan(model.downloadBytes, 0)
        }
        XCTAssertEqual(Set(PhoneModel.catalogue.map(\.id)).count, PhoneModel.catalogue.count)
    }

    // MARK: - fit

    /// THE POINT OF THE WHOLE TYPE. iOS gives an app a budget and kills it for
    /// exceeding one, so a 2.3 GB model on a phone offering 1.4 GB is not
    /// "slow" — it is an app that dies part-way through an answer.
    func testABigModelDoesNotFitASmallBudget() {
        let big = PhoneModel.catalogue.last!
        XCTAssertFalse(big.fits(budgetBytes: 1_400_000_000))
        XCTAssertTrue(big.fits(budgetBytes: 4_000_000_000))
    }

    func testTheSmallestFitsEvenAModestBudget() {
        XCTAssertTrue(PhoneModel.catalogue.first!.fits(budgetBytes: 1_400_000_000))
    }

    /// Peak is more than the download: the weights, plus room for the context
    /// and the arithmetic.
    func testPeakIsLargerThanTheDownload() {
        for model in PhoneModel.catalogue {
            XCTAssertGreaterThan(model.estimatedPeakBytes, model.downloadBytes, model.name)
        }
    }

    /// AND THE REFUSAL ADMITS THE ESTIMATE IS AN ESTIMATE. Nothing here has
    /// been measured on a phone, and a sentence that implied otherwise would be
    /// the kind of claim this app removes.
    func testTheTooBigSentenceOwnsUpToBeingAnEstimate() {
        let s = PhoneModel.tooBig(PhoneModel.catalogue.last!, budgetBytes: 1_400_000_000)
        XCTAssertTrue(s.contains("rule of thumb, not a measurement on this phone"), s)
        XCTAssertTrue(s.contains("killed part-way"), s)
    }

    func testAppleIsStillOfferedAsTheNoDownloadOption() {
        XCTAssertTrue(PhoneModel.versusApple.contains("no download"), PhoneModel.versusApple)
    }

    // MARK: - searching for one that is not listed

    func testTheSearchIsScopedToTheOrganisationWhoseFormatLoads() {
        let url = PhoneModelSearch.url(matching: "qwen").absoluteString
        XCTAssertTrue(url.contains("author=mlx-community"), url)
        XCTAssertTrue(url.contains("search=qwen"), url)
        XCTAssertTrue(url.contains("sort=downloads"), url)
    }

    func testAnEmptySearchListsTheMostDownloadedRatherThanNothing() {
        let url = PhoneModelSearch.url(matching: "   ").absoluteString
        XCTAssertFalse(url.contains("search="), url)
        XCTAssertTrue(url.contains("author=mlx-community"), url)
    }

    /// THE INDEX GIVES NO SIZES, checked against the live endpoint:
    /// `expand[]=usedStorage` is rejected outright and every `siblings` entry
    /// comes back sizeless. So a Hit carries none and the size comes from the
    /// tree API for the one model somebody taps.
    func testResultsAreReadWithoutASizeBecauseTheIndexHasNone() throws {
        let json = """
        [{"id":"mlx-community/Qwen3-1.7B-4bit","downloads":1234,"likes":7},
         {"modelId":"mlx-community/Other-4bit","downloads":10,"likes":0}]
        """.data(using: .utf8)!
        let hits = try PhoneModelSearch.read(json)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].name, "Qwen3-1.7B-4bit")
        XCTAssertEqual(hits[0].downloads, 1234)
        XCTAssertEqual(hits[1].repository, "mlx-community/Other-4bit")
    }

    /// THE TAG FILTER IS LOAD-BEARING. Without it the top hit for "qwen3-1.7b"
    /// on the live index is a text-to-speech model in bf16.
    func testTheSearchAsksForTextGenerationOnly() {
        XCTAssertTrue(PhoneModelSearch.url(matching: "qwen").absoluteString
                        .contains("pipeline_tag=text-generation"))
    }

    /// And the note admits the filter is not a guarantee — an embedding model
    /// tagged text-generation gets through it.
    func testTheScopeNoteAdmitsResultsAreUnchecked() {
        let note = PhoneModelSearch.scopeNote
        XCTAssertTrue(note.contains("not checked beyond that"), note)
        XCTAssertTrue(note.contains("embedding or speech model"), note)
        XCTAssertTrue(note.contains("list above is the one that has been tried"), note)
    }

    /// AN EMPTY RESULT EXPLAINS THE SCOPE. Somebody searching for a model that
    /// exists on Hugging Face and is not in mlx-community needs to know why it
    /// is not here, or they will conclude the search is broken.
    func testNoResultsExplainsWhyTheScopeIsNarrow() {
        XCTAssertThrowsError(try PhoneModelSearch.read("[]".data(using: .utf8)!,
                                                       matching: "llama")) { error in
            let message = (error as? PhoneModelSearch.ReadError)?.message ?? ""
            XCTAssertTrue(message.contains("mlx-community"), message)
            XCTAssertTrue(message.contains("download and then fail to load"), message)
        }
    }

    func testATreeAnswerIsSummedOverFilesOnly() throws {
        let json = """
        [{"type":"file","size":100},{"type":"directory"},{"type":"file","size":23}]
        """.data(using: .utf8)!
        XCTAssertEqual(try PhoneModelSearch.readTreeBytes(json), 123)
    }

    func testTheScopeNoteWarnsBeforeTheDownloadRatherThanAfter() {
        XCTAssertTrue(PhoneModelSearch.scopeNote.contains("slow way to find out"),
                      PhoneModelSearch.scopeNote)
    }
}
