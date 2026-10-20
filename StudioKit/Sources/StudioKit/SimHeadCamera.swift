import Foundation
import DuckKit

/// Where the simulated duck's head camera is and where it looks, from the duck's own kinematics.
///
/// WHY THIS EXISTS. Dream-1 drives from the head camera, and a duck in this app's own physics has
/// none: the bench reports joints and a root, not pictures. So the app draws one (`SimHeadCameraView`,
/// RealityKit) from the pose this works out, and a person with no robot can record runs and run
/// Dream-1 on the phone's duck. It is a drawing, not a camera: no lens, no noise, no light like a
/// room's. A model trained on these pictures learns this stage, not a floor at home.
///
/// THE CAMERA IS POLLEN'S. Its position is the model's `head_camera` site on `bottom_head_shell`.
/// Its direction is that body's -z: the MJCF's camera looks along +z, and Pollen's own simulator
/// (`mjlab_microduck/sim/camera.py`) measured it as exactly backwards, "the camera's view direction
/// is -x where both of those are +x", and turns it round. Its field of view is MuJoCo's default 45
/// degrees, vertical, which at 16:9 is the 72.7 degrees across the card reader uses. Its picture is
/// drawn the right way up, as `mediad`'s `/frame` serves a real one.
public enum SimHeadCamera {
    public static let fovyDegrees = 45.0
    public static let body = "bottom_head_shell"
    public static let site = "head_camera"

    public struct Pose: Equatable, Sendable {
        /// In the model's world: metres, z up, x the way the duck faces at home.
        public let position: DuckVector
        public let forward: DuckVector
        public let up: DuckVector
    }

    /// The head-frame direction that is "up" in the picture, fixed at the home pose so the picture
    /// tilts with the head rather than staying level with the world.
    static let headUp: DuckVector = {
        let home = DuckKinematics.bodyPoses(jointAngles: DuckModel.homePose)[body]!.orientation
        let worldUp = home.conjugate.rotate(DuckVector(0, 0, 1))
        let f = DuckVector(0, 0, -1)
        return (worldUp - f * worldUp.dot(f)).normalized
    }()

    /// The camera for a root (the trunk, as the bench reports it) and fifteen joint angles.
    public static func pose(rootPosition: DuckVector, rootOrientation: DuckQuaternion, jointAngles: [Double]) -> Pose {
        let placed = DuckKinematics.placement(forRoot: rootPosition, orientation: rootOrientation)
        let head = DuckKinematics.bodyPoses(jointAngles: jointAngles)[body]!
        let siteLocal = DuckKinematics.sitePositions(jointAngles: jointAngles)[site]!
        let world = { (v: DuckVector) in placed.position + placed.orientation.rotate(v) }
        let turn = { (v: DuckVector) in placed.orientation.rotate(head.orientation.rotate(v)) }
        return Pose(position: world(siteLocal), forward: turn(DuckVector(0, 0, -1)).normalized,
                    up: turn(headUp).normalized)
    }

    /// The same, for the bench's own state block.
    public static func pose(_ live: DuckDrive.Live) -> Pose {
        let r = live.stance.root
        return pose(rootPosition: DuckVector(r.x, r.y, r.z),
                    rootOrientation: DuckQuaternion(w: r.quaternion.0, x: r.quaternion.1,
                                                    y: r.quaternion.2, z: r.quaternion.3),
                    jointAngles: live.stance.jointAngles)
    }
}

/// What the simulated duck can see: a taped mat of 30 cm squares, and three things to walk to.
///
/// SMALL ON PURPOSE. Each thing has a name a task can use ("walk to the red mat", "go to the
/// ball"), and nothing moves, so a run recorded today is the same stage as one recorded tomorrow.
public enum DreamPracticeWorld {
    public struct Thing: Equatable, Sendable {
        public enum Shape: Equatable, Sendable { case tile(width: Double, depth: Double), ball(radius: Double) }
        public let name: String
        public let shape: Shape
        /// The centre, in the model's world (metres, z up).
        public let x: Double, y: Double
        public let rgb: (Double, Double, Double)
        public static func == (a: Thing, b: Thing) -> Bool {
            a.name == b.name && a.shape == b.shape && a.x == b.x && a.y == b.y
        }
    }

    public static let square = 0.30
    /// The mat: 5 squares ahead of the duck, 3 across, the duck starting on the middle of the first.
    public static let matSquaresAhead = 5, matSquaresAcross = 3
    public static let tapeWidth = 0.019
    public static let floorRGB = (0.86, 0.84, 0.80)
    public static let tapeRGB = (0.12, 0.12, 0.14)
    /// Behind everything: RealityKit's off-screen picture is transparent there, and a video has no
    /// transparency, so without a sky the top of every frame would be black.
    public static let skyRGB = (0.80, 0.86, 0.92)

    public static let things: [Thing] = [
        Thing(name: "the red mat", shape: .tile(width: 0.30, depth: 0.30), x: 1.20, y: 0.00, rgb: (0.85, 0.12, 0.10)),
        Thing(name: "the blue mat", shape: .tile(width: 0.30, depth: 0.30), x: 0.60, y: 0.60, rgb: (0.10, 0.30, 0.85)),
        Thing(name: "the ball", shape: .ball(radius: 0.035), x: 0.90, y: -0.45, rgb: (0.98, 0.78, 0.10)),
    ]

    /// The tape lines, as (centre x, centre y, length along x, length along y).
    public static var tape: [(Double, Double, Double, Double)] {
        let x0 = -square / 2, x1 = x0 + Double(matSquaresAhead) * square
        let y0 = -Double(matSquaresAcross) * square / 2, y1 = -y0
        var lines: [(Double, Double, Double, Double)] = []
        for i in 0...matSquaresAhead {
            let x = x0 + Double(i) * square
            lines.append((x, 0, tapeWidth, y1 - y0 + tapeWidth))
        }
        for j in 0...matSquaresAcross {
            let y = y0 + Double(j) * square
            lines.append(((x0 + x1) / 2, y, x1 - x0 + tapeWidth, tapeWidth))
        }
        return lines
    }

    public static let tasks = ["walk to the red mat", "walk to the blue mat", "walk to the ball", "turn to face the ball"]
}

fileprivate extension DuckVector {
    static func * (v: DuckVector, s: Double) -> DuckVector { DuckVector(v.x * s, v.y * s, v.z * s) }
    var normalized: DuckVector { let l = length; return l > 0 ? self * (1 / l) : self }
}

fileprivate extension DuckQuaternion {
    var conjugate: DuckQuaternion { DuckQuaternion(w: w, x: -x, y: -y, z: -z) }
}
