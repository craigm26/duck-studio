import Foundation
import DuckKit

/// A person, as seventeen points in space and the angles between them.
///
/// WHAT THIS IS AND IS NOT. A body-pose model on the phone — Vision's 3D
/// skeleton, ARKit's body anchor, anything that answers "where are the knees"
/// — hands back joint positions in some camera-flavoured coordinate frame it
/// chose. This type takes those positions and answers the only questions the
/// duck can act on: how far each thigh is swung forward, how bent each knee
/// is, how far each leg is out to the side, which way the head is turned and
/// nodded, and how high the hands are. Every answer is an angle in the
/// PERSON'S OWN FRAME — built from their hips and spine, below — so it does not
/// matter where the camera was, whether the phone was held sideways, or which
/// way the model's axes point. That is the whole reason the frame is derived
/// rather than assumed.
///
/// IT IMPORTS NO VISION, NO ARKit AND NO simd, AND THAT IS THE POINT. The app
/// target converts a framework's points into `DuckVector`s and hands them over;
/// this file does the deciding, so every angle it reports can be asserted by
/// `swift test` on a Pi with no camera in the room. `DuckVector` is the kit's
/// own three numbers, chosen over simd because simd does not exist on Linux —
/// the same reason `DuckKinematics` gives for its own arithmetic.
///
/// HANDEDNESS. The person's frame is `left`, `up`, `forward` with
/// `forward = left × up`, which is a right-handed frame — the duck's own
/// (x forward, y left, z up) is the same one. If the source's coordinates are
/// left-handed the person comes out facing backwards, which the app fixes by
/// swapping left and right points before they get here (`mirrored`), not by
/// anything in this file guessing.
public struct HumanFigure: Equatable, Sendable {

    /// The joints a body model is asked for, named as Vision names them so the
    /// app-side mapping is a one-to-one switch with nothing to get backwards.
    public enum Joint: String, CaseIterable, Equatable, Sendable {
        case root, spine, centerShoulder, centerHead, topHead
        case leftShoulder, leftElbow, leftWrist
        case rightShoulder, rightElbow, rightWrist
        case leftHip, leftKnee, leftAnkle
        case rightHip, rightKnee, rightAnkle

        /// The same joint on the other side, or itself for a joint on the
        /// midline. What `mirrored` swaps.
        public var opposite: Joint {
            switch self {
            case .leftShoulder: return .rightShoulder
            case .leftElbow: return .rightElbow
            case .leftWrist: return .rightWrist
            case .leftHip: return .rightHip
            case .leftKnee: return .rightKnee
            case .leftAnkle: return .rightAnkle
            case .rightShoulder: return .leftShoulder
            case .rightElbow: return .leftElbow
            case .rightWrist: return .leftWrist
            case .rightHip: return .leftHip
            case .rightKnee: return .leftKnee
            case .rightAnkle: return .leftAnkle
            case .root, .spine, .centerShoulder, .centerHead, .topHead: return self
            }
        }
    }

    /// A 3×3 rotation, row-major, in the same coordinates as the points.
    ///
    /// Only the head needs one: a head's pitch can be read off where the top of
    /// it is, but a head turned to look sideways moves no point this skeleton
    /// has — there is no nose — so the turn has to come from the joint's own
    /// orientation, when the model reports one.
    public struct Rotation: Equatable, Sendable {
        public let m: [Double]

        public init(rowMajor m: [Double]) {
            precondition(m.count == 9, "a rotation is nine numbers")
            self.m = m
        }

        public static let identity = Rotation(rowMajor: [1, 0, 0, 0, 1, 0, 0, 0, 1])

        func apply(_ v: DuckVector) -> DuckVector {
            DuckVector(m[0] * v.x + m[1] * v.y + m[2] * v.z,
                       m[3] * v.x + m[4] * v.y + m[5] * v.z,
                       m[6] * v.x + m[7] * v.y + m[8] * v.z)
        }

        var transposed: Rotation {
            Rotation(rowMajor: [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]])
        }

        static func * (a: Rotation, b: Rotation) -> Rotation {
            var out = [Double](repeating: 0, count: 9)
            for r in 0..<3 {
                for c in 0..<3 {
                    out[r * 3 + c] = a.m[r * 3] * b.m[c] + a.m[r * 3 + 1] * b.m[3 + c]
                                   + a.m[r * 3 + 2] * b.m[6 + c]
                }
            }
            return Rotation(rowMajor: out)
        }
    }

    public let points: [Joint: DuckVector]
    /// The head joint's orientation and the torso's, when the source has them.
    /// Both or neither: a head turn is measured RELATIVE to the shoulders, and
    /// one without the other would be a turn measured against nothing.
    public let headRotation: Rotation?
    public let torsoRotation: Rotation?

    public init(points: [Joint: DuckVector],
                headRotation: Rotation? = nil, torsoRotation: Rotation? = nil) {
        self.points = points
        self.headRotation = headRotation
        self.torsoRotation = torsoRotation
    }

    /// The joints a frame cannot be built without.
    public static let required: [Joint] = [.leftHip, .rightHip, .root, .centerShoulder]

    /// What is missing, or empty when the figure can be read.
    public var missing: [Joint] { Self.required.filter { points[$0] == nil } }

    /// The same person with left and right swapped.
    ///
    /// A MIRROR IS WHAT A PERSON FACING A PHONE EXPECTS. When you raise your
    /// right hand in front of a front camera, the picture raises the hand on
    /// the right of the screen — and a duck facing you that raised ITS right
    /// would look wrong. Swapping the sides is also what puts a left-handed
    /// source frame right way round, which is why it is one switch and not two.
    public var mirrored: HumanFigure {
        var swapped: [Joint: DuckVector] = [:]
        for (joint, point) in points { swapped[joint.opposite] = point }
        return HumanFigure(points: swapped, headRotation: headRotation,
                           torsoRotation: torsoRotation)
    }

    // MARK: - the person's own frame

    /// Left, up and forward, unit length, built from the hips and the spine.
    public struct Frame: Equatable, Sendable {
        public let left: DuckVector
        public let up: DuckVector
        public let forward: DuckVector
    }

    /// The frame, or nil when the hips or the spine are missing or coincide.
    ///
    /// `up` is the spine — root to the centre of the shoulders — rather than
    /// the source's own vertical, so a person bending over reads as a person
    /// bending over and not as a person whose legs have swung backwards. `left`
    /// is the hip line with its spine component removed, so the two are square
    /// even when the model's hips are not level.
    public var frame: Frame? {
        guard let lh = points[.leftHip], let rh = points[.rightHip],
              let root = points[.root], let shoulders = points[.centerShoulder]
        else { return nil }
        guard let up = (shoulders - root).unit else { return nil }
        let hip = lh - rh
        let square = hip - up.scaled(hip.dot(up))
        guard let left = square.unit else { return nil }
        return Frame(left: left, up: up, forward: left.cross(up))
    }

    // MARK: - what the duck can act on

    /// One leg, as three angles in radians.
    public struct Leg: Equatable, Sendable {
        /// How far the thigh is swung forward of straight down. Positive in
        /// front; a person standing is 0 and sitting is about π/2.
        public let hipFlexion: Double
        /// How far the knee is bent. 0 straight, π/2 a right angle.
        public let kneeFlexion: Double
        /// How far the thigh is swung OUT to that leg's own side. Positive is
        /// outward for both legs, so a person standing with feet together is 0
        /// on both and a star jump is positive on both.
        public let abduction: Double
    }

    /// The head, relative to the shoulders, radians.
    public struct Head: Equatable, Sendable {
        /// Positive nods forward and down.
        public let pitch: Double
        /// Positive turns toward the person's left. 0 without a rotation.
        public let yaw: Double
        /// Positive tilts the top of the head toward the person's left. 0
        /// without a rotation.
        public let roll: Double
    }

    /// Everything a duck is retargeted from, read off one figure.
    public struct Reading: Equatable, Sendable {
        public let left: Leg
        public let right: Leg
        public let head: Head
        /// How high the higher hand is, 0 at shoulder height and below, 1 with
        /// the arm straight up. The duck has no arms; see `PoseRetarget`.
        public let armRaise: Double
    }

    /// The reading, or nil when there is no frame to read against.
    ///
    /// A LEG WITH A MISSING JOINT READS AS STANDING, not as an error. A body
    /// model drops a joint it cannot see — an ankle behind a desk — and a duck
    /// that snapped to a refusal every time a foot went out of shot would be
    /// unusable in any real room. Standing is the pose the duck is already in.
    public var reading: Reading? {
        guard let frame else { return nil }
        return Reading(left: leg(hip: .leftHip, knee: .leftKnee, ankle: .leftAnkle,
                                 outward: 1, in: frame),
                       right: leg(hip: .rightHip, knee: .rightKnee, ankle: .rightAnkle,
                                  outward: -1, in: frame),
                       head: head(in: frame),
                       armRaise: armRaise(in: frame))
    }

    private func leg(hip: Joint, knee: Joint, ankle: Joint, outward: Double,
                     in frame: Frame) -> Leg {
        guard let h = points[hip], let k = points[knee], let thigh = (k - h).unit
        else { return Leg(hipFlexion: 0, kneeFlexion: 0, abduction: 0) }
        // Straight down is -up. Flexion is the thigh's angle from it in the
        // sagittal plane; abduction its angle from it in the frontal plane.
        let down = -thigh.dot(frame.up)
        let flexion = atan2(thigh.dot(frame.forward), down)
        let abduction = atan2(thigh.dot(frame.left) * outward, down)
        var kneeFlexion = 0.0
        if let a = points[ankle], let shank = (a - k).unit {
            kneeFlexion = acos(min(max(thigh.dot(shank), -1), 1))
        }
        return Leg(hipFlexion: flexion, kneeFlexion: kneeFlexion, abduction: abduction)
    }

    private func head(in frame: Frame) -> Head {
        var pitch = 0.0
        if let c = points[.centerHead], let t = points[.topHead], let crown = (t - c).unit {
            pitch = atan2(crown.dot(frame.forward), crown.dot(frame.up))
        }
        guard let headRotation, let torsoRotation else {
            return Head(pitch: pitch, yaw: 0, roll: 0)
        }
        // The head's turn relative to the torso, in the source's coordinates,
        // then measured about the person's own axes. Convention-free: whatever
        // the model means by a joint's local axes, the two frames share it and
        // the difference between them is a real rotation of the head.
        let relative = headRotation * torsoRotation.transposed
        let turned = relative.apply(frame.forward)
        let yaw = atan2(turned.dot(frame.left), turned.dot(frame.forward))
        let tilted = relative.apply(frame.up)
        let roll = atan2(tilted.dot(frame.left), tilted.dot(frame.up))
        return Head(pitch: pitch, yaw: yaw, roll: roll)
    }

    private func armRaise(in frame: Frame) -> Double {
        func raise(shoulder: Joint, elbow: Joint, wrist: Joint) -> Double {
            guard let s = points[shoulder], let w = points[wrist] else { return 0 }
            let reach: Double
            if let e = points[elbow] {
                reach = (e - s).length + (w - e).length
            } else {
                reach = (w - s).length
            }
            guard reach > 0 else { return 0 }
            return (w - s).dot(frame.up) / reach
        }
        let best = max(raise(shoulder: .leftShoulder, elbow: .leftElbow, wrist: .leftWrist),
                       raise(shoulder: .rightShoulder, elbow: .rightElbow, wrist: .rightWrist))
        return min(max(best, 0), 1)
    }
}

// MARK: - the three vector operations this file needs and DuckVector lacks

extension DuckVector {
    func dot(_ o: DuckVector) -> Double { x * o.x + y * o.y + z * o.z }

    func cross(_ o: DuckVector) -> DuckVector {
        DuckVector(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }

    func scaled(_ s: Double) -> DuckVector { DuckVector(x * s, y * s, z * s) }

    /// Unit length, or nil for a zero or non-finite vector.
    var unit: DuckVector? {
        let n = length
        guard n.isFinite, n > 1e-9 else { return nil }
        return scaled(1 / n)
    }

    static prefix func - (v: DuckVector) -> DuckVector { DuckVector(-v.x, -v.y, -v.z) }
}
