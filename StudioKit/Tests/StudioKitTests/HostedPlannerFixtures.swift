import Foundation
import XCTest
@testable import StudioKit

/// A transport that answers from a fixture and records what was sent. No network, no keys.
final class StubPlannerHTTP: PlannerHTTP, @unchecked Sendable {
    struct Sent { let url: URL; let headers: [String: String]; let body: Data }

    private let lock = NSLock()
    private var _sent: [Sent] = []
    let status: Int
    let replyHeaders: [String: String]
    let reply: Data
    let delay: Duration?
    let failure: (any Error)?

    init(status: Int = 200, headers: [String: String] = [:], json: String = "{}", delay: Duration? = nil,
         failure: (any Error)? = nil) {
        self.status = status
        self.replyHeaders = headers
        self.reply = Data(json.utf8)
        self.delay = delay
        self.failure = failure
    }

    var sent: [Sent] { lock.lock(); defer { lock.unlock() }; return _sent }

    func send(url: URL, headers: [String: String], body: Data) async throws -> (status: Int, headers: [String: String], body: Data) {
        lock.lock(); _sent.append(Sent(url: url, headers: headers, body: body)); lock.unlock()
        if let delay { try await Task.sleep(for: delay) }
        if let failure { throw failure }
        return (status, replyHeaders, reply)
    }
}

struct StubNetworkError: Error {}

/// Recorded-shape replies. Field names and nesting follow each vendor's published reference
/// (see AnthropicPlanner.swift and OpenAIPlanner.swift); ids and text are invented.
enum HostedFixtures {
    // Obviously fake, and shorter than real keys.
    static let anthropicKey = "sk-ant-api03-" + String(repeating: "Fake", count: 6)
    static let openaiKey = "sk-proj-" + String(repeating: "Fake", count: 6)

    static let practice = AllowedDecisions(kinds: [.walk, .turn])
    static let real = AllowedDecisions(kinds: [.walk, .turn, .sound, .skill], skills: ["kick_left", "sit"],
                                       sounds: ["quack"])

    static func ask(_ allowed: AllowedDecisions = practice, frame: Data? = nil) -> PlannerAsk {
        PlannerAsk(goal: "walk to the red ball", utterance: "go to the ball", frame: frame,
                   state: DuckStateSnapshot(x: 0.1, y: -0.2, yaw: 0.3, odomAgeMs: 40, standing: true),
                   allowed: allowed)
    }

    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

    // MARK: Anthropic Messages API

    static func anthropicToolUse(_ name: String, _ input: String, model: String = "claude-haiku-5-5",
                                 stop: String = "tool_use") -> String {
        """
        {"id":"msg_01Fixture","type":"message","role":"assistant","model":"\(model)",
         "content":[{"type":"tool_use","id":"toolu_01Fixture","name":"\(name)","input":\(input)}],
         "stop_reason":"\(stop)","stop_sequence":null,"stop_details":null,
         "usage":{"input_tokens":412,"output_tokens":38}}
        """
    }

    static let anthropicTextOnly = """
        {"id":"msg_01Fixture","type":"message","role":"assistant","model":"claude-haiku-5-5",
         "content":[{"type":"text","text":"I think the duck should walk forward."}],
         "stop_reason":"end_turn","stop_sequence":null,"usage":{"input_tokens":412,"output_tokens":12}}
        """

    static let anthropicRefusal = """
        {"id":"msg_01Fixture","type":"message","role":"assistant","model":"claude-haiku-5-5",
         "content":[],"stop_reason":"refusal",
         "stop_details":{"type":"refusal","category":null,"explanation":null},
         "usage":{"input_tokens":412,"output_tokens":0}}
        """

    static let anthropicTwoCalls = """
        {"id":"msg_01Fixture","type":"message","role":"assistant","model":"claude-haiku-5-5",
         "content":[{"type":"tool_use","id":"toolu_1","name":"walk","input":{"forward_m":0.5,"side_m":0,"why":"a"}},
                    {"type":"tool_use","id":"toolu_2","name":"turn","input":{"degrees":30,"why":"b"}}],
         "stop_reason":"tool_use","usage":{"input_tokens":1,"output_tokens":1}}
        """

    static func anthropicError(_ type: String, _ message: String) -> String {
        #"{"type":"error","error":{"type":"\#(type)","message":"\#(message)"},"request_id":"req_01Fixture"}"#
    }

    // MARK: OpenAI Responses API

    static func openaiCall(_ name: String, _ arguments: String, model: String = "gpt-6-luna",
                           status: String = "completed") -> String {
        let escaped = arguments.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"id":"resp_fixture","object":"response","created_at":1763000000,"status":"\(status)","model":"\(model)",
         "error":null,"incomplete_details":null,
         "output":[{"type":"function_call","id":"fc_fixture","call_id":"call_fixture","name":"\(name)",
                    "arguments":"\(escaped)","status":"completed"}],
         "store":false,"usage":{"input_tokens":400,"output_tokens":30,"total_tokens":430}}
        """
    }

    static let openaiTextOnly = """
        {"id":"resp_fixture","object":"response","status":"completed","model":"gpt-6-luna","error":null,
         "output":[{"type":"message","id":"msg_fixture","role":"assistant","status":"completed",
                    "content":[{"type":"output_text","text":"Walk forward.","annotations":[]}]}]}
        """

    static let openaiRefusal = """
        {"id":"resp_fixture","object":"response","status":"completed","model":"gpt-6-luna","error":null,
         "output":[{"type":"message","id":"msg_fixture","role":"assistant","status":"completed",
                    "content":[{"type":"refusal","refusal":"I can't help with that."}]}]}
        """

    static let openaiIncomplete = """
        {"id":"resp_fixture","object":"response","status":"incomplete","model":"gpt-6-luna","error":null,
         "incomplete_details":{"reason":"max_output_tokens"},"output":[]}
        """

    static func openaiError(type: String, code: String?, _ message: String) -> String {
        let c = code.map { "\"\($0)\"" } ?? "null"
        return #"{"error":{"message":"\#(message)","type":"\#(type)","param":null,"code":\#(c)}}"#
    }
}

extension XCTestCase {
    func hostedJSON(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
    }

    func assertHostedAsk(_ d: DuckDecision, containing words: String? = nil, file: StaticString = #filePath, line: UInt = #line) {
        guard case .ask(let q) = d else { return XCTFail("expected .ask, got \(d)", file: file, line: line) }
        if let words { XCTAssertTrue(q.contains(words), q, file: file, line: line) }
    }
}
