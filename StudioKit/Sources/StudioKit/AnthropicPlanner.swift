import Foundation

/// A planner on Anthropic's Messages API, with the person's own key (brains-layer.md 3.2 and 4).
///
/// THE WIRE IS RAW HTTP, `POST https://api.anthropic.com/v1/messages`, API version 2026-10-21.
/// Shapes are from Anthropic's Claude API reference as bundled with the claude-api skill
/// (read 2026-11-13). No live call was made to write or test this file.
///
/// - The closed set goes as tools, one per allowed kind, each `strict`.
/// - The tool call is forced: `tool_choice` `any` with `disable_parallel_tool_use`, so the reply
///   is exactly one tool call. Claude Haiku 5.5 accepts a forced choice and then answers with the
///   call first, without a thinking pass, which is what a fast planner wants. Opus 5.5 and
///   Sonnet 5.5 reject a forced choice with a 400, so for those the request says `auto` and the
///   instructions name the tools. The reply is read the same way either way.
/// - No sampling fields: API version 2026-10-21 refuses `temperature`, `top_p` and `top_k`.
/// - Retention: Anthropic has no per-request "do not keep" switch. Zero data retention is an
///   organisation agreement, not a field. Pictures go inline as base64, never through the Files
///   API, which keeps uploads regardless.
public struct AnthropicPlanner: Planner {
    /// The default model, and the version an EvidenceRow keys on. Claude Haiku 5.5: the fastest
    /// and cheapest current Claude model ($0.10 / $0.50 per million tokens up to 100K prompt
    /// tokens), it takes images, and it accepts a forced tool call. A closed-set pick of one tool
    /// does not need a larger model until a measured row says otherwise.
    public static let defaultModel = "claude-haiku-5-5"
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let apiVersion = "2026-10-21"
    /// Models that answer a forced `tool_choice` with a 400.
    public static let noForcedToolChoice: Set<String> = [
        "claude-opus-5-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-fable-5-2",
    ]

    public let info: PlannerInfo
    let key: PlannerKey
    let model: String
    let cameraConsent: Bool
    let http: any PlannerHTTP
    let deadline: Duration

    public init(key: String, model: String = AnthropicPlanner.defaultModel, cameraConsent: Bool = false,
                deadline: Duration = HostedPlanner.decisionDeadline, http: any PlannerHTTP = URLSessionPlannerHTTP()) {
        self.key = PlannerKey(key)
        self.model = model
        self.cameraConsent = cameraConsent
        self.http = http
        self.deadline = deadline
        self.info = HostedVendor.anthropic.info(model: model)
    }

    // MARK: request

    public func headers() -> [String: String] {
        ["x-api-key": key.value, "anthropic-version": Self.apiVersion, "content-type": "application/json"]
    }

    public func body(_ ask: PlannerAsk) throws -> Data {
        let tools: [JSONValue] = HostedPlanner.tools(for: ask.allowed).map { t in
            .object(["name": .string(t.name), "description": .string(t.description),
                     "input_schema": .object(t.schema), "strict": .bool(true)])
        }
        var content: [JSONValue] = []
        if HostedPlanner.sendsFrame(ask, cameraConsent: cameraConsent), let frame = ask.frame {
            content.append(.object(["type": .string("image"), "source": .object([
                "type": .string("base64"), "media_type": .string("image/jpeg"),
                "data": .string(frame.base64EncodedString())])]))
        }
        content.append(.object(["type": .string("text"), "text": .string(HostedPlanner.userText(ask))]))
        let forced = !Self.noForcedToolChoice.contains(model)
        var body: [String: JSONValue] = [
            "model": .string(model),
            "max_tokens": .int(HostedPlanner.maxOutputTokens),
            "system": .string(HostedPlanner.instructions),
            "messages": .array([.object(["role": .string("user"), "content": .array(content)])]),
            "tools": .array(tools),
            "tool_choice": .object(["type": .string(forced ? "any" : "auto"),
                                    "disable_parallel_tool_use": .bool(true)]),
        ]
        // Low effort: a pick from a short list. Forced calls skip thinking on Haiku 5.5 anyway.
        body["output_config"] = .object(["effort": .string("low")])
        return try JSONValue.object(body).data()
    }

    // MARK: decide

    public func decide(_ ask: PlannerAsk) async throws -> Decided {
        guard !key.value.isEmpty else { throw PlannerError.noKey }
        let payload = try body(ask)
        let headers = headers()
        let http = self.http
        let start = ContinuousClock.now
        let reply: (status: Int, headers: [String: String], body: Data)
        do {
            reply = try await HostedPlanner.withDeadline(deadline) {
                try await http.send(url: Self.endpoint, headers: headers, body: payload)
            }
        } catch let e as PlannerError {
            throw e
        } catch {
            throw PlannerError.network(vendor: HostedVendor.anthropic.name)
        }
        let latency = ContinuousClock.now - start
        return try Self.read(status: reply.status, headers: reply.headers, body: reply.body,
                             ask: ask, info: info, latency: latency)
    }

    // MARK: reply

    /// The decision in one reply, or the error. A reply that is not one tool call inside the set
    /// becomes `.ask`.
    public static func read(status: Int, headers: [String: String] = [:], body: Data, ask: PlannerAsk,
                            info: PlannerInfo, latency: Duration) throws -> Decided {
        let vendor = HostedVendor.anthropic.name
        let top = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        guard status == 200 else { throw error(status: status, headers: headers, top: top) }
        guard let top, top["type"] as? String == "message", let content = top["content"] as? [[String: Any]] else {
            throw PlannerError.unreadable(vendor: vendor)
        }
        let served = HostedPlanner.served(info, model: top["model"] as? String)
        let stop = top["stop_reason"] as? String
        if stop == "refusal" {
            return Decided(decision: .ask(question: "\(vendor)'s model declined to choose a step. What should the duck do?"),
                           why: "The model refused.", provider: served, latency: latency)
        }
        let calls: [HostedPlanner.ToolCall] = content.compactMap { block in
            guard block["type"] as? String == "tool_use", let name = block["name"] as? String else { return nil }
            // An input that is not an object is kept as empty arguments, which read as no decision.
            // `isValidJSONObject` first: serialising a bare string would raise, not throw.
            let input = block["input"] ?? NSNull()
            let data = JSONSerialization.isValidJSONObject(input) ? (try? JSONSerialization.data(withJSONObject: input)) : nil
            return HostedPlanner.ToolCall(name: name, arguments: data ?? Data())
        }
        if calls.isEmpty, stop == "max_tokens" {
            return Decided(decision: HostedPlanner.ask(.notADecision), why: "The answer was cut off.",
                           provider: served, latency: latency)
        }
        let (decision, why) = HostedPlanner.decision(from: calls, allowed: ask.allowed)
        return Decided(decision: decision, why: why, provider: served, latency: latency)
    }

    /// Anthropic's error body is `{"type":"error","error":{"type":...,"message":...}}`.
    static func error(status: Int, headers: [String: String], top: [String: Any]?) -> PlannerError {
        let vendor = HostedVendor.anthropic.name
        let err = top?["error"] as? [String: Any]
        let type = err?["type"] as? String ?? ""
        let message = err?["message"] as? String ?? ""
        switch (status, type) {
        case (401, _), (403, _), (_, "authentication_error"), (_, "permission_error"):
            return .keyRefused(vendor: vendor)
        case (402, _), (_, "billing_error"):
            return .noCredit(vendor: vendor)
        case (400, _) where message.lowercased().contains("credit balance"):
            return .noCredit(vendor: vendor)
        case (429, _), (_, "rate_limit_error"):
            return .rateLimited(vendor: vendor, retryAfterS: headers["retry-after"].flatMap(Double.init))
        case (500..., _), (_, "overloaded_error"), (_, "api_error"):
            return .busy(vendor: vendor, status: status)
        default:
            return top == nil ? .unreadable(vendor: vendor)
                : .refusedRequest(vendor: vendor, status: status, detail: PlannerError.detail(message))
        }
    }
}
