import Foundation

/// One sentence in, one checked proposal out — whichever model wrote it.
///
/// THE INSTRUCTIONS CARRY THE SHAPE, because a local model has no `@Generable`
/// to be handed. Apple's model is given a Swift type and returns that type; a
/// Gemma on a Raspberry Pi is given a paragraph and returns whatever it likes,
/// so the paragraph has to say exactly what JSON is wanted. What both paths
/// share is the landing: a `MotionProposal` or an `AutomationProposal` that
/// still has to resolve against the real joints, travels and intents.
public enum ChatDraft {

    /// What kind of thing the sentence is asking for.
    public enum Kind: String, Sendable, CaseIterable {
        case motion, rule, retrieval
    }

    // MARK: - what to tell the model

    public static func instructions(for kind: Kind, knownIntents: Set<String> = []) -> String {
        switch kind {
        case .motion:
            return """
            \(MotionProposal.grounding())

            Answer with JSON and nothing else. No explanation, no markdown fence.
            Exactly this shape:
            {"name":"Short name","keys":[{"atSeconds":0.0,"mouthOpen":0.0,\
            "moves":[{"joint":"neck","degrees":10}]}]}
            """
        case .rule:
            return """
            \(AutomationProposal.grounding(knownIntents: knownIntents))

            Answer with JSON and nothing else. No explanation, no markdown fence.
            Exactly this shape:
            {"name":"Short name","predicate":"one of the listed words","value":0.0,\
            "intent":"one of the listed intents"}
            """
        case .retrieval:
            return """
            You read one sentence about fetching an object for a 25 cm duck robot \
            and report the object's properties. You do not decide whether the robot \
            can do it — that is checked afterwards against measurements.

            Estimate from everyday knowledge when the sentence does not say: a pencil \
            is about 6 g and 7 mm thick, a wooden dowel about 25 g and 20 mm.

            Answer with JSON and nothing else. No explanation, no markdown fence.
            Exactly this shape:
            {"object":"what it is","grams":6.0,"thicknessMillimetres":7.0,\
            "metresAway":1.0}
            """
        }
    }

    // MARK: - reading it back

    public enum DraftError: Error, Equatable, Sendable {
        case missing(String)
        case wrongType(String)

        public var message: String {
            switch self {
            case .missing(let key): return "The model left out \(key)."
            case .wrongType(let key): return "\(key) came back as the wrong kind of value."
            }
        }
    }

    public static func motion(fromJSON json: String) throws -> MotionProposal {
        let top = try object(json)
        let name = try string(top, "name")
        guard let rawKeys = top["keys"] as? [[String: Any]] else {
            throw DraftError.missing("keys")
        }
        let keys: [MotionProposal.Key] = try rawKeys.map { key in
            let moves = (key["moves"] as? [[String: Any]] ?? []).compactMap { move -> MotionProposal.Move? in
                guard let joint = move["joint"] as? String,
                      let degrees = number(move["degrees"]) else { return nil }
                return MotionProposal.Move(joint: joint, degrees: degrees)
            }
            guard let at = number(key["atSeconds"]) else { throw DraftError.missing("atSeconds") }
            return MotionProposal.Key(atSeconds: at, moves: moves,
                                      mouthOpen: number(key["mouthOpen"]) ?? 0)
        }
        return MotionProposal(name: name, keys: keys)
    }

    public static func rule(fromJSON json: String) throws -> AutomationProposal {
        let top = try object(json)
        return AutomationProposal(name: try string(top, "name"),
                                  predicate: try string(top, "predicate"),
                                  value: number(top["value"]) ?? 0,
                                  intent: try string(top, "intent"))
    }

    /// A fetch request, as the model understood it.
    ///
    /// THE MODEL ESTIMATES THE OBJECT; IT DOES NOT JUDGE THE ROBOT. Whether a
    /// duck can pick the thing up is decided by `Retrieval.plan`, against
    /// measurements, in code that runs offline. Letting a language model answer
    /// "can it?" would be letting it guess at the one part of this that is
    /// actually known.
    public static func stick(fromJSON json: String) throws -> (object: String?, stick: Retrieval.Stick) {
        let top = try object(json)
        guard let grams = number(top["grams"]) else { throw DraftError.missing("grams") }
        guard let mm = number(top["thicknessMillimetres"]) else {
            throw DraftError.missing("thicknessMillimetres")
        }
        return (top["object"] as? String,
                Retrieval.Stick(grams: grams,
                                thicknessMillimetres: mm,
                                metresAway: number(top["metresAway"]) ?? 1.0))
    }

    // MARK: - small helpers

    private static func object(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DraftError.wrongType("the reply")
        }
        return top
    }

    private static func string(_ top: [String: Any], _ key: String) throws -> String {
        guard let value = top[key] else { throw DraftError.missing(key) }
        guard let text = value as? String else { throw DraftError.wrongType(key) }
        return text
    }

    /// Numbers arrive as numbers, or as strings, because small models quote
    /// them about a third of the time. Refusing a quoted 10 would be refusing a
    /// correct answer on a technicality.
    private static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let text = value as? String { return Double(text.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}
