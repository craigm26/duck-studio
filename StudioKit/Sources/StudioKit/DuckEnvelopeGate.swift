import Foundation

/// The envelope every brain's motion goes through (docs/plans/brains-layer.md, 6.2).
///
/// It is deterministic arithmetic on one row at a time, and it is the same for every brain:
/// the phone driver, Dream-1, a hosted planner. A model is one input to it and never changes it.
///
/// BIND BEFORE ACT. As in `be_yam_gate`, `act` and `check` throw until `bind` has run, so no row
/// can reach a motor without a provider, a model version and a venue on record.
///
/// THE CHECKS RUN IN THE PLAN'S ORDER AND EACH ONE HAS A FIXED VERDICT. For a twist row: 1 finite
/// numbers, 2 stick envelope, 3 rate, 4 staleness, 5 keep-in, 6 tilt, 7 run cap and authority,
/// 11 proximity (always reported unmet). For a decision: 7 run limits, 8 allowlist, 10
/// confirmation. Rule 9 (head) is later: there is no head output from a planner yet. The row's
/// verdict is the most severe one any rule reached, and the rule named is the first to reach it.
///
/// NOT WIRED IN YET. This build adds the gate and its golden cases only. Binding it inside
/// `DreamPilot` and the runners is a later build.
///
/// The copy calls it "the limits" or "the envelope". It makes no claim that any brain is safe.
public struct DuckEnvelopeGate: Sendable {

    // MARK: limits

    /// Every number the gate checks against.
    ///
    /// SOURCED OR PLACEHOLDER, AND EACH ONE SAYS WHICH. The stick envelope comes from
    /// `DuckDrive` and the run caps from `ControlArbiter.Caps`. Everything in `placeholders` is
    /// a starting number nobody has measured on a duck; build 94's plan replaces them or leaves
    /// them labelled.
    public struct Limits: Equatable, Sendable, Codable {
        public let id: String
        public let maxForward: Double
        public let maxBackward: Double
        public let maxSideways: Double
        public let maxTurn: Double
        /// Most change in m/s per row, on x and on y, when speeding up.
        public let maxDeltaLinear: Double
        /// Most change in rad/s per row when speeding up.
        public let maxDeltaTurn: Double
        public let maxStateAgeMs: Double
        /// Odometry stale this long is a cut.
        public let staleCutSeconds: Double
        public let maxObservationAgeS: Double
        /// Half the side of the square keep-in area, centred on the odometry origin.
        public let matHalfM: Double
        /// How long the duck takes to stop. The keep-in check sweeps the arc over this time.
        public let stopSeconds: Double
        public let arcSamples: Int
        public let maxTiltDeg: Double
        public let runCapPracticeS: Double
        public let runCapRealS: Double
        /// Per-run decision limits (3.3).
        public let runWallClockS: Double
        public let maxDecisions: Int
        public let maxHostedCalls: Int
        public let maxIdenticalInARow: Int
        public let skillsPerMinute: Int
        /// A confidence under this asks for a Go.
        public let confidenceFloor: Double
        /// A decision clamped by more than this share asks for a Go.
        public let clampShareForGo: Double
        /// The names of the fields above that are placeholders.
        public let placeholders: [String]

        public func runCap(_ venue: BrainVenue) -> Double {
            venue == .real ? runCapRealS : runCapPracticeS
        }

        /// The first envelope. Shared with the golden cases by `id`.
        public static let placeholderV1 = Limits(
            id: "microduck-placeholder-v1",
            maxForward: DuckDrive.maxForward, maxBackward: DuckDrive.maxBackward,
            maxSideways: DuckDrive.maxSideways, maxTurn: DuckDrive.maxTurn,
            maxDeltaLinear: 0.1, maxDeltaTurn: 0.35,
            maxStateAgeMs: 100, staleCutSeconds: 1.0, maxObservationAgeS: 1.0,
            matHalfM: 1.0, stopSeconds: 0.5, arcSamples: 10, maxTiltDeg: 30,
            runCapPracticeS: ControlArbiter.Caps.practiceDuckDefault,
            runCapRealS: ControlArbiter.Caps.realDuckDefault,
            runWallClockS: 180, maxDecisions: 20, maxHostedCalls: 20, maxIdenticalInARow: 3,
            skillsPerMinute: 4, confidenceFloor: 0.6, clampShareForGo: 0.2,
            placeholders: ["maxDeltaLinear", "maxDeltaTurn", "maxStateAgeMs", "staleCutSeconds",
                           "maxObservationAgeS", "matHalfM", "stopSeconds", "maxTiltDeg",
                           "skillsPerMinute", "confidenceFloor"])
    }

    // MARK: rules and verdicts

    /// The plan's rule numbers, as ids that read in a log.
    public enum Rule: String, Equatable, Hashable, Sendable, Codable, CaseIterable {
        case finite, stick, rate, stale
        case keepIn = "keep-in"
        case tilt, run, allowlist, confirm, proximity

        public var number: Int {
            switch self {
            case .finite: return 1
            case .stick: return 2
            case .rate: return 3
            case .stale: return 4
            case .keepIn: return 5
            case .tilt: return 6
            case .run: return 7
            case .allowlist: return 8
            case .confirm: return 10
            case .proximity: return 11
            }
        }
    }

    /// The fixed verdicts, least to most severe.
    public enum Verdict: String, Equatable, Hashable, Sendable, Codable, CaseIterable, Comparable {
        case pass, clamped, slowed, held, cut, invalid

        public static func < (a: Verdict, b: Verdict) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }

        /// Cut and invalid both end the run through the stop path.
        public var stopsTheRun: Bool { self == .cut || self == .invalid }
    }

    /// Rule 11. There is no obstacle sensing, so proximity is never passed.
    public enum Proximity: String, Equatable, Sendable, Codable { case unmet }

    // MARK: binding

    public struct Binding: Equatable, Sendable {
        public let providerId: String
        public let modelVersion: String
        public let venue: BrainVenue
        public let mode: BrainMode
        /// Runs somewhere other than this phone.
        public let remote: Bool
        public let allowed: AllowedDecisions

        public init(providerId: String, modelVersion: String, venue: BrainVenue, mode: BrainMode,
                    remote: Bool, allowed: AllowedDecisions) {
            self.providerId = KeyScrub.scrub(providerId)
            self.modelVersion = KeyScrub.scrub(modelVersion)
            self.venue = venue
            self.mode = mode
            self.remote = remote
            self.allowed = allowed
        }

        public init(_ brain: some BrainCard, venue: BrainVenue, mode: BrainMode, allowed: AllowedDecisions) {
            self.init(providerId: brain.id, modelVersion: brain.modelVersion, venue: venue, mode: mode,
                      remote: brain.runsOn != .thisPhone, allowed: allowed)
        }
    }

    public enum GateError: Error, Equatable, Sendable {
        /// `act` or `check` before `bind`.
        case notBound
    }

    // MARK: one twist row

    /// One row a brain wants to send, with what the duck reported when it was made.
    public struct Row: Equatable, Sendable, Codable {
        /// Seconds since the run started.
        public let t: Double
        public let twist: GateTwist
        /// Nil when the duck reports no odometry.
        public let odomAgeMs: Double?
        /// `now - frameTimestamp`. Nil when the row was not made from a picture.
        public let observationAgeS: Double?
        /// The source answered after its deadline.
        public let chunkLate: Bool
        /// Odometry pose (x m, y m, yaw rad). Nil when there is none.
        public let pose: Pose?
        public let tiltDeg: Double?
        public let phoneUnlocked: Bool
        public let phase: String

        public init(t: Double, twist: GateTwist, odomAgeMs: Double?, observationAgeS: Double? = nil,
                    chunkLate: Bool = false, pose: Pose?, tiltDeg: Double? = nil, phoneUnlocked: Bool = true,
                    phase: String = "act") {
            self.t = t
            self.twist = twist
            self.odomAgeMs = odomAgeMs
            self.observationAgeS = observationAgeS
            self.chunkLate = chunkLate
            self.pose = pose
            self.tiltDeg = tiltDeg
            self.phoneUnlocked = phoneUnlocked
            self.phase = phase
        }
    }

    public struct Pose: Equatable, Sendable, Codable {
        public let x: Double, y: Double, yaw: Double
        public init(x: Double, y: Double, yaw: Double) { self.x = x; self.y = y; self.yaw = yaw }
    }

    public struct Result: Equatable, Sendable {
        public let sent: GateTwist
        public let verdict: Verdict
        /// Nil on a pass.
        public let rule: Rule?
        /// Send `robot.stop` through the stop path.
        public let stopPath: Bool
        public let proximity: Proximity
        public let keepInMarginM: Double?
    }

    // MARK: state

    public let limits: Limits
    public private(set) var binding: Binding?
    public private(set) var stats = GateStats()
    public private(set) var events: [GateEvent] = []

    private var lastSent = GateTwist.still
    private var staleSince: Double?
    private var cutBy: Rule?

    // Decision state.
    private var seenKinds: Set<DuckDecision.Kind> = []
    private var seenSkills: Set<String> = []
    private var seenSources: Set<String> = []
    private var decisions = 0
    private var hostedCalls = 0
    private var recent: [DuckDecision] = []
    private var skillTimes: [Double] = []
    private var askOpen = false

    public init(limits: Limits = .placeholderV1) {
        self.limits = limits
    }

    /// Bind the gate to one run. A new binding starts a fresh run.
    public mutating func bind(_ binding: Binding) {
        self = DuckEnvelopeGate(limits: limits)
        self.binding = binding
    }

    /// Check one row and return what may be sent. Throws `GateError.notBound` before `bind`.
    public mutating func act(_ row: Row) throws -> Result {
        guard let binding else { throw GateError.notBound }
        let result = evaluate(row, binding)
        events.append(GateEvent(row: row, binding: binding, result: result))
        return result
    }

    private mutating func evaluate(_ row: Row, _ binding: Binding) -> Result {
        let still = GateTwist.still
        var margin: Double?
        if let p = row.pose, p.x.isFinite, p.y.isFinite {
            margin = min(limits.matHalfM - abs(p.x), limits.matHalfM - abs(p.y))
        }

        // After a cut or an invalid row, nothing moves until the gate is bound again. These
        // rows are logged but not counted a second time.
        if let cutBy {
            return Result(sent: still, verdict: .cut, rule: cutBy, stopPath: true, proximity: .unmet,
                          keepInMarginM: margin)
        }

        // 1. Finite numbers.
        guard row.twist.isFinite else {
            return stop(.invalid, .finite, margin)
        }

        var verdict = Verdict.pass
        var rule: Rule?
        func reach(_ v: Verdict, _ r: Rule) {
            if v > verdict { verdict = v; rule = r }
        }
        var twist = row.twist

        // 2. Stick envelope.
        let clamped = GateTwist(vx: min(max(twist.vx, -limits.maxBackward), limits.maxForward),
                                vy: min(max(twist.vy, -limits.maxSideways), limits.maxSideways),
                                vyaw: min(max(twist.vyaw, -limits.maxTurn), limits.maxTurn))
        if clamped != twist { reach(.clamped, .stick); twist = clamped }

        // 3. Rate. Speeding up is limited per row; slowing down toward zero is not.
        let eased = GateTwist(vx: Self.ease(lastSent.vx, twist.vx, limits.maxDeltaLinear),
                              vy: Self.ease(lastSent.vy, twist.vy, limits.maxDeltaLinear),
                              vyaw: Self.ease(lastSent.vyaw, twist.vyaw, limits.maxDeltaTurn))
        if eased != twist { reach(.slowed, .rate); twist = eased }

        // 4. Staleness. Missing odometry counts as stale: keep-in cannot be checked without it.
        let odomStale = row.odomAgeMs.map { !$0.isFinite || $0 > limits.maxStateAgeMs } ?? true
        let noPose = row.pose.map { !($0.x.isFinite && $0.y.isFinite && $0.yaw.isFinite) } ?? true
        if odomStale || noPose {
            let since = staleSince ?? row.t
            staleSince = since
            if row.t - since >= limits.staleCutSeconds - 1e-9 {
                reach(.cut, .stale)
            } else {
                reach(.held, .stale)
            }
            twist = still
        } else {
            staleSince = nil
        }
        if row.chunkLate { reach(.held, .stale); twist = still }
        if let age = row.observationAgeS, !age.isFinite || age > limits.maxObservationAgeS {
            reach(.held, .stale); twist = still
        }

        // 5. Keep-in, on odometry, sweeping the arc the duck would follow while it stops.
        if let pose = row.pose, !noPose {
            if abs(pose.x) > limits.matHalfM || abs(pose.y) > limits.matHalfM {
                reach(.cut, .keepIn)
                twist = still
            } else if twist != still {
                for share in [1.0, 0.5, 0.25, 0.0] {
                    let tried = GateTwist(vx: twist.vx * share, vy: twist.vy * share, vyaw: twist.vyaw)
                    if staysIn(pose, tried) {
                        if share < 1 { reach(.slowed, .keepIn); twist = tried }
                        break
                    }
                }
            }
        }

        // 6. Tilt or fall.
        if let tilt = row.tiltDeg, !tilt.isFinite || abs(tilt) > limits.maxTiltDeg {
            reach(.cut, .tilt)
        }

        // 7. Run cap and authority.
        if row.t > limits.runCap(binding.venue) { reach(.cut, .run) }
        if !row.phoneUnlocked { reach(.held, .run); twist = still }

        if verdict.stopsTheRun { return stop(verdict, rule ?? .run, margin) }
        lastSent = twist
        if let rule { stats.count(rule) }
        return Result(sent: twist, verdict: verdict, rule: rule, stopPath: false, proximity: .unmet,
                      keepInMarginM: margin)
    }

    private mutating func stop(_ verdict: Verdict, _ rule: Rule, _ margin: Double?) -> Result {
        cutBy = rule
        lastSent = .still
        stats.count(rule)
        return Result(sent: .still, verdict: verdict, rule: rule, stopPath: true, proximity: .unmet,
                      keepInMarginM: margin)
    }

    /// One axis of the rate rule.
    static func ease(_ last: Double, _ want: Double, _ step: Double) -> Double {
        if want == 0 { return 0 }
        let sameSign = (want > 0) == (last > 0) && last != 0
        if sameSign && abs(want) <= abs(last) { return want }
        let base = sameSign ? last : 0
        let change = want - base
        if abs(change) <= step + 1e-9 { return want }
        return base + (change > 0 ? step : -step)
    }

    /// Whether the duck stays on the mat for `stopSeconds` at this twist, checked at
    /// `arcSamples` points along the arc it turns through, not along a straight line.
    func staysIn(_ pose: Pose, _ twist: GateTwist) -> Bool {
        let n = max(1, limits.arcSamples)
        for k in 1...n {
            let tau = limits.stopSeconds * Double(k) / Double(n)
            let w = twist.vyaw
            let bx: Double, by: Double
            if abs(w) < 1e-9 {
                bx = twist.vx * tau
                by = twist.vy * tau
            } else {
                let s = sin(w * tau), c = cos(w * tau)
                bx = (twist.vx * s + twist.vy * (c - 1)) / w
                by = (twist.vx * (1 - c) + twist.vy * s) / w
            }
            let x = pose.x + bx * cos(pose.yaw) - by * sin(pose.yaw)
            let y = pose.y + bx * sin(pose.yaw) + by * cos(pose.yaw)
            if abs(x) > limits.matHalfM + 1e-9 || abs(y) > limits.matHalfM + 1e-9 { return false }
        }
        return true
    }

    // MARK: one decision

    /// Why a decision waits for a person.
    public enum ConfirmReason: Equatable, Hashable, Sendable {
        case tellCountdown
        case newKind(DuckDecision.Kind)
        case newSkill(String)
        case newSource(String)
        case lowConfidence
        case bigClamp
    }

    public struct DecisionCheck: Equatable, Sendable {
        /// The decision as it may run, clamped to one decision's limits.
        public let decision: DuckDecision
        public let verdict: Verdict
        public let rule: Rule?
        /// Non-empty when the run pauses on a Go/Cancel card (rule 10).
        public let confirmations: [ConfirmReason]
        public let stopPath: Bool
    }

    /// Check one decision before anything runs it. `t` is seconds since the run started.
    ///
    /// A decision that needs a Go comes back `held` by `confirm`, and is not counted against the
    /// run until `confirm(_:at:)` is called after the person taps Go.
    public mutating func check(_ decided: Decided, at t: Double, phoneUnlocked: Bool = true) throws -> DecisionCheck {
        guard let binding else { throw GateError.notBound }
        let result = evaluate(decided, t, phoneUnlocked, confirmed: false, binding)
        events.append(GateEvent(decided: decided, at: t, binding: binding, check: result))
        return result
    }

    /// The person tapped Go on a decision that was held for confirmation.
    public mutating func confirm(_ decided: Decided, at t: Double, phoneUnlocked: Bool = true) throws -> DecisionCheck {
        guard let binding else { throw GateError.notBound }
        let result = evaluate(decided, t, phoneUnlocked, confirmed: true, binding)
        events.append(GateEvent(decided: decided, at: t, binding: binding, check: result))
        return result
    }

    /// The open `.ask` was answered.
    public mutating func answered() { askOpen = false }

    /// The reasons this decision needs a Go. Confidence can only add to them: the set without a
    /// confidence is always a subset of the set with one.
    public func confirmations(for decided: Decided) -> [ConfirmReason] {
        let d = decided.decision
        guard let binding, !d.kind.onlyStops, d.kind != .ask else { return [] }
        var reasons: [ConfirmReason] = []
        if binding.mode == .tell { reasons.append(.tellCountdown) }
        if !seenKinds.contains(d.kind) { reasons.append(.newKind(d.kind)) }
        var asked = Set<String>()
        for n in d.skillNames where !seenSkills.contains(n) && asked.insert(n).inserted { reasons.append(.newSkill(n)) }
        if !seenSources.contains(decided.provider.id) { reasons.append(.newSource(decided.provider.id)) }
        // The action source a `.drive` hands the duck to is a new source too (rule 10).
        if case .drive(let source, _, _) = d, !seenSources.contains(source.rawValue) {
            reasons.append(.newSource(source.rawValue))
        }
        if d.clamped().cut > limits.clampShareForGo { reasons.append(.bigClamp) }
        // The one place confidence is read. It appends; nothing above depends on it.
        if let c = decided.confidence, !(c.isFinite && c >= limits.confidenceFloor && c <= 1) {
            reasons.append(.lowConfidence)
        }
        return reasons
    }

    private mutating func evaluate(_ decided: Decided, _ t: Double, _ unlocked: Bool,
                                   confirmed: Bool, _ binding: Binding) -> DecisionCheck {
        let d = decided.decision
        // A stop or done is never refused, never waits and never counts.
        if d.kind.onlyStops {
            return DecisionCheck(decision: d, verdict: .pass, rule: nil, confirmations: [], stopPath: true)
        }
        if cutBy != nil {
            return DecisionCheck(decision: d, verdict: .cut, rule: cutBy, confirmations: [], stopPath: true)
        }
        func held(_ rule: Rule, _ reasons: [ConfirmReason] = []) -> DecisionCheck {
            if rule != .confirm { stats.count(rule) }
            return DecisionCheck(decision: d, verdict: .held, rule: rule, confirmations: reasons, stopPath: false)
        }
        func cut(_ rule: Rule) -> DecisionCheck {
            cutBy = rule
            stats.count(rule)
            return DecisionCheck(decision: d, verdict: .cut, rule: rule, confirmations: [], stopPath: true)
        }

        // 1. Finite numbers.
        guard d.isFinite else {
            cutBy = .finite
            stats.count(.finite)
            return DecisionCheck(decision: d, verdict: .invalid, rule: .finite, confirmations: [], stopPath: true)
        }

        // 7. Run limits and authority.
        if t > limits.runWallClockS || t > limits.runCap(binding.venue) { return cut(.run) }
        if decisions >= limits.maxDecisions { return cut(.run) }
        if binding.remote && hostedCalls >= limits.maxHostedCalls { return cut(.run) }
        if recent.count >= limits.maxIdenticalInARow,
           recent.suffix(limits.maxIdenticalInARow).allSatisfy({ $0 == d }) { return cut(.run) }
        if !unlocked && d.kind != .sound && d.kind != .ask { return held(.run) }
        if d.kind == .ask && askOpen { return held(.run) }

        // 8. Allowlist, per venue and brain kind, and skills per minute.
        if case .failure = binding.allowed.admit(d) { return held(.allowlist) }
        // A plan's skill beats are skills: the same remote rule and the same per-minute cap.
        let skills = d.skillNames
        if !skills.isEmpty {
            if binding.remote && binding.venue == .real { return held(.allowlist) }
            let lastMinute = skillTimes.filter { t - $0 < 60 }
            if lastMinute.count + skills.count > limits.skillsPerMinute { return held(.allowlist) }
        }

        // 10. Confirmation for anything new.
        if !confirmed {
            let reasons = confirmations(for: decided)
            if !reasons.isEmpty { return held(.confirm, reasons) }
        }

        // It runs.
        let (clamped, share) = d.clamped()
        seenKinds.insert(d.kind)
        for n in skills { seenSkills.insert(n); skillTimes.append(t) }
        seenSources.insert(decided.provider.id)
        if case .drive(let source, _, _) = d { seenSources.insert(source.rawValue) }
        decisions += 1
        if binding.remote { hostedCalls += 1 }
        recent.append(d)
        if d.kind == .ask { askOpen = true }
        if share > 0 {
            // A walk or turn is cut to the stick envelope; a drive's seconds or a plan's beats and
            // walk time are cut to the run's own limits (6.5, "Model-supplied durations").
            let rule: Rule = (d.kind == .drive || d.kind == .plan) ? .run : .stick
            stats.count(rule)
            return DecisionCheck(decision: clamped, verdict: .clamped, rule: rule, confirmations: [],
                                 stopPath: false)
        }
        return DecisionCheck(decision: d, verdict: .pass, rule: nil, confirmations: [], stopPath: false)
    }
}

/// A twist as the gate logs it. Codable, where `DuckDrive.Twist` is not.
public struct GateTwist: Equatable, Hashable, Sendable, Codable {
    public let vx: Double, vy: Double, vyaw: Double

    public init(vx: Double, vy: Double, vyaw: Double) { self.vx = vx; self.vy = vy; self.vyaw = vyaw }
    public init(_ t: DuckDrive.Twist) { self.init(vx: t.vx, vy: t.vy, vyaw: t.vyaw) }

    public static let still = GateTwist(vx: 0, vy: 0, vyaw: 0)
    public var isFinite: Bool { vx.isFinite && vy.isFinite && vyaw.isFinite }
    public var drive: DuckDrive.Twist { DuckDrive.Twist(vx: vx, vy: vy, vyaw: vyaw) }
}
