import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLRequest lives here on Linux, where these tests run
#endif
import DuckEvidence

/// A plain-language request as a router proposed it, in a form a person edits
/// before anything moves — `duck-intent-plan/0`, the format craigm26/duckbatch's
/// `router.py` writes.
///
/// THE ROUTER PROPOSES; IT DOES NOT COMMAND. A request comes back as steps, one
/// per clause, each with a label per head (action, speed, head, sound) and the
/// model's confidence in each. The plan editor shows those steps as a chain of
/// nodes, the person keeps, edits or discards each one, and only then does the
/// plan become something the duck is asked to do. Every one of those decisions
/// is a `route_correction` record, which is the ground truth the router was
/// graded without.
///
/// THE ROUTER'S NUMBERS ARE READ AND THEN IGNORED. The file carries a
/// `command` per step, with velocities worked out against Pollen's limits.
/// This app has its own limits (`DuckDrive`), and `SequenceProposal.resolve`
/// is where every velocity it sends is derived and clamped — so a step goes
/// to the duck as its LABELS, mapped here, and never as a number somebody
/// else's code chose. That is the router's own rule ("the model picks a label;
/// code owns what the label means") applied one hop further.
///
/// ONLY CONFIDENT LABELS ARE TAKEN ON TRUST. duckbatch's r001 measured
/// GLiNER2.5-Decide wrong only at confidence 0.56 and below, and right on every
/// label at 0.6 and above, so `autoAccept` is 0.6: a label under it is flagged
/// for the person rather than silently used.
public struct DuckIntentPlan: Equatable, Sendable {

    public static let format = "duck-intent-plan/0"
    public static let readableFormats: Set<String> = [format]

    /// r001's measured line: every label at or above it was right.
    public static let autoAccept = 0.6

    /// How long one movement step lasts unless the person says otherwise. The
    /// router's own `DEFAULT_MOVE_S`, so an untouched plan runs as proposed.
    public static let defaultSeconds = 2.0

    // MARK: - the vocabulary

    /// The labels a router may use, by vocabulary id. A label outside it is
    /// refused on reading, because a record carrying it would be refused by
    /// duckbatch's reader and a step carrying it has no mapping here.
    public enum Vocabulary {
        public static let id = "r001"
        public static let actions = ["walk_forward", "walk_backward", "turn_left", "turn_right",
                                     "stop", "kick_left", "kick_right", "sit_or_stand", "roll",
                                     "peck_ground", "make_sound", "unsupported"]
        public static let speeds = ["slow", "normal", "fast"]
        public static let heads = ["straight", "look_left", "look_right", "look_up", "look_down"]
        public static let sounds = ["greet", "alarm", "inquire", "peck", "chirp", "coo", "wheee"]

        public static func labels(for head: Head) -> [String] {
            switch head {
            case .action: return actions
            case .speed: return speeds
            case .head: return heads
            case .sound: return sounds
            }
        }

        /// What a person reads for a label. The vocabulary's spelling is the
        /// wire's; this is the screen's.
        public static func words(_ label: String) -> String {
            switch label {
            case "walk_forward": return "Walk forward"
            case "walk_backward": return "Walk back"
            case "turn_left": return "Turn left"
            case "turn_right": return "Turn right"
            case "stop": return "Stop"
            case "kick_left": return "Kick, left"
            case "kick_right": return "Kick, right"
            case "sit_or_stand": return "Sit or stand"
            case "roll": return "Roll"
            case "peck_ground": return "Peck the ground"
            case "make_sound": return "Make a sound"
            case "unsupported": return "Not something it can do"
            case "look_left": return "Look left"
            case "look_right": return "Look right"
            case "look_up": return "Look up"
            case "look_down": return "Look down"
            case "straight": return "Straight ahead"
            case "greet": return "Hello"
            case "wheee": return "Wheee"
            default: return label.prefix(1).uppercased() + label.dropFirst()
            }
        }
    }

    /// The four things a router decides about a clause.
    public enum Head: String, Sendable, CaseIterable {
        case action, speed, head, sound
    }

    // MARK: - one node

    /// One clause, as proposed and as it stands now.
    public struct Node: Equatable, Sendable, Identifiable {
        /// Its position in the request as proposed. Stable across reordering,
        /// so a view keeps track of a node the person has dragged.
        public let id: Int
        public let clause: String
        public let proposed: [String: String]
        public let confidence: [String: Double]
        /// The labels now. Starts equal to `proposed`.
        public private(set) var labels: [String: String]
        /// Movement steps only: how long it is held.
        public var seconds: Double
        public var discarded: Bool
        /// Whether `confidence` means anything. A router scores every label; a
        /// language model writing a whole plan (`ModelIntentPlanner`) scores
        /// none, and an absent score read as 0 would flag every head of every
        /// step — a screen that asks about everything asks about nothing. So a
        /// planner's node says it was not measured, and is not flagged; the
        /// person still sees the whole chain before anything moves.
        public let measured: Bool

        public init(id: Int, clause: String, proposed: [String: String],
                    confidence: [String: Double], measured: Bool = true) {
            self.id = id
            self.clause = clause
            self.proposed = proposed
            self.confidence = confidence
            self.labels = proposed
            self.seconds = DuckIntentPlan.defaultSeconds
            self.discarded = false
            self.measured = measured
        }

        public var action: String { labels["action"] ?? "unsupported" }

        /// The heads that mean anything for this action. A kick has no speed
        /// and a sound has no head direction, so neither is shown, flagged or
        /// offered for editing — a low confidence on a head nobody uses is not
        /// something to ask a person about.
        public var heads: [Head] {
            switch action {
            case "walk_forward", "walk_backward", "turn_left", "turn_right": return [.action, .speed, .head]
            case "stop": return [.action, .head]
            case "make_sound": return [.action, .sound]
            default: return [.action]
            }
        }

        /// Heads whose PROPOSED label was under the line, and still is as
        /// proposed. Once a person has chosen, it is theirs and not flagged.
        public var flagged: [Head] {
            guard measured else { return [] }
            return heads.filter { head in
                let key = head.rawValue
                guard labels[key] == proposed[key] else { return false }
                return (confidence[key] ?? 0) < DuckIntentPlan.autoAccept
            }
        }

        /// The router said this is not something the duck can do.
        public var isRefusal: Bool { action == "unsupported" }

        public var isMovement: Bool {
            ["walk_forward", "walk_backward", "turn_left", "turn_right", "stop"].contains(action)
        }

        /// Refuses a label outside the vocabulary — the reader would.
        public mutating func set(_ head: Head, to label: String) throws {
            guard Vocabulary.labels(for: head).contains(label) else {
                throw ReadError.unknownLabel(head.rawValue, label)
            }
            labels[head.rawValue] = label
        }

        /// What happened to it, in `duck-feedback/0`'s words.
        public var outcome: DuckFeedback.Outcome {
            if discarded { return .rejected }
            return labels == proposed ? .accepted : .edited
        }
    }

    public let request: String
    /// The model that proposed, as the router named it (`decide`, `jev`).
    public let model: String
    public private(set) var nodes: [Node]

    public init(request: String, model: String, nodes: [Node]) {
        self.request = request
        self.model = model
        self.nodes = nodes
    }

    public mutating func update(_ node: Node) {
        guard let i = nodes.firstIndex(where: { $0.id == node.id }) else { return }
        nodes[i] = node
    }

    public mutating func move(from source: Int, to destination: Int) {
        guard nodes.indices.contains(source), (0...nodes.count).contains(destination) else { return }
        let node = nodes.remove(at: source)
        nodes.insert(node, at: destination > source ? destination - 1 : destination)
    }

    /// Nodes still flagged, across the plan — what the screen asks about first.
    public var flaggedCount: Int { nodes.filter { !$0.discarded }.map(\.flagged.count).reduce(0, +) }

    // MARK: - reading

    public enum ReadError: Error, Equatable {
        case notJSON
        case wrongFormat(String)
        case missing(String)
        case unknownLabel(String, String)
        case noSteps

        public var message: String {
            switch self {
            case .notJSON:
                return "The router's answer is not JSON, so there is no plan in it."
            case .wrongFormat(let found):
                return "The router answered in format \"\(found)\", which this version does not read."
            case .missing(let field):
                return "The router's plan is missing \(field)."
            case .unknownLabel(let head, let label):
                return "\"\(label)\" is not a \(head) this app knows (vocabulary \(Vocabulary.id)). "
                     + "A step carrying it could not be run or recorded, so the plan was refused "
                     + "rather than guessed at."
            case .noSteps:
                return "The router found no steps in that. Try saying what the duck should do, "
                     + "one thing after another."
            }
        }
    }

    /// Strict: every label is checked against the vocabulary. The `command`
    /// block is read past on purpose — see the type's comment.
    public static func read(_ data: Data) throws -> DuckIntentPlan {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        guard let format = top["format"] as? String else { throw ReadError.missing("a format") }
        guard readableFormats.contains(format) else { throw ReadError.wrongFormat(format) }
        guard let request = top["request"] as? String else { throw ReadError.missing("the request") }
        guard let steps = top["steps"] as? [[String: Any]] else { throw ReadError.missing("steps") }
        guard !steps.isEmpty else { throw ReadError.noSteps }
        var nodes: [Node] = []
        for (i, step) in steps.enumerated() {
            guard let clause = step["clause"] as? String else { throw ReadError.missing("a clause") }
            guard let labels = step["labels"] as? [String: String] else {
                throw ReadError.missing("labels for \"\(clause)\"")
            }
            guard labels["action"] != nil else { throw ReadError.missing("an action for \"\(clause)\"") }
            for (key, label) in labels {
                guard let head = Head(rawValue: key) else { continue }
                guard Vocabulary.labels(for: head).contains(label) else {
                    throw ReadError.unknownLabel(key, label)
                }
            }
            var confidence: [String: Double] = [:]
            for (key, value) in step["confidence"] as? [String: Any] ?? [:] {
                if let number = value as? Double { confidence[key] = number }
                else if let number = value as? Int { confidence[key] = Double(number) }
            }
            nodes.append(Node(id: i, clause: clause, proposed: labels, confidence: confidence))
        }
        return DuckIntentPlan(request: request, model: (top["model"] as? String) ?? "a router",
                              nodes: nodes)
    }

    // MARK: - running

    /// What the plan becomes on a bench: moves for `SequenceProposal`, and at
    /// most one skill loaded when they finish.
    public struct Run: Equatable, Sendable {
        public let moves: [SequenceProposal.Move]
        public let thenLoading: DuckOfficialPolicies.Slot?
        /// Parts of the plan that stay in it but are not sent, each said once.
        public let notSent: [String]
    }

    public enum RunRefusal: Error, Equatable {
        case nothingToRun
        case skillNotLast(String)
        case twoSkills(String, String)

        public var message: String {
            switch self {
            case .nothingToRun:
                return "Every step is discarded or refused, so there is nothing to send. Keep at "
                     + "least one movement or skill."
            case .skillNotLast(let clause):
                return "\"\(clause)\" loads a skill network, and a skill does not hand the duck "
                     + "back to the walker when it finishes — so it can only be the last step. "
                     + "Move it to the end or discard it."
            case .twoSkills(let first, let second):
                return "\"\(first)\" and \"\(second)\" are both skills, and a plan can end in one "
                     + "skill, not two. Discard one of them."
            }
        }
    }

    /// Movement labels as the words `SequenceProposal` resolves.
    static let goes = ["walk_forward": "forward", "walk_backward": "back",
                       "turn_left": "turn left", "turn_right": "turn right", "stop": "stop"]
    /// The router's shares of the limit, so slow/normal/fast mean what the
    /// router meant by them — against THIS app's limits.
    static let shares = ["slow": 1.0 / 3.0, "normal": 2.0 / 3.0, "fast": 1.0]
    static let skills: [String: DuckOfficialPolicies.Slot] = [
        "kick_left": .kickLeft, "kick_right": .kickRight, "sit_or_stand": .sitstand,
        "roll": .roulade, "peck_ground": .groundPick,
    ]

    /// Map the kept nodes, in their current order, or refuse by name.
    public func run() throws -> Run {
        let kept = nodes.filter { !$0.discarded && !$0.isRefusal }
        var moves: [SequenceProposal.Move] = []
        var slot: DuckOfficialPolicies.Slot?
        var skillClause: String?
        var heads = false, sounds: [String] = []
        for node in kept {
            if let skill = DuckIntentPlan.skills[node.action] {
                if let earlier = skillClause { throw RunRefusal.twoSkills(earlier, node.clause) }
                slot = skill
                skillClause = node.clause
                continue
            }
            if let clause = skillClause { throw RunRefusal.skillNotLast(clause) }
            if node.action == "make_sound" {
                sounds.append(node.clause)
                continue
            }
            guard let go = DuckIntentPlan.goes[node.action] else { continue }
            if (node.labels["head"] ?? "straight") != "straight" { heads = true }
            let share = node.action == "stop" ? nil
                : DuckIntentPlan.shares[node.labels["speed"] ?? "normal"]
            moves.append(SequenceProposal.Move(go: go, seconds: node.seconds, speed: share))
        }
        guard !moves.isEmpty || slot != nil else { throw RunRefusal.nothingToRun }
        // A SEQUENCE IS AT LEAST ONE MOVE, and a plan that is only a kick is
        // still a plan. One second of standing is what the pad would send
        // before the button, so it is what this sends.
        if moves.isEmpty { moves = [SequenceProposal.Move(go: "stop", seconds: 1)] }
        var notSent: [String] = []
        if heads {
            notSent.append("Where the head looks is kept in the plan but not sent: a bench takes a "
                         + "velocity twist and no head pose.")
        }
        if !sounds.isEmpty {
            notSent.append("Sounds are kept in the plan but not played: \(sounds.joined(separator: ", ")). "
                         + "A bench has no speaker.")
        }
        return Run(moves: moves, thenLoading: slot, notSent: notSent)
    }

    // MARK: - what the person told us

    /// Which router, for the record. The model id and revision are what
    /// duckbatch pinned for r001; a different router says so itself.
    public struct RouterIdentity: Equatable, Sendable {
        public let model: String
        public let revision: String
        public init(model: String, revision: String) { self.model = model; self.revision = revision }
        public static let decide = RouterIdentity(model: "fastino/GLiNER2.5-Decide", revision: "65624f1")
    }

    /// One `route_correction` per node, in the order proposed.
    ///
    /// CONSENT IS PASSED IN, NOT READ FROM A SETTING HERE. The caller holds the
    /// person's choice and it defaults to `.local`, so a record that nobody
    /// agreed to share is still written — the person can see their own edits —
    /// and `mayLeaveDevice` keeps it on the phone.
    public func corrections(router: RouterIdentity, share: DuckFeedback.Share,
                            client: String, at when: Date = Date()) throws -> [DuckFeedback] {
        try nodes.sorted { $0.id < $1.id }.map { node in
            try DuckFeedback.routeCorrection(
                request: request, clause: node.clause,
                router: router.model, revision: router.revision, vocabulary: Vocabulary.id,
                proposed: node.proposed, confidence: node.confidence,
                final: node.discarded ? nil : node.labels, outcome: node.outcome,
                share: share, client: client, created: when)
        }
    }
}

// MARK: - where a plan comes from

/// Something that turns a request into a proposed plan.
///
/// A PROTOCOL SO THE ROUTER CAN MOVE. Today it is GLiNER2.5-Decide behind a
/// small HTTP service (duckbatch's `route_server.py`, on the Pi); an on-device
/// model is the obvious next home, and a screen written against this does not
/// change when it gets there.
public protocol IntentRouting: Sendable {
    var identity: DuckIntentPlan.RouterIdentity { get }
    func plan(for request: String) async throws -> DuckIntentPlan
}

/// A router over HTTP: `POST <base>/route` with `{"text": …}`, answered with a
/// `duck-intent-plan/0`.
///
/// IT TAKES AN ERRAND, NOT A `URLSession` — `BenchPeer`'s reason: the request
/// and the reading are checked by `swift test` on Linux, and the app owns the
/// session, the timeout and the network.
public struct HTTPIntentRouter: IntentRouting {
    public typealias Errand = @Sendable (URLRequest) async throws -> Data

    public let base: URL
    public let identity: DuckIntentPlan.RouterIdentity
    private let errand: Errand

    public init(base: URL, identity: DuckIntentPlan.RouterIdentity = .decide, errand: @escaping Errand) {
        self.base = base
        self.identity = identity
        self.errand = errand
    }

    /// Decide takes about 1.4 s a clause on an x86 CPU and, measured on
    /// 2026-09-24, about 32 s a clause on a Raspberry Pi 5 (four threads). A three-step
    /// request on a Pi is minutes, so the timeout allows five of them rather
    /// than cutting a slow router off mid-answer.
    public static let timeout: TimeInterval = 300

    public func request(for text: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("route"))
        request.httpMethod = "POST"
        request.timeoutInterval = HTTPIntentRouter.timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["text": text])
        return request
    }

    public func plan(for text: String) async throws -> DuckIntentPlan {
        try DuckIntentPlan.read(try await errand(request(for: text)))
    }
}
