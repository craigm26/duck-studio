import XCTest
@testable import StudioKit

/// The modes are the surface most able to overclaim, so their sentences are
/// asserted here rather than read on a phone.
final class LabCatalogueTests: XCTestCase {

    func testThePreambleSaysNoRobotIsInvolved() {
        let p = LabCatalogue.modesPreamble
        XCTAssertTrue(p.contains("No Microduck exists yet"), p)
        XCTAssertTrue(p.contains("Nothing in these modes is talking to a robot"), p)
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

    /// A ROW MAY BE MID-PORT, BUT ONLY ON PURPOSE AND ONLY BY NAME.
    ///
    /// This used to forbid `.portingFrom` outright, which was right while every
    /// planned port was finished and wrong the moment a fourth app — Duck
    /// Sounds — actually started folding in. The hazard it was written for is
    /// not the status; it is a row wearing it forever, because "being ported"
    /// reads as progress and costs nothing to leave in place.
    ///
    /// So the list is here rather than in the catalogue. Adding a row that
    /// claims to be mid-port means editing a test and saying which app, and
    /// finishing one means deleting a line — a row cannot drift into limbo
    /// quietly in either direction.
    func testOnlyTheRowsListedHereMayClaimToBeMidPort() {
        let expected: [String: String] = [:]
        var seen: [String: String] = [:]
        for mode in LabCatalogue.modes {
            if case .portingFrom(let app) = mode.status { seen[mode.name] = app }
        }
        XCTAssertEqual(seen, expected,
                       "either a row started claiming to be mid-port without being listed, or a "
                     + "listed one finished and this line should go")
    }

    /// AND A MID-PORT ROW IS NOT REACHABLE. `usable` is what the screen draws
    /// as tappable, and a row whose code has not arrived must not be in it —
    /// the whole point of the status is that the screen draws it disabled with
    /// the reason beside it.
    func testAModeStillBeingPortedIsNotOfferedAsUsable() {
        let usable = Set(LabCatalogue.usable.map(\.id))
        for mode in LabCatalogue.modes {
            if case .portingFrom = mode.status {
                XCTAssertFalse(usable.contains(mode.id), "\(mode.name) is tappable too early")
                XCTAssertNotNil(mode.status.reason, "and it must say why")
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

    /// The bench is the one thing in here that works today, and Studio > Modes
    /// is pointless if it is empty. If this fails somebody moved the bench out
    /// without moving anything in.
    func testTheLabHasSomethingAPersonCanOpen() {
        XCTAssertFalse(LabCatalogue.usable.isEmpty)
        // PINNED EXACTLY, because `StudioHubView.destination` switches on these ids
        // and its default branch is a refusal rather than a screen. A row that
        // became usable without a case would push an empty view; a case with
        // no row is dead code. Changing this line is how you notice.
        XCTAssertEqual(LabCatalogue.usable.map(\.id),
                       ["bench", "ghost", "soccer", "room", "sounds"])
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
