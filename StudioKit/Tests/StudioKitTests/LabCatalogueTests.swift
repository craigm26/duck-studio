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

    /// ROOM CAPTURE IS THE ROW MOST ABLE TO OVERCLAIM, because what it produces
    /// looks like a room and is a handful of rectangles. It once said it turned
    /// the room into a scene, which it does not; then it said "real boxes at
    /// real dimensions", which is true of the numbers and silent about the
    /// shapes. This pins the whole sentence, because every clause in it is a
    /// claim about `DuckRoomReduction`: the floor is the lowest large-enough
    /// horizontal plane, everything else is a 20 mm slab, and `emit()` never
    /// reaches `SceneStore`.
    func testRoomCaptureSaysWhatTheGeometryActuallyIs() throws {
        let room = try XCTUnwrap(LabCatalogue.modes.first { $0.id == "room" })
        XCTAssertEqual(room.blurb,
            "Measures the flat surfaces ARKit finds around you and writes them out as "
            + "MuJoCo scene geometry for a simulator elsewhere: the lowest big-enough "
            + "horizontal surface becomes the floor, and every other surface becomes a "
            + "20 mm-thick box at the size and place it was seen. Boxes, not furniture "
            + "shapes. It does not yet become a scene this app can stand a duck in.")
    }

    func testTheRationaleNamesTheAppsThatFoldedIn() {
        let r = LabCatalogue.rationale
        for app in ["Duck Soccer", "Duckboard", "Duck Diary"] {
            XCTAssertTrue(r.contains(app), "\(app) missing from: \(r)")
        }
    }
}
