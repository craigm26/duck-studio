import XCTest
@testable import StudioKit

final class DragTests: XCTestCase {

    // MARK: - reaching something that is not on the floor

    /// The ground-pick arc sweeps the mouth from 184 mm down to 35 mm, so a
    /// leaning broom handle is a matter of TIMING rather than of a reach the
    /// duck does not have.
    func testTheArcPassesEveryUsefulHeight() {
        XCTAssertNotNil(Retrieval.Reach.graspTime(forHeight: 0.15))
        XCTAssertNotNil(Retrieval.Reach.graspTime(forHeight: 0.05))
        XCTAssertNil(Retrieval.Reach.graspTime(forHeight: 0.25), "higher than it ever reaches")
        XCTAssertNil(Retrieval.Reach.graspTime(forHeight: 0.01), "below the bottom of the arc")
    }

    /// Measured crossings, and the ordering that matters: the higher the
    /// target, the earlier the bite.
    func testHigherThingsAreBittenEarlier() {
        let high = Retrieval.Reach.graspTime(forHeight: 0.15)!
        let middle = Retrieval.Reach.graspTime(forHeight: 0.10)!
        let low = Retrieval.Reach.graspTime(forHeight: 0.06)!
        XCTAssertEqual(high, 0.18, accuracy: 0.01)
        XCTAssertEqual(middle, 0.30, accuracy: 0.01)
        XCTAssertLessThan(high, middle)
        XCTAssertLessThan(middle, low)
    }

    /// Between two measured rows it interpolates rather than snapping.
    func testItInterpolatesBetweenMeasuredCrossings() {
        let at = Retrieval.Reach.graspTime(forHeight: 0.11)!
        XCTAssertGreaterThan(at, 0.26)
        XCTAssertLessThan(at, 0.30)
    }

    /// The descending pass, not the ascending one: a bite taken on the way up
    /// is a bite taken while pulling away.
    func testEveryGraspIsOnTheWayDown() {
        for height in [0.15, 0.12, 0.10, 0.08, 0.06] {
            XCTAssertLessThan(Retrieval.Reach.graspTime(forHeight: height)!,
                              Retrieval.graspInstant + 0.01)
        }
    }

    // MARK: - pulling

    /// Both ceilings come from declared values: the mass out of the MJCF, the
    /// torque limit training runs at, the lever out of the kinematics.
    func testTheTwoCeilings() {
        // 0.7 x 0.7372 x 9.81
        XCTAssertEqual(Retrieval.Drag.pullBeforeSlipping(footFriction: 0.7), 5.06, accuracy: 0.02)
        XCTAssertEqual(Retrieval.Drag.pullBeforeSlipping(footFriction: 1.3), 9.40, accuracy: 0.02)
        // 0.6405 / 0.0836
        XCTAssertEqual(Retrieval.Drag.pullBeforeNeckStalls, 7.66, accuracy: 0.02)
    }

    /// WHICH ceiling binds depends on the floor, and both cases happen inside
    /// the friction range training actually randomises over.
    func testTheBindingLimitChangesWithTheFloor() {
        let slippery = Retrieval.Drag.ceiling(footFriction: 0.7)
        XCTAssertEqual(slippery.newtons, 5.06, accuracy: 0.02)
        XCTAssertTrue(slippery.limit.contains("feet"))
        let grippy = Retrieval.Drag.ceiling(footFriction: 1.3)
        XCTAssertEqual(grippy.newtons, 7.66, accuracy: 0.02)
        XCTAssertTrue(grippy.limit.contains("neck"))
    }

    /// A light broom on a smooth floor is inside the ceiling; a heavy one on
    /// carpet is not.
    func testABroomEitherWay() {
        let light = Retrieval.Drag.verdict(kilograms: 0.5, floorFriction: 0.3)
        XCTAssertTrue(light.isWithin)                       // 1.47 N against 5.06
        XCTAssertTrue(light.message.contains("ceiling, not a demonstration"))
        let heavy = Retrieval.Drag.verdict(kilograms: 1.2, floorFriction: 0.6)
        XCTAssertFalse(heavy.isWithin)                      // 7.06 N against 5.06
        XCTAssertTrue(heavy.message.contains("feet"))
    }

    /// The ceiling is quoted at the WORST friction training covers, because one
    /// quoted at the best case flatters.
    func testTheDefaultIsThePessimisticFriction() {
        let pessimistic = Retrieval.Drag.verdict(kilograms: 1.0, floorFriction: 0.6)
        let optimistic = Retrieval.Drag.verdict(kilograms: 1.0, floorFriction: 0.6,
                                                footFriction: 1.3)
        XCTAssertFalse(pessimistic.isWithin)                // 5.89 N against 5.06
        XCTAssertTrue(optimistic.isWithin)                  // 5.89 N against 7.66
    }

    /// And the honest limit of all of it.
    func testTheOpenQuestionIsStated() {
        XCTAssertTrue(Retrieval.Drag.untestedNote.contains("Staying upright while dragging"))
        XCTAssertTrue(Retrieval.Drag.untestedNote.contains("10–40 g"))
    }
}

/// The broom, end to end from a sentence.
extension DragTests {

    func testAStandingBroomIsATimingProblemNotAReachProblem() {
        let (reading, plan) = Retrieval.plan(for: "drag the broom standing in the corner over here")
        XCTAssertEqual(reading.object, "broom")
        XCTAssertTrue(reading.wantsDrag)
        XCTAssertEqual(reading.stick.graspHeightMillimetres, 150)
        XCTAssertNotNil(Retrieval.Reach.graspTime(forHeight: 0.15))
        XCTAssertTrue(plan.isPossible, "\(plan.refusals.map(\.message))")
        XCTAssertTrue(plan.steps.contains(.dragBack(metres: 1.0)))
    }

    /// Laid down, it is back on the floor — and a 25 mm handle clears the
    /// 20 mm bite, so it still works.
    func testABroomLaidDownIsGraspedOnTheFloor() {
        let (reading, plan) = Retrieval.plan(for: "the broom is laid down, drag it back")
        XCTAssertNil(reading.stick.graspHeightMillimetres)
        XCTAssertTrue(plan.isPossible, "\(plan.refusals.map(\.message))")
    }

    /// A 600 g broom on a rug is past the pull, and then it is a real refusal.
    func testABroomOnAStickyFloorIsRefused() {
        let heavy = Retrieval.Stick(grams: 600, thicknessMillimetres: 25, metresAway: 1,
                                    graspHeightMillimetres: 150, floorFriction: 0.9)
        let plan = Retrieval.plan(for: heavy)
        XCTAssertFalse(plan.isPossible)                     // 5.30 N against 5.06
        guard case .tooHeavyToDrag? = plan.refusals.first else {
            return XCTFail("expected the drag refusal, got \(plan.refusals)")
        }
    }

    /// The same broom on a smooth board is inside the ceiling. The floor is
    /// the difference, which is why it is an input rather than a constant.
    func testTheSameBroomOnASmoothFloorIsNot() {
        let easy = Retrieval.Stick(grams: 600, thicknessMillimetres: 25, metresAway: 1,
                                   graspHeightMillimetres: 150, floorFriction: 0.3)
        XCTAssertTrue(Retrieval.plan(for: easy).isPossible)  // 1.77 N against 5.06
    }

    /// Held higher than the arc ever reaches, it says so and says what to do.
    func testSomethingHeldTooHighIsRefusedWithTheNumbers() {
        let high = Retrieval.Stick(grams: 30, thicknessMillimetres: 25, metresAway: 1,
                                   graspHeightMillimetres: 400)
        let plan = Retrieval.plan(for: high)
        XCTAssertFalse(plan.isPossible)
        XCTAssertTrue(plan.refusals.first!.message.contains("184 mm"))
        XCTAssertTrue(plan.refusals.first!.message.contains("lay it down"))
    }

    /// A thin thing held UP is fine — the bite only has to clear the floor
    /// when the thing is on the floor.
    func testThicknessOnlyMattersOnTheFloor() {
        let onFloor = Retrieval.Stick(grams: 20, thicknessMillimetres: 7, metresAway: 1)
        XCTAssertFalse(Retrieval.plan(for: onFloor).isPossible)
        let heldUp = Retrieval.Stick(grams: 20, thicknessMillimetres: 7, metresAway: 1,
                                     graspHeightMillimetres: 120)
        XCTAssertTrue(Retrieval.plan(for: heldUp).isPossible)
    }
}
