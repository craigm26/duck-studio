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
        ("beak", "mouth"),
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

    /// Words the model was never offered but will produce anyway — its priors
    /// know yaw/pitch/roll, the wire names leak through, and "mouth" is what
    /// anyone calls a beak. Accepted silently; the vocabulary above is what it
    /// is TOLD, this is what it is FORGIVEN.
    static let synonyms: [String: String] = [
        "mouth": "mouth", "jaw": "mouth", "mouthopen": "mouth", "mouth open": "mouth",
        "neck pitch": "neck_pitch",
        "head pitch": "head_pitch", "head yaw": "head_yaw", "head roll": "head_roll",
        "head": "head_pitch",
        "left hip pitch": "left_hip_pitch", "left hip yaw": "left_hip_yaw",
        "left hip roll": "left_hip_roll",
        "right hip pitch": "right_hip_pitch", "right hip yaw": "right_hip_yaw",
        "right hip roll": "right_hip_roll",
    ]

    /// Group words: one word, a mirrored pair. The right leg's home pose is
    /// the left's with every sign flipped, so "both knees 20°" bends both the
    /// same way by sending +20° left and −20° right — a model that writes one
    /// number for a pair almost always means the symmetric motion.
    static let groups: [String: [(joint: String, mirror: Double)]] = [
        "knees": [("left_knee", 1), ("right_knee", -1)],
        "both knees": [("left_knee", 1), ("right_knee", -1)],
        "hips": [("left_hip_pitch", 1), ("right_hip_pitch", -1)],
        "both hips": [("left_hip_pitch", 1), ("right_hip_pitch", -1)],
        "ankles": [("left_ankle", 1), ("right_ankle", -1)],
        "both ankles": [("left_ankle", 1), ("right_ankle", -1)],
        "legs": [("left_hip_pitch", 1), ("right_hip_pitch", -1),
                 ("left_knee", 1), ("right_knee", -1)],
        "both legs": [("left_hip_pitch", 1), ("right_hip_pitch", -1),
                      ("left_knee", 1), ("right_knee", -1)],
    ]

    /// Every word the model is ALLOWED to put in a move — the joint words and
    /// the mirrored-pair group words — for a decoder that enforces the list
    /// at generation time. Synonyms are deliberately absent: they are what a
    /// model is forgiven, not what it is offered.
    public static var offeredWords: [String] {
        jointVocabulary.map(\.word) + groups.keys.sorted()
    }

    /// What a model's joint string becomes before matching: case, wire
    /// underscores and hyphens, stray newlines, and the travel annotation the
    /// grounding itself taught it ("neck (-110° to 40°)") all go.
    static func normalised(_ raw: String) -> String {
        var word = raw.lowercased()
        // Only a TRAILING annotation is stripped — "neck (-110° to 40°)" —
        // never a leading one, so "(left) knee" is refused rather than
        // vanishing as a blank no-op.
        if let paren = word.firstIndex(of: "("), paren > word.startIndex {
            word = String(word[..<paren])
        }
        word = word.replacingOccurrences(of: "_", with: " ")
                   .replacingOccurrences(of: "-", with: " ")
        word = word.trimmingCharacters(in: .whitespacesAndNewlines)
        while word.contains("  ") { word = word.replacingOccurrences(of: "  ", with: " ") }
        return word
    }

    /// Every (joint, degrees) a single move stands for — usually one, a
    /// mirrored pair for a group word — or nil for a word nobody knows.
    static func expand(_ move: Move) -> [(joint: String, degrees: Double)]? {
        let word = normalised(move.joint)
        if let entry = jointVocabulary.first(where: { $0.word == word })
            ?? jointVocabulary.first(where: { $0.joint == word }) {
            return [(entry.joint, move.degrees)]
        }
        if let joint = synonyms[word] { return [(joint, move.degrees)] }
        if let pair = groups[word] { return pair.map { ($0.joint, move.degrees * $0.mirror) } }
        if DuckModel.jointIndex(of: move.joint.lowercased()) != nil {
            return [(move.joint.lowercased(), move.degrees)]
        }
        return nil
    }

    public enum Unresolvable: Error, Equatable {
        case noKeyframes
        case unknownJoint(String, closest: String?)

        public var message: String {
            switch self {
            case .noKeyframes:
                return "The draft has no keyframes — one pose is a pose, not a motion."
            case .unknownJoint(let word, let closest):
                let hint = closest.map { " The nearest name is \"\($0)\"." }
                    ?? " The joints are: " + MotionProposal.jointVocabulary.map(\.word)
                        .joined(separator: ", ") + "."
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
        // SORT FIRST. The prepend decision once read the UNSORTED first key
        // while the loop iterated sorted keys, so [(0.8, …), (0.0, …)] got a
        // home key at 0 AND the model's own 0 — a duplicate time, a broken
        // draft.
        let ordered = keys.sorted(by: { $0.atSeconds < $1.atSeconds })
        // Every motion starts from home: the robot is standing before the
        // sentence happens to it. A model rarely thinks to say so.
        if ordered.first.map({ $0.atSeconds > 0.05 }) ?? false {
            draftKeys.append(.init(time: 0, pose: DuckModel.homePose))
        }

        for key in ordered {
            var pose = DuckModel.homePose
            for move in key.moves {
                // A blank joint is a small model's way of writing "nothing
                // moves here" — a no-op, not a refusal.
                if Self.normalised(move.joint).isEmpty { continue }
                guard let targets = Self.expand(move) else {
                    throw Unresolvable.unknownJoint(
                        move.joint, closest: Self.closest(to: Self.normalised(move.joint)))
                }
                for target in targets {
                    let index = DuckModel.jointIndex(of: target.joint)!
                    let range = DuckModel.jointRanges[index]
                    let radians = DuckModel.homePose[index] + target.degrees * .pi / 180
                    pose[index] = min(max(radians, range.lower), range.upper)
                }
            }
            // THE BEAK STAYS AT HOME UNLESS ASKED. The first version wrote
            // mouthTarget(0) = −5° into every key, but the home pose holds
            // the mouth at 0, so every draft — even one that never opened
            // the beak — grew a return-home tail and tripped the "drives the
            // mouth" caution. Only an actual opening touches it.
            // mouthOpen is on the SAME scale as a beak move — an offset from
            // the resting beak, 0 … 30° — so the two cannot disagree by
            // convention. (mouthTarget(open:) starts at −5°, and max() with it
            // silently dropped every mouthOpen below 0.14.)
            if key.mouthOpen > 0 {
                let open = DuckModel.homePose[DuckModel.mouthIndex]
                    + min(key.mouthOpen, 1) * 30 * .pi / 180
                pose[DuckModel.mouthIndex] = max(pose[DuckModel.mouthIndex], open)
            }
            // Equal times are nudged apart rather than left to break the draft.
            var time = max(key.atSeconds, 0)
            if let last = draftKeys.last, time <= last.time { time = last.time + 0.02 }
            draftKeys.append(.init(time: time, pose: pose))
        }

        // And it ends at home unless the words said otherwise — a motion that
        // finishes mid-gesture leaves the robot wearing it forever. A beak
        // anywhere between pressed-shut (−5°) and resting (0°) counts as home.
        func isHome(_ pose: [Double]) -> Bool {
            for (index, value) in pose.enumerated() {
                if index == DuckModel.mouthIndex {
                    if value < DuckModel.mouthClosed - 1e-9 || value > DuckModel.homePose[index] + 1e-9 {
                        return false
                    }
                } else if abs(value - DuckModel.homePose[index]) > 1e-9 {
                    return false
                }
            }
            return true
        }
        if let last = draftKeys.last, !isHome(last.pose) {
            draftKeys.append(.init(time: last.time + 0.6, pose: DuckModel.homePose))
        }
        // One pose is a pose, not a motion: "stand still" becomes a
        // half-second of standing, which is at least playable.
        if draftKeys.count == 1, let only = draftKeys.first {
            draftKeys.append(.init(time: only.time + 0.5, pose: DuckModel.homePose))
        }

        return IntentDraft(
            name: name.isEmpty ? "drafted motion" : name,
            keys: draftKeys,
            provenance: "Drafted from your words by the on-device model, resolved and "
                      + "clamped to the robot's real travel here. Open the keyframes to "
                      + "see what the sentence became.")
    }

    /// The nearest vocabulary word, for the refusal message — or nothing,
    /// because a hint that is wrong is worse than none. "mouthopen" was once
    /// told its nearest joint was "left hip" (edit distance 7).
    static func closest(to word: String) -> String? {
        guard !word.isEmpty else { return nil }
        let tokens = word.split(separator: " ").map(String.init)
        // Token match — whole, or a prefix of three letters or more, so
        // "kne" still finds a knee — shortest candidate first: "knee" →
        // "left knee", not whichever entry happens to come first in the table.
        func near(_ a: String, _ b: String) -> Bool {
            a == b || (min(a.count, b.count) >= 3 && (a.hasPrefix(b) || b.hasPrefix(a)))
        }
        // Ranked by how many of the word's tokens a candidate matches, then
        // shortest: "left kne" → "left knee" (two tokens), not "left hip".
        var scored: [(word: String, matches: Int)] = []
        for candidate in jointVocabulary.map(\.word) {
            let parts = candidate.split(separator: " ").map(String.init)
            var matches = 0
            for token in tokens where parts.contains(where: { near($0, token) }) {
                matches += 1
            }
            if matches > 0 { scored.append((candidate, matches)) }
        }
        scored.sort { a, b in
            if a.matches != b.matches { return a.matches > b.matches }
            return a.word.count < b.word.count
        }
        if let hit = scored.first { return hit.word }
        let allowed = max(2, word.count / 3)
        let best = jointVocabulary.map(\.word).min {
            editDistance($0, word) < editDistance($1, word)
        }
        if let best, editDistance(best, word) <= allowed { return best }
        return nil
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
            if entry.joint == "mouth" { return "beak (0° resting to 30° wide open)" }
            let lo = Int(((range.lower - DuckModel.homePose[index]) * 180 / .pi).rounded())
            let hi = Int(((range.upper - DuckModel.homePose[index]) * 180 / .pi).rounded())
            return "\(entry.word) (\(lo)° to \(hi)°)"
        }.joined(separator: ", ")
        return """
        You draft short motions for a 25 cm duck robot as keyframes.

        Joints you may move, each with its travel in degrees from the standing pose:
        \(joints).
        Use exactly these joint names. "beak" is the mouth: 0 is its resting, \
        closed position and 30 is wide open; never go below 0. Signs: positive \
        neck and head nod bow the beak toward the floor, positive head turn looks \
        to the duck's own left, positive head tilt leans its head to the right. Pair words move both sides together, mirrored: \
        \(groups.keys.sorted().joined(separator: ", ")). A keyframe's separate mouthOpen field (0 closed to 1 open) may be used \
        instead of a beak move; leave it 0 when the beak stays shut.

        Use 2 to 6 keyframes over 1 to 4 seconds, angles well inside the travel, and \
        finish with everything back at 0 so the robot returns to standing. Degrees \
        are offsets from standing, not absolutes.
        """
    }
}
