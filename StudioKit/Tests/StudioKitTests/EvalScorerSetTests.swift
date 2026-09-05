import XCTest
@testable import StudioKit

/// The first refusal, which is a type: a success that travels alone cannot be
/// constructed.
final class EvalScorerSetTests: XCTestCase {

    func testASuccessScorerWithNoMotionEvidenceCannotBeBuilt() {
        XCTAssertThrowsError(try EvalScorerSet.checked([.successAtEnd])) { error in
            XCTAssertEqual(error as? EvalScorerSet.Refusal,
                           .successWithoutMotionEvidence("success_at_end"))
        }
        XCTAssertThrowsError(try EvalScorerSet.checked([.successAtEnd, .endHeight])) { error in
            XCTAssertEqual(error as? EvalScorerSet.Refusal,
                           .successWithoutMotionEvidence("success_at_end"),
                           "end height is context, not evidence that it went anywhere")
        }
    }

    func testASuccessScorerWithMotionEvidenceIsFine() throws {
        let set = try EvalScorerSet.checked([.successAtEnd, .travelled])
        XCTAssertEqual(set.names, ["success_at_end", "travelled_m"])
    }

    /// A set with no success scorer at all is allowed: a cost only measurement
    /// is a real thing to want, and the rule is about a success without
    /// evidence rather than about evidence without a success.
    func testASetWithNoSuccessScorerIsAllowed() throws {
        XCTAssertNoThrow(try EvalScorerSet.checked([.maxTorque]))
    }

    func testAnEmptySetIsRefused() {
        XCTAssertThrowsError(try EvalScorerSet.checked([])) { error in
            XCTAssertEqual(error as? EvalScorerSet.Refusal, .empty)
        }
    }

    func testTwoScorersCannotShareAName() {
        XCTAssertThrowsError(try EvalScorerSet.checked([.travelled, .travelled])) { error in
            XCTAssertEqual(error as? EvalScorerSet.Refusal, .duplicateName("travelled_m"))
        }
    }

    // MARK: - their names, left empty

    func testTheirNamesThisAppDoesNotFillAreRefusedRatherThanReused() {
        for name in EvalScorer.reservedNames {
            let borrowed = EvalScorer(name: name, said: "no", role: .motionEvidence,
                                      unit: "", higherIsBetter: true)
            XCTAssertThrowsError(try EvalScorerSet.checked([borrowed])) { error in
                XCTAssertEqual(error as? EvalScorerSet.Refusal, .reservedName(name))
            }
        }
    }

    func testNoSetThisAppShipsCarriesOneOfTheirNames() {
        for set in EvalScorerSet.all {
            for name in EvalScorer.reservedNames {
                XCTAssertFalse(set.names.contains(name),
                               "\(name) is a name this app says it does not emit")
            }
        }
    }

    /// L22. A verdict is recorded in their own operator fields and is never a
    /// metric, so `operator` is a name no set anywhere can carry.
    func testOperatorIsNotAScorerAnywhere() {
        XCTAssertTrue(EvalScorer.reservedNames.contains("operator"))
        for set in EvalScorerSet.all {
            XCTAssertFalse(set.names.contains("operator"))
        }
    }

    /// L15. The six reward terms are recorded per trial and are never scorers,
    /// because five of the six are maximised by a duck that does nothing.
    func testNoRewardTermIsAScorer() {
        let terms = Set(DuckTuner.terms.map(\.key))
        for set in EvalScorerSet.all {
            for name in set.names {
                XCTAssertFalse(terms.contains(name),
                               "\(name) is one of Pollen's reward terms, not a score")
            }
        }
    }

    // MARK: - the three sets this app ships

    func testEverySetThisAppShipsPassesItsOwnRule() throws {
        for set in EvalScorerSet.all {
            XCTAssertNoThrow(try EvalScorerSet.checked(set.scorers))
            XCTAssertTrue(set.scorers.contains { $0.role == .motionEvidence },
                          "\(set.names) has no motion evidence")
        }
    }

    func testTheThreeSetsAreTheOnesTheThreeRoutesNeed() {
        XCTAssertEqual(EvalScorerSet.walk.names,
                       ["success_at_end", "travelled_m", "net_displacement_m", "end_height_m"])
        XCTAssertEqual(EvalScorerSet.stairs.names,
                       ["success_at_end", "cleared_honestly", "peak_above_tread_mm",
                        "max_torque_nm"])
        XCTAssertEqual(EvalScorerSet.ball.names,
                       ["success_at_end", "ball_travel_mm", "ball_net_mm",
                        "closest_approach_mm"])
    }

    func testASetCanBeLookedUpByName() {
        XCTAssertEqual(EvalScorerSet.walk["travelled_m"]?.unit, "m")
        XCTAssertNil(EvalScorerSet.walk["nothing_like_this"])
    }

    func testTheOnlyScorersWhereLessIsBetterAreTheOnesWhereLessIsBetter() {
        XCTAssertFalse(EvalScorer.maxTorque.higherIsBetter)
        XCTAssertFalse(EvalScorer.closestApproach.higherIsBetter)
        XCTAssertTrue(EvalScorer.successAtEnd.higherIsBetter)
        XCTAssertTrue(EvalScorer.travelled.higherIsBetter)
    }

    /// THE SENTENCE WALKS THE RESERVED SET AND NOT A LIST OF ITS OWN. It said
    /// three and named three while the set reserved four, and the missing one
    /// was `operator`, which is the one most relevant to what this app does: it
    /// records a person's verdict per trial and deliberately keeps it out of
    /// `metrics`, and the copy that explains the omissions did not mention it.
    /// A second list here would let the same thing happen again.
    func testEveryReservedNameIsNamedOnScreenWithTheReason() {
        for name in EvalScorer.reservedNames {
            XCTAssertTrue(EvalScorer.notEmittedHere.contains(name), name)
        }
        XCTAssertEqual(EvalScorer.reservedNames.count, 4)
        XCTAssertTrue(EvalScorer.notEmittedHere.hasPrefix("Four of their scorers"),
                      EvalScorer.notEmittedHere)
        XCTAssertTrue(EvalScorer.notEmittedHere.contains("the same name meaning something else"))
    }

    /// And the count in the sentence is the count of the set, in words, so the
    /// two cannot say different numbers.
    func testTheCountInTheSentenceIsTheCountOfTheSet() {
        let spelled = ["", "One", "Two", "Three", "Four", "Five", "Six"]
        XCTAssertTrue(
            EvalScorer.notEmittedHere.hasPrefix("\(spelled[EvalScorer.reservedNames.count]) of "),
            EvalScorer.notEmittedHere)
    }
}
