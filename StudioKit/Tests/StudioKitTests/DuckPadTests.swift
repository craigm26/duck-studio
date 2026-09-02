import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// The pad mapping, pinned against `padd/src/main.rs` in
/// pollen-robotics/microduck.
///
/// ITS HEADER IS THE SPEC AND IT IS SHORT ENOUGH TO QUOTE:
///
///     Start        toggle the policy
///     Y (North)    head mode — sticks pose the head
///     B (East)     body-pose mode — sticks lean and crouch the standing robot
///     A (South)    ground pick
///     LB / RB      left / right kick
///     DPad-Down    sit ↔ stand
///     RT / LT      mouth (either trigger; the max wins)
///     Select, 2 s  sit down, then power off
///
/// Muscle memory is the reason to match it exactly.
final class DuckPadTests: XCTestCase {

    private func binding(_ control: DuckPad.Control) throws -> DuckPad.Binding {
        try XCTUnwrap(DuckPad.binding(for: control))
    }

    /// The face buttons load the slots `deploy/robotd.toml` names — the same
    /// skills `padd` triggers, reached the way a bench can reach them.
    func testTheFaceButtonsMapToTheSlotsPaddTriggers() throws {
        XCTAssertEqual(try binding(.a).here, .loadSlot(.groundPick))
        XCTAssertEqual(try binding(.x).here, .loadSlot(.roulade))
        XCTAssertEqual(try binding(.leftBumper).here, .loadSlot(.kickLeft))
        XCTAssertEqual(try binding(.rightBumper).here, .loadSlot(.kickRight))
        XCTAssertEqual(try binding(.dpadDown).here, .loadSlot(.sitstand))
    }

    func testTheSticksDrive() throws {
        XCTAssertEqual(try binding(.leftStick).here, .drive)
        XCTAssertEqual(try binding(.rightStick).here, .drive)
    }

    /// A CONTROL THAT CANNOT WORK MUST SAY SO. Every one of these is a real
    /// `padd` binding with no counterpart on a physics server, and each has to
    /// carry its own reason rather than being quietly absent.
    func testWhatABenchCannotDoIsNamedRatherThanHidden() throws {
        for control in [DuckPad.Control.y, .b, .start, .select, .dpadUp,
                        .leftTrigger, .rightTrigger] {
            let b = try binding(control)
            XCTAssertFalse(b.isLive, "\(control) should not be live against a bench")
            guard case .unsupported(let why) = b.here else {
                return XCTFail("\(control) has no reason attached")
            }
            XCTAssertFalse(why.isEmpty, "\(control) is dead with no explanation")
            XCTAssertFalse(b.onTheRobot.isEmpty, "\(control) must still say what the ROBOT does")
        }
    }

    /// The mouth is servo 9 and no network drives it — the app says this
    /// everywhere else, and the trigger binding must agree.
    func testTheTriggersExplainTheMouthTheSameWayTheRestOfTheAppDoes() throws {
        XCTAssertTrue(try binding(.rightTrigger).here == .unsupported(
            "The mouth is servo 9 and no network drives it. Nothing on a bench opens it."))
        XCTAssertEqual(DuckModel.mouthIndex, 9, "the sentence names the index; keep them together")
    }

    /// Stop and reset are the bench's, not the pad's, and are labelled so.
    func testTheBenchOnlyControlsDoNotClaimARobotBinding() throws {
        XCTAssertEqual(try binding(.dpadLeft).here, .stop)
        XCTAssertEqual(try binding(.dpadRight).here, .reset)
        XCTAssertEqual(try binding(.dpadLeft).onTheRobot, "—")
    }

    func testEveryControlWithABindingHasAFaceLabel() {
        for binding in DuckPad.bindings {
            XCTAssertFalse(binding.control.face.isEmpty)
        }
        XCTAssertEqual(DuckPad.binding(for: .a)?.control.face, "A")
        XCTAssertEqual(DuckPad.binding(for: .leftBumper)?.control.face, "LB")
    }

    func testLiveIsExactlyTheBindingsThatDoSomething() {
        XCTAssertEqual(Set(DuckPad.live.map(\.control)),
                       Set([.leftStick, .rightStick, .a, .x, .leftBumper, .rightBumper,
                            .dpadDown, .dpadLeft, .dpadRight]))
    }

    // MARK: - layers

    func testADriverStartsWithTelemetryAndNothingElseOnTop() {
        XCTAssertEqual(DuckPad.Layer.defaults, [])
        XCTAssertTrue(DuckPad.Layer.allCases.count > 1, "layers are worth toggling")
        for layer in DuckPad.Layer.allCases {
            XCTAssertFalse(layer.title.isEmpty)
            XCTAssertFalse(layer.detail.isEmpty, "a toggle nobody can explain is a toggle nobody uses")
        }
    }

    // MARK: - near a stop

    /// The failure this layer exists to make visible: the last-mile clone drove
    /// the neck to its -1.920 rad stop in 0.4 s and stayed there, and every
    /// number on screen looked plausible.
    func testAJointHeldAgainstItsStopIsReported() {
        var angles = DuckModel.homePose
        let neck = try! XCTUnwrap(DuckModel.jointNames.firstIndex(of: "neck_pitch"))
        angles[neck] = DuckModel.jointRanges[neck].lower
        let flagged = DuckPad.nearLimits(angles)
        XCTAssertTrue(flagged.contains { $0.name == "neck_pitch" }, "\(flagged.map(\.name))")
    }

    func testAHomePoseIsNotFlagged() {
        // HOME is the resting pose; if it tripped the warning the layer would
        // be noise from the first frame.
        XCTAssertTrue(DuckPad.nearLimits(DuckModel.homePose).isEmpty,
                      "\(DuckPad.nearLimits(DuckModel.homePose).map(\.name))")
    }

    func testTheMouthIsNeverFlaggedBecauseNoNetworkDrivesIt() {
        var angles = DuckModel.homePose
        angles[DuckModel.mouthIndex] = DuckModel.jointRanges[DuckModel.mouthIndex].lower
        XCTAssertFalse(DuckPad.nearLimits(angles).contains { $0.name == "mouth" })
    }

    func testAWrongLengthPoseIsRefusedRatherThanIndexed() {
        XCTAssertTrue(DuckPad.nearLimits([0, 0, 0]).isEmpty)
    }
}
