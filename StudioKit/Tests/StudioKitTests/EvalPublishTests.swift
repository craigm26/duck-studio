import XCTest
@testable import StudioKit

/// Publishing an evaluation: the dataset, the three files, the card, and the
/// one line that appears in an activity feed without them.
///
/// PUBLISHING IS PUBLIC AND IS NOT REALLY UNDOABLE, which is why every call
/// here is CONSTRUCTED and none is sent. These tests are about what the screen
/// would show somebody before they press the button.
final class EvalPublishTests: XCTestCase {

    // MARK: - L13, the commit summary

    /// A commit summary is the one line that appears in an activity feed, in a
    /// notification and in a diff header, without the file beside it. A
    /// cancelled run whose summary opened with its best metric would read,
    /// everywhere a summary is read alone, as a finished run.
    func testTheCommitSummaryAlwaysLeadsWithTheStatus() throws {
        let cases: [(EvalLog.Status, EvalLogFile)] = [
            (.success, try EvalFixtures.workedExample()),
            (.cancelled, try EvalFixtures.cancelled()),
            (.error, try EvalFixtures.allErrored()),
            (.started, try startedLog()),
        ]
        for (status, file) in cases {
            let summary = file.commitSummary()
            XCTAssertEqual(file.log.status, status)
            let stem = EvalLogWriter.slug(file.log.eval.task)
            XCTAssertTrue(summary.hasPrefix("Eval \(stem): \(status.rawValue)"), summary)
        }
        XCTAssertEqual(EvalLog.Status.allCases.count, 4,
                       "a fifth status would need a fifth branch and this list would miss it")
    }

    /// A log this app never writes but can read: their `started`, for a run
    /// still going when the file was made.
    private func startedLog() throws -> EvalLogFile {
        let base = try EvalFixtures.workedExample().log
        let log = EvalLog(status: .started, eval: base.eval, results: base.results,
                          stats: base.stats, samples: base.samples, error: nil)
        return try EvalLogFile.imported(log.encoded(), named: "started.json", runID: "0000ffff")
    }

    func testASuccessfulSummaryCarriesItsMetricsAndItsWorld() throws {
        let summary = try EvalFixtures.workedExample().commitSummary()
        XCTAssertTrue(summary.contains("success_at_end 1.0"), summary)
        XCTAssertTrue(summary.contains("travelled_m 1.1932"), summary)
        XCTAssertTrue(summary.contains("on scene.mjb 3f8c9ab9b409"), summary)
    }

    func testACancelledSummarySaysHowMuchRan() throws {
        let summary = try EvalFixtures.cancelled().commitSummary()
        XCTAssertTrue(summary.contains("8 trials ran before it stopped"), summary)
    }

    func testAnErroredSummarySaysHowManyErrored() throws {
        let summary = try EvalFixtures.allErrored().commitSummary()
        XCTAssertTrue(summary.contains("8 of 8 trials errored"), summary)
    }

    /// A run that finished with failures in it says so on the same line, so a
    /// green word never travels alone.
    func testASuccessWithFailuresInItSaysSoOnTheSameLine() throws {
        let summary = try EvalFixtures.walkDiverged().commitSummary()
        XCTAssertTrue(summary.hasPrefix("Eval walk-under-a-forward-command: success"), summary)
        XCTAssertTrue(summary.contains("2 of 8 errored"), summary)
    }

    // MARK: - the repository

    /// A dataset and never a model. Their own Hub search proves the point:
    /// a measurement published as a model repository is one nobody's dataset
    /// search reaches.
    func testItPublishesADatasetAndNeverAModel() throws {
        let file = try EvalFixtures.workedExample()
        let repository = try file.repository(namespace: "craigm26")
        XCTAssertEqual(repository.kind, .dataset)
        XCTAssertEqual(repository.name, "microduck-studio-evals")
        XCTAssertEqual(repository.id, "craigm26/microduck-studio-evals")
        XCTAssertTrue(repository.webURL.contains("/datasets/"),
                      "the prefix a dataset needs, or the address opens a model")
    }

    func testTheThreeFilesAreTheLogTheReportAndTheCard() throws {
        let file = try EvalFixtures.workedExample()
        let files = file.files()
        XCTAssertEqual(files.map(\.path), [file.name, file.htmlName, "README.md"])
        XCTAssertTrue(files.allSatisfy(\.isText))
        XCTAssertEqual(files[0].contents, file.bytes, "the artefact goes as it was written")
        XCTAssertTrue(files.allSatisfy { $0.bytes > 0 })
    }

    /// L14: an imported log cannot be published from here at all, and the
    /// refusal is thrown rather than a hidden button.
    func testAnImportedLogCannotBePublished() throws {
        let file = try EvalFixtures.importedForeign()
        XCTAssertFalse(file.canPublish)
        XCTAssertThrowsError(try file.publishCalls(namespace: "craigm26", isPrivate: true)) {
            XCTAssertEqual($0 as? EvalLogFile.Refusal, .imported)
            XCTAssertEqual(EvalLogFile.Refusal.imported.message,
                           EvalLogFile.cannotPublishImported)
        }
    }

    // MARK: - the calls

    func testThePublishCallsCarryNoCredential() throws {
        let file = try EvalFixtures.workedExample()
        let calls = try file.publishCalls(namespace: "craigm26", isPrivate: false)
        XCTAssertEqual(calls.create.method, "POST")
        XCTAssertEqual(calls.commit.method, "POST")
        XCTAssertFalse(calls.create.displayURL.lowercased().contains("token"))
        XCTAssertFalse(calls.commit.displayURL.lowercased().contains("token"))
        XCTAssertTrue(calls.commit.displayURL.contains("/api/datasets/"),
                      "a commit to the wrong segment addresses a repository that is not there")
        let body = try XCTUnwrap(calls.create.body)
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(text.contains("cc-by-4.0"))
    }

    func testTheCommitSummaryIsTheOneOnTheCall() throws {
        let file = try EvalFixtures.workedExample()
        let calls = try file.publishCalls(namespace: "craigm26", isPrivate: true)
        let body = try XCTUnwrap(calls.commit.body)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body)
                                     as? [String: Any])
        XCTAssertEqual(json["summary"] as? String, file.commitSummary())
        XCTAssertEqual(json["description"] as? String, EvalReport.reproduceSaid(file.log))
        XCTAssertEqual((json["files"] as? [[String: Any]])?.count, 3)
    }

    // MARK: - the card

    func testTheCardCarriesEveryClaimItMustCarry() throws {
        let file = try EvalFixtures.workedExample()
        let card = file.card()
        let required: [(String, String)] = [
            ("licence header", "license: cc-by-4.0"),
            ("the task", file.log.eval.task),
            ("the status first", file.commitSummary()),
            ("reproduce", EvalReport.reproduceSaid(file.log)),
            ("the criterion label", EvalLogFile.criterionLabel),
            ("the criterion whole", EvalFixtures.criterion),
            ("the whole digest", EvalFixtures.plantDigest),
            ("no seed", EvalEpochs.noSeedSaid),
            ("step counts", EvalRun.stepCountsSaid),
            ("the trace", EvalTrace.firstDropOnlySaid),
            ("a verdict is not a score", EvalVerdict.recordedNotScoredSaid),
            ("no real duck", EvalEmbodiment.realMicroduckRefusal),
            ("how to read it", EvalLogFile.howToRead),
            ("independence", Provenance.independence),
            ("not their render", EvalText.notTheirRender),
        ]
        for (name, text) in required {
            XCTAssertTrue(card.contains(text), name)
        }
    }

    /// The challenge caveat is about playing a MOVE on hardware, so it belongs
    /// on a grid log and nowhere else; a walk log gets the refusal that fits.
    func testOnlyAGridCardCarriesTheChallengeCaveat() throws {
        let grid = try EvalFixtures.stairsMixed().card()
        XCTAssertTrue(grid.contains(StairsChallenge.realDuckCaveat))
        XCTAssertTrue(grid.contains(EvalReport.leaderboardIsTheChallengeScreen))
        let walk = try EvalFixtures.workedExample().card()
        XCTAssertFalse(walk.contains(StairsChallenge.realDuckCaveat))
        XCTAssertFalse(walk.contains(EvalReport.leaderboardIsTheChallengeScreen))
    }

    func testTheBallGridCardCarriesTheBallsOwnCaveat() throws {
        let card = try EvalFixtures.ballGrid().card()
        XCTAssertTrue(card.contains(BallChallenge.realDuckCaveat))
    }

    /// Nothing in the card may carry the word this app does not say, and the
    /// only em dashes in it are the bench's own, inside the quoted criterion.
    func testTheCardSaysNothingThisAppDoesNotSay() throws {
        for entry in try EvalFixtures.corpus() {
            let card = entry.file.card()
            XCTAssertFalse(card.uppercased().contains("RLHF"), entry.name)
            let withoutQuotes = card.split(separator: "\n")
                .filter { !$0.hasPrefix(">") }
                .joined(separator: "\n")
            XCTAssertFalse(withoutQuotes.contains("\u{2014}"),
                           "\(entry.name) has an em dash outside the quoted criterion")
        }
    }
}
