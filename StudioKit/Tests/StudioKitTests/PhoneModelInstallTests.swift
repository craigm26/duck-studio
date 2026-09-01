import XCTest
@testable import StudioKit

/// `PhoneModelInstall` had no test references at all, which is why a frozen
/// progress line, a half-download reported as complete, and two false clauses
/// in one sentence all shipped together.
final class PhoneModelInstallTests: XCTestCase {

    // MARK: - the progress line

    /// THE REAL SHAPE: 2.28 GB, most of it one file. Counting whole files gave
    /// "1%, 14 MB of 2.3 GB" frozen for twenty minutes; the fraction moves.
    func testProgressNamesBothThePercentageAndTheBytes() {
        let line = PhoneModelInstall.downloading(fraction: 0.4, totalBytes: 2_278_972_236)
        XCTAssertTrue(line.contains("40%"), line)
        XCTAssertTrue(line.contains("912 MB"), line)   // below the 1 GB threshold
        XCTAssertTrue(line.contains("2.3 GB"), line)
    }

    /// AN UNCLAMPED FRACTION PRINTS 103%. The parent's total is a sum of tree
    /// sizes while each child's is overwritten by the HTTP content length.
    func testAnImpossibleFractionIsClamped() {
        XCTAssertTrue(PhoneModelInstall.downloading(fraction: 1.03, totalBytes: 1_000_000_000)
                        .contains("100%"))
        XCTAssertTrue(PhoneModelInstall.downloading(fraction: -1, totalBytes: 1_000_000_000)
                        .contains("0%"))
        XCTAssertTrue(PhoneModelInstall.downloading(fraction: .nan, totalBytes: 1_000_000_000)
                        .contains("0%"))
    }

    /// The hub reports a placeholder count of 1 for an already-cached snapshot.
    /// There are no bytes to name, so it must not invent "0 MB of 0 MB".
    func testAPlaceholderTotalNamesNoBytes() {
        let line = PhoneModelInstall.downloading(fraction: 0.5, totalBytes: 1)
        XCTAssertEqual(line, "Downloading — 50%.")
        XCTAssertFalse(line.contains("0 MB"), line)
    }

    // MARK: - the three states

    func testAnEmptyDirectoryIsAbsent() {
        XCTAssertEqual(PhoneModelInstall.state(paths: [], indexJSON: nil, bytes: 0), .absent)
        XCTAssertEqual(PhoneModelInstall.state(paths: ["config.json"], indexJSON: nil, bytes: 0),
                       .absent)
    }

    /// A TORN-OFF DOWNLOAD IS NOT AN INSTALL. Weights with no tokenizer used to
    /// render the green "On this phone, taking 1.4 GB" with a Delete button and
    /// no way back to Download.
    func testWeightsWithoutATokenizerArePartial() {
        XCTAssertEqual(
            PhoneModelInstall.state(paths: ["config.json", "model.safetensors"],
                                    indexJSON: nil, bytes: 1_400_000_000),
            .partial)
    }

    func testAWholeUnshardedModelIsComplete() {
        XCTAssertEqual(
            PhoneModelInstall.state(paths: ["config.json", "tokenizer.json", "model.safetensors"],
                                    indexJSON: nil, bytes: 700_000_000),
            .complete)
    }

    /// SHARDED MODELS NEED EVERY SHARD THE MAP NAMES. One missing shard is a
    /// model that downloads, looks finished, and fails to open.
    func testAShardedModelNeedsEveryShardTheMapNames() throws {
        let index = """
        {"weight_map":{"a":"model-00001-of-00002.safetensors",
                       "b":"model-00002-of-00002.safetensors"}}
        """.data(using: .utf8)!
        let missing = ["config.json", "tokenizer.json", "model-00001-of-00002.safetensors"]
        XCTAssertEqual(PhoneModelInstall.state(paths: missing, indexJSON: index,
                                               bytes: 1_000_000_000), .partial)

        let whole = missing + ["model-00002-of-00002.safetensors"]
        XCTAssertEqual(PhoneModelInstall.state(paths: whole, indexJSON: index,
                                               bytes: 2_000_000_000), .complete)
    }

    // MARK: - the sentences that were false

    /// BOTH CLAUSES WERE WRONG. Leaving did not stop it — nothing cancelled the
    /// task — and it did not resume from where it got to: the hub writes its
    /// partial marker only on success, and the in-flight temp file is discarded.
    func testTheStaysOpenNoteDescribesWhatActuallyHappens() {
        let s = PhoneModelInstall.staysOpenNote
        XCTAssertTrue(s.contains("Leaving stops it"), s)
        XCTAssertTrue(s.contains("starts over"), s)
        XCTAssertFalse(s.contains("from where it got to"),
                       "that promised mid-file resume, which does not happen: \(s)")
    }

    /// A partial download must not be described as usable.
    func testThePartialSentenceClaimsNoUsability() {
        let s = PhoneModelInstall.partlyDownloaded(bytes: 1_400_000_000)
        XCTAssertTrue(s.contains("Partly downloaded"), s)
        XCTAssertTrue(s.contains("1.4 GB"), s)
        XCTAssertFalse(s.lowercased().contains("ready"), s)
    }

    /// THE SWIPE PATH HOLDS AN ENDPOINT, NOT A CATALOGUE ENTRY, and a searched
    /// repository is in no catalogue — so the confirmation takes a name, and
    /// survives not knowing the size.
    func testTheDeleteConfirmationWorksWithAndWithoutASize() {
        let known = PhoneModelInstall.deleteConfirmation(named: "Qwen3 4B", bytes: 2_278_972_236)
        XCTAssertTrue(known.contains("free 2.3 GB"), known)
        XCTAssertTrue(known.contains("downloaded again"), known)

        let unknown = PhoneModelInstall.deleteConfirmation(named: "Something", bytes: nil)
        XCTAssertFalse(unknown.contains("free"), "no size, no number: \(unknown)")
        XCTAssertTrue(unknown.contains("downloaded again"), unknown)
    }

    /// The distinction that saves somebody spending the bytes twice.
    func testTheTokenizerFailureSaysNotToRetryTheDownload() {
        let s = PhoneModelInstall.downloadedButWouldNotOpen
        XCTAssertTrue(s.contains("download finished"), s)
        XCTAssertTrue(s.contains("again will not help"), s)
    }

    /// TWO OF FIVE CATALOGUE MODELS THINK BY DEFAULT, and greedy decoding with
    /// thinking on is the failure Qwen's own card names.
    func testThinkingIsTurnedOffByTheKeyTheTemplateReads() {
        XCTAssertEqual(PhoneModelInstall.templateThinkingOff["enable_thinking"] as? Bool, false)
    }

    // MARK: - the fit check

    /// ONCE LOADED, A MODEL'S OWN WEIGHTS HAVE ALREADY BEEN SUBTRACTED from the
    /// budget it is compared against — so it reported itself too big to run
    /// seconds after answering.
    func testALoadedModelIsJudgedOnHeadroomAlone() throws {
        let big = try XCTUnwrap(PhoneModel.catalogue.last)
        XCTAssertFalse(big.fits(budgetBytes: 500_000_000))
        XCTAssertTrue(big.fits(budgetBytes: 500_000_000, alreadyResident: true))
    }

    func testTheLoadedRefusalDoesNotClaimItNeedsToBeLoaded() {
        let s = PhoneModel.tooBigWhileLoaded("Qwen3 4B", budgetBytes: 200_000_000)
        XCTAssertTrue(s.contains("is loaded"), s)
        XCTAssertFalse(s.contains("needs roughly"),
                       "that is the not-yet-loaded sentence: \(s)")
    }

    /// A BUDGET OF ZERO IS A MOMENT, NOT A VERDICT — iOS returns it when the
    /// process is already at its limit.
    func testAnUnknownBudgetIsNotRenderedAsZero() {
        XCTAssertFalse(PhoneModel.budgetUnknown.contains("0"), PhoneModel.budgetUnknown)
        XCTAssertTrue(PhoneModel.budgetUnknown.contains("try again"), PhoneModel.budgetUnknown)
    }

    // MARK: - an HTTP fault is not a verdict about a repository

    func testAFaultIsBlamedOnTheIndexRatherThanTheModel() {
        let s = PhoneModelSearch.huggingFaceAnswered(429)
        XCTAssertTrue(s.contains("429"), s)
        XCTAssertTrue(s.contains("the index, not the model"), s)
        XCTAssertTrue(PhoneModelSearch.noConfigJSON.contains("no config.json"))
    }

    /// Without LocalizedError a bare catch prints the enum's own index number
    /// in front of somebody who asked a question about a model.
    func testTheReadErrorDescribesItself() {
        let error: Error = PhoneModelSearch.ReadError.notJSON
        XCTAssertEqual(error.localizedDescription,
                       PhoneModelSearch.ReadError.notJSON.message)
        XCTAssertFalse(error.localizedDescription.contains("error 1"))
    }

    // MARK: - the untried list

    /// THE FIRST LIST MAKES A PROMISE and the second one must not be folded
    /// into it: `scopeNote` says the first list is the tried one.
    func testTheUntriedListIsSeparateAndSaysSo() throws {
        XCTAssertFalse(PhoneModel.untried.isEmpty)
        for model in PhoneModel.untried {
            XCTAssertFalse(PhoneModel.catalogue.contains(model), model.name)
        }
        XCTAssertEqual(PhoneModel.all.count,
                       PhoneModel.catalogue.count + PhoneModel.untried.count)
        XCTAssertTrue(PhoneModelSearch.scopeNote.contains("first list above"),
                      PhoneModelSearch.scopeNote)
        XCTAssertTrue(PhoneModel.untriedPreamble.contains("not tried here"),
                      PhoneModel.untriedPreamble)
    }

    /// And the Gemma 4 row must not repeat the vendor's framing: on this stack
    /// the per-layer embedding table is resident, so "effective" buys nothing.
    func testTheGemma4RowRefusesTheEffectiveParameterFraming() throws {
        let gemma = try XCTUnwrap(PhoneModel.untried.first { $0.name.contains("Gemma 4") })
        XCTAssertTrue(gemma.note.contains("buys back no memory"), gemma.note)
        XCTAssertTrue(gemma.note.contains("nobody has run it here"), gemma.note)
    }

    /// A STOPPED DOWNLOAD MUST SAY SO. Swallowing cancellation made the row
    /// stop moving and — with the partial read as complete — turn green, which
    /// is how a half-downloaded model looked finished.
    func testAStoppedDownloadIsReportedAndSaysWhatToDo() {
        let s = PhoneModelInstall.stopped
        XCTAssertTrue(s.contains("stopped before it finished"), s)
        XCTAssertTrue(s.contains("starting it again"), s)
        XCTAssertTrue(s.contains("delete it and start over"), s)
    }

    /// QWEN'S OWN SOFT SWITCH, sent as well as the template flag because the
    /// template route is unproven on a device and the first real run spent
    /// twenty-three minutes producing no JSON.
    func testQwenModelsGetTheDocumentedThinkingSwitch() {
        XCTAssertEqual(
            PhoneModelInstall.prompt("take a bow", for: "mlx-community/Qwen3-1.7B-4bit"),
            "take a bow /no_think")
        // AND NOTHING ELSE DOES. A model that never heard of the token would
        // just receive a stray word in its prompt.
        XCTAssertEqual(
            PhoneModelInstall.prompt("take a bow", for: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
            "take a bow")
        XCTAssertEqual(
            PhoneModelInstall.prompt("take a bow", for: "mlx-community/gemma-3-1b-it-qat-4bit"),
            "take a bow")
    }

    /// A DEADLINE THAT STOPS IT, and a sentence that says what to do instead.
    func testTheTimeoutSentenceSuggestsSomethingActionable() {
        let s = PhoneModelInstall.tookTooLong(seconds: 300)
        XCTAssertTrue(s.contains("300 seconds"), s)
        XCTAssertTrue(s.contains("shorter one, or a bigger model"), s)
    }
}
