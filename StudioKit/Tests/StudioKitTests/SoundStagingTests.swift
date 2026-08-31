import XCTest
import DuckKit
@testable import StudioKit

/// Duck Sounds arrives from an app that had a physics engine. What it looks
/// like here is decided by one function, so what that function claims about
/// itself is asserted rather than believed.
final class SoundStagingTests: XCTestCase {

    private func standingLegs() throws -> DuckTrajectory.Pose {
        try DuckTrajectory.bundled(.stand).pose(at: 0.4)
    }

    // MARK: - the head is the robot's own command, not an interpretation

    /// THE WHOLE CLAIM OF THIS TYPE. `DuckCommand.head` is four numbers that
    /// land on joints 5 to 8, so above the neck there is nothing to solve and
    /// nothing to approximate — what is drawn is what the servo is asked for.
    func testTheHeadJointsAreExactlyWhatTheCallCommands() throws {
        let pose = DuckPerformance.pose(.inquire, elapsed: 0.28)
        let stance = SoundStaging.stance(pose, legs: try standingLegs())
        let (neck, headPitch, headYaw, headRoll) = pose.command.head

        XCTAssertEqual(stance.jointAngles[5], neck, accuracy: 1e-12)
        XCTAssertEqual(stance.jointAngles[6], headPitch, accuracy: 1e-12)
        XCTAssertEqual(stance.jointAngles[7], headYaw, accuracy: 1e-12)
        XCTAssertEqual(stance.jointAngles[8], headRoll, accuracy: 1e-12)

        // And inquire is the tilt: the roll is what makes it a question.
        XCTAssertGreaterThan(headRoll, 0.2, "the tilt is the gesture")
    }

    func testTheBeakIsTheCommandedOpeningAndNotTheRecordingS() throws {
        let pose = DuckPerformance.pose(.alarm, elapsed: 0.04)
        let stance = SoundStaging.stance(pose, legs: try standingLegs())
        XCTAssertEqual(stance.jointAngles[DuckModel.mouthIndex], pose.mouthTarget, accuracy: 1e-12)
        XCTAssertGreaterThan(pose.mouth, 0.9, "alarm throws the beak wide")
    }

    /// A COMMANDED ANGLE IS A REQUEST. A servo that cannot reach a stop does
    /// not reach it, and drawing past one shows hardware doing what it would
    /// refuse to do.
    func testAHeadAngleCannotBeDrawnPastItsStop() throws {
        let absurd = DuckCommand(twist: (0, 0, 0), head: (9, 9, 9, 9),
                                 bodyZ: 0, bodyRoll: 0, bodyPitch: 0)
        let stance = SoundStaging.stance(.init(command: absurd, mouth: 0.5),
                                         legs: try standingLegs())
        for joint in 5...8 {
            let travel = DuckModel.jointRanges[joint]
            XCTAssertLessThanOrEqual(stance.jointAngles[joint], travel.upper + 1e-9,
                                     DuckModel.jointNames[joint])
        }
    }

    // MARK: - the legs are a recording and say so

    /// The legs come from the clip untouched. If this ever stops being true,
    /// the caveat this type prints stops being true with it.
    func testTheLegJointsAreTheRecordingUntouched() throws {
        let legs = try standingLegs()
        let stance = SoundStaging.stance(DuckPerformance.pose(.coo, elapsed: 0.6), legs: legs)
        for joint in [0, 1, 2, 3, 4, 10, 11, 12, 13, 14] {
            XCTAssertEqual(stance.jointAngles[joint], legs.jointAngles[joint], accuracy: 1e-12,
                           DuckModel.jointNames[joint])
        }
    }

    /// SIX OF THE SEVEN NEVER COMMAND A TWIST, so they stand. `wheee` is the
    /// only ride, and it clears the runtime's threshold by twelve times — this
    /// asserts the selection against `DuckGait.locomotion` rather than against
    /// a number written here.
    func testOnlyTheJoyRideSelectsTheWalkingRecording() {
        for sound in DuckSound.allCases where sound != .wheee {
            for part in sound.parts {
                let pose = DuckPerformance.pose(sound, elapsed: 0.1)
                XCTAssertEqual(SoundStaging.gait(for: pose), .stand, "\(sound) \(part)")
            }
        }
        let ride = DuckPerformance.timeline(for: .wheee, part: .loop).pose(at: 0.2)
        XCTAssertEqual(SoundStaging.gait(for: ride), .walk)
        XCTAssertGreaterThan(ride.command.twistMagnitude, DuckModel.standingThreshold)
    }

    /// A head sweep must not make the duck think it is walking — the runtime
    /// reads the twist alone, and this is the case that rule exists for.
    func testAHeadSweepDoesNotStartAWalk() {
        let sweeping = DuckCommand(twist: (0, 0, 0), head: (0, 0, 0.9, 0.3),
                                   bodyZ: 0, bodyRoll: 0, bodyPitch: 0)
        XCTAssertEqual(SoundStaging.gait(for: .init(command: sweeping, mouth: 0)), .stand)
    }

    // MARK: - the body offset

    func testTheBodySettleMovesTheTrunkByExactlyWhatWasCommanded() throws {
        let legs = try standingLegs()
        let pose = DuckPerformance.pose(.coo, elapsed: 0.6)
        let stance = SoundStaging.stance(pose, legs: legs)
        XCTAssertLessThan(pose.command.bodyZ, 0, "coo settles")
        XCTAssertEqual(stance.root.z, legs.z + pose.command.bodyZ, accuracy: 1e-12)
    }

    /// THE FLOOR IS WHERE THE FLOOR IS. A settle deeper than the duck is tall
    /// would put the feet under it.
    func testASettleCannotPushTheDuckThroughTheFloor() throws {
        let sunk = DuckCommand(twist: (0, 0, 0), head: (0, 0, 0, 0),
                               bodyZ: -10, bodyRoll: 0, bodyPitch: 0)
        let stance = SoundStaging.stance(.init(command: sunk, mouth: 0),
                                         legs: try standingLegs())
        XCTAssertGreaterThanOrEqual(stance.root.z, 0)
    }

    // MARK: - what it says about itself

    /// THE CAVEAT IS THE POINT. This app's ghost duck is careful to say a
    /// kinematic replay is not a simulation, and this screen is the one most
    /// likely to be mistaken for one — a duck that honks and moves looks alive.
    func testTheCaveatAdmitsTheLegsAreARecordingAndTheKneesAreWrong() {
        let s = SoundStaging.caveat
        XCTAssertTrue(s.contains("not a simulation"), s)
        XCTAssertTrue(s.contains("recording"), s)
        XCTAssertTrue(s.contains("right height with the wrong knees"), s)
        // And it must not undersell the half that IS exact.
        XCTAssertTrue(s.contains("exactly what the robot would be commanded"), s)
    }

    func testTheHeldCallsAreTheTwoThatAreHeld() {
        XCTAssertTrue(SoundStaging.isHeld(.wheee))
        XCTAssertFalse(SoundStaging.isHeld(.chirp))
        XCTAssertEqual(DuckSound.allCases.filter(SoundStaging.isHeld).count, 1,
                       "only wheee reports itself as held; coo is long, not held")
    }

    /// Every call produces a drawable duck at every moment of it — no NaN, no
    /// wrong joint count, nothing under the floor.
    func testEveryCallIsDrawableThroughoutItsWholeLength() throws {
        let legs = try standingLegs()
        for sound in DuckSound.allCases {
            for part in sound.parts {
                let timeline = DuckPerformance.timeline(for: sound, part: part)
                for step in 0...40 {
                    let t = timeline.duration * Double(step) / 40
                    let stance = SoundStaging.stance(timeline.pose(at: t), legs: legs)
                    XCTAssertEqual(stance.jointAngles.count, DuckModel.jointNames.count,
                                   "\(sound) \(part)")
                    XCTAssertTrue(stance.jointAngles.allSatisfy(\.isFinite), "\(sound) \(part) @\(t)")
                    XCTAssertGreaterThanOrEqual(stance.root.z, 0, "\(sound) \(part) @\(t)")
                }
            }
        }
    }
}
