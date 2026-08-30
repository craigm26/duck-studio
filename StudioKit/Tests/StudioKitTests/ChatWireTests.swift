import XCTest
@testable import StudioKit

final class ChatWireTests: XCTestCase {

    // MARK: - endpoints

    func testALocalOllamaEndpointIsAccepted() throws {
        var endpoint = ModelEndpoint(name: "Pi", kind: .openAICompatible,
                                     baseURL: "http://100.122.199.6:11434/v1",
                                     model: "gemma4:e4b-it-qat")
        XCTAssertNoThrow(try endpoint.validate())
        XCTAssertEqual(try endpoint.chatURL().absoluteString,
                       "http://100.122.199.6:11434/v1/chat/completions")
        XCTAssertEqual(try endpoint.modelsURL().absoluteString,
                       "http://100.122.199.6:11434/v1/models")
        // A trailing slash is a thing people type.
        endpoint.baseURL = "http://100.122.199.6:11434/v1/"
        XCTAssertEqual(try endpoint.chatURL().absoluteString,
                       "http://100.122.199.6:11434/v1/chat/completions")
    }

    /// Tailscale's 100.x is as private as 192.168.x, and a duck owner reaching
    /// their Pi over a tailnet must not be pushed onto plaintext-to-the-world
    /// or onto nothing.
    func testWhatCountsAsYourOwnNetwork() {
        for host in ["localhost", "127.0.0.1", "::1", "duck.local", "192.168.1.20",
                     "10.0.0.5", "172.20.0.1", "100.122.199.6", "169.254.1.1"] {
            XCTAssertTrue(ModelEndpoint.isLocalHost(host), host)
        }
        for host in ["api.openai.com", "8.8.8.8", "172.32.0.1", "100.128.0.1", "example.com"] {
            XCTAssertFalse(ModelEndpoint.isLocalHost(host), host)
        }
    }

    func testPlaintextOffYourNetworkIsRefused() {
        let endpoint = ModelEndpoint(name: "Somewhere", kind: .openAICompatible,
                                     baseURL: "http://example.com/v1", model: "m")
        XCTAssertThrowsError(try endpoint.validate()) { error in
            XCTAssertEqual(error as? ModelEndpoint.Refusal,
                           .plaintextToThePublicInternet(host: "example.com"))
        }
        // The same host over https is fine.
        let secure = ModelEndpoint(name: "Somewhere", kind: .openAICompatible,
                                   baseURL: "https://example.com/v1", model: "m")
        XCTAssertNoThrow(try secure.validate())
    }

    func testTheMissingVersionPathIsNamed() {
        let endpoint = ModelEndpoint(name: "Pi", kind: .openAICompatible,
                                     baseURL: "http://duck.local:11434", model: "m")
        XCTAssertThrowsError(try endpoint.validate()) { error in
            guard case .missingVersionPath? = error as? ModelEndpoint.Refusal else {
                return XCTFail("expected the /v1 refusal, got \(error)")
            }
        }
    }

    /// A person deserves to know whether their sentence left the building.
    func testPrivacyNoteSaysWhereTheWordsGo() {
        XCTAssertEqual(ModelEndpoint.onDevice.privacyNote, "Nothing you type leaves this phone.")
        let phone = ModelEndpoint(name: "On here", kind: .openAICompatible,
                                  baseURL: "http://localhost:8080/v1", model: "m")
        XCTAssertTrue(phone.privacyNote.contains("another app on this phone"))
        let pi = ModelEndpoint(name: "Pi", kind: .openAICompatible,
                               baseURL: "http://100.122.199.6:11434/v1", model: "m")
        XCTAssertTrue(pi.privacyNote.contains("your own network"))
        let cloud = ModelEndpoint(name: "Cloud", kind: .openAICompatible,
                                  baseURL: "https://api.example.com/v1", model: "m")
        XCTAssertTrue(cloud.privacyNote.contains("over the internet"))
    }

    /// The default timeout is set by a measurement, not a habit: a 7.5B Gemma
    /// at Q4 on a CPU-only Pi 5 took 766 s to write one motion draft. The
    /// usual 60 s — and the 300 s this first shipped with — would have failed
    /// it, which reads as a broken server rather than a slow one.
    func testTheDefaultTimeoutOutlastsAPiWritingADraft() {
        XCTAssertGreaterThan(ModelEndpoint(name: "x", kind: .openAICompatible).timeout, 766)
    }

    // MARK: - the request

    func testTheRequestBodyIsWhatEveryServerExpects() throws {
        let data = try ChatWire.requestBody(model: "gemma4:e4b-it-qat",
                                            instructions: "be brief", prompt: "bow")
        let top = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(top["model"] as? String, "gemma4:e4b-it-qat")
        XCTAssertEqual(top["stream"] as? Bool, false)
        let messages = try XCTUnwrap(top["messages"] as? [[String: String]])
        XCTAssertEqual(messages.map { $0["role"] }, ["system", "user"])
        XCTAssertEqual(messages.last?["content"], "bow")
    }

    // MARK: - the reply, in all its costumes

    func testAPlainReply() throws {
        let body = #"{"choices":[{"message":{"role":"assistant","content":"{\"name\":\"Bow\"}"}}]}"#
        XCTAssertEqual(try ChatWire.content(from: Data(body.utf8)), "{\"name\":\"Bow\"}")
    }

    func testAServerErrorIsQuoted() {
        let body = #"{"error":{"message":"model 'nope' not found"}}"#
        XCTAssertThrowsError(try ChatWire.content(from: Data(body.utf8))) { error in
            XCTAssertEqual(error as? ChatWire.WireError,
                           .serverSaid("model 'nope' not found"))
        }
    }

    func testJSONInsideAMarkdownFence() throws {
        let reply = "Sure! Here's the motion:\n```json\n{\"name\":\"Bow\",\"keys\":[]}\n```\nHope that helps."
        XCTAssertEqual(try ChatWire.firstJSONObject(in: reply), "{\"name\":\"Bow\",\"keys\":[]}")
    }

    func testJSONAfterAParagraphOfProse() throws {
        let reply = "I think a bow works best here. {\"name\":\"Bow\",\"keys\":[]}"
        XCTAssertEqual(try ChatWire.firstJSONObject(in: reply), "{\"name\":\"Bow\",\"keys\":[]}")
    }

    /// A reasoning model's scratchpad routinely contains a REJECTED draft.
    /// Taking the first object without stripping picks the wrong one.
    func testTheThinkBlockIsStrippedBeforeScanning() throws {
        let reply = """
        <think>Maybe {"name":"Wrong","keys":[1]} — no, the neck should lead.</think>
        {"name":"Right","keys":[]}
        """
        XCTAssertEqual(try ChatWire.firstJSONObject(in: reply), "{\"name\":\"Right\",\"keys\":[]}")
    }

    /// Cut off mid-thought by a token limit: there is an opening tag and no
    /// closing one, and everything after it is scratchpad.
    func testAnUnclosedThinkBlockTakesTheRestWithIt() {
        let reply = "<think>Let me consider {\"name\":\"Draft\"}"
        XCTAssertThrowsError(try ChatWire.firstJSONObject(in: reply))
    }

    /// A brace inside a string must not end the object.
    func testBracesInsideStringsSurvive() throws {
        let reply = #"{"name":"A } brace","keys":[]}"#
        XCTAssertEqual(try ChatWire.firstJSONObject(in: reply), reply)
    }

    func testNestedObjectsComeBackWhole() throws {
        let reply = "prose {\"a\":{\"b\":{\"c\":1}},\"d\":2} more prose"
        XCTAssertEqual(try ChatWire.firstJSONObject(in: reply), "{\"a\":{\"b\":{\"c\":1}},\"d\":2}")
    }

    func testAReplyWithNoJSONQuotesWhatItSaid() {
        XCTAssertThrowsError(try ChatWire.firstJSONObject(in: "I cannot help with that.")) { error in
            XCTAssertEqual(error as? ChatWire.WireError,
                           .noJSONInReply("I cannot help with that."))
        }
    }

    // MARK: - into a proposal

    func testAMotionComesOutOfJSON() throws {
        let json = """
        {"name":"Bow","keys":[{"atSeconds":0,"mouthOpen":0,"moves":[{"joint":"neck","degrees":20}]},
                              {"atSeconds":1.5,"mouthOpen":0,"moves":[{"joint":"neck","degrees":0}]}]}
        """
        let proposal = try ChatDraft.motion(fromJSON: json)
        XCTAssertEqual(proposal.name, "Bow")
        XCTAssertEqual(proposal.keys.count, 2)
        XCTAssertEqual(proposal.keys.first?.moves.first?.joint, "neck")
        XCTAssertEqual(proposal.keys.first?.moves.first?.degrees, 20)
    }

    /// Small models quote their numbers about a third of the time. Refusing a
    /// quoted 20 would be refusing a correct answer on a technicality.
    func testQuotedNumbersAreAccepted() throws {
        let json = #"{"name":"Bow","keys":[{"atSeconds":"0.5","moves":[{"joint":"neck","degrees":"20"}]}]}"#
        let proposal = try ChatDraft.motion(fromJSON: json)
        XCTAssertEqual(proposal.keys.first?.atSeconds, 0.5)
        XCTAssertEqual(proposal.keys.first?.moves.first?.degrees, 20)
    }

    func testARuleComesOutOfJSON() throws {
        let json = #"{"name":"Greet","predicate":"nearer","value":1.5,"intent":"wave"}"#
        let rule = try ChatDraft.rule(fromJSON: json)
        XCTAssertEqual(rule.predicate, "nearer")
        XCTAssertEqual(rule.value, 1.5)
        XCTAssertEqual(rule.intent, "wave")
    }

    /// The model estimates the object. It does NOT get to say whether the duck
    /// can pick it up — that is decided against measurements, offline.
    func testTheModelSizesTheObjectAndTheCodeJudgesIt() throws {
        let json = #"{"object":"pencil","grams":6,"thicknessMillimetres":7,"metresAway":1.2}"#
        let (object, stick) = try ChatDraft.stick(fromJSON: json)
        XCTAssertEqual(object, "pencil")
        let plan = Retrieval.plan(for: stick)
        XCTAssertFalse(plan.isPossible)
        XCTAssertEqual(plan.refusals.first, .tooThin(millimetres: 7))
    }

    func testAMissingFieldIsNamed() {
        XCTAssertThrowsError(try ChatDraft.rule(fromJSON: #"{"name":"x"}"#)) { error in
            XCTAssertEqual(error as? ChatDraft.DraftError, .missing("predicate"))
        }
    }
}

/// The reasoning-model failure, which is the one that actually happens.
extension ChatWireTests {

    /// Measured on this Pi: qwen3.5:2b spent 725 s and its whole 900-token
    /// budget thinking, then answered with an empty string. Without a specific
    /// message for it, the app says "replied without any JSON in it. It said:"
    /// and then nothing, which helps nobody.
    func testAModelThatThoughtItselfOutOfRoomSaysSo() {
        let body = """
        {"choices":[{"finish_reason":"length","message":{"role":"assistant","content":"",
         "reasoning":"Thinking Process: the user wants a bow, so I should"}}]}
        """
        XCTAssertThrowsError(try ChatWire.content(from: Data(body.utf8))) { error in
            XCTAssertEqual(error as? ChatWire.WireError, .spentItAllThinking)
            XCTAssertTrue(ChatWire.WireError.spentItAllThinking.message.contains("suppress reasoning"))
        }
    }

    /// But if the JSON is IN the scratchpad, it is still an answer. Throwing it
    /// away to be strict about which field it arrived in loses work for nothing.
    func testJSONFoundInTheReasoningBlockIsAccepted() throws {
        let body = """
        {"choices":[{"finish_reason":"length","message":{"role":"assistant","content":"",
         "reasoning":"Let me write it: {\\"name\\":\\"Bow\\",\\"keys\\":[]}"}}]}
        """
        let text = try ChatWire.content(from: Data(body.utf8))
        XCTAssertEqual(try ChatWire.firstJSONObject(in: text), #"{"name":"Bow","keys":[]}"#)
    }

    /// `reasoning_content` is the other server's spelling of the same field.
    func testTheOtherSpellingOfTheReasoningField() {
        let body = """
        {"choices":[{"finish_reason":"length","message":{"role":"assistant","content":"",
         "reasoning_content":"thinking out loud with no answer"}}]}
        """
        XCTAssertThrowsError(try ChatWire.content(from: Data(body.utf8))) { error in
            XCTAssertEqual(error as? ChatWire.WireError, .spentItAllThinking)
        }
    }

    /// Cut off mid-answer with no complete object is its own message: the
    /// remedy is more tokens, not a different model.
    func testATruncatedAnswerIsNamedAsTruncated() {
        let body = #"{"choices":[{"finish_reason":"length","message":{"content":"{\"name\":\"Bo"}}]}"#
        XCTAssertThrowsError(try ChatWire.content(from: Data(body.utf8))) { error in
            guard case .cutOffAtTokenLimit? = error as? ChatWire.WireError else {
                return XCTFail("expected truncation, got \(error)")
            }
        }
    }

    /// A complete object that merely happened to end at the limit is fine.
    func testALimitStopWithCompleteJSONIsStillAnAnswer() throws {
        let body = #"{"choices":[{"finish_reason":"length","message":{"content":"{\"name\":\"Bow\",\"keys\":[]}"}}]}"#
        XCTAssertEqual(try ChatWire.content(from: Data(body.utf8)), #"{"name":"Bow","keys":[]}"#)
    }

    /// The switch that fixes it. `chat_template_kwargs.enable_thinking` and
    /// Ollama's own `think` flag were both tried through this route and did
    /// nothing; `reasoning_effort` is what works.
    func testReasoningIsSuppressedByDefaultAndCanBeTurnedOff() throws {
        let on = try JSONSerialization.jsonObject(
            with: ChatWire.requestBody(model: "m", instructions: "i", prompt: "p")) as? [String: Any]
        XCTAssertEqual(on?["reasoning_effort"] as? String, "none")
        let off = try JSONSerialization.jsonObject(
            with: ChatWire.requestBody(model: "m", instructions: "i", prompt: "p",
                                       suppressReasoning: false)) as? [String: Any]
        XCTAssertNil(off?["reasoning_effort"])
    }

    func testEndpointsSuppressReasoningByDefault() {
        XCTAssertTrue(ModelEndpoint(name: "x", kind: .openAICompatible).suppressReasoning)
    }
}
