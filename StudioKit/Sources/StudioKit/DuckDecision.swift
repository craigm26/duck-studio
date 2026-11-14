import Foundation
import DuckKit

// MARK: - the decision

/// One typed decision from a closed set (docs/plans/brains-layer.md, 3.2).
///
/// A planner answers with exactly one of these. It calls nothing and moves nothing. A runner
/// in the kit carries the decision out later, after the arbiter has clamped it and the gate has
/// checked it.
///
/// ONLY THE V1 CASES ARE HERE. The plan's later cases (`lookAt`, `walkTo`, `drive`, `plan`) are
/// left out of the enum on purpose, not marked unavailable. A case that exists can be decoded,
/// stored and switched on, and an "unavailable" marker does not stop any of that at run time.
/// Left out, a model that writes `{"kind":"look_at"}` is refused by the reader like any other
/// unknown word, and adding a case later is a visible change that every `switch` has to answer.
///
/// THE WIRE SHAPE IS FLAT AND SNAKE_CASE: `{"kind":"walk","forward_m":0.5,"side_m":0}`. It is
/// the shape in `Resources/Planner/duck-decision.schema.json`, which a BYOK tool definition and
/// a Python bench can read without Swift. `DuckDecisionSchemaTests` holds the two together.
public enum DuckDecision: Equatable, Hashable, Sendable {
    /// One of the robot's skills, by the name `robot.skills` gave it. The allowlist narrows it.
    case skill(name: String)
    /// Walk this far, in metres, in the duck's own frame (x forward, y left). The arbiter clamps
    /// it to at most `maxSeconds` at the drive limits before anything moves.
    case walk(forwardM: Double, sideM: Double)
    /// Turn this many degrees, positive to the left. Clamped like a walk.
    case turn(degrees: Double)
    /// One voice-bank sound, by tag.
    case sound(name: String)
    /// Ask the person something. At most one is open in a run.
    case ask(question: String)
    /// The planner thinks the goal is met. The run ends and Stop is sent.
    case done(reason: String)
    /// The planner asks for a stop. It calls the stop path like any other entry point. A stop
    /// never needs a planner to ask for it.
    case stop(reason: String)

    /// The case names on the wire. `CaseIterable`, so the schema test can check every one.
    public enum Kind: String, CaseIterable, Codable, Hashable, Sendable, Comparable {
        case skill, walk, turn, sound, ask, done, stop

        public static func < (a: Kind, b: Kind) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }

        /// The JSON keys this kind carries besides `kind`, in schema order.
        public var fields: [String] {
            switch self {
            case .skill, .sound: return ["name"]
            case .walk: return ["forward_m", "side_m"]
            case .turn: return ["degrees"]
            case .ask: return ["question"]
            case .done, .stop: return ["reason"]
            }
        }

        /// Kinds that only make the duck do less. They are always allowed, never need a Go, and
        /// never count toward a run's limits.
        public var onlyStops: Bool { self == .stop || self == .done }
    }

    public var kind: Kind {
        switch self {
        case .skill: return .skill
        case .walk: return .walk
        case .turn: return .turn
        case .sound: return .sound
        case .ask: return .ask
        case .done: return .done
        case .stop: return .stop
        }
    }

    /// Longest free text a decision may carry (`question`, `reason`). The schema says the same.
    public static let maxTextLength = 280

    /// The longest a walk or turn decision may run at the drive limits. The same 5 s as
    /// `DuckOrder.walkSecondsRange`, so a planner's walk and a tapped walk share one ceiling.
    public static let maxSeconds = DuckOrder.walkSecondsRange.upperBound

    /// The furthest one walk decision may go on each axis: the drive limit for `maxSeconds`.
    public static let maxForwardM = DuckDrive.maxForward * maxSeconds
    public static let maxBackM = DuckDrive.maxBackward * maxSeconds
    public static let maxSideM = DuckDrive.maxSideways * maxSeconds
    /// The most one turn decision may turn, in degrees.
    public static let maxTurnDegrees = DuckDrive.maxTurn * maxSeconds * 180 / .pi

    /// This decision with its numbers held to one decision's limits, and how much of the asked
    /// amount was cut off (0 when nothing was, up to 1). The gate asks for a Go above 20%.
    public func clamped() -> (decision: DuckDecision, cut: Double) {
        switch self {
        case .walk(let f, let s):
            let cf = min(max(f, -Self.maxBackM), Self.maxForwardM)
            let cs = min(max(s, -Self.maxSideM), Self.maxSideM)
            let asked = (f * f + s * s).squareRoot()
            let kept = (cf * cf + cs * cs).squareRoot()
            return (.walk(forwardM: cf, sideM: cs), asked > 0 ? max(0, 1 - kept / asked) : 0)
        case .turn(let d):
            let cd = min(max(d, -Self.maxTurnDegrees), Self.maxTurnDegrees)
            return (.turn(degrees: cd), d != 0 ? max(0, 1 - abs(cd) / abs(d)) : 0)
        default:
            return (self, 0)
        }
    }

    /// Whether every number in it is finite. A decision that is not is refused by the reader.
    public var isFinite: Bool {
        switch self {
        case .walk(let f, let s): return f.isFinite && s.isFinite
        case .turn(let d): return d.isFinite
        default: return true
        }
    }
}

// MARK: - the wire

extension DuckDecision: Codable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// Why a reply could not be read as a decision. The words are `AllowedDecisions.Refusal`'s.
    public enum WireError: Error, Equatable, Sendable {
        case unknownKind(String)
        case unexpectedField(String)
        case missingField(String)
        case wrongType(String)
        case textTooLong(String)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let kindWord: String
        do {
            kindWord = try c.decode(String.self, forKey: Key("kind"))
        } catch DecodingError.keyNotFound {
            throw WireError.missingField("kind")
        } catch {
            throw WireError.wrongType("kind")
        }
        guard let kind = Kind(rawValue: kindWord) else { throw WireError.unknownKind(kindWord) }
        let allowedKeys = Set(["kind"] + kind.fields)
        for key in c.allKeys where !allowedKeys.contains(key.stringValue) {
            throw WireError.unexpectedField(key.stringValue)
        }
        func text(_ name: String) throws -> String {
            guard c.contains(Key(name)) else { throw WireError.missingField(name) }
            guard let s = try? c.decode(String.self, forKey: Key(name)) else { throw WireError.wrongType(name) }
            guard s.count <= DuckDecision.maxTextLength else { throw WireError.textTooLong(name) }
            return s
        }
        func number(_ name: String) throws -> Double {
            guard c.contains(Key(name)) else { throw WireError.missingField(name) }
            guard let d = try? c.decode(Double.self, forKey: Key(name)), d.isFinite else {
                throw WireError.wrongType(name)
            }
            return d
        }
        switch kind {
        case .skill: self = .skill(name: try text("name"))
        case .walk: self = .walk(forwardM: try number("forward_m"), sideM: try number("side_m"))
        case .turn: self = .turn(degrees: try number("degrees"))
        case .sound: self = .sound(name: try text("name"))
        case .ask: self = .ask(question: try text("question"))
        case .done: self = .done(reason: try text("reason"))
        case .stop: self = .stop(reason: try text("reason"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(kind.rawValue, forKey: Key("kind"))
        switch self {
        case .skill(let n), .sound(let n): try c.encode(n, forKey: Key("name"))
        case .walk(let f, let s):
            try c.encode(f, forKey: Key("forward_m"))
            try c.encode(s, forKey: Key("side_m"))
        case .turn(let d): try c.encode(d, forKey: Key("degrees"))
        case .ask(let q): try c.encode(q, forKey: Key("question"))
        case .done(let r), .stop(let r): try c.encode(r, forKey: Key("reason"))
        }
    }
}

// MARK: - the closed set for one run

/// What a planner may answer in this run: the kinds, the skill names and the sound names.
///
/// It is per mode, per venue and per brain kind (3.2). Stop, done and ask are always in it: a
/// stop is never refused, and ask is where a refusal goes.
///
/// DECODING OUTSIDE THE SET IS REFUSED BY NAME, NOT REPAIRED. `read` throws the refusal;
/// `readOrAsk` turns it into an `.ask` that says what was refused, so a run never runs a guess.
public struct AllowedDecisions: Equatable, Hashable, Sendable, Codable {
    public let kinds: Set<DuckDecision.Kind>
    public let skills: [String]
    public let sounds: [String]

    public static let alwaysAllowed: Set<DuckDecision.Kind> = [.stop, .done, .ask]

    private enum CodingKeys: String, CodingKey { case kinds, skills, sounds }

    /// Decoded through `init`, so a stored set cannot drop stop, done or ask.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kinds: try c.decode(Set<DuckDecision.Kind>.self, forKey: .kinds),
                  skills: try c.decodeIfPresent([String].self, forKey: .skills) ?? [],
                  sounds: try c.decodeIfPresent([String].self, forKey: .sounds) ?? [])
    }

    public init(kinds: Set<DuckDecision.Kind>, skills: [String] = [], sounds: [String] = []) {
        self.kinds = kinds.union(Self.alwaysAllowed)
        self.skills = kinds.contains(.skill) ? Array(Set(skills)).sorted() : []
        self.sounds = kinds.contains(.sound) ? Array(Set(sounds)).sorted() : []
    }

    /// The set for this duck and this planner.
    ///
    /// - The practice duck walks and turns, nothing else (`DuckDecider.actions(on: .sim)`).
    /// - A real duck adds the skills and sounds `DuckDecider` already offers.
    /// - A planner that does not run on this phone gets no skills on a real duck in v1 (6.2,
    ///   rule 8).
    public static func forDuck(_ duck: DuckIdentity.Kind, runsOn: RunsOn,
                               robotSkills: [String]? = nil) -> AllowedDecisions {
        switch duck {
        case .sim:
            return AllowedDecisions(kinds: [.walk, .turn])
        case .real:
            let skills = runsOn == .thisPhone ? DuckDecider.skillNames(on: .real, skills: robotSkills) : []
            var kinds: Set<DuckDecision.Kind> = [.walk, .turn, .sound]
            if !skills.isEmpty { kinds.insert(.skill) }
            return AllowedDecisions(kinds: kinds, skills: skills, sounds: DuckDecider.soundNames(on: .real))
        }
    }

    public enum Refusal: Error, Equatable, Sendable {
        case notADecision
        case unknownKind(String)
        case kindNotAllowed(DuckDecision.Kind)
        case unknownSkill(String)
        case unknownSound(String)
        case badField(String)

        public var says: String {
            switch self {
            case .notADecision:
                return "The planner's answer was not one decision this app can read."
            case .unknownKind(let k):
                return "The planner asked for \"\(k)\", which is not something it can decide here."
            case .kindNotAllowed(let k):
                return "The planner asked to \(k.rawValue), which is not allowed in this run."
            case .unknownSkill(let n):
                return "The planner named the move \"\(n)\", which is not one of this duck's moves here."
            case .unknownSound(let n):
                return "The planner named the sound \"\(n)\", which is not one of this duck's sounds."
            case .badField(let f):
                return "The planner wrote \"\(f)\" in a way this app does not read, so nothing was guessed."
            }
        }
    }

    /// The decision if it is inside this set, or the refusal.
    public func admit(_ decision: DuckDecision) -> Result<DuckDecision, Refusal> {
        guard decision.isFinite else { return .failure(.badField(decision.kind.rawValue)) }
        guard kinds.contains(decision.kind) else { return .failure(.kindNotAllowed(decision.kind)) }
        switch decision {
        case .skill(let n) where !skills.contains(n): return .failure(.unknownSkill(n))
        case .sound(let n) where !sounds.contains(n): return .failure(.unknownSound(n))
        default: return .success(decision)
        }
    }

    /// Read one decision from a JSON object, and admit it. Throws `Refusal`.
    public func read(_ data: Data) throws -> DuckDecision {
        let decision: DuckDecision
        do {
            decision = try JSONDecoder().decode(DuckDecision.self, from: data)
        } catch let e as DuckDecision.WireError {
            switch e {
            case .unknownKind(let k): throw Refusal.unknownKind(k)
            case .unexpectedField(let f), .missingField(let f), .wrongType(let f), .textTooLong(let f):
                throw Refusal.badField(f)
            }
        } catch {
            throw Refusal.notADecision
        }
        return try admit(decision).get()
    }

    /// Read one decision, or an `.ask` that says why it could not be. Never a guess.
    public func readOrAsk(_ data: Data) -> DuckDecision {
        do { return try read(data) } catch let r as Refusal {
            return .ask(question: r.says + " What should the duck do?")
        } catch {
            return .ask(question: Refusal.notADecision.says + " What should the duck do?")
        }
    }
}

// MARK: - a planner, and what it is asked

/// A planner's answer, with the reason it gave and who gave it.
///
/// `confidence` is the planner's own number. It may only ADD a confirmation, never remove one
/// (`DuckEnvelopeGate.confirmations`). Nothing in the kit reads a high confidence as permission.
public struct Decided: Equatable, Sendable {
    public let decision: DuckDecision
    public let why: String
    public let confidence: Double?
    public let provider: PlannerInfo
    public let latency: Duration

    public init(decision: DuckDecision, why: String, confidence: Double? = nil,
                provider: PlannerInfo, latency: Duration) {
        self.decision = decision
        self.why = why
        self.confidence = confidence
        self.provider = provider
        self.latency = latency
    }
}

/// The duck as a planner sees it at the moment it is asked.
public struct DuckStateSnapshot: Equatable, Sendable, Codable {
    /// Odometry pose: x and y in metres, yaw in radians. Nil when the duck reports none.
    public let x: Double?
    public let y: Double?
    public let yaw: Double?
    /// How old that odometry is, in milliseconds.
    public let odomAgeMs: Double?
    public let standing: Bool?
    public let lastSkill: String?
    /// Distance to the nearest edge of the keep-in area, in metres.
    public let keepInMarginM: Double?

    public init(x: Double? = nil, y: Double? = nil, yaw: Double? = nil, odomAgeMs: Double? = nil,
                standing: Bool? = nil, lastSkill: String? = nil, keepInMarginM: Double? = nil) {
        self.x = x; self.y = y; self.yaw = yaw
        self.odomAgeMs = odomAgeMs
        self.standing = standing
        self.lastSkill = lastSkill
        self.keepInMarginM = keepInMarginM
    }
}

/// One question to a planner.
///
/// `goal` comes from the person's own turn only. Tool results and anything read from the camera
/// never set it (3.2, prompt injection).
public struct PlannerAsk: Sendable {
    public let goal: String
    public let utterance: String?
    /// One JPEG, only when the provider takes images and camera consent was given.
    public let frame: Data?
    public let frameTimestamp: ContinuousClock.Instant?
    public let state: DuckStateSnapshot
    public let allowed: AllowedDecisions
    /// The last few decisions in this run.
    public let history: [Decided]

    public init(goal: String, utterance: String? = nil, frame: Data? = nil,
                frameTimestamp: ContinuousClock.Instant? = nil, state: DuckStateSnapshot,
                allowed: AllowedDecisions, history: [Decided] = []) {
        self.goal = goal
        self.utterance = utterance
        self.frame = frame
        self.frameTimestamp = frameTimestamp
        self.state = state
        self.allowed = allowed
        self.history = history
    }
}

/// Something that picks one decision from a closed set. It calls nothing.
public protocol Planner: Sendable {
    var info: PlannerInfo { get }
    func decide(_ ask: PlannerAsk) async throws -> Decided
}
