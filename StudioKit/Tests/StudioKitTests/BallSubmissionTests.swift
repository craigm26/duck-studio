import XCTest
@testable import StudioKit

/// What a ball-challenge submission carries, and what it says.
final class BallSubmissionTests: XCTestCase {

    static let date = Date(timeIntervalSince1970: 1_788_307_200)  // 2026-09-02

    func submission(entrant: BallChallenge.Entrant = BallChallenge.Entrants.alphaWalking,
                    chasedAtBearingZero: Bool = true,
                    row: BallChallenge.Row? = nil) throws -> BallChallenge.Submission {
        let cells = try BallChallenge.Grid.fallback.map { cell -> DuckBench.Chased in
            let ahead = cell.bearing == 0 && chasedAtBearingZero
            return try DuckBench.readChased(BallScoreTests.answer(
                cell: cell, seconds: entrant.seconds,
                travelLiteral: ahead ? "214.37158662135791" : "3.5",
                closest: ahead ? 1.25 : 402.0,
                touched: ahead, peak: ahead ? 0.83 : 0,
                chased: ahead, stable: ahead))
        }
        return BallChallenge.Submission(entrant: entrant,
                                        score: BallChallenge.Score(cells: cells),
                                        benchName: "This iPhone",
                                        row: row,
                                        appVersion: "1.1 (46)",
                                        date: Self.date)
    }

    /// THE BUNDLE NAMES ITS CHALLENGE. A bundle from this app can now be one
    /// of two things, and a reader who has to guess from the field names is a
    /// reader about to score it with the wrong harness.
    func testTheBundleSaysWhichChallengeItIs() throws {
        let json = try HarnessJSON.parse(try submission().bundle())
        XCTAssertEqual(json["kind"]?.stringValue, "microduck-ball-challenge-submission")
        XCTAssertEqual(json["challenge"]?.stringValue, "ball")
        XCTAssertEqual(Challenge(rawValue: "ball"), .ball)
    }

    /// THE ENTRANT TRAVELS WHOLE. A submission that carried a summary of the
    /// entrant instead of the entrant could not be re-scored, which is the
    /// only thing it is for.
    func testTheBundleCarriesTheEntrantVerbatim() throws {
        let entrant = BallChallenge.Entrants.alphaWalking
        let json = try HarnessJSON.parse(try submission(entrant: entrant).bundle())
        XCTAssertEqual(json["entrant"]?["file"], entrant.json)
        XCTAssertEqual(json["entrant"]?["kind"]?.stringValue, "policy")
        XCTAssertEqual(json["entrant"]?["name"]?.stringValue, entrant.name)
    }

    /// AND THE PER-CELL ANSWERS UNROUNDED. The bundle claims to carry the
    /// bench's own digits; a re-formatted `Double` agrees to fifteen places
    /// and not to seventeen.
    func testTheBundleCarriesTheBenchesOwnDigits() throws {
        let json = try HarnessJSON.parse(try submission().bundle())
        let cells = try XCTUnwrap(json["cells"]?.arrayValue)
        XCTAssertEqual(cells.count, 14)
        let chased = try XCTUnwrap(cells.first { $0["chased"]?.boolValue == true })
        XCTAssertEqual(chased["ballTravel_mm"]?.encoded(.compact),
                       Data("214.37158662135791".utf8))
        XCTAssertNotNil(chased["closest_mm"])
        XCTAssertNotNil(chased["ballNet_mm"])
        XCTAssertNotNil(chased["final_mm"])
        XCTAssertNotNil(chased["ballPeakSpeed_mps"])
        XCTAssertEqual(chased["terms"]?.arrayValue?.count, 9)
    }

    /// THE THREE REFUSALS TRAVEL WITH THE NINE TERMS. A reward table that
    /// quietly dropped them would be a different reward wearing this one's
    /// name.
    func testTheBundleCarriesTheRefusedTermsWithTheirReasons() throws {
        let json = try HarnessJSON.parse(try submission().bundle())
        let refused = try XCTUnwrap(json["refused"]?.arrayValue)
        XCTAssertEqual(refused.compactMap { $0["term"]?.stringValue },
                       ["support_foot_grounded", "self_collisions", "dof_pos_limits"])
        for entry in refused {
            XCTAssertFalse(entry["reason"]?.stringValue?.isEmpty ?? true)
        }
    }

    func testTheBundleCarriesBothCaveatsAndTheCriterion() throws {
        let json = try HarnessJSON.parse(try submission().bundle())
        XCTAssertEqual(json["caveat"]?.stringValue, BallChallenge.realDuckCaveat)
        XCTAssertEqual(json["ballCaveat"]?.stringValue, BallChallenge.ballCaveat)
        XCTAssertEqual(json["challengeInfo"]?["criterion"]?.stringValue,
                       BallChallenge.criterionSentence)
    }

    /// `howToRescore` NAMES `chase_robust`, not `robust`. Somebody handed this
    /// bundle and the stairs instruction would score a ball entrant with the
    /// stairs harness and get a refusal they could not read.
    func testHowToRescoreNamesTheBallHarness() throws {
        let how = BallChallenge.Submission.howToRescore
        XCTAssertTrue(how.contains("chase/chase_robust.mjs"), how)
        XCTAssertTrue(how.contains("entrant.json"), how)
        XCTAssertFalse(how.contains("climb/robust.mjs"), how)
        let json = try HarnessJSON.parse(try submission().bundle())
        XCTAssertEqual(json["challengeInfo"]?["howToRescore"]?.stringValue, how)
    }

    func testTheIssueTitleNamesTheEntrant() throws {
        let made = try submission()
        XCTAssertEqual(made.issueTitle, "Ball challenge: ctrl_alpha_walking")
        XCTAssertEqual(made.issueURL.path, "/craigm26/duck-sounds/issues/new")
    }

    func testTheIssueBodyCarriesTheVerdictTheFactsAndBothCaveats() throws {
        let body = try submission().issueBody
        XCTAssertTrue(body.contains("Chased the ball in 3 of 9 core cells"))
        XCTAssertTrue(body.contains("3/9 chased"))
        XCTAssertTrue(body.contains("Touched the ball in 6 of 14 cells"))
        XCTAssertTrue(body.contains("PLEASE ATTACH"))
        XCTAssertTrue(body.contains(BallChallenge.ballCaveat))
        XCTAssertTrue(body.contains(BallChallenge.realDuckCaveat))
        XCTAssertTrue(body.contains("chase/chase_robust.mjs"))
    }

    /// A RUN WITH A PROBLEM SAYS SO IN THE ISSUE ITSELF, rather than looking
    /// like a clean entry a maintainer has to catch.
    func testAProblemTravelsIntoTheIssueBody() throws {
        let body = try submission(chasedAtBearingZero: false).issueBody
        XCTAssertTrue(body.contains("never touched the ball"), body)
    }

    func testTheFilenameLeadsWithTheHash() throws {
        XCTAssertEqual(try submission().filename,
                       "microduck-ball-2f1c0d9ab4e6-4s-2026-09-02.json")
    }

    func testTheDatasetCardCarriesTheCriterionAndBothCaveats() throws {
        let card = try submission().card()
        XCTAssertTrue(card.contains("license: cc-by-4.0"))
        XCTAssertTrue(card.contains(BallChallenge.criterionSentence))
        XCTAssertTrue(card.contains(BallChallenge.ballCaveat))
        XCTAssertTrue(card.contains(BallChallenge.realDuckCaveat))
        XCTAssertTrue(card.contains("https://github.com/craigm26/duck-sounds"))
    }

    /// A DATASET, NEVER A MODEL, and to the ball repository rather than the
    /// stairs one.
    func testItPublishesToItsOwnDatasetRepository() throws {
        let (repository, create, commit) =
            try submission().publishCalls(namespace: "craigm26", isPrivate: true)
        XCTAssertEqual(repository.kind, .dataset)
        XCTAssertEqual(repository.name, "microduck-ball-challenge-submissions")
        XCTAssertNotEqual(repository.name,
                          StairsChallenge.Submission.defaultRepositoryName)
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(commit.method, "POST")
    }

    func testAStartingRowIsNamedInTheBody() throws {
        let row = BallScoreTests.row(kChased: 2)
        let body = try submission(row: row).issueBody
        XCTAssertTrue(body.contains("Started from `x.json` (published 2 of 9 chased)"), body)
    }
}
