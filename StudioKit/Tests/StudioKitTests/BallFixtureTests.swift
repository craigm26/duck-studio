import XCTest
@testable import StudioKit

/// THE APP'S COPY AGAINST THE HARNESS'S OWN FILES, when the harness is checked
/// out beside this repository.
///
/// WHY THIS TEST EXISTS. Everything the ball challenge ships is a copy of
/// something `duck-sounds` owns: the four entrant files are its bytes, the
/// fourteen cells are `sim/chase_score.mjs`'s constants, the criterion is its
/// exported sentence, and every number in the leaderboard came out of
/// `chase/chase_controls-results.json`. A copy nobody checks is a copy that
/// drifts, and a drifted copy shows a number under a published row's name that
/// the run behind that row never produced.
///
/// AND WHY IT SKIPS RATHER THAN FAILING when `duck-sounds` is not beside this
/// repository: a phone build and a CI checkout of `duck-studio` alone are both
/// legitimate, and a test that failed there would train somebody to ignore it.
/// Every skip names exactly what was missing.
final class BallFixtureTests: XCTestCase {

    static var duckSounds: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // StudioKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // StudioKit
            .deletingLastPathComponent()   // duck-studio
            .deletingLastPathComponent()   // projects
            .appendingPathComponent("duck-sounds")
    }

    static var chase: URL { duckSounds.appendingPathComponent("chase") }

    func requireHarness() throws {
        guard FileManager.default.fileExists(atPath: Self.chase.path) else {
            throw XCTSkip("duck-sounds/chase is not checked out beside duck-studio "
                        + "(\(Self.chase.path)), so the harness's own files cannot be read")
        }
    }

    func file(_ name: String) throws -> Data {
        let url = Self.chase.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("\(url.path) does not exist yet")
        }
        return try Data(contentsOf: url)
    }

    // MARK: - the four entrant files

    /// THE BYTES, KEY FOR KEY AND DIGIT FOR DIGIT. `chase_controls-results.json`
    /// publishes each of these four under a sha256 of the entrant it read out
    /// of these files; an app whose copy differs is scoring a different entrant
    /// under a published row's name.
    ///
    /// THE FILE WINS. If this fails, `BallEntrants.swift` is what changes.
    func testTheBundledEntrantsAreTheHarnessesOwnBytes() throws {
        try requireHarness()
        for control in BallChallenge.controls {
            let theirs = try file(control.file)
            let ours = try XCTUnwrap(BallChallenge.Entrants.data(control.file))
            XCTAssertEqual(ours, theirs,
                           "\(control.file): the app's copy is not the harness's file. THE FILE "
                         + "WINS — update BallEntrants.swift, never the harness.")
        }
    }

    /// And they parse to the entrant the app believes they do.
    func testTheHarnessesEntrantsParseToWhatTheAppShows() throws {
        try requireHarness()
        for control in BallChallenge.controls {
            let entrant = try BallChallenge.Entrant.decode(try file(control.file))
            XCTAssertEqual(entrant.name, control.entrant.name, control.file)
            XCTAssertEqual(entrant.kind, control.entrant.kind, control.file)
            XCTAssertEqual(entrant.seconds, control.entrant.seconds, control.file)
            XCTAssertEqual(entrant.policy, control.entrant.policy, control.file)
            XCTAssertEqual(entrant.schedule, control.entrant.schedule, control.file)
            XCTAssertEqual(entrant.move?.keyframes.map(\.pose),
                           control.entrant.move?.keyframes.map(\.pose), control.file)
        }
    }

    // MARK: - the grid and the criterion

    /// THE PINNED GRID AND THE PINNED CRITERION AGAINST `chase_score.mjs`'S
    /// OWN. The app draws fourteen rows and prints a criterion sentence before
    /// the first request comes back; if either is not the harness's, it is
    /// describing a measurement nobody is making.
    func testTheGridAndCriterionAreChaseScoresOwn() throws {
        let source = Self.duckSounds.appendingPathComponent("sim/chase_score.mjs")
        guard let text = try? String(contentsOf: source, encoding: .utf8) else {
            throw XCTSkip("sim/chase_score.mjs is not checked out beside duck-studio "
                        + "(\(source.path)), so its constants cannot be read")
        }
        XCTAssertTrue(text.contains("export const BEARINGS = [-20, 0, 20];"),
                      "chase_score.mjs's BEARINGS are not the app's [-20, 0, 20]")
        XCTAssertTrue(text.contains("export const RANGES = [0.45, 0.70, 0.95];"),
                      "chase_score.mjs's RANGES are not the app's [0.45, 0.70, 0.95]")
        XCTAssertTrue(text.contains("export const TOUCH_MM = 3.0;"))
        XCTAssertTrue(text.contains("export const TRAVEL_MIN_MM = 100.0;"))
        XCTAssertTrue(text.contains("export const TAIL_TICKS = 50;"))
        XCTAssertTrue(text.contains("export const CRITERION_SENTENCE"))

        // The sentence itself, reassembled from the source's own concatenated
        // literals: the app must print the bench's words and not its own.
        let flattened = text
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "'\n  + '", with: "")
            .replacingOccurrences(of: "'\n  + '", with: "")
        XCTAssertTrue(flattened.contains(BallChallenge.criterionSentence),
                      "BallChallenge.criterionSentence is not chase_score.mjs's "
                    + "CRITERION_SENTENCE")
    }

    // MARK: - the measured leaderboard

    /// EVERY ROW OF `BallChallenge.leaderboard` AGAINST THE RUN THAT PRODUCED
    /// IT — digest, counts and facts, row by row. This is the sha-pinning: a
    /// row pinned by a twelve-character prefix is a row pinned by nothing, so
    /// the whole digest is compared.
    func testTheLeaderboardIsTheHarnessesOwnMeasuredRows() throws {
        try requireHarness()
        let json = try HarnessJSON.parse(try file("chase_controls-results.json"))

        XCTAssertEqual(json["plantDigest"]?.stringValue, BallChallenge.plantDigest)
        XCTAssertEqual(json["plantName"]?.stringValue, BallChallenge.plantName)
        XCTAssertEqual(json["criterion"]?.stringValue, BallChallenge.criterionSentence)

        // The grid the rows were produced on is the grid the app draws.
        let grid = (json["grid"]?.arrayValue ?? []).compactMap { row -> DuckBench.ChaseCell? in
            guard let bearing = row["bearing"]?.doubleValue,
                  let range = row["range"]?.doubleValue,
                  let drop = row["drop"]?.doubleValue,
                  let fmul = row["fmul"]?.doubleValue else { return nil }
            let tier = (row["tier"]?.stringValue)
                .flatMap(DuckBench.ChaseCell.Tier.init(rawValue:))
                ?? BallChallenge.Grid.tier(bearing: bearing, range: range, drop: drop, fmul: fmul)
            return DuckBench.ChaseCell(bearing: bearing, range: range, drop: drop, fmul: fmul,
                                       tier: tier)
        }
        XCTAssertEqual(grid, BallChallenge.Grid.fallback,
                       "chase_controls-results.json was scored over a different grid from the "
                     + "one the app draws")

        let measured = json["entrants"]?.arrayValue ?? json["leaderboard"]?.arrayValue ?? []
        XCTAssertEqual(measured.count, BallChallenge.leaderboard.count)
        for row in BallChallenge.leaderboard {
            guard let theirs = measured.first(where: {
                $0["source"]?.stringValue == row.file
            }) else {
                XCTFail("\(row.file) has no measured row in chase_controls-results.json")
                continue
            }
            XCTAssertEqual(theirs["sha256"]?.stringValue, row.sha256, row.file)
            XCTAssertEqual(theirs["entrant"]?.stringValue, row.hash, row.file)
            XCTAssertEqual(theirs["name"]?.stringValue, row.entrantName, row.file)
            XCTAssertEqual(theirs["kind"]?.stringValue, row.kind.rawValue, row.file)
            XCTAssertEqual(theirs["policy"]?.stringValue, row.policy, row.file)
            XCTAssertEqual(theirs["seconds"]?.doubleValue, row.seconds, row.file)
            XCTAssertEqual(Int(theirs["kChased"]?.doubleValue ?? -1), row.kChased, row.file)
            XCTAssertEqual(Int(theirs["kStable"]?.doubleValue ?? -1), row.kStable, row.file)
            XCTAssertEqual(Int(theirs["kExt"]?.doubleValue ?? -1), row.kExt, row.file)
            XCTAssertEqual(Int(theirs["touchedCells"]?.doubleValue ?? -1), row.touchedCells,
                           row.file)
            if let travel = theirs["maxBallTravel_mm"]?.doubleValue {
                XCTAssertEqual(travel, row.maxBallTravelMillimetres, row.file)
            }
            XCTAssertEqual(Int(theirs["nCore"]?.doubleValue ?? -1),
                           BallChallenge.Grid.coreCount, row.file)
        }
    }

    /// THE PREDICTIONS WERE WRITTEN BEFORE THE RUN, so whether they held is a
    /// fact this test can state. If one of these ever stops holding, that is a
    /// finding to chase down and not a number to quietly rewrite.
    func testEveryControlsDeclaredPredictionHeld() throws {
        try requireHarness()
        for control in BallChallenge.controls {
            let held = try XCTUnwrap(control.predictionHeld,
                                     "\(control.file) has no published row to check its "
                                   + "prediction against")
            if control.file == "ctrl_alpha_walking.json" {
                // THE FINDING, CHASED DOWN AND KEPT: the count held, the shape
                // did not. The prediction stays as it was written; the verdict
                // says both halves, and the screen draws that instead of a seal.
                XCTAssertFalse(held, "the walker's shape prediction is known not to hold")
                XCTAssertEqual(control.predictionSaid, BallChallenge.walkerPredictionSaid)
            } else {
                XCTAssertTrue(held,
                              "\(control.file) did not do what was predicted of it: "
                            + "\(control.expected)")
                XCTAssertEqual(control.predictionSaid, "The prediction held.")
            }
        }
    }
}
