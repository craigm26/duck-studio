import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import StudioKit

/// A transport that records what was sent and answers from a script. No network, no calls.
final class StubLocalHTTP: LocalPlannerHTTP, @unchecked Sendable {
    struct Sent {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: [String: Any]?
    }

    private let lock = NSLock()
    private var script: [Result<(Int, Data), Error>]
    private var _sent: [Sent] = []
    let delay: Duration?

    init(_ script: [Result<(Int, Data), Error>], delay: Duration? = nil) {
        self.script = script
        self.delay = delay
    }

    convenience init(status: Int = 200, json: String, delay: Duration? = nil) {
        self.init([.success((status, Data(json.utf8)))], delay: delay)
    }

    var sent: [Sent] { lock.lock(); defer { lock.unlock() }; return _sent }

    func send(_ method: String, url: URL, headers: [String: String], body: Data?,
              timeout: TimeInterval) async throws -> (status: Int, body: Data) {
        let parsed = body.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let next: Result<(Int, Data), Error>? = {
            lock.lock(); defer { lock.unlock() }
            _sent.append(Sent(method: method, url: url, headers: headers, body: parsed))
            return script.isEmpty ? nil : script.removeFirst()
        }()
        if let delay { try await Task.sleep(for: delay) }
        guard let next else { return (500, Data()) }
        let (status, data) = try next.get()
        return (status, data)
    }
}

enum LocalFixtures {
    static let sim = AllowedDecisions(kinds: [.walk, .turn])
    static let real = AllowedDecisions(kinds: [.walk, .turn, .skill, .sound], skills: ["sit", "stand"], sounds: ["quack"])

    static func ask(_ allowed: AllowedDecisions = sim) -> PlannerAsk {
        PlannerAsk(goal: "walk to the ball", state: DuckStateSnapshot(x: 0, y: 0, yaw: 0, odomAgeMs: 20, standing: true),
                   allowed: allowed)
    }

    static func endpoint(_ base: String = "http://mac.local:11434/v1", model: String = "qwen3.5:4b",
                         key: String? = nil, relay: Bool = false) -> ModelEndpoint {
        ModelEndpoint(name: "Mac", kind: .openAICompatible, baseURL: base, model: model, apiKey: key, relay: relay)
    }

    static let pinned = LocalModelVersion(model: "qwen3.5:4b", checkpoint: "1a2b3c4d5e6f", quantisation: "Q4_K_M")

    static func planner(_ http: StubLocalHTTP, base: String = "http://mac.local:11434/v1", key: String? = nil,
                        mode: LocalOutputMode? = nil, deadline: Duration = LANPlanner.decisionDeadline,
                        evidence: EvidenceRow? = nil, terms: TermsRow? = nil) throws -> LANPlanner {
        try LANPlanner(endpoint: endpoint(base, key: key), version: pinned, mode: mode, evidence: evidence,
                       terms: terms, deadline: deadline, http: http)
    }

    /// A JSON string literal of `s`, quotes included.
    static func quoted(_ s: String) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: [s]), as: UTF8.self).dropFirst().dropLast().description
    }

    static func ollama(content: String, model: String = "qwen3.5:4b", thinking: String? = nil,
                       doneReason: String = "stop") -> String {
        let think = thinking.map { ",\"thinking\":" + quoted($0) } ?? ""
        return #"{"model":"\#(model)","message":{"role":"assistant","content":\#(quoted(content))\#(think)},"done":true,"done_reason":"\#(doneReason)"}"#
    }

    static func openAI(content: String, model: String = "qwen3.5:4b", reasoning: String? = nil,
                       finish: String = "stop") -> String {
        let r = reasoning.map { ",\"reasoning_content\":" + quoted($0) } ?? ""
        return #"{"model":"\#(model)","choices":[{"index":0,"message":{"role":"assistant","content":\#(quoted(content))\#(r)},"finish_reason":"\#(finish)"}]}"#
    }

    static func toolCall(_ name: String, arguments: String, model: String = "qwen3.5:4b") -> String {
        #"{"model":"\#(model)","choices":[{"index":0,"message":{"role":"assistant","content":"","tool_calls":[{"id":"c1","type":"function","function":{"name":"\#(name)","arguments":\#(quoted(arguments))}}]},"finish_reason":"tool_calls"}]}"#
    }

    static let walk = #"{"kind":"walk","forward_m":0.5,"side_m":0,"why":"the ball is ahead"}"#
}

/// A runner for `PhoneMLXPlanner` that answers from a closure.
struct StubRunner: PhoneModelRunning {
    struct Seen: Sendable { let repository: String; let instructions: String; let prompt: String; let deadline: TimeInterval }
    let answer: @Sendable (Seen) async throws -> String
    func respond(repository: String, instructions: String, prompt: String, deadline: TimeInterval) async throws -> String {
        try await answer(Seen(repository: repository, instructions: instructions, prompt: prompt, deadline: deadline))
    }
}

/// Records what a stub runner saw.
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T
    init(_ v: T) { _value = v }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
