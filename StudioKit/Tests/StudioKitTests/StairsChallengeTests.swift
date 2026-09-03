import XCTest
import Crypto
@testable import StudioKit

/// The bundled challenge: the dataset's own bytes, and the typed leaderboard
/// checked against the markdown that ships beside it.
final class StairsChallengeTests: XCTestCase {

    // MARK: - the files are the dataset's, unchanged

    /// EVERY BUNDLED FILE, BY SHA-256, AGAINST THE PUBLISHED DATASET. Taken on
    /// 2026-09-02 from `duck-sounds/challenge`, which is what
    /// `huggingface.co/datasets/craigm26/microduck-stairs-challenge` carries.
    /// A file that drifts here is a move the leaderboard does not describe, and
    /// there is no way to notice that by looking at the app.
    static let digests: [String: String] = [
        "leaderboard.md": "4a6765931656d45e2993568326c7c1f34ce20313f47a769edd5544b6c96c6376",
        "best_r6_ceilvaultC_60mm.json":
            "bbb8e0eb7c41a65e23c0f53ecbc762e0ab25843fde65ec5da06b7a3a87f7c746",
        "best_r3_vault_60mm.json":
            "8a4d6100c5e5810e207c18529bf75418b56ab4cf502cb8b9337dcc72a4975445",
        "best_r3_vault_70mm.json":
            "2e96411b1ac30b3402ceb3a1167012614a126722e4685e2d1c167bdf617f369d",
        "best_r3_vault_80mm.json":
            "b571d21c60376f9ea02bb7523e6a0f7a5526fc17a214257a91b7eef928fc5e22",
        "best_r4_famA_60mm.json":
            "85d183d5d3780c9513a87e9ee205be730c61f0f4927a38bec56a0297c26a4602",
        "best_r6_ceilvaultB_60mm.json":
            "3e76ae623c9efc86618d6a6263073daab8965e14106cbcaff4e712f07e5b8f20",
        "best_r3_vault_50mm.json":
            "d8bafed50bf2b650c81601125accabaadb2a9a9457efe15e7455f4850588b746",
        "best_r3_vault_40mm.json":
            "76fb311f94464691a00d852f530e249f914bb5226b71f6789b9e9366ecaece6c",
        "best_r6_ceilvault_60mm.json":
            "846dda540ad54b0664c7b0538f06b2a0f068c59d80eb55e311f2b86153987542",
        "best_r2_vault_60mm.json":
            "1014643c36d0ce5b69e5eff39224d63704730820adbbc32fa5105f6f16437b80",
        "best_r2_vault_40mm.json":
            "1b36137c0ae7da874052bccb586e86017bcfada9ac4dd4880f826fa31b47d9f8",
        "best_r5_servo_60mm.json":
            "ced6e8857c7889396aa3b4c42cf3fe6918370364135a63891a011ba1615a16b2",
        "best_r5_servoland_kcore_60mm.json":
            "7096a3dcd6b0c3bd46fb773a55964dab2e2ba728e4a508c4e237966cfa96555a",
        "best_r4_famB_beat1_90mm.json":
            "0da45856af41478701aad33121d4dce50a075a3e39fa57fe27537141db39e55d",
        "best_r4_famB_beat1_120mm.json":
            "012e02aff41f52c0e89103b4f5a0e6d2b3dd966aac68d9f3464682045783b368",
        "best_r3_cornerclimb_180mm.json":
            "a69644a1033c62dc3738d75c4a82e76a8773576ba60abeaca57899281e45618a",
        "r4_ctrl_on_tread_60mm.json":
            "0612c37ba259d3533017ad9777e1c4c9ea2a68cb68ffbb3df292b79cd5c4d200",
        "r4_ctrl_on_tread_90mm.json":
            "4d3525c1eb8e493542a79f6bf702143ad8331f7e9e8cec8e9d6ba47eddb3885e",
        "ctrl_do_nothing.json":
            "08683d8434ec615fbf92bcf4ff071d66733852b767b19cb328d2298d381eb016",
    ]

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func testEveryBundledFileIsTheDatasetsOwnBytes() throws {
        for file in StairsChallenge.bundledFiles {
            let wanted = try XCTUnwrap(Self.digests[file], "\(file) has no pinned digest")
            XCTAssertEqual(Self.digest(try StairsChallenge.intentData(named: file)), wanted,
                           "\(file) is not the file the dataset publishes")
        }
        XCTAssertEqual(Self.digest(try StairsChallenge.leaderboardMarkdown()),
                       Self.digests["leaderboard.md"])
    }

    /// The pin list and the bundle are the same set. A digest for a file that
    /// no longer ships passes vacuously; a file that ships with no digest
    /// passes because nothing looked.
    func testThePinListAndTheBundleAreTheSameSet() {
        XCTAssertEqual(Set(StairsChallenge.bundledFiles),
                       Set(Self.digests.keys).subtracting(["leaderboard.md"]))
        XCTAssertEqual(StairsChallenge.bundledFiles.count, 19)
    }

    func testAMissingFileIsARefusalRatherThanACrash() {
        XCTAssertThrowsError(try StairsChallenge.intentData(named: "no_such_move")) {
            XCTAssertEqual($0 as? StairsChallenge.ResourceError, .missing("no_such_move"))
        }
    }

    /// Every row's `moveName` is the `name` INSIDE its file. Typed here so a
    /// screen can label a row without opening one, and checked so the label
    /// cannot become fiction.
    func testEveryRowsMoveNameIsTheOneInsideItsFile() throws {
        for row in StairsChallenge.leaderboard {
            let move = try StairsChallenge.move(for: row)
            XCTAssertEqual(move.name, row.moveName, "\(row.file)")
        }
    }

    // MARK: - the typed leaderboard against the shipped markdown

    /// EVERY COLUMN OF EVERY ROW, PARSED OUT OF `leaderboard.md`. The typed
    /// list is what the app draws and the markdown is the receipt; this is the
    /// only thing keeping them from drifting.
    func testTheTypedLeaderboardMatchesTheShippedTable() throws {
        let text = try XCTUnwrap(String(data: StairsChallenge.leaderboardMarkdown(),
                                        encoding: .utf8))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.hasPrefix("| ") }
        var seen = 0
        for row in StairsChallenge.leaderboard {
            let line = try XCTUnwrap(lines.first { $0.contains("intents/\(row.file)`") },
                                     "\(row.file) is not in leaderboard.md")
            seen += 1
            let cells = Self.cells(of: line)
            XCTAssertGreaterThanOrEqual(cells.count, 7, "\(row.file)")

            // rank
            XCTAssertEqual(cells[0], row.isControl ? "ctrl" : row.rankSaid, "\(row.file) rank")
            // hash
            XCTAssertEqual(Self.plain(cells[1]), row.hash, "\(row.file) hash")
            // rise
            XCTAssertEqual(cells[3], row.riseSaid, "\(row.file) rise")
            // "5 / 9 (kCore 5)" — or, for a control, just "9 / 9"
            let stableCell = Self.plain(cells[4])
            XCTAssertEqual(Self.firstInt(stableCell), row.kCoreStable, "\(row.file) kCoreStable")
            XCTAssertEqual(Self.int(after: "kCore", in: stableCell) ?? row.kCoreStable,
                           row.kCore, "\(row.file) kCore")
            // "5 (stable 5)"
            let extCell = Self.plain(cells[5])
            XCTAssertEqual(Self.firstInt(extCell), row.kExt, "\(row.file) kExt")
            XCTAssertEqual(Self.int(after: "stable", in: extCell), row.kExtStable,
                           "\(row.file) kExtStable")
            // "5 / 9" or "n/m"
            XCTAssertEqual(Self.firstInt(Self.plain(cells[6])), row.ceilingCore,
                           "\(row.file) ceilingCore")
            if !row.isControl {
                XCTAssertEqual(cells[7], row.who, "\(row.file) who")
                XCTAssertEqual(cells[8], row.scored, "\(row.file) scored")
            }
        }
        XCTAssertEqual(seen, 19)
    }

    /// The parser can fail. A cross-check that cannot is decoration.
    func testTheTableParserActuallyReadsTheTable() {
        let line = "| 1 | `a56d459fb649` | `intents/x.json` | 60 mm | **5** / 9 (kCore 4) "
                 + "| 3 (stable 2) | n/m | who | 2026-09-02 | note |"
        let cells = Self.cells(of: line)
        XCTAssertEqual(cells[0], "1")
        XCTAssertEqual(Self.plain(cells[1]), "a56d459fb649")
        XCTAssertEqual(Self.firstInt(Self.plain(cells[4])), 5)
        XCTAssertEqual(Self.int(after: "kCore", in: Self.plain(cells[4])), 4)
        XCTAssertEqual(Self.firstInt(Self.plain(cells[5])), 3)
        XCTAssertEqual(Self.int(after: "stable", in: Self.plain(cells[5])), 2)
        XCTAssertNil(Self.firstInt(Self.plain(cells[6])))
    }

    static func cells(of line: String) -> [String] {
        var parts = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "" { parts.removeFirst() }
        if parts.last == "" { parts.removeLast() }
        return parts
    }

    /// Markdown emphasis and code ticks are decoration, not data.
    static func plain(_ cell: String) -> String {
        cell.replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    static func firstInt(_ text: String) -> Int? {
        var digits = ""
        for character in text {
            if character.isNumber { digits.append(character) }
            else if !digits.isEmpty { break }
        }
        return Int(digits)
    }

    static func int(after word: String, in text: String) -> Int? {
        guard let range = text.range(of: word) else { return nil }
        return firstInt(String(text[range.upperBound...]))
    }

    // MARK: - the shape of the list

    func testTheRecordIsTheRoundSixCeilingVaultAndThereIsExactlyOne() {
        XCTAssertEqual(StairsChallenge.leaderboard.filter(\.isRecord).count, 1)
        XCTAssertEqual(StairsChallenge.record.hash, "a56d459fb649")
        XCTAssertEqual(StairsChallenge.record.kCoreStable, 5)
        XCTAssertEqual(StairsChallenge.record.rank, 1)
        // The record does not meet the bar, and the app must never imply it.
        XCTAssertLessThan(StairsChallenge.record.kCoreStable, StairsChallenge.bar)
    }

    func testTheRecordIsTheHighestRankedEntry() {
        let best = StairsChallenge.entries.map(\.kCoreStable).max()
        XCTAssertEqual(StairsChallenge.record.kCoreStable, best)
    }

    /// The controls are not entries and must never be ranked among them: one
    /// of them passes 9 of 9 by being spawned on the tread.
    func testTheControlsAreUnrankedAndOutsideTheEntries() {
        XCTAssertEqual(StairsChallenge.controls.count, 3)
        for control in StairsChallenge.controls {
            XCTAssertNil(control.rank)
            XCTAssertFalse(StairsChallenge.entries.contains(control))
        }
        XCTAssertEqual(StairsChallenge.entries.count, 16)
    }

    /// The two oracle rows out-score most of the entries and cannot be
    /// reproduced by anything a robot could run. They stay flagged.
    func testTheOracleRowsAreFlaggedAndUnranked() {
        let oracles = StairsChallenge.leaderboard.filter(\.isOracle)
        XCTAssertEqual(oracles.map(\.file),
                       ["best_r5_servo_60mm.json", "best_r5_servoland_kcore_60mm.json"])
        for oracle in oracles {
            XCTAssertNil(oracle.rank)
            XCTAssertEqual(oracle.kCoreStable, 0)
            XCTAssertTrue(oracle.note.contains("ORACLE"))
        }
    }

    func testRanksAreOneUpwardsWithNoGapsAndNoRepeats() {
        let ranks = StairsChallenge.leaderboard.compactMap(\.rank)
        XCTAssertEqual(ranks, Array(1...ranks.count))
    }

    func testLookupIsByFileBecauseThreeRowsShareAName() {
        XCTAssertEqual(StairsChallenge.row(file: "best_r3_vault_70mm.json")?.riseMillimetres, 70)
        XCTAssertNil(StairsChallenge.row(file: "nothing.json"))
        let shared = StairsChallenge.leaderboard
            .filter { $0.moveName == "beak_strut_vault_r6_ceiling_60mm" }
        XCTAssertEqual(shared.count, 3)
        XCTAssertEqual(Set(shared.map(\.id)).count, 3)
    }

    // MARK: - the sentences

    func testTheBarSentenceSaysTheBarStandsUnmet() {
        XCTAssertEqual(StairsChallenge.bar, 7)
        XCTAssertEqual(StairsChallenge.barSaid,
            "The bar is 7 of the 9 core cells, cleared and still standing. Nothing has met it: "
          + "the record is 5 of 9 at a 60 mm rise, and round six measured the trunk's peak "
          + "height as the reason 7 was never reachable at this scale.")
    }

    func testTheChallengeIsOneSentence() {
        XCTAssertEqual(StairsChallenge.oneSentence,
            "Get the duck from the floor onto a step in simulation and leave it standing "
          + "there — upright on the tread with both feet resting on it, fifty ticks after your "
          + "move ends.")
    }

    /// THE BUTTON PLAYS ON THE BENCH, and the sentence beside it says so:
    /// the app has no path to a real Microduck for a harness move yet.
    func testTheRealDuckCaveatSaysThePlayIsOnTheBenchAndHardwareIsNotWired() {
        XCTAssertEqual(StairsChallenge.realDuckCaveat,
            "This plays the move on the bench, in physics. Playing it on a real Microduck is not "
          + "wired in this build, a score exists only on a bench, and nothing here has been run on "
          + "hardware.")
        XCTAssertFalse(StairsChallenge.realDuckCaveat.contains("Send to the duck"))
    }

    /// The edit-score-keep loop's sentences, and the words never in them.
    func testTheEditLoopSentencesNameTheJudgeAndNotARewardModel() {
        XCTAssertTrue(StairsChallenge.editorNote.contains("Change any keyframe's servo values"))
        XCTAssertTrue(StairsChallenge.editedVersionNote.contains("Keep what scores better"))
        XCTAssertTrue(StairsChallenge.editedVersionNote.contains("There is no reward model"))
        XCTAssertFalse(StairsChallenge.editedVersionNote.contains("RLHF"))
        XCTAssertTrue(StairsChallenge.editedNotFoundNote.hasPrefix("Open the move in the editor first"))
        XCTAssertEqual(StairsChallenge.oracleWord, "Oracle")
        XCTAssertTrue(StairsChallenge.oracleNote.contains("not a move a Microduck could run"))
    }

    /// A bench that cannot do this NAMES ITSELF AND SAYS WHAT TO UPDATE.
    func testTheNotYetNamesTheBenchAndWhatToUpdate() {
        let said = StairsChallenge.noClimbHere(bench: "the Pi at 100.122.199.6:8770")
        XCTAssertEqual(said,
            "No /climb on the Pi at 100.122.199.6:8770. This bench answers /health and /perform "
          + "but not the stairs challenge, so nothing here can be scored on it. Pick a bench "
          + "that has it — this iPhone's own bench does, once the app is updated — or update "
          + "the Pi bench from github.com/craigm26/duck-sounds and restart it with "
          + "`systemctl --user restart duckbench`.")
        XCTAssertTrue(said.contains("the Pi at 100.122.199.6:8770"))
    }

    func testTheSameCriterionSentenceCarriesThePlantDigest() {
        XCTAssertEqual(StairsChallenge.sameCriterion(plantDigest: StairsChallenge.plantDigest),
            "This is the audit's criterion and grid, scored on this bench's plant 3f8c9ab9b409.")
        XCTAssertEqual(StairsChallenge.sameCriterion(plantDigest: nil),
            "This is the audit's criterion and grid, scored on this bench's plant, which it did "
          + "not identify.")
    }

    /// Every rise a published row was scored at is offered, so no row's
    /// screen shows a Score button that cannot score at that row's rise.
    func testTheRisesOfferedCoverEveryPublishedRow() {
        XCTAssertEqual(StairsChallenge.rises, [0.040, 0.050, 0.060, 0.070, 0.080, 0.090, 0.120, 0.180])
        for row in StairsChallenge.leaderboard {
            XCTAssertTrue(StairsChallenge.rises.contains { Int(($0 * 1000).rounded()) == row.riseMillimetres },
                          "\(row.file) is published at \(row.riseMillimetres) mm, which the picker does not offer")
        }
        XCTAssertEqual(StairsChallenge.defaultRise, 0.060)
        XCTAssertEqual(StairsChallenge.riseSaid(0.060), "60 mm")
    }

    // MARK: - one cell, said as one cell

    /// THE CELL `rig3` ITSELF RUNS is `fallback[3]`, not `[4]`: the grid
    /// iterates `for dh { for plant }`, so 0, 1 and 2 are dh −0.010.
    func testTheNominalCellIsTheOneRig3Runs() {
        let nominal = StairsChallenge.Grid.nominal
        XCTAssertEqual(nominal, StairsChallenge.Grid.fallback[3])
        XCTAssertEqual(nominal.dh, 0)
        XCTAssertEqual(nominal.drop, 0.120)
        XCTAssertEqual(nominal.fmul, 1.0)
        XCTAssertEqual(nominal.tier, .core)
        XCTAssertEqual(StairsChallenge.Grid.fallback.filter { $0 == nominal }.count, 1)
    }

    func testOneCellIsNeverSaidAsAScore() {
        XCTAssertTrue(StairsChallenge.oneCellIsNotAScore.contains("fourteen"))
        let cell = Pipeline.CellOutcome(
            when: Date(timeIntervalSince1970: 0), hash: "a56d459fb649", rise: 0.06,
            cell: StairsChallenge.Grid.nominal, honest: true, stable: true,
            reachedFlight: true, invalid: false, uprightTailTicks: 48, tailTicks: 50,
            aboveMillimetres: 116.17, peakAboveTreadMillimetres: 41.4,
            criterion: "honest: …")
        let said = StairsChallenge.oneCellSaid(cell)
        XCTAssertFalse(said.contains("of 9"))
        XCTAssertFalse(said.contains("Cleared"))
        XCTAssertTrue(said.contains("60/.120/x1.0 at 60 mm"), said)
        XCTAssertTrue(said.contains("41 mm above the tread against a 95 mm bar"), said)
        XCTAssertTrue(said.contains("48 of the last 50 ticks"), said)
    }

    /// AN UNSCORED CELL SAYS ONLY THAT AND WHY. Printing tread heights beside
    /// it would report an episode that never ran.
    func testACellOutsideItsOwnBoundsIsSaidAsUnscored() {
        let cell = Pipeline.CellOutcome(
            when: Date(timeIntervalSince1970: 0), rise: 0.06,
            cell: StairsChallenge.Grid.nominal, honest: false, stable: false,
            reachedFlight: false, invalid: true, uprightTailTicks: 0, tailTicks: 50,
            aboveMillimetres: 0, peakAboveTreadMillimetres: 0,
            why: "blend 2.6000 is outside [0.7, 2.4]", criterion: "honest: …")
        let said = StairsChallenge.oneCellSaid(cell)
        XCTAssertEqual(said, "60/.120/x1.0 at 60 mm: not scored: blend 2.6000 is outside "
                           + "[0.7, 2.4].")
        XCTAssertFalse(said.contains("bar"))
    }

    func testTheScoredRouteAndThePlayedRouteAreSaidApart() {
        let scored = StairsChallenge.scoredWhereItIsScored
        let played = StairsChallenge.performIsNotTheScore
        XCTAssertNotEqual(scored, played)
        XCTAssertFalse(scored.contains(played))
        XCTAssertFalse(played.contains(scored))
        XCTAssertTrue(scored.contains("climb_score.mjs"))
        XCTAssertTrue(played.contains("bare bench"))
        XCTAssertTrue(StairsChallenge.roomWasEdited.contains("cannot be scored"))
        XCTAssertTrue(StairsChallenge.authoredIntentDefaults.contains("blend 1, gap 0, side 0"))
        XCTAssertTrue(StairsChallenge.outsideTheScoredBox(param: "blend", value: 0.5,
                                                          low: 0.7, high: 2.4)
                        .contains("0.70"))
    }


    /// The tread under a point, by the harness's own geometry: the published
    /// placed spawn at x 0.212 is on the first tread, the floor is the floor,
    /// and in the overlap of two blocks the higher tread wins.
    func testTheTreadUnderAPointIsTheHarnessGeometry() {
        let h = StairsChallenge.Harness.self
        XCTAssertEqual(h.treadTop(atX: 0.212, rise: 0.06, stepCount: 4), 0.06, accuracy: 1e-12)
        XCTAssertEqual(h.treadTop(atX: 0.212, rise: 0.09, stepCount: 4), 0.09, accuracy: 1e-12)
        XCTAssertEqual(h.treadTop(atX: 0.05, rise: 0.06, stepCount: 4), 0)
        XCTAssertEqual(h.treadTop(atX: 0.42, rise: 0.06, stepCount: 4), 0.12, accuracy: 1e-12,
                       "0.42 is under both the first block (0.12-0.46) and the second (0.40-0.74)")
        XCTAssertEqual(h.treadTop(atX: 0.212, rise: 0.06, stepCount: 0), 0)
        XCTAssertEqual(h.treadTop(atX: 0.212, rise: 0.06, stepCount: 1) + DuckWorld.spawnHeight,
                       0.18, accuracy: 1e-12)
    }
}
