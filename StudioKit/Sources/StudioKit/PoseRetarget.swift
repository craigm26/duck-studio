import Foundation
import DuckKit

/// A person's reading, put onto the duck's fifteen joints.
///
/// THE DUCK IS NOT A PERSON AND THIS FILE DOES NOT PRETEND IT IS. It has two
/// legs of three pitch joints, a hip that rolls and yaws, a head on a neck, a
/// beak, and no arms. So a human pose is not copied onto it — it is READ for
/// the five things the duck can do something with and then written as offsets
/// from the duck's own home stance:
///
/// - thigh forward → hip pitch, knee bent → knee, and the ankle follows so the
///   foot stays level, exactly as it does when a person crouches;
/// - leg out to the side → hip roll;
/// - head nodded, turned, tilted → head pitch, yaw, roll, on top of the neck;
/// - the higher hand → the beak. The duck has no arms, and the mouth is the one
///   joint no policy drives, so the arm channel goes there: raise a hand and
///   the beak opens. It is said on the screen rather than discovered.
///
/// EVERY SIGN BELOW WAS MEASURED, NOT ASSUMED. `DuckKinematics` was run on the
/// home pose with one joint moved 0.3 rad at a time and the foot and head sites
/// read back; `PoseRetargetTests` re-runs that measurement so the signs cannot
/// drift from the model. What it found, in the trunk frame (x forward, y left,
/// z up):
///
///   left_hip_pitch  + → left foot BACK       right_hip_pitch + → right foot FORWARD
///   left_knee       + → left foot FORWARD    right_knee      + → right foot BACK
///   left_hip_roll   + → left foot to +y (OUT)  right_hip_roll + → right foot to +y (IN)
///   ankle           foot stays level when  ankle offset = knee offset − hip offset
///   head_pitch      + → beak DOWN            head_yaw        + → beak to +y (LEFT)
///   head_roll       + → top of head to +y (LEFT)
///
/// The robot's home stance is exactly antisymmetric — every left joint is the
/// negation of its right counterpart — which is why the left and right rules
/// are the same rule with the sign flipped.
///
/// GAINS UNDER ONE ON THE LEGS, BY DESIGN. The duck's legs are 5 cm long and
/// already crouched at home; a person's full squat mapped one-to-one would fold
/// them past the point where the trunk sits on the floor. 0.7 keeps a deep
/// squat inside the travel and leaves a walk looking like a walk. The head is
/// one-to-one because the head is the part that reads as mimicry.
///
/// CLAMPED TO THE ROBOT'S TRAVEL, AND SAID. Nothing here can ask a joint for an
/// angle it does not have — `DuckModel.jointRanges` is the last word — and the
/// joints that were held back are named in the result so the screen can say
/// "your knee went further than the duck's can".
public enum PoseRetarget {

    /// How much of each human angle the duck takes.
    public struct Gains: Equatable, Sendable {
        public let hip: Double
        public let knee: Double
        public let roll: Double
        public let head: Double

        public init(hip: Double, knee: Double, roll: Double, head: Double) {
            self.hip = hip; self.knee = knee; self.roll = roll; self.head = head
        }

        public static let standard = Gains(hip: 0.7, knee: 0.7, roll: 0.7, head: 1.0)
    }

    /// The duck's pose, and what was done to get it.
    public struct Retargeted: Equatable, Sendable {
        /// All fifteen joints, radians, inside the robot's travel.
        public let pose: [Double]
        /// Joints that asked for more than the robot has and were held at the
        /// stop, by index into `DuckModel.jointNames`.
        public let clamped: [Int]
        public let reading: HumanFigure.Reading
    }

    /// How far inside a joint's stop the pose is kept. A pose exactly at a
    /// stop is one a servo has to lean on, and a draft at a stop is one that a
    /// hair of rounding puts outside it. THE MOUTH IS EXEMPT: its range is
    /// closed-to-open, not stop-to-stop, and a beak that could never quite
    /// close would be the margin showing.
    public static let travelMargin = 0.02

    /// The duck, standing as the person is standing.
    public static func duckPose(from reading: HumanFigure.Reading,
                                gains: Gains = .standard) -> Retargeted {
        var pose = DuckModel.homePose
        // Legs. Offsets first, because the ankle rule is written in offsets.
        let leftHip = -gains.hip * reading.left.hipFlexion
        let leftKnee = -gains.knee * reading.left.kneeFlexion
        let rightHip = gains.hip * reading.right.hipFlexion
        let rightKnee = gains.knee * reading.right.kneeFlexion
        pose[2] += leftHip
        pose[3] += leftKnee
        pose[4] += leftKnee - leftHip
        pose[12] += rightHip
        pose[13] += rightKnee
        pose[14] += rightKnee - rightHip
        pose[1] += gains.roll * reading.left.abduction
        pose[11] -= gains.roll * reading.right.abduction
        // Head, on top of the home neck.
        pose[6] += gains.head * reading.head.pitch
        pose[7] += gains.head * reading.head.yaw
        pose[8] += gains.head * reading.head.roll
        // The beak.
        pose[DuckModel.mouthIndex] = DuckModel.mouthTarget(open: reading.armRaise)

        var clamped: [Int] = []
        for joint in 0..<DuckModel.jointCount {
            let range = DuckModel.jointRanges[joint]
            let margin = joint == DuckModel.mouthIndex ? 0 : travelMargin
            let low = range.lower + margin
            let high = range.upper - margin
            guard pose[joint].isFinite else { pose[joint] = DuckModel.homePose[joint]; continue }
            if pose[joint] < low { pose[joint] = low; clamped.append(joint) }
            if pose[joint] > high { pose[joint] = high; clamped.append(joint) }
        }
        return Retargeted(pose: pose, clamped: clamped, reading: reading)
    }

    /// The duck from a figure, or nil when the figure has no frame to read.
    public static func duckPose(from figure: HumanFigure,
                                gains: Gains = .standard) -> Retargeted? {
        guard let reading = figure.reading else { return nil }
        return duckPose(from: reading, gains: gains)
    }

    /// One line about what the person is doing, for a readout beside the
    /// picture. Degrees, because that is how a person thinks about a knee.
    public static func readingLine(_ reading: HumanFigure.Reading) -> String {
        func deg(_ r: Double) -> String { String(format: "%.0f°", r * 180 / .pi) }
        return "Hips \(deg(reading.left.hipFlexion)) / \(deg(reading.right.hipFlexion)) · "
             + "knees \(deg(reading.left.kneeFlexion)) / \(deg(reading.right.kneeFlexion)) · "
             + "head \(deg(reading.head.pitch)) down, \(deg(reading.head.yaw)) turned · "
             + "hands \(Int((reading.armRaise * 100).rounded()))% up"
    }

    /// The joints held at their stops, named, or nil when none were.
    public static func clampedLine(_ clamped: [Int]) -> String? {
        guard !clamped.isEmpty else { return nil }
        let names = clamped.map { MotionTweak.plainName(DuckModel.jointNames[$0]) }
        return "Held at the robot's stop: \(names.joined(separator: ", ")). You went further "
             + "than the duck can."
    }
}
