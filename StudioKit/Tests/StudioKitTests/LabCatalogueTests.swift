import XCTest
@testable import StudioKit

/// The Lab is the surface most able to overclaim, so its sentences are asserted
/// here rather than read on a phone.
final class LabCatalogueTests: XCTestCase {

    func testThePreambleSaysNoRobotIsInvolved() {
        let p = LabCatalogue.preamble
        XCTAssertTrue(p.contains("No Microduck exists yet"), p)
        XCTAssertTrue(p.contains("Nothing in the Lab is talking to a robot"), p)
        // It names what DOES run, because "nothing is real" on its own tells a
        // person the app is a toy.
        XCTAssertTrue(p.contains("trained policy on this phone"), p)
        XCTAssertTrue(p.contains("physics bench"), p)
    }

    /// A row that cannot be opened must carry a reason, and a row that can must
    /// not carry one — the screen draws the reason, so a nil here is a row that
    /// goes dead silently.
    func testEveryUnusableModeSaysWhyAndEveryUsableOneDoesNot() {
        for mode in LabCatalogue.modes {
            if mode.status == .here {
                XCTAssertNil(mode.status.reason, mode.name)
            } else {
                let reason = try? XCTUnwrap(mode.status.reason)
                XCTAssertNotNil(reason, "\(mode.name) is not usable and says nothing about why")
                XCTAssertFalse(mode.status.reason!.isEmpty, mode.name)
            }
        }
    }

    /// NO ROW SAYS "COMING SOON". Three apps in this family were planned, gated
    /// and never written; a date-free promise is exactly what their rows would
    /// have carried for a year. Every reason names a cause instead.
    func testNoReasonIsAPromiseInsteadOfACause() {
        let banned = ["coming soon", "soon", "shortly", "in a future", "stay tuned", "watch this space"]
        for mode in LabCatalogue.modes {
            guard let reason = mode.status.reason?.lowercased() else { continue }
            for phrase in banned {
                XCTAssertFalse(reason.contains(phrase), "\(mode.name): \(reason)")
            }
        }
    }

    /// THE PORT IS DONE, SO NOTHING MAY CLAIM TO BE MID-PORT. `.portingFrom`
    /// stays in the enum because the next app to fold in will need it, but a
    /// row still wearing it after the code arrived is a row lying about itself.
    func testNothingIsStillClaimingToBeBeingPorted() {
        for mode in LabCatalogue.modes {
            if case .portingFrom(let app) = mode.status {
                XCTFail("\(mode.name) still says it is being ported from \(app)")
            }
        }
    }

    func testEveryModeIsDistinctAndSaysWhatItDoes() {
        XCTAssertEqual(Set(LabCatalogue.modes.map(\.id)).count, LabCatalogue.modes.count,
                       "two modes share an id, so a list would collapse them")
        for mode in LabCatalogue.modes {
            XCTAssertFalse(mode.name.isEmpty)
            XCTAssertFalse(mode.symbol.isEmpty)
            XCTAssertGreaterThan(mode.blurb.count, 40, "\(mode.name)'s blurb says nothing")
            // A blurb ends in a sentence, not a trailing clause.
            XCTAssertTrue(mode.blurb.hasSuffix("."), mode.name)
        }
    }

    /// The bench is the one thing in here that works today, and the Lab is
    /// pointless if it is empty. If this fails somebody moved the bench out
    /// without moving anything in.
    func testTheLabHasSomethingAPersonCanOpen() {
        XCTAssertFalse(LabCatalogue.usable.isEmpty)
        XCTAssertEqual(LabCatalogue.usable.map(\.id), ["bench", "ghost", "soccer", "room"])
    }

    func testTheRationaleNamesTheAppsThatFoldedIn() {
        let r = LabCatalogue.rationale
        for app in ["Duck Soccer", "Duckboard", "Duck Diary"] {
            XCTAssertTrue(r.contains(app), "\(app) missing from: \(r)")
        }
    }
}
