import Foundation
import DuckKit

/// What each of the 61 numbers the policy sees actually is.
///
/// DERIVED FROM POLLEN'S TRAINING CONFIGS, NOT FROM INSPECTION. Every label,
/// unit and bound below was read out of `pollen-robotics/microduck_rl` —
/// `microduck_velocity_env_cfg.py` for the observation terms and their command
/// ranges, `microduck_constants.py` for the home frame, `robot_walk.xml` for
/// joint travel. A slot table invented by looking at a running policy would be
/// a plausible guess; this is what the network was trained against.
///
/// THE BOUNDS ARE FOR AN EDITOR, AND THEY ARE NOT ALL THE SAME KIND OF THING.
/// Where training sampled a command from a range, that range is the bound and
/// it means something. Where nothing bounds a value — the gyro, joint
/// velocities and the previous action are all unclipped and unscaled in
/// training — the bound is a sane editing range and nothing more. The
/// difference matters to anyone reading a z-score, so `isBoundedByTraining`
/// says which is which rather than letting a slider imply authority it lacks.
public struct ObservationSlot: Equatable, Sendable, Identifiable {

    public enum Block: String, Equatable, Sendable, CaseIterable {
        case angularVelocity, projectedGravity, jointPosition, jointVelocity
        case lastAction, twist, headCommand, bodyCommand

        public var title: String {
            switch self {
            case .angularVelocity:  return "Angular velocity"
            case .projectedGravity: return "Projected gravity"
            case .jointPosition:    return "Joint positions"
            case .jointVelocity:    return "Joint velocities"
            case .lastAction:       return "Previous action"
            case .twist:            return "Twist command"
            case .headCommand:      return "Head command"
            case .bodyCommand:      return "Body command"
            }
        }
    }

    public enum Unit: String, Equatable, Sendable {
        case radians = "rad", radiansPerSecond = "rad/s"
        case metres = "m", metresPerSecond = "m/s"
        case dimensionless = ""
    }

    public let index: Int
    public let block: Block
    public let label: String
    public let unit: Unit
    public let lower: Double
    public let upper: Double
    /// True when this slot is structurally constant in training.
    ///
    /// A constant slot has zero variance, so it cannot be normalised and cannot
    /// be ranked by sensitivity — a z-score for it is a division by zero and a
    /// Jacobian column for it is meaningless. Anything that ranks or normalises
    /// must skip these and SAY it skipped them.
    public let isConstantInTraining: Bool

    public var id: Int { index }

    init(_ index: Int, _ block: Block, _ label: String, _ unit: Unit,
         _ lower: Double, _ upper: Double, _ constant: Bool) {
        self.index = index; self.block = block; self.label = label
        self.unit = unit; self.lower = lower; self.upper = upper
        self.isConstantInTraining = constant
    }

    /// All 61, in observation order.
    public static let all: [ObservationSlot] = [
        .init(0, .angularVelocity, "gyro X — trunk roll rate", .radiansPerSecond, -10, 10, false),
        .init(1, .angularVelocity, "gyro Y — trunk pitch rate", .radiansPerSecond, -10, 10, false),
        .init(2, .angularVelocity, "gyro Z — trunk yaw rate", .radiansPerSecond, -10, 10, false),
        .init(3, .projectedGravity, "gravity X in trunk frame", .dimensionless, -1, 1, false),
        .init(4, .projectedGravity, "gravity Y in trunk frame", .dimensionless, -1, 1, false),
        .init(5, .projectedGravity, "gravity Z in trunk frame (−1 when upright)", .dimensionless, -1, 1, false),
        .init(6, .jointPosition, "left hip yaw position (rel. home)", .radians, -0.4363, 0.5236, false),
        .init(7, .jointPosition, "left hip roll position (rel. home)", .radians, -0.2967, 0.4713, false),
        .init(8, .jointPosition, "left hip pitch position (rel. home)", .radians, -1.1129, 2.0287, false),
        .init(9, .jointPosition, "left knee position (rel. home)", .radians, -1.5659, 1.5757, false),
        .init(10, .jointPosition, "left ankle position (rel. home)", .radians, -2.0238, 1.1178, false),
        .init(11, .jointPosition, "neck pitch position (rel. home)", .radians, -1.9199, 0.6981, false),
        .init(12, .jointPosition, "head pitch position (rel. home)", .radians, -1.9199, 1.2217, false),
        .init(13, .jointPosition, "head yaw position (rel. home)", .radians, -2.9671, 2.9671, false),
        .init(14, .jointPosition, "head roll position (rel. home)", .radians, -0.4363, 0.4363, false),
        .init(15, .jointPosition, "right hip yaw position (rel. home)", .radians, -0.5236, 0.4363, false),
        .init(16, .jointPosition, "right hip roll position (rel. home)", .radians, -0.4713, 0.2967, false),
        .init(17, .jointPosition, "right hip pitch position (rel. home)", .radians, -2.0287, 1.1129, false),
        .init(18, .jointPosition, "right knee position (rel. home)", .radians, -1.5757, 1.5659, false),
        .init(19, .jointPosition, "right ankle position (rel. home)", .radians, -1.1178, 2.0238, false),
        .init(20, .jointVelocity, "left hip yaw velocity", .radiansPerSecond, -5, 5, false),
        .init(21, .jointVelocity, "left hip roll velocity", .radiansPerSecond, -5, 5, false),
        .init(22, .jointVelocity, "left hip pitch velocity", .radiansPerSecond, -5, 5, false),
        .init(23, .jointVelocity, "left knee velocity", .radiansPerSecond, -5, 5, false),
        .init(24, .jointVelocity, "left ankle velocity", .radiansPerSecond, -5, 5, false),
        .init(25, .jointVelocity, "neck pitch velocity", .radiansPerSecond, -5, 5, false),
        .init(26, .jointVelocity, "head pitch velocity", .radiansPerSecond, -5, 5, false),
        .init(27, .jointVelocity, "head yaw velocity", .radiansPerSecond, -5, 5, false),
        .init(28, .jointVelocity, "head roll velocity", .radiansPerSecond, -5, 5, false),
        .init(29, .jointVelocity, "right hip yaw velocity", .radiansPerSecond, -5, 5, false),
        .init(30, .jointVelocity, "right hip roll velocity", .radiansPerSecond, -5, 5, false),
        .init(31, .jointVelocity, "right hip pitch velocity", .radiansPerSecond, -5, 5, false),
        .init(32, .jointVelocity, "right knee velocity", .radiansPerSecond, -5, 5, false),
        .init(33, .jointVelocity, "right ankle velocity", .radiansPerSecond, -5, 5, false),
        .init(34, .lastAction, "previous action — left hip yaw", .dimensionless, -3, 3, false),
        .init(35, .lastAction, "previous action — left hip roll", .dimensionless, -3, 3, false),
        .init(36, .lastAction, "previous action — left hip pitch", .dimensionless, -3, 3, false),
        .init(37, .lastAction, "previous action — left knee", .dimensionless, -3, 3, false),
        .init(38, .lastAction, "previous action — left ankle", .dimensionless, -3, 3, false),
        .init(39, .lastAction, "previous action — neck pitch", .dimensionless, -3, 3, false),
        .init(40, .lastAction, "previous action — head pitch", .dimensionless, -3, 3, false),
        .init(41, .lastAction, "previous action — head yaw", .dimensionless, -3, 3, false),
        .init(42, .lastAction, "previous action — head roll", .dimensionless, -3, 3, false),
        .init(43, .lastAction, "previous action — right hip yaw", .dimensionless, -3, 3, false),
        .init(44, .lastAction, "previous action — right hip roll", .dimensionless, -3, 3, false),
        .init(45, .lastAction, "previous action — right hip pitch", .dimensionless, -3, 3, false),
        .init(46, .lastAction, "previous action — right knee", .dimensionless, -3, 3, false),
        .init(47, .lastAction, "previous action — right ankle", .dimensionless, -3, 3, false),
        .init(48, .twist, "commanded forward velocity (vx)", .metresPerSecond, -0.4, 0.4, false),
        .init(49, .twist, "commanded lateral velocity (vy)", .metresPerSecond, -0.3, 0.3, false),
        .init(50, .twist, "commanded yaw rate (vyaw)", .radiansPerSecond, -1, 1, false),
        .init(51, .headCommand, "commanded neck pitch delta", .radians, -1.1, 1.1, false),
        .init(52, .headCommand, "commanded head pitch delta", .radians, -1.1, 1.1, false),
        .init(53, .headCommand, "commanded head yaw delta", .radians, -1.4, 1.4, false),
        .init(54, .headCommand, "commanded head roll delta", .radians, -0.31, 0.31, false),
        .init(55, .bodyCommand, "commanded body X delta — never emitted by DuckKit", .metres, 0, 0, true),
        .init(56, .bodyCommand, "commanded body Y delta — never emitted by DuckKit", .metres, 0, 0, true),
        .init(57, .bodyCommand, "commanded body Z delta (crouch −/extend +)", .metres, -0.04, 0.03, false),
        .init(58, .bodyCommand, "commanded body roll delta", .radians, -0.2618, 0.2618, false),
        .init(59, .bodyCommand, "commanded body pitch delta", .radians, -0.2618, 0.2618, false),
        .init(60, .bodyCommand, "commanded body yaw delta — never emitted by DuckKit", .radians, 0, 0, true),    ]

    public static subscript(index: Int) -> ObservationSlot { all[index] }

    /// The slots of one block, in order.
    public static func slots(in block: Block) -> [ObservationSlot] {
        all.filter { $0.block == block }
    }

    /// The slots nothing can normalise or rank.
    public static var constantSlots: [ObservationSlot] { all.filter(\.isConstantInTraining) }
}
