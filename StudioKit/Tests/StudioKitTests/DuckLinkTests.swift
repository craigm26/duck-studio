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

// MARK: - the two calls the spike makes past hello

/// THESE ARE THE TESTS THAT COULD NOT EXIST BEFORE. Both request shapes were
/// assembled in the app target, in a private type whose own doc comment
/// admitted it was in the wrong place: a `params` member spelled in a SwiftUI
/// target is a claim about Pollen's protocol that no `swift test` can reach. The
/// spike's whole deliverable is a report a Pollen engineer will act on, and a
/// robot refusing a line THIS APP got wrong would be written up in that report
/// as a fact about pairing.
extension DuckLinkTests {

    private func body(of line: Data) throws -> [String: Any] {
        XCTAssertEqual(line.last, 0x0A, "NDJSON is delimited by the newline and nothing else")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: line.dropLast()) as? [String: Any])
    }

    /// The PIN is a STRING. A factory PIN of "000000" sent as a number is `0`,
    /// and a robot that refused it would be working perfectly.
    func testTheAuthenticateRequestSendsThePinAsAString() throws {
        let line = try DuckLink.authenticateRequest(pin: "000000", id: 2)
        let body = try body(of: line)
        XCTAssertEqual(body["jsonrpc"] as? String, "2.0")
        XCTAssertEqual(body["method"] as? String, "system.authenticate")
        XCTAssertEqual(body["id"] as? Int, 2)
        let params = try XCTUnwrap(body["params"] as? [String: Any])
        XCTAssertEqual(params["pin"] as? String, "000000")
        XCTAssertNil(params["pin"] as? Int, "a PIN read as a number loses its leading zeroes")
    }

    /// The exact bytes, sorted, which is what a robot actually receives.
    func testTheAuthenticateRequestIsExactlyTheseBytes() throws {
        let line = try DuckLink.authenticateRequest(pin: "000000", id: 2)
        XCTAssertEqual(String(data: line, encoding: .utf8),
                       #"{"id":2,"jsonrpc":"2.0","method":"system.authenticate","params":{"pin":"000000"}}"# + "\n")
    }

    /// `params` is OMITTED, not sent empty — the rule `DuckCall.parameters()`
    /// already states: "an empty object is a claim that the method takes
    /// parameters and got none, which is a different thing to say to a strict
    /// deserialiser."
    func testTheSystemInfoRequestSendsNoParamsAtAll() throws {
        let line = try DuckLink.systemInfoRequest(id: 3)
        XCTAssertEqual(String(data: line, encoding: .utf8),
                       #"{"id":3,"jsonrpc":"2.0","method":"system.info"}"# + "\n")
        let body = try body(of: line)
        XCTAssertNil(body["params"])
    }

    /// A duck answering system.info names itself, and the serial is the answer
    /// that matters: it is the durable identity a peripheral identifier is not.
    func testASystemInfoAnswerIsRead() throws {
        let line = Data(#"{"jsonrpc":"2.0","id":3,"result":{"name":"microduck-a3f1","serial":"10000000abcd1234","uptime_seconds":11520}}"#.utf8)
        let info = try DuckLink.systemInfo(fromLine: line)
        XCTAssertEqual(info, DuckLink.SystemInfo(name: "microduck-a3f1",
                                                 serial: "10000000abcd1234",
                                                 uptimeSeconds: 11520))
    }

    /// A MALFORMED ANSWER IS AN ERROR, NOT AN EMPTY STRUCT. The report prints
    /// the name and the serial; a `SystemInfo` with blanks in it would be read
    /// as a robot that answered and said nothing about itself.
    func testAMalformedSystemInfoAnswerIsRefusedRatherThanBlanked() {
        // A result with no serial in it.
        XCTAssertThrowsError(try DuckLink.systemInfo(fromLine:
            Data(#"{"jsonrpc":"2.0","id":3,"result":{"name":"duck","uptime_seconds":3}}"#.utf8))) {
            guard case .unexpected(let what)? = $0 as? DuckLink.LinkError else {
                return XCTFail("expected .unexpected, got \($0)")
            }
            XCTAssertTrue(what.contains("name and serial"))
        }
        // A result with no uptime in it.
        XCTAssertThrowsError(try DuckLink.systemInfo(fromLine:
            Data(#"{"jsonrpc":"2.0","id":3,"result":{"name":"duck","serial":"abc"}}"#.utf8)))
        // Not JSON at all.
        XCTAssertThrowsError(try DuckLink.systemInfo(fromLine: Data("who are you?".utf8))) {
            XCTAssertEqual($0 as? DuckLink.LinkError, .notJSON)
        }
        // A refusal is carried with its own words, not flattened into "no data".
        XCTAssertThrowsError(try DuckLink.systemInfo(fromLine:
            Data(#"{"jsonrpc":"2.0","id":3,"error":{"code":-32000,"message":"not authenticated"}}"#.utf8))) {
            XCTAssertEqual($0 as? DuckLink.LinkError,
                           .robot(code: -32000, message: "not authenticated"))
        }
    }

    /// An answer is filed by ITS OWN id, because "whatever step is running" is
    /// the same thing right up until a step times out — and then it is the
    /// difference between a true report and a fabricated one.
    func testAnAnswerCarriesTheIDItWasAskedUnder() {
        XCTAssertEqual(DuckLink.reply(fromLine: Data(#"{"jsonrpc":"2.0","id":2,"result":{}}"#.utf8)),
                       DuckLink.Reply(id: 2, trouble: nil))
        let refused = DuckLink.reply(fromLine:
            Data(#"{"jsonrpc":"2.0","id":2,"error":{"code":-32001,"message":"bad pin"}}"#.utf8))
        XCTAssertEqual(refused?.id, 2)
        XCTAssertEqual(refused?.trouble, "The duck refused: bad pin (-32001)")
        // A line with no id is not an answer to anything this app sent, and the
        // caller has to report that rather than discard it.
        XCTAssertNil(DuckLink.reply(fromLine: Data(#"{"jsonrpc":"2.0","result":{}}"#.utf8)))
        XCTAssertNil(DuckLink.reply(fromLine: Data("nonsense".utf8)))
    }
}

// MARK: - ranking what a scan saw

/// THE FILTER THAT IS NOT ON THE SCAN CALL. It used to be three `||`s in the
/// scanner, in the app target, while the report told its reader the scan was
/// unfiltered — true of the CoreBluetooth call and misleading about what
/// happened next.
extension DuckLinkTests {

    func testTheStrongestEvidenceAScanCanCarryWinsAndOnlyItEndsTheScan() {
        XCTAssertEqual(DuckLink.tier(advertisesService: true, knownBefore: false,
                                     name: "Craig's AirPods"), .advertisedService)
        // The service UUID beats everything, including a name that says nothing.
        XCTAssertTrue(DuckLink.Tier.advertisedService.endsTheScan)
        XCTAssertFalse(DuckLink.Tier.knownBefore.endsTheScan)
        XCTAssertFalse(DuckLink.Tier.nameOnly.endsTheScan)
    }

    /// A BONDED DUCK ADVERTISES NOTHING, which is why the weaker tiers exist at
    /// all: the duck somebody has already paired with is exactly the one the
    /// strongest evidence goes missing for.
    func testABondedDuckWithNoServicesAndNoNameIsStillACandidate() {
        XCTAssertEqual(DuckLink.tier(advertisesService: false, knownBefore: true, name: nil),
                       .knownBefore)
        XCTAssertEqual(DuckLink.tier(advertisesService: false, knownBefore: false,
                                     name: "microduck-a3f1"), .nameOnly)
    }

    /// Somebody else's headphones are not a candidate, and a scan that offered
    /// them would spend a 60-second read budget on a device that cannot answer.
    func testSomebodyElsesDeviceIsNotACandidateAtAll() {
        XCTAssertNil(DuckLink.tier(advertisesService: false, knownBefore: false,
                                   name: "Craig's AirPods"))
        XCTAssertNil(DuckLink.tier(advertisesService: false, knownBefore: false, name: nil))
    }

    /// The line the report prints for a sighting says what got it onto the list,
    /// and says so about a withheld signal rather than printing a zero.
    func testASightingsReportLineNamesItsEvidenceAndNeverInventsASignal() {
        let strong = DuckLink.Sighting(name: "microduck-a3f1", rssi: -58,
                                       address: .at("192.168.1.24"), tier: .advertisedService)
        XCTAssertEqual(strong.line,
                       "microduck-a3f1, -58 dBm — advertises the robot's service UUID")
        let quiet = DuckLink.Sighting(name: "duckling", rssi: nil,
                                      address: .notBroadcast, tier: .nameOnly)
        XCTAssertEqual(quiet.line, "duckling, no signal reading — a duck-ish name and nothing else")
        XCTAssertFalse(quiet.line.contains("0 dBm"))
    }

    /// An id-less line with a method is a notification, not garbage and not
    /// a reply. A reply still has an id; garbage has neither.
    func testANotificationIsNotAnUnreadableAnswer() {
        let progress = Data(#"{"jsonrpc":"2.0","method":"update.progress","params":{"percent":40}}"#.utf8)
        XCTAssertEqual(DuckLink.notificationMethod(fromLine: progress), "update.progress")
        XCTAssertNil(DuckLink.reply(fromLine: progress))
        let answer = Data(#"{"jsonrpc":"2.0","id":3,"result":{}}"#.utf8)
        XCTAssertNil(DuckLink.notificationMethod(fromLine: answer))
        XCTAssertEqual(DuckLink.reply(fromLine: answer)?.id, 3)
        XCTAssertNil(DuckLink.notificationMethod(fromLine: Data("not json".utf8)))
        XCTAssertNil(DuckLink.notificationMethod(fromLine: Data(#"{"jsonrpc":"2.0"}"#.utf8)))
    }

    /// A sighting says whether the radio heard it or memory offered it.
    func testASightingOfferedFromMemorySaysSoOnItsLine() {
        let heard = DuckLink.Sighting(name: "microduck-a3f1", rssi: -58,
                                      address: .at("192.168.1.24"), tier: .advertisedService)
        XCTAssertTrue(heard.heard)
        XCTAssertFalse(heard.line.contains("NOT heard"))
        let remembered = DuckLink.Sighting(name: "microduck-a3f1", rssi: nil,
                                           address: .notBroadcast, tier: .knownBefore, heard: false)
        XCTAssertTrue(remembered.line.hasSuffix("offered from this phone's memory and NOT heard in this window"))
    }
}
