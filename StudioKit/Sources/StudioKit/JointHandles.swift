import Foundation
import DuckKit

/// Where each joint's grab-handle lives in 3D, and how a drag becomes an angle.
///
/// THE GEOMETRY LIVES HERE, NOT IN THE VIEW, because it is provable here. A
/// RealityKit gesture cannot run under `swift test`, but everything it needs —
/// the pivot, the axis, the tangent, the angle a drag maps to — is pure
/// kinematics, and getting any of it wrong produces a handle that drags the
/// wrong joint the wrong way, which on a phone looks like haunted furniture.
/// The view's whole job is to draw a marker at `pivot`, aim a gesture at it,
/// and hand the drag back to `angleDelta`.
public enum JointHandles {

    /// One joint you can grab.
    public struct Handle: Equatable, Sendable, Identifiable {
        public let joint: Int
        public let name: String
        /// Where the marker sits: the moved body's origin, in the model's
        /// world frame (z up — the same frame `DuckKinematics.bodyPoses`
        /// works in; the view converts once at the boundary).
        public let pivot: DuckVector
        /// The world-space rotation axis, unit length. Every hinge in this
        /// model rotates about its body-local Z, and rotZ leaves Z fixed — so
        /// the axis is the moved body's world Z whatever the joint's angle.
        public let axis: DuckVector
        public let angle: Double
        public let lower: Double
        public let upper: Double
        /// The arm this handle is dragged by, from `pivot`, in the model's
        /// world frame — always perpendicular to `axis`, and never shorter
        /// than `minimumLever`. See `grip`.
        public let lever: DuckVector
        public var id: Int { joint }

        /// The point a drag pulls: `pivot` plus `lever`.
        ///
        /// WHY NOT THE PIVOT ITSELF. A hinge's pivot is its one point that does
        /// not move, so a marker drawn there and dragged there tells the person
        /// nothing about which way the joint goes and gives the maths no arm to
        /// divide by. The arm is taken from the robot: the origin of the body
        /// hanging off this one (an ankle, which has no child body, uses its own
        /// foot site), with the along-axis part removed because sliding along a
        /// hinge is not a rotation.
        public var grip: DuckVector { pivot + lever }

        /// Where `grip` lands after `probeRadians` — the second point the app
        /// projects, and the whole of what the kit needs from the camera.
        ///
        /// The screen vector from the projected `grip` to the projected
        /// `swung` is this joint's direction of travel and its scale in one:
        /// no camera maths in the kit, no kinematics in the view. It is
        /// `DuckKinematics.bodyPoses` at `angle + probeRadians`, exactly, and a
        /// test asserts that against the chain rather than against this
        /// formula.
        ///
        /// THE PROBE IS SMALL AND THAT IS THE WHOLE POINT — see
        /// `probeRadians`, which was 1 rad in the first draft of this and made
        /// the right knee drag backwards.
        public var swung: DuckVector {
            // Rodrigues about a unit axis, with the axis-parallel term dropped
            // because `lever` is perpendicular to `axis` by construction.
            let turned = JointHandles.cross(axis, lever)
            let c = cos(JointHandles.probeRadians), s = sin(JointHandles.probeRadians)
            return DuckVector(pivot.x + lever.x * c + turned.x * s,
                              pivot.y + lever.y * c + turned.y * s,
                              pivot.z + lever.z * c + turned.z * s)
        }

        /// The joint's whole range, which is what the drag budget is measured
        /// against; it does not depend on where the joint is now.
        public var travel: Double { upper - lower }
    }

    // MARK: - the numbers a drag is calibrated against

    /// The shortest arm a handle is allowed. Two links in this robot are
    /// shorter than this off their own axis — `left_hip_yaw`'s child sits
    /// 16.5 mm off it and `head_pitch`'s 18.7 mm — and an arm that short makes
    /// a drag hypersensitive and its direction unstable under the camera. The
    /// arm is pushed out along its own direction instead, which changes the
    /// gain and not the geometry: the direction it points is still the robot's.
    public static let minimumLever = 0.020

    /// How far the joint is turned to find out which way it goes on screen.
    ///
    /// SMALL, AND MEASURED RATHER THAN CHOSEN. The plan for this said one
    /// radian, and one radian is a 57° swing whose CHORD is not its tangent:
    /// projected from a camera in front of the duck, the right knee's chord
    /// over a whole radian points UP the screen while the joint's first
    /// movement is DOWN it — a handle that runs away from the thumb for the
    /// first third of the drag and then turns round. `probeReallyIsATangent`
    /// pins both halves of that. A tenth of a radian is 5.7°, whose chord is
    /// within 2.9° of the tangent and whose length understates the rate by
    /// 0.04%, and it is still hundreds of times the projector's own noise.
    public static let probeRadians = 0.1

    /// Below this many points of screen movement per radian, the arc is being
    /// seen edge-on and a straight drag has no honest direction. The same
    /// number guards the projected arm: an arm foreshortened to fewer points
    /// than this is a marker sitting on top of its own pivot.
    public static let edgeOnPoints = 6.0

    /// The window a joint's whole travel is held inside, in points of drag.
    /// A handle far from the camera would otherwise need a metre of thumb, and
    /// one close to it would cross its whole range in a twitch.
    public static let slowestFullTravelPoints = 600.0
    public static let fastestFullTravelPoints = 80.0

    /// How far a joint's pivot may move on screen, in points, before a drag
    /// on it is no longer about that joint. A pivot moves under a finger
    /// only when the camera does, and a drag that kept going would then be
    /// steering a joint from a viewpoint the finger never aimed from.
    public static let pivotMovedPoints = 4.0

    /// Whether a drag that began with the pivot at `began` should end now
    /// that the pivot is at `now`.
    public static func pivotMoved(from began: ScreenPoint, to now: ScreenPoint) -> Bool {
        separation(began, now) > pivotMovedPoints
    }

    /// Which body each joint moves. Derived from the kinematic chain — the
    /// body whose `joint` field names it — not written by hand.
    static let movedBody: [String: String] = {
        var map: [String: String] = [:]
        for body in DuckKinematics.bodies {
            if let joint = body.joint { map[joint] = body.name }
        }
        return map
    }()

    /// A handle for every policy joint, at a pose.
    ///
    /// The mouth is skipped for the same reason everywhere else does: handles
    /// exist to author motion the robot can perform, and the editor already
    /// gives the mouth its own slider.
    public static func handles(at pose: [Double]) -> [Handle] {
        // A POSE OF THE WRONG WIDTH DRAWS NOTHING RATHER THAN TRAPPING.
        // `DuckKinematics.bodyPoses` preconditions on all fifteen joints, and
        // the editor can hand this a key that a malformed file left short. A
        // crash is not a better answer than an empty stage: the app's job then
        // is to say the draft is unreadable, which it cannot do from inside a
        // dead process.
        guard pose.count == DuckModel.jointCount else { return [] }
        let poses = DuckKinematics.bodyPoses(jointAngles: pose)
        return (0..<DuckModel.policyJointCount).compactMap { slot in
            let joint = DuckModel.jointOfPolicySlot(slot)
            let name = DuckModel.jointNames[joint]
            guard let bodyName = movedBody[name], let body = poses[bodyName] else { return nil }
            let range = DuckModel.jointRanges[joint]
            let local = downstreamOffset[bodyName] ?? DuckVector(1, 0, 0)
            // Off-axis part only: the along-axis part of a link is a slide, and
            // a hinge does not slide. Then out to `minimumLever` if the link is
            // shorter than that off its own axis.
            var flat = DuckVector(local.x, local.y, 0)
            var reach = magnitude(flat)
            if reach < 1e-9 { flat = DuckVector(1, 0, 0); reach = 1 }
            let scale = max(minimumLever, reach) / reach
            let lever = body.orientation.rotate(
                DuckVector(flat.x * scale, flat.y * scale, flat.z * scale))
            return Handle(
                joint: joint,
                name: name,
                pivot: body.position,
                axis: body.orientation.rotate(DuckVector(0, 0, 1)),
                angle: pose.indices.contains(joint) ? pose[joint] : 0,
                lower: range.lower,
                upper: range.upper,
                lever: lever)
        }
    }

    /// What hangs off each body, in that body's own frame: the child body's
    /// origin, or — for the two ankles, which have no child body — that body's
    /// own site, which is the foot. Derived from the chain, like `movedBody`,
    /// so a sixteenth body cannot leave a handle with a hand-written arm.
    static let downstreamOffset: [String: DuckVector] = {
        var map: [String: DuckVector] = [:]
        for body in DuckKinematics.bodies {
            guard let parent = body.parent else { continue }
            if map[parent] == nil { map[parent] = body.position }
        }
        for body in DuckKinematics.bodies where map[body.name] == nil {
            if let site = body.sites.first { map[body.name] = site.position }
        }
        return map
    }()

    /// The angle change a drag asks for.
    ///
    /// HOW IT WORKS, because the view must not re-derive it: the natural
    /// motion of a grabbed point on a hinge is along the TANGENT — the axis
    /// crossed with the arm from the pivot to the grab point. A drag is
    /// projected onto that tangent, and the projected length over the arm's
    /// length is the angle, by the small-arc approximation that makes dragging
    /// feel linear. The sign falls out of the cross product, which is what
    /// makes "drag up" open a knee on the left leg and close it on the right —
    /// the two knees' axes point opposite ways, exactly as the robot's do.
    ///
    /// `grab` is where the finger took hold (usually the marker itself) and
    /// `drag` is the world-space displacement the gesture has produced so far.
    /// Both are in the model frame; the view converts its screen delta using
    /// the camera it already owns.
    public static func angleDelta(handle: Handle, grab: DuckVector,
                                  drag: DuckVector) -> Double {
        let arm = grab - handle.pivot
        let tangent = cross(handle.axis, arm)
        let length = magnitude(tangent)
        // A grab AT the pivot has no arm and no defined direction — the view
        // should not offer one, and if it does, the honest answer is "this
        // drag means nothing" rather than a division by almost-zero that
        // spins the joint to a stop.
        guard length > 1e-6 else { return 0 }
        let along = dot(drag, tangent) / length          // metres along the tangent
        let radius = magnitude(arm)
        guard radius > 1e-6 else { return 0 }
        return along / radius
    }

    /// The dragged angle, clamped to the joint's travel — what the editor
    /// actually writes into the keyframe.
    public static func dragged(handle: Handle, grab: DuckVector,
                               drag: DuckVector) -> Double {
        let proposed = handle.angle + angleDelta(handle: handle, grab: grab, drag: drag)
        return min(max(proposed, handle.lower), handle.upper)
    }

    // MARK: - the screen half

    /// A point in view coordinates: points, x right, y DOWN, as every Apple
    /// view reports them. NOT `CGPoint` — this package has no CoreGraphics,
    /// on purpose, because it is tested on Linux.
    public struct ScreenPoint: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    /// What a thumb on this handle can do, worked out once when the finger
    /// lands and held for the whole drag.
    ///
    /// HELD, NOT RECOMPUTED. The gain depends on how far the joint is from the
    /// camera, and the camera moves — a gain re-derived every frame would make
    /// the joint accelerate under a finger that is moving steadily, which reads
    /// as the app fighting you.
    public enum Grab: Equatable, Sendable {
        /// `direction` is a unit vector in view points; a drag along it opens
        /// the joint, and against it closes the joint.
        case draggable(radiansPerPoint: Double, direction: ScreenPoint)
        /// The arc is edge-on to the camera. A drag here would be a guess.
        case edgeOn
    }

    /// Turn three projected points into a drag law.
    ///
    /// The caller projects `handle.pivot`, `handle.grip` and `handle.swung`
    /// with the camera it already owns. `swung − grip` is then this joint's
    /// direction of travel on screen over `probeRadians` — direction and scale
    /// in one — so the kit never sees a camera and the view never sees a
    /// kinematic chain.
    ///
    /// IT REFUSES IN TWO CASES, both of which the same sentence covers.
    /// Less than `edgeOnPoints` of screen movement per radian means the arc is
    /// being seen edge-on: a whole radian barely moves the marker, so a
    /// straight drag has no honest direction and any gain would be enormous. An ARM shorter than
    /// `edgeOnPoints` means the link is pointing at the camera and the marker
    /// is sitting on top of its own pivot: it moves plenty, but nothing on
    /// screen tells the person which way, and a handle you cannot aim is worse
    /// than a slider.
    public static func grab(handle: Handle, pivot: ScreenPoint,
                            grip: ScreenPoint, swung: ScreenPoint) -> Grab {
        let arm = separation(pivot, grip)
        let chordX = swung.x - grip.x
        let chordY = swung.y - grip.y
        let chord = (chordX * chordX + chordY * chordY).squareRoot()
        let perRadian = chord / probeRadians
        guard perRadian >= edgeOnPoints, arm >= edgeOnPoints, chord > 0 else { return .edgeOn }

        // Points of screen movement per radian, off the probe itself.
        let raw = 1 / perRadian
        // Then held inside the travel window, so no joint needs a metre of
        // thumb and none crosses its whole range in a twitch.
        let travel = handle.travel
        var radiansPerPoint = raw
        if travel > 0 {
            radiansPerPoint = min(max(raw, travel / slowestFullTravelPoints),
                                  travel / fastestFullTravelPoints)
        }
        return .draggable(radiansPerPoint: radiansPerPoint,
                          direction: ScreenPoint(x: chordX / chord, y: chordY / chord))
    }

    /// The angle a drag of `(dx, dy)` view points asks for, clamped to travel.
    /// An edge-on handle answers with the angle it already had: a refusal is a
    /// joint that did not move, never a joint that moved a little.
    /// The law for THIS frame with the gain of the frame the drag began on.
    ///
    /// THE DIRECTION FOLLOWS THE ARC, THE GAIN DOES NOT. A drag's direction
    /// fixed at its first instant runs away from the thumb as the limb swings
    /// through its arc — the marker turns round under a finger that is still
    /// moving the same way — so the direction is re-read from each frame's
    /// projected grip and swung. The gain stays what the first frame set,
    /// because a pinch mid-drag must not change how far a point of thumb
    /// turns the joint. Feed `dragged` the PER-TICK delta with the handle's
    /// current angle, not the total translation from the start.
    public static func grab(handle: Handle, pivot: ScreenPoint,
                            grip: ScreenPoint, swung: ScreenPoint,
                            keepingGainOf previous: Grab) -> Grab {
        let fresh = grab(handle: handle, pivot: pivot, grip: grip, swung: swung)
        guard case .draggable(let gain, _) = previous,
              case .draggable(_, let direction) = fresh else { return fresh }
        return .draggable(radiansPerPoint: gain, direction: direction)
    }

    public static func dragged(handle: Handle, grab: Grab,
                               dx: Double, dy: Double) -> Double {
        guard case .draggable(let radiansPerPoint, let direction) = grab else {
            return handle.angle
        }
        let along = dx * direction.x + dy * direction.y
        return min(max(handle.angle + along * radiansPerPoint, handle.lower), handle.upper)
    }

    /// One target actually drawn on the stage.
    public struct Placed: Equatable, Sendable, Identifiable {
        public let joint: Int
        public let at: ScreenPoint
        /// Farther from the camera than the trunk, so it is drawn dim. Not an
        /// occlusion test — the duck is not opaque enough for one to be worth
        /// the frame time, and a dim target is still tappable.
        public let behind: Bool
        /// Other joints whose targets landed on top of this one.
        public let clustered: [Int]
        public var id: Int { joint }

        public init(joint: Int, at: ScreenPoint, behind: Bool, clustered: [Int]) {
            self.joint = joint; self.at = at; self.behind = behind
            self.clustered = clustered
        }

        /// How many joints this one target stands for.
        public var count: Int { clustered.count + 1 }
    }

    /// Fourteen joints on a stage the size of a playing card.
    ///
    /// THE PROBLEM IS NOT DRAWING THEM, IT IS TAPPING THEM. At the angles
    /// people actually orbit to, a hip yaw, a hip roll and a hip pitch project
    /// within a few points of each other, and a 44-point target drawn over each
    /// means three overlapping targets where the top one silently wins. So no
    /// two targets are ever drawn closer than `minimumSeparation`: the first to
    /// arrive keeps the spot and the rest fold into it, and the folded ones are
    /// named so the view can offer to spread them.
    ///
    /// Input order is the caller's priority order — the first joint at a spot
    /// is the one that keeps it.
    /// `place`, keeping only targets whose whole box sits inside a viewport.
    ///
    /// A TARGET AT THE EDGE STEALS THE ORBIT. The band a thumb swipes in to
    /// orbit the stage is the band a handle at the edge would sit in, and
    /// orbiting is the fix the edge-on refusal prescribes — so a handle whose
    /// box crosses the edge is dropped rather than drawn half off the glass.
    public static func place(_ projected: [(joint: Int, at: ScreenPoint, depth: Double)],
                             trunkDepth: Double, minimumSeparation: Double,
                             within width: Double, _ height: Double,
                             inset: Double) -> [Placed] {
        place(projected, trunkDepth: trunkDepth, minimumSeparation: minimumSeparation)
            .filter { $0.at.x >= inset && $0.at.y >= inset
                   && $0.at.x <= width - inset && $0.at.y <= height - inset }
    }

    public static func place(_ projected: [(joint: Int, at: ScreenPoint, depth: Double)],
                             trunkDepth: Double,
                             minimumSeparation: Double) -> [Placed] {
        var anchors: [(joint: Int, at: ScreenPoint, behind: Bool, clustered: [Int])] = []
        for item in projected {
            if let index = anchors.firstIndex(where: {
                separation($0.at, item.at) < minimumSeparation
            }) {
                anchors[index].clustered.append(item.joint)
            } else {
                anchors.append((item.joint, item.at, item.depth > trunkDepth, []))
            }
        }
        return anchors.map {
            Placed(joint: $0.joint, at: $0.at, behind: $0.behind, clustered: $0.clustered)
        }
    }

    static func separation(_ a: ScreenPoint, _ b: ScreenPoint) -> Double {
        let dx = a.x - b.x, dy = a.y - b.y
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - what the screen says

    /// The refusal on an edge-on hinge. IT SAYS WHAT TO DO. "Cannot drag this
    /// joint" would leave somebody tapping harder at a handle that is working
    /// exactly as it should from a different angle.
    public static let edgeOnSaid =
        "This hinge is pointing at the camera, so a drag here has no direction. Orbit the stage "
      + "a little and the handle takes a drag again."

    /// Why the handles are inert when the playhead is between keyframes: the
    /// pose on screen is interpolated, so there is nothing there to write to.
    public static let betweenKeyframesSaid =
        "The playhead is between keyframes, so there is no pose here to change. Tap the keyframe "
      + "you want to edit and the handles come back."

    /// The label on a target that stands for several joints.
    public static func clusterSaid(_ count: Int) -> String {
        "\(count) joints here — tap to spread them"
    }

    /// The one action a handle's pill offers besides dragging: put this joint
    /// back where the policy holds it. A button, not a double-tap — a double
    /// tap on the rest of the stage resets the camera, and the same gesture
    /// meaning "overwrite this joint" on a 44 pt disc was a trap.
    public static let homeActionSaid = "Home"

    /// Why there is no handle on the beak. FOURTEEN HANDLES, FIFTEEN JOINTS,
    /// and the missing one is a fact about the policies rather than an
    /// oversight worth hiding.
    public static let noMouthHandleSaid =
        "The beak has no handle on the stage: no policy commands it, so it is not one of the "
      + "joints a move is authored against. Its slider is below with the rest."

    // MARK: - vector helpers (DuckVector has +/-, not these)

    static func cross(_ a: DuckVector, _ b: DuckVector) -> DuckVector {
        DuckVector(a.y * b.z - a.z * b.y,
                   a.z * b.x - a.x * b.z,
                   a.x * b.y - a.y * b.x)
    }
    static func dot(_ a: DuckVector, _ b: DuckVector) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }
    static func magnitude(_ v: DuckVector) -> Double { dot(v, v).squareRoot() }
}
