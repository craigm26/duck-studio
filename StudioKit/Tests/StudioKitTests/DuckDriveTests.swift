import XCTest
import DuckKit
@testable import StudioKit

/// The stick-to-twist mapping, pinned against `padd/src/main.rs` in
/// pollen-robotics/microduck.
///
/// THE SIGNS ARE THE WHOLE POINT. Pollen's protocol fixes `vy` positive to the
/// LEFT and `vyaw` positive turning LEFT, while a stick pushed left reads
/// negative on every pad. Their own contract says the convention is written
/// down because the prototype grew five separate sign flags when it was not.
/// A mirrored duck is the failure these tests exist to catch.
final class DuckDriveTests: XCTestCase {

    private func twist(left: (Double, Double) = (0, 0),
                       right: (Double, Double) = (0, 0)) -> DuckDrive.Twist {
        DuckDrive.twist(for: .init(left: .init(x: left.0, y: left.1),
                                   right: .init(x: right.0, y: right.1)))
    }

    func testCentredSticksCommandNothing() {
        XCTAssertEqual(twist(), .still)
    }

    func testFullForwardIsPollensMaxLinear() {
        XCTAssertEqual(twist(left: (0, 1)).vx, 0.3, accuracy: 1e-12)
    }

    func testFullBackIsPollensBackwardLimit() {
        XCTAssertEqual(twist(left: (0, -1)).vx, -0.3, accuracy: 1e-12)
    }

    /// `vy: -left_x * max_linear`. Stick LEFT is negative x, and vy is positive
    /// to the left, so a leftward push must come out POSITIVE.
    func testPushingTheLeftStickLeftStrafesLeft() {
        XCTAssertEqual(twist(left: (-1, 0)).vy, 0.3, accuracy: 1e-12)
        XCTAssertEqual(twist(left: (1, 0)).vy, -0.3, accuracy: 1e-12)
    }

    /// `vyaw: -right_x * max_angular`, and positive vyaw turns left.
    func testPushingTheRightStickRightTurnsRight() {
        XCTAssertEqual(twist(right: (1, 0)).vyaw, -1.5, accuracy: 1e-12)
        XCTAssertEqual(twist(right: (-1, 0)).vyaw, 1.5, accuracy: 1e-12)
    }

    /// Turning is not limited to the walking range — it is 1.5 rad/s, five
    /// times the figure this file first guessed at.
    func testTurningIsNotClampedToTheForwardRange() {
        XCTAssertEqual(DuckDrive.maxTurn, 1.5)
        XCTAssertNotEqual(DuckDrive.maxTurn, DuckDrive.maxForward)
    }

    /// The right stick's y drives nothing here: `padd` spends it on head pose,
    /// in a mode this screen does not offer.
    func testTheRightSticksVerticalAxisIsUnused() {
        XCTAssertEqual(twist(right: (0, 1)), .still)
    }

    func testAThumbInsideTheDeadzoneReadsAsCentred() {
        XCTAssertEqual(twist(left: (0.09, 0.09), right: (0.09, 0)), .still)
        XCTAssertNotEqual(twist(left: (0, 0.11)), .still)
    }

    func testANonFiniteStickIsCentredRatherThanPropagated() {
        XCTAssertEqual(twist(left: (.nan, .infinity)), .still)
    }

    func testTheStickCannotAskForMoreThanFullDeflection() {
        XCTAssertEqual(twist(left: (0, 40)).vx, DuckDrive.maxForward, accuracy: 1e-12)
    }

    /// The gait's threshold, not the stick's — a small command makes the duck
    /// STAND, which looks like a fault and is not one.
    func testASmallCommandIsNamedAsStandingRatherThanLeftLookingBroken() {
        let creeping = DuckDrive.Twist(vx: 0.02, vy: 0, vyaw: 0)
        XCTAssertTrue(creeping.standsStill)
        XCTAssertTrue(DuckDrive.says(creeping).contains("standing policy takes over"))
        XCTAssertTrue(DuckDrive.says(creeping).contains("not a stall"))
    }

    func testARealWalkIsNotDescribedAsStanding() {
        let walking = DuckDrive.twist(for: .init(left: .init(x: 0, y: 1), right: .centred))
        XCTAssertFalse(walking.standsStill)
        XCTAssertFalse(DuckDrive.says(walking).contains("stall"))
    }

    /// `/intent`, `/stop`, `/policy` and `/reset` all answer with the same
    /// state block, and the mouth is in none of them.
    func testReadingLiveFillsTheMouthFromHomeRatherThanZero() throws {
        let joints = [Double](repeating: 0.25, count: DuckModel.policyJointCount)
        let body: [String: Any] = [
            "t": 1.5, "joints": joints, "height": 0.116, "upright": true,
            "position": [0.2, -0.1, 0.116], "quaternion": [1, 0, 0, 0],
            "policy": "alpha_walking", "command": ["vx": 0.3, "vy": 0.0, "vyaw": 0.0],
        ]
        let live = try DuckDrive.readLive(JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(live.stance.jointAngles.count, DuckModel.jointNames.count)
        XCTAssertEqual(live.stance.jointAngles[DuckModel.mouthIndex],
                       DuckModel.homePose[DuckModel.mouthIndex],
                       "a mouth no network drives must not be drawn hanging open")
        XCTAssertEqual(live.stance.jointAngles[0], 0.25)
        XCTAssertEqual(live.policy, "alpha_walking")
        XCTAssertEqual(live.command.vx, 0.3)
        XCTAssertTrue(live.upright)
    }

    func testTheBenchsOwnErrorIsCarriedRatherThanSwallowed() {
        let body = try! JSONSerialization.data(withJSONObject: ["error": "unknown policy: nope"])
        XCTAssertThrowsError(try DuckDrive.readLive(body)) {
            XCTAssertEqual($0 as? DuckBench.ReadError, .bench("unknown policy: nope"))
        }
    }

    /// The hold is what the bench takes, and the bench caps it at 2 s.
    func testTheHoldIsClampedToWhatTheBenchAccepts() throws {
        let address = DuckBench.Address(host: "127.0.0.1", port: 8770)
        let call = try DuckDrive.intent(address, .init(vx: 0.3, vy: 0, vyaw: 0), hold: 99)
        let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: call.body!) as? [String: Any])
        XCTAssertEqual(sent["hold"] as? Double, 2)
        XCTAssertEqual(sent["vx"] as? Double, 0.3)
        XCTAssertEqual(call.url.path, "/intent")
    }
}
