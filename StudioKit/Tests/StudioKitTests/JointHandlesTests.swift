import XCTest
import DuckKit
@testable import StudioKit

/// The 3D grab-handle geometry, proved before any gesture exists. Wrong
/// answers here become a handle that drags the wrong joint the wrong way.
final class JointHandlesTests: XCTestCase {

    func testEveryPolicyJointGetsAHandleAndTheMouthDoesNot() {
        let handles = JointHandles.handles(at: DuckModel.homePose)
        XCTAssertEqual(handles.count, DuckModel.policyJointCount)
        XCTAssertFalse(handles.contains { $0.name == "mouth" })
        // Every axis is unit length — a scaled axis scales every drag.
        for handle in handles {
            XCTAssertEqual(JointHandles.magnitude(handle.axis), 1.0, accuracy: 1e-9,
                           handle.name)
        }
    }

    /// A handle sits ON the robot: within its physical envelope in the model
    /// frame, not at the origin and not in another room.
    func testHandlesSitInsideTheRobotsEnvelope() {
        for handle in JointHandles.handles(at: DuckModel.homePose) {
            XCTAssertLessThan(abs(handle.pivot.x), 0.25, handle.name)
            XCTAssertLessThan(abs(handle.pivot.y), 0.25, handle.name)
            XCTAssertGreaterThan(handle.pivot.z, 0.0, handle.name)
            XCTAssertLessThan(handle.pivot.z, 0.40, handle.name)
        }
    }

    /// Moving a joint must not move its own pivot — the pivot is the hinge —
    /// while it MUST move everything downstream of it.
    func testAJointsOwnPivotIsItsFixedPoint() throws {
        let home = JointHandles.handles(at: DuckModel.homePose)
        var bent = DuckModel.homePose
        let hip = try XCTUnwrap(DuckModel.jointIndex(of: "left_hip_pitch"))
        bent[hip] += 0.5
        let after = JointHandles.handles(at: bent)

        let hipBefore = try XCTUnwrap(home.first { $0.name == "left_hip_pitch" })
        let hipAfter = try XCTUnwrap(after.first { $0.name == "left_hip_pitch" })
        XCTAssertEqual(hipBefore.pivot.x, hipAfter.pivot.x, accuracy: 1e-12)
        XCTAssertEqual(hipBefore.pivot.z, hipAfter.pivot.z, accuracy: 1e-12)

        let kneeBefore = try XCTUnwrap(home.first { $0.name == "left_knee" })
        let kneeAfter = try XCTUnwrap(after.first { $0.name == "left_knee" })
        let moved = JointHandles.magnitude(kneeAfter.pivot - kneeBefore.pivot)
        XCTAssertGreaterThan(moved, 0.01, "the knee hangs off the hip and must swing with it")
    }

    /// The axis is invariant under the joint's own angle — rotZ leaves Z fixed.
    func testTheAxisDoesNotChaseTheJointsOwnAngle() throws {
        var bent = DuckModel.homePose
        let knee = try XCTUnwrap(DuckModel.jointIndex(of: "left_knee"))
        bent[knee] += 0.8
        let before = try XCTUnwrap(JointHandles.handles(at: DuckModel.homePose)
            .first { $0.name == "left_knee" })
        let after = try XCTUnwrap(JointHandles.handles(at: bent)
            .first { $0.name == "left_knee" })
        XCTAssertEqual(JointHandles.dot(before.axis, after.axis), 1.0, accuracy: 1e-9)
    }

    /// A drag along the tangent turns the joint; the same drag along the AXIS
    /// does nothing. This is the pair of facts that makes a handle feel like a
    /// hinge rather than a trackball.
    func testDragAlongTheTangentTurnsAndAlongTheAxisDoesNot() throws {
        let handle = try XCTUnwrap(JointHandles.handles(at: DuckModel.homePose)
            .first { $0.name == "left_knee" })
        // Grab a point one arm's-length off the pivot, perpendicular to the axis.
        let arm = JointHandles.cross(handle.axis, DuckVector(0, 0, 1))
        let grabOffset = JointHandles.magnitude(arm) > 1e-6 ? arm : DuckVector(1, 0, 0)
        let grab = handle.pivot + DuckVector(grabOffset.x * 0.05, grabOffset.y * 0.05,
                                             grabOffset.z * 0.05)
        let tangent = JointHandles.cross(handle.axis, grab - handle.pivot)

        let turned = JointHandles.angleDelta(handle: handle, grab: grab, drag: tangent)
        XCTAssertGreaterThan(abs(turned), 0.01, "a tangent drag turns the joint")

        let alongAxis = JointHandles.angleDelta(
            handle: handle, grab: grab,
            drag: DuckVector(handle.axis.x * 0.05, handle.axis.y * 0.05, handle.axis.z * 0.05))
        XCTAssertEqual(alongAxis, 0, accuracy: 1e-9, "an axis drag means nothing to a hinge")
    }

    /// The small-arc approximation is calibrated: a drag equal in length to
    /// the arm, along the tangent, is one radian.
    func testTheDragToAngleScaleIsOneRadianPerArmLength() throws {
        let handle = try XCTUnwrap(JointHandles.handles(at: DuckModel.homePose)
            .first { $0.name == "right_hip_pitch" })
        let grab = handle.pivot + DuckVector(0.05, 0, 0)
        let arm = grab - handle.pivot
        var tangent = JointHandles.cross(handle.axis, arm)
        let scale = JointHandles.magnitude(arm) / JointHandles.magnitude(tangent)
        tangent = DuckVector(tangent.x * scale, tangent.y * scale, tangent.z * scale)
        let delta = JointHandles.angleDelta(handle: handle, grab: grab, drag: tangent)
        XCTAssertEqual(abs(delta), 1.0, accuracy: 1e-9)
    }

    /// A grab at the pivot has no arm: the answer is zero, not a spin to the
    /// travel stop off a near-zero division.
    func testAGrabAtThePivotMeansNothing() throws {
        let handle = try XCTUnwrap(JointHandles.handles(at: DuckModel.homePose).first)
        let delta = JointHandles.angleDelta(handle: handle, grab: handle.pivot,
                                            drag: DuckVector(1, 1, 1))
        XCTAssertEqual(delta, 0)
    }

    /// What the editor writes is clamped to the joint's real travel.
    func testTheDraggedAngleIsClampedToTravel() throws {
        let handle = try XCTUnwrap(JointHandles.handles(at: DuckModel.homePose)
            .first { $0.name == "left_knee" })
        let grab = handle.pivot + DuckVector(0.05, 0, 0)
        let arm = grab - handle.pivot
        let tangent = JointHandles.cross(handle.axis, arm)
        // A drag of a hundred arm-lengths asks for ~100 rad; travel is ±π/2.
        let huge = DuckVector(tangent.x * 100, tangent.y * 100, tangent.z * 100)
        let angle = JointHandles.dragged(handle: handle, grab: grab, drag: huge)
        XCTAssertTrue(angle == handle.lower || angle == handle.upper,
                      "a huge drag lands exactly on a stop, got \(angle)")
    }

    /// The two knees' axes point opposite ways — but NOT perfectly. The home
    /// stance rolls each hip 5° inward (hip_roll ±0.0873 rad) so the soles sit
    /// flat, which tilts each knee axis by the same 5°: measured, the dot
    /// product is −0.985 = cos(170°), ten degrees short of antiparallel and
    /// exactly 2 × 5°. A first cut of this test asserted −1.0 and failed on a
    /// correct robot.
    func testTheKneesAxesAreAntiparallelUpToTheStanceRoll() throws {
        let handles = JointHandles.handles(at: DuckModel.homePose)
        let left = try XCTUnwrap(handles.first { $0.name == "left_knee" })
        let right = try XCTUnwrap(handles.first { $0.name == "right_knee" })
        let dot = JointHandles.dot(left.axis, right.axis)
        XCTAssertEqual(dot, -cos(2 * 0.0873), accuracy: 1e-3,
                       "ten degrees short of antiparallel — the 5° inward stance, twice")
        XCTAssertLessThan(dot, -0.98)
    }
}
