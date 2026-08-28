import Foundation
import DuckKit

/// The robot's joints, grouped the way the robot is built.
///
/// A FLAT LIST OF FIFTEEN SLIDERS IS NOT AN EDITOR. The joint order is left leg,
/// then neck and head and mouth, then right leg — which is the order the wire,
/// the policies and the MuJoCo model all use, and which makes the two legs look
/// unrelated on screen. Grouping them is presentation, and the sentences under
/// each group are claims about the robot that have to be true, so both live
/// here where `swift test` can check them rather than in a view.
public struct JointGroup: Equatable, Sendable, Identifiable {
    public let title: String
    /// Indices into `DuckModel.jointNames`.
    public let joints: [Int]
    /// What somebody needs to know before moving these, or nil.
    public let note: String?
    public var id: String { title }

    public static let all: [JointGroup] = [
        JointGroup(title: "Left leg", joints: [0, 1, 2, 3, 4], note: nil),
        JointGroup(title: "Right leg", joints: [10, 11, 12, 13, 14], note: nil),
        JointGroup(
            title: "Neck and head", joints: [5, 6, 7, 8],
            note: "The head is command-driven in the velocity config — the policy is handed a head "
                + "pose to track rather than pulled back home — so this is the part a motion can "
                + "move without fighting the gait."),
        JointGroup(
            title: "Mouth", joints: [DuckModel.mouthIndex],
            note: "Joint \(DuckModel.mouthIndex), and outside every alpha policy's action space: "
                + "all of them take \(DuckObservation.length) inputs and answer with "
                + "\(DuckModel.policyJointCount), and the mouth is the one they skip. Nothing "
                + "trained it, and nothing but an authored motion can move it."),
    ]

    /// Every joint appears in exactly one group. Asserted, because a group list
    /// written by hand is a list somebody will later add a joint to and forget.
    public static var coversEveryJoint: Bool {
        let listed = all.flatMap(\.joints).sorted()
        return listed == Array(0..<DuckModel.jointCount)
    }
}

/// One joint, ready to put behind a control.
public struct JointControl: Equatable, Sendable, Identifiable {
    public let index: Int
    public let name: String
    /// The joint's real travel. THE ENDS OF A SLIDER, not a suggestion: a
    /// control with generous ends and a warning underneath is a control that
    /// teaches people to ignore warnings.
    public let lower: Double
    public let upper: Double
    public var id: Int { index }

    public init(index: Int) {
        self.index = index
        name = DuckModel.jointNames[index]
        let range = DuckModel.jointRanges[index]
        lower = range.lower
        upper = range.upper
    }

    /// Where a joint sits when nothing is asking it to be anywhere.
    public var home: Double { DuckModel.homePose[index] }

    public func degrees(_ radians: Double) -> String {
        String(format: "%+.0f°", radians * 180 / .pi)
    }

    public var travelLabel: (lower: String, upper: String) {
        (String(format: "%.0f°", lower * 180 / .pi),
         String(format: "%.0f°", upper * 180 / .pi))
    }
}
