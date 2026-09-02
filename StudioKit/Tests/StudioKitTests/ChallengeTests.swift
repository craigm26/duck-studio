import XCTest
@testable import StudioKit

/// The list of challenges, which is what the challenge screen becomes.
final class ChallengeTests: XCTestCase {

    func testThereAreTwoAndTheStairsComeFirst() {
        XCTAssertEqual(Challenge.allCases, [.stairs, .ball])
        XCTAssertEqual(Challenge.allCases.map(\.name), ["Stairs", "Ball"])
        XCTAssertEqual(Challenge.allCases.map(\.id), ["stairs", "ball"])
    }

    /// EVERY MEMBER ANSWERS EVERY QUESTION, which is the point of the enum:
    /// the list screen has no `switch` in it and a third challenge is a case
    /// rather than a rewrite.
    func testEveryChallengeAnswersEveryQuestion() {
        for challenge in Challenge.allCases {
            XCTAssertFalse(challenge.title.isEmpty, challenge.rawValue)
            XCTAssertFalse(challenge.oneSentence.isEmpty, challenge.rawValue)
            XCTAssertFalse(challenge.criterion.isEmpty, challenge.rawValue)
            XCTAssertFalse(challenge.realDuckCaveat.isEmpty, challenge.rawValue)
            XCTAssertFalse(challenge.provenanceLead.isEmpty, challenge.rawValue)
            XCTAssertFalse(challenge.rowsSaid.isEmpty, challenge.rawValue)
            XCTAssertEqual(challenge.coreCount, 9, challenge.rawValue)
            XCTAssertEqual(challenge.cellCount, 14, challenge.rawValue)
            XCTAssertTrue(challenge.notYetHere(bench: "the Pi").contains("the Pi"))
            XCTAssertTrue(DuckBench.routes.contains(challenge.routes.score))
            XCTAssertTrue(DuckBench.routes.contains(challenge.routes.grid))
        }
    }

    /// THE TWO CRITERIA ARE THE BENCHES' OWN SENTENCES and they are not the
    /// same sentence. A screen that showed one for both would be labelling one
    /// challenge with the other's test.
    func testTheTwoCriteriaAreTheBenchesOwnAndAreDifferent() {
        XCTAssertNotEqual(Challenge.stairs.criterion, Challenge.ball.criterion)
        XCTAssertTrue(Challenge.stairs.criterion.hasPrefix("honest:"))
        XCTAssertTrue(Challenge.ball.criterion.hasPrefix("chased:"))
        // The stable clause is worded identically on purpose: a person who has
        // read one challenge already knows what the other one means.
        XCTAssertTrue(Challenge.stairs.criterion
            .contains("upright for at least 45 of the 50 tail ticks"))
        XCTAssertTrue(Challenge.ball.criterion
            .contains("upright for at least 45 of the 50 tail ticks"))
    }

    func testTheTwoRoutesAreTheOnesTheBenchAnswers() {
        XCTAssertEqual(Challenge.stairs.routes.score, "/climb")
        XCTAssertEqual(Challenge.stairs.routes.grid, "/climb/grid")
        XCTAssertEqual(Challenge.ball.routes.score, "/chase")
        XCTAssertEqual(Challenge.ball.routes.grid, "/chase/grid")
    }

    /// `isMeasured` IS COMPUTED, NEVER DECLARED. A constant saying "the ball
    /// challenge has no rows yet" would go on saying it for a build after the
    /// rows landed.
    func testWhetherAChallengeHasPublishedRowsIsReadOffItsLeaderboard() {
        XCTAssertEqual(Challenge.stairs.rowCount, StairsChallenge.leaderboard.count)
        XCTAssertEqual(Challenge.ball.rowCount, BallChallenge.leaderboard.count)
        XCTAssertTrue(Challenge.stairs.isMeasured)
        XCTAssertEqual(Challenge.ball.isMeasured, !BallChallenge.leaderboard.isEmpty)
        if BallChallenge.leaderboard.isEmpty {
            XCTAssertEqual(Challenge.ball.rowsSaid, BallChallenge.leaderboardPending)
        }
    }

    /// THE BALL LEADERBOARD IS FOUR CONTROLS AND NO ENTRIES, and it says that
    /// rather than ranking them. Ranking a control would put "walk forward and
    /// hope" at the top of a leaderboard for chasing.
    func testTheBallLeaderboardIsFourControlsAndNoEntries() {
        XCTAssertEqual(BallChallenge.leaderboard.count, 4)
        XCTAssertEqual(BallChallenge.entries, [])
        XCTAssertEqual(BallChallenge.controlRows.count, 4)
        for row in BallChallenge.leaderboard {
            XCTAssertNil(row.rank, row.file)
            XCTAssertTrue(row.isControl, row.file)
            XCTAssertEqual(row.sha256.count, 64, row.file)
            XCTAssertTrue(row.sha256.hasPrefix(row.hash), row.file)
        }
        XCTAssertEqual(BallChallenge.leaderboard.map(\.file),
                       BallChallenge.controls.map(\.file))
        for control in BallChallenge.controls { XCTAssertNotNil(control.row, control.file) }
    }

    /// THREE ZERO ROWS AND ONE THAT WALKS. That shape is the result, and it is
    /// the sentence the table is drawn under.
    func testTheMeasuredRowsAreTheOnesThePredictionsCalled() {
        let byFile = Dictionary(uniqueKeysWithValues: BallChallenge.leaderboard.map { ($0.file, $0) })
        for file in ["ctrl_do_nothing.json", "ctrl_ball_kick_left.json",
                     "ctrl_ball_kick_right.json"] {
            let row = byFile[file]!
            XCTAssertEqual(row.kChased, 0, file)
            XCTAssertEqual(row.kExt, 0, file)
            XCTAssertEqual(row.touchedCells, 0, file)
            XCTAssertEqual(row.maxBallTravelMillimetres, 0, file)
        }
        let walker = byFile["ctrl_alpha_walking.json"]!
        XCTAssertEqual(walker.kChased, 4)
        XCTAssertEqual(walker.kStable, 4)
        XCTAssertEqual(walker.kExt, 1)
        XCTAssertEqual(walker.touchedCells, 5)
        XCTAssertTrue(BallChallenge.leaderboardSaid.contains("4 of the 9 core cells"))
        XCTAssertTrue(BallChallenge.leaderboardSaid.contains("drifts about 15° right"))
        XCTAssertTrue(BallChallenge.leaderboardSaid.contains("misses the ball dead ahead at 0.70 and 0.95 m"))
        XCTAssertFalse(BallChallenge.leaderboardSaid.contains("unclaimed"))
        XCTAssertTrue(BallChallenge.walkerPredictionSaid.contains("the shape did not"))
        // The pending sentence still exists for a build with no rows, and is
        // not what the screen shows now.
        XCTAssertNotEqual(Challenge.ball.rowsSaid, BallChallenge.leaderboardPending)
    }

    /// THE FOUR CONTROLS CARRY THEIR EXPECTATION AND WHAT IT ESTABLISHES, so a
    /// run that disagrees is a finding to chase down rather than a number to
    /// write down.
    func testEveryControlDeclaresWhatItIsExpectedToDoAndWhyThatMatters() {
        XCTAssertEqual(BallChallenge.controls.count, 4)
        for control in BallChallenge.controls {
            XCTAssertFalse(control.expected.isEmpty, control.file)
            XCTAssertFalse(control.establishes.isEmpty, control.file)
            XCTAssertFalse(control.who.isEmpty, control.file)
        }
        let doNothing = BallChallenge.controls[0]
        XCTAssertTrue(doNothing.expected.contains("must fail every cell"))
        XCTAssertTrue(doNothing.establishes.contains("IS NOT A CHASING TEST"))
        XCTAssertTrue(BallChallenge.controls[3].establishes.contains("steering"))
    }

    func testTheChallengesShareTheOnePlantEveryClipClaimsToComeFrom() {
        XCTAssertEqual(BallChallenge.plantName, "scene.mjb")
        XCTAssertEqual(BallChallenge.plantDigest, StairsChallenge.plantDigest)
    }

    /// The bearing convention has to be on screen: a grid of ±20 with no
    /// stated sign is a grid nobody can reproduce.
    func testTheBearingConventionIsSaidAndPositiveIsLeft() {
        XCTAssertTrue(BallChallenge.bearingConvention.contains("LEFT"))
        XCTAssertEqual(BallChallenge.bearingSaid(20), "+20°")
        XCTAssertEqual(BallChallenge.bearingSaid(-40), "-40°")
        XCTAssertEqual(BallChallenge.bearingSaid(0), "0°")
        XCTAssertEqual(BallChallenge.rangeSaid(0.45), "0.45 m")
        XCTAssertEqual(BallChallenge.secondsSaid(5), "5 s")
        XCTAssertEqual(BallChallenge.secondsSaid(4.5), "4.5 s")
    }

    /// The reward is REPORTED and it is not the verdict, and the app says so
    /// where the nine terms are drawn.
    func testTheScreenSaysWhyTheRewardIsNotTheVerdict() {
        XCTAssertTrue(BallChallenge.whyNotTheReward.contains("not the verdict"))
        XCTAssertTrue(BallChallenge.whyNotTheReward.contains("stands beautifully still"))
    }
}
