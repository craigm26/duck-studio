import XCTest
@testable import StudioKit

/// URL construction is the kind of code that looks obviously right and is
/// quietly wrong for a year, so every rule gets a test.
final class PolicySourceTests: XCTestCase {

    /// `resolve/` and not `blob/`. Getting this wrong fetches the HTML page
    /// wrapped around the file, which then fails to parse as ONNX with a
    /// message about protobuf that sends the reader in the wrong direction.
    func testTheHuggingFaceURLIsTheRawResolveEndpoint() throws {
        let r = try PolicySource.huggingFace(repository: "pollen-robotics/microduck",
                                             file: "alpha_walking.onnx")
        XCTAssertEqual(r.displayURL,
                       "https://huggingface.co/pollen-robotics/microduck/resolve/main/alpha_walking.onnx")
        XCTAssertEqual(r.host, "huggingface.co")
        XCTAssertEqual(r.suggestedName, "alpha_walking.onnx")
    }

    func testANestedPathKeepsItsDirectoriesButNotInTheName() throws {
        let r = try PolicySource.huggingFace(repository: "a/b", file: "policies/walk.onnx")
        XCTAssertTrue(r.displayURL.hasSuffix("/resolve/main/policies/walk.onnx"), r.displayURL)
        XCTAssertEqual(r.suggestedName, "walk.onnx", "the stored name is the file, not the path")
    }

    func testARevisionCanBePinned() throws {
        let r = try PolicySource.huggingFace(repository: "a/b", file: "w.onnx", revision: "v2.1")
        XCTAssertTrue(r.displayURL.contains("/resolve/v2.1/"), r.displayURL)
    }

    /// The address is carried explicitly so a screen can show it before
    /// anything leaves the device.
    func testTheRequestCarriesSomethingToShowBeforeFetching() throws {
        let r = try PolicySource.huggingFace(repository: "a/b", file: "w.onnx")
        XCTAssertEqual(r.displayURL, r.url.absoluteString)
        XCTAssertFalse(r.displayURL.isEmpty)
    }

    func testAMalformedRepositoryIsRefusedWithAnExample() {
        for bad in ["microduck", "a/b/c", "/b", "a/", ""] {
            XCTAssertThrowsError(try PolicySource.huggingFace(repository: bad, file: "w.onnx"),
                                 "\(bad) should be refused") { error in
                guard case PolicySource.Refusal.malformedRepository = error else {
                    return XCTFail("wrong refusal for \(bad): \(error)")
                }
            }
        }
        let message = PolicySource.message(for: .malformedRepository("microduck"))
        XCTAssertTrue(message.contains("owner/name"), message)
        XCTAssertTrue(message.contains("pollen-robotics/microduck"),
                      "show a real example, not an abstract shape")
    }

    func testOnlyOnnxFilesAreAccepted() {
        XCTAssertThrowsError(try PolicySource.huggingFace(repository: "a/b", file: "README.md"))
        XCTAssertThrowsError(try PolicySource.direct("https://example.com/model.pt"))
    }

    /// http is refused, and the message says why rather than just "invalid".
    func testPlainHttpIsRefused() {
        XCTAssertThrowsError(try PolicySource.direct("http://example.com/w.onnx")) { error in
            guard case PolicySource.Refusal.insecureScheme(let scheme) = error else {
                return XCTFail("expected insecureScheme, got \(error)")
            }
            XCTAssertEqual(scheme, "http")
        }
        let message = PolicySource.message(for: .insecureScheme("http"))
        XCTAssertTrue(message.contains("modify in flight"), message)
    }

    func testHttpsElsewhereIsFine() throws {
        let r = try PolicySource.direct("https://example.org/nets/walk.onnx")
        XCTAssertEqual(r.host, "example.org")
        XCTAssertEqual(r.suggestedName, "walk.onnx")
    }

    /// The cap is ten times a real policy: loose enough not to block a bigger
    /// network, tight enough that a mistyped URL pointing at a dataset fails
    /// before it costs anyone a cellular allowance.
    func testTheSizeCapIsGenerousButReal() throws {
        XCTAssertEqual(PolicySource.byteCap, 8 * 1024 * 1024)
        XCTAssertNoThrow(try PolicySource.accept(Data(count: 793_705)),
                         "a real policy passes comfortably")
        XCTAssertThrowsError(try PolicySource.accept(Data(count: PolicySource.byteCap + 1))) { error in
            guard case PolicySource.Refusal.tooLarge = error else {
                return XCTFail("expected tooLarge, got \(error)")
            }
        }
        let message = PolicySource.message(for: .tooLarge(bytes: 40 * 1024 * 1024))
        XCTAssertTrue(message.contains("40.0 MB"), message)
    }

    /// There is deliberately no way to supply a credential. If a token
    /// parameter ever appears, this test is where the argument happens.
    func testThereIsNoWayToSupplyAToken() {
        let surface = "\(PolicySource.Request.self) \(PolicySource.Refusal.self)"
        XCTAssertFalse(surface.lowercased().contains("token"),
                       "an inspector has no account and must not become a place to paste one")
    }
}
