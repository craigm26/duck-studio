import XCTest
@testable import StudioKit

/// A contribution is a pull request anyone can read the moment it is opened,
/// so the tests hold what may go into one: public records only, each once,
/// under a path that says nothing about who sent it.
final class CommunityFeedbackTests: XCTestCase {

    private let stamp = Date(timeIntervalSince1970: 1_790_000_000)  // 2026-09-21

    private func log(_ shares: [DuckFeedback.Share]) throws -> String {
        let records = try shares.enumerated().map { i, share in
            try DuckFeedback.routeCorrection(
                request: "r\(i)", clause: "c\(i)", router: "m", revision: "r", vocabulary: "r001",
                proposed: ["action": "stop"], confidence: ["action": 0.9],
                final: ["action": "stop"], outcome: .accepted, share: share, client: "t",
                id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", i))!)
        }
        return String(decoding: FeedbackLog.appending(records), as: UTF8.self)
    }

    func testOnlyPublicRecordsAreEligibleBecauseAPullRequestIsReadableAtOnce() throws {
        let pending = CommunityFeedback.pending(try log([.local, .research, .public, .public]),
                                                alreadySent: [])
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.allSatisfy { $0.line.contains(#""share":"public""#) })
    }

    func testARecordAlreadyContributedIsNotSentAgain() throws {
        let text = try log([.public, .public])
        let first = CommunityFeedback.pending(text, alreadySent: [])
        let again = CommunityFeedback.pending(text, alreadySent: Set(first.prefix(1).map(\.id)))
        XCTAssertEqual(again.map(\.id), [first[1].id])
    }

    func testTheContributionIsAPullRequestAgainstTheCommunityDataset() throws {
        let call = try CommunityFeedback.contribution(["{}"], at: stamp,
            contribution: UUID(uuidString: "11111111-2222-4333-8444-555555555555")!)
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.url.absoluteString,
            "https://huggingface.co/api/datasets/craigm26/microduck-feedback/commit/main?create_pr=1")
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: call.body ?? Data()) as? [String: Any])
        let file = try XCTUnwrap((body["files"] as? [[String: Any]])?.first)
        XCTAssertEqual(file["path"] as? String,
                       "contributions/2026-09-21/11111111-2222-4333-8444-555555555555.jsonl",
                       "dated, and named by a fresh id rather than by anything about the person")
        XCTAssertEqual(file["content"] as? String, "{}\n")
    }

    func testNothingToSendIsRefusedByNameBeforeATokenIsSpent() {
        XCTAssertThrowsError(try CommunityFeedback.contribution([])) { error in
            XCTAssertEqual(error as? CommunityFeedback.Refusal, .nothingToSend)
        }
    }

    func testThePullRequestLinkIsReadFromTheAnswer() {
        let answer = Data(#"{"commitOid":"abc","pullRequestUrl":"https://huggingface.co/datasets/craigm26/microduck-feedback/discussions/3"}"#.utf8)
        XCTAssertEqual(CommunityFeedback.pullRequest(from: answer)?.lastPathComponent, "3")
        XCTAssertNil(CommunityFeedback.pullRequest(from: Data("{}".utf8)))
    }

    func testTheScreenSaysTheUsernameIsOnTheRequestBeforeAnythingIsSent() {
        let line = CommunityFeedback.explain(pending: 2)
        XCTAssertTrue(line.contains("your username is on the request"))
        XCTAssertTrue(line.contains("CC0-1.0"))
        XCTAssertTrue(line.hasPrefix("2 records"))
        XCTAssertEqual(CommunityFeedback.contributingAs("someone"),
                       "Contributing as someone on Hugging Face")
    }

    /// Writes the exact request for a live check, when asked to:
    /// `DUCK_COMMUNITY_CALL_OUT=… swift test --filter CommunityFeedbackTests`.
    func testWritesTheContributionRequestForALiveCheck() throws {
        guard let out = ProcessInfo.processInfo.environment["DUCK_COMMUNITY_CALL_OUT"] else { return }
        let text = try log([.public])
        let lines = CommunityFeedback.pending(text, alreadySent: []).map(\.line)
        let call = try CommunityFeedback.contribution(lines)
        try call.url.absoluteString.write(toFile: out + ".url", atomically: true, encoding: .utf8)
        try (call.body ?? Data()).write(to: URL(fileURLWithPath: out + ".json"))
    }
}
