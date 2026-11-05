import XCTest
@testable import StudioKit

/// The controller's small rules: the venue-switch stick gate, Auto's goal card and the walk.
final class ControllerWordsTests: XCTestCase {

    /// After a venue switch the stick is ignored until the finger lifts: a held deflection does
    /// not drive the new duck, a centred sample opens the gate, and the next push drives.
    func testTheStickIsDeafUntilTheFingerLifts() {
        var gate = StickGate()
        XCTAssertTrue(gate.admits(centred: false), "before any switch the stick drives")
        gate.venueChanged()
        XCTAssertTrue(gate.waitingForLift)
        XCTAssertFalse(gate.admits(centred: false))
        XCTAssertFalse(gate.admits(centred: false), "still held, still ignored")
        XCTAssertTrue(gate.admits(centred: true))
        XCTAssertFalse(gate.waitingForLift)
        XCTAssertTrue(gate.admits(centred: false), "a fresh push drives")
    }

    /// Not on this device: the card says to get it, and it cannot start, on either duck.
    func testAPhoneDriverNotHereSaysGetIt() {
        let size = DriverRelease.walkToBall.size
        for duck in [DuckIdentity.Kind.sim, .real] {
            XCTAssertEqual(BallWalk.availability(on: duck, driverInstalled: false),
                           .unavailable(BallWalk.Words.getFirst(size)))
            XCTAssertEqual(BallWalk.line(on: duck, driverInstalled: false), BallWalk.Words.getFirst(size))
        }
        XCTAssertTrue(BallWalk.Words.getFirst(size).contains("4.4 MB"))
        XCTAssertTrue(BallWalk.Words.getFirst(size).contains("Tell"))
    }

    /// Once a driver is on the phone it runs on either duck, and with no duck it does not.
    func testAnInstalledDriverRunsOnEitherDuck() {
        for duck in [DuckIdentity.Kind.sim, .real] {
            XCTAssertEqual(BallWalk.availability(on: duck, driverInstalled: true), .ready)
            XCTAssertEqual(BallWalk.line(on: duck, driverInstalled: true), BallWalk.subtitle)
        }
        XCTAssertEqual(BallWalk.availability(on: nil, driverInstalled: true), .unavailable(AutoGoal.Words.noDuck))
    }

    /// Dream-1 runs on either duck; nothing runs with no duck.
    func testDreamRunsOnEitherDuckAndNothingRunsOnNone() {
        XCTAssertEqual(AutoGoal.dream.availability(on: .sim), .ready)
        XCTAssertEqual(AutoGoal.dream.availability(on: .real), .ready)
        for goal in AutoGoal.allCases {
            XCTAssertEqual(goal.availability(on: nil),
                           .unavailable(AutoGoal.Words.noDuck))
        }
    }

    /// Both cards say where they run and that they are not Pollen's.
    func testEveryCardHasProvenance() {
        for line in AutoGoal.allCases.map(\.provenance) + [BallWalk.provenance] {
            XCTAssertTrue(line.contains("Not made by Pollen"), line)
        }
    }

    /// The Moves and More sheets' words: plain, no em-dash, no engineering word.
    func testTheSheetWordsArePlain() {
        XCTAssertEqual(ControllerWords.movesSheet, "Moves")
        XCTAssertEqual(ControllerWords.more, "More")
        for line in ControllerWords.sheetWords {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("\u{2014}"), line)
            for shop in ["policy", "bench", "MuJoCo", "deadman"] {
                XCTAssertFalse(line.lowercased().contains(shop.lowercased()), "\(shop) in \(line)")
            }
        }
    }

    func testTheModesUseSymbolsNotColour() {
        XCTAssertEqual(ControlArbiter.Mode.allCases.map(ControllerWords.symbol),
                       ["gamecontroller.fill", "waveform", "sparkles"])
        XCTAssertEqual(ControlArbiter.Mode.allCases.map(ControllerWords.title), ["Drive", "Tell", "Auto"])
    }
}
