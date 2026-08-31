import Foundation
import DuckKit

/// Where to put the trunk so a drawn pose stands on the floor.
///
/// THE PROBLEM THIS SOLVES, MEASURED. A draft carries joint angles and no root:
/// physics produced the body's height, and nothing in an authored motion knows
/// it. So the stage pinned the trunk at standing height — 116 mm — and drew the
/// joints under it. For most motions that is invisible: measured against the
/// real meshes, `hold`, `ground_pick`, `roulade` and `kick_left` all read within
/// 2 mm of the floor with the trunk pinned.
///
/// For the two clips whose body height actually changes it is not invisible at
/// all. `sit` ends 56.9 mm lower than it started, and pinned, its last frame
/// draws the feet **54.9 mm in the air**. `stand` is the same motion backwards
/// and floats by 55.0 mm at its first frame. A person looking at that sees a
/// duck hovering, and reasonably concludes the data is wrong — it is not.
/// Every clip, evaluated at the root physics actually recorded, has its feet on
/// the floor within 2 mm.
///
/// SO THE FIX IS TO DROP THE BODY, NOT TO CHANGE THE POSE. The lowest point of
/// the pose goes on the floor and the joints are untouched.
///
/// AND IT IS STILL NOT PHYSICS, WHICH THE CAPTION HAS TO SAY. Resting the feet
/// on the floor is a drawing decision: it assumes the duck is standing on the
/// ground, so a motion that would genuinely leave the ground is drawn as though
/// it had not, and nothing here knows whether the pose could hold that weight.
/// It also restores no horizontal travel — a draft still carries none.
public enum StageFloor {

    /// The root that puts this pose's lowest point on the floor.
    ///
    /// TAKES THE MEASUREMENT, NOT THE MESHES. The clearance comes from
    /// `DuckGroundClearance`, which samples the real meshes over 26 support
    /// directions so a rolled body still reports its true lowest point. Passing
    /// the number in keeps this rule where a test can reach it without StudioKit
    /// taking a dependency on the mesh bundle.
    public static func resting(_ root: DuckIntentClip.Root,
                               clearanceMetres: Double) -> DuckIntentClip.Root {
        guard clearanceMetres.isFinite else { return root }
        return DuckIntentClip.Root(x: root.x, y: root.y,
                                   z: root.z - clearanceMetres,
                                   quaternion: root.quaternion)
    }

    /// How far below standing this pose puts the body, in metres. Positive
    /// means lower than standing.
    ///
    /// THIS IS THE NUMBER WORTH SHOWING, and it is the same measurement that
    /// used to be reported as a float. A pose whose feet were 55 mm in the air
    /// under a pinned trunk is a pose that sits 55 mm below standing — the
    /// first is alarming and the second is the fact.
    public static func drop(clearanceMetres: Double) -> Double { clearanceMetres }
}
