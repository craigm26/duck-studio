import XCTest
import DuckKit
@testable import StudioKit

/// A shared motion has to survive the trip and arrive saying what it is.
final class IntentExportTests: XCTestCase {

    private func clip(_ name: String = "sit") throws -> DuckIntentClip {
        try XCTUnwrap(DuckIntentClip.bundled()[name])
    }

    func testItRoundTrips() throws {
        let original = IntentExport(clip: try clip(), policyFingerprint: "abc123", note: "hi")
        let decoded = try IntentExport.decode(try original.encoded())
        XCTAssertEqual(decoded, original)
    }

    /// The measured postures travel, because "this one falls over" is the most
    /// useful thing a recipient can be told and it cannot be recomputed from
    /// joint angles alone.
    func testThePostureVerdictTravels() throws {
        let export = IntentExport(clip: try clip("step_up"), policyFingerprint: nil)
        let decoded = try IntentExport.decode(try export.encoded())
        XCTAssertEqual(decoded.endsIn, "toppled")
    }

    /// The filename says it is a motion, not a network — the confusion this
    /// whole app is organised to prevent.
    func testTheFilenameDistinguishesAMotionFromANetwork() throws {
        let export = IntentExport(clip: try clip("roulade"), policyFingerprint: nil)
        XCTAssertEqual(export.suggestedFilename, "roulade.duckintent")
        XCTAssertFalse(export.suggestedFilename.hasSuffix(".onnx"))
    }

    // MARK: - reading what someone sent

    func testGarbageIsRefused() {
        XCTAssertThrowsError(try IntentExport.decode(Data("not json".utf8))) {
            XCTAssertEqual($0 as? IntentExport.ImportError, .notAnIntent)
        }
        XCTAssertThrowsError(try IntentExport.decode(Data("{}".utf8))) {
            XCTAssertEqual($0 as? IntentExport.ImportError, .notAnIntent)
        }
    }

    /// A future format must be refused by NAME rather than silently misread —
    /// a reader that guessed would play a motion it does not understand.
    func testAnUnknownFormatIsRefusedByName() throws {
        let future = try JSONSerialization.data(withJSONObject: [
            "format": "duck-intent/9", "frames": [[Double]](),
        ])
        XCTAssertThrowsError(try IntentExport.decode(future)) { error in
            guard case IntentExport.ImportError.unsupportedFormat(let f) = error else {
                return XCTFail("wrong error")
            }
            XCTAssertEqual(f, "duck-intent/9")
        }
    }

    /// The 14-vs-15 trap again, on the import path this time. The message has
    /// to explain the shape rather than just report a count.
    func testAWrongJointCountExplainsTheShape() throws {
        let wrong = try JSONSerialization.data(withJSONObject: [
            "format": IntentExport.format,
            "frames": [[Double](repeating: 0, count: 15)],
        ])
        XCTAssertThrowsError(try IntentExport.decode(wrong)) { error in
            guard case IntentExport.ImportError.wrongJointCount(_, let got) = error else {
                return XCTFail("wrong error")
            }
            XCTAssertEqual(got, 15)
            XCTAssertTrue((error as! IntentExport.ImportError).message.contains("mouth left out"))
        }
    }

    // MARK: - what the package claims

    /// The sentence must say what the digest establishes and what it does not.
    func testProvenanceSaysWhatIsAndIsNotEstablished() throws {
        let withDigest = IntentExport(clip: try clip(), policyFingerprint: "deadbeef")
        XCTAssertTrue(withDigest.provenanceSentence(recipientHoldsPolicy: true)
                        .contains("digest matches"))
        XCTAssertTrue(withDigest.provenanceSentence(recipientHoldsPolicy: false)
                        .contains("cannot reproduce this motion"))

        let without = IntentExport(clip: try clip(), policyFingerprint: nil)
        let sentence = without.provenanceSentence(recipientHoldsPolicy: nil)
        XCTAssertTrue(sentence.contains("no way to check"),
                      "a filename alone is not provenance and must not read as it: \(sentence)")
    }

    /// The package makes a checkable claim and declines an unverifiable one.
    /// If a signature ever appears here, this is where the argument happens.
    func testItDoesNotClaimAuthorship() throws {
        let data = try IntentExport(clip: try clip(), policyFingerprint: "abc").encoded()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any])
        // Checked as KEYS, not as a substring of the whole document: the
        // legitimate `authored` field — meaning "a keyframe track rather than
        // the policy's own output" — contains "author" and is not a claim
        // about who wrote anything.
        let keys = Set(object.keys.map { $0.lowercased() })
        for claim in ["signature", "signedby", "signer", "verifiedby", "trusted"] {
            XCTAssertFalse(keys.contains(claim),
                           "a signature without an anchored key says nothing a recipient can act on")
        }
        XCTAssertTrue(keys.contains("authored"), "and that field is about the motion, not a person")
        XCTAssertTrue(keys.contains("policyfingerprint"), "the one checkable claim IS made")
    }
}
