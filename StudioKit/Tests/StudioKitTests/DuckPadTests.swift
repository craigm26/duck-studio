import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// The pad mapping's shape. Each default against Pollen's source line is
/// `DuckPadDefaultsTests`; this file is about what the table promises beyond
/// the values.
final class DuckPadTests: XCTestCase {

    private func binding(_ control: DuckPad.Control) throws -> DuckPad.Binding {
        try XCTUnwrap(DuckPad.binding(for: control))
    }

    func testTheSticksDrive() throws {
        XCTAssertEqual(try binding(.leftStick).here, .drive)
        XCTAssertEqual(try binding(.rightStick).here, .drive)
    }

    /// A CONTROL THAT CANNOT WORK MUST SAY SO. Every one of these is a real
    /// Pollen binding with no counterpart on a physics server, and each has to
    /// carry its own reason rather than being quietly absent.
    func testWhatABenchCannotDoIsNamedRatherThanHidden() throws {
        for control in [DuckPad.Control.dpadRight, .dpadDown, .start, .select,
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

    /// The emotions and head mode are a real duck's: dead on the practice duck,
    /// and each says why.
    func testARealDucksControlsAreDeadOnTheBenchAndSaySo() throws {
        for control in [DuckPad.Control.y, .leftBumper, .rightBumper, .dpadUp] {
            XCTAssertFalse(try binding(control).isLive, "\(control)")
        }
        XCTAssertTrue(DuckPad.onlyOnARealDuck("excited").contains("real duck"))
        XCTAssertTrue(DuckPad.noHeadOnTheBench.contains("real duck"))
    }

    /// The mouth is servo 9 and no network drives it. The app says this
    /// everywhere else, and the trigger binding must agree.
    func testTheTriggersExplainTheMouthTheSameWayTheRestOfTheAppDoes() throws {
        XCTAssertTrue(try binding(.rightTrigger).here == .unsupported(
            "The mouth is servo 9 and no network drives it. Nothing on a bench opens it."))
        XCTAssertEqual(DuckModel.mouthIndex, 9, "the sentence names the index; keep them together")
    }

    /// Stop and reset are the bench's, not the pad's, and are labelled so.
    func testTheBenchOnlyControlsDoNotClaimARobotBinding() throws {
        XCTAssertEqual(try binding(.leftStickClick).here, .stop)
        XCTAssertEqual(try binding(.rightStickClick).here, .reset)
        XCTAssertEqual(try binding(.leftStickClick).onTheRobot, "—")
        XCTAssertEqual(try binding(.rightStickClick).onTheRobot, "—")
    }

    func testEveryControlWithABindingHasAFaceLabel() {
        for binding in DuckPad.bindings {
            XCTAssertFalse(binding.control.face.isEmpty)
        }
        XCTAssertEqual(DuckPad.binding(for: .a)?.control.face, "A")
        XCTAssertEqual(DuckPad.binding(for: .leftBumper)?.control.face, "LB")
        XCTAssertEqual(DuckPad.binding(for: .leftStickClick)?.control.face, "L3")
    }

    func testEveryControlHasExactlyOneRow() {
        XCTAssertEqual(DuckPad.bindings.count, DuckPad.Control.allCases.count)
        XCTAssertEqual(Set(DuckPad.bindings.map(\.control)), Set(DuckPad.Control.allCases))
    }

    func testLiveIsExactlyTheBindingsThatDoSomething() {
        XCTAssertEqual(Set(DuckPad.live.map(\.control)),
                       Set([.leftStick, .rightStick, .a, .b, .x,
                            .dpadLeft, .leftStickClick, .rightStickClick]))
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
