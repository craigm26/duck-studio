import XCTest
@testable import StudioKit

/// The contract with `bridge/microduck-bridge.py`, both ends of which are in
/// this repo — so these assertions are pinned against the strings that program
/// actually writes, taken from its source.
final class BridgeHandshakeTests: XCTestCase {

    func testTheHelloIsTheLineTheBridgeReads() throws {
        let line = BridgeHandshake.hello(token: "0123456789abcdef0123456789abcdef")
        let text = String(decoding: line, as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("\n"), "the bridge reads to a newline")
        let top = try XCTUnwrap(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        XCTAssertEqual(top["microduck"] as? String, "v1")
        XCTAssertEqual(top["token"] as? String, "0123456789abcdef0123456789abcdef")
    }

    func testAQuoteInATokenCannotBreakTheLine() throws {
        let line = BridgeHandshake.hello(token: "a\"b\\c")
        let top = try XCTUnwrap(try JSONSerialization.jsonObject(with: line) as? [String: Any])
        XCTAssertEqual(top["token"] as? String, "a\"b\\c")
    }

    /// The greeting the bridge sends on acceptance, verbatim from its source.
    func testTheBridgesOwnGreetingIsRead() throws {
        let said = Data(#"{"microduck": "v1", "bridge": "microduck-bridge/1", "deadman_ms": 700}"#.utf8)
        let greeting = try BridgeHandshake.read(said)
        XCTAssertEqual(greeting.bridge, "microduck-bridge/1")
        XCTAssertEqual(greeting.deadmanMilliseconds, 700)
    }

    /// And its refusal, verbatim: a bridge that says no is not a bridge that
    /// failed to answer, and the two must not be reported the same way.
    func testARefusalIsReadAsARefusalAndNotAsRubbish() {
        let said = Data(#"{"error":"microduck-bridge: wrong or missing token"}"#.utf8)
        XCTAssertThrowsError(try BridgeHandshake.read(said)) { error in
            XCTAssertEqual(error as? BridgeHandshake.Refusal,
                           .refused("microduck-bridge: wrong or missing token"))
            XCTAssertTrue((error as? BridgeHandshake.Refusal)?.message
                            .contains("wrong or missing token") == true)
        }
    }

    func testSomethingThatIsNotABridgeSaysSo() {
        XCTAssertThrowsError(try BridgeHandshake.read(Data("HTTP/1.1 404".utf8))) { error in
            XCTAssertEqual(error as? BridgeHandshake.Refusal, .notJSON)
        }
        XCTAssertThrowsError(try BridgeHandshake.read(Data(#"{"hello":"world"}"#.utf8))) { error in
            XCTAssertEqual(error as? BridgeHandshake.Refusal, .notJSON)
        }
    }

    func testAnOlderOrNewerBridgeIsNamedRatherThanGuessedAt() {
        XCTAssertThrowsError(try BridgeHandshake.read(Data(#"{"microduck":"v2"}"#.utf8))) { error in
            XCTAssertEqual(error as? BridgeHandshake.Refusal, .wrongVersion("v2"))
            XCTAssertTrue((error as? BridgeHandshake.Refusal)?.message.contains("v2") == true)
        }
    }

    /// A deadman this app did not measure is not a deadman this app claims.
    func testTheDeadmanSentenceOnlyPromisesWhatTheBridgeSaid() {
        XCTAssertTrue(BridgeHandshake.deadmanSaid(700).contains("700 ms"))
        XCTAssertTrue(BridgeHandshake.deadmanSaid(nil).contains("does not claim one"))
        XCTAssertFalse(BridgeHandshake.deadmanSaid(nil).contains("ms —"))
    }

    func testTheTokenSentenceRefusesToCallItSecurity() {
        XCTAssertTrue(BridgeHandshake.tokenIsNotSecurity.contains("not a security boundary"))
        XCTAssertTrue(BridgeHandshake.tokenIsNotSecurity.contains("port-forwarded"))
        for said in BridgeHandshake.everySentence {
            XCTAssertFalse(said.isEmpty)
            XCTAssertTrue(said.hasSuffix("."), said)
        }
    }

    func testTheBonjourTypeIsWhatTheAvahiRecordAdvertises() {
        XCTAssertEqual(BridgeHandshake.bonjourType, "_robotd._tcp")
        XCTAssertEqual(BridgeHandshake.defaultPort, 7788)
    }
}
