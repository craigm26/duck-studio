import XCTest
import DuckKit
@testable import StudioKit

/// A person as points, read for angles — with the figures built by hand so
/// every expected angle is known before the code runs.
final class HumanFigureTests: XCTestCase {

    /// A person standing straight, 1.7 m tall, facing +z in a right-handed
    /// frame with y up and x to THEIR LEFT. Hips 0.3 m apart, arms hanging.
    private func standing() -> [HumanFigure.Joint: DuckVector] {
        [
            .root: DuckVector(0, 0, 0),
            .spine: DuckVector(0, 0.25, 0),
            .centerShoulder: DuckVector(0, 0.5, 0),
            .centerHead: DuckVector(0, 0.62, 0),
            .topHead: DuckVector(0, 0.75, 0),
            .leftShoulder: DuckVector(0.2, 0.5, 0),
            .leftElbow: DuckVector(0.22, 0.2, 0),
            .leftWrist: DuckVector(0.24, -0.08, 0),
            .rightShoulder: DuckVector(-0.2, 0.5, 0),
            .rightElbow: DuckVector(-0.22, 0.2, 0),
            .rightWrist: DuckVector(-0.24, -0.08, 0),
            .leftHip: DuckVector(0.15, 0, 0),
            .leftKnee: DuckVector(0.15, -0.45, 0),
            .leftAnkle: DuckVector(0.15, -0.9, 0),
            .rightHip: DuckVector(-0.15, 0, 0),
            .rightKnee: DuckVector(-0.15, -0.45, 0),
            .rightAnkle: DuckVector(-0.15, -0.9, 0),
        ]
    }

    private let tolerance = 1e-6

    func testTheFrameIsLeftUpForwardAndRightHanded() throws {
        let frame = try XCTUnwrap(HumanFigure(points: standing()).frame)
        XCTAssertEqual(frame.left.x, 1, accuracy: tolerance)
        XCTAssertEqual(frame.up.y, 1, accuracy: tolerance)
        // left × up = +z: the way this person faces.
        XCTAssertEqual(frame.forward.z, 1, accuracy: tolerance)
        XCTAssertEqual(frame.forward.x, 0, accuracy: tolerance)
        XCTAssertEqual(frame.forward.y, 0, accuracy: tolerance)
    }

    /// The frame follows the person, not the source's axes: the same body
    /// rotated a quarter turn about the vertical reads the same.
    func testTheFrameTurnsWithThePerson() throws {
        var turned: [HumanFigure.Joint: DuckVector] = [:]
        for (joint, p) in standing() { turned[joint] = DuckVector(p.z, p.y, -p.x) }
        let reading = try XCTUnwrap(HumanFigure(points: turned).reading)
        let straight = try XCTUnwrap(HumanFigure(points: standing()).reading)
        XCTAssertEqual(reading, straight)
        // (x, y, z) → (z, y, -x) takes +x to -z, so left is now -z and
        // forward = left × up = +x: the person turned with their points.
        let frame = try XCTUnwrap(HumanFigure(points: turned).frame)
        XCTAssertEqual(frame.forward.x, 1, accuracy: tolerance)
        XCTAssertEqual(frame.left.z, -1, accuracy: tolerance)
    }

    func testStandingStraightReadsAsZeroEverywhere() throws {
        let reading = try XCTUnwrap(HumanFigure(points: standing()).reading)
        for leg in [reading.left, reading.right] {
            XCTAssertEqual(leg.hipFlexion, 0, accuracy: tolerance)
            XCTAssertEqual(leg.kneeFlexion, 0, accuracy: tolerance)
            XCTAssertEqual(leg.abduction, 0, accuracy: tolerance)
        }
        XCTAssertEqual(reading.head.pitch, 0, accuracy: tolerance)
        XCTAssertEqual(reading.head.yaw, 0, accuracy: tolerance)
        XCTAssertEqual(reading.head.roll, 0, accuracy: tolerance)
        XCTAssertEqual(reading.armRaise, 0, accuracy: tolerance)
    }

    /// A thigh swung forward 45° with the shank hanging straight down reads as
    /// 45° of hip flexion and 45° of knee flexion — and only on that leg.
    func testAThighForwardIsHipFlexionAndABentKneeIsKneeFlexion() throws {
        var points = standing()
        let thigh = 0.45
        points[.leftKnee] = DuckVector(0.15, -thigh * cos(.pi / 4), thigh * sin(.pi / 4))
        points[.leftAnkle] = DuckVector(0.15, -thigh * cos(.pi / 4) - 0.45, thigh * sin(.pi / 4))
        let reading = try XCTUnwrap(HumanFigure(points: points).reading)
        XCTAssertEqual(reading.left.hipFlexion, .pi / 4, accuracy: tolerance)
        XCTAssertEqual(reading.left.kneeFlexion, .pi / 4, accuracy: tolerance)
        XCTAssertEqual(reading.left.abduction, 0, accuracy: tolerance)
        XCTAssertEqual(reading.right.hipFlexion, 0, accuracy: tolerance)
        XCTAssertEqual(reading.right.kneeFlexion, 0, accuracy: tolerance)
    }

    /// A thigh swung backwards is negative flexion.
    func testAThighBehindIsNegativeFlexion() throws {
        var points = standing()
        points[.rightKnee] = DuckVector(-0.15, -0.4, -0.2)
        points[.rightAnkle] = DuckVector(-0.15, -0.8, -0.4)
        let reading = try XCTUnwrap(HumanFigure(points: points).reading)
        XCTAssertLessThan(reading.right.hipFlexion, -0.4)
        XCTAssertEqual(reading.right.kneeFlexion, 0, accuracy: tolerance)
    }

    /// Both legs out to the side is positive on BOTH — outward is outward for
    /// each leg, not "toward +x".
    func testAStarJumpIsPositiveAbductionOnBothLegs() throws {
        var points = standing()
        points[.leftKnee] = DuckVector(0.15 + 0.3, -0.35, 0)
        points[.leftAnkle] = DuckVector(0.15 + 0.6, -0.7, 0)
        points[.rightKnee] = DuckVector(-0.15 - 0.3, -0.35, 0)
        points[.rightAnkle] = DuckVector(-0.15 - 0.6, -0.7, 0)
        let reading = try XCTUnwrap(HumanFigure(points: points).reading)
        XCTAssertGreaterThan(reading.left.abduction, 0.5)
        XCTAssertGreaterThan(reading.right.abduction, 0.5)
        XCTAssertEqual(reading.left.abduction, reading.right.abduction, accuracy: tolerance)
        XCTAssertEqual(reading.left.hipFlexion, 0, accuracy: tolerance)
    }

    /// A head nodded forward: the crown moves toward +forward.
    func testANodForwardIsPositivePitch() throws {
        var points = standing()
        points[.topHead] = DuckVector(0, 0.62 + 0.13 * cos(0.3), 0.13 * sin(0.3))
        let reading = try XCTUnwrap(HumanFigure(points: points).reading)
        XCTAssertEqual(reading.head.pitch, 0.3, accuracy: tolerance)
        // No rotations were given, so no turn and no tilt are claimed.
        XCTAssertEqual(reading.head.yaw, 0)
        XCTAssertEqual(reading.head.roll, 0)
    }

    /// A head turned to the person's left, given as a rotation of the head
    /// joint relative to the torso joint, reads as positive yaw — whatever
    /// axes the source used, because both joints share them.
    func testATurnToTheLeftIsPositiveYawFromTheJointRotations() throws {
        let angle = 0.4
        // Rotation about +y (up) by `angle`, in the points' coordinates.
        let aboutUp = HumanFigure.Rotation(rowMajor: [
            cos(angle), 0, sin(angle),
            0, 1, 0,
            -sin(angle), 0, cos(angle),
        ])
        let figure = HumanFigure(points: standing(), headRotation: aboutUp,
                                 torsoRotation: .identity)
        let reading = try XCTUnwrap(figure.reading)
        // forward is +z; rotating +z about +y by a positive angle moves it
        // toward +x, which is this person's left.
        XCTAssertEqual(reading.head.yaw, angle, accuracy: tolerance)
        XCTAssertEqual(reading.head.roll, 0, accuracy: tolerance)

        // The same head rotation with the torso ALSO turned reads as no turn:
        // the head is measured against the shoulders.
        let same = HumanFigure(points: standing(), headRotation: aboutUp, torsoRotation: aboutUp)
        XCTAssertEqual(try XCTUnwrap(same.reading).head.yaw, 0, accuracy: tolerance)
    }

    func testATiltToTheLeftIsPositiveRoll() throws {
        let angle = 0.25
        // Rotation about +z (forward): +y (up) moves toward -x for a positive
        // angle in a right-handed frame, so tilt the other way to get +x.
        let aboutForward = HumanFigure.Rotation(rowMajor: [
            cos(angle), sin(angle), 0,
            -sin(angle), cos(angle), 0,
            0, 0, 1,
        ])
        let figure = HumanFigure(points: standing(), headRotation: aboutForward,
                                 torsoRotation: .identity)
        let reading = try XCTUnwrap(figure.reading)
        XCTAssertEqual(reading.head.roll, angle, accuracy: tolerance)
        XCTAssertEqual(reading.head.yaw, 0, accuracy: tolerance)
    }

    /// A hand at the shoulder is 0, straight up is 1, and nothing goes past
    /// either end.
    func testTheHigherHandSetsTheArmRaise() throws {
        var points = standing()
        points[.rightElbow] = DuckVector(-0.2, 0.8, 0)
        points[.rightWrist] = DuckVector(-0.2, 1.08, 0)
        let up = try XCTUnwrap(HumanFigure(points: points).reading)
        XCTAssertEqual(up.armRaise, 1, accuracy: tolerance)

        points[.rightElbow] = DuckVector(-0.2, 0.65, 0.26)
        points[.rightWrist] = DuckVector(-0.2, 0.79, 0.5)
        let half = try XCTUnwrap(HumanFigure(points: points).reading)
        XCTAssertEqual(half.armRaise, 0.5, accuracy: 1e-2)
        XCTAssertEqual(try XCTUnwrap(HumanFigure(points: standing()).reading).armRaise, 0)
    }

    /// A joint the model could not see reads as that leg standing, never as a
    /// failure — the duck is already standing.
    func testAMissingAnkleReadsAsAStraightKneeAndAMissingKneeAsStanding() throws {
        var points = standing()
        points[.leftKnee] = DuckVector(0.15, -0.3, 0.3)
        points[.leftAnkle] = nil
        let noAnkle = try XCTUnwrap(HumanFigure(points: points).reading)
        XCTAssertGreaterThan(noAnkle.left.hipFlexion, 0.7)
        XCTAssertEqual(noAnkle.left.kneeFlexion, 0)
        points[.leftKnee] = nil
        let noKnee = try XCTUnwrap(HumanFigure(points: points).reading)
        XCTAssertEqual(noKnee.left, HumanFigure.Leg(hipFlexion: 0, kneeFlexion: 0, abduction: 0))
    }

    /// Without hips or a spine there is no frame and no reading, and the
    /// missing joints are named.
    func testNoHipsMeansNoFrameAndTheMissingJointsAreNamed() {
        var points = standing()
        points[.leftHip] = nil
        let figure = HumanFigure(points: points)
        XCTAssertNil(figure.frame)
        XCTAssertNil(figure.reading)
        XCTAssertEqual(figure.missing, [.leftHip])
        XCTAssertEqual(HumanFigure(points: [:]).missing, HumanFigure.required)
    }

    /// Hips on top of each other cannot say which way is left.
    func testCoincidentHipsHaveNoFrame() {
        var points = standing()
        points[.rightHip] = points[.leftHip]
        XCTAssertNil(HumanFigure(points: points).frame)
    }

    /// Mirroring swaps sides and only sides; mirroring twice is the identity.
    func testMirroringSwapsLeftAndRight() throws {
        var points = standing()
        points[.leftKnee] = DuckVector(0.15, -0.3, 0.3)
        points[.leftAnkle] = DuckVector(0.15, -0.75, 0.3)
        let figure = HumanFigure(points: points)
        let mirrored = figure.mirrored
        XCTAssertEqual(mirrored.points[.rightKnee], points[.leftKnee])
        XCTAssertEqual(mirrored.points[.rightHip], points[.leftHip])
        XCTAssertEqual(mirrored.points[.topHead], points[.topHead])
        XCTAssertEqual(mirrored.mirrored, figure)
        // The bent leg is now the right one — and the frame's forward has
        // flipped with the hips, which is what a mirror does.
        let reading = try XCTUnwrap(mirrored.reading)
        XCTAssertEqual(reading.left.kneeFlexion, 0, accuracy: tolerance)
        XCTAssertGreaterThan(reading.right.kneeFlexion, 0.5)
    }

    func testEveryJointHasAnOppositeAndTheMidlineIsItsOwn() {
        for joint in HumanFigure.Joint.allCases {
            XCTAssertEqual(joint.opposite.opposite, joint)
        }
        XCTAssertEqual(HumanFigure.Joint.root.opposite, .root)
        XCTAssertEqual(HumanFigure.Joint.leftWrist.opposite, .rightWrist)
    }
}
