import XCTest
@testable import StudioKit

/// The mean, against the mean their library actually computes.
///
/// WHY A TABLE OF BIT PATTERNS AND NOT A TOLERANCE. The whole point of
/// `ExactMean` is the last unit in the last place, so a test written with
/// `accuracy:` would pass on exactly the defect it exists to catch. Every
/// expectation below is the raw sixty-four bits of a Double, so the assertion
/// is bit for bit or it is nothing.
///
/// WHERE THE EXPECTATIONS COME FROM. They were computed on 2026-09-05 by
/// `statistics.mean` in the venv that the cross-language gate uses, Python
/// 3.13.5 with inspect-robots 0.58.0 installed, and printed as
/// `struct.pack('<d', value)`. inspect-robots reduces epochs with
/// `statistics.mean` (`scorer.py` `reduce_mean`) and aggregates metrics with it
/// (`eval.py`), so these are the numbers their run of the same values produces.
/// Five of the twenty-four differ from a running sum in Double, which is what
/// this kit did before and what makes the table worth having.
///
/// A NOTE ON PYTHON'S OWN `sum`. CPython compensates its float `sum`, so
/// `sum(values)/n` in Python often agrees with `statistics.mean` where a Swift
/// `reduce(0, +)` does not. The comparison that matters is against
/// `statistics.mean`, which is the function their code calls.
final class ExactMeanTests: XCTestCase {

    static let cases: [(String, [Double], UInt64)] = [
        ("twelve scenes at 0.6405", [0.6405, 0.6405, 0.6405, 0.6405, 0.6405, 0.6405, 0.6405, 0.6405, 0.6405, 0.6405, 0.6405, 0.6405], 0x3fe47ef9db22d0e5),
        ("twelve scenes at 18.9", [18.9, 18.9, 18.9, 18.9, 18.9, 18.9, 18.9, 18.9, 18.9, 18.9, 18.9, 18.9], 0x4032e66666666666),
        ("three walk scenes", [0.48661075, 0.4901935, 0.48838525], 0x3fdf41e364bec67a),
        ("ball closest approach", [41.2, 620.5, 620.5, 620.5, 41.2, 620.5, 620.5, 620.5, 41.2, 620.5, 620.5, 620.5, 41.2, 620.5], 0x407c6fc57c57c57c),
        ("two halves", [0.1, 0.2], 0x3fc3333333333334),
        ("one value", [0.30000000000000004], 0x3fd3333333333334),
        ("negative and positive", [-1.5, 2.25, -0.75], 0x0000000000000000),
        ("tiny and huge", [1e-300, 1e+300, -1e+300], 0x018c92d503f699cc),
        ("all negative zero", [-0.0, -0.0], 0x0000000000000000),
        ("cancels exactly", [1.0, -1.0], 0x0000000000000000),
        ("subnormal", [5e-324, 5e-324, 5e-324], 0x0000000000000001),
        ("seven sevenths", [0.14285714285714285, 0.14285714285714285, 0.14285714285714285, 0.14285714285714285, 0.14285714285714285, 0.14285714285714285, 0.14285714285714285], 0x3fc2492492492492),
        ("random 0", [2.194453711499529, 2.1411780383084977, 1.6873083322785822, -0.2890060764026079, 2.130273815425552, -1.8605878121557684, 1.8234018763262911, -0.14542058274674208, 0.683753004356185], 0x3fedbe54d5c57cae),
        ("random 1", [-2.4352592626246894, -1.179592424252847, -2.4559767750489634, 1.857867206203065], 0xbff0da1283f296c8),
        ("random 2", [0.5726190350440179, -0.6230401412505908], 0xbf99d0cb945ee940),
        ("random 3", [0.9235352012030429, 0.6933762274714246, -2.0550354291590254, -2.9099955783023708, 0.17028759702287255, -2.64269336898687, -1.8587504232124252, -1.5483419180087115, -2.819504464651269], 0xbff56ac776666cdd),
        ("random 4", [-1.0422398847104115, 0.5457566608083448, -1.8280717349443985, -1.5981261741984618, -1.2350905761224116, -2.9724373670317448, -2.490067431748068, 0.9288098340405329, -0.5593275726889284], 0xbff23940178cb756),
        ("random 5", [1.2468577289876972, -1.1083366979067006, -1.6220045903525666], 0xbfdfa5cc579a2285),
        ("random 6", [-2.821488526304506, 0.37885356394743397, -2.352438506466159, -2.353181369010346, -1.254582641131571, -2.599040957180751], 0xbffd569d9d24d689),
        ("random 7", [2.0838586398168264, -2.9967303776665775], 0xbfdd363eca703c58),
        ("small 0", [9.270421483387941e-07, 5.232259236266667e-08, 3.7546320989995397e-07, 7.088991433190135e-07, 4.197914009767647e-07], 0x3ea0aaa6fc346525),
        ("small 1", [6.294549122340242e-07, 7.785108586766508e-07, 2.6977558685014267e-07, 8.714419835217013e-08, 3.325856254633479e-07, 9.64076216593764e-07, 7.580405169937588e-07, 1.179916794195508e-07, 2.4638794889312995e-07, 1.0104630895670508e-07, 5.98934029410767e-08], 0x3e9a81e74a5e9f3c),
        ("small 2", [4.868232919102767e-07, 6.820774418063098e-07, 1.8838546758461648e-07, 5.088654398224086e-07, 9.852814058355556e-07, 7.695219973546793e-07, 4.1923049571897917e-07, 3.8375178811332566e-07, 3.94853371536401e-07, 9.900522471432809e-07, 4.709085061771478e-10, 8.643339423159438e-07, 9.748570606366656e-07, 5.92740627409109e-07], 0x3ea3c08de42a257c),
        ("small 3", [2.107102214344394e-07, 3.942746370720543e-07], 0x3e944cc7c5eab55a),
    ]

    func testEveryCaseMatchesStatisticsMean() {
        for (label, values, expected) in Self.cases {
            guard let mean = ExactMean.mean(values) else {
                return XCTFail("\(label): no mean over \(values.count) values")
            }
            XCTAssertEqual(mean.bitPattern, expected,
                           "\(label): \(mean) is not statistics.mean of \(values)")
        }
    }

    /// The five the table is really for, named so a failure says which
    /// direction the arithmetic went. These are the cases where adding the
    /// values up in Double and dividing lands one unit in the last place away
    /// from the answer their library gives.
    func testTheCasesARunningSumGetsWrong() {
        let differ = ["three walk scenes", "ball closest approach",
                      "random 3", "random 4", "small 2"]
        var seen = 0
        for (label, values, expected) in Self.cases where differ.contains(label) {
            seen += 1
            let running = values.reduce(0, +) / Double(values.count)
            XCTAssertNotEqual(running.bitPattern, expected,
                              "\(label) no longer distinguishes the two sums")
            XCTAssertEqual(ExactMean.mean(values)?.bitPattern, expected, label)
        }
        XCTAssertEqual(seen, differ.count, "a named case has gone out of the table")
    }

    /// Twelve scenes that each measured exactly the same number average to that
    /// number. This is the one that shipped wrong: `stairs_mixed.json` carried
    /// 0.6405000000000001 for twelve scenes of 0.6405.
    func testTwelveEqualScenesAverageToTheirOwnValue() {
        XCTAssertEqual(ExactMean.mean([Double](repeating: 0.6405, count: 12)), 0.6405)
        XCTAssertEqual(ExactMean.mean([Double](repeating: 18.9, count: 12)), 18.9)
        XCTAssertNotEqual([Double](repeating: 0.6405, count: 12).reduce(0, +) / 12, 0.6405,
                          "the running sum this replaced no longer disagrees")
    }

    /// `Fraction` has no signed zero, so neither has theirs, and neither has
    /// this: a list of negative zeros means +0.0 upstream.
    func testAZeroMeanIsPositive() {
        XCTAssertEqual(ExactMean.mean([-0.0, -0.0])?.sign, .plus)
        XCTAssertEqual(ExactMean.mean([1.0, -1.0])?.sign, .plus)
        XCTAssertEqual(ExactMean.mean([-0.0, 0.0]), 0)
    }

    func testAnEmptyListHasNoMean() {
        XCTAssertNil(ExactMean.mean([]))
    }

    /// A single value is itself, whatever it is, because one exact value
    /// divided by one is that value.
    func testOneValueIsItself() {
        for value in [0.1, -3.25, 1e-308, 1e308, 0.30000000000000004] {
            XCTAssertEqual(ExactMean.mean([value]), value)
        }
    }

    /// Upstream raises on a non finite value: `Fraction(float('inf'))` cannot
    /// be built. A phone does not get to raise, so the ordinary sum's answer
    /// carries through to the writer, which nulls it and names the scorer.
    func testANonFiniteValueFallsBackRatherThanTrapping() {
        XCTAssertEqual(ExactMean.mean([1.0, .infinity]), .infinity)
        XCTAssertEqual(ExactMean.mean([-.infinity, 1.0]), -.infinity)
        XCTAssertEqual(ExactMean.mean([.nan, 1.0])?.isNaN, true)
    }

    /// The reducer is the caller of it, and `EvalEpochs` is where a scene's
    /// epochs are collapsed, so the two cannot disagree.
    func testTheMeanReducerIsThisMean() {
        let values = [0.48661075, 0.4901935, 0.48838525]
        XCTAssertEqual(EvalEpochs.reduce(values, with: .mean)?.bitPattern,
                       ExactMean.mean(values)?.bitPattern)
        XCTAssertEqual(EvalEpochs.reduce(values, with: .mean), 0.4883965)
    }

    // MARK: - the big integer under it

    func testTheBigIntegerAddsAcrossAWordBoundary() {
        var big = Big(UInt64.max)
        big.add(Big(1))
        XCTAssertEqual(big.bitWidth, 65)
        XCTAssertTrue(big.bit(at: 64))
        XCTAssertFalse(big.bit(at: 0))
    }

    func testTheBigIntegerSubtractsBackToZero() {
        var big = Big(UInt64.max)
        big.add(Big(UInt64.max))
        let back = big.subtracting(Big(UInt64.max))
        XCTAssertEqual(back.compare(Big(UInt64.max)), 0)
        XCTAssertTrue(back.subtracting(Big(UInt64.max)).isZero)
    }

    func testTheBigIntegerShiftsAndDivides() {
        let shifted = Big(3).shiftedLeft(by: 130)
        XCTAssertEqual(shifted.bitWidth, 132)
        let (quotient, remainder) = shifted.dividing(by: 4)
        XCTAssertEqual(remainder, 0)
        XCTAssertEqual(quotient.compare(Big(3).shiftedLeft(by: 128)), 0)
        let (odd, left) = Big(10).dividing(by: 4)
        XCTAssertEqual(odd.compare(Big(2)), 0)
        XCTAssertEqual(left, 2)
    }

    func testTheBigIntegerReadsItsOwnBits() {
        let value = Big(0b1011).shiftedLeft(by: 70)
        XCTAssertTrue(value.bit(at: 73))
        XCTAssertFalse(value.bit(at: 72))
        XCTAssertTrue(value.anyBit(below: 72))
        XCTAssertFalse(value.anyBit(below: 70))
        XCTAssertEqual(value.bits(from: 70, count: 4), 0b1011)
    }
}
