import XCTest
@testable import StudioKit

/// The OpenAI planner against a stubbed transport and recorded-shape replies. No live call.
final class OpenAIPlannerTests: XCTestCase {
    typealias F = HostedFixtures

    func planner(_ stub: StubPlannerHTTP, consent: Bool = false, deadline: Duration = .seconds(8)) -> OpenAIPlanner {
        OpenAIPlanner(key: F.openaiKey, cameraConsent: consent, deadline: deadline, http: stub)
    }

    // MARK: request shape

    func testHeadersAndEndpoint() async throws {
        let stub = StubPlannerHTTP(json: F.openaiCall("turn", #"{"degrees":45,"why":"face the ball"}"#))
        _ = try await planner(stub).decide(F.ask())
        let sent = try XCTUnwrap(stub.sent.first)
        XCTAssertEqual(sent.url.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(sent.headers["Authorization"], "Bearer " + F.openaiKey)
        XCTAssertEqual(sent.headers["Content-Type"], "application/json")
        XCTAssertFalse(String(decoding: sent.body, as: UTF8.self).contains(F.openaiKey), "the key is not in the body")
    }

    func testToolsStoreAndForcedChoice() throws {
        let body = try hostedJSON(planner(StubPlannerHTTP()).body(F.ask(F.real)))
        XCTAssertEqual(body["model"] as? String, "gpt-6-luna")
        XCTAssertEqual(body["store"] as? Bool, false, "the Responses API must not keep application state")
        XCTAssertEqual(body["tool_choice"] as? String, "required")
        XCTAssertEqual(body["parallel_tool_calls"] as? Bool, false)
        XCTAssertEqual(body["max_output_tokens"] as? Int, HostedPlanner.maxOutputTokens)
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "none")
        XCTAssertNotNil(body["instructions"] as? String)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["skill", "walk", "turn", "sound", "ask", "done", "stop"])
        for tool in tools {
            XCTAssertEqual(tool["type"] as? String, "function")
            XCTAssertEqual(tool["strict"] as? Bool, true)
            let schema = try XCTUnwrap(tool["parameters"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            let kind = try XCTUnwrap(DuckDecision.Kind(rawValue: tool["name"] as! String))
            XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(kind.fields + ["why"]),
                           "strict mode needs every property required")
        }
        let sound = try XCTUnwrap(tools.first { $0["name"] as? String == "sound" })
        let name = ((sound["parameters"] as? [String: Any])?["properties"] as? [String: Any])?["name"] as? [String: Any]
        XCTAssertEqual(name?["enum"] as? [String], ["quack"])
        let feature = tools.compactMap { $0["description"] as? String }.joined()
        XCTAssertFalse(feature.contains("GPT"))
    }

    func testAPictureGoesOnlyWithAFrameAndConsent() throws {
        func images(_ p: OpenAIPlanner, _ ask: PlannerAsk) throws -> [[String: Any]] {
            let body = try hostedJSON(p.body(ask))
            let content = ((body["input"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
            return content.filter { $0["type"] as? String == "input_image" }
        }
        XCTAssertTrue(try images(planner(StubPlannerHTTP(), consent: false), F.ask(frame: F.jpeg)).isEmpty)
        XCTAssertTrue(try images(planner(StubPlannerHTTP(), consent: true), F.ask(frame: nil)).isEmpty)
        let one = try images(planner(StubPlannerHTTP(), consent: true), F.ask(frame: F.jpeg))
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one.first?["image_url"] as? String, "data:image/jpeg;base64," + F.jpeg.base64EncodedString())
    }

    // MARK: replies

    func read(_ json: String, _ allowed: AllowedDecisions = F.practice, status: Int = 200,
              headers: [String: String] = [:]) throws -> Decided {
        try OpenAIPlanner.read(status: status, headers: headers, body: Data(json.utf8), ask: F.ask(allowed),
                               info: HostedVendor.openai.info(), latency: .milliseconds(1))
    }

    func testAFunctionCallBecomesADecision() async throws {
        let stub = StubPlannerHTTP(json: F.openaiCall("sound", #"{"name":"quack","why":"say hello"}"#))
        let d = try await planner(stub).decide(F.ask(F.real))
        XCTAssertEqual(d.decision, .sound(name: "quack"))
        XCTAssertEqual(d.why, "say hello")
        XCTAssertEqual(d.provider.id, "byok.openai")
        XCTAssertEqual(d.provider.modelVersion, "gpt-6-luna")
        XCTAssertGreaterThanOrEqual(d.latency, .zero)
    }

    func testTheServedModelIsRecorded() throws {
        let d = try read(F.openaiCall("done", #"{"reason":"at the ball","why":"close"}"#, model: "gpt-6-luna-2026-12-01"))
        XCTAssertEqual(d.decision, .done(reason: "at the ball"))
        XCTAssertEqual(d.provider.modelVersion, "gpt-6-luna-2026-12-01")
    }

    func testOutOfSetBecomesAsk() throws {
        assertHostedAsk(try read(F.openaiCall("sound", #"{"name":"quack","why":"x"}"#)).decision, containing: "not allowed")
        assertHostedAsk(try read(F.openaiCall("skill", #"{"name":"backflip","why":"x"}"#), F.real).decision, containing: "backflip")
        assertHostedAsk(try read(F.openaiCall("drive", #"{"why":"x"}"#)).decision, containing: "drive")
    }

    func testMalformedArgumentsBecomeAsk() throws {
        assertHostedAsk(try read(F.openaiCall("walk", #"{"forward_m":0.5,"side_m":"#)).decision)
        assertHostedAsk(try read(F.openaiCall("walk", #"{"forward_m":null,"side_m":0,"why":"x"}"#)).decision, containing: "forward_m")
        assertHostedAsk(try read(F.openaiCall("turn", #"[30]"#)).decision)
    }

    func testNoCallRefusalAndIncompleteBecomeAsk() throws {
        let none = try read(F.openaiTextOnly)
        assertHostedAsk(none.decision)
        XCTAssertEqual(none.why, "No tool was called.")
        let refused = try read(F.openaiRefusal)
        assertHostedAsk(refused.decision, containing: "declined")
        XCTAssertEqual(refused.why, "The model refused.")
        let cut = try read(F.openaiIncomplete)
        assertHostedAsk(cut.decision)
        XCTAssertEqual(cut.why, "The answer was cut off.")
    }

    func testHTTPErrors() {
        func err(_ status: Int, _ json: String, headers: [String: String] = [:]) -> PlannerError? {
            do { _ = try read(json, status: status, headers: headers); return nil } catch { return error as? PlannerError }
        }
        XCTAssertEqual(err(401, F.openaiError(type: "invalid_request_error", code: "invalid_api_key", "Incorrect API key provided")),
                       .keyRefused(vendor: "OpenAI"))
        XCTAssertEqual(err(429, F.openaiError(type: "rate_limit_error", code: "rate_limit_exceeded", "Rate limit reached"),
                           headers: ["retry-after": "2"]),
                       .rateLimited(vendor: "OpenAI", retryAfterS: 2))
        XCTAssertEqual(err(429, F.openaiError(type: "insufficient_quota", code: "credit_balance_exhausted", "no credit")),
                       .noCredit(vendor: "OpenAI"))
        XCTAssertEqual(err(500, F.openaiError(type: "server_error", code: nil, "boom")), .busy(vendor: "OpenAI", status: 500))
        XCTAssertEqual(err(503, F.openaiError(type: "service_unavailable_error", code: "server_is_overloaded", "busy")),
                       .busy(vendor: "OpenAI", status: 503))
        XCTAssertEqual(err(400, F.openaiError(type: "invalid_request_error", code: nil, "Invalid schema for function")),
                       .refusedRequest(vendor: "OpenAI", status: 400, detail: "Invalid schema for function"))
        XCTAssertEqual(err(502, "upstream"), .busy(vendor: "OpenAI", status: 502))
        XCTAssertThrowsError(try read("not json")) { XCTAssertEqual($0 as? PlannerError, .unreadable(vendor: "OpenAI")) }
    }

    func testATimeoutDropsTheDecision() async {
        let stub = StubPlannerHTTP(json: F.openaiCall("walk", #"{"forward_m":1,"side_m":0,"why":"x"}"#), delay: .seconds(30))
        let start = ContinuousClock.now
        do {
            _ = try await planner(stub, deadline: .milliseconds(100)).decide(F.ask())
            XCTFail("a late answer must not become a decision")
        } catch {
            XCTAssertEqual(error as? PlannerError, .timedOut)
        }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5))
    }

    func testANetworkFailureSaysSoWithoutDetail() async {
        do { _ = try await planner(StubPlannerHTTP(failure: StubNetworkError())).decide(F.ask()); XCTFail() } catch {
            XCTAssertEqual(error as? PlannerError, .network(vendor: "OpenAI"))
        }
    }
}
