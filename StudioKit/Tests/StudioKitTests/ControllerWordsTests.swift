import XCTest
@testable import StudioKit

/// The controller's small rules: the venue-switch stick gate and the Auto goal cards.
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

    /// The phone driver is not installed in the app: its card says so and cannot start, on any
    /// duck. Never faked.
    func testThePhoneDriverIsHonestlyNotHereYet() {
        for duck in [DuckIdentity.Kind.sim, .real] {
            XCTAssertEqual(AutoGoal.walkToBall.availability(on: duck, driverInstalled: false),
                           .unavailable(AutoGoal.Words.notOnThisPhone))
        }
        XCTAssertEqual(AutoGoal.walkToBall.subtitle(on: .sim, driverInstalled: false),
                       AutoGoal.Words.notOnThisPhone)
    }

    /// Once a driver is on the phone it runs on the practice duck only.
    func testAnInstalledDriverIsPracticeDuckOnly() {
        XCTAssertEqual(AutoGoal.walkToBall.availability(on: .sim, driverInstalled: true), .ready)
        XCTAssertEqual(AutoGoal.walkToBall.availability(on: .real, driverInstalled: true),
                       .unavailable(AutoGoal.Words.trainedOnSim))
        XCTAssertEqual(AutoGoal.walkToBall.subtitle(on: .sim, driverInstalled: true),
                       AutoGoal.Words.practiceOnly)
    }

    /// Dream-1 runs on either duck; nothing runs with no duck.
    func testDreamRunsOnEitherDuckAndNothingRunsOnNone() {
        XCTAssertEqual(AutoGoal.dream.availability(on: .sim, driverInstalled: false), .ready)
        XCTAssertEqual(AutoGoal.dream.availability(on: .real, driverInstalled: false), .ready)
        for goal in AutoGoal.allCases {
            XCTAssertEqual(goal.availability(on: nil, driverInstalled: true),
                           .unavailable(AutoGoal.Words.noDuck))
        }
    }

    /// Both cards say where they run and that they are not Pollen's.
    func testEveryCardHasProvenance() {
        for goal in AutoGoal.allCases {
            XCTAssertTrue(goal.provenance.contains("Not made by Pollen"), goal.provenance)
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
