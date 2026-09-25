import Foundation

/// duckbatch's p002, run on this phone against whichever model is chosen.
///
/// WHY THE PHONE MEASURES ITSELF. p002 was scored on a laptop: Gemma 4 E4B
/// 30/30, the router 17/30. Nothing measured says what Apple's on-device model
/// or a 4-bit MLX model does with the same prompt, and a screen that offered
/// "plan with this phone's model" on the strength of a laptop's number would be
/// spending a measurement it does not have. So the thirty requests ship with
/// the app, with their gold, and a person can put them to their own phone.
///
/// THE SCORING IS duckbatch's, RULE FOR RULE (`planner.evaluate`): repeats
/// unrolled, consecutive refusals collapsed to one, the action sequence first,
/// then speed and head on movement steps, sound on sounds, and a duration only
/// where the request states one, within a quarter of a second. The request set
/// is `Resources/Planner/p002.json`, exported by duckbatch and pinned by sha256.
public enum PlannerCheck {

    public struct GoldStep: Decodable, Equatable, Sendable {
        public let action: String
        public let speed: String?
        public let head: String?
        public let sound: String?
        public let seconds: Double?
        public let `repeat`: Int?
    }

    public struct Request: Decodable, Equatable, Sendable {
        public let text: String
        public let steps: [GoldStep]
    }

    private struct File: Decodable {
        let id: String
        let requests: [Request]
    }

    public static let setID = "p002-plan-requests"

    /// The bundled set, or empty if the bundle is broken (a test catches that).
    public static let requests: [Request] = {
        guard let url = ModelIntentPlanner.resource("Planner/p002", "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return [] }
        return file.requests
    }()

    /// One request's result.
    public struct Row: Equatable, Sendable {
        public let request: String
        public let sequenceExact: Bool
        public let fullyExact: Bool
        /// The refusal's message when the model's answer could not be read.
        public let unreadable: String?
        public let seconds: Double
        public let got: [String]
    }

    private struct Flat: Equatable {
        let action: String
        let labels: [String: String]
        let seconds: Double?
    }

    private static let movement: Set<String> = ["walk_forward", "walk_backward", "turn_left",
                                                "turn_right", "stop"]

    private static func collapse(_ steps: [Flat]) -> [Flat] {
        var out: [Flat] = []
        for step in steps where !(step.action == "unsupported" && out.last?.action == "unsupported") {
            out.append(step)
        }
        return out
    }

    /// Score one plan against one request. `plan` is nil when the model's
    /// answer was refused by the reader; that is a wrong plan, recorded.
    public static func score(_ request: Request, plan: DuckIntentPlan?, unreadable: String? = nil,
                             seconds: Double) -> Row {
        let gold = collapse(request.steps.flatMap { step -> [Flat] in
            var labels: [String: String] = [:]
            labels["speed"] = step.speed; labels["head"] = step.head; labels["sound"] = step.sound
            let flat = Flat(action: step.action, labels: labels, seconds: step.seconds)
            return Array(repeating: flat, count: step.repeat ?? 1)
        })
        let got = collapse((plan?.nodes ?? []).map {
            Flat(action: $0.action, labels: $0.labels, seconds: $0.seconds)
        })
        let sequenceExact = plan != nil && got.map(\.action) == gold.map(\.action)
        var fullyExact = sequenceExact
        if sequenceExact {
            for (mine, want) in zip(got, gold) {
                var heads: [String] = []
                if movement.contains(want.action) { heads += ["speed", "head"] }
                if want.action == "make_sound" { heads.append("sound") }
                for head in heads {
                    let expected = want.labels[head] ?? (head == "speed" ? "normal" : "straight")
                    if mine.labels[head] != expected { fullyExact = false }
                }
                if let stated = want.seconds, abs((mine.seconds ?? .nan) - stated) >= 0.25 {
                    fullyExact = false
                }
            }
        }
        return Row(request: request.text, sequenceExact: sequenceExact, fullyExact: fullyExact,
                   unreadable: unreadable, seconds: seconds, got: got.map(\.action))
    }

    public struct Summary: Equatable, Sendable {
        public let total: Int
        public let sequenceExact: Int
        public let fullyExact: Int
        public let unreadable: Int
        public let medianSeconds: Double

        /// One line, in p002's close's terms, so a phone's number can be put
        /// beside the laptop's.
        public var line: String {
            String(format: "%d/%d sequences, %d/%d fully right, %d unreadable, median %.1f s",
                   sequenceExact, total, fullyExact, total, unreadable, medianSeconds)
        }
    }

    public static func summarise(_ rows: [Row]) -> Summary {
        let times = rows.map(\.seconds).sorted()
        return Summary(total: rows.count,
                       sequenceExact: rows.filter(\.sequenceExact).count,
                       fullyExact: rows.filter(\.fullyExact).count,
                       unreadable: rows.filter { $0.unreadable != nil }.count,
                       medianSeconds: times.isEmpty ? 0 : times[times.count / 2])
    }

    /// What the laptop scored, for the line beside the phone's.
    public static let laptopReference =
        "On a laptop, p002 measured Gemma 4 E4B at 30/30 and the router at 17/30 sequences."
}
