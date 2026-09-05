import XCTest
@testable import StudioKit

/// The epoch axis, its refusals, and the five reducers against the arithmetic
/// `scorer.py` does.
final class EvalEpochsTests: XCTestCase {

    // MARK: - the axis

    /// L5. There is no repeat count, so there is no control that could ask for
    /// one, so a deterministic episode cannot be written down five times and
    /// averaged into a spread of zero.
    func testTheAxisHasTwoCasesAndNeitherOfThemIsARepeatCount() throws {
        let list = try EvalEpochs.drops([0.12, 0.13], reducer: .median)
        XCTAssertEqual(list.axis, .dropHeights([0.12, 0.13]))
        XCTAssertEqual(list.count, 2)
        let one = EvalEpochs.single(reducer: .mean)
        XCTAssertEqual(one.axis, .single)
        XCTAssertEqual(one.count, 1)
        XCTAssertNil(one.axis.dropValues)
    }

    /// E6. THE LITERAL NUMBERS IN `scene_metadata` ARE WHAT KEEP AN ARCHIVED
    /// LOG MEANING WHAT IT MEANT. This axis is `DuckTuner.Schedule.onAPhone.heldOutDrops`
    /// by identity, and that array belongs to the tuner and to the weight
    /// search as well. A change to it there would silently redefine what an old
    /// evaluation's epoch axis was, which is exactly why `EvalTask.sceneMetadata`
    /// writes `drop_heights_m` as a list of numbers into every scene rather
    /// than naming the array.
    func testTheWalkAxisIsTheTunersHeldOutList() {
        XCTAssertEqual(EvalTask.walkDrops, DuckTuner.Schedule.onAPhone.heldOutDrops)
        XCTAssertEqual(EvalTask.walkDrops,
                       [0.1200, 0.1215, 0.1230, 0.1245, 0.1260, 0.1275, 0.1285, 0.1300])
    }

    // MARK: - the bench's own validation, in front of the Start button

    func testAnEmptyDropListIsRefused() {
        XCTAssertThrowsError(try EvalEpochs.drops([], reducer: .mean)) { error in
            XCTAssertEqual(error as? EvalEpochs.Refusal, .noDrops)
        }
    }

    func testADropOutsideTheBenchsRangeIsRefusedInTheBenchsOwnWords() {
        for bad in [0.0, 1.0, -0.1, 2.0, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try EvalEpochs.drops([bad], reducer: .mean)) { error in
                XCTAssertEqual(error as? EvalEpochs.Refusal, .outOfRange)
            }
        }
        XCTAssertTrue(EvalEpochs.Refusal.outOfRange.message
            .contains("a finite number of metres between 0 and 1"))
    }

    func testMoreThanThirtyTwoDropsIsRefused() {
        let many = (1...33).map { 0.1 + Double($0) * 0.001 }
        XCTAssertThrowsError(try EvalEpochs.drops(many, reducer: .mean)) { error in
            XCTAssertEqual(error as? EvalEpochs.Refusal, .tooMany(33))
        }
        XCTAssertNoThrow(try EvalEpochs.drops(Array(many.prefix(32)), reducer: .mean))
    }

    /// The bench compares to nine decimal places, so this does too: two heights
    /// that differ past the ninth are the same episode counted twice.
    func testARepeatedDropIsRefusedTheWayTheBenchRefusesIt() {
        XCTAssertThrowsError(try EvalEpochs.drops([0.12, 0.12], reducer: .mean)) { error in
            XCTAssertEqual(error as? EvalEpochs.Refusal, .duplicateDrop)
        }
        XCTAssertThrowsError(try EvalEpochs.drops([0.12, 0.1200000000001],
                                                  reducer: .mean)) { error in
            XCTAssertEqual(error as? EvalEpochs.Refusal, .duplicateDrop)
        }
        XCTAssertTrue(EvalEpochs.Refusal.duplicateDrop.message
            .contains("the same height twice is the same episode counted twice"))
    }

    // MARK: - the five reducers, against theirs

    func testReducerAllCasesIsExactlyTheirFive() {
        XCTAssertEqual(EvalEpochs.Reducer.allCases.map(\.rawValue),
                       ["mean", "median", "max", "min", "mode"])
    }

    /// L12 as a count. `pass_at_k` is resolved by name in their code and is not
    /// a member of `_REDUCERS`; here it is not a case at all, so no picker can
    /// offer it.
    func testPassAtKIsNotOffered() {
        XCTAssertEqual(EvalEpochs.Reducer.allCases.count, 5)
        XCTAssertFalse(EvalEpochs.Reducer.allCases.contains { $0.rawValue.contains("pass") })
    }

    func testTheMeanIsTheArithmeticMean() {
        XCTAssertEqual(EvalEpochs.reduce([1, 2, 3, 4], with: .mean), 2.5)
    }

    /// The half a hand-rolled median usually gets wrong.
    func testTheMedianAveragesTheTwoMiddleValuesAtEvenN() {
        XCTAssertEqual(EvalEpochs.reduce([1, 2, 3, 4], with: .median), 2.5)
        XCTAssertEqual(EvalEpochs.reduce([1, 2, 3], with: .median), 2)
        XCTAssertEqual(EvalEpochs.reduce([4, 1, 3, 2], with: .median), 2.5,
                       "it has to sort first")
    }

    func testMaxAndMinAreMaxAndMin() {
        XCTAssertEqual(EvalEpochs.reduce([1, 9, 3], with: .max), 9)
        XCTAssertEqual(EvalEpochs.reduce([1, 9, 3], with: .min), 1)
    }

    /// Their `max(values, key=lambda v: (counts[v], str(v)))`: count first, and
    /// the PRINTED form second. `"2.0"` sorts after `"1.0"` by code point, so a
    /// tie between one and two picks two.
    func testTheModeBreaksATieOnThePrintedFormTheWayTheirsDoes() {
        XCTAssertEqual(EvalEpochs.reduce([1, 1, 2], with: .mode), 1)
        XCTAssertEqual(EvalEpochs.reduce([1, 2], with: .mode), 2)
        XCTAssertEqual(EvalEpochs.reduce([2, 1], with: .mode), 2,
                       "the tie break is the spelling and not the order they arrived in")
        // "10.0" begins with "1" and sorts BEFORE "9.0", which is the case a
        // numeric tie break would get wrong.
        XCTAssertEqual(EvalEpochs.reduce([10, 9], with: .mode), 9)
    }

    func testAnEmptyListReducesToNothingRatherThanToZero() {
        for reducer in EvalEpochs.Reducer.allCases {
            XCTAssertNil(EvalEpochs.reduce([], with: reducer), reducer.rawValue)
        }
    }

    // MARK: - pass@k, for reading somebody else's log

    func testPassAtKIsTheUnbiasedEstimatorTheyImplement() throws {
        // Every epoch a success: certain.
        XCTAssertEqual(try EvalEpochs.passAtK(1, over: [1, 1, 1]), 1.0)
        // None: impossible.
        XCTAssertEqual(try EvalEpochs.passAtK(1, over: [0, 0, 0]), 0.0)
        // One of four, one draw: a quarter.
        XCTAssertEqual(try EvalEpochs.passAtK(1, over: [1, 0, 0, 0]), 0.25, accuracy: 1e-12)
        // One of four, two draws: 1 - C(3,2)/C(4,2) = 1 - 3/6.
        XCTAssertEqual(try EvalEpochs.passAtK(2, over: [1, 0, 0, 0]), 0.5, accuracy: 1e-12)
        // The 0.5 threshold is theirs.
        XCTAssertEqual(try EvalEpochs.passAtK(1, over: [0.5, 0, 0, 0]), 0.25, accuracy: 1e-12)
        XCTAssertEqual(try EvalEpochs.passAtK(1, over: [0.49, 0, 0, 0]), 0.0)
    }

    func testPassAtKRefusesWhatTheirsRefuses() {
        XCTAssertThrowsError(try EvalEpochs.passAtK(0, over: [1])) { error in
            XCTAssertEqual(error as? EvalEpochs.PassAtKRefusal, .kBelowOne(0))
        }
        XCTAssertThrowsError(try EvalEpochs.passAtK(3, over: [1, 0])) { error in
            XCTAssertEqual(error as? EvalEpochs.PassAtKRefusal,
                           .notEnoughEpochs(k: 3, epochs: 2))
        }
    }

    func testChooseIsChoose() {
        XCTAssertEqual(EvalEpochs.combinations(4, 2), 6)
        XCTAssertEqual(EvalEpochs.combinations(5, 0), 1)
        XCTAssertEqual(EvalEpochs.combinations(5, 5), 1)
        XCTAssertEqual(EvalEpochs.combinations(32, 16), 601080390)
    }

    // MARK: - what a person reads

    func testTheAxisSentenceNamesTheRangeAndSaysNothingElseVaries() throws {
        let epochs = try EvalEpochs.drops([0.12, 0.1215, 0.123], reducer: .median)
        XCTAssertEqual(epochs.said,
                       "Three drop heights, 0.1200 m to 0.1230 m, each run once. Nothing else "
                     + "varies between the epochs of a scene.")
    }

    func testASingleAxisSaysWhyThereIsNothingToVary() {
        XCTAssertTrue(EvalEpochs.single(reducer: .mean).said.contains("One episode per scene"))
    }

    func testTheSeedSentenceSaysWhatVariesInstead() {
        XCTAssertTrue(EvalEpochs.noSeedSaid.contains("No seed"))
        XCTAssertTrue(EvalEpochs.noSeedSaid.contains("the height the duck is dropped from"))
    }

    /// G1: `policy_config` notes are capped at two sentences and this is one of
    /// them.
    func testTheSeedSentenceIsAtMostTwoSentences() {
        XCTAssertLessThanOrEqual(EvalStringsTests.sentences(in: EvalEpochs.noSeedSaid), 2)
    }
}
