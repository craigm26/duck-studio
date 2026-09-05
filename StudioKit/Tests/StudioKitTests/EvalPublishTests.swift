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

    /// EVERY RUN GETS A FOLDER AND THE FRONT PAGE BELONGS TO NOBODY. All of
    /// these logs publish into one dataset, and the card used to be committed
    /// at the root: the second run's card replaced the first run's, so the
    /// repository described its newest log and every older one sat underneath
    /// it undescribed. A card is a claim about one measurement, so it lives
    /// beside that measurement.
    func testEachRunGetsItsOwnFolderAndTheRootCardIsStable() throws {
        let file = try EvalFixtures.workedExample()
        let files = file.files()
        XCTAssertEqual(files.map(\.path),
                       ["\(file.folder)/\(file.name)", "\(file.folder)/\(file.htmlName)",
                        "\(file.folder)/README.md", "README.md"])
        XCTAssertTrue(files.allSatisfy(\.isText))
        XCTAssertEqual(files[0].contents, file.bytes, "the artefact goes as it was written")
        XCTAssertTrue(files.allSatisfy { $0.bytes > 0 })
        XCTAssertEqual(files[2].contents, Data(file.card().utf8))

        // The root file is the same bytes whichever log is being published, so
        // a second publish cannot overwrite the first one's description.
        let other = try EvalFixtures.stairsMixed()
        XCTAssertEqual(files[3].contents, other.files()[3].contents)
        XCTAssertNotEqual(file.folder, other.folder)
        XCTAssertNotEqual(files[2].contents, other.files()[2].contents)
    }

    /// The front page says what the repository is and carries the claims that
    /// belong to all of it rather than to one run.
    func testTheRepositoryCardIsAnIndexAndNotAResult() {
        let card = EvalLogFile.repositoryCard()
        XCTAssertTrue(card.hasPrefix("---\nlicense: cc-by-4.0"), card)
        XCTAssertTrue(card.contains("One folder per run"), card)
        XCTAssertTrue(card.contains(EvalLogFile.howToRead))
        XCTAssertTrue(card.contains(Provenance.independence))
        XCTAssertTrue(card.contains(EvalText.notTheirRender))
        XCTAssertFalse(card.contains("success_at_end"), "no run's numbers on the front page")
        XCTAssertTrue(card.hasSuffix("\n"))
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
        XCTAssertEqual((json["files"] as? [[String: Any]])?.count, 4)
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

    /// QUOTED MEANS SOMEBODY SAID IT. The three bench readers default a
    /// missing criterion to one word of this app's own, so a bench that said
    /// nothing had "unstated" published under a label promising the bench's own
    /// words. A card with nothing to quote quotes nothing.
    func testACriterionNobodySaidIsNotQuotedAsTheBenchs() throws {
        let file = try EvalFixtures.workedExample()
        XCTAssertTrue(file.card().contains(EvalLogFile.criterionLabel))
        let spec = EvalLog.Spec(
            task: file.log.eval.task, policy: file.log.eval.policy,
            embodiment: file.log.eval.embodiment, created: file.log.eval.created,
            producer: file.log.eval.inspectRobotsVersion,
            policyConfig: file.log.eval.policyConfig.merging(
                [EvalMeta.criterion: .string(DuckBench.criterionUnstated)]) { _, new in new },
            embodimentInfo: file.log.eval.embodimentInfo,
            maxSteps: file.log.eval.maxSteps, maxSeconds: file.log.eval.maxSeconds)
        let log = EvalLog(status: file.log.status, eval: spec, results: file.log.results,
                          stats: file.log.stats, samples: file.log.samples, error: nil)
        let unstated = try EvalLogFile.onDisk(log.encoded(), named: file.name)
        XCTAssertNil(EvalReport.statedCriterion(log))
        XCTAssertFalse(unstated.card().contains(EvalLogFile.criterionLabel))
        XCTAssertFalse(unstated.card().contains(DuckBench.criterionUnstated))
        XCTAssertFalse(EvalReport.html(unstated).contains(DuckBench.criterionUnstated))
    }

    /// A GRID CARD SAYS WHAT A GRID DID. The three recording sentences used to
    /// go on every card whatever ran: a stairs card carried "the bench returns
    /// a trajectory for the first drop of each call", "one trial in eight is
    /// one a person could watch" and a step count sentence about traced
    /// episodes, over fourteen cells that recorded nothing and reported no
    /// ticks at all. The seed note had the same problem one line above it.
    func testAGridCardCarriesTheSentencesItsOwnRouteEarns() throws {
        let grid = try EvalFixtures.stairsMixed().card()
        XCTAssertTrue(grid.contains(EvalEpochs.noSeedOnAGridSaid))
        XCTAssertTrue(grid.contains(EvalTrace.noTraceOnAGridSaid))
        XCTAssertTrue(grid.contains(EvalRun.noStepsOnAGridSaid))
        XCTAssertFalse(grid.contains(EvalEpochs.noSeedSaid))
        XCTAssertFalse(grid.contains(EvalTrace.firstDropOnlySaid))
        XCTAssertFalse(grid.contains(EvalRun.stepCountsSaid))
        XCTAssertFalse(grid.contains(EvalVerdict.recordedNotScoredSaid),
                       "no verdict was offered on a cell nobody could watch")
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
