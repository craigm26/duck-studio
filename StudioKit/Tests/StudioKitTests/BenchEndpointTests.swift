import XCTest
@testable import StudioKit

/// A saved bench is the thing that stops somebody retyping an address every
/// time they move between machines, so what survives storage matters as much as
/// what is refused.
final class BenchEndpointTests: XCTestCase {

    private func bench(_ address: String, name: String = "Pi") -> BenchEndpoint {
        BenchEndpoint(name: name, address: address)
    }

    // MARK: - refusing a bad one

    /// THE NAME COMES FIRST. A new entry has neither a name nor an address, and
    /// "give it a name" is the step somebody can act on without knowing
    /// anything about ports.
    func testAnUnnamedBenchIsRefusedBeforeItsAddressIs() {
        XCTAssertThrowsError(try BenchEndpoint(name: "  ", address: "nonsense").validate()) {
            XCTAssertEqual($0 as? BenchEndpoint.Refusal, .emptyName)
        }
    }

    /// ONE PARSER FOR AN ADDRESS. Two would let a screen accept something the
    /// client then refuses, so the refusal comes out of `DuckBench` itself and
    /// keeps its own sentence.
    func testAnAddressIsRefusedByTheSameParserThatWillDialIt() {
        XCTAssertThrowsError(try bench("bench.example.com:8770").validate()) { error in
            guard case .address(let inner)? = error as? BenchEndpoint.Refusal else {
                return XCTFail("\(error)")
            }
            XCTAssertEqual(inner, .notLocal("bench.example.com"))
            // And the message a person sees is the client's own.
            XCTAssertEqual((error as? BenchEndpoint.Refusal)?.message, inner.message)
        }
    }

    /// "Check this address" is wanted on an entry that is NOT finished, which
    /// is the only moment anybody presses it. A check that demanded a name
    /// would refuse the case it exists for.
    func testAnAddressCanBeCheckedBeforeTheBenchHasAName() {
        XCTAssertNoThrow(try BenchEndpoint(name: "", address: "100.122.199.6:8770")
                            .validateAddress())
    }

    func testAGoodOneResolvesToSomethingDialable() throws {
        let resolved = try bench("100.122.199.6:8770").resolved()
        XCTAssertEqual(resolved.host, "100.122.199.6")
        XCTAssertEqual(resolved.port, 8770)
    }

    func testATailnetBenchIsRecognisedAsOneThatKeepsWorking() {
        XCTAssertTrue(bench("100.122.199.6:8770").isTailnet)
        XCTAssertFalse(bench("192.168.1.20:8770").isTailnet)
    }

    // MARK: - what is stored

    /// THE TOKEN NEVER REACHES THE PLIST. Device backups copy `UserDefaults`;
    /// a bench token is a secret and belongs in the Keychain, so the encoded
    /// form carries only the fact that there is one.
    func testTheTokenIsNotEncodedButTheFactOfItIs() throws {
        let armed = BenchEndpoint(name: "Pi", address: "100.122.199.6:8770",
                                  hasToken: true, token: "hunter2")
        let text = String(decoding: try JSONEncoder().encode(armed), as: UTF8.self)
        XCTAssertFalse(text.contains("hunter2"), text)
        XCTAssertTrue(text.contains("hasToken"), text)

        let back = try JSONDecoder().decode(BenchEndpoint.self,
                                            from: try JSONEncoder().encode(armed))
        XCTAssertTrue(back.hasToken)
        XCTAssertNil(back.token, "a decoded bench is not armed")
    }

    func testARoundTripKeepsEverythingElse() throws {
        let one = BenchEndpoint(name: "Desktop", address: "100.95.79.116:8770")
        let back = try JSONDecoder().decode(BenchEndpoint.self,
                                            from: try JSONEncoder().encode(one))
        XCTAssertEqual(back, one)
    }

    // MARK: - one bad record must not cost the others

    /// A CORRUPT ENTRY IS NOT "ALL YOUR BENCHES ARE GONE". Decoding the array
    /// whole throws on the first bad element and takes every good one with it.
    func testAnUnreadableEntryLosesOnlyItself() throws {
        let good = [BenchEndpoint(name: "Pi", address: "100.122.199.6:8770"),
                    BenchEndpoint(name: "Desktop", address: "100.95.79.116:8770")]
        var array = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(good)) as! [Any]
        array.insert(["name": "broken"], at: 1)          // no id, no address
        let data = try JSONSerialization.data(withJSONObject: array)

        let salvage = BenchEndpoint.decodeList(from: data)
        XCTAssertEqual(salvage.benches.map(\.name), ["Pi", "Desktop"])
        XCTAssertEqual(salvage.unreadable, 1)
    }

    /// AND THE SALVAGE MUST NOT QUIETLY DROP A FIELD. The first version of this
    /// re-encoded each element through a string-only box, which silently lost
    /// `hasToken` — a Bool — so a recovered bench forgot it had a token and
    /// started failing with 401 for no visible reason.
    func testSalvagingAListKeepsWhetherEachBenchHasAToken() throws {
        let benches = [BenchEndpoint(name: "Pi", address: "100.122.199.6:8770", hasToken: true),
                       BenchEndpoint(name: "Open", address: "100.95.79.116:8770", hasToken: false)]
        var array = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(benches)) as! [Any]
        array.append("not a bench at all")
        let data = try JSONSerialization.data(withJSONObject: array)

        let salvage = BenchEndpoint.decodeList(from: data)
        XCTAssertEqual(salvage.benches.map(\.hasToken), [true, false])
        XCTAssertEqual(salvage.unreadable, 1)
    }

    func testACompletelyUnreadableBlobIsReportedAsSuchRatherThanAsEmpty() {
        let salvage = BenchEndpoint.decodeList(from: Data("{not json".utf8))
        XCTAssertTrue(salvage.benches.isEmpty)
        XCTAssertNil(salvage.unreadable, "nil means the whole blob, not zero losses")
    }

    func testAnEmptyListReadsAsNoBenchesAndNoLosses() {
        let salvage = BenchEndpoint.decodeList(from: Data("[]".utf8))
        XCTAssertTrue(salvage.benches.isEmpty)
        XCTAssertEqual(salvage.unreadable, 0)
    }
}
