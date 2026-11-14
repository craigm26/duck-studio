import XCTest
@testable import StudioKit

/// Where a planner's words go, and the card line for each (brains-layer.md 6.6 and section 9
/// item 2: "with TLS or the plaintext caveat").
final class ModelTransportTests: XCTestCase {
    typealias F = LocalFixtures

    func classify(_ base: String, relay: Bool = false, note: String? = nil) throws -> ModelTransport {
        var e = F.endpoint(base, relay: relay)
        e.relayNote = note
        return try ModelTransport.classify(e)
    }

    func testEveryKindOfAddress() throws {
        XCTAssertEqual(try ModelTransport.classify(ModelEndpoint(name: "m", kind: .downloadedMLX, model: "a/b")), .thisDevice)
        XCTAssertEqual(try ModelTransport.classify(.onDevice), .thisDevice)
        XCTAssertEqual(try classify("http://localhost:8080/v1"), .otherAppOnThisDevice)
        XCTAssertEqual(try classify("http://127.0.0.1:8080/v1"), .otherAppOnThisDevice)
        XCTAssertEqual(try classify("http://192.168.1.20:11434/v1"), .ownNetworkPlain(host: "192.168.1.20"))
        XCTAssertEqual(try classify("http://Mac-Studio.local:1234/v1"), .ownNetworkPlain(host: "mac-studio.local"))
        XCTAssertEqual(try classify("https://mac.local:8443/v1"), .ownNetworkEncrypted(host: "mac.local"))
        XCTAssertEqual(try classify("http://100.101.102.103:11434/v1"), .tailnet(host: "100.101.102.103"))
        XCTAssertEqual(try classify("http://mac.tail1234.ts.net:11434/v1"), .tailnet(host: "mac.tail1234.ts.net"))
        XCTAssertEqual(try classify("https://mac.tail1234.ts.net/v1"), .ownNetworkEncrypted(host: "mac.tail1234.ts.net"))
        XCTAssertEqual(try classify("http://pi.local:8080/v1", relay: true), .forwardsElsewhere(host: "pi.local", to: nil))
        XCTAssertEqual(try classify("http://pi.local:8080/v1", relay: true, note: "Anthropic"),
                       .forwardsElsewhere(host: "pi.local", to: "Anthropic"))
        XCTAssertEqual(try classify("http://pi.local:8080/v1", relay: true, note: " \n"), .forwardsElsewhere(host: "pi.local", to: nil))
        XCTAssertEqual(try classify("https://models.example.com/v1"), .internetEncrypted(host: "models.example.com"))
        XCTAssertThrowsError(try classify("http://models.example.com/v1")) {
            XCTAssertEqual($0 as? ModelEndpoint.Refusal, .plaintextToThePublicInternet(host: "models.example.com"))
        }
    }

    func testOnlyPlainHTTPOnYourWiFiIsReadableOnTheWay() {
        XCTAssertTrue(ModelTransport.ownNetworkPlain(host: "h").readableOnTheWay)
        for t: ModelTransport in [.thisDevice, .otherAppOnThisDevice, .ownNetworkEncrypted(host: "h"), .tailnet(host: "h"),
                                  .forwardsElsewhere(host: "h", to: nil), .internetEncrypted(host: "h")] {
            XCTAssertFalse(t.readableOnTheWay, "\(t)")
        }
        XCTAssertTrue(ModelTransport.forwardsElsewhere(host: "h", to: nil).leavesYourNetwork)
        XCTAssertFalse(ModelTransport.ownNetworkPlain(host: "h").leavesYourNetwork)
    }

    func testThePlainHTTPCaveat() {
        let lines = ModelTransport.ownNetworkPlain(host: "mac.local").card(bearerSet: false, device: .phone)
        XCTAssertEqual(lines, ["Goes to mac.local on your own network.",
                               "What you type is sent unencrypted over your Wi-Fi. Anyone on it can read it."])
        let withToken = ModelTransport.ownNetworkPlain(host: "mac.local").card(bearerSet: true, device: .phone)
        XCTAssertEqual(withToken.last, "The access token for it is sent unencrypted too.")
        XCTAssertFalse(ModelTransport.ownNetworkEncrypted(host: "mac.local").card(bearerSet: true).contains(ModelTransport.Words.plainCaveat))
        XCTAssertFalse(ModelTransport.tailnet(host: "h").card(bearerSet: true).contains(ModelTransport.Words.plainCaveat),
                       "a tailnet is encrypted between devices, so the caveat would be false")
    }

    func testCardsNameTheDevice() {
        XCTAssertEqual(ModelTransport.thisDevice.card(device: .phone), ["Runs on this phone. Nothing you type leaves it."])
        XCTAssertEqual(ModelTransport.thisDevice.card(device: .mac), ["Runs on this Mac. Nothing you type leaves it."])
    }

    /// No em-dashes, nothing called safe, and no key in any card line.
    func testTheCopyRules() {
        let all = ModelTransport.Words.all + LocalPlannerWords.all
        XCTAssertGreaterThan(all.count, 20)
        for s in all {
            XCTAssertFalse(s.contains("\u{2014}"), "em-dash in: \(s)")
            XCTAssertFalse(s.contains("\u{2013}"), "en-dash in: \(s)")
            XCTAssertNil(s.range(of: #"(^|[^A-Za-z])safe"#, options: [.regularExpression, .caseInsensitive]), "\"safe\" in: \(s)")
            XCTAssertFalse(s.isEmpty)
        }
        let prompts = [LocalDecisionPrompt.instructions(for: F.real), LocalDecisionPrompt.instructions(for: F.real, toolCalls: true)]
        for s in prompts { XCTAssertFalse(s.contains("\u{2014}"), "em-dash in the prompt") }
    }
}
