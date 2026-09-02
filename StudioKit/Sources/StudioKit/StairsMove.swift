import Foundation
import DuckKit

extension StairsChallenge {

    /// A harness intent — the file the scorer replays and the leaderboard is
    /// keyed by — and the two conversions that let somebody edit one.
    ///
    /// IT KEEPS EVERYTHING IT DOES NOT UNDERSTAND. A challenge file carries
    /// fields this app has no opinion about: `event` and `servo` (landing laws
    /// the round-4 and round-5 families added), `spawn`, `bounds`, `params`,
    /// `robust`, `ceiling`, `duplicateBehaviourOf`. Some of them are INSIDE
    /// the identity — `intentHash` folds `event`, `servo` and the spawn keys in
    /// when the file has them — so a reader that dropped an unknown field would
    /// hand the bench a different move under the leaderboard's hash. So the
    /// whole object is held as `HarnessJSON`, order and digits intact, and the
    /// typed properties below are a VIEW of it rather than a replacement for
    /// it. `StairsMoveTests` re-encodes all nineteen bundled files and
    /// compares them to the shipped bytes, byte for byte.
    ///
    /// FOURTEEN JOINTS HERE, FIFTEEN IN A DRAFT, AND THAT IS NOT A ROUNDING
    /// ERROR. A harness pose is the policy's action space, which skips the
    /// mouth (`DuckModel.mouthIndex`). An `IntentDraft` is fifteen wide because
    /// a person wrote it and a person can open the beak. `toDraft()` widens by
    /// putting the mouth at its home angle; `applying(draft:)` narrows by
    /// dropping it, and `StairsChallenge.mouthDroppedNote` is the sentence for
    /// the case where that actually loses an edit.
    public struct Move: Equatable, Sendable {

        /// One authored pose and the second it happens at.
        public struct Keyframe: Equatable, Sendable {
            public let t: Double
            /// Fourteen, in policy-slot order.
            public let pose: [Double]
            public init(t: Double, pose: [Double]) { self.t = t; self.pose = pose }
        }

        public enum Refusal: Error, Equatable {
            case notAnObject
            case noKeyframes
            case wrongPoseWidth(Int)

            public var message: String {
                switch self {
                case .notAnObject:
                    return "That is not a harness intent: the file has to be one JSON object."
                case .noKeyframes:
                    return "That intent has no keyframes, so there is no move in it."
                case .wrongPoseWidth(let width):
                    return "A harness pose is \(DuckModel.policyJointCount) joints and this one "
                         + "is \(width). The mouth is the joint the format leaves out."
                }
            }
        }

        /// The whole file, order and digits intact.
        public let json: HarnessJSON

        public var name: String { json["name"]?.stringValue ?? "unnamed" }
        public var family: String? { json["family"]?.stringValue }
        public var note: String? { json["note"]?.stringValue }

        /// The four shape parameters every family carries. Defaults match the
        /// harness's own (`gap`, `side` and `approach` default to 0 there).
        public var blend: Double { json["blend"]?.doubleValue ?? 1 }
        public var gap: Double { json["gap"]?.doubleValue ?? 0 }
        public var side: Double { json["side"]?.doubleValue ?? 0 }
        public var approach: Double { json["approach"]?.doubleValue ?? 0 }
        public var isolate: Bool { json["isolate"]?.boolValue ?? false }
        public var stepCount: Int { Int(json["stepCount"]?.doubleValue ?? 4) }

        /// The fields that make a move something other than keyframes, named
        /// so a screen can say what it is looking at rather than hiding it.
        public var hasEvent: Bool { json["event"] != nil }
        public var hasServo: Bool { json["servo"] != nil }
        public var hasSpawn: Bool { json["spawn"] != nil }
        /// Where a placed spawn puts the duck, in the harness's room
        /// coordinates (x forward, y across). The harness writes `{x, y, z}`;
        /// the height is the drop the harness chooses, not a scene fact, so
        /// only the floor point comes through. `nil` when there is no spawn
        /// or the object is not a floor point.
        public var spawn: (x: Double, y: Double)? {
            guard let x = json["spawn"]?["x"]?.doubleValue,
                  let y = json["spawn"]?["y"]?.doubleValue else { return nil }
            return (x, y)
        }

        public var keyframes: [Keyframe] {
            guard let items = json["keyframes"]?.arrayValue else { return [] }
            return items.compactMap { item in
                guard let t = item["t"]?.doubleValue,
                      let pose = item["pose"]?.arrayValue else { return nil }
                return Keyframe(t: t, pose: pose.compactMap(\.doubleValue))
            }
        }

        public var duration: Double { keyframes.map(\.t).max() ?? 0 }

        // MARK: - reading and writing one

        public init(json: HarnessJSON) throws {
            guard case .object = json else { throw Refusal.notAnObject }
            self.json = json
            guard !keyframes.isEmpty else { throw Refusal.noKeyframes }
            for frame in keyframes where frame.pose.count != DuckModel.policyJointCount {
                throw Refusal.wrongPoseWidth(frame.pose.count)
            }
        }

        public static func decode(_ data: Data) throws -> Move {
            try Move(json: HarnessJSON.parse(data))
        }

        /// The file again, in the shape `JSON.stringify(value, null, 2)`
        /// writes — which is what `climb/robust.mjs`'s `saveIntent` uses, so
        /// an unedited move comes back out as the bytes it went in as.
        public func encoded() -> Data { json.encoded(.pretty) }

        // MARK: - into the editor and back

        /// The editable draft this move opens as.
        ///
        /// The provenance line names the challenge, the hash and the rank,
        /// because the moment this is in the Studio's draft list it looks like
        /// something the person wrote, and a draft that lost where it came from
        /// is a leaderboard entry somebody is about to publish as their own by
        /// accident.
        ///
        /// `challenge` DEFAULTS TO `.stairs` AND IS NOT DECORATION. The ball
        /// challenge's move entrants are harness intents too and reuse every
        /// line of this conversion; what must not be reused is the sentence,
        /// because a draft that says it came from the stairs challenge when it
        /// came from the ball one is a provenance line that is worse than
        /// none.
        public func toDraft(challenge: Challenge = .stairs,
                            hash: String? = nil, rank: Int? = nil) -> IntentDraft {
            let mouth = DuckModel.homePose[DuckModel.mouthIndex]
            let keys = keyframes.map { frame -> IntentDraft.Key in
                var pose = [Double](repeating: 0, count: DuckModel.jointCount)
                for slot in 0..<min(frame.pose.count, DuckModel.policyJointCount) {
                    pose[DuckModel.jointOfPolicySlot(slot)] = frame.pose[slot]
                }
                pose[DuckModel.mouthIndex] = mouth
                return IntentDraft.Key(time: frame.t, pose: pose)
            }
            return IntentDraft(name: name, keys: keys,
                               provenance: Self.provenance(challenge: challenge,
                                                           name: name, family: family,
                                                           hash: hash, rank: rank))
        }

        static func provenance(challenge: Challenge = .stairs, name: String, family: String?,
                               hash: String?, rank: Int?) -> String {
            var parts = [challenge.provenanceLead]
            if let rank { parts.append("rank \(rank)") }
            if let hash { parts.append("move \(hash)") }
            var line = parts.joined(separator: ", ") + "."
            if let family, !family.isEmpty { line += " \(family)." }
            line += " Simulation only — nothing in the challenge has been run on hardware."
            return line
        }

        /// The same move with the draft's keyframes in it.
        ///
        /// `blend`, `gap`, `side`, `approach`, `isolate` and `stepCount` are
        /// kept, and so is every field this type does not model: what comes
        /// back is the file that went in, with one key replaced. The MOUTH IS
        /// DROPPED — see the note on this type — and `movedMouth(in:)` says
        /// when that lost something.
        public func applying(draft: IntentDraft) throws -> Move {
            let frames: [HarnessJSON] = draft.keys
                .sorted { $0.time < $1.time }
                .map { key in
                    let pose = (0..<DuckModel.policyJointCount).map { slot -> HarnessJSON in
                        let joint = DuckModel.jointOfPolicySlot(slot)
                        return .number(joint < key.pose.count ? key.pose[joint] : 0)
                    }
                    return .object([
                        .init(key: "t", value: .number(key.time)),
                        .init(key: "pose", value: .array(pose)),
                    ])
                }
            return try Move(json: json.setting("keyframes", to: .array(frames)))
        }

        /// Whether a draft moved the one joint the harness format cannot
        /// carry. Only then is `StairsChallenge.mouthDroppedNote` true, and a
        /// caveat shown when it is false is a caveat people learn to skip.
        public static func movedMouth(in draft: IntentDraft) -> Bool {
            let home = DuckModel.homePose[DuckModel.mouthIndex]
            return draft.keys.contains { key in
                key.pose.count > DuckModel.mouthIndex
                    && abs(key.pose[DuckModel.mouthIndex] - home) > 1e-9
            }
        }
    }
}
