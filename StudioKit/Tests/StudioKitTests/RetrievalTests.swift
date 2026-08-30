import XCTest
@testable import StudioKit

final class RetrievalTests: XCTestCase {

    /// The constants are upstream's, and a drift in either direction is a bug.
    func testTheScheduleMatchesUpstream() {
        XCTAssertEqual(Retrieval.phasePeriod, 4.0)            // GP_PERIOD, ground_pick_period
        XCTAssertEqual(Retrieval.endPhase, 0.7)               // GROUND_PICK_END_PHASE
        XCTAssertEqual(Retrieval.pickDuration, 2.8, accuracy: 1e-9)
        XCTAssertEqual(Retrieval.payloadRange.lowerBound, 0.010)
        XCTAssertEqual(Retrieval.payloadRange.upperBound, 0.040)
    }

    /// The grasp instant is MEASURED and lands before the config's nominal
    /// hold, not inside it. If these ever agree, one of them has changed.
    func testTheGraspInstantDisagreesWithTheConfigsHold() {
        let nominalHoldStart = 0.375 * Retrieval.phasePeriod   // DESCENT_END
        let nominalHoldEnd = 0.425 * Retrieval.phasePeriod     // HOLD_END
        XCTAssertEqual(nominalHoldStart, 1.5, accuracy: 1e-9)
        XCTAssertLessThan(Retrieval.graspInstant, nominalHoldStart)
        XCTAssertTrue(Retrieval.graspWindow.contains(Retrieval.graspInstant))
        // The measured window CLOSES where the config's hold opens.
        XCTAssertEqual(Retrieval.graspWindow.upperBound, nominalHoldStart, accuracy: 1e-9)
        XCTAssertFalse(Retrieval.graspWindow.contains(nominalHoldEnd),
                       "closing the jaw on the config's hold closes it on the way up")
    }

    func testAPencilIsTooThinToPickUp() {
        let (reading, plan) = Retrieval.plan(for: "go and fetch the pencil")
        XCTAssertEqual(reading.object, "pencil")
        XCTAssertFalse(plan.isPossible)
        XCTAssertEqual(plan.refusals.first, .tooThin(millimetres: 7))
        XCTAssertTrue(plan.refusals.first!.message.contains("20 mm above the floor"))
    }

    func testACarrotIsTooHeavy() {
        let (_, plan) = Retrieval.plan(for: "bring me the carrot")
        XCTAssertTrue(plan.refusals.contains(.tooHeavy(grams: 60)))
        XCTAssertFalse(plan.isPossible)
    }

    /// A 20 mm dowel at 25 g is inside every envelope, so the plan stands.
    func testADowelIsFetchable() {
        let (_, plan) = Retrieval.plan(for: "pick up the dowel 1 m away and bring it back")
        XCTAssertTrue(plan.isPossible, "\(plan.refusals.map(\.message))")
        XCTAssertEqual(plan.steps.count, 7)
        XCTAssertEqual(plan.steps.first, .approach(metres: 1.0))
        XCTAssertEqual(plan.steps.last, .release)
    }

    /// Distance warns, it does not refuse. Slow is not impossible.
    func testDistanceWarnsWithoutStopping() {
        let (_, plan) = Retrieval.plan(for: "fetch the stick 5 m away")
        XCTAssertTrue(plan.isPossible)
        guard case .tooFar(let metres, let minutes)? = plan.refusals.first else {
            return XCTFail("expected a distance warning, got \(plan.refusals)")
        }
        XCTAssertEqual(metres, 5, accuracy: 1e-9)
        XCTAssertEqual(minutes, 2 * 5 / 0.106 / 60, accuracy: 1e-9)
    }

    /// "2 mm thick" must not be read as a distance, and "2 m away" must not be
    /// read as a thickness.
    func testUnitsAreReadInContext() {
        let thin = Retrieval.read("a stick 4 mm thick, 2 m away")
        XCTAssertEqual(thin.stick.thicknessMillimetres, 4, accuracy: 1e-9)
        XCTAssertEqual(thin.stick.metresAway, 2, accuracy: 1e-9)
    }

    func testGramsAndKilogramsBothRead() {
        XCTAssertEqual(Retrieval.read("fetch the 30 g stick").stick.grams, 30, accuracy: 1e-9)
        XCTAssertEqual(Retrieval.read("fetch the 0.02 kg stick").stick.grams, 20, accuracy: 1e-9)
    }

    /// What was guessed has to be visible. A plan built on three defaults and
    /// presented as an answer is a guess wearing a timeline.
    func testEverythingUnsaidIsReportedAsAnAssumption() {
        let reading = Retrieval.read("fetch it")
        XCTAssertNil(reading.object)
        XCTAssertTrue(reading.understood.isEmpty)
        XCTAssertEqual(reading.assumed.count, 3)
        XCTAssertTrue(reading.assumed.contains { $0.contains("weight") })
        XCTAssertTrue(reading.assumed.contains { $0.contains("thickness") })
        XCTAssertTrue(reading.assumed.contains { $0.contains("distance") })
    }

    /// The timeline adds up, and the two policy segments together are exactly
    /// one truncated ground-pick.
    func testTheTimelineAddsUp() {
        let plan = Retrieval.plan(for: .init(grams: 25, thicknessMillimetres: 22, metresAway: 0.5))
        let walk = 0.5 / Retrieval.walkSpeed
        XCTAssertEqual(plan.seconds,
                       walk * 2 + Retrieval.pickDuration + 0.25 + 0.25 + Retrieval.settleAfterLift,
                       accuracy: 1e-9)
        let pick = plan.steps.filter { $0.policy == "alpha_ground_pick" }
        XCTAssertEqual(pick.reduce(0) { $0 + $1.seconds }, Retrieval.pickDuration, accuracy: 1e-9)
        XCTAssertEqual(plan.schedule.first!.start, 0)
        XCTAssertEqual(plan.schedule.map(\.start).sorted(), plan.schedule.map(\.start))
    }

    /// No policy drives the mouth, which is the whole reason a grasp can be
    /// scheduled at all.
    func testTheGraspIsNotAPolicyStep() {
        XCTAssertNil(Retrieval.Step.closeMouth.policy)
        XCTAssertNil(Retrieval.Step.release.policy)
        XCTAssertEqual(Retrieval.Step.approach(metres: 1).policy, "alpha_walking")
        XCTAssertEqual(Retrieval.Step.reachDown.policy, "alpha_ground_pick")
    }
}

extension RetrievalTests {

    /// A task that travels without its constraints is a task somebody runs
    /// against a carrot, so the body carries them.
    func testTheExportedTaskCarriesTheConstraints() throws {
        let plan = Retrieval.plan(for: .init(grams: 25, thicknessMillimetres: 22, metresAway: 0.8))
        let task = try plan.duckTask(named: "Fetch the dowel")
        XCTAssertEqual(task.name, "fetch-the-dowel", "a typed title is slugged, not refused")
        XCTAssertTrue(task.verbs.allow.contains("ground_pick"))
        XCTAssertTrue(task.verbs.allow.contains("mouth"))
        for fact in ["20 mm above the floor", "10–40 g", "cannot pivot", "phase 0.7", "1.16 s"] {
            XCTAssertTrue(task.body.contains(fact), "the body should say: \(fact)")
        }
        // And it survives a round trip through the format.
        XCTAssertEqual(try DuckTask.decode(task.encode()), task)
    }

    func testARefusedPlanSaysSoInTheTask() throws {
        let plan = Retrieval.plan(for: .init(grams: 25, thicknessMillimetres: 5, metresAway: 0.5))
        let task = try plan.duckTask(named: "Fetch the chopstick")
        XCTAssertTrue(task.body.contains("REFUSED:"))
    }
}
