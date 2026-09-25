import Foundation

/// A language model that writes the whole plan — order, repeats, durations —
/// where the router labels one clause at a time.
///
/// WHY A SECOND WAY TO PLAN. duckbatch's p002 put the same thirty requests to
/// both: GLiNER2.5-Decide behind `HTTPIntentRouter` got 17 sequences right,
/// Gemma 4 E4B got all 30. The router has no word for "three times" or "for
/// five seconds", and its clause splitter only splits on "then", so "sit down
/// and say hello" loses the hello. A model reading the whole request has none
/// of those limits.
///
/// IT RUNS ON WHATEVER THE PERSON CHOSE. `ask` is `DraftEngine.ask` in the
/// app, so the same planner runs on Apple's on-device model, on a model
/// downloaded to this phone (MLX), or on a server such as llama.cpp serving
/// Gemma 4 on a desk. It takes a closure rather than an endpoint for
/// `HTTPIntentRouter`'s reason: the prompt and the reading are checked by
/// `swift test` on Linux, and the app owns the model.
///
/// THE PROMPT IS duckbatch'S, BYTE FOR BYTE. `Resources/Planner/instructions.txt`
/// is exported by duckbatch (`planner.export_for_phone`) and pinned here by
/// sha256, so a phone asks exactly what p002 measured on a laptop. It is the
/// no-grammar form: none of the phone's runtimes can constrain decoding to a
/// schema, so the reply is prose that should hold JSON, and `read` decides.
///
/// THE READER REFUSES; IT DOES NOT REPAIR. A label outside the vocabulary
/// refuses the plan — the same rule as `DuckIntentPlan.read`, and the same
/// answers as duckbatch's `read_reply`, which `reader-cases.json` pins case by
/// case. Numbers are clamped to the ranges the laptop's schema allows, because
/// that is what the schema would have enforced there.
public struct ModelIntentPlanner: IntentRouting {
    public typealias Ask = @Sendable (_ instructions: String, _ prompt: String) async throws -> String

    public let identity: DuckIntentPlan.RouterIdentity
    private let ask: Ask

    public init(identity: DuckIntentPlan.RouterIdentity, ask: @escaping Ask) {
        self.identity = identity
        self.ask = ask
    }

    public func plan(for request: String) async throws -> DuckIntentPlan {
        let reply = try await ask(Self.instructions, request)
        return try Self.read(reply: reply, request: request, model: identity.model)
    }

    /// Where duckbatch's planner came from, for a record that says which model
    /// proposed a step. The phone's own model names itself in `identity`.
    public static let promptSource = "craigm26/duckbatch planner.py (p002)"

    // MARK: - the prompt

    /// A bundled planner file, by its path under `Resources/`. Internal so the
    /// sha256 pin reads the file the app ships, not a test copy of it.
    static func resource(_ name: String, _ ext: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext)
    }

    /// The bundled instructions. A missing file is a broken build, which
    /// `ModelIntentPlannerTests` catches; the empty string keeps the app from
    /// crashing on a malformed bundle and makes any model answer unreadable.
    public static let instructions: String = {
        guard let url = resource("Planner/instructions", "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    // MARK: - the reply

    /// One step as the model wrote it, after checking. `repeat` is kept here
    /// and unrolled into nodes by `read`, because the editor edits each run
    /// of a skill separately.
    public struct Step: Equatable, Sendable {
        public let skill: String
        public let speed: String
        public let head: String
        public let sound: String
        public let seconds: Double
        public let repeats: Int
    }

    public enum ReadError: Error, Equatable {
        case noJSON
        case notAPlan
        case noSteps
        case unknownLabel(String, String)
        case missingSkill
        case badNumber

        public var message: String {
            switch self {
            case .noJSON:
                return "The model answered in words with no plan in them. Try again, or say the "
                     + "steps one after another."
            case .notAPlan:
                return "The model's answer is JSON but not a plan: it has no list of steps."
            case .noSteps:
                return "The model found no steps in that. Try saying what the duck should do, "
                     + "one thing after another."
            case .unknownLabel(let head, let label):
                return "The model wrote \"\(label)\" as a \(head), which this app does not know "
                     + "(vocabulary \(DuckIntentPlan.Vocabulary.id)). The plan was refused rather "
                     + "than guessed at."
            case .missingSkill:
                return "The model wrote a step without saying which skill it is."
            case .badNumber:
                return "The model wrote a duration or a count that is not a number."
            }
        }
    }

    public static let secondsRange = 0.5...10.0
    public static let repeatRange = 1...5

    private struct RawStep: Decodable {
        let skill: String?
        let speed: String?
        let head: String?
        let sound: String?
        let seconds: Double?
        let `repeat`: Int?
    }

    private struct RawPlan: Decodable {
        let steps: [RawStep]?
    }

    /// The model's steps, checked and clamped, or a refusal by name.
    public static func steps(fromReply reply: String) throws -> [Step] {
        guard let json = try? ChatWire.firstJSONObject(in: reply) else { throw ReadError.noJSON }
        // TYPES FIRST, SO A NUMBER WRITTEN AS A WORD IS A REFUSAL. `Decodable`
        // refuses `"seconds": "two"` and `"repeat": 2.5` outright, which is the
        // rule duckbatch's reader was tightened to match.
        let raw: RawPlan
        do {
            raw = try JSONDecoder().decode(RawPlan.self, from: Data(json.utf8))
        } catch DecodingError.typeMismatch, DecodingError.dataCorrupted {
            throw ReadError.badNumber
        } catch {
            throw ReadError.notAPlan
        }
        guard let rawSteps = raw.steps else { throw ReadError.notAPlan }
        guard !rawSteps.isEmpty else { throw ReadError.noSteps }
        let vocabulary = DuckIntentPlan.Vocabulary.self
        return try rawSteps.map { step in
            guard let skill = step.skill else { throw ReadError.missingSkill }
            guard vocabulary.actions.contains(skill) else { throw ReadError.unknownLabel("skill", skill) }
            let speed = step.speed ?? "normal"
            guard vocabulary.speeds.contains(speed) else { throw ReadError.unknownLabel("speed", speed) }
            let head = step.head ?? "straight"
            guard vocabulary.heads.contains(head) else { throw ReadError.unknownLabel("head", head) }
            let sound = step.sound ?? "none"
            guard sound == "none" || vocabulary.sounds.contains(sound) else {
                throw ReadError.unknownLabel("sound", sound)
            }
            let seconds = min(secondsRange.upperBound, max(secondsRange.lowerBound, step.seconds ?? 2))
            let repeats = min(repeatRange.upperBound, max(repeatRange.lowerBound, step.repeat ?? 1))
            return Step(skill: skill, speed: speed, head: head, sound: sound,
                        seconds: seconds, repeats: repeats)
        }
    }

    /// The reply as a plan the editor shows: one node per run of a skill, so
    /// "peck twice" is two nodes a person can keep or drop separately.
    ///
    /// THE LABELS ARE THE ROUTER'S SHAPE — action, speed, head, and sound only
    /// on a sound — so everything downstream (the editor, `run()`, the
    /// `route_correction` record) is the code the router already uses. A sound
    /// the model left as "none" becomes "chirp", duckbatch's `plan()` default.
    public static func read(reply: String, request: String, model: String) throws -> DuckIntentPlan {
        var nodes: [DuckIntentPlan.Node] = []
        for step in try steps(fromReply: reply) {
            var labels = ["action": step.skill, "speed": step.speed, "head": step.head]
            if step.skill == "make_sound" { labels["sound"] = step.sound == "none" ? "chirp" : step.sound }
            let words = DuckIntentPlan.Vocabulary.words(step.skill)
            for run in 1...step.repeats {
                let clause = step.repeats == 1 ? words : "\(words) (\(run) of \(step.repeats))"
                var node = DuckIntentPlan.Node(id: nodes.count, clause: clause, proposed: labels,
                                               confidence: [:], measured: false)
                node.seconds = step.seconds
                nodes.append(node)
            }
        }
        return DuckIntentPlan(request: request, model: model, nodes: nodes)
    }
}
