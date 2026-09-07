import XCTest
import DuckKit
@testable import StudioKit

/// The retargeting, checked against the robot's own kinematics rather than
/// against the signs written in the source: every direction claimed in
/// `PoseRetarget`'s header is re-measured here with `DuckKinematics`.
final class PoseRetargetTests: XCTestCase {

    private func standing(left: HumanFigure.Leg = .init(hipFlexion: 0, kneeFlexion: 0, abduction: 0),
                          right: HumanFigure.Leg = .init(hipFlexion: 0, kneeFlexion: 0, abduction: 0),
                          head: HumanFigure.Head = .init(pitch: 0, yaw: 0, roll: 0),
                          armRaise: Double = 0) -> HumanFigure.Reading {
        HumanFigure.Reading(left: left, right: right, head: head, armRaise: armRaise)
    }

    private func site(_ pose: [Double], _ name: String) throws -> DuckVector {
        try XCTUnwrap(DuckKinematics.sitePositions(jointAngles: pose)[name])
    }

    private func orientation(_ pose: [Double], _ body: String) throws -> DuckQuaternion {
        try XCTUnwrap(DuckKinematics.bodyPoses(jointAngles: pose)[body]).orientation
    }

    private func assertSameOrientation(_ a: DuckQuaternion, _ b: DuckQuaternion,
                                       _ message: String, file: StaticString = #filePath,
                                       line: UInt = #line) {
        let err = abs(a.w - b.w) + abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)
        XCTAssertLessThan(err, 1e-6, message, file: file, line: line)
    }

    /// A person standing straight is the duck at home, to the digit, mouth
    /// closed.
    func testStandingStraightIsTheHomeStance() {
        let out = PoseRetarget.duckPose(from: standing())
        for joint in 0..<DuckModel.jointCount where joint != DuckModel.mouthIndex {
            XCTAssertEqual(out.pose[joint], DuckModel.homePose[joint], accuracy: 1e-12,
                           DuckModel.jointNames[joint])
        }
        XCTAssertEqual(out.pose[DuckModel.mouthIndex], DuckModel.mouthClosed, accuracy: 1e-12)
        XCTAssertEqual(out.clamped, [])
    }

    /// The claim in the header, measured: a thigh swung forward puts that
    /// foot forward of where home puts it, on each side, and leaves the other
    /// foot alone.
    func testAThighForwardMovesThatFootForward() throws {
        let home = DuckModel.homePose
        let left = PoseRetarget.duckPose(from: standing(left: .init(hipFlexion: 0.5, kneeFlexion: 0, abduction: 0)))
        XCTAssertGreaterThan(try site(left.pose, "left_foot").x - site(home, "left_foot").x, 0.01)
        XCTAssertEqual(try site(left.pose, "right_foot").x, try site(home, "right_foot").x, accuracy: 1e-9)

        let right = PoseRetarget.duckPose(from: standing(right: .init(hipFlexion: 0.5, kneeFlexion: 0, abduction: 0)))
        XCTAssertGreaterThan(try site(right.pose, "right_foot").x - site(home, "right_foot").x, 0.01)
        XCTAssertEqual(try site(right.pose, "left_foot").x, try site(home, "left_foot").x, accuracy: 1e-9)
    }

    /// A bent knee takes that foot back. (Not measurably up: the ankle rule
    /// keeps the foot level, and levelling swings the sole about the ankle.)
    func testABentKneeMovesThatFootBack() throws {
        let home = DuckModel.homePose
        for (leg, foot) in [("left", "left_foot"), ("right", "right_foot")] {
            let bent: HumanFigure.Leg = .init(hipFlexion: 0, kneeFlexion: 0.6, abduction: 0)
            let out = leg == "left"
                ? PoseRetarget.duckPose(from: standing(left: bent))
                : PoseRetarget.duckPose(from: standing(right: bent))
            let moved = try site(out.pose, foot), rest = try site(home, foot)
            XCTAssertLessThan(moved.x - rest.x, -0.01, leg)
        }
    }

    /// The ankle rule, measured as an orientation: however the hip and knee
    /// move, the foot body keeps the orientation it has at home.
    func testTheFootStaysLevelWhateverTheHipAndKneeDo() throws {
        let home = DuckModel.homePose
        for hip in [-0.4, 0, 0.6] {
            for knee in [0.0, 0.5, 1.0] {
                let leg: HumanFigure.Leg = .init(hipFlexion: hip, kneeFlexion: knee, abduction: 0)
                let out = PoseRetarget.duckPose(from: standing(left: leg, right: leg))
                guard out.clamped.isEmpty else { continue }
                assertSameOrientation(try orientation(out.pose, "ankle_left"),
                                      try orientation(home, "ankle_left"), "left \(hip) \(knee)")
                assertSameOrientation(try orientation(out.pose, "ankle_right"),
                                      try orientation(home, "ankle_right"), "right \(hip) \(knee)")
            }
        }
    }

    /// Outward is outward on each side: the left foot goes to +y, the right
    /// foot to -y.
    func testAbductionSwingsEachFootOutToItsOwnSide() throws {
        let home = DuckModel.homePose
        let out: HumanFigure.Leg = .init(hipFlexion: 0, kneeFlexion: 0, abduction: 0.3)
        let both = PoseRetarget.duckPose(from: standing(left: out, right: out))
        XCTAssertGreaterThan(try site(both.pose, "left_foot").y - site(home, "left_foot").y, 0.01)
        XCTAssertLessThan(try site(both.pose, "right_foot").y - site(home, "right_foot").y, -0.01)
    }

    /// A nod puts the beak down; a turn to the left puts it to +y; a tilt to
    /// the left puts the top of the head to +y and the beak the other way.
    func testTheHeadFollowsInTheDirectionsTheModelHas() throws {
        let home = DuckModel.homePose
        let nod = PoseRetarget.duckPose(from: standing(head: .init(pitch: 0.3, yaw: 0, roll: 0)))
        XCTAssertLessThan(try site(nod.pose, "mouth_tip").z - site(home, "mouth_tip").z, -0.01)

        let turn = PoseRetarget.duckPose(from: standing(head: .init(pitch: 0, yaw: 0.3, roll: 0)))
        XCTAssertGreaterThan(try site(turn.pose, "mouth_tip").y - site(home, "mouth_tip").y, 0.01)

        let tilt = PoseRetarget.duckPose(from: standing(head: .init(pitch: 0, yaw: 0, roll: 0.3)))
        XCTAssertGreaterThan(try site(tilt.pose, "head_imu").y - site(home, "head_imu").y, 0.001)
        XCTAssertLessThan(try site(tilt.pose, "mouth_tip").y - site(home, "mouth_tip").y, -0.0005)
        // The neck is left where home puts it; the head does the following.
        XCTAssertEqual(nod.pose[5], home[5])
        XCTAssertEqual(nod.pose[6], home[6] + 0.3, accuracy: 1e-12)
    }

    /// The arm channel is the beak, and it is the robot's own mouth travel.
    func testTheHigherHandOpensTheBeak() {
        XCTAssertEqual(PoseRetarget.duckPose(from: standing(armRaise: 1)).pose[DuckModel.mouthIndex],
                       DuckModel.mouthTarget(open: 1), accuracy: 1e-12)
        XCTAssertEqual(PoseRetarget.duckPose(from: standing(armRaise: 0.5)).pose[DuckModel.mouthIndex],
                       DuckModel.mouthTarget(open: 0.5), accuracy: 1e-12)
    }

    /// Nothing asked of the duck is outside its travel, however far a person
    /// goes — and the joints that were held are named.
    func testEveryPoseIsInsideTheTravelAndClampsAreNamed() {
        let extreme: HumanFigure.Leg = .init(hipFlexion: 3, kneeFlexion: 3, abduction: 3)
        let out = PoseRetarget.duckPose(from: standing(left: extreme, right: extreme,
                                                       head: .init(pitch: 4, yaw: 5, roll: 4),
                                                       armRaise: 9))
        for joint in 0..<DuckModel.jointCount {
            let range = DuckModel.jointRanges[joint]
            XCTAssertGreaterThanOrEqual(out.pose[joint], range.lower, DuckModel.jointNames[joint])
            XCTAssertLessThanOrEqual(out.pose[joint], range.upper, DuckModel.jointNames[joint])
        }
        XCTAssertFalse(out.clamped.isEmpty)
        XCTAssertTrue(out.clamped.contains(1), "left hip roll at 3 rad is past ±0.38")
        XCTAssertTrue(out.clamped.contains(7), "head yaw at 5 rad is past ±2.97")
        let line = PoseRetarget.clampedLine(out.clamped)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("Held at the robot's stop"))
        XCTAssertNil(PoseRetarget.clampedLine([]))
        // And the mouth never opens past open — exactly open, no margin,
        // because closed-to-open is not stop-to-stop.
        XCTAssertEqual(out.pose[DuckModel.mouthIndex], DuckModel.mouthOpen, accuracy: 1e-12)
        XCTAssertFalse(out.clamped.contains(DuckModel.mouthIndex))
    }

    /// A pose a bench draft would refuse is not produced: the retargeted pose
    /// passes the editor's own range check.
    func testARetargetedPoseIsADraftTheEditorAccepts() {
        let squat: HumanFigure.Leg = .init(hipFlexion: 1.5, kneeFlexion: 2.0, abduction: 0.2)
        let out = PoseRetarget.duckPose(from: standing(left: squat, right: squat))
        var draft = IntentDraft.blank(named: "squat")
        draft.keys = [IntentDraft.Key(time: 0, pose: out.pose), IntentDraft.Key(time: 1, pose: out.pose)]
        XCTAssertFalse(draft.problems.contains { $0.text.contains("outside its travel") })
    }

    /// NaN from a model that lost a joint mid-frame does not reach a servo.
    func testANonFiniteAngleFallsBackToHome() {
        let broken: HumanFigure.Leg = .init(hipFlexion: .nan, kneeFlexion: 0, abduction: 0)
        let out = PoseRetarget.duckPose(from: standing(left: broken))
        XCTAssertTrue(out.pose.allSatisfy(\.isFinite))
        XCTAssertEqual(out.pose[2], DuckModel.homePose[2])
    }

    func testTheReadingLineIsInDegreesAndPercent() {
        let line = PoseRetarget.readingLine(standing(left: .init(hipFlexion: .pi / 4, kneeFlexion: 0, abduction: 0),
                                                     armRaise: 0.5))
        XCTAssertTrue(line.hasPrefix("Hips 45° / 0°"), line)
        XCTAssertTrue(line.hasSuffix("hands 50% up"), line)
    }

    /// A figure with no frame retargets to nothing rather than to home.
    func testAFigureWithNoFrameIsNil() {
        XCTAssertNil(PoseRetarget.duckPose(from: HumanFigure(points: [:])))
    }

    func testGainsUnderOneOnTheLegsAndOneOnTheHead() {
        XCTAssertLessThan(PoseRetarget.Gains.standard.hip, 1)
        XCTAssertLessThan(PoseRetarget.Gains.standard.knee, 1)
        XCTAssertEqual(PoseRetarget.Gains.standard.head, 1)
    }
}
