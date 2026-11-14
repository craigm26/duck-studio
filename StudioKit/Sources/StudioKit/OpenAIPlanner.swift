import Foundation

/// A planner on OpenAI's Responses API, with the person's own key (brains-layer.md 3.2 and 4).
///
/// THE WIRE IS RAW HTTP, `POST https://api.openai.com/v1/responses`. Shapes are from OpenAI's
/// developer docs read 2026-11-13: the function calling guide, the GPT-6 Luna model page, the
/// Responses create reference, the error codes guide and the migrate-to-Responses guide (all under
/// developers.openai.com/api/docs). No live call was made to write or test this file.
///
/// - The closed set goes as function tools, one per allowed kind, each `strict`.
/// - `tool_choice` is `required` and `parallel_tool_calls` is false, so the reply is exactly one
///   function call.
/// - `store` is false on every request, so the Responses API keeps no application state for 30
///   days. OpenAI's abuse-monitoring logs (up to 30 days) are separate and cannot be turned off
///   per request.
/// - Reasoning effort is `none`: a pick from a short list.
///
/// Naming: the feature is "Hosted by OpenAI, your key". The model is named as OpenAI names it.
/// Nothing in this app is called "GPT" anything.
public struct OpenAIPlanner: Planner {
    /// The default model, and the version an EvidenceRow keys on. GPT-6 Luna: OpenAI's most
    /// efficient current model ($0.10 / $0.50 per million tokens), it takes images, supports
    /// function calling on the Responses API and reasoning effort `none`. The model page lists no
    /// dated snapshot, so the alias is the version; the reply's `model` field is recorded with
    /// each decision so a moved alias shows up.
    public static let defaultModel = "gpt-6-luna"
    public static let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    public let info: PlannerInfo
    let key: PlannerKey
    let model: String
    let cameraConsent: Bool
    let http: any PlannerHTTP
    let deadline: Duration

    public init(key: String, model: String = OpenAIPlanner.defaultModel, cameraConsent: Bool = false,
                deadline: Duration = HostedPlanner.decisionDeadline, http: any PlannerHTTP = URLSessionPlannerHTTP()) {
        self.key = PlannerKey(key)
        self.model = model
        self.cameraConsent = cameraConsent
        self.http = http
        self.deadline = deadline
        self.info = HostedVendor.openai.info(model: model)
    }

    // MARK: request

    public func headers() -> [String: String] {
        ["Authorization": "Bearer \(key.value)", "Content-Type": "application/json"]
    }

    public func body(_ ask: PlannerAsk) throws -> Data {
        let tools: [JSONValue] = HostedPlanner.tools(for: ask.allowed).map { t in
            .object(["type": .string("function"), "name": .string(t.name), "description": .string(t.description),
                     "parameters": .object(t.schema), "strict": .bool(true)])
        }
        var content: [JSONValue] = [.object(["type": .string("input_text"), "text": .string(HostedPlanner.userText(ask))])]
        if HostedPlanner.sendsFrame(ask, cameraConsent: cameraConsent), let frame = ask.frame {
            content.append(.object(["type": .string("input_image"), "detail": .string("low"),
                                    "image_url": .string("data:image/jpeg;base64," + frame.base64EncodedString())]))
        }
        let body: [String: JSONValue] = [
            "model": .string(model),
            "instructions": .string(HostedPlanner.instructions),
            "input": .array([.object(["role": .string("user"), "content": .array(content)])]),
            "tools": .array(tools),
            "tool_choice": .string("required"),
            "parallel_tool_calls": .bool(false),
            "store": .bool(false),
            "max_output_tokens": .int(HostedPlanner.maxOutputTokens),
            "reasoning": .object(["effort": .string("none")]),
        ]
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
            throw PlannerError.network(vendor: HostedVendor.openai.name)
        }
        let latency = ContinuousClock.now - start
        return try Self.read(status: reply.status, headers: reply.headers, body: reply.body,
                             ask: ask, info: info, latency: latency)
    }

    // MARK: reply

    public static func read(status: Int, headers: [String: String] = [:], body: Data, ask: PlannerAsk,
                            info: PlannerInfo, latency: Duration) throws -> Decided {
        let vendor = HostedVendor.openai.name
        let top = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        guard status == 200 else { throw error(status: status, headers: headers, top: top) }
        guard let top, top["object"] as? String == "response", let output = top["output"] as? [[String: Any]] else {
            throw PlannerError.unreadable(vendor: vendor)
        }
        let served = HostedPlanner.served(info, model: top["model"] as? String)
        if top["status"] as? String == "failed" {
            throw PlannerError.busy(vendor: vendor, status: status)
        }
        // A refusal is a message whose content has a part of type "refusal".
        let refused = output.contains { item in
            item["type"] as? String == "message"
                && ((item["content"] as? [[String: Any]]) ?? []).contains { $0["type"] as? String == "refusal" }
        }
        let calls: [HostedPlanner.ToolCall] = output.compactMap { item in
            guard item["type"] as? String == "function_call", let name = item["name"] as? String,
                  let args = item["arguments"] as? String else { return nil }
            return HostedPlanner.ToolCall(name: name, arguments: Data(args.utf8))
        }
        if calls.isEmpty, refused {
            return Decided(decision: .ask(question: "\(vendor)'s model declined to choose a step. What should the duck do?"),
                           why: "The model refused.", provider: served, latency: latency)
        }
        if calls.isEmpty, top["status"] as? String == "incomplete" {
            return Decided(decision: HostedPlanner.ask(.notADecision), why: "The answer was cut off.",
                           provider: served, latency: latency)
        }
        let (decision, why) = HostedPlanner.decision(from: calls, allowed: ask.allowed)
        return Decided(decision: decision, why: why, provider: served, latency: latency)
    }

    /// OpenAI's error body is `{"error":{"message":...,"type":...,"param":...,"code":...}}`.
    static func error(status: Int, headers: [String: String], top: [String: Any]?) -> PlannerError {
        let vendor = HostedVendor.openai.name
        let err = top?["error"] as? [String: Any]
        let type = err?["type"] as? String ?? ""
        let code = err?["code"] as? String ?? ""
        let message = err?["message"] as? String ?? ""
        let quotaCodes: Set<String> = ["insufficient_quota", "credit_balance_exhausted", "organization_spend_limit_exceeded",
                                       "project_spend_limit_exceeded", "organization_usage_limit_exceeded"]
        if type == "insufficient_quota" || quotaCodes.contains(code) { return .noCredit(vendor: vendor) }
        switch status {
        case 401: return .keyRefused(vendor: vendor)
        case 429: return .rateLimited(vendor: vendor, retryAfterS: headers["retry-after"].flatMap(Double.init))
        case 500...: return .busy(vendor: vendor, status: status)
        default:
            return top == nil ? .unreadable(vendor: vendor)
                : .refusedRequest(vendor: vendor, status: status, detail: PlannerError.detail(message))
        }
    }
}
