import Foundation

/// What a person told the app, as a `duck-feedback/0` record — the format
/// craigm26/duckbatch reads (`docs/duck-feedback-0.md` there) to recalibrate the
/// plain-language router, fine-tune it, and learn which policies people prefer.
///
/// THE APP IS WHERE THE GROUND TRUTH IS. Every judge duckbatch measured was
/// graded against rules or labels one person wrote, and one of those labels
/// (the head during a turn) turned out to be a guess. A person editing a
/// proposed step, or choosing which of two ducks walks better, is the label that
/// was missing. This type turns that act into a record the pipeline accepts.
///
/// CONSENT IS PART OF THE RECORD, NOT A SETTING BESIDE IT. A record cannot be
/// built without saying how far it may travel, and `share == .local` is a
/// record that the reader refuses to ingest — so the only way a correction
/// reaches training is a person having said it may. No name, no account, no
/// device identifier: `id` is a fresh UUID per record, never derived from the
/// person or the phone.
///
/// IT REFUSES WHAT THE READER WOULD. An edit that changes nothing, an
/// acceptance that changed something, two sides of a preference that are the
/// same network, a reason outside the fixed list — each throws here with the
/// reader's own words, so nothing leaves the phone that duckbatch rejects.
public struct DuckFeedback: Equatable, Sendable {

    public static let format = "duck-feedback/0"

    public enum Share: String, Sendable, CaseIterable {
        /// Stays on this device. The reader refuses to ingest it.
        case local
        /// May go to a private dataset for training and evaluation.
        case research
        /// May appear in a public dataset.
        case `public`
    }

    public enum Outcome: String, Sendable { case accepted, edited, rejected }
    public enum Choice: String, Sendable { case a, b, tie, bothBad = "both_bad" }
    public enum Where: String, Sendable { case sim, phoneBench = "phone_bench", ar, robot }
    public enum Order: String, Sendable { case aLeft = "a_left", bLeft = "b_left" }
    /// A fixed list, so reasons can be counted. There is no free text.
    public enum Reason: String, Sendable, CaseIterable {
        case steadier, moreNatural = "more natural", faster
        case followsTheCommand = "follows the command", fell, jittery, other
    }

    public enum Refusal: Error, Equatable {
        case noLabels
        case acceptedButChanged
        case editedButUnchanged
        case sameNetwork
        case emptyClause

        public var message: String {
            switch self {
            case .noLabels: return "A correction needs the proposed labels, including an action."
            case .acceptedButChanged: return "The outcome says accepted but labels changed."
            case .editedButUnchanged: return "The outcome says edited but no label changed."
            case .sameNetwork: return "A preference between a network and itself says nothing."
            case .emptyClause: return "There is no clause to learn from."
            }
        }
    }

    public struct Policy: Equatable, Sendable {
        public let repo: String
        public let file: String?
        /// `DuckPolicy.fingerprint` (DuckEvidence), so a preference is about a
        /// network and not a filename. Written as `sha256:<hex>`.
        public let fingerprint: String
        public init(repo: String, file: String? = nil, fingerprint: String) {
            self.repo = repo; self.file = file; self.fingerprint = fingerprint
        }
    }

    public let id: String
    public let created: Date
    public let share: Share
    public let client: String
    private let body: [String: Any]
    private let kind: String

    public static func == (a: DuckFeedback, b: DuckFeedback) -> Bool {
        a.id == b.id && a.jsonLine() == b.jsonLine()
    }

    // MARK: - the two kinds

    /// The person kept, edited or discarded what the router proposed for one clause.
    public static func routeCorrection(
        request: String, clause: String,
        router model: String, revision: String, vocabulary: String,
        proposed: [String: String], confidence: [String: Double],
        final: [String: String]?, outcome: Outcome,
        share: Share, client: String, id: UUID = UUID(), created: Date = Date()
    ) throws -> DuckFeedback {
        guard !clause.trimmingCharacters(in: .whitespaces).isEmpty else { throw Refusal.emptyClause }
        guard proposed["action"] != nil else { throw Refusal.noLabels }
        switch outcome {
        case .accepted where final != proposed: throw Refusal.acceptedButChanged
        case .edited where final == nil || final == proposed: throw Refusal.editedButUnchanged
        default: break
        }
        var block: [String: Any] = [
            "request": request, "clause": clause,
            "router": ["model": model, "revision": revision, "vocabulary": vocabulary],
            "proposed": ["labels": proposed, "confidence": confidence],
            "outcome": outcome.rawValue,
        ]
        if let final { block["final"] = ["labels": final] }
        return DuckFeedback(id: id.uuidString.lowercased(), created: created, share: share,
                            client: client, body: block, kind: "route_correction")
    }

    /// The person watched two policies do the same thing and chose.
    public static func policyPreference(
        a: Policy, b: Policy, choice: Choice, reasons: [Reason] = [],
        where place: Where, order: Order, command: [Double]? = nil, seconds: Double? = nil,
        seed: Int? = nil, pairID: String? = nil,
        share: Share, client: String, id: UUID = UUID(), created: Date = Date()
    ) throws -> DuckFeedback {
        guard a.fingerprint != b.fingerprint else { throw Refusal.sameNetwork }
        func side(_ p: Policy) -> [String: Any] {
            var s: [String: Any] = ["repo": p.repo, "fingerprint": p.fingerprint]
            if let f = p.file { s["file"] = f }
            return s
        }
        var shown: [String: Any] = ["where": place.rawValue, "order": order.rawValue]
        if let command { shown["command"] = command }
        if let seconds { shown["seconds"] = seconds }
        if let seed { shown["seed"] = seed }
        if let pairID { shown["pair_id"] = pairID }
        let block: [String: Any] = ["a": side(a), "b": side(b), "shown": shown,
                                    "choice": choice.rawValue, "reasons": reasons.map(\.rawValue)]
        return DuckFeedback(id: id.uuidString.lowercased(), created: created, share: share,
                            client: client, body: block, kind: "policy_preference")
    }

    // MARK: - writing

    /// One JSONL line, keys sorted, no trailing newline.
    public func jsonLine() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        let object: [String: Any] = [
            "format": DuckFeedback.format, "id": id, "created": formatter.string(from: created),
            "kind": kind, "consent": ["opt_in": true, "share": share.rawValue],
            "source": ["client": client], kind: body,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: object,
                                                 options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Whether this record may ever leave the device.
    public var mayLeaveDevice: Bool { share != .local }
}
