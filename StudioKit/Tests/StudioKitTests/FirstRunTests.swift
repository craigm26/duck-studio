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

    /// Then straight to playing, admitting there is probably no robot yet and
    /// saying it does not matter.
    func testTheSecondCardSendsYouToPlayWithoutARobot() {
        let play = FirstRun.steps[1]
        XCTAssertEqual(play.tab, "Play")
        XCTAssertTrue(play.body.contains("Christmas 2026"))
        XCTAssertTrue(play.body.contains("without one"))
    }

    /// Every step that names a tab has to name one that exists.
    func testEveryNamedTabIsARealTab() {
        let real = Set(["Play", "Learn", "Behaviours", "Studio", "My Microduck"])
        for step in FirstRun.steps {
            guard let tab = step.tab else { continue }
            XCTAssertTrue(real.contains(tab), "\(tab) is not a tab")
        }
    }

    /// The claim the whole app rests on must survive into the onboarding: a
    /// preview is what you asked for, not what the robot would do.
    func testItRepeatsTheOneCaveatThatMatters() {
        let text = FirstRun.steps.map(\.body).joined(separator: " ")
        XCTAssertTrue(text.contains("A preview runs no physics"))
        XCTAssertFalse(text.contains("phone has no physics"))
        XCTAssertTrue(text.contains("ASKED"))
    }

    /// THREE CARDS. It was six and a question; a person who wants to drive a
    /// duck should be driving it after three swipes.
    func testTheStepsAreShortAndOrdered() {
        XCTAssertEqual(FirstRun.steps.map(\.id), ["not-official", "play", "learn"])
        for step in FirstRun.steps.dropFirst() {
            XCTAssertLessThan(step.body.split(separator: " ").count, 40, step.id)
        }
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
        XCTAssertTrue(FirstRun.shouldShow(seenVersion: 2))
        XCTAssertFalse(FirstRun.shouldShow(seenVersion: FirstRun.currentVersion))
        XCTAssertFalse(FirstRun.shouldShow(seenVersion: FirstRun.currentVersion + 1))
    }
}
