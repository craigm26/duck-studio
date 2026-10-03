import XCTest
@testable import StudioKit

final class BehavioursWordsTests: XCTestCase {

    /// A door on the list is one line: one sentence, short enough not to wrap
    /// into a paragraph on a phone.
    func testDoorsAreOneLine() {
        for line in [BehavioursWords.pollenDoor, BehavioursWords.communityDoor,
                     BehavioursWords.challengesDoor, BehavioursWords.browseCommunity] {
            XCTAssertFalse(line.contains(". "), line)
            XCTAssertLessThanOrEqual(line.count, 60, line)
        }
    }

    /// The lines a footer leads with are one sentence each, or two short ones.
    func testFooterLinesAreShort() {
        for line in [BehavioursWords.retrainLine, BehavioursWords.nothingRecordedLine,
                     BehavioursWords.recordedLine] {
            XCTAssertLessThanOrEqual(line.count, 90, line)
        }
    }

    /// THE CAVEATS MOVED, THEY WERE NOT DELETED. Each note still says the thing
    /// that keeps the screen honest.
    func testTheNotesKeepTheCaveats() {
        XCTAssertTrue(BehavioursWords.retrainNote.contains("Python, mjlab and a GPU"))
        XCTAssertTrue(BehavioursWords.retrainNote.contains("Nothing here keeps a request"))
        XCTAssertTrue(BehavioursWords.nothingRecordedNote.contains("no time axis"))
        XCTAssertTrue(BehavioursWords.nothingRecordedNote.contains("cannot play a policy"))
        XCTAssertTrue(BehavioursWords.recordedNote.contains("not what somebody asked for"))
        XCTAssertTrue(BehavioursWords.recordedNote.contains("no time axis"))
    }

    func testTheHiddenLineNamesEverySectionOnce() {
        XCTAssertNil(BehavioursWords.hiddenLine([]))
        XCTAssertEqual(BehavioursWords.hiddenLine(["Publishing"]),
                       "Hidden in Simple: Publishing. Settings → Detail shows it.")
        XCTAssertEqual(BehavioursWords.hiddenLine(["Physics bench", "Publishing"]),
                       "Hidden in Simple: Physics bench, Publishing. Settings → Detail shows them.")
    }

    func testNoEmDashes() {
        let all = [BehavioursWords.pollenDoor, BehavioursWords.communityDoor,
                   BehavioursWords.challengesDoor, BehavioursWords.browseCommunity,
                   BehavioursWords.retrainLine, BehavioursWords.retrainNote,
                   BehavioursWords.nothingRecordedLine, BehavioursWords.nothingRecordedNote,
                   BehavioursWords.recordedLine, BehavioursWords.recordedNote]
        for s in all { XCTAssertFalse(s.contains("\u{2014}"), s) }
    }
}
