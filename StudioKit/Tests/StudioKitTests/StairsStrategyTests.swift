import XCTest
@testable import StudioKit

/// What a leaderboard row does, in one word — checked against the files the
/// rows are keyed by rather than against the table that describes them.
final class StairsStrategyTests: XCTestCase {

    /// EVERY ROW'S FAMILY IS ITS FILE'S FAMILY, BYTE FOR BYTE. The table is
    /// typed out in Swift and the files are the dataset's own bytes; this is
    /// the assertion that keeps the two from drifting.
    func testEveryRowsFamilyIsTheFilesFamily() throws {
        for row in StairsChallenge.leaderboard {
            let move = try StairsChallenge.move(for: row)
            XCTAssertEqual(row.family, move.family, row.file)
        }
    }

    /// Only the three controls have no family; every entry has one.
    func testOnlyTheControlsHaveNoFamily() {
        for row in StairsChallenge.entries {
            XCTAssertNotNil(row.family, row.file)
        }
        for row in StairsChallenge.controls {
            XCTAssertNil(row.family, row.file)
        }
    }

    /// Every row resolves, and no control ever wears an entry's badge.
    func testEveryRowResolvesAndNoControlWearsAnEntrysBadge() throws {
        let entryStrategies: Set<StairsChallenge.Strategy> = [
            .beakStrutVault, .ceilingVault, .eventLanding, .servoLanding,
            .twoBeat, .cornerClimb,
        ]
        for row in StairsChallenge.leaderboard {
            let strategy = try XCTUnwrap(row.strategy, row.file)
            if row.isControl {
                XCTAssertFalse(entryStrategies.contains(strategy), row.file)
            } else {
                XCTAssertTrue(entryStrategies.contains(strategy), row.file)
            }
        }
    }

    /// THE TWO "C"s ARE NOT THE SAME THING. "C beak-strut vault" and
    /// "C_whole_body_corner_climb_r3" share a letter and share nothing else, so
    /// the resolution has to read the whole string. A first cut that keyed on
    /// the family's leading token would pass every other test in this file.
    func testTheTwoCFamiliesAreDifferentStrategies() throws {
        let vault = try XCTUnwrap(StairsChallenge.row(file: "best_r2_vault_60mm.json"))
        let corner = try XCTUnwrap(StairsChallenge.row(file: "best_r3_cornerclimb_180mm.json"))
        XCTAssertEqual(vault.family?.prefix(1), "C")
        XCTAssertEqual(corner.family?.prefix(1), "C")
        XCTAssertEqual(vault.strategy, .beakStrutVault)
        XCTAssertEqual(corner.strategy, .cornerClimb)
        XCTAssertNotEqual(vault.strategy, corner.strategy)
    }

    /// Every published row, named. Written out so that adding a twentieth file
    /// is a decision somebody makes rather than a badge that appears.
    func testEveryFileIsTheStrategyItsFamilySays() throws {
        let expected: [String: StairsChallenge.Strategy] = [
            "best_r6_ceilvaultC_60mm.json": .ceilingVault,
            "best_r6_ceilvaultB_60mm.json": .ceilingVault,
            "best_r6_ceilvault_60mm.json": .ceilingVault,
            "best_r3_vault_40mm.json": .beakStrutVault,
            "best_r3_vault_50mm.json": .beakStrutVault,
            "best_r3_vault_60mm.json": .beakStrutVault,
            "best_r3_vault_70mm.json": .beakStrutVault,
            "best_r3_vault_80mm.json": .beakStrutVault,
            "best_r2_vault_40mm.json": .beakStrutVault,
            "best_r2_vault_60mm.json": .beakStrutVault,
            "best_r4_famA_60mm.json": .eventLanding,
            "best_r5_servo_60mm.json": .servoLanding,
            "best_r5_servoland_kcore_60mm.json": .servoLanding,
            "best_r4_famB_beat1_90mm.json": .twoBeat,
            "best_r4_famB_beat1_120mm.json": .twoBeat,
            "best_r3_cornerclimb_180mm.json": .cornerClimb,
            "r4_ctrl_on_tread_60mm.json": .placedSpawn,
            "r4_ctrl_on_tread_90mm.json": .placedSpawn,
            "ctrl_do_nothing.json": .doNothing,
        ]
        XCTAssertEqual(expected.count, StairsChallenge.leaderboard.count)
        for row in StairsChallenge.leaderboard {
            XCTAssertEqual(row.strategy, expected[row.file], row.file)
        }
    }

    /// NO CASE EXISTS THAT THE CORPUS CANNOT REACH. This is the test that
    /// refuses a block-push badge for an entrant nobody has submitted: add a
    /// case here without a file that resolves to it and this fails.
    func testEveryStrategyIsReachableFromTheBundledFiles() {
        let reachable = Set(StairsChallenge.leaderboard.compactMap(\.strategy))
        XCTAssertEqual(Set(StairsChallenge.Strategy.allCases).subtracting(reachable), [],
                       "a strategy no bundled entrant uses")
        XCTAssertEqual(reachable.count, StairsChallenge.Strategy.allCases.count)
    }

    /// The oracle word and the servoed-landing badge are the same fact said
    /// twice, so they had better agree: the two rows whose landing law reads
    /// the plant are exactly the two rows the table marks ORACLE.
    func testTheOracleRowsAreExactlyTheServoedLandings() {
        for row in StairsChallenge.leaderboard {
            XCTAssertEqual(row.isOracle, row.strategy == .servoLanding, row.file)
        }
        XCTAssertEqual(StairsChallenge.leaderboard.filter(\.isOracle).count, 2)
    }

    /// A LANDING LAW BEATS THE LAUNCH IT IS BOLTED ONTO. Both servo files and
    /// the event file say "beak-strut" in their family string; if the ladder
    /// read the launch first, all three would be labelled as the plain vault
    /// and the one thing worth knowing about them would vanish.
    func testALandingLawWinsOverTheLaunchItIsBoltedOnto() {
        let servoed = "Round 5: the round-3 beak-strut LAUNCH + a per-tick servoed landing "
                    + "(climb/servo.mjs)"
        XCTAssertTrue(servoed.lowercased().contains("beak-strut"))
        XCTAssertEqual(StairsChallenge.Strategy.of(family: servoed, hasEvent: false,
                                                   hasServo: true, hasSpawn: false,
                                                   isControl: false),
                       .servoLanding)
        let evented = "A beak-strut vault, event-triggered landing (round 4)"
        XCTAssertEqual(StairsChallenge.Strategy.of(family: evented, hasEvent: true,
                                                   hasServo: false, hasSpawn: false,
                                                   isControl: false),
                       .eventLanding)
        // And without either law, the same strings are the launch they name.
        XCTAssertEqual(StairsChallenge.Strategy.of(family: "A beak-strut vault (round 3)",
                                                   hasEvent: false, hasServo: false,
                                                   hasSpawn: false, isControl: false),
                       .beakStrutVault)
    }

    /// A family this build has never seen gets NO badge, not a guessed one.
    func testAnUnknownFamilyGetsNoBadge() {
        XCTAssertNil(StairsChallenge.Strategy.of(family: "D block push (round 9)",
                                                 hasEvent: false, hasServo: false,
                                                 hasSpawn: false, isControl: false))
        XCTAssertNil(StairsChallenge.Strategy.of(family: nil, hasEvent: false,
                                                 hasServo: false, hasSpawn: false,
                                                 isControl: false))
    }

    /// A control is a control before it is anything else.
    func testAControlIsReadAsAControlFirst() {
        XCTAssertEqual(StairsChallenge.Strategy.of(family: "A beak-strut vault (round 3)",
                                                   hasEvent: true, hasServo: true,
                                                   hasSpawn: true, isControl: true),
                       .placedSpawn)
        XCTAssertEqual(StairsChallenge.Strategy.of(family: nil, hasEvent: false,
                                                   hasServo: false, hasSpawn: false,
                                                   isControl: true),
                       .doNothing)
    }

    /// The words and pictures a row wears: one each, all different, and no
    /// wire names among them.
    func testEveryStrategyHasItsOwnWordGlyphAndSentence() {
        var words: Set<String> = []
        var glyphs: Set<String> = []
        for strategy in StairsChallenge.Strategy.allCases {
            XCTAssertFalse(strategy.word.isEmpty)
            XCTAssertFalse(strategy.word.contains("_"), strategy.word)
            XCTAssertLessThan(strategy.word.count, 20, strategy.word)
            XCTAssertTrue(words.insert(strategy.word).inserted, strategy.word)

            XCTAssertFalse(strategy.glyph.isEmpty)
            XCTAssertFalse(strategy.glyph.contains(" "), strategy.glyph)
            XCTAssertEqual(strategy.glyph, strategy.glyph.lowercased(), strategy.glyph)
            XCTAssertTrue(glyphs.insert(strategy.glyph).inserted, strategy.glyph)

            XCTAssertGreaterThan(strategy.whatItDoes.count, 40, strategy.rawValue)
            XCTAssertTrue(strategy.whatItDoes.hasSuffix("."), strategy.rawValue)
            XCTAssertFalse(strategy.whatItDoes.contains("_"), strategy.rawValue)
        }
    }

    /// The two sentences that must not soften: the servoed landing says it
    /// reads the simulator, and both controls say they are not a climb.
    func testTheSentencesThatMustNotSoften() {
        XCTAssertTrue(StairsChallenge.Strategy.servoLanding.whatItDoes
            .lowercased().contains("no robot can"))
        XCTAssertTrue(StairsChallenge.Strategy.placedSpawn.whatItDoes
            .lowercased().contains("not a climb"))
        XCTAssertTrue(StairsChallenge.Strategy.doNothing.whatItDoes
            .lowercased().contains("for free"))
    }

    /// The rise a scene is built at comes off the row, in the unit a scene
    /// wants it in.
    func testEveryRowsRiseInMetresMatchesItsMillimetres() {
        for row in StairsChallenge.leaderboard {
            XCTAssertEqual(row.riseMetres * 1000, Double(row.riseMillimetres), accuracy: 1e-9)
            XCTAssertTrue(StairsChallenge.rises.contains {
                abs($0 - row.riseMetres) < 1e-9
            }, "\(row.file) is scored at a rise the picker does not offer")
        }
    }
}
