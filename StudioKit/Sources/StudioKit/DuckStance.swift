import Foundation
import DuckKit

/// A robot standing somewhere: the joints, and where the trunk is.
///
/// WHY THIS IS NOT IN THE VIEW. A stage needs a pose to draw before any clip is
/// playing — an empty scene editor, a bench with no observation yet — and the
/// obvious thing is to write `DuckModel.homePose` and a plausible height at the
/// call site. Those are two pieces of robot knowledge, and the height is a
/// MEASURED one: 116.22 mm is where the standing policy settles in MuJoCo, not
/// a number anybody chose. Both belong where they can be asserted on Linux
/// rather than eyeballed on a phone.
public struct DuckStance: Equatable, Sendable {
    public let jointAngles: [Double]
    public let root: DuckIntentClip.Root

    public init(jointAngles: [Double], root: DuckIntentClip.Root) {
        self.jointAngles = jointAngles
        self.root = root
    }

    /// Where the trunk sits when the standing policy has settled, metres.
    ///
    /// MEASURED, NOT CHOSEN. `hold` — the clip recorded from
    /// `BEST_alpha_stand.onnx` — settles here, and the posture classifier's
    /// "standing" threshold of 100 mm is set below it for that reason. A round
    /// 0.12 would put the feet 4 mm under the floor.
    public static let standingHeight = 0.11622

    /// The robot at the origin, facing along +x, in the home stance. Every clip
    /// is de-origined to begin exactly here, so this is the fixed point the
    /// grid and every distance on screen are measured from.
    public static let home = DuckStance(
        jointAngles: DuckModel.homePose,
        root: .init(x: 0, y: 0, z: standingHeight, quaternion: (1, 0, 0, 0)))

    /// The robot standing on top of a step — which is what a stair scene is
    /// being built to make possible, and therefore the pose worth previewing
    /// while somebody builds one.
    public static func onTop(of step: DuckScene.Step) -> DuckStance {
        DuckStance(jointAngles: DuckModel.homePose,
                   root: .init(x: step.x, y: step.y, z: step.top + standingHeight,
                               quaternion: (1, 0, 0, 0)))
    }

    /// The pose at a moment in a recording.
    public static func at(_ pose: DuckIntentClip.Pose) -> DuckStance {
        DuckStance(jointAngles: pose.jointAngles, root: pose.root)
    }
}
