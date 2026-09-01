import XCTest
@testable import StudioKit

/// The BLE contract, pinned against `btd`'s source in
/// pollen-robotics/microduck.
///
/// THESE ARE TRANSCRIPTION TESTS AND THAT IS THE POINT. Nothing here has met a
/// robot. What they check is that the values in `DuckLink` are the values in
/// `gatt.rs`, `adv.rs` and `framing.rs` — because a UUID typo produces a
/// scanner that finds nothing and reports no error, which is indistinguishable
/// from a duck being switched off.
final class DuckLinkTests: XCTestCase {

    /// `gatt.rs`: "Random v4 UUIDs rather than anything derived: they are ours,
    /// and they must not change once an app has shipped against them."
    func testTheUUIDsAreExactlyTheOnesTheRobotServes() {
        XCTAssertEqual(DuckLink.serviceUUID, "6F5D2A10-3B47-4C8E-9A1F-2D7E8C4B6019")
        XCTAssertEqual(DuckLink.rpcUUID, "6F5D2A11-3B47-4C8E-9A1F-2D7E8C4B6019")
        // Their own test: the two must differ. They differ in one digit, which
        // is exactly the kind of pair a transcription slip collapses.
        XCTAssertNotEqual(DuckLink.serviceUUID, DuckLink.rpcUUID)
    }

    // MARK: - the advertisement

    private func advertisement(_ bytes: [UInt8]) -> Data { Data(bytes) }

    /// Company id 0xFFFF little-endian, then four octets.
    func testARealAddressIsReadOutOfTheAdvertisement() {
        let data = advertisement([0xFF, 0xFF, 192, 168, 1, 24])
        XCTAssertEqual(DuckLink.address(fromManufacturerData: data), .at("192.168.1.24"))
    }

    /// `adv.rs`: absent and zero "want different next moves. Dropping the field
    /// would collapse them into one blank column."
    func testNoWifiAndNoBroadcastAreDifferentAnswers() {
        XCTAssertEqual(DuckLink.address(fromManufacturerData:
            advertisement([0xFF, 0xFF, 0, 0, 0, 0])), .none)
        XCTAssertEqual(DuckLink.address(fromManufacturerData: Data()), .notBroadcast)
        XCTAssertEqual(DuckLink.address(fromManufacturerData:
            advertisement([0xFF, 0xFF])), .notBroadcast)
    }

    /// Another vendor's manufacturer data is not an address, and 0xFFFF "is not
    /// an identity check" — the service UUID is the discriminator.
    func testSomebodyElsesManufacturerDataIsNotReadAsAnAddress() {
        XCTAssertEqual(DuckLink.address(fromManufacturerData:
            advertisement([0x4C, 0x00, 10, 0, 0, 1])), .notBroadcast)
        // Right company, wrong length.
        XCTAssertEqual(DuckLink.address(fromManufacturerData:
            advertisement([0xFF, 0xFF, 10, 0, 0])), .notBroadcast)
    }

    // MARK: - the version read

    /// `btd` answers the read with `vec![API_VERSION as u8]` — one byte.
    func testTheVersionReadIsExactlyOneByte() {
        XCTAssertEqual(DuckLink.apiVersion(fromRead: Data([16])), 16)
        XCTAssertNil(DuckLink.apiVersion(fromRead: Data()))
        XCTAssertNil(DuckLink.apiVersion(fromRead: Data([16, 0, 0, 0])),
                     "four bytes is a different protocol, not this one")
    }

    // MARK: - framing

    func testAHelloRequestIsOneNewlineTerminatedJSONLine() throws {
        let line = try DuckLink.helloRequest()
        XCTAssertEqual(line.last, 0x0A, "NDJSON is delimited by the newline and nothing else")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(
            with: line.dropLast()) as? [String: Any])
        XCTAssertEqual(body["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(body["method"] as? String, "hello")
        XCTAssertNotNil(body["id"], "hello is a REQUEST — a notification would never be answered")
        let params = try XCTUnwrap(body["params"] as? [String: Any])
        XCTAssertEqual(params["api_version"] as? Int, 16)
    }

    /// The whole line must survive being cut at the worst MTU a phone offers.
    func testALineSurvivesTwentyByteWrites() throws {
        let line = try DuckLink.helloRequest()
        let pieces = DuckLink.chunks(line, mtu: 20)
        XCTAssertTrue(pieces.count > 1, "this line is longer than one 20-byte write")
        XCTAssertTrue(pieces.allSatisfy { $0.count <= 20 })
        XCTAssertEqual(pieces.reduce(Data(), +), line)
    }

    func testAShortLineIsOneWrite() throws {
        let line = try DuckLink.helloRequest()
        XCTAssertEqual(DuckLink.chunks(line, mtu: 512), [line])
    }

    /// Reassembly is the same problem in the other direction.
    func testChunkedAnswersReassembleIntoWholeLines() throws {
        var r = DuckLink.Reassembler()
        let payload = Data(#"{"jsonrpc":"2.0","id":1,"result":{"api_version":16}}"#.utf8) + Data([0x0A])
        var out: [Data] = []
        for piece in DuckLink.chunks(payload, mtu: 7) {
            out += try r.feed(piece)
        }
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first, payload.dropLast())
    }

    func testTwoLinesInOneChunkComeBackAsTwo() throws {
        var r = DuckLink.Reassembler()
        let out = try r.feed(Data("{\"a\":1}\n{\"b\":2}\n".utf8))
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(String(data: out[1], encoding: .utf8), "{\"b\":2}")
    }

    /// `framing.rs` caps the buffer because a peer "is reachable by anyone in
    /// radio range".
    func testAPeerThatNeverSendsANewlineIsDropped() {
        var r = DuckLink.Reassembler()
        XCTAssertThrowsError(try r.feed(Data(repeating: 0x41, count: DuckLink.maxLine + 1))) {
            XCTAssertEqual($0 as? DuckLink.Reassembler.Failure, .lineTooLong)
        }
    }

    /// A buffer holding many complete lines is not a peer that cannot frame.
    func testPlentyOfCompleteLinesDoNotTripTheCap() throws {
        var r = DuckLink.Reassembler()
        let one = Data(String(repeating: "x", count: 500).utf8) + Data([0x0A])
        var count = 0
        for _ in 0..<40 { count += try r.feed(one).count }
        XCTAssertEqual(count, 40)
    }

    // MARK: - the answer

    func testAHelloAnswerIsRead() throws {
        let line = Data(#"{"jsonrpc":"2.0","id":1,"result":{"api_version":16,"daemon_version":"0.4.1","revision":"abc1234"}}"#.utf8)
        let hello = try DuckLink.hello(fromLine: line)
        XCTAssertEqual(hello.apiVersion, 16)
        XCTAssertEqual(hello.daemonVersion, "0.4.1")
        XCTAssertEqual(hello.revision, "abc1234")
    }

    /// "Always serialised, including as `null`, for a build that did not come
    /// from CI."
    func testALaptopBuildHasNoRevisionAndThatIsNotAnError() throws {
        let line = Data(#"{"jsonrpc":"2.0","id":1,"result":{"api_version":16,"revision":null}}"#.utf8)
        let hello = try DuckLink.hello(fromLine: line)
        XCTAssertNil(hello.revision)
        XCTAssertEqual(hello.apiVersion, 16)
    }

    func testARefusalIsCarriedRatherThanSwallowed() {
        let line = Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"method not found: hello"}}"#.utf8)
        XCTAssertThrowsError(try DuckLink.hello(fromLine: line)) {
            XCTAssertEqual($0 as? DuckLink.LinkError,
                           .robot(code: -32601, message: "method not found: hello"))
        }
    }

    func testSomethingThatIsNotJSONRPCIsNamedAsSuch() {
        XCTAssertThrowsError(try DuckLink.hello(fromLine: Data("hello?".utf8))) {
            XCTAssertEqual($0 as? DuckLink.LinkError, .notJSON)
        }
    }

    // MARK: - what we tell people

    /// A newer duck is news, not a failure — this app makes one call and it has
    /// existed since v1.
    func testAVersionDifferenceSaysWhichWayRound() {
        XCTAssertTrue(DuckLink.verdict(for: 16).contains("the same one"))
        XCTAssertTrue(DuckLink.verdict(for: 20).contains("newer"))
        XCTAssertTrue(DuckLink.verdict(for: 9).contains("older"))
    }

    /// The read must come before the write, or iOS fails with no error at all.
    func testTheStepsPutPairingBeforeAnyWrite() {
        let order = DuckLink.Step.allCases
        let read = order.firstIndex(of: .readVersion)!
        XCTAssertLessThan(read, order.firstIndex(of: .subscribe)!)
        XCTAssertLessThan(read, order.firstIndex(of: .hello)!)
        XCTAssertTrue(DuckLink.Step.readVersion.detail.contains("pairing prompt"))
    }

    /// The screen must not imply it can drive.
    func testTheScreenAdmitsItCannotDrive() {
        XCTAssertTrue(DuckLink.whatThisCanDo.contains("does not drive"))
        XCTAssertTrue(DuckLink.whatThisCanDo.contains("Nothing here has been run against a robot"))
    }
}

extension DuckLinkTests {

    /// The weakest tier, and the one a bonded duck falls back to.
    func testANameIsAcceptedGenerouslyBecauseAMissCostsMore() {
        XCTAssertTrue(DuckLink.looksLikeADuck("microduck-a3f1"))
        XCTAssertTrue(DuckLink.looksLikeADuck("Duck"))
        XCTAssertTrue(DuckLink.looksLikeADuck("pistachio-duck"))
        XCTAssertFalse(DuckLink.looksLikeADuck("Craig's AirPods"))
        XCTAssertFalse(DuckLink.looksLikeADuck("LE-Bose QC35"))
    }
}

extension DuckLinkTests {

    /// The app's own shortcut, named — Pollen document the failure mode about
    /// exactly this shape, and the word in their sentence doing the work is
    /// "alone".
    func testTheAppAdmitsAPeripheralIdentifierIsNotAnIdentity() {
        XCTAssertTrue(DuckLink.identifierIsNotAnIdentity.contains("Bluetooth address"))
        XCTAssertTrue(DuckLink.identifierIsNotAnIdentity.contains("SoC serial"))
        XCTAssertTrue(DuckLink.identifierIsNotAnIdentity.contains("system.info"))
    }
}
