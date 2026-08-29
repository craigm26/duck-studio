import Foundation
import DuckKit

/// A motion as a language model states it, before anyone decides it is one.
///
/// THE SAME CONTRACT AS `AutomationProposal`, FOR THE SAME REASON: flat
/// strings and doubles, because that is what a small on-device model reliably
/// fills, and every interesting decision — does this joint exist, is that
/// angle inside its travel, is this fast enough to matter — happens HERE,
/// where `swift test` checks it on Linux, not in a view.
///
/// WHY THIS EXISTS. Typing keyframes joint by joint is authoring for people
/// who already know the robot. "Take a slow bow, then look left" is authoring
/// for everyone else — and resolving those words into a real, previewable,
/// EDITABLE draft is also how somebody learns what the words became: say it,
/// watch it, then open the keyframes and see the sliders the sentence moved.
public struct MotionProposal: Equatable, Sendable {

    /// One joint, moved. `joint` must name a real joint — matched exactly
    /// against the vocabulary below, which uses PLAIN names a model will
    /// naturally produce, mapped here onto the robot's own.
    public struct Move: Equatable, Sendable {
        public let joint: String
        /// Degrees away from the home pose. Degrees, not radians: the model
        /// (and the person reading its output) both think in degrees, and the
        /// resolver owns the conversion exactly once.
        public let degrees: Double

        public init(joint: String, degrees: Double) {
            self.joint = joint; self.degrees = degrees
        }
    }

    /// One moment in the motion.
    public struct Key: Equatable, Sendable {
        public let atSeconds: Double
        public let moves: [Move]
        /// 0 closed … 1 open. The one channel no policy can drive.
        public let mouthOpen: Double

        public init(atSeconds: Double, moves: [Move], mouthOpen: Double = 0) {
            self.atSeconds = atSeconds; self.moves = moves
            self.mouthOpen = mouthOpen
        }
    }

    public let name: String
    public let keys: [Key]

    public init(name: String, keys: [Key]) {
        self.name = name; self.keys = keys
    }

    /// The vocabulary: what a model may call a joint, and which joint each
    /// word is. Plain names first — "head turn", not "head_yaw" — because a
    /// model prompted with friendly words emits friendly words, and the
    /// mapping belongs in tested code rather than in the model's memory.
    public static let jointVocabulary: [(word: String, joint: String)] = [
        ("neck", "neck_pitch"),
        ("head nod", "head_pitch"),
        ("head turn", "head_yaw"),
        ("head tilt", "head_roll"),
        ("left hip swing", "left_hip_yaw"),
        ("left hip lean", "left_hip_roll"),
        ("left hip", "left_hip_pitch"),
        ("left knee", "left_knee"),
        ("left ankle", "left_ankle"),
        ("right hip swing", "right_hip_yaw"),
        ("right hip lean", "right_hip_roll"),
        ("right hip", "right_hip_pitch"),
        ("right knee", "right_knee"),
        ("right ankle", "right_ankle"),
    ]

    public enum Unresolvable: Error, Equatable {
        case noKeyframes
        case unknownJoint(String, closest: String?)

        public var message: String {
            switch self {
            case .noKeyframes:
                return "The draft has no keyframes — one pose is a pose, not a motion."
            case .unknownJoint(let word, let closest):
                let hint = closest.map { " The nearest name is \"\($0)\"." } ?? ""
                return "\"\(word)\" is not a joint this robot has.\(hint)"
            }
        }
    }

    /// The words, turned into an editable draft — or the reason they are not
    /// one.
    ///
    /// WHAT RESOLUTION DOES AND VALIDATION STILL CHECKS. This maps names and
    /// units and CLAMPS each angle into the joint's real travel — a model
    /// asking for a 200° nod gets the joint's actual limit, which is the
    /// robot's answer to an impossible request. Everything else — ordering,
    /// speed against the measured corpus, the mouth caution — is the same
    /// `IntentDraft.problems` machinery every hand-made draft goes through,
    /// because a generated draft is not a special kind of draft.
    public func resolve() throws -> IntentDraft {
        guard !keys.isEmpty else { throw Unresolvable.noKeyframes }

        var draftKeys: [IntentDraft.Key] = []
        // Every motion starts from home: the robot is standing before the
        // sentence happens to it. A model rarely thinks to say so.
        if keys.first.map({ $0.atSeconds > 0.05 }) ?? false {
            draftKeys.append(.init(time: 0, pose: DuckModel.homePose))
        }

        for key in keys.sorted(by: { $0.atSeconds < $1.atSeconds }) {
            var pose = DuckModel.homePose
            for move in key.moves {
                let word = move.joint.lowercased()
                    .trimmingCharacters(in: .whitespaces)
                guard let entry = Self.jointVocabulary.first(where: { $0.word == word })
                        ?? Self.jointVocabulary.first(where: { $0.joint == word }) else {
                    throw Unresolvable.unknownJoint(
                        move.joint, closest: Self.closest(to: word))
                }
                let index = DuckModel.jointIndex(of: entry.joint)!
                let range = DuckModel.jointRanges[index]
                let radians = DuckModel.homePose[index] + move.degrees * .pi / 180
                pose[index] = min(max(radians, range.lower), range.upper)
            }
            pose[DuckModel.mouthIndex] = DuckModel.mouthTarget(
                open: key.mouthOpen)
            draftKeys.append(.init(time: max(key.atSeconds, 0), pose: pose))
        }

        // And it ends at home unless the words said otherwise — a motion that
        // finishes mid-gesture leaves the robot wearing it forever.
        if let last = draftKeys.last,
           last.pose != DuckModel.homePose {
            draftKeys.append(.init(time: last.time + 0.6, pose: DuckModel.homePose))
        }

        return IntentDraft(
            name: name.isEmpty ? "drafted motion" : name,
            keys: draftKeys,
            provenance: "Drafted from your words by the on-device model, resolved and "
                      + "clamped to the robot's real travel here. Open the keyframes to "
                      + "see what the sentence became.")
    }

    /// The nearest vocabulary word, for the refusal message.
    static func closest(to word: String) -> String? {
        // Cheap containment first — "head" alone should suggest a head word.
        if let contained = jointVocabulary.first(where: {
            $0.word.contains(word) || word.contains($0.word)
        }) { return contained.word }
        // Otherwise the shortest edit distance, small-n so O(n·m²) is fine.
        return jointVocabulary.map(\.word).min {
            editDistance($0, word) < editDistance($1, word)
        }
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for (i, ca) in a.enumerated() {
            var previous = row[0]
            row[0] = i + 1
            for (j, cb) in b.enumerated() {
                let insertOrDelete = min(row[j + 1], row[j]) + 1
                let substitute = previous + (ca == cb ? 0 : 1)
                previous = row[j + 1]
                row[j + 1] = min(insertOrDelete, substitute)
            }
        }
        return row[b.count]
    }

    /// What the model is told, built from the same vocabulary the resolver
    /// matches against — so the words it is offered and the words that resolve
    /// are one list that cannot drift apart.
    public static func grounding() -> String {
        let joints = jointVocabulary.map { entry in
            let index = DuckModel.jointIndex(of: entry.joint)!
            let range = DuckModel.jointRanges[index]
            let lo = Int(((range.lower - DuckModel.homePose[index]) * 180 / .pi).rounded())
            let hi = Int(((range.upper - DuckModel.homePose[index]) * 180 / .pi).rounded())
            return "\(entry.word) (\(lo)° to \(hi)°)"
        }.joined(separator: ", ")
        return """
        You draft short motions for a 25 cm duck robot as keyframes. Joints you \
        may move, with their travel in degrees from the standing pose: \(joints). \
        mouthOpen is 0 closed to 1 open. Use 2 to 6 keyframes over 1 to 4 seconds, \
        angles well inside the travel, and finish with everything back at 0 so the \
        robot returns to standing. Degrees are offsets from standing, not absolutes.
        """
    }
}
