import Foundation
import DuckKit

extension BallChallenge {

    /// An entrant — the file the scorer replays and the leaderboard is keyed
    /// by — in either of its two kinds.
    ///
    /// IT KEEPS EVERYTHING IT DOES NOT UNDERSTAND, for the same reason
    /// `StairsChallenge.Move` does and with the same machinery. The bench
    /// hashes the object it receives, key order and digits included, so the
    /// whole file is held as `HarnessJSON` and the typed properties below are
    /// a VIEW of it rather than a replacement for it. A file that also carries
    /// stairs fields is a DIFFERENT entrant, not a silently equivalent one:
    /// unknown keys are preserved and hashed, never stripped.
    ///
    /// A MOVE ENTRANT IS A STAIRS MOVE IN A WRAPPER, ON PURPOSE. `intent` is
    /// parsed by `StairsChallenge.Move`, which already knows that a harness
    /// pose is fourteen joints with the mouth dropped, already widens to
    /// fifteen for the editor and already narrows back. Two transcriptions of
    /// that mapping is how a keyframe edit comes to land on the wrong joint in
    /// one challenge and not the other, with nothing to notice.
    ///
    /// A POLICY ENTRANT HAS NO KEYFRAMES AND IS NOT EDITABLE. It is a network
    /// name and a command schedule, and it is in the format from day one
    /// because it is what makes "chase" a closed-loop question later: the same
    /// `schedule` field carries a fixed list today and a list computed from
    /// the ball's bearing tomorrow, with no change to the file, the hash, this
    /// kit or the app.
    public struct Entrant: Equatable, Sendable, Identifiable {

        public enum Kind: String, Equatable, Sendable, Codable {
            case move
            case policy

            /// The word on a row, so a list can say which kind it is looking
            /// at without a legend.
            public var said: String {
                switch self {
                case .move:   return "authored move"
                case .policy: return "policy"
                }
            }
        }

        public enum Refusal: Error, Equatable {
            case notAnObject
            case unknownKind(String)
            case noPolicyNamed
            case noSchedule
            case badSeconds(Double)
            case notAMove(String)
            case notEditable

            public var message: String {
                switch self {
                case .notAnObject:
                    return "That is not a ball-challenge entrant: the file has to be one JSON "
                         + "object."
                case .unknownKind(let kind):
                    return "\"\(kind)\" is not an entrant kind. There are two: \"move\", which "
                         + "is keyframes, and \"policy\", which is a trained network under a "
                         + "command schedule."
                case .noPolicyNamed:
                    return "That policy entrant does not name a policy, so there is nothing for "
                         + "the bench to run."
                case .noSchedule:
                    return "That policy entrant has no command schedule. A schedule is a list of "
                         + "[seconds, {vx, vy, vyaw}]; an entrant commanded by nothing is not an "
                         + "entrant."
                case .badSeconds(let seconds):
                    return "An episode of \(seconds) seconds is not one. Give the seconds the "
                         + "entrant should be run for."
                case .notAMove(let why):
                    return "The intent inside that move entrant is not a harness intent: \(why)"
                case .notEditable:
                    return BallChallenge.policyNotEditable
                }
            }
        }

        /// The whole file, order and digits intact.
        public let json: HarnessJSON

        public var name: String { json["name"]?.stringValue ?? "unnamed" }
        public var note: String? { json["note"]?.stringValue }

        public let kind: Kind
        /// The episode length the entrant declares, in seconds.
        public let seconds: Double
        /// `.policy` only.
        public let policy: String?
        /// `.policy` only. The core's `commandAt` contract: the last entry
        /// that has begun wins.
        public let schedule: [DuckBench.Step]
        /// `.move` only.
        public let move: StairsChallenge.Move?

        public var id: String { name }

        /// Whether there are keyframes in it to open.
        public var isEditable: Bool { kind == .move }

        /// The command, in words, for a row that has no room for a schedule.
        /// Nil for a move: a move has no command at all, and printing "held at
        /// rest" for one would say it was commanded.
        public var commandSaid: String? {
            guard kind == .policy else { return nil }
            guard let first = schedule.first else { return "no command" }
            let rest = schedule.count > 1 ? ", then \(schedule.count - 1) more" : ""
            if first.vx == 0, first.vy == 0, first.vyaw == 0 {
                return "held at rest\(rest)"
            }
            var parts: [String] = []
            if first.vx != 0 { parts.append("vx \(Self.trim(first.vx))") }
            if first.vy != 0 { parts.append("vy \(Self.trim(first.vy))") }
            if first.vyaw != 0 { parts.append("vyaw \(Self.trim(first.vyaw))") }
            return parts.joined(separator: ", ") + rest
        }

        static func trim(_ value: Double) -> String {
            value == value.rounded() ? "\(Int(value))" : "\(value)"
        }

        /// One line for a list row: the kind, the length, and the command.
        public var subtitle: String {
            var parts = [kind.said, BallChallenge.secondsSaid(seconds)]
            if let policy { parts.append(policy) }
            if let commandSaid { parts.append(commandSaid) }
            if kind == .move, let move { parts.append("\(move.keyframes.count) keyframes") }
            return parts.joined(separator: " · ")
        }

        // MARK: - reading and writing one

        public init(json: HarnessJSON) throws {
            guard case .object = json else { throw Refusal.notAnObject }
            self.json = json

            let kindText = json["kind"]?.stringValue ?? ""
            guard let kind = Kind(rawValue: kindText) else {
                throw Refusal.unknownKind(kindText)
            }
            self.kind = kind

            let seconds = json["seconds"]?.doubleValue ?? 0
            guard seconds > 0, seconds.isFinite else { throw Refusal.badSeconds(seconds) }
            self.seconds = seconds

            switch kind {
            case .move:
                guard let intent = json["intent"] else {
                    throw Refusal.notAMove("there is no `intent` object in the file.")
                }
                do {
                    self.move = try StairsChallenge.Move(json: intent)
                } catch let refusal as StairsChallenge.Move.Refusal {
                    throw Refusal.notAMove(refusal.message)
                }
                self.policy = nil
                self.schedule = []
            case .policy:
                guard let policy = json["policy"]?.stringValue, !policy.isEmpty else {
                    throw Refusal.noPolicyNamed
                }
                guard let rows = json["schedule"]?.arrayValue, !rows.isEmpty else {
                    throw Refusal.noSchedule
                }
                self.policy = policy
                self.schedule = rows.compactMap(Self.step)
                self.move = nil
                guard !self.schedule.isEmpty else { throw Refusal.noSchedule }
            }
        }

        /// `[atSeconds, {vx, vy, vyaw}]`, the core's own schedule shape.
        static func step(_ row: HarnessJSON) -> DuckBench.Step? {
            guard let pair = row.arrayValue, pair.count >= 2,
                  let at = pair[0].doubleValue else { return nil }
            let twist = pair[1]
            return DuckBench.Step(at: at,
                                  vx: twist["vx"]?.doubleValue ?? 0,
                                  vy: twist["vy"]?.doubleValue ?? 0,
                                  vyaw: twist["vyaw"]?.doubleValue ?? 0)
        }

        public static func decode(_ data: Data) throws -> Entrant {
            try Entrant(json: HarnessJSON.parse(data))
        }

        /// The file again, in the shape `JSON.stringify(value, null, 2)`
        /// writes — so an unedited entrant comes back out as the bytes it went
        /// in as.
        public func encoded() -> Data { json.encoded(.pretty) }

        // MARK: - into the editor and back

        /// The editable draft this entrant opens as.
        ///
        /// A POLICY REFUSES BY NAME rather than opening an empty draft. The
        /// screen is expected to have shown `policyNotEditable` and hidden the
        /// button before it gets here; this is the second lock.
        public func toDraft(hash: String? = nil, rank: Int? = nil) throws -> IntentDraft {
            guard let move else { throw Refusal.notEditable }
            return move.toDraft(challenge: .ball, hash: hash, rank: rank)
        }

        /// The same entrant with the draft's keyframes in it. Every other
        /// field of the file survives — `seconds`, `note`, and anything this
        /// type does not model — so what comes back is the file that went in
        /// with one key inside `intent` replaced.
        public func applying(draft: IntentDraft) throws -> Entrant {
            guard let move else { throw Refusal.notEditable }
            let edited = try move.applying(draft: draft)
            return try Entrant(json: json.setting("intent", to: edited.json))
        }

        /// Whether a draft moved the one joint the harness format cannot
        /// carry.
        public static func movedMouth(in draft: IntentDraft) -> Bool {
            StairsChallenge.Move.movedMouth(in: draft)
        }
    }
}
