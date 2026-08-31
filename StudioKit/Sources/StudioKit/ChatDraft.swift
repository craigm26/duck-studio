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
        case motion, rule, retrieval, training, tweak

        /// The kind in the words a person uses, for the line that says how a
        /// sentence was read. "retrieval" is not a word anybody types.
        public var spoken: String {
            switch self {
            case .motion:    return "a motion"
            case .rule:      return "a rule"
            case .retrieval: return "fetching something"
            case .training:  return "a training brief"
            case .tweak:     return "an edit to a motion"
            }
        }
    }

    // MARK: - what to tell the model

    /// Instructions for editing a motion that already exists. Needs the
    /// motion, which the other kinds do not, so it has its own door.
    public static func tweakInstructions(for draft: IntentDraft) -> String {
        """
        You EDIT an existing motion for a 25 cm robot duck. You do not rewrite         it. Return only the changes asked for; everything you do not mention is         left exactly as it is.

        \(MotionTweak.describe(draft))

        \(MotionProposal.grounding())

        Each edit names a moment in seconds. To change a joint, give "at",         "joint" and "degrees". To add a keyframe give "at" and "action":"add";         to remove one, "action":"remove"; to move one, "at" and "to". To rename         the motion, "name".

        Answer with JSON and nothing else. No explanation, no markdown fence.
        Exactly this shape:
        {"summary":"what you changed","edits":[\
        {"at":0.5,"joint":"neck","degrees":30},\
        {"at":1.2,"action":"add"},\
        {"at":0.5,"to":0.8},\
        {"name":"A deeper bow"}]}
        """
    }

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
        case .tweak:
            // Editing needs the motion in front of it, which this door cannot
            // see. `tweakInstructions(for:)` is the one to call.
            return "Use tweakInstructions(for:) — editing a motion needs the motion."
        case .training:
            let rewards = TrainingRequest.vocabulary
                .sorted { $0.key < $1.key }
                .map { "\($0.key) — \($0.value)" }
                .joined(separator: "\n")
            let bases = TrainingRequest.Base.allCases
                .map { "\($0.rawValue) — \($0.summary); command \($0.command)" }
                .joined(separator: "\n")
            return """
            You turn one sentence into a request to TRAIN a new policy for a             25 cm robot duck. You are not training anything and neither is the             app — this is a specification somebody with a GPU will run.

            Fork one of these existing tasks, whichever is closest:
            \(bases)

            Choose reward functions ONLY from this list. Do not invent one; a             config naming a function that does not exist will not import:
            \(rewards)

            Give three to seven rewards. Include at least one that keeps the             duck upright, because a task rewarded only for its job learns to do             it while falling over. Episodes run 2 to 8 seconds. Weights are             usually 0.1 to 6.

            Put anything you are unsure about in openQuestions rather than             guessing at it.

            Answer with JSON and nothing else. No explanation, no markdown fence.
            Exactly this shape:
            {"name":"Short name","summary":"one sentence",\
            "base":"one of the filenames above","episodeSeconds":4.0,\
            "successCriterion":"how you would know it worked",\
            "rewards":[{"function":"one from the list","weight":2.0,"reason":"why"}],\
            "openQuestions":["what you are unsure of"]}
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

    /// A training request, as the model wrote it.
    ///
    /// THE MODEL PICKS FROM A LIST; THE CODE CHECKS THE LIST WAS OBEYED. A
    /// reward it invented is refused by `TrainingRequest.refusals`, and so is a
    /// request that asks for something the torque or the geometry forbids — a
    /// language model is a poor judge of whether a neck can hold two kilos.
    public static func training(fromJSON json: String,
                                prop: DuckScene.Prop? = nil) throws -> TrainingRequest {
        let top = try object(json)
        let baseName = (try? string(top, "base")) ?? TrainingRequest.Base.groundPick.rawValue
        let base = TrainingRequest.Base(rawValue: baseName)
            ?? TrainingRequest.Base.allCases.first { baseName.contains($0.rawValue) }
            ?? .groundPick
        let rewards = (top["rewards"] as? [[String: Any]] ?? []).compactMap {
            reward -> TrainingRequest.Reward? in
            guard let function = reward["function"] as? String else { return nil }
            return TrainingRequest.Reward(
                function: function.trimmingCharacters(in: .whitespaces),
                weight: number(reward["weight"]) ?? 1,
                reason: reward["reason"] as? String ?? "no reason given")
        }
        return TrainingRequest(
            name: try string(top, "name"),
            summary: (try? string(top, "summary")) ?? "",
            base: base,
            episodeSeconds: number(top["episodeSeconds"]) ?? 4,
            rewards: rewards,
            prop: prop,
            successCriterion: (try? string(top, "successCriterion"))
                ?? "not stated, which is itself worth fixing",
            openQuestions: (top["openQuestions"] as? [String]) ?? [])
    }

    /// Read the model's edits. Anything it returns that is not one of the
    /// shapes above is DROPPED rather than guessed at — a half-understood edit
    /// applied to somebody's motion is worse than one that did not happen.
    public static func tweak(fromJSON json: String) throws -> MotionTweak {
        let top = try object(json)
        let raw = top["edits"] as? [[String: Any]] ?? []
        let edits: [MotionTweak.Edit] = raw.compactMap { entry in
            if let name = entry["name"] as? String { return .rename(name) }
            guard let at = number(entry["at"]) else { return nil }
            if let action = (entry["action"] as? String)?.lowercased() {
                if action.hasPrefix("add") { return .addKey(at: at) }
                if action.hasPrefix("remove") || action.hasPrefix("delete") {
                    return .removeKey(at: at)
                }
            }
            if let to = number(entry["to"]) { return .moveKey(at: at, to: to) }
            if let joint = entry["joint"] as? String, let degrees = number(entry["degrees"]) {
                return .joint(at: at, word: joint, degrees: degrees)
            }
            return nil
        }
        return MotionTweak(summary: (try? string(top, "summary")) ?? "", edits: edits)
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
