import XCTest
@testable import StudioKit

/// Every message here is transcribed from `mediad/webclient/index.html`, the
/// client the robot serves — so these tests are written against the shapes
/// that page actually puts on the wire, not against a reading of the docs.
final class DuckSignallingTests: XCTestCase {

    func testTheServerIsWhereTheDesignNoteSaysItIs() {
        XCTAssertEqual(DuckSignalling.port, 8443)
        XCTAssertEqual(DuckSignalling.url(host: "duck.local")?.absoluteString,
                       "ws://duck.local:8443")
    }

    func testWelcomeIsAnsweredWithAListThatTakesNoFields() throws {
        guard case .welcome(let id) = DuckSignalling.read(Data(#"{"type":"welcome","peerId":"7"}"#.utf8))
        else { return XCTFail("welcome") }
        XCTAssertEqual(id, "7")
        let list = try XCTUnwrap(try JSONSerialization.jsonObject(with: DuckSignalling.list())
                                    as? [String: Any])
        XCTAssertEqual(list["type"] as? String, "list")
        XCTAssertEqual(list.count, 1, "`list` takes no fields")
    }

    /// The producer's meta names the robot before a session exists.
    func testAProducerCarriesTheRobotsNameBeforeAnyVideo() {
        let said = Data(#"""
        {"type":"list","producers":[{"id":"p1","meta":{"name":"Kevin","release":"1.4.0",
         "api_version":3}}]}
        """#.utf8)
        guard case .producers(let found) = DuckSignalling.read(said) else {
            return XCTFail("producers")
        }
        XCTAssertEqual(found, [DuckSignalling.Producer(id: "p1", name: "Kevin",
                                                       release: "1.4.0", apiVersion: "3")])
    }

    /// An empty list is a pipeline that did not start, which is a different
    /// thing from a robot without a camera — the case exists so a screen can
    /// say the right one.
    func testAnEmptyProducerListIsStillAList() {
        guard case .producers(let found) =
                DuckSignalling.read(Data(#"{"type":"list","producers":[]}"#.utf8))
        else { return XCTFail("producers") }
        XCTAssertTrue(found.isEmpty)
    }

    /// The shape the reference client warns about: one `peer` type, two
    /// payloads, flattened beside the session id.
    func testPeerCarriesEitherAnSdpOrACandidate() {
        let offer = Data(#"{"type":"peer","sessionId":"s1","sdp":{"type":"offer","sdp":"v=0..."}}"#.utf8)
        guard case .sdp(let session, let kind, let body) = DuckSignalling.read(offer) else {
            return XCTFail("sdp")
        }
        XCTAssertEqual([session, kind, body], ["s1", "offer", "v=0..."])

        let ice = Data(#"{"type":"peer","sessionId":"s1","ice":{"candidate":"a=x","sdpMLineIndex":0}}"#.utf8)
        guard case .ice(let s, let candidate, let index) = DuckSignalling.read(ice) else {
            return XCTFail("ice")
        }
        XCTAssertEqual(s, "s1")
        XCTAssertEqual(candidate, "a=x")
        XCTAssertEqual(index, 0)
    }

    func testWhatThisAppSendsIsTheShapeThePageSends() throws {
        let start = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: DuckSignalling.startSession(with: "p1")) as? [String: Any])
        XCTAssertEqual(start["type"] as? String, "startSession")
        XCTAssertEqual(start["peerId"] as? String, "p1")

        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: DuckSignalling.answer(sessionId: "s1", sdp: "v=0...")) as? [String: Any])
        XCTAssertEqual(answer["type"] as? String, "peer")
        XCTAssertEqual(answer["sessionId"] as? String, "s1")
        let sdp = try XCTUnwrap(answer["sdp"] as? [String: Any])
        XCTAssertEqual(sdp["type"] as? String, "answer",
                       "the producer offers and this app answers")
        XCTAssertEqual(sdp["sdp"] as? String, "v=0...")

        let ice = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: DuckSignalling.candidate(sessionId: "s1", candidate: "a=x",
                                           sdpMLineIndex: 2)) as? [String: Any])
        let body = try XCTUnwrap(ice["ice"] as? [String: Any])
        XCTAssertEqual(body["candidate"] as? String, "a=x")
        XCTAssertEqual(body["sdpMLineIndex"] as? Int, 2)
        XCTAssertEqual(body.count, 2, "both fields, and nothing else")
    }

    /// A message from a newer server is not an error. A client that threw on
    /// one would break on an upgrade it did not need to care about.
    func testAMessageThisAppDoesNotKnowIsNotAFailure() {
        guard case .unknown(let type) =
                DuckSignalling.read(Data(#"{"type":"somethingNew","x":1}"#.utf8))
        else { return XCTFail("unknown") }
        XCTAssertEqual(type, "somethingNew")
        guard case .peerStatusChanged =
                DuckSignalling.read(Data(#"{"type":"peerStatusChanged"}"#.utf8))
        else { return XCTFail("peerStatusChanged") }
    }

    func testTheTwoRulesAClientMustObeyAreWrittenDown() {
        XCTAssertEqual(DuckSignalling.controlChannel, "control")
        XCTAssertEqual(DuckSignalling.teleopChannel, "teleop")
        XCTAssertTrue(DuckSignalling.repliesAreNotCorrelated.contains("none of them is a reply"))
        XCTAssertTrue(DuckSignalling.oneLaneOneRequest.contains("one request at a time"))
    }
}
