import XCTest
@testable import StudioKit

/// A third model kind touches every switch that used to have two arms, and
/// several that were written as a guard and silently passed anything else.
final class DownloadedModelKindTests: XCTestCase {

    private func downloaded(_ repository: String = "mlx-community/Qwen3-1.7B-4bit")
        -> ModelEndpoint {
        ModelEndpoint(name: "On this phone", kind: .downloadedMLX, baseURL: "",
                      model: repository)
    }

    // MARK: - every kind, swept

    /// CaseIterable exists so a FOURTH kind fails here rather than shipping
    /// with a blank privacy note.
    func testEveryKindSaysWhereTheWordsGo() {
        for kind in ModelEndpoint.Kind.allCases {
            let endpoint = ModelEndpoint(name: "x", kind: kind,
                                         baseURL: "http://192.168.1.10:1234/v1", model: "m")
            XCTAssertFalse(endpoint.privacyNote.isEmpty, kind.rawValue)
        }
    }

    /// THE ONE DIFFERENCE FROM APPLE'S SENTENCE IS DELIBERATE. The weights came
    /// over the network once, and somebody who just spent two gigabytes should
    /// not be told flatly that nothing leaves the phone.
    func testADownloadedModelSaysNothingLeavesButAdmitsTheDownload() {
        let note = downloaded().privacyNote
        XCTAssertTrue(note.contains("Nothing you type leaves it"), note)
        XCTAssertTrue(note.contains("downloaded from Hugging Face once"), note)
        XCTAssertNotEqual(note, ModelEndpoint.onDevice.privacyNote)
    }

    // MARK: - what it refuses

    func testARepositoryIdIsRequiredAndMustLookLikeOne() {
        for bad in ["", "   ", "Qwen3-1.7B-4bit", "a/b/c", "/b", "a/"] {
            XCTAssertThrowsError(try downloaded(bad).validate(), bad) { error in
                guard case .notARepository? = error as? ModelEndpoint.Refusal else {
                    return XCTFail("\(bad) gave \(error)")
                }
            }
        }
        XCTAssertNoThrow(try downloaded().validate())
    }

    /// THE NAME COMES FIRST, the same order the HTTP kind pins.
    func testAnUnnamedDownloadedModelIsRefusedForItsNameFirst() {
        var endpoint = downloaded("")
        endpoint.name = ""
        XCTAssertThrowsError(try endpoint.validate()) {
            XCTAssertEqual($0 as? ModelEndpoint.Refusal, .emptyName)
        }
    }

    /// A MODEL ON THIS PHONE CANNOT FORWARD ANYWHERE. The relay branch of
    /// `privacyNote` is the most alarming sentence in the app to fire falsely.
    func testADownloadedModelCannotBeARelay() {
        var endpoint = downloaded()
        endpoint.relay = true
        XCTAssertThrowsError(try endpoint.validate()) {
            XCTAssertEqual($0 as? ModelEndpoint.Refusal, .relayOnADownloadedModel)
        }
    }

    /// AN ADDRESSLESS KIND MUST FAIL LOUDLY. Before this, `validate()` returned
    /// cleanly and the empty baseURL produced the relative URL
    /// "/chat/completions" — a mistake that surfaces as a network error
    /// somewhere else entirely.
    func testAskingADownloadedModelForAnAddressIsARefusalNotARelativeURL() {
        XCTAssertThrowsError(try downloaded().chatURL()) { error in
            guard case .notAnAddress? = error as? ModelEndpoint.Refusal else {
                return XCTFail("\(error)")
            }
        }
        XCTAssertThrowsError(try downloaded().modelsURL())
        XCTAssertThrowsError(try ModelEndpoint.onDevice.chatURL())
    }

    /// And it does not inherit the HTTP kind's address rules, which it has no
    /// address to satisfy.
    func testAnAddresslessKindPassesTheAddressCheck() {
        XCTAssertNoThrow(try downloaded().validateAddress())
        XCTAssertNoThrow(try ModelEndpoint.onDevice.validateAddress())
    }

    // MARK: - storage

    /// THE RAW VALUE IS PERMANENT. A stored endpoint carries it, so renaming
    /// the case would orphan every saved row.
    func testTheStoredNameIsTheOneOlderBuildsWillSee() throws {
        let text = String(decoding: try JSONEncoder().encode(downloaded()), as: UTF8.self)
        XCTAssertTrue(text.contains("\"kind\":\"downloadedMLX\""), text)
    }

    /// THE DOWNGRADE PATH, which had no coverage. Somebody installs this build,
    /// saves a downloaded model, then reinstalls an older one: that build
    /// cannot decode the row. The other rows must survive and the loss must be
    /// counted, which is exactly what the salvage reader is for.
    func testAnOlderBuildLosesOnlyTheRowItCannotRead() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Ollama","kind":"openAICompatible",
          "baseURL":"http://192.168.1.10:11434/v1","model":"gemma","timeout":60,
          "suppressReasoning":true,"relay":false},
         {"id":"\(UUID().uuidString)","name":"Phone","kind":"somethingLater",
          "baseURL":"","model":"a/b","timeout":60,
          "suppressReasoning":true,"relay":false}]
        """.data(using: .utf8)!
        let salvage = ModelEndpoint.decodeList(from: json)
        XCTAssertEqual(salvage.endpoints.map(\.name), ["Ollama"])
        XCTAssertEqual(salvage.unreadable, 1)
        XCTAssertNotNil(salvage.note)
    }

    // MARK: - the catalogue and the kind agree

    /// Every model this app offers to download must be a valid endpoint, or the
    /// picker builds one the editor would refuse.
    func testEveryCataloguedModelMakesAValidEndpoint() throws {
        for model in PhoneModel.catalogue {
            let endpoint = ModelEndpoint(name: model.name, kind: .downloadedMLX,
                                         baseURL: "", model: model.repository)
            XCTAssertNoThrow(try endpoint.validate(), model.repository)
        }
    }
}
