import XCTest
@testable import StudioKit

final class DuckSheetTests: XCTestCase {

    /// Expert hides one section; a Mac has no room capture.
    func testSectionsFollowExpertAndPhone() {
        XCTAssertEqual(DuckSheet.sections(expert: false, phone: true),
                       [.yourDuck, .camera, .pollen, .connection, .details, .room, .siri, .add])
        XCTAssertEqual(DuckSheet.sections(expert: true, phone: true).last, .expert)
        XCTAssertFalse(DuckSheet.sections(expert: true, phone: false).contains(.room))
    }

    /// Every sentence is non-empty, has no em-dash, and never talks shop on the front door.
    func testTheWordsAreCleanAndNeverTalkShop() {
        for line in DuckSheet.allWords {
            XCTAssertFalse(line.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(line.contains("\u{2014}"), line)
            for shop in ["MuJoCo", "deadman", "policy", "Hugging Face"] {
                XCTAssertFalse(line.contains(shop), "\(shop) in \(line)")
            }
        }
        XCTAssertFalse(ImportLanding.addedLine("a plan").contains("\u{2014}"))
    }

    // MARK: the venue switch

    /// Only a person's pick switches the venue, and a switch closes the stick gate until the
    /// finger lifts.
    func testTheVenueSwitchesOnlyOnAnExplicitPickAndIsInputSafe() {
        var gate = StickGate()
        for cause in VenueRule.Cause.allCases where !cause.isExplicit {
            let out = VenueRule.request(.real, from: .sim, cause: cause, gate: &gate)
            XCTAssertEqual(out, .init(venue: .sim, switched: false), cause.rawValue)
            XCTAssertFalse(gate.waitingForLift, cause.rawValue)
        }
        for cause in [VenueRule.Cause.duckPill, .duckSheet, .onboarding] {
            var g = StickGate()
            let out = VenueRule.request(.real, from: .sim, cause: cause, gate: &g)
            XCTAssertEqual(out, .init(venue: .real, switched: true), cause.rawValue)
            XCTAssertTrue(g.waitingForLift, cause.rawValue)
            // The thumb still pushing from the practice duck is ignored...
            XCTAssertFalse(g.admits(centred: false))
            XCTAssertFalse(g.admits(centred: false))
            // ...until it lifts, and then the stick drives again.
            XCTAssertTrue(g.admits(centred: true))
            XCTAssertTrue(g.admits(centred: false))
        }
    }

    /// Asking for the venue already in force is not a switch, and the gate stays open.
    func testTheSameVenueIsNotASwitch() {
        var gate = StickGate()
        let out = VenueRule.request(.sim, from: .sim, cause: .duckPill, gate: &gate)
        XCTAssertEqual(out, .init(venue: .sim, switched: false))
        XCTAssertFalse(gate.waitingForLift)
    }

    /// Reconnect, a game, an import and a launch are never explicit.
    func testTheCausesThatMayNotSwitch() {
        XCTAssertEqual(VenueRule.Cause.allCases.filter { !$0.isExplicit },
                       [.reconnect, .game, .importFile, .launch])
    }

    // MARK: imports

    func testImportsLandInMovesOrStudioMake() {
        XCTAssertEqual(ImportLanding.landing(for: .init(plans: 1)), .moves)
        XCTAssertEqual(ImportLanding.landing(for: .init(sequences: 1)), .moves)
        XCTAssertEqual(ImportLanding.landing(for: .init(packs: 1)), .moves)
        XCTAssertEqual(ImportLanding.landing(for: .init(decks: 1)), .moves)
        XCTAssertEqual(ImportLanding.landing(for: .init(drafts: 1)), .studioMake)
        XCTAssertEqual(ImportLanding.landing(for: .init(drafts: 1, plans: 1)), .studioMake)
        XCTAssertEqual(ImportLanding.landing(for: .init(policies: 1)), .studioBehaviours)
        XCTAssertEqual(ImportLanding.landing(for: .init()), .stay)
    }
}
