import XCTest
@testable import StudioKit

final class FirstRunTests: XCTestCase {

    /// THE FIRST CARD SAYS THIS IS NOT POLLEN'S APP, in their word, with the
    /// whole claim under it — pollen-robotics/microduck#329.
    func testItOpensBySayingThisIsNotTheOfficialApp() {
        let first = FirstRun.steps.first
        XCTAssertEqual(first?.id, "not-official")
        XCTAssertEqual(first?.title, Provenance.notOfficialTitle)
        XCTAssertEqual(first?.body, Provenance.independence)
    }

    /// Everybody who saw the run without that card sees it once more.
    func testTheRunIsShownAgainToAnybodyWhoSawVersionOne() {
        XCTAssertTrue(FirstRun.shouldShow(seenVersion: 1))
    }

    /// THE SECOND LINE HAS TO ADMIT THERE IS NO ROBOT. An app that starts with
    /// "pair your Microduck" fails for every person who has it today, because
    /// Pollen's first deliveries are around Christmas 2026.
    func testItOpensByAdmittingTheRobotDoesNotExistYet() {
        let first = FirstRun.steps.dropFirst().first
        XCTAssertEqual(first?.id, "no-duck")
        XCTAssertTrue(first!.body.contains("Christmas 2026"))
        XCTAssertTrue(first!.title.lowercased().contains("not have"))
    }

    /// And then says what works anyway, or the first card is just bad news.
    func testTheFirstCardAlsoSaysWhatWorksWithoutOne() {
        XCTAssertTrue(FirstRun.steps[1].body.contains("without one"))
    }

    /// Every step that names a tab has to name one that exists.
    func testEveryNamedTabIsARealTab() {
        let real = Set(["My Microduck", "Control", "Behaviours", "Studio", "Robot"])
        for step in FirstRun.steps {
            guard let tab = step.tab else { continue }
            XCTAssertTrue(real.contains(tab), "\(tab) is not a tab")
        }
    }

    /// The claim the whole app rests on must survive into the onboarding: a
    /// preview is what you asked for, not what the robot would do.
    func testItRepeatsTheOneCaveatThatMatters() {
        let text = FirstRun.steps.map(\.body).joined(separator: " ")
        // NOT "a phone has no physics engine": the phone IS a bench now —
        // PhoneBenchReport.premiseWasAboutABuild — and this card said the
        // stale thing until a screenshot showed both claims on one screen.
        XCTAssertTrue(text.contains("a preview runs no physics"))
        XCTAssertFalse(text.contains("phone has no physics"))
        XCTAssertTrue(text.contains("ASKED"))
    }

    func testTheStepsAreOrderedForSomebodyWithNothing() {
        XCTAssertEqual(FirstRun.steps.map(\.id),
                       ["not-official", "no-duck", "watch", "make", "play", "arrives"])
    }

    func testStepIdsAreUniqueAndNothingIsEmpty() {
        XCTAssertEqual(Set(FirstRun.steps.map(\.id)).count, FirstRun.steps.count)
        for step in FirstRun.steps {
            XCTAssertFalse(step.title.isEmpty)
            XCTAssertGreaterThan(step.body.count, 40, "\(step.id) is too thin to be worth a card")
        }
    }

    /// It asks once and never again, whichever way somebody leaves it.
    func testItIsShownOnceAndThenNot() {
        XCTAssertTrue(FirstRun.shouldShow(seenVersion: nil))
        XCTAssertTrue(FirstRun.shouldShow(seenVersion: 0))
        XCTAssertFalse(FirstRun.shouldShow(seenVersion: FirstRun.currentVersion))
        XCTAssertFalse(FirstRun.shouldShow(seenVersion: FirstRun.currentVersion + 1))
    }

    /// The detail question explains itself. Asking somebody to pick a mode
    /// without saying why is how they pick wrong and blame the app.
    func testTheDetailQuestionSaysWhyItIsBeingAsked() {
        XCTAssertTrue(FirstRun.detailWhy.contains("train"))
        XCTAssertTrue(FirstRun.detailWhy.contains("own the robot"))
        XCTAssertTrue(FirstRun.detailWhy.contains("Settings"))
    }
}
