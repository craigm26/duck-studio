import XCTest
@testable import StudioKit

/// The bundle, the issue and the Hugging Face path.
final class StairsSubmissionTests: XCTestCase {

    func made(benchName: String = "This iPhone", onPublishedGrid: Bool = true)
    throws -> StairsChallenge.Submission {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "Fixtures/stairs/best_r6_ceilvaultC_60mm-climb", withExtension: "json"))
        let top = try HarnessJSON.parse(try Data(contentsOf: url))
        let rows = try XCTUnwrap(top["answers"]?.arrayValue)
        let cells = try rows.map { try DuckBench.readClimbed($0.encoded(.compact)) }
        return StairsChallenge.Submission(
            move: try StairsChallenge.move(for: StairsChallenge.record),
            score: StairsChallenge.Score(rise: 0.060, cells: cells),
            benchName: benchName,
            benchAddress: benchName == "This iPhone" ? "http://127.0.0.1:8770" : nil,
            onPublishedGrid: onPublishedGrid,
            row: StairsChallenge.record,
            appVersion: "1.0 (41)",
            date: Date(timeIntervalSince1970: 1_788_307_200))   // 2026-09-02T00:00:00Z
    }

    // MARK: - the file

    /// THE HASH IS FIRST, because that is what somebody looking for this run
    /// has in their hand.
    func testTheFilenameNamesTheMoveTheRiseAndTheDay() throws {
        XCTAssertEqual(try made().filename,
            "microduck-stairs-a56d459fb6493855d635021dce569cc8b06b325b32b3c19e8593cf430ca442d1"
          + "-60mm-2026-09-02.json")
    }

    /// EVERYTHING A SECOND PERSON NEEDS TO REPEAT THE RUN. The intent byte for
    /// byte, the fourteen answers unrounded, and the plant digest — a
    /// submission without that digest is a screenshot.
    func testTheBundleCarriesTheIntentTheCellsAndThePlant() throws {
        let submission = try made()
        let bundle = try HarnessJSON.parse(submission.bundle())

        XCTAssertEqual(bundle["kind"]?.stringValue,
                       "microduck-stairs-challenge-submission")
        XCTAssertEqual(bundle["date"]?.stringValue, "2026-09-02T00:00:00Z")
        XCTAssertEqual(bundle["app"]?.stringValue, "Microduck Studio 1.0 (41)")

        // The intent, byte for byte with the shipped file.
        let intent = try XCTUnwrap(bundle["move"]?["intent"])
        XCTAssertEqual(intent.encoded(.pretty),
                       try StairsChallenge.intentData(named: StairsChallenge.record.file))

        // The bench and its plant.
        XCTAssertEqual(bundle["bench"]?["name"]?.stringValue, "This iPhone")
        XCTAssertEqual(bundle["bench"]?["address"]?.stringValue, "http://127.0.0.1:8770")
        XCTAssertEqual(bundle["bench"]?["plantName"]?.stringValue, "scene.mjb")
        XCTAssertEqual(bundle["bench"]?["plantDigest"]?.stringValue, StairsChallenge.plantDigest)
        XCTAssertEqual(bundle["bench"]?["publishedGrid"]?.boolValue, true)

        // The aggregate.
        XCTAssertEqual(bundle["score"]?["kCore"]?.doubleValue, 5)
        XCTAssertEqual(bundle["score"]?["kCoreStable"]?.doubleValue, 5)
        XCTAssertEqual(bundle["score"]?["kExt"]?.doubleValue, 5)
        XCTAssertEqual(bundle["score"]?["kExtStable"]?.doubleValue, 5)
        XCTAssertEqual(bundle["score"]?["ceilingCore"]?.doubleValue, 5)
        XCTAssertEqual(bundle["score"]?["rise_mm"]?.doubleValue, 60)
        XCTAssertEqual(bundle["score"]?["bar"]?.doubleValue, 7)
        XCTAssertEqual(bundle["score"]?["meetsBar"]?.boolValue, false)

        // And every cell, under the bench's own field names.
        let cells = try XCTUnwrap(bundle["cells"]?.arrayValue)
        XCTAssertEqual(cells.count, 14)
        XCTAssertEqual(cells[0]["above_mm"]?.doubleValue, 116.17658662135791)
        XCTAssertEqual(cells[0]["peakAboveTread_mm"]?.doubleValue, 121.71408220291646)
        XCTAssertEqual(cells[0]["cell"]?["tier"]?.stringValue, "core")
        XCTAssertEqual(cells[13]["cell"]?["tier"]?.stringValue, "ext")
        XCTAssertEqual(bundle["caveat"]?.stringValue, StairsChallenge.realDuckCaveat)
    }

    /// THE BENCH'S DIGITS, NOT A RE-FORMATTED `Double`. The bundle claims to
    /// carry the per-cell answers unrounded; this is that claim, checked
    /// against the token the bench actually wrote.
    func testTheBundleCarriesTheBenchesOwnDigits() throws {
        let bundle = try made().bundle()
        // It is JSON, and it parses.
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: bundle) as? [String: Any])
        let text = try XCTUnwrap(String(data: bundle, encoding: .utf8))
        XCTAssertTrue(text.contains("116.17658662135791"), "the bench's own above_mm")
        XCTAssertTrue(text.contains("237.36029825804"), "the bench's own x_mm")
        XCTAssertTrue(text.contains("-6.9746295824819065"), "the bench's own penetration")
    }

    // MARK: - GitHub

    func testTheIssueTitleIsTheRise() throws {
        XCTAssertEqual(try made().issueTitle, "Stairs challenge: 60 mm")
    }

    /// The body carries the hash, the score line and the instruction to attach
    /// the bundle — a link cannot carry a file, and a body that did not say so
    /// produces issues with nothing in them.
    func testTheIssueBodyCarriesTheHashTheScoreAndTheAttachInstruction() throws {
        let submission = try made()
        let body = submission.issueBody
        XCTAssertTrue(body.contains("`\(submission.hash)`"))
        XCTAssertTrue(body.contains(submission.score.verdict))
        XCTAssertTrue(body.contains(submission.score.line))
        XCTAssertTrue(body.contains("PLEASE ATTACH `\(submission.filename)` TO THIS ISSUE"))
        XCTAssertTrue(body.contains("Scored on This iPhone, plant 3f8c9ab9b409, 2026-09-02, "
                                  + "with Microduck Studio 1.0 (41)."))
        XCTAssertTrue(body.contains("Started from `best_r6_ceilvaultC_60mm.json`"))
        XCTAssertTrue(body.contains(StairsChallenge.realDuckCaveat))
    }

    func testABenchOnADifferentGridSaysSoInTheIssue() throws {
        let body = try made(benchName: "a bench", onPublishedGrid: false).issueBody
        XCTAssertTrue(body.contains(StairsChallenge.Grid.differentGridNote))
    }

    func testTheIssueURLIsTheHarnessRepositorysNewIssueForm() throws {
        let url = try made().issueURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/craigm26/duck-sounds/issues/new")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "title" }?.value, "Stairs challenge: 60 mm")
        XCTAssertEqual(items.first { $0.name == "body" }?.value, try made().issueBody)
    }

    // MARK: - Hugging Face

    /// A SCORED RUN IS DATA. Published as a dataset repository, never a model
    /// one — the same rule the rest of this app publishes motions under.
    func testItPublishesAsADatasetUnderTheSignedInAccount() throws {
        let submission = try made()
        let (repository, create, commit) =
            try submission.publishCalls(namespace: "craigm26", isPrivate: false)
        XCTAssertEqual(repository.kind, .dataset)
        XCTAssertEqual(repository.id, "craigm26/microduck-stairs-challenge-submissions")
        XCTAssertEqual(repository.webURL,
            "https://huggingface.co/datasets/craigm26/microduck-stairs-challenge-submissions")
        XCTAssertEqual(create.url.absoluteString, "https://huggingface.co/api/repos/create")
        XCTAssertTrue(commit.url.absoluteString.contains("/api/datasets/"))

        // The licence is the data licence, not the harness's.
        let created = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try XCTUnwrap(create.body)) as? [String: Any])
        XCTAssertEqual(created["license"] as? String, "cc-by-4.0")
        XCTAssertEqual(created["type"] as? String, "dataset")
        XCTAssertEqual(created["private"] as? Bool, false)
    }

    func testTheCommitCarriesTheBundleAndACard() throws {
        let submission = try made()
        let files = submission.files()
        XCTAssertEqual(files.map(\.path), [submission.filename, "README.md"])
        XCTAssertEqual(files[0].contents, submission.bundle())
        let card = try XCTUnwrap(String(data: files[1].contents, encoding: .utf8))
        XCTAssertTrue(card.contains("license: cc-by-4.0"))
        XCTAssertTrue(card.contains(submission.score.verdict))
        XCTAssertTrue(card.contains(StairsChallenge.realDuckCaveat))
        XCTAssertTrue(card.contains("https://github.com/craigm26/duck-sounds"))
    }

    /// The token never enters a Call. `HuggingFacePublish` pins that for its
    /// own factories; this pins it for the ones built here.
    func testNoCallBuiltHereCanCarryAToken() throws {
        let (_, create, commit) =
            try made().publishCalls(namespace: "craigm26", isPrivate: true)
        for call in [create, commit] {
            XCTAssertFalse(call.displayURL.lowercased().contains("token"))
            XCTAssertFalse(call.displayURL.lowercased().contains("authorization"))
        }
    }

    // MARK: - the sentences

    func testTheSubmissionSentences() {
        XCTAssertEqual(StairsChallenge.Submission.notScoredYet,
            "Score the move on a bench first. A submission is the fourteen cells and the plant "
          + "they were scored in; there is nothing to send until they exist.")
        XCTAssertEqual(StairsChallenge.Submission.whatIsSent,
            "The file holds the move, all fourteen per-cell answers unrounded, the bench's "
          + "plant digest and the date. It is written to this device and nothing is sent until "
          + "you pick where it goes.")
        XCTAssertEqual(StairsChallenge.Submission.issueNote,
            "Opens the issue form with the move's hash and the score line already written. The "
          + "file does not travel in a link — attach it to the issue yourself. You will need a "
          + "GitHub account to open the issue; this is the submission a maintainer sees.")
        XCTAssertEqual(StairsChallenge.Submission.publishNote,
            "Commits the file to a dataset repository under your own account, using the write "
          + "token this app already holds, published under CC BY 4.0, the same licence the "
          + "challenge's data carries.")
        XCTAssertTrue(StairsChallenge.Submission.archiveNote.contains("submits nothing to anyone"))
        XCTAssertTrue(StairsChallenge.Submission.howToRescore.contains("scoreRobust"))
        XCTAssertEqual(HuggingFacePublish.publicWarning,
            "PUBLIC: anyone can find and download it, and anything already fetched stays fetched "
          + "even if you delete it later.")
        XCTAssertEqual(HuggingFacePublish.tokenRefused, "Hugging Face did not accept that token.")
        XCTAssertEqual(HuggingFacePublish.answered(503), "huggingface.co answered 503.")
    }
}
