import Foundation
import DuckKit

/// Changing a motion you already have, in a sentence.
///
/// DRAFTING AND TWEAKING ARE DIFFERENT JOBS. `MotionProposal` writes a motion
/// from nothing: a model invents keyframes and the app checks them. That is the
/// wrong shape for "make the bow deeper" — asking for a whole new motion throws
/// away everything already adjusted, and a model asked to reproduce fourteen
/// joints across five keyframes will quietly change three of them it was not
/// asked about.
///
/// So a tweak is a LIST OF EDITS against the motion in front of you. It names a
/// moment and a joint and a number, or it adds, removes or moves a keyframe.
/// Everything it does not mention is left exactly as it was, which is the only
/// behaviour that makes a second sentence safe to send.
public struct MotionTweak: Equatable, Sendable {

    public enum Edit: Equatable, Sendable {
        /// Set one joint at the keyframe nearest `at`, in degrees from home.
        case joint(at: Double, word: String, degrees: Double)
        /// A new keyframe at `at`, holding whatever the motion was already
        /// doing there.
        case addKey(at: Double)
        case removeKey(at: Double)
        case moveKey(at: Double, to: Double)
        case rename(String)
    }

    public let summary: String
    public let edits: [Edit]

    public init(summary: String, edits: [Edit]) {
        self.summary = summary; self.edits = edits
    }

    public enum Failure: Error, Equatable, Sendable {
        case noEdits
        case unknownJoint(String)
        case noKeyframeNear(Double)
        case wouldEmptyTheMotion

        public var message: String {
            switch self {
            case .noEdits:
                return "Nothing in that changed anything. Try naming a joint and a moment — "
                     + "\"bow deeper at half a second\"."
            case .unknownJoint(let word):
                return "\(word) is not a joint this robot has. It has a neck, a head that nods, "
                     + "turns and tilts, a beak, and hips, knees and ankles on both sides."
            case .noKeyframeNear(let time):
                return String(format: "There is no keyframe near %.2f s to change.", time)
            case .wouldEmptyTheMotion:
                return "That would remove every keyframe, and a motion with none is not a motion."
            }
        }
    }

    /// How close a named moment has to be to an existing keyframe to count as
    /// that one. A model asked about "the bow at 1.5" and given keyframes at
    /// 1.48 and 2.0 means the first, and demanding an exact match would refuse
    /// a correct answer over rounding.
    public static let nearEnough = 0.26

    /// Apply the edits, and say what actually happened.
    ///
    /// IT RETURNS THE NOTES AS WELL AS THE DRAFT, because an edit that silently
    /// did nothing is worse than one that failed: the screen redraws, the
    /// motion looks unchanged, and the person types the same sentence again.
    public func applied(to draft: IntentDraft) throws -> (draft: IntentDraft, notes: [String]) {
        guard !edits.isEmpty else { throw Failure.noEdits }
        var result = draft
        var notes: [String] = []

        for edit in edits {
            switch edit {
            case .rename(let name):
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                result.name = trimmed
                notes.append("Renamed to \"\(trimmed)\".")

            case .addKey(let at):
                let time = max(at, 0)
                guard !result.keys.contains(where: { abs($0.time - time) < 0.005 }) else {
                    notes.append(String(format: "There was already a keyframe at %.2f s.", time))
                    continue
                }
                // The pose the motion was ALREADY passing through, which pins
                // every pose that was pinned before.
                //
                // IT IS STILL NOT A NO-OP, and pretending otherwise was wrong.
                // Each span is smoothstepped separately, easing in and out at
                // both ends, so cutting one span into two makes the duck slow
                // down in the middle where it used to sail through — about two
                // degrees at the half-second on a simple bow. Capturing the
                // interpolated pose is the least surprising choice available,
                // not a free one.
                result.keys.append(.init(time: time, pose: result.pose(at: time)))
                notes.append(String(format: "Added a keyframe at %.2f s.", time))

            case .removeKey(let at):
                guard let key = MotionTweak.nearest(to: at, in: result) else {
                    throw Failure.noKeyframeNear(at)
                }
                guard result.keys.count > 1 else { throw Failure.wouldEmptyTheMotion }
                result.keys.removeAll { $0.id == key.id }
                notes.append(String(format: "Removed the keyframe at %.2f s.", key.time))

            case .moveKey(let at, let to):
                guard let key = MotionTweak.nearest(to: at, in: result) else {
                    throw Failure.noKeyframeNear(at)
                }
                let time = max(to, 0)
                guard let index = result.keys.firstIndex(where: { $0.id == key.id }) else { continue }
                result.keys[index].time = time
                notes.append(String(format: "Moved %.2f s to %.2f s.", key.time, time))

            case .joint(let at, let word, let degrees):
                guard let targets = MotionTweak.targets(for: word) else {
                    throw Failure.unknownJoint(word)
                }
                guard let key = MotionTweak.nearest(to: at, in: result),
                      let index = result.keys.firstIndex(where: { $0.id == key.id }) else {
                    throw Failure.noKeyframeNear(at)
                }
                for (joint, mirror) in targets {
                    guard let slot = DuckModel.jointIndex(of: joint) else { continue }
                    let radians = degrees * mirror * .pi / 180
                    let home = DuckModel.homePose[slot]
                    let range = DuckModel.jointRanges[slot]
                    // CLAMPED TO THE SERVO'S TRAVEL, exactly as a slider is. A
                    // sentence is not a licence to ask for an angle the robot
                    // does not have.
                    let wanted = min(max(home + radians, range.lower), range.upper)
                    if result.keys[index].pose.indices.contains(slot) {
                        result.keys[index].pose[slot] = wanted
                    }
                }
                notes.append(String(format: "%@ set to %.0f° at %.2f s.",
                                    word, degrees, key.time))
            }
        }
        result.keys.sort { $0.time < $1.time }
        return (result, notes)
    }

    /// The keyframe a stated moment means.
    static func nearest(to time: Double, in draft: IntentDraft) -> IntentDraft.Key? {
        draft.keys
            .filter { abs($0.time - time) <= nearEnough }
            .min { abs($0.time - time) < abs($1.time - time) }
    }

    /// A word, as one or more joints with their mirror signs — the same
    /// vocabulary drafting uses, so "both hips" means the same thing in a
    /// sentence that writes a motion and a sentence that edits one.
    static func targets(for word: String) -> [(joint: String, mirror: Double)]? {
        let lowered = word.lowercased().trimmingCharacters(in: .whitespaces)
        if let group = MotionProposal.groups[lowered] { return group }
        if let entry = MotionProposal.jointVocabulary.first(where: { $0.word == lowered }) {
            return [(entry.joint, 1)]
        }
        if let wire = MotionProposal.synonyms[lowered],
           DuckModel.jointIndex(of: wire) != nil {
            return [(wire, 1)]
        }
        if DuckModel.jointIndex(of: lowered) != nil { return [(lowered, 1)] }
        return nil
    }

    /// What the model needs to know to edit THIS motion: the moments that
    /// exist and where the joints are now.
    ///
    /// WITHOUT THIS IT IS GUESSING. A model told only "make it deeper" does not
    /// know whether there is a keyframe at 0.5 s or 5, and will invent one of
    /// each. Describing the motion is what turns a tweak from a re-draft into
    /// an edit.
    public static func describe(_ draft: IntentDraft) -> String {
        let rows = draft.keys.sorted { $0.time < $1.time }.map { key -> String in
            let moved = MotionProposal.jointVocabulary.compactMap { entry -> String? in
                guard let slot = DuckModel.jointIndex(of: entry.joint),
                      key.pose.indices.contains(slot) else { return nil }
                let degrees = (key.pose[slot] - DuckModel.homePose[slot]) * 180 / .pi
                guard abs(degrees) >= 1 else { return nil }
                return String(format: "%@ %+.0f°", entry.word, degrees)
            }
            return String(format: "  %.2f s: %@", key.time,
                          moved.isEmpty ? "standing" : moved.joined(separator: ", "))
        }.joined(separator: "\n")
        return """
        The motion being edited is called "\(draft.name)" and has \
        \(draft.keys.count) keyframe\(draft.keys.count == 1 ? "" : "s"):
        \(rows)
        Degrees are offsets from standing.
        """
    }
}
