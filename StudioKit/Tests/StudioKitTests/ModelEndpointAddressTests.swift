import XCTest
@testable import StudioKit

/// The address half of an endpoint, checked on its own.
///
/// THE BUG THIS FILE PINS SHUT WAS A CIRCLE. `modelsURL()` — the address of the
/// list a server keeps of its own models — ran the full `validate()`, so asking
/// a server what models it has was refused with "Name the model as the server
/// names it. Ask the server for its list — /v1/models — if you are not sure."
/// The app was sending somebody to do the exact thing it had just refused to
/// do, and both "Ask what models it has" and "Check this address" were dead at
/// the only moment they are wanted: a brand new endpoint, before anything about
/// that machine is known.
final class ModelEndpointAddressTests: XCTestCase {

    /// What the editor holds a second after a preset is tapped: a real address
    /// and no model name yet.
    private let fresh = ModelEndpoint(name: "Ollama", kind: .openAICompatible,
                                      baseURL: "http://192.168.1.10:11434/v1", model: "")

    private func refusal(_ body: @autoclosure () throws -> Any) -> ModelEndpoint.Refusal? {
        do {
            _ = try body()
            return nil
        } catch let refusal as ModelEndpoint.Refusal {
            return refusal
        } catch {
            return nil
        }
    }

    // MARK: - the circle, broken

    func testAnEndpointWithNoModelNameYetStillHasAModelListToAsk() {
        XCTAssertEqual(try fresh.modelsURL().absoluteString,
                       "http://192.168.1.10:11434/v1/models")
    }

    /// The name is a label for a list on a screen. It has nothing to do with
    /// whether an address can be reached.
    func testAnEndpointWithNoNameYetCanStillBeChecked() {
        var unnamed = fresh
        unnamed.name = ""
        XCTAssertEqual(try unnamed.modelsURL().absoluteString,
                       "http://192.168.1.10:11434/v1/models")
    }

    /// Saving still wants both, and in the same order it always did: an
    /// endpoint with neither is missing a model name first.
    func testSavingStillWantsANameAndAModelAndInThatOrder() {
        XCTAssertEqual(refusal(try fresh.validate()), .emptyModel)
        var nameless = fresh
        nameless.name = ""
        nameless.baseURL = "not an address"
        XCTAssertEqual(refusal(try nameless.validate()), .emptyName)
        var unmodelled = fresh
        unmodelled.baseURL = "not an address"
        XCTAssertEqual(refusal(try unmodelled.validate()), .emptyModel)
    }

    /// Chatting genuinely cannot happen without a model id, so that half of the
    /// check is untouched.
    func testChattingStillNeedsAModelName() {
        XCTAssertEqual(refusal(try fresh.chatURL()), .emptyModel)
    }

    // MARK: - and no hole opened by the split

    /// THE REFUSAL THAT MUST SURVIVE. The check is a real outbound request, so
    /// the rule against sending plaintext off your own network has to hold for
    /// it exactly as it holds for a draft.
    func testTheCheckWillNotSendPlaintextOffYourOwnNetwork() {
        var public_ = fresh
        public_.baseURL = "http://api.example.com/v1"
        XCTAssertEqual(refusal(try public_.modelsURL()),
                       .plaintextToThePublicInternet(host: "api.example.com"))
    }

    func testTheCheckStillWantsTheVersionPathOnTheEnd() {
        var noVersion = fresh
        noVersion.baseURL = "http://192.168.1.10:11434"
        XCTAssertEqual(refusal(try noVersion.modelsURL()),
                       .missingVersionPath("http://192.168.1.10:11434"))
    }

    func testTheCheckStillRefusesSomethingThatIsNotAnAddress() {
        var nonsense = fresh
        nonsense.baseURL = "192.168.1.10"
        XCTAssertEqual(refusal(try nonsense.modelsURL()), .notAURL("192.168.1.10"))
    }

    /// https off your own network is fine, with or without a model name.
    func testAHostedEndpointOverHTTPSCanBeCheckedBeforeAModelIsChosen() {
        var hosted = fresh
        hosted.baseURL = "https://api.example.com/v1"
        XCTAssertEqual(try hosted.modelsURL().absoluteString,
                       "https://api.example.com/v1/models")
    }
}
