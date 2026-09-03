import XCTest
@testable import StudioKit

/// The two doors Control opens onto Studio, and what they are allowed to claim.
final class ControlShelfTests: XCTestCase {

    func testTheChipsAreTheTwoWordsTheScreenDraws() {
        XCTAssertEqual(ControlShelf.sceneChip, "Scene")
        XCTAssertEqual(ControlShelf.motionsChip, "Motions")
        XCTAssertEqual(ControlShelf.runItHere, "Run it here")
        XCTAssertEqual(ControlShelf.poseChip, "Pose")
        XCTAssertEqual(ControlShelf.whatHappened, "What happened")
    }

    /// The chip's second line is a readback or the bench's own world; it never
    /// invents a name for a world nobody set.
    func testTheStandingLineNamesTheWorldOrTheBenchsOwn() {
        XCTAssertEqual(ControlShelf.standingSaid("Stairs challenge, 60 mm"),
                       "Stairs challenge, 60 mm")
        XCTAssertEqual(ControlShelf.standingSaid(nil), "The bench's own world")
        XCTAssertEqual(ControlShelf.standingSaid(""), "The bench's own world")
    }

    /// A motion run from Control is a batch run, and every sentence about it
    /// says so rather than letting it read as a steering command.
    func testRunningAMotionIsSaidToStopTheDrive() {
        XCTAssertTrue(ControlShelf.runningStopsTheDrive.contains("stops driving"))
        XCTAssertTrue(ControlShelf.runningStopsTheDrive.contains("sticks come back"))
        XCTAssertTrue(ControlShelf.motionSheetSaid.contains("stops the drive loop"))
        XCTAssertEqual(ControlShelf.running("lever_up"), "Running lever_up on the bench…")
    }

    /// A batch run lays its own room and leaves the driven world standing —
    /// the fact `/perform` established, said where somebody presses Run.
    func testTheRoomAMotionRunsInIsItsOwnAndTheDrivenWorldIsLeftStanding() {
        XCTAssertTrue(ControlShelf.runsInItsOwnRoom.contains("room it was authored in"))
        XCTAssertTrue(ControlShelf.runsInItsOwnRoom.contains("left standing"))
        XCTAssertEqual(ControlShelf.authoredIn("Stairs challenge, 60 mm"),
                       "Authored in Stairs challenge, 60 mm, and that is the room it will lay "
                     + "for the run.")
        XCTAssertTrue(ControlShelf.authoredAnywhere.contains("bare floor"))
    }

    /// The same run on a pad button, named where somebody would look for it.
    func testTheButtonPathIsNamedAndIsTheSameRun() {
        XCTAssertTrue(ControlShelf.alsoOnAButton.contains("pad button"))
        XCTAssertTrue(ControlShelf.alsoOnAButton.contains("A press does what Run does here."))
    }

    func testEverySentenceSaysTheThingItIsFor() {
        for said in ControlShelf.everySentence {
            XCTAssertFalse(said.isEmpty)
            XCTAssertFalse(said.lowercased().contains("rlhf"))
        }
        // The four LABELS are labels — a chip and a button and a heading —
        // and the rest are sentences. A label with a full stop on a capsule
        // would be a sentence pretending to be a control.
        let labels = [ControlShelf.sceneChip, ControlShelf.poseChip, ControlShelf.motionsChip,
                      ControlShelf.runItHere, ControlShelf.whatHappened,
                      ControlShelf.holdIt, ControlShelf.keepItAsAMotion,
                      ControlShelf.doneposing, ControlShelf.posingNow]
        for said in labels { XCTAssertFalse(said.hasSuffix("."), said) }
        for said in ControlShelf.everySentence where !labels.contains(said) {
            XCTAssertTrue(said.hasSuffix(".") || said.hasSuffix("…"), said)
        }
        XCTAssertEqual(Set(ControlShelf.everySentence).count, ControlShelf.everySentence.count)
    }

    /// Posing sends nothing, and holding a pose is the batch door with the
    /// same promise about the sticks. Both said where somebody is posing.
    func testPosingSaysNothingIsSentAndHoldingSaysWhatItCosts() {
        XCTAssertTrue(ControlShelf.posingSaid.contains("Nothing is sent while you pose"))
        XCTAssertTrue(ControlShelf.holdingSaid.contains("stops driving"))
        XCTAssertTrue(ControlShelf.holdingSaid.contains("hands the sticks back"))
        XCTAssertEqual(ControlShelf.keptAsAMotion("Bow"),
                       "Kept as Bow. It is in Studio with the other motions, and it is on the "
                     + "Motions chip.")
        for label in [ControlShelf.holdIt, ControlShelf.keepItAsAMotion, ControlShelf.doneposing] {
            XCTAssertFalse(label.hasSuffix("."), label)
        }
    }

    /// The sentence that explains why a correct run looked like nothing
    /// happening: two ducks, and the picture was drawing the other one.
    func testTheRunSaysWhichDuckItWas() {
        XCTAssertTrue(ControlShelf.thisIsTheRun.contains("beside the duck you drive"))
        XCTAssertTrue(ControlShelf.thisIsTheRun.contains("frame for frame"))
    }
}
