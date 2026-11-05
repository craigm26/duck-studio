import XCTest
@testable import StudioKit

final class OnboardingTests: XCTestCase {

    func testPageOneAsksAboutTheDuckAndSaysWhoseAppThisIsNot() {
        let first = Onboarding.pages[0]
        XCTAssertEqual(first.id, .haveDuck)
        XCTAssertEqual(first.title, "Do you have a Microduck with you?")
        XCTAssertEqual(first.choices.map(\.label), ["Yes, it's here and on my Wi-Fi",
                                                    "It's here, but not on Wi-Fi yet",
                                                    "Not yet, let me practise"])
        XCTAssertEqual(Onboarding.next(from: .haveDuck, choosing: .yesItsHere), .page(.find))
        XCTAssertEqual(Onboarding.next(from: .haveDuck, choosing: .hereNotOnWifi), .page(.wifiHelp))
        XCTAssertEqual(first.smallPrint,
                       "Microduck Studio is a companion app, not Pollen's official app.")
        XCTAssertFalse(Onboarding.companionLine.lowercased().contains("unofficial"),
                       "a plain negation of official, as Provenance says")
    }

    func testThePagesAreInTheOrderOfThePlan() {
        XCTAssertEqual(Onboarding.pages.map(\.id), Onboarding.PageID.allCases)
        XCTAssertEqual(Onboarding.page(.wifi).title, "Is your duck on your Wi-Fi?")
        XCTAssertEqual(Onboarding.page(.find).title, "Let Studio find your duck on this network")
        XCTAssertEqual(Onboarding.page(.standUp).choices.map(\.label), ["Stand up"])
    }

    func testEveryPageHasExactlyOneProminentButtonAndEveryChoiceGoesSomewhere() {
        for page in Onboarding.pages {
            XCTAssertEqual(page.choices.filter(\.prominent).count, 1, page.id.rawValue)
            for choice in page.choices {
                XCTAssertNotEqual(Onboarding.next(from: page.id, choosing: choice.id), .page(page.id),
                                  "\(page.id).\(choice.id) goes nowhere")
            }
        }
    }

    func testNotYetGoesStraightToThePracticeDuck() {
        XCTAssertEqual(Onboarding.next(from: .haveDuck, choosing: .notYet),
                       .controller(onPracticeDuck: true))
        XCTAssertEqual(Onboarding.next(from: .find, choosing: .practiceInstead),
                       .controller(onPracticeDuck: true))
    }

    func testWifiHelpPointsAtPollensAppAndDoesNotRebuildIt() {
        XCTAssertEqual(Onboarding.next(from: .wifi, choosing: .notOnWifi), .page(.wifiHelp))
        let help = Onboarding.page(.wifiHelp)
        XCTAssertTrue(help.body?.contains("Pollen's Microduck app does Wi-Fi, updates and sign-in") == true)
        XCTAssertEqual(help.choices.map(\.label), ["Open Pollen's app", "I've done that"])
        XCTAssertEqual(Onboarding.next(from: .wifiHelp, choosing: .openPollensApp), .openPollensApp)
        XCTAssertEqual(Onboarding.next(from: .wifiHelp, choosing: .doneThat), .page(.find))
    }

    func testAddYourDuckReentersAtTheWifiPage() {
        XCTAssertEqual(Onboarding.addYourDuckStart, .wifi)
    }

    func testTheRealDuckEndsOnTheControllerOnTheRealDuck() {
        XCTAssertEqual(Onboarding.next(from: .sayHi, choosing: .notMine), .page(.find))
        XCTAssertEqual(Onboarding.next(from: .standUp, choosing: .standUp),
                       .controller(onPracticeDuck: false))
    }

    /// The happy path, walked through `next`, really ends on the real duck.
    /// It is four taps, the plan's exit check, and the two safety presses are still in it: the
    /// quack asks whether this duck is yours, and Stand up is its own press.
    func testTheHappyPathIsFourTaps() {
        var at: Onboarding.Destination = .page(.haveDuck)
        for (page, choice) in Onboarding.tapsToStand {
            XCTAssertEqual(at, .page(page))
            at = Onboarding.next(from: page, choosing: choice)
        }
        XCTAssertEqual(at, .controller(onPracticeDuck: false))
        XCTAssertEqual(Onboarding.tapsToStand.count, 4)
        XCTAssertLessThanOrEqual(Onboarding.tapsToStand.count, 4)
        XCTAssertTrue(Onboarding.tapsToStand.contains { $0.0 == .sayHi && $0.1 == .quacked })
        XCTAssertTrue(Onboarding.tapsToStand.contains { $0.0 == .standUp && $0.1 == .standUp })
    }

    func testDiscoveryTriesBluetoothFirstAndTypingLastAndFlagsBluetoothUnverified() {
        XCTAssertEqual(Onboarding.Discovery.allCases, [.bluetooth, .bonjour, .code, .typed])
        XCTAssertEqual(Onboarding.Discovery.typed.label, "Type it")
        XCTAssertFalse(Onboarding.Discovery.bluetooth.verified)
    }

    func testARefusalIsTheRobotsReasonInPlainWords() {
        XCTAssertEqual(Onboarding.standRefused(because: "it is busy."),
                       "Your duck did not stand up: it is busy.")
        XCTAssertEqual(Onboarding.standRefused(because: "  "), "Your duck did not stand up.")
        XCTAssertEqual(Onboarding.sittingRefusal,
                       "Your duck is sitting; it can only stand up from here.")
    }

    func testCoachMarksAndTheSiriTip() {
        XCTAssertEqual(Onboarding.coachMarks,
                       ["Press Stand", "Push the stick a little", "Tap the red disc any time to stop"])
        XCTAssertEqual(Onboarding.siriTip, "Say: Duck Studio, stop the duck.")
    }

    /// The app cannot place a Control or set the Action button, so the card
    /// shows steps and never says it did them.
    func testMakeItYoursNeverClaimsToHaveDoneIt() {
        XCTAssertEqual(Onboarding.makeItYoursSteps.count, 3)
        for step in Onboarding.makeItYoursSteps {
            for claim in ["added", "is now", "done", "we set", "we put"] {
                XCTAssertFalse(step.lowercased().contains(claim), step)
            }
        }
    }

    func testReturningLaunchesWaitBrieflyAndNeverSwitchByThemselves() {
        XCTAssertEqual(Onboarding.reconnectWait, 1.5)
        XCTAssertEqual(Onboarding.practiceDuck, "Practice duck")
        XCTAssertEqual(Onboarding.reconnect, "Reconnect")
    }

    func testItIsForAFreshInstallOnly() {
        XCTAssertTrue(Onboarding.shouldShow(seenFirstRunVersion: nil))
        XCTAssertFalse(Onboarding.shouldShow(seenFirstRunVersion: FirstRun.currentVersion))
        XCTAssertFalse(Onboarding.shouldShow(seenFirstRunVersion: 1))
    }

    /// Onboarding never mentions benches, models, Hugging Face, detail levels,
    /// MuJoCo, deadman or policy.
    func testItNeverTalksShop() {
        let banned = ["bench", "model", "hugging face", "detail", "mujoco", "deadman", "policy",
                      "policies", "simple", "everything"]
        for line in Onboarding.allWords {
            let lower = line.lowercased()
            for word in banned {
                XCTAssertFalse(lower.contains(word), "\"\(line)\" says \(word)")
            }
        }
    }

    func testEverySentenceIsNonEmptyAndHasNoEmDash() {
        for line in Onboarding.allWords {
            XCTAssertFalse(line.isEmpty)
            XCTAssertFalse(line.contains("\u{2014}"), line)
        }
    }

    /// Build 93: the stick mark first, then the Stop mark, each once, only in Drive.
    func testCoachMarksShowOneAtATimeInDriveAndGoForGood() {
        var marks = Onboarding.CoachMarks()
        XCTAssertEqual(marks.showing(in: .drive), .stick)
        XCTAssertNil(marks.showing(in: .tell))
        XCTAssertNil(marks.showing(in: .auto))
        marks.did(.stick)
        XCTAssertEqual(marks.showing(in: .drive), .stop)
        XCTAssertEqual(marks.showing(in: .drive)?.says, "Tap the red disc any time to stop")
        marks.did(.stop)
        XCTAssertNil(marks.showing(in: .drive))
        // Kept as a bit set and read back the same.
        XCTAssertNil(Onboarding.CoachMarks(done: marks.done).showing(in: .drive))
        // A Stop pressed before any drive still counts.
        var early = Onboarding.CoachMarks()
        early.did(.stop)
        XCTAssertEqual(early.showing(in: .drive), .stick)
        early.did(.stick)
        XCTAssertNil(early.showing(in: .drive))
        XCTAssertEqual(Onboarding.CoachMarks.Mark.stick.says, "Push the stick a little")
        XCTAssertEqual(Onboarding.CoachMarks.Mark.stop.symbol, "stop.circle")
    }
}
