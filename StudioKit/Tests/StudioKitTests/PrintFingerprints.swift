import XCTest
import DuckKit
import Crypto
import DuckEvidence
@testable import StudioKit

/// Not a test — a generator. Prints the parameter fingerprint of every vendored
/// policy so the official manifest can be built from measurement rather than
/// typed by hand. Kept because the manifest has to be regenerated whenever
/// Pollen release new weights, and a one-off script that lived in a scratch
/// directory would not survive to that day.
final class PrintFingerprints: XCTestCase {
    func testPrintOfficialFingerprints() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/policies", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "onnx" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in files {
            let policy = try DuckPolicy.load(contentsOf: url)
            print("FINGERPRINT \(url.lastPathComponent) \(policy.fingerprint)")
        }
    }

    /// Every vendored policy must be recognised by DuckEvidence's manifest.
    ///
    /// This is where the manifest is actually proved. duckkit vendors only
    /// alpha_walking, so its own test can check one entry; all nine live here.
    /// A hand-edited digest fails here and nowhere else.
    func testAllNineVendoredPoliciesAreRecognisedAsOfficial() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/policies", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "onnx" }
        XCTAssertEqual(files.count, 9)
        for url in files {
            let policy = try DuckPolicy.load(contentsOf: url)
            guard case .released(let release) = DuckOfficialPolicies.standing(of: policy) else {
                XCTFail("\(url.lastPathComponent) is one of Pollen's nine and was not recognised")
                continue
            }
            XCTAssertEqual(release.filename, url.lastPathComponent,
                           "recognised, but under the wrong name — the manifest rows are crossed")
        }
    }

    /// Flipping a single weight must move the fingerprint out of the manifest.
    /// This is the case the whole design exists for: a file that is Pollen's in
    /// every respect except the numbers that decide what the robot does.
    func testOneChangedWeightIsNoLongerRecognised() throws {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "alpha_walking", withExtension: "onnx", subdirectory: "Fixtures/policies"))
        let original = try DuckPolicy.load(contentsOf: url)
        guard case .released = DuckOfficialPolicies.standing(of: original) else {
            return XCTFail("baseline must be recognised")
        }
        // Perturb the canonical bytes the way a tampered weight would, and ask
        // the manifest about the digest that results.
        var bytes = Array(original.canonicalParameterBytes)
        bytes[0] ^= 0x01
        let tampered = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        XCTAssertNotEqual(tampered, original.fingerprint)
        XCTAssertEqual(DuckOfficialPolicies.standing(ofFingerprint: tampered), DuckOfficialPolicies.Standing.unrecognised,
                       "one flipped bit must fall out of the manifest")
    }
}
