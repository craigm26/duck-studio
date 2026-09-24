import XCTest
@testable import StudioKit

/// The records this app writes must be ones craigm26/duckbatch's reader accepts:
/// consent on every record, refusals with the reader's reasons, and a fixed
/// wire shape. The cross-check against the Python reader itself is run by hand
/// and recorded in the PR (`duckbatch feedback validate` on this suite's output).
final class DuckFeedbackTests: XCTestCase {

    private let stamp = Date(timeIntervalSince1970: 1_790_000_000)

    private func correction(outcome: DuckFeedback.Outcome = .edited,
                            final: [String: String]? = ["action": "turn_left", "speed": "normal", "head": "straight"],
                            share: DuckFeedback.Share = .research) throws -> DuckFeedback {
        try DuckFeedback.routeCorrection(
            request: "turn left then say hello", clause: "turn left",
            router: "fastino/GLiNER2.5-Decide", revision: "65624f1", vocabulary: "r001",
            proposed: ["action": "turn_left", "speed": "normal", "head": "look_left"],
            confidence: ["action": 0.71, "speed": 0.66, "head": 0.56],
            final: final, outcome: outcome, share: share, client: "Microduck Studio test",
            id: UUID(uuidString: "7F3C0000-0000-4000-8000-000000000001")!, created: stamp)
    }

    private func decode(_ line: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
    }

    func testACorrectionCarriesConsentAndNothingThatIdentifiesAPerson() throws {
        let r = try decode(try correction().jsonLine())
        XCTAssertEqual(r["format"] as? String, "duck-feedback/0")
        XCTAssertEqual(r["kind"] as? String, "route_correction")
        XCTAssertEqual(r["created"] as? String, "2026-09-21T14:13:20Z")
        XCTAssertEqual((r["consent"] as? [String: Any])?["opt_in"] as? Bool, true)
        XCTAssertEqual((r["consent"] as? [String: Any])?["share"] as? String, "research")
        XCTAssertEqual(Set(r.keys), ["format", "id", "created", "kind", "consent", "source", "route_correction"],
                       "no field beyond the spec's: nothing about the person or the device")
        let body = try XCTUnwrap(r["route_correction"] as? [String: Any])
        XCTAssertEqual(body["outcome"] as? String, "edited")
        XCTAssertEqual((body["final"] as? [String: Any]).flatMap { $0["labels"] as? [String: String] }?["head"],
                       "straight")
    }

    func testTheOutcomeMustMatchWhatChanged() {
        XCTAssertThrowsError(try correction(outcome: .accepted)) {
            XCTAssertEqual($0 as? DuckFeedback.Refusal, .acceptedButChanged)
        }
        XCTAssertThrowsError(try correction(outcome: .edited,
                                            final: ["action": "turn_left", "speed": "normal", "head": "look_left"])) {
            XCTAssertEqual($0 as? DuckFeedback.Refusal, .editedButUnchanged)
        }
        XCTAssertNoThrow(try correction(outcome: .rejected, final: nil))
    }

    func testALocalRecordSaysItMayNotLeaveTheDevice() throws {
        XCTAssertFalse(try correction(share: .local).mayLeaveDevice)
        XCTAssertTrue(try correction(share: .public).mayLeaveDevice)
    }

    func testAPreferenceIsBetweenTwoNetworksWithReasonsFromTheList() throws {
        let a = DuckFeedback.Policy(repo: "craigm26/microduck-duckbatch-b002-128x128",
                                    fingerprint: "sha256:aa")
        let b = DuckFeedback.Policy(repo: "pollen-robotics/microduck-policies", file: "velstand.onnx",
                                    fingerprint: "sha256:bb")
        let line = try DuckFeedback.policyPreference(
            a: a, b: b, choice: .b, reasons: [.steadier, .moreNatural], where: .sim, order: .aLeft,
            command: [0.15, 0, 0], seconds: 6, seed: 2001, pairID: "p001/0042",
            share: .research, client: "Microduck Studio test", created: stamp).jsonLine()
        let body = try XCTUnwrap(try decode(line)["policy_preference"] as? [String: Any])
        XCTAssertEqual(body["choice"] as? String, "b")
        XCTAssertEqual(body["reasons"] as? [String], ["steadier", "more natural"])
        XCTAssertEqual((body["shown"] as? [String: Any])?["order"] as? String, "a_left")
        XCTAssertThrowsError(try DuckFeedback.policyPreference(
            a: a, b: a, choice: .a, where: .sim, order: .aLeft, share: .research, client: "t")) {
            XCTAssertEqual($0 as? DuckFeedback.Refusal, .sameNetwork)
        }
    }

    /// Writes a small file the Python reader can be pointed at, when asked to.
    func testWritesAFileForTheReaderCrossCheck() throws {
        guard let out = ProcessInfo.processInfo.environment["DUCK_FEEDBACK_OUT"] else { return }
        let a = DuckFeedback.Policy(repo: "x/a", fingerprint: "sha256:aa")
        let b = DuckFeedback.Policy(repo: "x/b", fingerprint: "sha256:bb")
        let lines = [
            try correction().jsonLine(),
            try correction(outcome: .rejected, final: nil).jsonLine()
                .replacingOccurrences(of: "7f3c0000-0000-4000-8000-000000000001",
                                      with: "7f3c0000-0000-4000-8000-000000000002"),
            try DuckFeedback.policyPreference(a: a, b: b, choice: .tie, where: .phoneBench,
                                              order: .bLeft, share: .public, client: "t",
                                              created: stamp).jsonLine(),
        ]
        try (lines.joined(separator: "\n") + "\n").write(toFile: out, atomically: true, encoding: .utf8)
    }
}
