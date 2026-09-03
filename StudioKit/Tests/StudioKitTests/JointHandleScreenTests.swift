import XCTest
import DuckKit
@testable import StudioKit

/// A pinhole camera, so a projection test is arithmetic on this Pi rather than
/// a RealityKit view on a phone. It is the same operation `ARView.project`
/// performs — a look-at basis, a perspective divide, and y down the screen —
/// which is what makes these assertions claims about the app's own geometry
/// and not about a toy.
struct TestCamera {
    let eye: DuckVector
    let target: DuckVector
    /// Focal length in view points. A 300-point stage holding a 250 mm duck at
    /// about 0.7 m is roughly this.
    let focal: Double

    private static func unit(_ v: DuckVector) -> DuckVector {
        let m = JointHandles.magnitude(v)
        return m > 0 ? DuckVector(v.x / m, v.y / m, v.z / m) : v
    }

    /// The projected point, and how far in front of the camera it is.
    func project(_ p: DuckVector) -> (at: JointHandles.ScreenPoint, depth: Double) {
        let forward = Self.unit(target - eye)
        let right = Self.unit(JointHandles.cross(forward, DuckVector(0, 0, 1)))
        let up = JointHandles.cross(right, forward)
        let v = p - eye
        let depth = JointHandles.dot(v, forward)
        return (JointHandles.ScreenPoint(x: focal * JointHandles.dot(v, right) / depth,
                                         y: -focal * JointHandles.dot(v, up) / depth),
                depth)
    }

    func grab(_ handle: JointHandles.Handle) -> JointHandles.Grab {
        JointHandles.grab(handle: handle,
                          pivot: project(handle.pivot).at,
                          grip: project(handle.grip).at,
                          swung: project(handle.swung).at)
    }

    /// Off the duck's left, a little above the trunk. Both knees' arcs face
    /// this camera, which is what makes it the one to prove drag signs with.
    static let fromTheSide = TestCamera(eye: DuckVector(0, 0.7, 0.20),
                                        target: DuckVector(0, 0, 0.12), focal: 800)
    /// Straight in front of the beak. A knee bends fore-and-aft, so from here
    /// every knee arc is nearly edge-on — the hard case.
    static let fromTheFront = TestCamera(eye: DuckVector(0.6, 0, 0.20),
                                         target: DuckVector(0, 0, 0.12), focal: 800)
}

/// Poses that are not the home pose. A lever that is only ever checked at home
/// is a lever checked in the one configuration nobody authors in.
enum BentPoses {
    static let all: [[Double]] = {
        func bent(_ moves: [(String, Double)]) -> [Double] {
            var pose = DuckModel.homePose
            for (name, delta) in moves {
                if let index = DuckModel.jointIndex(of: name) { pose[index] += delta }
            }
            return pose
        }
        return [
            // A deep crouch: both knees and both hips folded.
            bent([("left_knee", 0.9), ("right_knee", -0.9),
                  ("left_hip_pitch", -0.7), ("right_hip_pitch", 0.7)]),
            // The beak-strut vault's shape: head down and forward, legs
            // extended behind.
            bent([("neck_pitch", -0.9), ("head_pitch", 0.6),
                  ("left_hip_pitch", 0.5), ("right_hip_pitch", -0.5),
                  ("left_ankle", 0.4), ("right_ankle", -0.4)]),
            // Wrung out sideways: every yaw and roll off its stop.
            bent([("left_hip_yaw", 0.4), ("right_hip_yaw", -0.4),
                  ("left_hip_roll", 0.3), ("right_hip_roll", -0.3),
                  ("head_yaw", 1.2), ("head_roll", 0.3)]),
        ]
    }()

    static var allWithHome: [[Double]] { [DuckModel.homePose] + all }
}

/// The lever, the probe, and the screen law a thumb actually drags through.
final class JointHandleLeverTests: XCTestCase {

    /// EVERY joint has an arm long enough to drag by, in every pose — not just
    /// at home. Two links in this robot are shorter than the minimum off their
    /// own axis and are pushed out to it; the rest keep their own length.
    func testEveryPolicyJointHasAnArmAtLeastTheMinimum() {
        for pose in BentPoses.allWithHome {
            let handles = JointHandles.handles(at: pose)
            XCTAssertEqual(handles.count, DuckModel.policyJointCount)
            for handle in handles {
                XCTAssertGreaterThanOrEqual(JointHandles.magnitude(handle.lever),
                                            JointHandles.minimumLever - 1e-12,
                                            handle.name)
            }
        }
    }

    /// An arm with any component along the axis would turn a drag into a
    /// slide, which a hinge cannot do.
    func testTheArmIsPerpendicularToTheAxis() {
        for pose in BentPoses.allWithHome {
            for handle in JointHandles.handles(at: pose) {
                XCTAssertEqual(JointHandles.dot(handle.lever, handle.axis), 0,
                               accuracy: 1e-12, handle.name)
            }
        }
    }

    /// The two links that need pushing out are named in the comment on
    /// `minimumLever`, so pin them: this is what the constant is FOR, and if a
    /// future robot's hip yaw grew an arm of its own the comment would be the
    /// only thing left saying otherwise.
    func testTheTwoShortLinksAreTheOnesPushedOut() throws {
        let handles = JointHandles.handles(at: DuckModel.homePose)
        for name in ["left_hip_yaw", "right_hip_yaw", "head_pitch", "head_yaw"] {
            let handle = try XCTUnwrap(handles.first { $0.name == name })
            XCTAssertEqual(JointHandles.magnitude(handle.lever),
                           JointHandles.minimumLever, accuracy: 1e-12, name)
        }
        let knee = try XCTUnwrap(handles.first { $0.name == "left_knee" })
        XCTAssertEqual(JointHandles.magnitude(knee.lever), 0.042, accuracy: 1e-3,
                       "the shank is its own arm and is not touched")
    }

    /// `swung` IS THE KINEMATIC CHAIN, NOT A FORMULA BESIDE IT. Turning the
    /// joint by `probeRadians` and asking `bodyPoses` again has to land on the
    /// same point, or the screen direction the app drags along belongs to a
    /// robot this one only resembles.
    func testSwungIsTheChainAtTheProbeAngle() throws {
        for pose in BentPoses.allWithHome {
            for handle in JointHandles.handles(at: pose) {
                var turned = pose
                turned[handle.joint] += JointHandles.probeRadians
                let after = try XCTUnwrap(JointHandles.handles(at: turned)
                    .first { $0.joint == handle.joint })
                XCTAssertEqual(JointHandles.magnitude(after.grip - handle.swung), 0,
                               accuracy: 1e-9, handle.name)
            }
        }
    }

    /// FOURTEEN HANDLES, FIFTEEN-WIDE INDICES. The handles walk the policy's
    /// fourteen action slots, and a draft key is fifteen joints wide; a handle
    /// carrying its SLOT would write the wrong joint from the neck down,
    /// silently, because both numbers are small integers.
    func testAHandlesJointIsTheDraftsIndexAndNotThePolicySlot() {
        let handles = JointHandles.handles(at: DuckModel.homePose)
        for handle in handles {
            XCTAssertEqual(DuckModel.jointNames[handle.joint], handle.name)
        }
        XCTAssertFalse(handles.contains { $0.joint == DuckModel.mouthIndex })
        // The last policy slot's joint is past the fourteenth index, which is
        // the whole reason the two numberings cannot be swapped unnoticed.
        XCTAssertEqual(Set(handles.map(\.joint)).count, DuckModel.policyJointCount)
        XCTAssertEqual(handles.map(\.joint).max(), DuckModel.jointCount - 1)
    }

    /// A pose of the wrong width draws nothing rather than trapping inside
    /// `bodyPoses`' precondition.
    func testAPoseOfTheWrongWidthDrawsNothing() {
        XCTAssertEqual(JointHandles.handles(at: []).count, 0)
        XCTAssertEqual(
            JointHandles.handles(
                at: [Double](repeating: 0, count: DuckModel.policyJointCount)).count, 0,
            "a fourteen-wide harness pose is not a draft key")
        XCTAssertEqual(
            JointHandles.handles(at: [Double](repeating: 0, count: DuckModel.jointCount + 1)).count,
            0)
        XCTAssertEqual(JointHandles.handles(at: DuckModel.homePose).count,
                       DuckModel.policyJointCount)
    }

    /// WHY THE PROBE IS A TENTH OF A RADIAN AND NOT ONE.
    ///
    /// This is the measurement the constant's comment cites. From a camera in
    /// front of the duck, the right knee's chord over a WHOLE radian points up
    /// the screen while the joint's actual first movement is down it: a handle
    /// built on the full chord runs away from the thumb, turns round a third of
    /// the way through, and comes back. The small probe agrees with the 3D
    /// tangent instead.
    func testProbeReallyIsATangent() throws {
        let camera = TestCamera.fromTheFront
        let handle = try XCTUnwrap(JointHandles.handles(at: DuckModel.homePose)
            .first { $0.name == "right_knee" })

        // Where the grip really is a whole radian later, off the chain.
        var wholeRadian = DuckModel.homePose
        wholeRadian[handle.joint] += 1
        let far = try XCTUnwrap(JointHandles.handles(at: wholeRadian)
            .first { $0.joint == handle.joint })

        let grip = camera.project(handle.grip).at
        let probe = camera.project(handle.swung).at
        let whole = camera.project(far.grip).at

        // Per radian, so the two chords are comparable: the probe says this
        // joint sets off DOWN the screen at about 7 points a radian, and the
        // full chord says it sets off UP it at about 16.
        XCTAssertGreaterThan((probe.y - grip.y) / JointHandles.probeRadians, 3.0,
                             "the joint's first move is DOWN the screen")
        XCTAssertLessThan(whole.y - grip.y, -3.0,
                          "and a whole radian later it is far UP the screen — the arc curls")
    }

    /// The pair of facts that makes a handle feel like a hinge: the same
    /// thumb-stroke opens one knee and closes the other, because the two
    /// knees' axes point opposite ways.
    func testTheSameDragOpensTheLeftKneeAndClosesTheRight() throws {
        let camera = TestCamera.fromTheSide
        let handles = JointHandles.handles(at: DuckModel.homePose)
        let left = try XCTUnwrap(handles.first { $0.name == "left_knee" })
        let right = try XCTUnwrap(handles.first { $0.name == "right_knee" })

        let leftAfter = JointHandles.dragged(handle: left, grab: camera.grab(left),
                                             dx: 0, dy: -20)
        let rightAfter = JointHandles.dragged(handle: right, grab: camera.grab(right),
                                              dx: 0, dy: -20)
        XCTAssertGreaterThan(leftAfter - left.angle, 0.05)
        XCTAssertLessThan(rightAfter - right.angle, -0.05)
    }

    /// No joint's whole travel ever costs less than a short flick or more than
    /// a long swipe, however far the camera is — because the gain is clamped,
    /// not because the camera is polite.
    func testFullTravelAlwaysCostsBetweenAFlickAndASwipe() {
        for handle in JointHandles.handles(at: DuckModel.homePose) {
            for perRadian in stride(from: 1.0, through: 5000.0, by: 7.0) {
                // A synthetic projection: the arm along +x, the arc along +y.
                let pivot = JointHandles.ScreenPoint(x: 0, y: 0)
                let grip = JointHandles.ScreenPoint(x: 60, y: 0)
                let swung = JointHandles.ScreenPoint(
                    x: 60, y: perRadian * JointHandles.probeRadians)
                let grab = JointHandles.grab(handle: handle, pivot: pivot,
                                             grip: grip, swung: swung)
                guard case .draggable(let radiansPerPoint, _) = grab else {
                    XCTAssertLessThan(perRadian, JointHandles.edgeOnPoints,
                                      "\(handle.name) refused at \(perRadian) pt/rad")
                    continue
                }
                let points = handle.travel / radiansPerPoint
                XCTAssertGreaterThanOrEqual(points,
                                            JointHandles.fastestFullTravelPoints - 1e-9,
                                            "\(handle.name) at \(perRadian) pt/rad")
                XCTAssertLessThanOrEqual(points,
                                         JointHandles.slowestFullTravelPoints + 1e-9,
                                         "\(handle.name) at \(perRadian) pt/rad")
            }
        }
    }

    /// An edge-on arc refuses, and a refusal leaves the joint exactly where it
    /// was — never a joint that moved a little.
    func testAnEdgeOnHandleRefusesAndKeepsItsAngle() throws {
        let handle = try XCTUnwrap(JointHandles.handles(at: DuckModel.homePose)
            .first { $0.name == "left_knee" })
        let grab = JointHandles.grab(
            handle: handle,
            pivot: JointHandles.ScreenPoint(x: 0, y: 0),
            grip: JointHandles.ScreenPoint(x: 60, y: 0),
            // Five points of screen movement per radian: less than the floor.
            swung: JointHandles.ScreenPoint(x: 60, y: 5 * JointHandles.probeRadians))
        XCTAssertEqual(grab, .edgeOn)
        XCTAssertEqual(JointHandles.dragged(handle: handle, grab: grab, dx: 200, dy: -200),
                       handle.angle)
    }

    /// An arm foreshortened to nothing is a marker sitting on its own pivot:
    /// it moves plenty, and nothing on screen says which way. Also a refusal.
    func testAnArmPointingAtTheCameraRefuses() throws {
        let handle = try XCTUnwrap(JointHandles.handles(at: DuckModel.homePose)
            .first { $0.name == "left_knee" })
        let grab = JointHandles.grab(
            handle: handle,
            pivot: JointHandles.ScreenPoint(x: 0, y: 0),
            grip: JointHandles.ScreenPoint(x: 3, y: 0),
            swung: JointHandles.ScreenPoint(x: 3, y: 40 * JointHandles.probeRadians))
        XCTAssertEqual(grab, .edgeOn)
    }

    /// From a real camera, every handle either drags or says why — nothing in
    /// between, and no NaN out of a degenerate projection.
    func testEveryHandleFromARealCameraIsEitherDraggableOrAnHonestRefusal() {
        for camera in [TestCamera.fromTheSide, TestCamera.fromTheFront] {
            for pose in BentPoses.allWithHome {
                for handle in JointHandles.handles(at: pose) {
                    switch camera.grab(handle) {
                    case .edgeOn:
                        continue
                    case .draggable(let radiansPerPoint, let direction):
                        XCTAssertTrue(radiansPerPoint.isFinite, handle.name)
                        XCTAssertGreaterThan(radiansPerPoint, 0, handle.name)
                        let length = (direction.x * direction.x
                                      + direction.y * direction.y).squareRoot()
                        XCTAssertEqual(length, 1, accuracy: 1e-12, handle.name)
                    }
                }
            }
        }
    }

    /// A drag never leaves the joint's real travel, whichever way it is aimed.
    func testADragIsAlwaysInsideTheJointsTravel() {
        let camera = TestCamera.fromTheSide
        for handle in JointHandles.handles(at: DuckModel.homePose) {
            let grab = camera.grab(handle)
            for (dx, dy) in [(4000.0, 0.0), (-4000.0, 0.0), (0.0, 4000.0), (0.0, -4000.0)] {
                let angle = JointHandles.dragged(handle: handle, grab: grab, dx: dx, dy: dy)
                XCTAssertGreaterThanOrEqual(angle, handle.lower, handle.name)
                XCTAssertLessThanOrEqual(angle, handle.upper, handle.name)
            }
        }
    }
}

/// Fourteen targets on a stage the size of a playing card.
final class JointHandlePlacementTests: XCTestCase {

    private func projected(_ points: [(Int, Double, Double, Double)])
        -> [(joint: Int, at: JointHandles.ScreenPoint, depth: Double)] {
        points.map { (joint: $0.0,
                      at: JointHandles.ScreenPoint(x: $0.1, y: $0.2),
                      depth: $0.3) }
    }

    /// The guarantee the overlay is built on: no two drawn targets are ever
    /// closer than the minimum, so the top one cannot silently eat the tap
    /// meant for the one under it.
    func testNoTwoDrawnTargetsAreEverTooClose() {
        let minimum = 44.0
        // A hip's three joints landing on each other, plus a spread of others.
        let placed = JointHandles.place(projected([
            (0, 100, 100, 0.6), (1, 104, 103, 0.6), (2, 99, 96, 0.6),
            (3, 100, 160, 0.6), (4, 100, 220, 0.6),
            (10, 40, 100, 0.9), (11, 42, 101, 0.9), (12, 41, 99, 0.9),
            (5, 200, 60, 0.5), (6, 202, 62, 0.5),
        ]), trunkDepth: 0.7, minimumSeparation: minimum)

        for a in placed.indices {
            for b in (a + 1)..<placed.count {
                XCTAssertGreaterThanOrEqual(
                    JointHandles.separation(placed[a].at, placed[b].at), minimum,
                    "joints \(placed[a].joint) and \(placed[b].joint) overlap")
            }
        }
    }

    /// Every joint is drawn, or folded into exactly one target that is. A
    /// joint that fell out of both is a joint nobody can reach.
    func testEveryJointIsDrawnOrInExactlyOneCluster() {
        let joints = (0..<DuckModel.policyJointCount).map { DuckModel.jointOfPolicySlot($0) }
        let placed = JointHandles.place(
            projected(joints.enumerated().map { index, joint in
                // Deliberately piled up: three distinct spots for fourteen.
                (joint, Double(index % 3) * 30, Double(index % 3) * 20, 0.6)
            }), trunkDepth: 0.7, minimumSeparation: 44)

        let accounted = placed.flatMap { [$0.joint] + $0.clustered }
        XCTAssertEqual(accounted.sorted(), joints.sorted())
        XCTAssertEqual(Set(accounted).count, accounted.count, "a joint was folded in twice")
        XCTAssertEqual(placed.map(\.count).reduce(0, +), joints.count)
    }

    /// Farther from the camera than the trunk means drawn dim. Nothing else.
    func testWhatIsBehindTheTrunkIsMarkedBehind() {
        let placed = JointHandles.place(projected([
            (0, 0, 0, 0.5), (10, 300, 300, 0.9),
        ]), trunkDepth: 0.7, minimumSeparation: 44)
        XCTAssertEqual(placed.count, 2)
        XCTAssertFalse(placed[0].behind)
        XCTAssertTrue(placed[1].behind)
    }

    /// The first joint at a spot keeps it, so the caller's order is the
    /// priority order.
    func testTheFirstJointAtASpotKeepsIt() {
        let placed = JointHandles.place(projected([
            (7, 50, 50, 0.6), (2, 52, 51, 0.6), (11, 48, 53, 0.6),
        ]), trunkDepth: 0.7, minimumSeparation: 44)
        XCTAssertEqual(placed.count, 1)
        XCTAssertEqual(placed[0].joint, 7)
        XCTAssertEqual(placed[0].clustered, [2, 11])
        XCTAssertEqual(placed[0].count, 3)
    }

    func testNothingProjectedDrawsNothing() {
        XCTAssertTrue(JointHandles.place([], trunkDepth: 0.7, minimumSeparation: 44).isEmpty)
    }
}

/// The sentences a handle can put on screen.
final class JointHandlesSentenceTests: XCTestCase {

    func testTheEdgeOnRefusalSaysWhatToDo() {
        let said = JointHandles.edgeOnSaid
        XCTAssertTrue(said.lowercased().contains("orbit"),
                      "a refusal that does not say how to fix it is a dead end")
        XCTAssertFalse(said.lowercased().contains("error"))
        XCTAssertFalse(said.lowercased().contains("unsupported"))
        XCTAssertFalse(said.contains("_"))
        XCTAssertTrue(said.hasSuffix("."))
    }

    func testTheBetweenKeyframesRefusalNamesTheKeyframe() {
        let said = JointHandles.betweenKeyframesSaid
        XCTAssertTrue(said.lowercased().contains("keyframe"))
        XCTAssertTrue(said.lowercased().contains("playhead"))
        XCTAssertFalse(said.lowercased().contains("error"))
        XCTAssertTrue(said.hasSuffix("."))
    }

    func testTheClusterLabelCountsTheJointsItStandsFor() {
        XCTAssertTrue(JointHandles.clusterSaid(3).contains("3"))
        XCTAssertTrue(JointHandles.clusterSaid(3).lowercased().contains("joints"))
        XCTAssertFalse(JointHandles.clusterSaid(3).contains("_"))
    }

    /// The pill's one button is named by the kit, so the concept it acts on
    /// (JointControl.home) and its word cannot drift apart.
    func testTheHomeActionIsNamedByTheKit() {
        XCTAssertEqual(JointHandles.homeActionSaid, "Home")
    }

    /// Fourteen handles, fifteen joints, and the app says which one is missing
    /// and why rather than leaving a gap.
    func testTheBeakSaysWhyItHasNoHandle() {
        let said = JointHandles.noMouthHandleSaid
        XCTAssertTrue(said.lowercased().contains("beak"))
        XCTAssertTrue(said.lowercased().contains("policy"))
        XCTAssertFalse(said.contains("_"))
    }

    /// Every joint has a plain word, and none of them is a wire name.
    func testEveryJointHasAPlainName() {
        for index in 0..<DuckModel.jointCount {
            let control = JointControl(index: index)
            XCTAssertFalse(control.plainName.isEmpty)
            XCTAssertFalse(control.plainName.contains("_"),
                           "\(control.name) has no plain word")
        }
        XCTAssertEqual(JointControl(index: 13).plainName, "right knee")
        XCTAssertEqual(JointControl(index: DuckModel.mouthIndex).plainName, "beak")
    }

    /// The direction is this frame's; the gain is the first frame's.
    func testARefreshedGrabKeepsTheGainAndTakesTheNewDirection() {
        let handle = JointHandles.handles(at: DuckModel.homePose)[3]
        let first = JointHandles.grab(handle: handle, pivot: .init(x: 100, y: 100),
                                      grip: .init(x: 140, y: 100), swung: .init(x: 140, y: 96))
        let later = JointHandles.grab(handle: handle, pivot: .init(x: 100, y: 100),
                                      grip: .init(x: 140, y: 100), swung: .init(x: 143, y: 100),
                                      keepingGainOf: first)
        guard case .draggable(let g1, let d1) = first, case .draggable(let g2, let d2) = later else {
            return XCTFail("both grabs should be draggable")
        }
        XCTAssertEqual(g1, g2, accuracy: 1e-12)
        XCTAssertNotEqual(d1, d2)
        XCTAssertEqual(d2.x, 1, accuracy: 1e-9); XCTAssertEqual(d2.y, 0, accuracy: 1e-9)
        let edge = JointHandles.grab(handle: handle, pivot: .init(x: 100, y: 100),
                                     grip: .init(x: 101, y: 100), swung: .init(x: 101, y: 100),
                                     keepingGainOf: first)
        XCTAssertEqual(edge, .edgeOn)
    }

    /// A target whose box would cross the viewport's edge is dropped — AND IT
    /// IS NAMED ON THE WAY OUT.
    ///
    /// THE OLD ASSERTION WAS `kept == [4]` AND NOTHING ELSE, which is precisely
    /// the shape of the bug: two joints left the picture and the test agreed
    /// with the code that they had simply ceased to exist. Every joint that goes
    /// in comes out drawn, folded, or counted.
    func testEveryJointIsDrawnClusteredOrNamedOffPicture() {
        let projected: [(joint: Int, at: JointHandles.ScreenPoint, depth: Double)] = [
            (joint: 3, at: .init(x: 10, y: 150), depth: 1),
            (joint: 4, at: .init(x: 180, y: 150), depth: 1),
            (joint: 13, at: .init(x: 350, y: 295), depth: 1),
        ]
        let out = JointHandles.placed(projected, trunkDepth: 1, minimumSeparation: 44,
                                      within: 360, 300, inset: 22)
        XCTAssertEqual(out.kept.map(\.joint), [4])
        XCTAssertEqual(out.offPicture, [3, 13])
        // The single-return overload is the same answer, so nothing that reads
        // it can disagree with what this one counted.
        XCTAssertEqual(JointHandles.place(projected, trunkDepth: 1, minimumSeparation: 44,
                                          within: 360, 300, inset: 22).map(\.joint),
                       out.kept.map(\.joint))
        assertAccountedFor(projected, out)
    }

    /// The accounting, over a set with real clustering in it — including an
    /// anchor that folds two joints and is THEN dropped off the picture, which
    /// is the case that lost three joints at once and said nothing.
    func testAFoldedJointGoesOffThePictureWithTheAnchorItFoldedInto() {
        let projected: [(joint: Int, at: JointHandles.ScreenPoint, depth: Double)] = [
            (joint: 0, at: .init(x: 352, y: 150), depth: 1),
            (joint: 1, at: .init(x: 356, y: 152), depth: 1),
            (joint: 2, at: .init(x: 180, y: 150), depth: 1),
        ]
        let out = JointHandles.placed(projected, trunkDepth: 1, minimumSeparation: 44,
                                      within: 360, 300, inset: 22)
        XCTAssertEqual(out.kept.map(\.joint), [2])
        XCTAssertEqual(out.offPicture, [0, 1])
        assertAccountedFor(projected, out)
    }

    /// A BIGGER PICTURE BUYS HANDLE REACH, MEASURED. The same fourteen
    /// projections against the shipped inline stage and against the grown one:
    /// strictly fewer are dropped, and nothing that was reachable on the small
    /// stage stops being reachable on the large one.
    func testABiggerPictureDropsFewerJoints() {
        var projected: [(joint: Int, at: JointHandles.ScreenPoint, depth: Double)] = []
        // Spread across a 351 × 300 glass, with four of them out past its
        // edges and inside the larger one.
        let spots: [(Double, Double)] = [
            (60, 60), (120, 90), (180, 120), (240, 150), (300, 180),
            (90, 200), (150, 230), (210, 260), (60, 140), (120, 170),
            (330, 120), (170, 292), (250, 295), (360, 200),
        ]
        for (index, spot) in spots.enumerated() {
            projected.append((joint: index, at: .init(x: spot.0, y: spot.1), depth: 1))
        }
        let small = JointHandles.placed(projected, trunkDepth: 1, minimumSeparation: 44,
                                        within: 351, 300, inset: 22)
        let large = JointHandles.placed(projected, trunkDepth: 1, minimumSeparation: 44,
                                        within: 393, 534, inset: 22)
        assertAccountedFor(projected, small)
        assertAccountedFor(projected, large)
        XCTAssertGreaterThan(small.offPicture.count, 0, "nothing was dropped on the small stage")
        XCTAssertLessThan(large.offPicture.count, small.offPicture.count)
        for joint in small.kept.map(\.joint) {
            XCTAssertTrue(large.kept.contains { $0.joint == joint },
                          "joint \(joint) was reachable small and is not reachable large")
        }
    }

    /// The band the camera column stands in drops the handles under it, because
    /// a handle under a button is a handle nobody can press.
    func testTheColumnsBandDropsTheHandlesUnderIt() {
        let projected: [(joint: Int, at: JointHandles.ScreenPoint, depth: Double)] = [
            (joint: 5, at: .init(x: 351 - 40, y: 150), depth: 1),
        ]
        let open = JointHandles.placed(projected, trunkDepth: 1, minimumSeparation: 44,
                                       within: 351, 300, inset: 22, reservingTrailing: 0)
        XCTAssertEqual(open.kept.map(\.joint), [5])
        XCTAssertEqual(open.offPicture, [])
        let column = JointHandles.placed(projected, trunkDepth: 1, minimumSeparation: 44,
                                         within: 351, 300, inset: 22, reservingTrailing: 76)
        XCTAssertEqual(column.kept, [])
        XCTAssertEqual(column.offPicture, [5])
    }

    /// The sentence offers the two moves that bring a handle back, and gets its
    /// grammar right at one.
    func testTheOffPictureSentenceOffersTheTwoFixes() {
        XCTAssertEqual(JointHandles.offPictureSaid(1),
            "1 joint is off the edge of the picture, so it has no handle. Make the picture "
          + "bigger, or orbit until it comes into view.")
        XCTAssertEqual(JointHandles.offPictureSaid(3),
            "3 joints are off the edge of the picture, so they have no handle. Make the "
          + "picture bigger, or orbit until they come into view.")
        for count in [1, 3] {
            XCTAssertTrue(JointHandles.offPictureSaid(count).contains("bigger"))
            XCTAssertTrue(JointHandles.offPictureSaid(count).contains("orbit"))
        }
    }

    /// Every joint that went in is drawn, folded into a drawn one, or counted —
    /// and none of them is in two of the three.
    private func assertAccountedFor(
        _ projected: [(joint: Int, at: JointHandles.ScreenPoint, depth: Double)],
        _ out: (kept: [JointHandles.Placed], offPicture: [Int]),
        file: StaticString = #filePath, line: UInt = #line) {
        let drawn = Set(out.kept.map(\.joint))
        let folded = Set(out.kept.flatMap(\.clustered))
        let off = Set(out.offPicture)
        XCTAssertEqual(drawn.union(folded).union(off), Set(projected.map(\.joint)),
                       "a joint went in and came out of none of the three", file: file, line: line)
        XCTAssertTrue(drawn.isDisjoint(with: folded), file: file, line: line)
        XCTAssertTrue(drawn.isDisjoint(with: off), file: file, line: line)
        XCTAssertTrue(folded.isDisjoint(with: off), file: file, line: line)
        XCTAssertEqual(drawn.count + folded.count + off.count, projected.count,
                       "a joint was counted twice", file: file, line: line)
    }

    /// A drag ends when its pivot moves further than a few points, and not
    /// for the jitter of a re-projection.
    func testADragEndsOnlyWhenThePivotReallyMoves() {
        let began = JointHandles.ScreenPoint(x: 100, y: 100)
        XCTAssertFalse(JointHandles.pivotMoved(from: began, to: began))
        XCTAssertFalse(JointHandles.pivotMoved(
            from: began, to: JointHandles.ScreenPoint(x: 102, y: 101)))
        XCTAssertTrue(JointHandles.pivotMoved(
            from: began, to: JointHandles.ScreenPoint(x: 100, y: 100 + JointHandles.pivotMovedPoints + 1)))
    }
}
