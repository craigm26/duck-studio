import XCTest
import DuckKit
@testable import StudioKit

/// The drafter's budget, and the point at which it stops asking.
final class DraftGateTests: XCTestCase {

    /// A clock somebody else winds. Injecting `now` is what makes every
    /// deadline below exact and instant instead of slow and approximate.
    private final class FakeClock: @unchecked Sendable {
        var seconds: Double = 0
        func advance(_ by: Double) { seconds += by }
    }

    private func resolvable() -> MotionProposal {
        MotionProposal(name: "a nod", keys: [
            .init(atSeconds: 0.4, moves: [.init(joint: "head nod", degrees: 10)]),
        ])
    }

    /// The duck has no elbow, and `resolve()` says so by name.
    private func unresolvable() -> MotionProposal {
        MotionProposal(name: "an elbow", keys: [
            .init(atSeconds: 0.4, moves: [.init(joint: "elbow", degrees: 10)]),
        ])
    }

    private func draftOf(_ outcome: DraftGate.Outcome) -> IntentDraft? {
        if case .drafted(let draft) = outcome { return draft }
        return nil
    }

    private func feedbackOf(_ outcome: DraftGate.Outcome) -> String? {
        if case .feedback(let text) = outcome { return text }
        return nil
    }

    private func stopOf(_ outcome: DraftGate.Outcome) -> String? {
        if case .stopped(let text) = outcome { return text }
        return nil
    }

    // MARK: - the budget

    /// The step count is checked BEFORE it is incremented, so the fortieth
    /// step is allowed and the forty-first is the one that dies — with the
    /// counter reading 40, which is the number the refusal quotes.
    func testFortyStepsAreAllowedAndTheFortyFirstDiesWithTheCounterReadingForty() {
        let clock = FakeClock()
        var budget = DraftBudget(maxSteps: 40, maxSeconds: 1000, now: { clock.seconds })
        for step in 1...40 {
            XCTAssertNoThrow(try budget.spend(), "step \(step) is inside a budget of 40")
        }
        XCTAssertEqual(budget.spent, 40)
        XCTAssertThrowsError(try budget.spend()) {
            XCTAssertEqual($0 as? DraftBudget.Exhausted, .outOfSteps(spent: 40, allowed: 40))
        }
        XCTAssertEqual(budget.spent, 40, "a refused step is not a spent one")
    }

    /// A strict `>`: landing exactly on the deadline is inside it. Otherwise
    /// "five seconds" quietly means "just under five seconds".
    func testARunLandingExactlyOnItsDeadlineIsStillInsideIt() {
        let clock = FakeClock()
        var budget = DraftBudget(maxSteps: 1000, maxSeconds: 5, now: { clock.seconds })
        clock.advance(5)
        XCTAssertNoThrow(try budget.spend(), "5 s of a 5 s budget has not passed 5 s")
        clock.advance(0.5)
        XCTAssertThrowsError(try budget.spend()) {
            guard case .outOfTime(let elapsed, let allowed)? = $0 as? DraftBudget.Exhausted else {
                return XCTFail("expected outOfTime, got \($0)")
            }
            XCTAssertEqual(elapsed, 5.5, accuracy: 1e-9)
            XCTAssertEqual(allowed, 5, accuracy: 1e-9)
        }
    }

    /// The budget follows the clock it was handed. A run that costs no time on
    /// that clock costs none, however long it really took — which is exactly
    /// what running at sim speed, or in a test, needs.
    func testTheDeadlineIsMeasuredOnTheInjectedClockAndNotTheWallClock() {
        let clock = FakeClock()
        var budget = DraftBudget(maxSteps: 1000, maxSeconds: 0.001, now: { clock.seconds })
        for _ in 0..<50 {
            XCTAssertNoThrow(try budget.spend(), "no time has passed on the clock that counts")
        }
        XCTAssertEqual(budget.elapsed, 0)
        clock.advance(1)
        XCTAssertThrowsError(try budget.spend(), "one second of the caller's clock ends it")
    }

    /// It measures from when it was made, not from the clock's own zero.
    func testABudgetMeasuresFromTheMomentItWasMade() {
        let clock = FakeClock()
        clock.advance(1_000)
        var budget = DraftBudget(maxSteps: 10, maxSeconds: 60, now: { clock.seconds })
        XCTAssertEqual(budget.elapsed, 0)
        XCTAssertNoThrow(try budget.spend())
    }

    // MARK: - the gate

    func testAProposalThatResolvesComesBackAsADraftAndCostsOneTry() {
        let clock = FakeClock()
        var gate = DraftGate(now: { clock.seconds })
        let outcome = gate.draft(resolvable())
        let draft = draftOf(outcome)
        XCTAssertNotNil(draft, "\(outcome)")
        XCTAssertEqual(draft?.name, "a nod")
        XCTAssertEqual(gate.budget.spent, 1)
        XCTAssertEqual(gate.consecutiveFailures, 0)
        XCTAssertFalse(gate.isStopped)
    }

    /// THE BEHAVIOUR THIS WHOLE FILE IS FOR. The same failure four times is
    /// feedback — say what is wrong and let them try again. The fifth is a
    /// stop, and the stop repeats the sentence the model kept failing with,
    /// because "the model failed" is not something anybody can act on.
    func testTheSameUnresolvableFailureBecomesFeedbackAndThenAStop() {
        let clock = FakeClock()
        var gate = DraftGate(limits: .init(maxConsecutiveFailures: 5), now: { clock.seconds })

        for attempt in 1...4 {
            let outcome = gate.draft(unresolvable())
            let text = feedbackOf(outcome)
            XCTAssertNotNil(text, "attempt \(attempt) should still be feedback: \(outcome)")
            XCTAssertEqual(text, MotionProposal.Unresolvable
                .unknownJoint("elbow", closest: MotionProposal.closest(to: "elbow")).message,
                "the resolver's own words reach the person unchanged")
            XCTAssertFalse(gate.isStopped)
            XCTAssertEqual(gate.consecutiveFailures, attempt)
        }

        let fifth = gate.draft(unresolvable())
        let reason = stopOf(fifth)
        XCTAssertNotNil(reason, "\(fifth)")
        XCTAssertTrue(reason?.contains("5 drafts in a row") == true, reason ?? "")
        XCTAssertTrue(reason?.contains("elbow") == true,
                      "the stop carries the reason it kept failing: \(reason ?? "")")
        XCTAssertTrue(gate.isStopped)
        XCTAssertEqual(gate.budget.spent, 5, "every one of those was a real try")
    }

    /// The counter is "the model is stuck", not "the model has had a bad day",
    /// so any success clears it.
    func testASuccessResetsTheFailureRun() {
        let clock = FakeClock()
        var gate = DraftGate(limits: .init(maxConsecutiveFailures: 3), now: { clock.seconds })
        XCTAssertNotNil(feedbackOf(gate.draft(unresolvable())))
        XCTAssertNotNil(feedbackOf(gate.draft(unresolvable())))
        XCTAssertEqual(gate.consecutiveFailures, 2)

        XCTAssertNotNil(draftOf(gate.draft(resolvable())))
        XCTAssertEqual(gate.consecutiveFailures, 0)

        // And the run has to build up again from nothing.
        XCTAssertNotNil(feedbackOf(gate.draft(unresolvable())))
        XCTAssertNotNil(feedbackOf(gate.draft(unresolvable())))
        XCTAssertFalse(gate.isStopped, "two is not three")
        XCTAssertNotNil(stopOf(gate.draft(unresolvable())))
    }

    /// Once stopped it answers with the same sentence rather than a new one,
    /// and it stops spending tries on questions it will not answer.
    func testOnceStoppedTheGateRepeatsItselfAndSpendsNothingMore() {
        let clock = FakeClock()
        var gate = DraftGate(limits: .init(maxConsecutiveFailures: 1), now: { clock.seconds })
        let first = stopOf(gate.draft(unresolvable()))
        XCTAssertNotNil(first)
        let spentWhenItStopped = gate.budget.spent

        // Even a proposal that WOULD have resolved gets the same answer.
        XCTAssertEqual(stopOf(gate.draft(resolvable())), first)
        XCTAssertEqual(stopOf(gate.draft(unresolvable())), first)
        XCTAssertEqual(gate.budget.spent, spentWhenItStopped)
    }

    func testRunningOutOfTriesStopsTheGateAndSaysHowManyThereWere() {
        let clock = FakeClock()
        var gate = DraftGate(limits: .init(maxDrafts: 3), now: { clock.seconds })
        for _ in 1...3 { XCTAssertNotNil(draftOf(gate.draft(resolvable()))) }
        let outcome = gate.draft(resolvable())
        let reason = stopOf(outcome)
        XCTAssertNotNil(reason, "\(outcome)")
        XCTAssertTrue(reason?.contains("3 of 3") == true, reason ?? "")
        XCTAssertTrue(gate.isStopped)
    }

    func testRunningOutOfTimeStopsTheGateOnTheInjectedClock() {
        let clock = FakeClock()
        var gate = DraftGate(limits: .init(maxSeconds: 10), now: { clock.seconds })
        XCTAssertNotNil(draftOf(gate.draft(resolvable())))
        clock.advance(10.5)
        let reason = stopOf(gate.draft(resolvable()))
        XCTAssertNotNil(reason)
        XCTAssertTrue(reason?.contains("Time is up") == true, reason ?? "")
    }

    /// PARAMS BEFORE BUDGET, which is quackd's order and decides who pays. A
    /// proposal that is not arithmetic is a broken call, not a failed try: it
    /// costs no try and does not count towards the stop.
    func testANumberThatIsNotANumberIsRefusedWithoutCostingATry() {
        let clock = FakeClock()
        var gate = DraftGate(now: { clock.seconds })
        let nonsense = MotionProposal(name: "nan", keys: [
            .init(atSeconds: 0.4, moves: [.init(joint: "head nod", degrees: .nan)]),
        ])
        let outcome = gate.draft(nonsense)
        XCTAssertTrue(feedbackOf(outcome)?.contains("not a number") == true, "\(outcome)")
        XCTAssertEqual(gate.budget.spent, 0, "a broken call is not a try")
        XCTAssertEqual(gate.consecutiveFailures, 0)
    }

    /// The same for a keyframe with no real time on it, and for the beak.
    func testEveryNonFiniteFieldIsCaughtBeforeItReachesTheResolver() {
        let clock = FakeClock()
        for proposal in [
            MotionProposal(name: "t", keys: [.init(atSeconds: .infinity, moves: [])]),
            MotionProposal(name: "m", keys: [.init(atSeconds: 0.4, moves: [], mouthOpen: .nan)]),
        ] {
            var gate = DraftGate(now: { clock.seconds })
            let outcome = gate.draft(proposal)
            XCTAssertTrue(feedbackOf(outcome)?.contains("not a number") == true, "\(outcome)")
            XCTAssertEqual(gate.budget.spent, 0)
        }
    }

    /// A model producing nothing at all is a FAILED TRY, not a broken call —
    /// it got as far as being asked, and it counts.
    func testAProposalWithNoKeyframesIsAFailedTryAndCostsOne() {
        let clock = FakeClock()
        var gate = DraftGate(now: { clock.seconds })
        let outcome = gate.draft(MotionProposal(name: "nothing", keys: []))
        XCTAssertEqual(feedbackOf(outcome), MotionProposal.Unresolvable.noKeyframes.message)
        XCTAssertEqual(gate.budget.spent, 1)
        XCTAssertEqual(gate.consecutiveFailures, 1)
    }
}
