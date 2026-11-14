import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import StudioKit

/// The LAN planner (brains-layer.md section 9 item 2): request shapes per server kind, reply
/// decoding, and every way a local server fails. All on a stub transport; nothing is called.
final class LocalPlannerTests: XCTestCase {
    typealias F = LocalFixtures

    // MARK: request shapes

    func testOllamaGetsItsOwnRouteWithTheSchemaAsFormat() async throws {
        let http = StubLocalHTTP(json: F.ollama(content: F.walk))
        let planner = try F.planner(http)
        XCTAssertEqual(planner.mode, .ollamaFormat, "port 11434 starts at Ollama's own route")
        _ = try await planner.decide(F.ask())
        let sent = try XCTUnwrap(http.sent.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url.absoluteString, "http://mac.local:11434/api/chat")
        let body = try XCTUnwrap(sent.body)
        XCTAssertEqual(body["model"] as? String, "qwen3.5:4b")
        XCTAssertEqual(body["stream"] as? Bool, false)
        XCTAssertEqual(body["think"] as? Bool, false, "reasoning off through Ollama's own flag")
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        XCTAssertEqual(options["temperature"] as? Int, 0)
        XCTAssertEqual(options["num_predict"] as? Int, LocalDecisionPrompt.maxOutputTokens)
        XCTAssertNil(body["tools"]); XCTAssertNil(body["response_format"])
        let format = try XCTUnwrap(body["format"] as? [String: Any])
        let kinds = try Self.branchKinds(format)
        XCTAssertEqual(kinds, ["walk", "turn", "ask", "done", "stop"], "only this run's kinds, in kit order")
        XCTAssertNil(sent.headers["Authorization"], "no token set, none sent")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        XCTAssertTrue((messages[1]["content"] as? String ?? "").hasPrefix("Goal: walk to the ball"))
    }

    func testOtherServersGetJSONSchemaOnV1() async throws {
        let http = StubLocalHTTP(json: F.openAI(content: F.walk))
        let planner = try F.planner(http, base: "http://192.168.1.20:1234/v1")
        XCTAssertEqual(planner.mode, .jsonSchema)
        _ = try await planner.decide(F.ask())
        let sent = try XCTUnwrap(http.sent.first)
        XCTAssertEqual(sent.url.absoluteString, "http://192.168.1.20:1234/v1/chat/completions")
        let body = try XCTUnwrap(sent.body)
        XCTAssertEqual(body["reasoning_effort"] as? String, "none")
        XCTAssertEqual(body["max_tokens"] as? Int, LocalDecisionPrompt.maxOutputTokens)
        XCTAssertEqual(body["temperature"] as? Int, 0)
        let rf = try XCTUnwrap(body["response_format"] as? [String: Any])
        XCTAssertEqual(rf["type"] as? String, "json_schema")
        let js = try XCTUnwrap(rf["json_schema"] as? [String: Any])
        XCTAssertEqual(js["name"] as? String, "duck_decision")
        XCTAssertEqual(js["strict"] as? Bool, true)
        XCTAssertEqual(try Self.branchKinds(try XCTUnwrap(js["schema"] as? [String: Any])).count, 5)
        XCTAssertNil(body["tools"]); XCTAssertNil(body["format"]); XCTAssertNil(body["think"])
    }

    func testSkillAndSoundNamesAreAnEnumInTheSchema() throws {
        let schema = LocalDecisionPrompt.schema(for: F.real)
        let branches = try XCTUnwrap(schema["anyOf"] as? [[String: Any]])
        func names(_ kind: String) throws -> [String]? {
            let b = try XCTUnwrap(branches.first { (($0["properties"] as? [String: Any])?["kind"] as? [String: Any])?["enum"] as? [String] == [kind] })
            XCTAssertEqual(b["additionalProperties"] as? Bool, false)
            return ((b["properties"] as? [String: Any])?["name"] as? [String: Any])?["enum"] as? [String]
        }
        XCTAssertEqual(try names("skill"), ["sit", "stand"])
        XCTAssertEqual(try names("sound"), ["quack"])
    }

    func testToolCallsShapeOffersOneToolPerAllowedKind() async throws {
        let http = StubLocalHTTP(json: F.toolCall("turn", arguments: #"{"degrees":30,"why":"face the ball"}"#))
        let planner = try F.planner(http, base: "http://mac.local:8080/v1", mode: .toolCalls)
        let d = try await planner.decide(F.ask())
        XCTAssertEqual(d.decision, .turn(degrees: 30))
        XCTAssertEqual(d.why, "face the ball")
        let body = try XCTUnwrap(http.sent.first?.body)
        let tools = try XCTUnwrap(body["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String },
                       ["walk", "turn", "ask", "done", "stop"])
        XCTAssertEqual(body["tool_choice"] as? String, "required")
        XCTAssertNil(body["response_format"])
    }

    func testPromptOnlyShowsTheShortListAndNothingElse() async throws {
        let http = StubLocalHTTP(json: F.openAI(content: F.walk))
        let planner = try F.planner(http, base: "http://mac.local:8080/v1", mode: .promptOnly)
        _ = try await planner.decide(F.ask())
        let body = try XCTUnwrap(http.sent.first?.body)
        XCTAssertNil(body["response_format"]); XCTAssertNil(body["tools"])
        let system = try XCTUnwrap((body["messages"] as? [[String: Any]])?.first?["content"] as? String)
        XCTAssertTrue(system.contains(#"{"kind":"walk""#))
        XCTAssertTrue(system.contains(#"{"kind":"turn""#))
        XCTAssertFalse(system.contains(#"{"kind":"skill""#), "a kind not allowed is not shown")
        let realSystem = LocalDecisionPrompt.instructions(for: F.real)
        XCTAssertTrue(realSystem.contains("one of: sit, stand"))
        XCTAssertTrue(realSystem.contains("one of: quack"))
    }

    func testTheTokenGoesInTheHeaderWhenOneIsSet() async throws {
        let http = StubLocalHTTP(json: F.ollama(content: F.walk))
        let planner = try F.planner(http, key: "my-own-token-123")
        _ = try await planner.decide(F.ask())
        XCTAssertEqual(http.sent.first?.headers["Authorization"], "Bearer my-own-token-123")
        XCTAssertNil(planner.endpoint.apiKey, "the stored endpoint carries no key")
    }

    func testReasoningFlagFollowsTheEndpoint() async throws {
        var e = F.endpoint()
        e.suppressReasoning = false
        let http = StubLocalHTTP(json: F.ollama(content: F.walk))
        _ = try await LANPlanner(endpoint: e, version: F.pinned, http: http).decide(F.ask())
        XCTAssertNil(http.sent.first?.body?["think"])
    }

    // MARK: reply decoding

    func testAValidAnswerIsReadWithLatencyAndThePinnedVersion() async throws {
        let http = StubLocalHTTP(json: F.ollama(content: F.walk), delay: .milliseconds(30))
        let outcome = try await F.planner(http).decideWithOutcome(F.ask())
        XCTAssertEqual(outcome.decided.decision, .walk(forwardM: 0.5, sideM: 0))
        XCTAssertEqual(outcome.decided.why, "the ball is ahead")
        XCTAssertNil(outcome.refusal)
        XCTAssertEqual(outcome.mode, .ollamaFormat)
        XCTAssertEqual(outcome.servedModel, "qwen3.5:4b")
        XCTAssertEqual(outcome.decided.provider.modelVersion, "qwen3.5:4b@1a2b3c4d5e6f Q4_K_M")
        XCTAssertGreaterThanOrEqual(outcome.decided.latency, .milliseconds(30))
    }

    func testFencedAndPrefacedAnswersAreStillRead() async throws {
        let text = "Here is the JSON:\n```json\n" + F.walk + "\n```"
        let d = try await F.planner(StubLocalHTTP(json: F.ollama(content: text))).decide(F.ask())
        XCTAssertEqual(d.decision, .walk(forwardM: 0.5, sideM: 0))
    }

    func testAKindOutsideTheSetBecomesAsk() async throws {
        let reply = F.ollama(content: #"{"kind":"skill","name":"sit","why":"tired"}"#)
        let o = try await F.planner(StubLocalHTTP(json: reply)).decideWithOutcome(F.ask())
        XCTAssertEqual(o.refusal, .kindNotAllowed(.skill))
        guard case .ask(let q) = o.decided.decision else { return XCTFail("not an ask") }
        XCTAssertTrue(q.contains("not allowed in this run"))
    }

    func testAnUnknownSkillOrKindBecomesAsk() async throws {
        let skill = F.ollama(content: #"{"kind":"skill","name":"backflip","why":"fun"}"#)
        let o1 = try await F.planner(StubLocalHTTP(json: skill)).decideWithOutcome(F.ask(F.real))
        XCTAssertEqual(o1.refusal, .unknownSkill("backflip"))
        let lookAt = F.ollama(content: #"{"kind":"look_at","x":1,"why":"see"}"#)
        let o2 = try await F.planner(StubLocalHTTP(json: lookAt)).decideWithOutcome(F.ask())
        XCTAssertEqual(o2.refusal, .unknownKind("look_at"))
        XCTAssertEqual(o2.decided.decision.kind, .ask)
    }

    func testMalformedAnswersBecomeAskNotAGuess() async throws {
        let prose = F.ollama(content: "I think the duck should walk forward a bit.")
        let o1 = try await F.planner(StubLocalHTTP(json: prose)).decideWithOutcome(F.ask())
        XCTAssertEqual(o1.refusal, .notADecision)
        let wordy = F.ollama(content: #"{"kind":"walk","forward_m":"far","side_m":0,"why":"x"}"#)
        let o2 = try await F.planner(StubLocalHTTP(json: wordy)).decideWithOutcome(F.ask())
        XCTAssertEqual(o2.refusal, .badField("forward_m"))
        let extra = F.ollama(content: #"{"kind":"turn","degrees":10,"speed":"fast","why":"x"}"#)
        let o3 = try await F.planner(StubLocalHTTP(json: extra)).decideWithOutcome(F.ask())
        XCTAssertEqual(o3.refusal, .badField("speed"))
        let infinite = F.openAI(content: #"{"kind":"turn","degrees":1e999,"why":"x"}"#)
        let o4 = try await F.planner(StubLocalHTTP(json: infinite), base: "http://mac.local:1234/v1").decideWithOutcome(F.ask())
        XCTAssertEqual(o4.decided.decision.kind, .ask)
    }

    func testOneToolCallOnlyAndItsNameIsTheKind() {
        let two = LocalDecisionPrompt.read(toolCalls: [("turn", Data(#"{"degrees":1}"#.utf8)),
                                                       ("walk", Data(#"{"forward_m":1,"side_m":0}"#.utf8))], allowed: F.sim)
        XCTAssertEqual(two.refusal, .notADecision)
        let mismatch = LocalDecisionPrompt.read(toolCalls: [("turn", Data(#"{"kind":"walk","degrees":1}"#.utf8))], allowed: F.sim)
        XCTAssertEqual(mismatch.refusal, .notADecision)
        let none = LocalDecisionPrompt.read(toolCalls: [], allowed: F.sim)
        XCTAssertEqual(none.refusal, .notADecision)
    }

    func testAnEmptyAnswerFromAReasoningModelIsRefused() async throws {
        let ollama = F.ollama(content: "", thinking: #"maybe {"kind":"walk","forward_m":3,"side_m":0}"#, doneReason: "length")
        await Self.assertThrows(.spentItAllThinking) { _ = try await F.planner(StubLocalHTTP(json: ollama)).decide(F.ask()) }
        let openAI = F.openAI(content: "", reasoning: "Let me think about the ball...", finish: "length")
        await Self.assertThrows(.spentItAllThinking) {
            _ = try await F.planner(StubLocalHTTP(json: openAI), base: "http://mac.local:1234/v1").decide(F.ask())
        }
        let unclosed = F.ollama(content: "<think>The ball is to the left so I")
        await Self.assertThrows(.spentItAllThinking) { _ = try await F.planner(StubLocalHTTP(json: unclosed)).decide(F.ask()) }
    }

    func testAnEmptyAnswerIsRefused() async throws {
        await Self.assertThrows(.emptyReply) {
            _ = try await F.planner(StubLocalHTTP(json: F.ollama(content: "  \n"))).decide(F.ask())
        }
    }

    func testANonJSONReplyIsUnreadable() async throws {
        await Self.assertThrows(.unreadable) {
            _ = try await F.planner(StubLocalHTTP(json: "<html>hello</html>")).decide(F.ask())
        }
    }

    // MARK: failures

    func testATimeoutHoldsTheDuckAndReturnsPromptly() async throws {
        let http = StubLocalHTTP(json: F.ollama(content: F.walk), delay: .seconds(10))
        let planner = try F.planner(http, deadline: .milliseconds(100))
        let start = ContinuousClock.now
        await Self.assertThrows(.timedOut(seconds: 1)) { _ = try await planner.decide(F.ask()) }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(3), "the deadline cancels the request")
    }

    func testConnectionRefusedNamesTheHost() async throws {
        let http = StubLocalHTTP([.failure(URLError(.cannotConnectToHost))])
        await Self.assertThrows(.notReachable(host: "mac.local")) { _ = try await F.planner(http).decide(F.ask()) }
        let noHost = StubLocalHTTP([.failure(URLError(.cannotFindHost))])
        await Self.assertThrows(.notReachable(host: "mac.local")) { _ = try await F.planner(noHost).decide(F.ask()) }
        let slow = StubLocalHTTP([.failure(URLError(.timedOut))])
        await Self.assertThrows(.timedOut(seconds: 15)) { _ = try await F.planner(slow).decide(F.ask()) }
    }

    func testARefusedShapeStepsDownToTheNextMode() async throws {
        let http = StubLocalHTTP([
            .success((400, Data(#"{"error":{"message":"response_format json_schema is not supported"}}"#.utf8))),
            .success((200, Data(F.toolCall("walk", arguments: #"{"forward_m":0.4,"side_m":0,"why":"go"}"#).utf8))),
        ])
        let o = try await F.planner(http, base: "http://mac.local:8080/v1").decideWithOutcome(F.ask())
        XCTAssertEqual(o.mode, .toolCalls)
        XCTAssertEqual(o.decided.decision, .walk(forwardM: 0.4, sideM: 0))
        XCTAssertEqual(http.sent.count, 2)
        XCTAssertNotNil(http.sent[0].body?["response_format"])
        XCTAssertNotNil(http.sent[1].body?["tools"])
    }

    func testNotOllamaAfterAllStepsDownToV1() async throws {
        let http = StubLocalHTTP([
            .success((404, Data("404 page not found".utf8))),
            .success((200, Data(F.openAI(content: F.walk).utf8))),
        ])
        let o = try await F.planner(http).decideWithOutcome(F.ask())
        XCTAssertEqual(o.mode, .jsonSchema)
        XCTAssertEqual(http.sent[1].url.path, "/v1/chat/completions")
    }

    func testEveryShapeRefusedEndsWithTheLastRefusal() async throws {
        let http = StubLocalHTTP(status: 400, json: #"{"error":"bad request"}"#)
        await Self.assertThrows(.serverRefused(status: 400, detail: "bad request")) {
            _ = try await F.planner(http, mode: .promptOnly).decide(F.ask())
        }
    }

    func testModelNotPulledTokenRefusedAndServerErrors() async throws {
        let missing = StubLocalHTTP(status: 404, json: #"{"error":"model \"qwen3.5:4b\" not found, try pulling it first"}"#)
        await Self.assertThrows(.modelNotFound(model: "qwen3.5:4b")) { _ = try await F.planner(missing).decide(F.ask()) }
        let token = StubLocalHTTP(status: 401, json: #"{"error":"unauthorized"}"#)
        await Self.assertThrows(.tokenRefused(host: "mac.local")) { _ = try await F.planner(token).decide(F.ask()) }
        let broke = StubLocalHTTP(status: 500, json: #"{"error":"llama runner process has terminated"}"#)
        await Self.assertThrows(.serverError(status: 500)) { _ = try await F.planner(broke).decide(F.ask()) }
    }

    // MARK: who answered

    func testADifferentServedModelIsCarriedUnpinned() async throws {
        let http = StubLocalHTTP(json: F.ollama(content: F.walk, model: "llama3.2:3b"))
        let d = try await F.planner(http).decide(F.ask())
        XCTAssertEqual(d.provider.modelVersion, "llama3.2:3b")
        XCTAssertFalse(LocalModelVersion.isPinned(d.provider.modelVersion))
        let same = StubLocalHTTP(json: F.ollama(content: F.walk, model: "qwen3.5:4b"))
        let d2 = try await F.planner(same).decide(F.ask())
        XCTAssertEqual(d2.provider.modelVersion, F.pinned.string)
    }

    func testOllamaTagsPinTheDigestAndQuantisation() async throws {
        let tags = #"{"models":[{"name":"gemma3:4b","digest":"ffff","details":{}},{"name":"qwen3.5:4b","model":"qwen3.5:4b","digest":"sha256:1a2b3c4d5e6f7a8b9c0d","details":{"quantization_level":"Q4_K_M","parameter_size":"4B"}}]}"#
        let http = StubLocalHTTP(json: tags)
        let v = try await LANPlanner.identifyOllama(F.endpoint(), http: http)
        XCTAssertEqual(v.string, "qwen3.5:4b@1a2b3c4d5e6f Q4_K_M")
        XCTAssertTrue(v.isPinned)
        XCTAssertEqual(http.sent.first?.method, "GET")
        XCTAssertEqual(http.sent.first?.url.absoluteString, "http://mac.local:11434/api/tags")
        let latest = try LocalModelVersion.ollama(tags: Data(#"{"models":[{"name":"phi4:latest","digest":"abcdef1234567890"}]}"#.utf8), model: "phi4")
        XCTAssertEqual(latest.checkpoint, "abcdef123456")
        XCTAssertThrowsError(try LocalModelVersion.ollama(tags: Data(tags.utf8), model: "mistral:7b")) {
            XCTAssertEqual($0 as? LocalPlannerError, .modelNotFound(model: "mistral:7b"))
        }
    }

    func testAHuggingFaceSnapshotPinsTheCommit() {
        let commit = "0123456789abcdef0123456789abcdef01234567"
        let one = LocalModelVersion.huggingFace(repository: "mlx-community/Qwen3-1.7B-4bit", snapshots: [commit, ".DS_Store"])
        XCTAssertEqual(one.string, "mlx-community/Qwen3-1.7B-4bit@0123456789ab 4bit")
        XCTAssertTrue(one.isPinned)
        let two = LocalModelVersion.huggingFace(repository: "mlx-community/Qwen3-1.7B-4bit", snapshots: [commit, String(commit.reversed())])
        XCTAssertFalse(two.isPinned, "two snapshots: which one loaded cannot be told")
        XCTAssertFalse(LocalModelVersion.huggingFace(repository: "a/b", snapshots: []).isPinned)
    }

    func testWhatCountsAsPinned() {
        XCTAssertTrue(LocalModelVersion.isPinned("qwen3.5:4b@1a2b3c4d5e6f Q4_K_M"))
        XCTAssertTrue(LocalModelVersion.isPinned("a/b@0123456"))
        XCTAssertFalse(LocalModelVersion.isPinned("qwen3.5:4b"))
        XCTAssertFalse(LocalModelVersion.isPinned("qwen3.5:4b@ab"))
        XCTAssertFalse(LocalModelVersion.isPinned("qwen3.5:4b@ Q4"))
    }

    // MARK: who it is

    func testInfoForAComputerOnYourNetwork() throws {
        let p = try F.planner(StubLocalHTTP(json: "{}"), base: "http://192.168.1.20:11434/v1", key: "my-own-token-123")
        XCTAssertEqual(p.info.id, "lan.qwen3.5:4b")
        XCTAssertEqual(p.info.runsOn, .lanComputer)
        XCTAssertEqual(p.info.key, .none, "a token for your own server is not a vendor key")
        XCTAssertEqual(p.info.framesSent, .none, "local planners are text only in v1")
        XCTAssertEqual(p.info.decisionDeadline, .seconds(15))
        XCTAssertEqual(p.info.label, "On your own computer. Slower.")
        XCTAssertEqual(p.info.realDuck, .off)
    }

    func testInfoForAnotherAppOnThisPhone() throws {
        let p = try F.planner(StubLocalHTTP(json: "{}"), base: "http://localhost:8080/v1")
        XCTAssertEqual(p.info.runsOn, .thisPhone)
        XCTAssertEqual(p.info.id, "phone.qwen3.5:4b")
    }

    func testARelayIsNotALocalModel() throws {
        let e = F.endpoint("http://pi.local:8080/v1", key: "my-own-token-123", relay: true)
        let p = try LANPlanner(endpoint: e, version: F.pinned, http: StubLocalHTTP(json: "{}"))
        XCTAssertEqual(p.info.runsOn, .hosted(vendor: "pi.local"))
        XCTAssertEqual(p.info.key, .byok(provider: "pi.local"))
    }

    func testOnARealDuckOnlyThisPhonesPlannersGetSkills() {
        XCTAssertFalse(AllowedDecisions.forDuck(.real, runsOn: .lanComputer, robotSkills: ["sit"]).kinds.contains(.skill))
        XCTAssertEqual(AllowedDecisions.forDuck(.sim, runsOn: .thisPhone).kinds, [.walk, .turn, .ask, .done, .stop])
    }

    func testEndpointsThatAreNotServersAreRefused() {
        let mlx = ModelEndpoint(name: "m", kind: .downloadedMLX, model: "a/b")
        XCTAssertThrowsError(try LANPlanner(endpoint: mlx, version: F.pinned, http: StubLocalHTTP(json: "{}")))
        let plain = F.endpoint("http://example.com/v1")
        XCTAssertThrowsError(try LANPlanner(endpoint: plain, version: F.pinned, http: StubLocalHTTP(json: "{}"))) {
            XCTAssertEqual($0 as? ModelEndpoint.Refusal, .plaintextToThePublicInternet(host: "example.com"))
        }
    }

    // MARK: helpers

    static func branchKinds(_ schema: [String: Any]) throws -> [String] {
        let branches = try XCTUnwrap(schema["anyOf"] as? [[String: Any]])
        return branches.compactMap { (($0["properties"] as? [String: Any])?["kind"] as? [String: Any])?["enum"] as? [String] }
            .flatMap { $0 }
    }

    static func assertThrows(_ expected: LocalPlannerError, file: StaticString = #filePath, line: UInt = #line,
                             _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("did not throw \(expected)", file: file, line: line)
        } catch let e as LocalPlannerError {
            XCTAssertEqual(e, expected, file: file, line: line)
        } catch {
            XCTFail("threw \(error), not \(expected)", file: file, line: line)
        }
    }
}
