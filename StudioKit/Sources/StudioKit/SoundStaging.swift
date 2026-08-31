import Foundation
import DuckKit

/// Putting a duck call on screen: the step the web version does inside a
/// physics engine, done without one.
///
/// WHY THIS IS NOT JUST "PLAY THE ANIMATION". `DuckPerformance` is choreography
/// written the way the ROBOT takes it — a `DuckCommand` and a beak fraction, not
/// joint angles. On hardware those become a posture because a trained network
/// and a floor turn them into one. The website gets away with sending them
/// straight into MuJoCo compiled to WASM. A phone has neither, and
/// `DuckSimulation` records with tests that closing a policy's loop without
/// contact gives "a fixed point or an oscillation, never a walk". So something
/// has to decide what the duck looks like, and it should be one tested function
/// rather than a view improvising.
///
/// THE SPLIT IS THE ROBOT'S OWN, WHICH IS WHY IT IS DEFENSIBLE.
/// A Microduck's head is position-commanded and its legs are policy-driven:
/// `DuckCommand.head` is four numbers that land on `neck_pitch`, `head_pitch`,
/// `head_yaw` and `head_roll` — joints 5 to 8 — and the mouth is joint 9, in no
/// policy at all. So everything from the neck up here is EXACTLY what the robot
/// would be commanded, not an interpretation of it. That is most of every call:
/// six of the seven never command a twist, and their whole gesture is head and
/// beak.
///
/// THE LEGS ARE A RECORDING AND MUST NEVER BE DESCRIBED AS ANYTHING ELSE. They
/// come from a `DuckTrajectory` clip that was recorded from the trained policy
/// on a real plant, chosen by the same threshold the runtime uses. They are not
/// solved for this command. A duck standing during `coo` is standing because a
/// recording of standing is playing, and if the choreography asked for
/// something a recording cannot show, this would not show it.
///
/// AND THE BODY OFFSET IS DRAWN, NOT SOLVED. `bodyZ` is how far the robot is
/// asked to settle — just over a centimetre in `coo`, up in `alarm` — and on
/// hardware the standing policy achieves it by bending the legs. Here it moves
/// the trunk and the legs do not bend. It is the right height with the wrong
/// knees. Anything reporting this as a simulation would be lying; `caveat` is
/// the sentence that says so, and the screen shows it.
public enum SoundStaging {

    /// Which recorded gait a moment of a performance rides on.
    ///
    /// THE RUNTIME'S OWN THRESHOLD, not a judgement call: `DuckGait.locomotion`
    /// is what robotd uses to pick walking over standing, and it reads the
    /// twist alone so that a head sweep cannot make the duck think it is
    /// walking. `wheee` is the only call that crosses it, at twelve times the
    /// threshold, so there is no ambiguity anywhere in the seven.
    public static func gait(for pose: DuckPerformance.Pose) -> DuckTrajectory.Clip {
        switch DuckGait.locomotion(for: pose.command) {
        case .walk: return .walk
        default: return .stand
        }
    }

    /// The duck, at one instant of a call.
    ///
    /// `legs` is a pose sampled from the gait clip — its joint angles are used
    /// for the legs and thrown away above the neck, because the recording's
    /// head was doing whatever it was doing when it was recorded and this
    /// performance has its own opinion.
    public static func stance(_ pose: DuckPerformance.Pose,
                              legs: DuckTrajectory.Pose) -> DuckStance {
        var angles = legs.jointAngles
        // A clip that is not the shape this model expects is a bug in the
        // bundle, not something to paper over with padding.
        guard angles.count == DuckModel.jointNames.count else {
            return DuckStance(jointAngles: DuckModel.homePose, root: DuckStance.home.root)
        }

        let (neck, headPitch, headYaw, headRoll) = pose.command.head
        angles[5] = clamped(neck, 5)
        angles[6] = clamped(headPitch, 6)
        angles[7] = clamped(headYaw, 7)
        angles[8] = clamped(headRoll, 8)
        angles[DuckModel.mouthIndex] = pose.mouthTarget

        // The trunk moves by the commanded body offset. The floor is where the
        // floor is, so a settle that would put the feet through it stops at the
        // floor rather than going under — `standingHeight` is measured from the
        // clip that settles there, not rounded.
        let z = max(legs.z + pose.command.bodyZ, 0)
        return DuckStance(
            jointAngles: angles,
            root: DuckIntentClip.Root(x: legs.x, y: legs.y, z: z,
                                      quaternion: yaw(legs.yaw)))
    }

    /// Clamp to the joint's own travel. A commanded head angle is a REQUEST,
    /// and a servo that cannot reach it does not reach it — drawing past a
    /// stop shows a duck doing something the hardware would refuse.
    private static func clamped(_ angle: Double, _ joint: Int) -> Double {
        let travel = DuckModel.jointRanges[joint]
        return min(max(angle, travel.lower), travel.upper)
    }

    private static func yaw(_ radians: Double) -> (Double, Double, Double, Double) {
        (cos(radians / 2), 0, 0, sin(radians / 2))
    }

    // MARK: - what the screen is allowed to say

    /// The sentence that has to sit under a duck performing a call.
    public static let caveat =
        "The head and beak are exactly what the robot would be commanded — those joints are "
      + "position-controlled, so there is nothing to solve. The legs are a recording of the "
      + "trained walking and standing policies, not a simulation of this call, and the body "
      + "settles by moving the trunk rather than by bending the knees. It is the right height "
      + "with the wrong knees."

    /// Said once, above the seven, rather than seven times.
    public static let preamble =
        "Seven calls. Each one is a voice synthesised on this phone and a movement of the whole "
      + "body — not a sound effect with an animation over it. Hold the last two and they keep "
      + "going until you let go, the way the robot's own held calls decay when the holds stop "
      + "arriving."

    /// Whether a call keeps going while a finger is down, which changes what
    /// the button has to be.
    public static func isHeld(_ sound: DuckSound) -> Bool { sound.isHeld }
}
