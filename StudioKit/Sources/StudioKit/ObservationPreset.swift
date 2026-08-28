import Foundation
import DuckKit

/// Observations worth starting a policy from.
///
/// IN THE KIT, NOT THE VIEW, and the guard is what put them here. A first
/// attempt built these inline in a SwiftUI screen and
/// `check_no_studio_math.sh` refused it for naming `DuckModel.homePose` — which
/// is exactly the rule working. Referencing DuckKit's constant is not
/// reimplementing it, but a preset is a claim about what a plausible robot
/// state looks like, and a claim belongs where `swift test` can check it.
public enum ObservationPreset: String, CaseIterable, Identifiable, Sendable {
    case standing = "Standing still"
    case walking = "Walking forward"
    case turning = "Turning left"
    case zeroed = "All zeros"

    public var id: String { rawValue }

    /// What this preset is for, in one line.
    public var detail: String {
        switch self {
        case .standing: return "Upright, level, no command. What the robot does when asked for nothing."
        case .walking:  return "0.15 m/s forward — inside the range the policy was trained over."
        case .turning:  return "1.0 rad/s yaw, no translation."
        case .zeroed:   return "Not a robot state at all: an all-zero gravity vector describes free fall."
        }
    }

    /// Upright: gravity points straight down in the body frame.
    static let level: [Double] = [0, 0, -1]

    /// Built through `DuckObservation.build`, never assembled here — that
    /// 61-float layout has exactly one home, and a second place that knows it
    /// is a second place to get it wrong.
    public var observation: DuckObservation {
        let still = [Double](repeating: 0, count: DuckModel.jointCount)
        let noAction = [Float](repeating: 0, count: DuckModel.policyJointCount)
        switch self {
        case .zeroed:
            // Kept because it is the warm-up input the robot's own runtime
            // uses, and because it is instructive: it sits about 32 training
            // standard deviations off the mean on projected gravity z.
            return .zeroed
        case .standing:
            return .build(gyro: [0, 0, 0], gravity: Self.level,
                          jointPositions: DuckModel.homePose, jointVelocities: still,
                          lastAction: noAction, command: DuckCommand(twist: (0, 0, 0)))
        case .walking:
            return .build(gyro: [0, 0, 0], gravity: Self.level,
                          jointPositions: DuckModel.homePose, jointVelocities: still,
                          lastAction: noAction, command: DuckCommand(twist: (0.15, 0, 0)))
        case .turning:
            return .build(gyro: [0, 0, 0], gravity: Self.level,
                          jointPositions: DuckModel.homePose, jointVelocities: still,
                          lastAction: noAction, command: DuckCommand(twist: (0, 0, 1.0)))
        }
    }

    /// The pose a bench should draw before anything has been run.
    public static var restingPose: [Double] { DuckModel.homePose }
}
