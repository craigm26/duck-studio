import XCTest
@testable import StudioKit

/// The Anthropic planner against a stubbed transport and recorded-shape replies. No live call.
final class AnthropicPlannerTests: XCTestCase {
    typealias F = HostedFixtures

    func planner(_ stub: StubPlannerHTTP, model: String = AnthropicPlanner.defaultModel, consent: Bool = false,
                 deadline: Duration = .seconds(8)) -> AnthropicPlanner {
        AnthropicPlanner(key: F.anthropicKey, model: model, cameraConsent: consent, deadline: deadline, http: stub)
    }

    // MARK: request shape

    func testHeadersAndEndpoint() async throws {
        let stub = StubPlannerHTTP(json: F.anthropicToolUse("walk", #"{"forward_m":0.5,"side_m":0,"why":"ball ahead"}"#))
        _ = try await planner(stub).decide(F.ask())
        let sent = try XCTUnwrap(stub.sent.first)
        XCTAssertEqual(sent.url.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(sent.headers["x-api-key"], F.anthropicKey)
        XCTAssertEqual(sent.headers["anthropic-version"], "2026-10-21")
        XCTAssertEqual(sent.headers["content-type"], "application/json")
        XCTAssertNil(sent.headers["Authorization"], "the key goes in x-api-key only")
        XCTAssertFalse(String(decoding: sent.body, as: UTF8.self).contains(F.anthropicKey), "the key is not in the body")
    }

    func testToolsAreTheClosedSetAndTheCallIsForced() throws {
        let body = try hostedJSON(planner(StubPlannerHTTP()).body(F.ask(F.real)))
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual(body["max_tokens"] as? Int, HostedPlanner.maxOutputTokens)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["skill", "walk", "turn", "sound", "ask", "done", "stop"])
        for tool in tools {
            XCTAssertEqual(tool["strict"] as? Bool, true)
            let schema = try XCTUnwrap(tool["input_schema"] as? [String: Any])
            XCTAssertEqual(schema["additionalProperties"] as? Bool, false)
            let kind = try XCTUnwrap(DuckDecision.Kind(rawValue: tool["name"] as! String))
            XCTAssertEqual(Set(schema["required"] as? [String] ?? []), Set(kind.fields + ["why"]))
            XCTAssertEqual(Set((schema["properties"] as? [String: Any] ?? [:]).keys), Set(kind.fields + ["why"]))
        }
        let skill = try XCTUnwrap(tools.first { $0["name"] as? String == "skill" })
        let name = ((skill["input_schema"] as? [String: Any])?["properties"] as? [String: Any])?["name"] as? [String: Any]
        XCTAssertEqual(name?["enum"] as? [String], ["kick_left", "sit"])
        let choice = try XCTUnwrap(body["tool_choice"] as? [String: Any])
        XCTAssertEqual(choice["type"] as? String, "any")
        XCTAssertEqual(choice["disable_parallel_tool_use"] as? Bool, true)
        for field in ["temperature", "top_p", "top_k"] { XCTAssertNil(body[field], "2026-10-21 refuses \(field)") }
        XCTAssertEqual((body["output_config"] as? [String: Any])?["effort"] as? String, "low")
        XCTAssertNotNil(body["system"] as? String)
    }

    func testAKindNotAllowedIsNotOffered() throws {
        let body = try hostedJSON(planner(StubPlannerHTTP()).body(F.ask(F.practice)))
        let names = (body["tools"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        XCTAssertEqual(names, ["walk", "turn", "ask", "done", "stop"])
    }

    func testModelsThatRefuseAForcedChoiceGetAuto() throws {
        for model in ["claude-sonnet-5-5", "claude-opus-5-5"] {
            let body = try hostedJSON(planner(StubPlannerHTTP(), model: model).body(F.ask()))
            let choice = body["tool_choice"] as? [String: Any]
            XCTAssertEqual(choice?["type"] as? String, "auto", model)
            XCTAssertEqual(choice?["disable_parallel_tool_use"] as? Bool, true, model)
        }
    }

    func testAPictureGoesOnlyWithAFrameAndConsent() throws {
        func images(_ p: AnthropicPlanner, _ ask: PlannerAsk) throws -> Int {
            let body = try hostedJSON(p.body(ask))
            let content = ((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
            return content.filter { $0["type"] as? String == "image" }.count
        }
        XCTAssertEqual(try images(planner(StubPlannerHTTP(), consent: false), F.ask(frame: F.jpeg)), 0)
        XCTAssertEqual(try images(planner(StubPlannerHTTP(), consent: true), F.ask(frame: nil)), 0)
        XCTAssertEqual(try images(planner(StubPlannerHTTP(), consent: true), F.ask(frame: F.jpeg)), 1)
        let body = try hostedJSON(planner(StubPlannerHTTP(), consent: true).body(F.ask(frame: F.jpeg)))
        let image = ((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])?.first
        let source = image?["source"] as? [String: Any]
        XCTAssertEqual(source?["type"] as? String, "base64", "inline, never the Files API")
        XCTAssertEqual(source?["media_type"] as? String, "image/jpeg")
        XCTAssertEqual(source?["data"] as? String, F.jpeg.base64EncodedString())
    }

    // MARK: replies

    func testAToolCallBecomesADecision() async throws {
        let stub = StubPlannerHTTP(json: F.anthropicToolUse("walk", #"{"forward_m":0.5,"side_m":0,"why":"the ball is ahead"}"#,
                                                            model: "claude-haiku-5-5"))
        let d = try await planner(stub).decide(F.ask())
        XCTAssertEqual(d.decision, .walk(forwardM: 0.5, sideM: 0))
        XCTAssertEqual(d.why, "the ball is ahead")
        XCTAssertEqual(d.provider.id, "byok.anthropic")
        XCTAssertEqual(d.provider.modelVersion, "claude-haiku-5-5")
        XCTAssertGreaterThanOrEqual(d.latency, .zero)
        XCTAssertNil(d.confidence)
    }

    func testTheServedModelIsRecorded() throws {
        let p = planner(StubPlannerHTTP())
        let d = try AnthropicPlanner.read(status: 200, body: Data(F.anthropicToolUse("turn", #"{"degrees":30,"why":"x"}"#,
                                                                                      model: "claude-haiku-5-5-moved").utf8),
                                          ask: F.ask(), info: p.info, latency: .milliseconds(420))
        XCTAssertEqual(d.decision, .turn(degrees: 30))
        XCTAssertEqual(d.provider.modelVersion, "claude-haiku-5-5-moved", "a moved alias shows in the log")
        XCTAssertEqual(d.latency, .milliseconds(420))
    }

    func read(_ json: String, _ allowed: AllowedDecisions = F.practice, status: Int = 200,
              headers: [String: String] = [:]) throws -> Decided {
        try AnthropicPlanner.read(status: status, headers: headers, body: Data(json.utf8), ask: F.ask(allowed),
                                  info: HostedVendor.anthropic.info(), latency: .milliseconds(1))
    }

    func testOutOfSetBecomesAsk() throws {
        assertHostedAsk(try read(F.anthropicToolUse("skill", #"{"name":"kick_left","why":"x"}"#)).decision,
                        containing: "not allowed in this run")
        assertHostedAsk(try read(F.anthropicToolUse("skill", #"{"name":"backflip","why":"x"}"#), F.real).decision,
                        containing: "backflip")
        assertHostedAsk(try read(F.anthropicToolUse("look_at", #"{"x":1,"why":"x"}"#)).decision, containing: "look_at")
    }

    func testMalformedInputBecomesAsk() throws {
        assertHostedAsk(try read(F.anthropicToolUse("walk", #"{"forward_m":"far","side_m":0,"why":"x"}"#)).decision,
                        containing: "forward_m")
        assertHostedAsk(try read(F.anthropicToolUse("walk", #"{"forward_m":0.5,"side_m":0,"speed":9,"why":"x"}"#)).decision,
                        containing: "speed")
        assertHostedAsk(try read(F.anthropicToolUse("walk", #"{"side_m":0,"why":"x"}"#)).decision)
        assertHostedAsk(try read(F.anthropicToolUse("walk", #""walk""#)).decision)
    }

    func testNoToolCallOrTwoCallsBecomeAsk() throws {
        let none = try read(F.anthropicTextOnly)
        assertHostedAsk(none.decision)
        XCTAssertEqual(none.why, "No tool was called.")
        let two = try read(F.anthropicTwoCalls)
        assertHostedAsk(two.decision)
        XCTAssertEqual(two.why, "More than one tool was called.")
        assertHostedAsk(try read(F.anthropicToolUse("walk", "{}", stop: "max_tokens").replacingOccurrences(
            of: #""content":[{"type":"tool_use","id":"toolu_01Fixture","name":"walk","input":{}}]"#, with: #""content":[]"#)).decision)
    }

    func testARefusalBecomesAsk() throws {
        let d = try read(F.anthropicRefusal)
        assertHostedAsk(d.decision, containing: "declined")
        XCTAssertEqual(d.why, "The model refused.")
    }

    func testABodyThatIsNotAMessageThrows() {
        XCTAssertThrowsError(try read("<html>oops</html>")) { XCTAssertEqual($0 as? PlannerError, .unreadable(vendor: "Anthropic")) }
        XCTAssertThrowsError(try read(#"{"type":"completion"}"#))
    }

    func testHTTPErrors() {
        func err(_ status: Int, _ json: String, headers: [String: String] = [:]) -> PlannerError? {
            do { _ = try read(json, status: status, headers: headers); return nil } catch { return error as? PlannerError }
        }
        XCTAssertEqual(err(401, F.anthropicError("authentication_error", "invalid x-api-key")), .keyRefused(vendor: "Anthropic"))
        XCTAssertEqual(err(403, F.anthropicError("permission_error", "no")), .keyRefused(vendor: "Anthropic"))
        XCTAssertEqual(err(429, F.anthropicError("rate_limit_error", "slow"), headers: ["retry-after": "12"]),
                       .rateLimited(vendor: "Anthropic", retryAfterS: 12))
        XCTAssertEqual(err(529, F.anthropicError("overloaded_error", "Overloaded")), .busy(vendor: "Anthropic", status: 529))
        XCTAssertEqual(err(500, F.anthropicError("api_error", "boom")), .busy(vendor: "Anthropic", status: 500))
        XCTAssertEqual(err(503, "<html>bad gateway</html>"), .busy(vendor: "Anthropic", status: 503))
        XCTAssertEqual(err(400, F.anthropicError("invalid_request_error",
                                                 "Your credit balance is too low to access the Anthropic API.")),
                       .noCredit(vendor: "Anthropic"))
        XCTAssertEqual(err(400, F.anthropicError("invalid_request_error", "tools.0: bad schema")),
                       .refusedRequest(vendor: "Anthropic", status: 400, detail: "tools.0: bad schema"))
    }

    func testATimeoutDropsTheDecision() async {
        let stub = StubPlannerHTTP(json: F.anthropicToolUse("walk", #"{"forward_m":1,"side_m":0,"why":"x"}"#), delay: .seconds(30))
        let start = ContinuousClock.now
        do {
            _ = try await planner(stub, deadline: .milliseconds(100)).decide(F.ask())
            XCTFail("a late answer must not become a decision")
        } catch {
            XCTAssertEqual(error as? PlannerError, .timedOut)
        }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(5), "the slow call was cancelled, not waited out")
    }

    func testANetworkFailureSaysSoWithoutDetail() async {
        let stub = StubPlannerHTTP(failure: StubNetworkError())
        do { _ = try await planner(stub).decide(F.ask()); XCTFail() } catch {
            XCTAssertEqual(error as? PlannerError, .network(vendor: "Anthropic"))
        }
    }

    func testNoKeyMakesNoCall() async {
        let stub = StubPlannerHTTP()
        do { _ = try await AnthropicPlanner(key: "", http: stub).decide(F.ask()); XCTFail() } catch {
            XCTAssertEqual(error as? PlannerError, .noKey)
        }
        XCTAssertTrue(stub.sent.isEmpty)
    }
}
