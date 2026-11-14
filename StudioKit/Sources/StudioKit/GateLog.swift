import Foundation

/// One line of the gate's log: a twist row or a decision, what was asked, what was sent, and why.
///
/// NO KEY EVER REACHES ONE. Every string is passed through `KeyScrub` when the event is made and
/// again when it is exported, so a key pasted into a model-version field still leaves as
/// `DuckDream.hint`'s "…abcd".
public struct GateEvent: Equatable, Sendable, Codable {
    public let t: Double
    public let providerId: String
    public let modelVersion: String
    public let phase: String
    /// The decision kind, for a decision event.
    public let decision: String?
    public let requested: GateTwist?
    public let sent: GateTwist?
    public let verdict: DuckEnvelopeGate.Verdict
    public let rule: DuckEnvelopeGate.Rule?
    public let odomAgeMs: Double?
    public let observationAgeS: Double?
    public let keepInMarginM: Double?
    public let proximity: DuckEnvelopeGate.Proximity
    public let note: String?

    enum CodingKeys: String, CodingKey {
        case t, phase, decision, requested, sent, verdict, rule, proximity, note
        case providerId = "provider_id", modelVersion = "model_version", odomAgeMs = "odom_age_ms"
        case observationAgeS = "observation_age_s", keepInMarginM = "keep_in_margin_m"
    }

    init(row: DuckEnvelopeGate.Row, binding: DuckEnvelopeGate.Binding, result: DuckEnvelopeGate.Result) {
        t = row.t
        providerId = KeyScrub.scrub(binding.providerId)
        modelVersion = KeyScrub.scrub(binding.modelVersion)
        phase = KeyScrub.scrub(row.phase)
        decision = nil
        requested = row.twist.isFinite ? row.twist : nil
        sent = result.sent
        verdict = result.verdict
        rule = result.rule
        odomAgeMs = row.odomAgeMs.flatMap { $0.isFinite ? $0 : nil }
        observationAgeS = row.observationAgeS.flatMap { $0.isFinite ? $0 : nil }
        keepInMarginM = result.keepInMarginM
        proximity = result.proximity
        note = nil
    }

    init(decided: Decided, at t: Double, binding: DuckEnvelopeGate.Binding,
         check: DuckEnvelopeGate.DecisionCheck) {
        self.t = t
        providerId = KeyScrub.scrub(decided.provider.id)
        modelVersion = KeyScrub.scrub(decided.provider.modelVersion)
        phase = "decide"
        decision = check.decision.kind.rawValue
        requested = nil
        sent = nil
        verdict = check.verdict
        rule = check.rule
        odomAgeMs = nil
        observationAgeS = nil
        keepInMarginM = nil
        proximity = .unmet
        note = KeyScrub.scrub(decided.why)
    }

    /// Every string in the event, for the key test.
    var strings: [String] { [providerId, modelVersion, phase, decision ?? "", note ?? ""] }
}

/// Interventions per rule, and the run summary chip.
public struct GateStats: Equatable, Sendable, Codable {
    public private(set) var counts: [DuckEnvelopeGate.Rule: Int] = [:]

    public init() {}

    mutating func count(_ rule: DuckEnvelopeGate.Rule) {
        guard rule != .confirm, rule != .proximity else { return }
        counts[rule, default: 0] += 1
    }

    public var total: Int { counts.values.reduce(0, +) }

    /// "Gate stepped in 14 times (keep-in 9, rate 5)". Rules by count, most first, then by rule
    /// number.
    public var chip: String {
        guard total > 0 else { return GateWords.didNotStepIn }
        let parts = counts.filter { $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.number < $1.key.number }
            .map { "\(GateWords.name($0.key)) \($0.value)" }
        let times = total == 1 ? "once" : "\(total) times"
        return "Gate stepped in \(times) (\(parts.joined(separator: ", ")))"
    }

    /// The run summary's lines: the chip, then what the gate cannot do.
    public func summary(venue: BrainVenue, limits: DuckEnvelopeGate.Limits) -> [String] {
        var lines = [chip, GateWords.noObstacleSensing]
        if venue == .real { lines.append(GateWords.keepInApproximate) }
        if !limits.placeholders.isEmpty { lines.append(GateWords.placeholders) }
        return lines
    }

    // Codable through rule ids, so the export reads {"keep-in": 9}.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: Int].self)
        for (k, v) in raw { if let r = DuckEnvelopeGate.Rule(rawValue: k) { counts[r] = v } }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) }))
    }
}

/// The gate's sentences. It is "the limits" or "the envelope", never "safety".
public enum GateWords {
    public static func name(_ rule: DuckEnvelopeGate.Rule) -> String {
        switch rule {
        case .finite: return "bad numbers"
        case .stick: return "speed"
        case .rate: return "rate"
        case .stale: return "stale data"
        case .keepIn: return "keep-in"
        case .tilt: return "tilt"
        case .run: return "run limits"
        case .allowlist: return "not allowed"
        case .confirm: return "asked first"
        case .proximity: return "obstacles"
        }
    }

    public static let didNotStepIn = "Gate did not step in."
    public static let noObstacleSensing = "No obstacle sensing."
    public static let keepInApproximate =
        "Keep-in is approximate on a real duck. Its odometry drift is not measured yet."
    public static let placeholders =
        "Some of the limits are placeholders until they are measured on a duck."
    public static let whatItIs =
        "The envelope holds every brain to the same limits: speed, rate, keep-in, tilt and time."

    public static var all: [String] {
        DuckEnvelopeGate.Rule.allCases.map(name)
            + [didNotStepIn, noObstacleSensing, keepInApproximate, placeholders, whatItIs]
    }
}

/// Masks anything shaped like an API key with `DuckDream.hint`, the masking the Dream key
/// already uses ("…abcd").
///
/// THE PATTERNS ARE VENDOR PREFIXES, NOT "ANY LONG STRING". A checkpoint hash is a long hex
/// string and must stay readable, because it pins the evidence row.
public enum KeyScrub {
    /// Each pattern is a regular expression for one kind of key.
    public static let patterns: [String] = [
        #"dl_(live|test)_[A-Za-z0-9]{8,}"#,          // Dream Labs
        #"sk-ant-[A-Za-z0-9_\-]{16,}"#,              // Anthropic
        #"sk-(proj-)?[A-Za-z0-9_\-]{16,}"#,          // OpenAI
        #"AIza[0-9A-Za-z_\-]{30,}"#,                 // Google
        #"hf_[A-Za-z0-9]{20,}"#,                     // Hugging Face
        #"(?i)bearer\s+[A-Za-z0-9._\-]{8,}"#,        // any bearer header
    ]

    private static let regexes: [NSRegularExpression] =
        patterns.compactMap { try? NSRegularExpression(pattern: $0) }

    /// Whether `text` holds anything shaped like a key.
    public static func containsKey(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return regexes.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    public static func scrub(_ text: String) -> String {
        var out = text
        for regex in regexes {
            while let m = regex.firstMatch(in: out, range: NSRange(out.startIndex..., in: out)),
                  let r = Range(m.range, in: out) {
                out.replaceSubrange(r, with: DuckDream.hint(String(out[r])))
            }
        }
        return out
    }
}

/// The gate log as a file for Studio > Measure: one JSON object per line.
public enum GateExport {
    public static func jsonLines(_ events: [GateEvent]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try events.map { event in
            KeyScrub.scrub(String(decoding: try encoder.encode(event), as: UTF8.self))
        }.joined(separator: "\n")
    }
}
