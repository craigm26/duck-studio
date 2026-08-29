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
        public var id: Int { joint }
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
        let poses = DuckKinematics.bodyPoses(jointAngles: pose)
        return (0..<DuckModel.policyJointCount).compactMap { slot in
            let joint = DuckModel.jointOfPolicySlot(slot)
            let name = DuckModel.jointNames[joint]
            guard let bodyName = movedBody[name], let body = poses[bodyName] else { return nil }
            let range = DuckModel.jointRanges[joint]
            return Handle(
                joint: joint,
                name: name,
                pivot: body.position,
                axis: body.orientation.rotate(DuckVector(0, 0, 1)),
                angle: pose.indices.contains(joint) ? pose[joint] : 0,
                lower: range.lower,
                upper: range.upper)
        }
    }

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
