import XCTest
import DuckKit
@testable import StudioKit

/// The player piano, pinned.
///
/// WHAT THESE TESTS ARE ACTUALLY DEFENDING is not arithmetic — the arithmetic
/// here is four additions — it is three claims about the robot that a future
/// change would find it very easy and very appealing to break. That a score is
/// playback rather than a flock, so nothing in it reads one duck and steers
/// another. That one duck falling out ends the piece, because the robots
/// cannot tell that it has and nobody else is watching. And — the one that
/// took a wrong turn once already — that what this app can do about two
/// writers on one duck is keep its OWN screens apart, and that it says so
/// rather than promising an exclusion `duck-ipc-proto` gives it no method to
/// arrange. Several assertions below are about what a sentence must NOT say,
/// which is unusual and is the point: the previous version of that sentence
/// passed every test there was.
///
/// EVERY CLOCK IN THIS FILE IS A `Double` SOMEBODY TYPED. There is no `Date()`
/// anywhere in `Choreography`, so a whole performance — the lead-in, the
/// stagger, the abort — runs here in microseconds and the assertions are about
/// instants rather than about "roughly when".
final class ChoreographyTests: XCTestCase {

    // MARK: - fixtures

    private let ada = DuckID("ada")
    private let bo = DuckID("bo")
    /// BOTH WRITERS ARE SCREENS OF THIS APP, AND THE FIXTURE IS NAMED THAT WAY
    /// ON PURPOSE. They used to be "this phone" and "Ada's phone", which read
    /// as two devices and made every assertion below look like a test of
    /// exclusion between people. `LocalWriterAdvisory` is a dictionary in one
    /// process: nothing on Ada's phone can ever appear in it, so a fixture
    /// named for her phone was describing a scenario the type has never been
    /// able to see.
    private let me = LocalWriterAdvisory.Writer("the drive screen")
    private let them = LocalWriterAdvisory.Writer("the score screen")

    /// A quick link: 60 ms typical, 40–80 ms measured.
    private func quickLink() throws -> RoundTrip {
        try RoundTrip(samples: [0.040, 0.060, 0.080])
    }

    /// A slow one: 100 ms typical, and it has been seen at 140.
    private func slowLink() throws -> RoundTrip {
        try RoundTrip(samples: [0.100, 0.100, 0.140])
    }

    /// Both ducks asked to do the same thing on the same beat — the case the
    /// whole file is about.
    private func unisonScore() throws -> Score {
        try Score([
            Score.Step(at: 0, duck: ada, call: .move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0))),
            Score.Step(at: 0, duck: bo, call: .move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0))),
            Score.Step(at: 1, duck: ada, call: .stop),
            Score.Step(at: 1, duck: bo, call: .stop),
        ])
    }

    private func unisonPlan(startingAt: Double = 0) throws -> Score.Plan {
        try unisonScore().schedule(startingAt: startingAt,
                                   roundTrips: [ada: quickLink(), bo: slowLink()])
    }

    /// An advisory in which this app has noted `me` as the driver of both
    /// ducks. It is returned by value and every caller keeps it in a `var`,
    /// because `ScoreRun` renews through it on every advance.
    private func advisoryHoldingBoth(at now: Double = 0) throws -> LocalWriterAdvisory {
        var advisory = LocalWriterAdvisory()
        try advisory.note(ada, driver: me, at: now)
        try advisory.note(bo, driver: me, at: now)
        return advisory
    }

    // MARK: - the score is a roll of holes, not a flock

    /// THE CENTRAL CLAIM, TESTED THE ONLY WAY IT CAN BE FROM HERE: what a duck
    /// is told, relative to the downbeat, is exactly what its own steps said,
    /// no matter who else is in the score. There is no term in any emission
    /// that came from another duck's state, because there is no channel over
    /// which such a term could exist — the robot's observation has no slot for
    /// a second robot. A future "formation" feature that adjusted one duck
    /// because of another would fail here, which is the point.
    func testEveryDuckGetsExactlyItsOwnStepsAndNothingFromTheOthers() throws {
        let score = try unisonScore()
        let plan = try unisonPlan()
        let downbeat = plan.startedAt + plan.leadSeconds

        for step in score.steps {
            let matching = plan.emissions.filter {
                $0.duck == step.duck && $0.call == step.call
                    && abs($0.landsAt - downbeat - step.at) < 1e-9
            }
            XCTAssertEqual(matching.count, 1,
                           "\(step.duck)'s step at \(step.at) should land exactly \(step.at) "
                           + "after the downbeat, unaltered by the presence of any other duck.")
        }
    }

    /// The same score played to one duck alone puts that duck's commands at the
    /// same offsets from the downbeat. Adding a partner changes when the piece
    /// starts — the lead-in — and changes nothing about what either duck does.
    func testAddingASecondDuckDoesNotChangeWhatTheFirstOneIsTold() throws {
        let together = try unisonPlan()
        let aloneScore = try Score(unisonScore().steps.filter { $0.duck == self.ada })
        let alone = try aloneScore.schedule(startingAt: 0, roundTrips: [ada: quickLink()])

        func offsets(_ plan: Score.Plan) -> [Double] {
            plan.emissions.filter { $0.duck == self.ada }
                .map { $0.landsAt - plan.startedAt - plan.leadSeconds }
        }
        let a = offsets(together), b = offsets(alone)
        XCTAssertEqual(a.count, b.count)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 1e-9) }
    }

    func testAScoreIsAsLongAsItsLastStep() throws {
        XCTAssertEqual(try unisonScore().seconds, 1, accuracy: 1e-12)
        XCTAssertEqual(try Score([]).seconds, 0, accuracy: 1e-12)
    }

    func testStepsAreSortedByTimeThenDuckSoTwoWritingsOfOneScoreAreEqual() throws {
        let forwards = try unisonScore()
        let backwards = try Score(unisonScore().steps.reversed())
        XCTAssertEqual(forwards, backwards)
        XCTAssertEqual(forwards.steps.map(\.at), [0, 0, 1, 1])
        XCTAssertEqual(forwards.steps.map(\.duck), [ada, bo, ada, bo])
    }

    /// A score runs forward from zero, so a step before the downbeat has no
    /// instant it could be sent at.
    func testAStepBeforeTheDownbeatIsRefused() {
        XCTAssertThrowsError(try Score([Score.Step(at: -0.5, duck: ada, call: .stop)])) { error in
            XCTAssertEqual(error as? Choreography.Problem, .stepOutOfOrder(-0.5))
        }
        XCTAssertThrowsError(try Score([Score.Step(at: .nan, duck: ada, call: .stop)]))
    }

    func testADuckIsListedOnceHoweverManyStepsItHas() throws {
        XCTAssertEqual(try unisonScore().ducks, [ada, bo])
    }

    // MARK: - bound one: skew

    /// THE ASSERTION THE WHOLE SCHEDULING TRICK EXISTS FOR. Both ducks are
    /// asked to move on the same beat; the one on the slower link is SENT TO
    /// FIRST, by exactly the difference in their one-way delays, so the two
    /// commands are intended to land at the same instant.
    func testTheDuckOnTheSlowerLinkIsSentToEarlier() throws {
        let plan = try unisonPlan()
        let firstBeat = plan.emissions.filter { $0.call != .stop }

        let toAda = try XCTUnwrap(firstBeat.first { $0.duck == self.ada })
        let toBo = try XCTUnwrap(firstBeat.first { $0.duck == self.bo })

        // bo's link is 100 ms round trip against ada's 60: 50 ms one way
        // against 30, so bo is sent to 20 ms before ada.
        XCTAssertLessThan(toBo.sendAt, toAda.sendAt)
        XCTAssertEqual(toAda.sendAt - toBo.sendAt, 0.020, accuracy: 1e-9)

        // And they are aimed at the same instant, which is what being sent at
        // different times bought.
        XCTAssertEqual(toAda.landsAt, toBo.landsAt, accuracy: 1e-9)
    }

    /// The lead-in is the slowest link's one-way delay, and the first thing
    /// sent goes out at the instant the caller asked to start — you cannot send
    /// into the past, so the downbeat moves rather than the send time.
    func testTheWholeScoreIsPushedBackByTheSlowestLink() throws {
        let plan = try unisonPlan(startingAt: 100)
        XCTAssertEqual(plan.leadSeconds, 0.050, accuracy: 1e-9)
        XCTAssertEqual(plan.emissions.map(\.sendAt).min() ?? -1, 100, accuracy: 1e-9)
        XCTAssertEqual(plan.emissions.map(\.landsAt).min() ?? -1, 100.050, accuracy: 1e-9)
    }

    func testEmissionsComeOutInSendOrder() throws {
        let plan = try unisonPlan()
        XCTAssertEqual(plan.emissions.map(\.sendAt), plan.emissions.map(\.sendAt).sorted())
        XCTAssertEqual(plan.emissions.count, 4)
    }

    /// The residual after correcting for each link's typical delay: ada can be
    /// 10 ms early, bo can be 20 ms late, so the worst spread between them is
    /// 30 ms. That figure is the one a screen shows instead of "synchronised".
    func testSkewIsTheSpreadThatCorrectingForTheTypicalDelayCannotRemove() throws {
        let skew = try unisonPlan().skew
        XCTAssertEqual(skew.earliestSeconds, -0.010, accuracy: 1e-9)
        XCTAssertEqual(skew.latestSeconds, 0.020, accuracy: 1e-9)
        XCTAssertEqual(skew.seconds, 0.030, accuracy: 1e-9)
        XCTAssertEqual(skew.earliestDuck, ada)
        XCTAssertEqual(skew.latestDuck, bo)
        XCTAssertTrue(skew.isEvidenced)
    }

    /// A LINK TIMED ONCE HAS A SPREAD OF ZERO AND THAT IS NOT A MEASUREMENT.
    /// The zero must not be reported as ducks landing together, because it is
    /// the absence of evidence rather than evidence of the absence.
    func testOneSampleReportsUnmeasuredRatherThanZeroSkew() throws {
        let plan = try unisonScore().schedule(
            startingAt: 0, roundTrips: [ada: try RoundTrip(seconds: 0.060),
                                        bo: try RoundTrip(seconds: 0.100)])
        XCTAssertEqual(plan.skew.seconds, 0, accuracy: 1e-12)
        XCTAssertFalse(plan.skew.isEvidenced)
        XCTAssertTrue(plan.skew.says.contains("unmeasured"), plan.skew.says)
        XCTAssertTrue(plan.skew.says.contains("absence of evidence"), plan.skew.says)
    }

    /// The sentence on the screen must never be the word somebody wants to
    /// hear. This app has no synchronised-start primitive to back it up.
    func testTheSkewSentenceNeverClaimsSynchrony() throws {
        let sentences: [Skew] = [try unisonPlan().skew, .silence]
        for skew in sentences {
            let said = skew.says.lowercased()
            XCTAssertFalse(said.contains("sync"), said)
            XCTAssertFalse(said.contains("in step"), said)
            XCTAssertFalse(said.contains("together"), said)
        }
    }

    /// One duck cannot be out of step with anybody, and its own jitter is
    /// still the number a person needs: how far off the beat it can land.
    /// Reporting zero would be the claim this type refuses to make.
    func testASingleDuckStillReportsItsOwnJitter() throws {
        let solo = try Score([Score.Step(at: 0, duck: ada, call: .stop)])
        let plan = try solo.schedule(startingAt: 0, roundTrips: [ada: quickLink()])
        XCTAssertEqual(plan.skew.seconds, 0.020, accuracy: 1e-9)
        XCTAssertEqual(plan.skew.earliestDuck, ada)
        XCTAssertEqual(plan.skew.latestDuck, ada)
    }

    func testAnEmptyScoreHasNothingToBeOutOfStep() throws {
        let plan = try Score([]).schedule(startingAt: 0, roundTrips: [:])
        XCTAssertEqual(plan.skew, .silence)
        XCTAssertTrue(plan.emissions.isEmpty)
        XCTAssertEqual(plan.leadSeconds, 0, accuracy: 1e-12)
    }

    /// A duck whose link nobody has timed is refused rather than assumed fast.
    /// Assuming would move the error out of a refusal and into the room.
    func testADuckWithNoMeasuredLinkCannotBeScheduled() throws {
        XCTAssertThrowsError(
            try unisonScore().schedule(startingAt: 0, roundTrips: [ada: quickLink()])
        ) { error in
            XCTAssertEqual(error as? Choreography.Problem, .unmeasuredLink(bo))
        }
    }

    // MARK: - round trips

    /// The lower median, so the figure the schedule is built on is a delay that
    /// actually happened rather than one interpolated between two that did.
    func testTypicalIsTheLowerMedianSoOneStallDoesNotMoveTheBeat() throws {
        let steady = try RoundTrip(samples: [0.050, 0.050, 0.050, 0.400])
        XCTAssertEqual(steady.typical, 0.050, accuracy: 1e-12)
        XCTAssertEqual(steady.oneWayTypical, 0.025, accuracy: 1e-12)
        XCTAssertEqual(steady.jitterSeconds, 0.350, accuracy: 1e-12)

        let odd = try RoundTrip(samples: [0.010, 0.020, 0.090])
        XCTAssertEqual(odd.typical, 0.020, accuracy: 1e-12)
    }

    func testALinkWithNoTimingsIsNotALink() {
        XCTAssertThrowsError(try RoundTrip(samples: [])) { error in
            XCTAssertEqual(error as? Choreography.Problem, .noSamples)
        }
        XCTAssertThrowsError(try RoundTrip(seconds: -1))
        XCTAssertThrowsError(try RoundTrip(seconds: .infinity))
    }

    func testSamplesAreSortedSoTheExtremesAreReadsRatherThanSearches() throws {
        let trip = try RoundTrip(samples: [0.090, 0.010, 0.020])
        XCTAssertEqual(trip.fastest, 0.010, accuracy: 1e-12)
        XCTAssertEqual(trip.slowest, 0.090, accuracy: 1e-12)
    }

    // MARK: - bound two: what a local advisory can and cannot promise

    /// THE PINNED SENTENCE, AND IT IS PINNED BY WHAT IT MUST NOT SAY. This
    /// used to read "nobody else can while it does", which is a claim of
    /// exclusivity that a `Dictionary` living in one process cannot make: two
    /// phones each hold their own empty advisory, both grant the duck, and both
    /// print the reassurance. `duck-ipc-proto` has no method by which a client
    /// could claim a duck — no token, no lease, no writer identity — so the
    /// claim was not merely unimplemented, it was unimplementable from here.
    /// If somebody reintroduces a promise of exclusion, this fails.
    func testTheAdvisoryDoesNotClaimExclusivity() throws {
        var advisory = LocalWriterAdvisory()
        let note = try advisory.note(ada, driver: me, at: 0)

        let said = note.says
        XCTAssertFalse(said.lowercased().contains("nobody else"), said)
        XCTAssertFalse(said.lowercased().contains("no one else"), said)
        XCTAssertFalse(said.lowercased().contains("exclusive"), said)
        XCTAssertFalse(said.lowercased().contains("only"), said)

        // And it says the true thing rather than merely omitting the false one.
        XCTAssertTrue(said.contains("this app's other screens"), said)
        XCTAssertTrue(said.contains("another phone"), said)
        XCTAssertTrue(said.contains("robotctl"), said)
    }

    /// The advisory's own summary, which is what a screen puts in front of
    /// somebody before a performance. Same rule: it must name what is not
    /// prevented, because the person reading it is about to walk away believing
    /// the ducks are theirs.
    func testTheAdvisorySaysWhatItDoesNotPrevent() {
        let said = LocalWriterAdvisory().says
        // "THIS APP WILL NOT…" WAS ITSELF AN OVERCLAIM, one level down from the
        // one this type was renamed to stop making. The advisory is a value:
        // two screens each holding their own copy see none of each other's
        // notes, so the guarantee is about the screens that SHARE one, not
        // about the app. The app holding a single instance is what makes the
        // stronger sentence true, and that is a fact about the app rather than
        // about this type.
        XCTAssertTrue(said.contains("screens that share this advisory"), said)
        XCTAssertFalse(said.contains("two of its own screens"), said)
        XCTAssertTrue(said.contains("no method for claiming a writer"), said)
        XCTAssertTrue(said.contains("gamepad"), said)
        XCTAssertFalse(said.lowercased().contains("nobody else"), said)
    }

    /// THE FAULT THIS HALF-PREVENTS LOOKS LIKE A DEAD ROBOT, NOT LIKE A
    /// CONFLICT. `intents.rs` keeps one command slot and takes the last write,
    /// so two writers at 50 Hz interleave into it and the duck obeys neither.
    /// Half of that — this app against itself — is a state the advisory can
    /// refuse; the refusal has to say which half.
    func testASecondScreenOfThisAppIsRefusedAndToldWhichScreenHasIt() throws {
        var advisory = LocalWriterAdvisory()
        try advisory.note(ada, driver: me, at: 0)

        XCTAssertThrowsError(try advisory.note(ada, driver: them, at: 0.1)) { error in
            XCTAssertEqual(error as? Choreography.Problem, .alreadyDrivenInThisApp(ada, by: me))
            let said = (error as? Choreography.Problem)?.message ?? ""
            XCTAssertTrue(said.contains("the drive screen"), said)
            XCTAssertTrue(said.contains("obeys neither"), said)
            XCTAssertTrue(said.contains("this app only"), said)
        }
        XCTAssertEqual(advisory.driver(of: ada, at: 0.1), me)
    }

    /// A running score renews every frame, so re-noting must extend rather
    /// than fail — and the original claim time must survive the renewal.
    func testTheSameScreenRenewsRatherThanCollidingWithItself() throws {
        var advisory = LocalWriterAdvisory(noteSeconds: 2)
        let first = try advisory.note(ada, driver: me, at: 10)
        let renewed = try advisory.note(ada, driver: me, at: 11)
        XCTAssertEqual(renewed.notedAt, first.notedAt, accuracy: 1e-12)
        XCTAssertEqual(renewed.expiresAt, 13, accuracy: 1e-12)
        XCTAssertTrue(advisory.isNoted(ada, as: me, at: 12.9))
    }

    /// A RENEWAL MUST NOT SHORTEN A NOTE, which is what makes a long score safe
    /// against a drive loop renewing the same duck two seconds at a time. See
    /// `LocalWriterAdvisory.note`.
    func testARenewalNeverShortensANoteThatWasTakenForLonger() throws {
        var advisory = LocalWriterAdvisory(noteSeconds: 2)
        try advisory.note(ada, driver: me, at: 0, through: 300)
        try advisory.note(ada, driver: me, at: 1)
        XCTAssertTrue(advisory.isNoted(ada, as: me, at: 299))
    }

    /// A note lapses rather than standing forever, because the writer is a
    /// screen that can be torn down without clearing anything. Lapsing stops no
    /// robot; it only lets the next screen in.
    func testALapsedNoteFreesTheDuckForAnotherScreen() throws {
        var advisory = LocalWriterAdvisory(noteSeconds: 2)
        try advisory.note(ada, driver: me, at: 0)
        XCTAssertNil(advisory.driver(of: ada, at: 2))
        XCTAssertNoThrow(try advisory.note(ada, driver: them, at: 2))
        XCTAssertEqual(advisory.driver(of: ada, at: 2), them)
    }

    /// A `nil` FROM `driver(of:at:)` MEANS "NOT FROM THIS APP" AND NOT
    /// "NOBODY", and there is no question this type can be asked that answers
    /// the second one. The assertion is that no such question exists: an
    /// advisory that has never heard of a duck answers exactly the same as one
    /// whose note has lapsed, because both are the same amount of knowledge.
    func testAnAdvisoryKnowsNothingAboutDucksItWasNeverToldAbout() throws {
        var advisory = LocalWriterAdvisory(noteSeconds: 2)
        try advisory.note(ada, driver: me, at: 0)
        XCTAssertNil(advisory.driver(of: bo, at: 0))
        XCTAssertNil(advisory.driver(of: ada, at: 99))
        XCTAssertFalse(advisory.isNoted(bo, as: me, at: 0))
    }

    /// A clearing that quietly succeeded for anybody would be a way for one
    /// screen to take a duck off another by asking politely.
    func testOnlyTheNotedScreenCanClearADuck() throws {
        var advisory = LocalWriterAdvisory()
        try advisory.note(ada, driver: me, at: 0)
        XCTAssertThrowsError(try advisory.clear(ada, from: them)) { error in
            XCTAssertEqual(error as? Choreography.Problem, .notTheNotedDriver(ada, them))
        }
        XCTAssertNoThrow(try advisory.clear(ada, from: me))
        XCTAssertNil(advisory.driver(of: ada, at: 0))
    }

    /// BOUND TWO'S GATE. The refusal arrives when the performance is built,
    /// before anything has moved, rather than at the first command.
    func testAScoreCannotRunAgainstADuckAnotherScreenIsDriving() throws {
        var advisory = LocalWriterAdvisory()
        try advisory.note(ada, driver: me, at: 0)
        try advisory.note(bo, driver: them, at: 0)

        XCTAssertThrowsError(
            try ScoreRun(plan: try unisonPlan(), driver: me, advisory: &advisory, at: 0)
        ) { error in
            XCTAssertEqual(error as? Choreography.Problem, .notNotedForThisScore(bo, me))
        }
    }

    func testAScoreRunsWhenThisAppHasNotedEveryDuck() throws {
        var advisory = try advisoryHoldingBoth()
        let run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        XCTAssertEqual(run.phase, .waiting)
        XCTAssertEqual(run.remaining, 4)
    }

    /// A note that lapsed between being taken and the score starting is not a
    /// note.
    func testALapsedNoteDoesNotStartAScore() throws {
        var advisory = try advisoryHoldingBoth(at: 0)
        XCTAssertThrowsError(
            try ScoreRun(plan: try unisonPlan(), driver: me, advisory: &advisory,
                         at: Choreography.defaultNoteSeconds + 1)
        )
    }

    /// THE BUG THIS SECTION EXISTS FOR, AND IT WAS THE ORDINARY CASE RATHER
    /// THAN A CORNER ONE. `ScoreRun` used to take the advisory by value, check
    /// it once in `init`, keep neither it nor the notes, and never ask again.
    /// The default note is two seconds; a score is minutes. So every real
    /// performance ran on a note that had lapsed in its first bar, and the run
    /// went on reporting itself the driver of ducks it had not looked at since
    /// the downbeat. Here is a five-minute score: the note has to still stand
    /// four minutes in, another screen must not be able to take the duck while
    /// it plays, and the last command still has to go out.
    func testALongScoreDoesNotSpendItselfOnALapsedNote() throws {
        let long = try Score([
            Score.Step(at: 0, duck: ada, call: .move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0))),
            Score.Step(at: 300, duck: ada, call: .stop),
        ])
        let plan = try long.schedule(startingAt: 0, roundTrips: [ada: quickLink()])

        var advisory = LocalWriterAdvisory(noteSeconds: Choreography.defaultNoteSeconds)
        try advisory.note(ada, driver: me, at: 0)
        var run = try ScoreRun(plan: plan, driver: me, advisory: &advisory, at: 0)

        XCTAssertEqual(run.due(at: 0, in: &advisory).count, 1)

        // Four minutes in, with the two-second note long past what it would
        // have covered on its own, this app still holds the duck — and says so
        // because it has just checked, not because it once did.
        XCTAssertTrue(advisory.isNoted(ada, as: me, at: 240),
                      "The run must cover the score it is playing, not two seconds of it.")
        XCTAssertTrue(run.due(at: 240, in: &advisory).isEmpty)
        XCTAssertEqual(run.phase, .running)

        // And no other screen of this app can take it mid-performance.
        XCTAssertThrowsError(try advisory.note(ada, driver: them, at: 240)) { error in
            XCTAssertEqual(error as? Choreography.Problem, .alreadyDrivenInThisApp(ada, by: me))
        }

        XCTAssertEqual(run.due(at: 301, in: &advisory).map(\.call), [.stop])
        XCTAssertEqual(run.phase, .finished)
    }

    /// THE OTHER HALF OF THE SAME FIX: a run that stopped being advanced long
    /// enough for its note to lapse must not pick up where it left off as
    /// though nothing had happened. It has not been the driver of that duck for
    /// some time, another screen is, and the honest thing to do with a score in
    /// that state is end it and stop everybody.
    func testARunWhoseNoteWasTakenWhileItSleptEndsTheScore() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        XCTAssertEqual(run.due(at: 0.05, in: &advisory).count, 2)

        // The app goes away for ten seconds; the notes lapse and the score
        // screen picks bo up.
        try advisory.note(bo, driver: them, at: 10)

        let out = run.due(at: 11, in: &advisory)
        XCTAssertEqual(out.map(\.duck), [ada, bo], "Everybody gets a stop, not the next note.")
        XCTAssertEqual(out.map(\.call), [.stop, .stop])
        guard case .abandoned(let fault) = run.phase else {
            return XCTFail("A duck this run is no longer driving has to end the score.")
        }
        XCTAssertEqual(fault.duck, bo)
        XCTAssertTrue(run.says.contains("bo dropped out"), run.says)
    }

    // MARK: - bound three: the deadman, and stopping everything

    /// THE ASSERTION THIS BOUND EXISTS FOR. One duck faults; every duck in the
    /// score gets a stop — including the one that faulted, because a fault is
    /// not proof of a partition and a duck that refused one call is perfectly
    /// capable of walking on its last twist.
    func testOneDuckFaultingStopsEveryDuckInTheScore() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        _ = run.due(at: 0.05, in: &advisory)

        let stops = run.fault(bo, "the link went away", at: 0.2, in: &advisory)

        XCTAssertEqual(stops.map(\.duck), [ada, bo])
        XCTAssertEqual(stops.map(\.call), [.stop, .stop])
        XCTAssertEqual(run.phase, .abandoned(ScoreRun.Fault(duck: bo,
                                                            reason: "the link went away",
                                                            atSeconds: 0.2)))
    }

    /// A stop is the one command where landing early beats landing together, so
    /// it does not pay the lead-in: everybody is sent to at the instant of the
    /// fault, and the arrivals are staggered by each link's own delay.
    func testStopsAreSentAtOnceRatherThanScheduledToLandTogether() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        let stops = run.fault(ada, "refused", at: 0.5, in: &advisory)
        XCTAssertEqual(Set(stops.map(\.sendAt)), [0.5])
        XCTAssertEqual(try XCTUnwrap(stops.first { $0.duck == self.ada }).landsAt,
                       0.530, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(stops.first { $0.duck == self.bo }).landsAt,
                       0.550, accuracy: 1e-9)
    }

    /// The rest of the score must not go out after an abort. The other ducks
    /// cannot tell that anything happened — there is no slot in the
    /// observation for a duck that has stopped — so nothing but this stops it.
    func testNothingMoreIsSentAfterAnAbort() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        XCTAssertEqual(run.due(at: 0.05, in: &advisory).count, 2)
        _ = run.fault(bo, "gone", at: 0.06, in: &advisory)
        XCTAssertTrue(run.due(at: 10, in: &advisory).isEmpty)
        XCTAssertEqual(run.remaining, 2, "The unsent stops stay unsent.")
    }

    /// A second fault must not produce a second round of stops for a score
    /// that is already over.
    func testASecondFaultDoesNotStopEverybodyTwice() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        XCTAssertEqual(run.fault(bo, "gone", at: 0.1, in: &advisory).count, 2)
        XCTAssertTrue(run.fault(ada, "also gone", at: 0.2, in: &advisory).isEmpty)
        XCTAssertEqual(run.phase, .abandoned(ScoreRun.Fault(duck: bo, reason: "gone",
                                                            atSeconds: 0.1)))
    }

    func testAPersonCanEndThePieceWithoutADuckToBlame() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        let stops = run.abandon("hands off the sticks", at: 0.4, in: &advisory)
        XCTAssertEqual(stops.map(\.duck), [ada, bo])
        guard case .abandoned(let fault) = run.phase else {
            return XCTFail("A deliberate stop is still an abandonment.")
        }
        XCTAssertEqual(fault.reason, "hands off the sticks")
        // NOBODY IS BLAMED. This used to forward to `fault(plan.ducks.first!)`,
        // so a person pressing stop produced "ada dropped out: hands off the
        // sticks" about a duck that had done nothing at all.
        XCTAssertNil(fault.duck)
        XCTAssertFalse(run.says.contains("dropped out"), run.says)
        XCTAssertTrue(run.says.hasPrefix("The score was ended"), run.says)
    }

    /// The sentence a person reads has to say that the other ducks were never
    /// going to notice, because that is the whole reason the app had to act.
    func testTheAbortSentenceSaysWhyTheAppHadToDoIt() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        _ = run.fault(bo, "the link went away", at: 0.2, in: &advisory)
        XCTAssertTrue(run.says.contains("bo dropped out"), run.says)
        XCTAssertTrue(run.says.contains("cannot tell"), run.says)
    }

    // MARK: - playing out

    func testCommandsComeDueInSendOrderAndOnlyOnce() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)

        XCTAssertTrue(run.due(at: -1, in: &advisory).isEmpty, "A clock behind the start is not due yet.")
        XCTAssertEqual(run.due(at: 0, in: &advisory).map(\.duck), [bo], "The slow link goes first.")
        XCTAssertEqual(run.phase, .running)
        XCTAssertEqual(run.due(at: 0.019, in: &advisory).map(\.duck), [])
        // 0.021 rather than 0.020: ada's send time is a sum of three binary
        // fractions and lands a few ulps above twenty milliseconds. A real
        // clock steps past that without noticing, and an assertion pinned to
        // the exact boundary would be testing IEEE 754 rather than the score.
        XCTAssertEqual(run.due(at: 0.021, in: &advisory).map(\.duck), [ada])
        XCTAssertEqual(run.due(at: 5, in: &advisory).count, 2)
        XCTAssertEqual(run.phase, .finished)
        XCTAssertEqual(run.remaining, 0)
        XCTAssertTrue(run.due(at: 6, in: &advisory).isEmpty)
    }

    /// Rewinding could only re-send what has already gone: a stale twist
    /// landing after a fresh one in a slot that keeps the last write.
    func testAClockThatWentBackwardsIsIgnoredRatherThanObeyed() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        XCTAssertEqual(run.due(at: 0.05, in: &advisory).count, 2)
        XCTAssertTrue(run.due(at: 0.01, in: &advisory).isEmpty)
        XCTAssertEqual(run.clockReached, 0.05, accuracy: 1e-9)
        XCTAssertEqual(run.remaining, 2)
    }

    /// "Finished" means every line was handed to a transport, which is a
    /// smaller claim than "the ducks did it" — and the gap between the two
    /// claims is exactly what `Skew` measures.
    func testFinishedMeansSentAndTheSentenceSaysSo() throws {
        var advisory = try advisoryHoldingBoth()
        var run = try ScoreRun(plan: try unisonPlan(), driver: me,
                               advisory: &advisory, at: 0)
        _ = run.due(at: 99, in: &advisory)
        XCTAssertEqual(run.phase, .finished)
        XCTAssertTrue(run.says.contains("has been sent"), run.says)
        XCTAssertTrue(run.says.contains("Achieved skew"), run.says)
    }

    /// " dropped out: …" — A SENTENCE BEGINNING WITH A SPACE, BLAMING A DUCK
    /// THAT DOES NOT EXIST. `abandon` on a plan with no ducks used to build
    /// `Fault(duck: DuckID(""))` because `Fault.duck` was not optional and
    /// there was nothing true to put in it. There is still nothing true to put
    /// in it; the field is optional now instead.
    func testEndingAScoreWithNoDucksNamesNoDuck() throws {
        var empty = LocalWriterAdvisory()
        let plan = try Score([]).schedule(startingAt: 0, roundTrips: [:])
        var run = try ScoreRun(plan: plan, driver: me, advisory: &empty, at: 0)

        XCTAssertTrue(run.abandon("hands off the sticks", at: 1, in: &empty).isEmpty,
                      "There is nobody to stop.")
        guard case .abandoned(let fault) = run.phase else {
            return XCTFail("A deliberate stop is still an abandonment.")
        }
        XCTAssertNil(fault.duck)
        XCTAssertFalse(run.says.hasPrefix(" "), run.says)
        XCTAssertFalse(run.says.contains("dropped out"), run.says)
        XCTAssertTrue(run.says.hasPrefix("The score was ended:"), run.says)
    }

    func testAnEmptyPlanIsFinishedBeforeItStarts() throws {
        let plan = try Score([]).schedule(startingAt: 0, roundTrips: [:])
        var empty = LocalWriterAdvisory()
        let run = try ScoreRun(plan: plan, driver: me, advisory: &empty, at: 0)
        XCTAssertEqual(run.phase, .finished)
    }

    // MARK: - what a link has to carry

    /// `robot.stop` is needed even by a score that never asks for one, because
    /// the abort path is part of the score rather than an extra.
    func testEveryDuckNeedsStopWhetherOrNotTheScoreAsksForIt() throws {
        let walk = try Score([
            Score.Step(at: 0, duck: ada, call: .move(.still))
        ])
        XCTAssertEqual(walk.methodsNeeded(of: ada), [.move, .stop])
    }

    /// BLE carries neither the driving nor the stop, so a score routed there
    /// would be a row of commands refused one at a time by name while the duck
    /// stood still. The bench carries both, and denies the head.
    ///
    /// THE SET IS ASKED FOR RATHER THAN WRITTEN OUT. `methodsNeeded`'s doc
    /// comment used to transcribe Bluetooth's five methods by hand, which is a
    /// second copy of `DuckMethod.reach(for:)`'s table that nothing compares
    /// against the first — so a routing change would have left the comment
    /// confidently describing the old columns. Here the table is the authority
    /// and this asserts the consequence, so the day Bluetooth's row moves, an
    /// assertion fails instead of a comment rotting.
    func testAScoreCannotBePerformedOverALinkThatDoesNotCarryIt() throws {
        XCTAssertFalse(DuckMethod.reach(for: .ble).contains(.stop),
                       "The abort path is what keeps a score off Bluetooth.")
        XCTAssertFalse(DuckMethod.reach(for: .ble).contains(.move))

        let walk = try Score([Score.Step(at: 0, duck: ada, call: .move(.still))])
        XCTAssertFalse(walk.isPerformable(by: ada, over: DuckMethod.reach(for: .ble)))
        XCTAssertTrue(walk.isPerformable(by: ada, over: DuckMethod.reach(for: .bench)))
        XCTAssertTrue(walk.isPerformable(by: ada, over: DuckMethod.reach(for: .webRTC)))

        let nod = try Score([Score.Step(at: 0, duck: ada, call: .head(.level))])
        XCTAssertFalse(nod.isPerformable(by: ada, over: DuckMethod.reach(for: .bench)),
                       "The bench posts {vx, vy, vyaw, hold} and has no head in it.")
        XCTAssertTrue(nod.isPerformable(by: ada, over: DuckMethod.reach(for: .bridge)))
    }

    // MARK: - holding a continuous intent down

    /// A one-second hold at 50 Hz is fifty-ONE frames: one on the downbeat and
    /// one on the final instant. Fifty would end the hold a frame early and
    /// leave the robot's expiry to finish the move.
    func testHoldingAWalkIsRepeatedFramesWithTheFencepostIncluded() throws {
        let frames = try Score.holding(.move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0)),
                                       on: ada, from: 0, for: 1)
        XCTAssertEqual(frames.count, 51)
        XCTAssertEqual(frames.first?.at, 0)
        XCTAssertEqual(try XCTUnwrap(frames.last).at, 1, accuracy: 1e-9)
        XCTAssertEqual(Set(frames.map(\.duck)), [ada])
    }

    func testAZeroLengthHoldIsStillOneFrame() throws {
        XCTAssertEqual(try Score.holding(.head(.level), on: ada, from: 2, for: 0).count, 1)
    }

    /// Only the continuous intents repeat, because only they expire. A
    /// `robot.stop` at 50 Hz is fifty answered requests a second arriving at a
    /// robot that stopped after the first.
    func testADiscreteCallCannotBeHeldDown() {
        XCTAssertThrowsError(try Score.holding(.stop, on: ada, from: 0, for: 1)) { error in
            XCTAssertEqual(error as? Choreography.Problem, .notSustainable(.stop))
        }
        XCTAssertThrowsError(try Score.holding(.look(.level), on: ada, from: 0, for: 1))
    }

    func testAHoldNeedsARealRateAndARealLength() {
        XCTAssertThrowsError(try Score.holding(.move(.still), on: ada, from: 0, for: 1, hz: 0)) {
            XCTAssertEqual($0 as? Choreography.Problem, .rateIsNotPositive(0))
        }
        XCTAssertThrowsError(try Score.holding(.move(.still), on: ada, from: 0, for: -1))
        XCTAssertThrowsError(try Score.holding(.move(.still), on: ada, from: -1, for: 1))
    }

    /// The rate a person has already driven the real robot at, so a held note
    /// in a score and a held stick are one thing.
    /// DERIVED, NOT RESTATED. `defaultRateHz` was a literal `50.0` and this
    /// test compared it to a literal `50.0`, so the pair could only ever agree
    /// with themselves: the day DuckKit's control rate moved, `DuckModel.tickHz`
    /// would have changed and both this constant and this assertion would have
    /// gone on passing about the old number. The comparison has to be against
    /// the thing that owns the answer.
    func testTheDefaultRateIsTheKitsRateRatherThanACopyOfIt() {
        XCTAssertEqual(Choreography.defaultRateHz, DuckModel.tickHz)
        XCTAssertEqual(Score.frameCeiling, Int(3600 * DuckModel.tickHz),
                       "The ceiling is an hour at the control rate, so it moves with it.")
    }

    // MARK: - the sentences

    /// Every refusal has to be readable by somebody whose score has just failed
    /// to start in front of an audience.
    func testEveryRefusalSaysSomethingAPersonCanActOn() {
        let all: [Choreography.Problem] = [
            .noSamples, .notASecond(.nan), .stepOutOfOrder(-1), .unmeasuredLink(ada),
            .alreadyDrivenInThisApp(ada, by: them), .notTheNotedDriver(ada, me),
            .notNotedForThisScore(bo, me), .notSustainable(.stop), .rateIsNotPositive(0),
            .tooManyFrames(seconds: 1e18, hz: 50), .sameKeyTwice("Duck"), .unknownDuck(ada),
            .linkCannotCarry(ada, [.move, .stop]),
        ]
        for problem in all {
            XCTAssertGreaterThan(problem.message.count, 60, "\(problem)")
            XCTAssertTrue(problem.message.hasSuffix("."), problem.message)
        }
    }

    func testThePlanSentenceReportsTheLeadInRatherThanHidingIt() throws {
        let said = try unisonPlan().says
        XCTAssertTrue(said.contains("50 ms lead-in"), said)
        XCTAssertTrue(said.contains("Achieved skew"), said)
    }

    func testARoundTripSaysHowManyTimesItWasActuallyMeasured() throws {
        let measured = try quickLink().says
        XCTAssertTrue(measured.contains("3 timings"), measured)
        let once = try RoundTrip(seconds: 0.06).says
        XCTAssertTrue(once.contains("Timed once"), once)
    }

    // MARK: - the sentences, where a sign is a claim

    /// "-0 ms early" WAS WHAT THE COMMON CASE PRINTED, AND A MINUS SIGN IN
    /// FRONT OF A MEASUREMENT IS READ AS A DIRECTION. `RoundTrip.typical` is
    /// the LOWER median, so a link timed an even number of times has
    /// `fastest == typical` exactly; `Skew.earliestSeconds` is then `+0.0`,
    /// `says` negates it, and `%.0f` of a negative zero is the string "-0".
    /// Two samples is the fewest `isEvidenced` will accept, so this was not an
    /// edge case, it was the ordinary one.
    func testMillisecondsNeverPrintASignedZero() {
        XCTAssertEqual(Choreography.ms(0), "0 ms")
        XCTAssertEqual(Choreography.ms(-0.0), "0 ms")
        XCTAssertEqual(Choreography.ms(-0.0004), "0 ms",
                       "A real value that rounds to zero is zero, not minus zero.")
        XCTAssertEqual(Choreography.ms(-0.012), "-12 ms",
                       "A real negative is still shown as negative.")
        XCTAssertEqual(Choreography.ms(0.020), "20 ms")
    }

    func testAnEvenlyTimedLinkDoesNotSayItCanLandMinusZeroEarly() throws {
        // Two samples: the lower median IS the fastest, so the early residual
        // is exactly zero and there is nothing left to be negative.
        let evenly = try RoundTrip(samples: [0.040, 0.080])
        let solo = try Score([Score.Step(at: 0, duck: ada, call: .stop)])
        let plan = try solo.schedule(startingAt: 0, roundTrips: [ada: evenly])

        XCTAssertEqual(plan.skew.earliestSeconds, 0, accuracy: 1e-12)
        let said = plan.skew.says
        XCTAssertFalse(said.contains("-0 ms"), said)
        XCTAssertTrue(said.contains("0 ms early"), said)
        XCTAssertTrue(said.contains("20 ms late"), said)
    }

    // MARK: - a bound describes every duck it was asked about

    /// IT USED TO SKIP THE DUCK NOBODY HAD TIMED AND STILL REPORT
    /// `isEvidenced == true`. A four-duck score with one unmeasured link
    /// produced a confident sentence about three of them and called it the
    /// achieved skew of the performance — and the duck left out is precisely
    /// the one whose link nobody knows anything about, which makes it the
    /// likeliest to miss the beat. `Score.schedule` has always thrown
    /// `unmeasuredLink` for this; the two must not disagree about whether a
    /// score is runnable.
    func testASkewWillNotDescribeFewerDucksThanItWasAskedAbout() throws {
        XCTAssertThrowsError(try Skew.across([ada, bo], roundTrips: [ada: quickLink()])) { error in
            XCTAssertEqual(error as? Choreography.Problem, .unmeasuredLink(bo))
        }
        // The same refusal, in the same words, from the other door.
        XCTAssertThrowsError(
            try unisonScore().schedule(startingAt: 0, roundTrips: [ada: quickLink()])
        ) { error in
            XCTAssertEqual(error as? Choreography.Problem, .unmeasuredLink(bo))
        }
        // Nothing at all is still silence rather than a refusal: there is no
        // duck to be unmeasured.
        XCTAssertEqual(try Skew.across([], roundTrips: [:]), .silence)
    }

    // MARK: - a hold that cannot be built is refused, not fatal

    /// `Int((seconds * hz).rounded())` TRAPS, AND A TRAP IS NOT A REFUSAL. Both
    /// arguments were checked for being finite and their product never was, so
    /// a parsed score file with a large duration in it — or the ordinary
    /// milliseconds-for-seconds slip — took the process down inside the
    /// function whose whole job is to refuse things.
    func testAHoldTooLongToBuildIsRefusedRatherThanFatal() {
        XCTAssertThrowsError(
            try Score.holding(.move(.still), on: ada, from: 0, for: 1e18)
        ) { error in
            XCTAssertEqual(error as? Choreography.Problem,
                           .tooManyFrames(seconds: 1e18, hz: Choreography.defaultRateHz))
        }
        // The value that actually traps `Int(_:)`, and the one that reaches it
        // through the rate instead of the duration.
        XCTAssertThrowsError(try Score.holding(.move(.still), on: ada, from: 0, for: 1e300))
        XCTAssertThrowsError(try Score.holding(.move(.still), on: ada, from: 0, for: 1, hz: 1e30))
    }

    /// The ceiling is an hour of frames, and the fencepost is at the frame
    /// rather than at the second: an hour exactly is one frame too many,
    /// because a hold includes both ends.
    func testTheCeilingIsAnHourOfFramesAndIsNotOffByOne() throws {
        let hz = Choreography.defaultRateHz
        let full = try Score.holding(.move(.still), on: ada, from: 0, for: 3600 - 1 / hz)
        XCTAssertEqual(full.count, Score.frameCeiling)
        XCTAssertThrowsError(try Score.holding(.move(.still), on: ada, from: 0, for: 3600))
    }

    // MARK: - the seam: a name, a peer, and the collision between them

    /// A stub link. It answers nothing; what is under test is which duck it
    /// says it is and what it says it carries.
    private final class StubPeer: DuckPeer {
        let identity: DuckIdentity
        let reach: Set<DuckMethod>

        init(_ name: String, kind: DuckIdentity.Kind = .sim,
             reach: Set<DuckMethod> = DuckMethod.reach(for: .bridge)) {
            self.identity = DuckIdentity(name: name, kind: kind)
            self.reach = reach
        }

        let transportKind = DuckTransportKind.bridge

        func call(_ c: DuckCall) async throws -> DuckReply {
            try vet(c, asNotification: false)
            return DuckReply(id: 1, result: Data("{}".utf8), failure: nil)
        }

        func notify(_ c: DuckCall) async throws {
            try vet(c, asNotification: true)
        }
    }

    /// THE COLLISION IS THE SECOND THING ANYBODY DOES, NOT A CORNER CASE.
    /// `SimDuckConfig.stock()` names every duck it makes "Duck", and a
    /// `DuckID` is that name in a wrapper, so two stock simulators in one cast
    /// would have collapsed into one key. The silent version costs a duck that
    /// stands still through a whole score while every screen in the app looks
    /// correct — so the one place a name becomes a key refuses instead.
    func testTwoDucksWithOneNameAreRefusedRatherThanCollapsedIntoOne() throws {
        let stock = SimDuckConfig.stock()
        XCTAssertEqual(stock.name, "Duck",
                       "If this changes, the collision below is somebody else's default now.")

        XCTAssertThrowsError(try DuckCast([StubPeer(stock.name), StubPeer(stock.name)])) { error in
            XCTAssertEqual(error as? Choreography.Problem, .sameKeyTwice("Duck"))
            let said = (error as? Choreography.Problem)?.message ?? ""
            XCTAssertTrue(said.contains("not an identity"), said)
            XCTAssertTrue(said.contains("stand still"), said)
        }

        let named = try DuckCast([StubPeer("ada"), StubPeer("bo")])
        XCTAssertEqual(named.ducks, [ada, bo])
    }

    /// THE SEAM ITSELF. A score names ducks and an emission carries a name;
    /// before `DuckCast` there was nothing in the package that turned either
    /// into something the app could write to, so every screen hand-wrote the
    /// loop and each one got the collision above wrong in its own way.
    func testAnEmissionResolvesToThePeerItIsAddressedTo() throws {
        let adaPeer = StubPeer("ada")
        let cast = try DuckCast([adaPeer, StubPeer("bo")])

        let plan = try unisonPlan()
        let first = try XCTUnwrap(plan.emissions.first { $0.duck == self.ada })
        XCTAssertTrue(try cast.peer(for: first) === adaPeer)

        let unknown = Score.Emission(sendAt: 0, landsAt: 0, duck: DuckID("cy"), call: .stop)
        XCTAssertThrowsError(try cast.peer(for: unknown)) { error in
            XCTAssertEqual(error as? Choreography.Problem, .unknownDuck(DuckID("cy")))
        }
    }

    /// `DuckPeer.vet` STAYS THE AUTHORITY AND THIS ASKS IT EARLY. The point is
    /// where the answer arrives: once, while somebody is looking at a start
    /// button, rather than as a row of commands refused one at a time by name
    /// in front of an audience.
    func testACastRefusesAScoreItsLinksCannotCarry() throws {
        let overBluetooth = try DuckCast([StubPeer("ada", reach: DuckMethod.reach(for: .ble))])
        let walk = try Score([Score.Step(at: 0, duck: ada, call: .move(.still))])

        XCTAssertThrowsError(try overBluetooth.vet(walk)) { error in
            XCTAssertEqual(error as? Choreography.Problem,
                           .linkCannotCarry(ada, [.move, .stop]))
            let said = (error as? Choreography.Problem)?.message ?? ""
            XCTAssertTrue(said.contains("robot.move, robot.stop"), said)
        }

        XCTAssertNoThrow(try DuckCast([StubPeer("ada")]).vet(walk))
        XCTAssertThrowsError(try DuckCast([StubPeer("bo")]).vet(walk)) { error in
            XCTAssertEqual(error as? Choreography.Problem, .unknownDuck(ada))
        }
    }

    /// `isPerformable` over a peer is the same question as over a reach set,
    /// asked without a screen reaching into `peer.reach` itself — which is the
    /// small step that ends with a screen deciding what a link carries.
    func testAScoreCanBeCheckedAgainstAPeerWithoutOpeningItUp() throws {
        let walk = try Score([Score.Step(at: 0, duck: ada, call: .move(.still))])
        XCTAssertTrue(walk.isPerformable(by: ada, over: StubPeer("ada")))
        XCTAssertFalse(walk.isPerformable(by: ada,
                                          over: StubPeer("ada",
                                                         reach: DuckMethod.reach(for: .ble))))
    }
}

extension ChoreographyTests {

    /// ENDING A SCORE GIVES THE NOTES BACK. `renew` extends every note through
    /// the end of the score plus slack — so a run that ends early used to hold
    /// its ducks for the whole remaining length of a piece that was no longer
    /// playing, and the refusal another screen got named the screen that had
    /// pressed stop.
    func testAbandoningAScoreReleasesEveryNoteItHeld() throws {
        var advisory = try advisoryHoldingBoth()
        // A long score, so a leak is unmistakable rather than a rounding edge.
        let long = try Score([
            Score.Step(at: 0, duck: ada, call: .move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0))),
            Score.Step(at: 0, duck: bo, call: .move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0))),
            Score.Step(at: 300, duck: ada, call: .stop),
            Score.Step(at: 300, duck: bo, call: .stop),
        ])
        let plan = try long.schedule(startingAt: 0,
                                     roundTrips: [ada: quickLink(), bo: slowLink()])
        var run = try ScoreRun(plan: plan, driver: me, advisory: &advisory, at: 0)
        _ = run.due(at: 1, in: &advisory)

        _ = run.abandon("hands off the sticks", at: 10, in: &advisory)

        // The moment it is over, another screen may take either duck. Before
        // this fix both of these threw for the next 290 seconds.
        let other = LocalWriterAdvisory.Writer("the other screen")
        XCTAssertNoThrow(try advisory.note(ada, driver: other, at: 11))
        XCTAssertNoThrow(try advisory.note(bo, driver: other, at: 11))
    }

    /// The same for a fault, which is the path a dropped link takes.
    func testAFaultAlsoReleasesTheNotes() throws {
        var advisory = try advisoryHoldingBoth()
        let long = try Score([
            Score.Step(at: 0, duck: ada, call: .move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0))),
            Score.Step(at: 0, duck: bo, call: .move(DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0))),
            Score.Step(at: 120, duck: ada, call: .stop),
            Score.Step(at: 120, duck: bo, call: .stop),
        ])
        let plan = try long.schedule(startingAt: 0,
                                     roundTrips: [ada: quickLink(), bo: slowLink()])
        var run = try ScoreRun(plan: plan, driver: me, advisory: &advisory, at: 0)
        _ = run.due(at: 0.5, in: &advisory)

        _ = run.fault(bo, "the link went away", at: 2, in: &advisory)

        let other = LocalWriterAdvisory.Writer("the other screen")
        XCTAssertNoThrow(try advisory.note(ada, driver: other, at: 3),
                         "ada did nothing wrong and is no longer being driven")
        XCTAssertNoThrow(try advisory.note(bo, driver: other, at: 3))
    }

    /// `Plan.says` claimed "The slowest link is sent to first". `schedule`
    /// offsets each duck by ITS OWN delay and orders nothing, so the claim only
    /// held when the slowest duck happened to have a step on the downbeat.
    func testThePlanDoesNotClaimAnOrderItDoesNotImpose() throws {
        // bo is on the slow link, and steps two seconds in. ada is fast and
        // steps at zero — so ada is sent to first, and the old sentence was
        // false about exactly this shape.
        let score = try Score([
            Score.Step(at: 0, duck: ada, call: .stop),
            Score.Step(at: 2, duck: bo, call: .stop),
        ])
        let plan = try score.schedule(startingAt: 0,
                                      roundTrips: [ada: quickLink(), bo: slowLink()])
        let first = try XCTUnwrap(plan.emissions.min { $0.sendAt < $1.sendAt })
        XCTAssertEqual(first.duck, ada, "the fast duck steps first, so it is sent to first")
        XCTAssertFalse(plan.says.contains("slowest link is sent to first"), plan.says)
        XCTAssertTrue(plan.says.contains("its own measured delay"), plan.says)
    }
}
