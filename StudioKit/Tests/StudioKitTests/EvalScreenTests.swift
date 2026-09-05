import XCTest
@testable import StudioKit

/// The words on the six evaluation screens, read letter by letter.
///
/// `scripts/check_stage_sentences.sh` proves a screen draws no literal of its
/// own. It cannot prove that what the screen draws instead says anything, which
/// is what this file is for: every heading and every button verb pinned to its
/// exact text, so changing one is a decision somebody made rather than a typo
/// somebody shipped.
final class EvalScreenTests: XCTestCase {

    func testTheShelfSaysWhatItSays() {
        XCTAssertEqual(EvalScreen.newEvaluationSaid, "New evaluation")
        XCTAssertEqual(EvalScreen.runOneHeading, "Run one")
        XCTAssertEqual(EvalScreen.deleteSaid, "Delete")
        XCTAssertEqual(EvalScreen.savedHeading, "Saved")
        XCTAssertEqual(EvalScreen.putTwoSideBySideSaid, "Put two side by side")
        XCTAssertEqual(EvalScreen.compareHeading, "Compare")
        XCTAssertEqual(EvalScreen.openALogFromElsewhereSaid, "Open a log from elsewhere")
        XCTAssertEqual(EvalScreen.openOneFromElsewhereHeading, "Open one from elsewhere")
    }

    func testSettingOneUpSaysWhatItSays() {
        XCTAssertEqual(EvalScreen.whatToEvaluateHeading, "What to evaluate")
        XCTAssertEqual(EvalScreen.whatIsBeingEvaluatedHeading, "What is being evaluated")
        XCTAssertEqual(EvalScreen.whereItRunsHeading, "Where it runs")
        XCTAssertEqual(EvalScreen.whatVariesHeading, "What varies, and how it is collapsed")
        XCTAssertEqual(EvalScreen.howItIsScoredHeading, "How it is scored")
        XCTAssertEqual(EvalScreen.askMeAboutTheTrialSaid, "Ask me about the trial it recorded")
        XCTAssertEqual(EvalScreen.watchAndJudgeHeading, "Watch and judge it")
        XCTAssertEqual(EvalScreen.askingThisBenchSaid, "Asking this bench what it can do")
        XCTAssertEqual(EvalScreen.startSaid, "Start")
    }

    func testTheRunScreenSaysWhatItSays() {
        XCTAssertEqual(EvalScreen.runningHeading, "Running")
        XCTAssertEqual(EvalScreen.scenesSaid, "Scenes")
        XCTAssertEqual(EvalScreen.benchSaid, "Bench")
        XCTAssertEqual(EvalScreen.whereItRanHeading, "Where it ran")
        XCTAssertEqual(EvalScreen.stopSaid, "Stop")
        XCTAssertEqual(EvalScreen.openTheLogSaid, "Open the log")
        XCTAssertEqual(EvalScreen.shareTheLogAndTheReportSaid, "Share the log and the report")
        XCTAssertEqual(EvalScreen.whatItWroteHeading, "What it wrote")
    }

    func testTheVerdictSheetSaysWhatItSays() {
        XCTAssertEqual(EvalScreen.watchItHeading, "Watch it")
        XCTAssertEqual(EvalScreen.whatItWasAskedToDoHeading, "What it was asked to do")
        XCTAssertEqual(EvalScreen.noteSaid, "Note")
        XCTAssertEqual(EvalScreen.yourVerdictHeading, "Your verdict")
        XCTAssertEqual(EvalScreen.skipThisOneSaid, "Skip this one")
        XCTAssertEqual(EvalScreen.stopWatchingSaid, "Stop watching")
    }

    func testTheLabNotebookSaysWhatItSays() {
        XCTAssertEqual(EvalScreen.whatRanHeading, "What ran")
        XCTAssertEqual(EvalScreen.metricsHeading, "Metrics")
        XCTAssertEqual(EvalScreen.errorsHeading, "Errors")
        XCTAssertEqual(EvalScreen.whatThisIsNotHeading, "What this is not")
        XCTAssertEqual(EvalScreen.shareHeading, "Share")
        XCTAssertEqual(EvalScreen.sendItSomewhereSaid, "Send it somewhere")
        XCTAssertEqual(EvalScreen.publishItHeading, "Publish it")
    }

    func testComparingTwoSaysWhatItSays() {
        XCTAssertEqual(EvalScreen.sideBySideTitle, "Side by side")
        XCTAssertEqual(EvalScreen.leftSaid, "Left")
        XCTAssertEqual(EvalScreen.rightSaid, "Right")
        XCTAssertEqual(EvalScreen.whichTwoHeading, "Which two")
        XCTAssertEqual(EvalScreen.notSideBySideHeading, "Not side by side")
        XCTAssertEqual(EvalScreen.bothScorerByScorerHeading, "Both, scorer by scorer")
    }

    /// The list is the sweep's input, so a constant that is not in it is a
    /// constant nothing checks. The count is written down so adding one without
    /// adding it here is a red test rather than a silent gap.
    func testEveryWordIsInTheList() {
        XCTAssertEqual(EvalScreen.everyWord.count, 44)
        XCTAssertEqual(Set(EvalScreen.everyWord).count, EvalScreen.everyWord.count,
                       "two of these are the same word")
        for word in [EvalScreen.newEvaluationSaid, EvalScreen.savedHeading,
                     EvalScreen.startSaid, EvalScreen.stopSaid,
                     EvalScreen.publishItHeading, EvalScreen.bothScorerByScorerHeading] {
            XCTAssertTrue(EvalScreen.everyWord.contains(word), word)
        }
    }

    /// A LABEL IS NOT A SENTENCE. Everything here goes in a section header, on
    /// a button or on a field, where a full stop is a full stop nobody asked
    /// for, and where a string long enough to wrap twice is a row nobody scans.
    /// The claims those labels sit above are the sentences, and they live on
    /// the types that own them.
    func testEveryWordIsALabelAndNotAParagraph() {
        for word in EvalScreen.everyWord {
            XCTAssertFalse(word.isEmpty)
            XCTAssertEqual(word, word.trimmingCharacters(in: .whitespaces), word)
            XCTAssertFalse(word.hasSuffix("."), "\(word) is a label, not a sentence")
            XCTAssertLessThanOrEqual(word.count, 40, "\(word) is too long for a row")
            XCTAssertFalse(word.contains("\u{2014}"), "\(word) has an em dash")
        }
    }

    /// The two words the Hugging Face flow says on this screen, which live on
    /// the type that owns the protocol rather than on this feature, because
    /// four other screens in this app say the same two things and there should
    /// be one place to change them.
    func testThePublishFlowSaysWhatItSays() {
        XCTAssertEqual(HuggingFacePublish.publishingAs("craigm26"), "Publishing as craigm26")
        XCTAssertEqual(HuggingFacePublish.openItOnHuggingFace, "Open it on Hugging Face")
        XCTAssertTrue(HuggingFacePublish.publishingAs("a-b_c").hasSuffix("a-b_c"),
                      "the account is named as the Hub spells it")
    }
}
