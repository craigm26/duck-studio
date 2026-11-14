import Foundation

// MARK: - the action sources a planner may name

/// The action sources a `.drive` decision may hand the duck to (brains-layer.md 3.1, 3.3).
///
/// A CLOSED SET IN THE KIT. A planner names one by its id, and an id outside this enum is refused
/// by the reader before `AllowedDecisions` even looks at it. Inside it, a run narrows it again:
/// `AllowedDecisions.sources` is empty unless a caller opts in, so no planner can drive by
/// default. Adding a source is a visible change here, the same as adding a decision kind.
///
/// The bridge-side VLA adapters (openpi, GR00T, SmolVLA) are not here: none has a Swift client or
/// duck fine-tuning yet (3.1, roadmap item 6).
public enum ActionSourceID: String, CaseIterable, Codable, Hashable, Sendable, Comparable {
    /// Dream Labs' Dream-1, by `DreamDirect` or the bridge's `dream.act`. Plain, with no assist.
    case dream1 = "dreamlabs.dream-1"
    /// The phone driver, ducknet-s1, run on this phone (`LocalDreamRows`).
    case phoneDriver = "phone.ducknet-s1"

    public static func < (a: ActionSourceID, b: ActionSourceID) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - a plan as a planner proposes it

/// The `.plan` decision's payload: a few beats in the router's r001 labels, which
/// `RobotPlan(DuckIntentPlan)` turns into what a duck runs (3.2, "When `.plan` arrives, it wraps
/// `RobotPlan(DuckIntentPlan)`").
///
/// LABELS, NEVER NUMBERS FOR A MOTOR. A beat names an action and a speed word. The twist each one
/// becomes is `SequenceProposal.twist(for:share:)`'s, the same door every plan goes through, so a
/// planner cannot ask for a velocity. Its only number is how long a timed beat lasts, and the
/// arbiter clamps that.
///
/// NO SOUND BEATS. A sound is its own `.sound` decision. Leaving `make_sound` out keeps every beat
/// to the same three fields, which a strict tool schema needs.
public struct RobotPlanProposal: Equatable, Hashable, Sendable, Codable {

    public struct Beat: Equatable, Hashable, Sendable, Codable {
        /// One of `RobotPlanProposal.actions`, in r001's spelling.
        public let action: String
        /// One of `RobotPlanProposal.speeds`. Read for timed beats only.
        public let speed: String
        /// How long a timed beat lasts. A skill beat's own length comes from robotd, not from here.
        public let seconds: Double

        public init(action: String, speed: String = "normal", seconds: Double = DuckIntentPlan.defaultSeconds) {
            self.action = action
            self.speed = speed
            self.seconds = seconds
        }

        private enum CodingKeys: String, CodingKey, CaseIterable { case action, speed, seconds }

        private struct AnyKey: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        /// Refuses rather than repairs, like the decision itself: an extra field, a missing one,
        /// an action or speed outside the list, or a number that is not finite.
        public init(from decoder: Decoder) throws {
            let any = try decoder.container(keyedBy: AnyKey.self)
            let known = Set(CodingKeys.allCases.map(\.rawValue))
            for key in any.allKeys where !known.contains(key.stringValue) {
                throw DuckDecision.WireError.unexpectedField(key.stringValue)
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            func text(_ k: CodingKeys) throws -> String {
                guard c.contains(k) else { throw DuckDecision.WireError.missingField(k.rawValue) }
                guard let s = try? c.decode(String.self, forKey: k) else { throw DuckDecision.WireError.wrongType(k.rawValue) }
                return s
            }
            let action = try text(.action)
            guard RobotPlanProposal.actions.contains(action) else { throw DuckDecision.WireError.wrongType("action") }
            let speed = try text(.speed)
            guard RobotPlanProposal.speeds.contains(speed) else { throw DuckDecision.WireError.wrongType("speed") }
            guard c.contains(.seconds) else { throw DuckDecision.WireError.missingField("seconds") }
            guard let s = try? c.decode(Double.self, forKey: .seconds), s.isFinite else {
                throw DuckDecision.WireError.wrongType("seconds")
            }
            self.init(action: action, speed: speed, seconds: s)
        }

        /// robotd's name for this beat's skill, or nil for a timed beat.
        public var skillName: String? {
            DuckIntentPlan.skills[action].flatMap { RobotPlan.robotdName[$0] }
        }

        /// A walk, turn or stop: a beat that runs for `seconds`.
        public var isTimed: Bool { DuckIntentPlan.goes[action] != nil }
    }

    public let beats: [Beat]

    public init(beats: [Beat]) { self.beats = beats }

    /// The most beats one plan decision runs (3.2). More are cut from the end.
    public static let maxBeats = 6
    /// The most seconds of timed beats one plan runs (3.2, "walk at most 5 s"): the same ceiling
    /// as one `.walk` decision. Counted over the whole plan, not per beat.
    public static let maxWalkSeconds = DuckDecision.maxSeconds
    /// Past this many beats the wire does not read it as a plan at all.
    public static let wireMaxBeats = 24

    /// The r001 actions a beat may name: the timed ones and the skills. Not `make_sound`, not
    /// `unsupported`.
    public static let actions: [String] = DuckIntentPlan.Vocabulary.actions.filter {
        DuckIntentPlan.goes[$0] != nil || DuckIntentPlan.skills[$0] != nil
    }
    public static let timedActions: [String] = actions.filter { DuckIntentPlan.goes[$0] != nil }
    public static let speeds: [String] = DuckIntentPlan.Vocabulary.speeds

    /// The beat labels for skills `AllowedDecisions` lets this run use, in r001's spelling.
    public static func skillActions(for allowed: AllowedDecisions) -> [String] {
        guard allowed.kinds.contains(.skill) else { return [] }
        return actions.filter { a in
            DuckIntentPlan.skills[a].flatMap { RobotPlan.robotdName[$0] }.map(allowed.skills.contains) ?? false
        }
    }

    public var skillNames: [String] { beats.compactMap(\.skillName) }

    /// This plan held to one decision's limits, and how much of it was cut (0 to 1).
    ///
    /// THE CUT ONLY EVER DOES LESS. Beats past `maxBeats` are dropped from the end. Timed beats
    /// run in order, each at least `DuckDrive.holdSeconds`, until `walkSeconds` is spent; the beat
    /// that overspends it is shortened, and the plan ends there. Nothing after a shortened or
    /// dropped beat runs, skills included, so a cut plan never skips ahead to a kick it was
    /// walking toward.
    public func clamped(walkSeconds: Double = RobotPlanProposal.maxWalkSeconds) -> (proposal: RobotPlanProposal, cut: Double) {
        let budget = min(max(walkSeconds, 0), Self.maxWalkSeconds)
        var kept: [Beat] = []
        var left = budget
        var askedSeconds = 0.0
        for beat in beats where beat.isTimed { askedSeconds += max(beat.seconds, DuckDrive.holdSeconds) }
        for beat in beats.prefix(Self.maxBeats) {
            guard beat.isTimed else { kept.append(beat); continue }
            let want = max(beat.seconds, DuckDrive.holdSeconds)
            if left < DuckDrive.holdSeconds - 1e-9 { break }
            let give = min(want, left)
            kept.append(Beat(action: beat.action, speed: beat.speed, seconds: give))
            left -= give
            if give < want { break }
        }
        let keptSeconds = kept.filter(\.isTimed).reduce(0) { $0 + $1.seconds }
        let beatCut = beats.isEmpty ? 0 : Double(beats.count - kept.count) / Double(beats.count)
        let timeCut = askedSeconds > 0 ? max(0, 1 - keptSeconds / askedSeconds) : 0
        return (RobotPlanProposal(beats: kept), max(beatCut, timeCut))
    }

    /// The person-editable plan this becomes, so `RobotPlan` and its refusals apply unchanged.
    /// Every node is marked unmeasured: a planner scores no labels.
    public func intentPlan(request: String) -> DuckIntentPlan {
        let nodes = beats.enumerated().map { i, beat -> DuckIntentPlan.Node in
            var labels = ["action": beat.action]
            if beat.isTimed { labels["speed"] = beat.speed; labels["head"] = "straight" }
            var node = DuckIntentPlan.Node(id: i, clause: DuckIntentPlan.Vocabulary.words(beat.action),
                                           proposed: labels, confidence: [:], measured: false)
            node.seconds = beat.seconds
            return node
        }
        return DuckIntentPlan(request: request, model: Self.model, nodes: nodes)
    }

    /// The `model` a planner's plan carries, so it is never read as a Duck Cards plan.
    public static let model = "planner"

    /// Clamp, then build the `RobotPlan`. Throws `RobotPlan.Refusal`, as any plan would.
    public func robotPlan(request: String, walkSeconds: Double = RobotPlanProposal.maxWalkSeconds) throws -> RobotPlan {
        try RobotPlan(clamped(walkSeconds: walkSeconds).proposal.intentPlan(request: request), measuredCards: false)
    }
}
