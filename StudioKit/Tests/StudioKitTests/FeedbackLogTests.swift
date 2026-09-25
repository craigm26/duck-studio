import XCTest
@testable import StudioKit

/// The log is where consent is enforced after the fact: whatever the setting
/// says today, a record leaves the phone only if it said it could when it was
/// written.
final class FeedbackLogTests: XCTestCase {

    private func record(_ share: DuckFeedback.Share, clause: String = "turn left") throws -> DuckFeedback {
        try DuckFeedback.routeCorrection(
            request: clause, clause: clause, router: "m", revision: "r", vocabulary: "r001",
            proposed: ["action": "turn_left"], confidence: ["action": 0.9],
            final: ["action": "turn_left"], outcome: .accepted, share: share, client: "t")
    }

    func testAppendingWritesOneTerminatedLinePerRecord() throws {
        let data = FeedbackLog.appending([try record(.local), try record(.research)])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(text.filter { $0 == "\n" }.count, 2)
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    func testOnlyRecordsThatSaidTheyMayLeaveAreExportable() throws {
        let log = String(decoding: FeedbackLog.appending([
            try record(.local, clause: "a"), try record(.research, clause: "b"),
            try record(.public, clause: "c"),
        ]), as: UTF8.self)
        let out = FeedbackLog.exportable(log)
        XCTAssertEqual(out.count, 2)
        XCTAssertFalse(out.contains { $0.contains(#""clause":"a""#) }, "the local one stays")
        XCTAssertEqual(FeedbackLog.counts(log).all, 3)
        XCTAssertEqual(FeedbackLog.counts(log).exportable, 2)
    }

    func testALineThatIsNotARecordIsNeverExported() {
        let log = "not json\n{\"consent\":{\"share\":\"public\"}}\n"
        XCTAssertEqual(FeedbackLog.exportable(log), [], "no opt_in, no export")
    }

    func testTheSettingOffersEveryChoiceInWordsAndSaysNothingIsSentAutomatically() {
        XCTAssertEqual(Set(DuckFeedback.Share.allCases.map(FeedbackLog.settingChoice)).count, 3)
        XCTAssertTrue(FeedbackLog.settingFooter.contains("nothing is ever sent automatically"))
        XCTAssertEqual(FeedbackLog.exportLine(all: 1, exportable: 0),
                       "1 record on this phone, 0 of them allowed to leave it.")
    }

    func testThePlanEditorSaysHowUnsureTheRouterWasInItsOwnNumber() {
        XCTAssertEqual(PlanEditorWords.unsure(.head, confidence: 0.52),
                       "Check the head — the router was unsure (52%).")
        XCTAssertEqual(PlanEditorWords.flaggedLeft(1),
                       "1 label is still flagged. You can run anyway; it will go as proposed.")
        XCTAssertTrue(PlanEditorWords.routerFooter.contains("no server of its own"))
    }
}
