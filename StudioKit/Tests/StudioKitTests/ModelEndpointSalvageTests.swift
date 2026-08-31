import XCTest
@testable import StudioKit

/// Reading the saved list of models back, and what happens when one row of it
/// is rubbish.
///
/// THE BUG THIS FILE STANDS AGAINST IS TOTAL AND SILENT. A JSON array decodes
/// all-or-nothing, so one unreadable element used to throw for the whole array;
/// the `try?` around it turned that into nil, every endpoint a person had
/// configured disappeared, Apple's on-device model was quietly selected in
/// their place, and nothing on any screen said a word. The only way to notice
/// was to go looking.
final class ModelEndpointSalvageTests: XCTestCase {

    private let ollama = ModelEndpoint(name: "Ollama", kind: .openAICompatible,
                                       baseURL: "http://192.168.1.10:11434/v1",
                                       model: "gemma4:e4b-it-qat")
    private let bridge = ModelEndpoint(name: "Claude", kind: .openAICompatible,
                                       baseURL: "http://192.168.1.10:8780/v1",
                                       model: "sonnet", timeout: 300, relay: true)

    private func element(_ endpoint: ModelEndpoint) -> String {
        let data = try! JSONEncoder().encode(endpoint)
        return String(data: data, encoding: .utf8)!
    }

    private func stored(_ parts: [String]) -> Data {
        Data(("[" + parts.joined(separator: ",") + "]").utf8)
    }

    // MARK: - the ordinary day

    func testAWholeReadableListComesBackWithNothingLostAndNothingToSay() {
        let salvage = ModelEndpoint.decodeList(from: stored([element(ollama), element(bridge)]))
        XCTAssertEqual(salvage.endpoints, [ollama, bridge])
        XCTAssertEqual(salvage.unreadable, 0)
        XCTAssertNil(salvage.note)
    }

    func testAnEmptyStoredListIsNotAFailure() {
        let salvage = ModelEndpoint.decodeList(from: stored([]))
        XCTAssertEqual(salvage.endpoints, [])
        XCTAssertEqual(salvage.unreadable, 0)
        XCTAssertNil(salvage.note)
    }

    // MARK: - one bad row

    /// A row written by an older or newer build, missing a field this one
    /// requires. The other endpoints survive it.
    func testOneUnreadableRowLosesThatRowAndNothingElse() {
        let salvage = ModelEndpoint.decodeList(
            from: stored([element(ollama), "{\"name\":\"half a row\"}", element(bridge)]))
        XCTAssertEqual(salvage.endpoints, [ollama, bridge])
        XCTAssertEqual(salvage.unreadable, 1)
        XCTAssertEqual(salvage.note,
            "1 saved model could not be read and has been left out of this list. Everything else "
            + "survived — add it again with the address and model name that server uses.")
    }

    /// THE TERMINATION TEST, and it is not a formality. A failed decode leaves
    /// an unkeyed container's cursor exactly where it was, so the obvious
    /// version of this loop spins on the first bad row forever and hangs the
    /// app on launch. If that ever comes back, this test never finishes.
    func testABadRowAtTheFrontDoesNotSwallowTheGoodOnesBehindIt() {
        let salvage = ModelEndpoint.decodeList(
            from: stored(["{}", element(ollama), element(bridge)]))
        XCTAssertEqual(salvage.endpoints, [ollama, bridge])
        XCTAssertEqual(salvage.unreadable, 1)
    }

    /// A null and a bare string are both things a cursor has to be stepped
    /// over, by two different routes.
    func testANullAndAStringAreCountedAndSteppedOver() {
        let salvage = ModelEndpoint.decodeList(
            from: stored(["null", element(ollama), "\"not an endpoint\""]))
        XCTAssertEqual(salvage.endpoints, [ollama])
        XCTAssertEqual(salvage.unreadable, 2)
        XCTAssertEqual(salvage.note,
            "2 saved models could not be read and have been left out of this list. Everything "
            + "else survived — add them again with the addresses and model names those servers "
            + "use.")
    }

    // MARK: - the whole thing is rubbish

    /// nil IS NOT ZERO. Nobody can say how many endpoints were in a blob that
    /// is not a list, so the note refuses to name a number.
    func testStorageThatIsNotAListAtAllRefusesToGuessHowManyWereLost() {
        let salvage = ModelEndpoint.decodeList(from: Data("{\"oops\":true}".utf8))
        XCTAssertEqual(salvage.endpoints, [])
        XCTAssertNil(salvage.unreadable)
        XCTAssertEqual(salvage.note,
            "The saved list of models could not be read at all, so this has started again with "
            + "Apple's on-device model. Add your own addresses back and they will save as before.")
    }

    func testStorageThatIsNotEvenJSONIsTheSameStory() {
        let salvage = ModelEndpoint.decodeList(from: Data("nonsense".utf8))
        XCTAssertEqual(salvage.endpoints, [])
        XCTAssertNil(salvage.unreadable)
        XCTAssertNotNil(salvage.note)
    }

    // MARK: - the round trip the app actually makes

    func testWhatTheAppSavesIsWhatTheAppReadsBack() {
        let saved = try! JSONEncoder().encode([ModelEndpoint.onDevice, ollama, bridge])
        let salvage = ModelEndpoint.decodeList(from: saved)
        XCTAssertEqual(salvage.endpoints, [.onDevice, ollama, bridge])
        XCTAssertEqual(salvage.unreadable, 0)
    }
}
