import XCTest
import DuckKit
@testable import StudioKit

/// The search over a network's own weights.
///
/// These are written against measurements taken on the desk bench before any of
/// `WeightSearch` existed: whole-network perturbations at eight step sizes, and
/// a five-generation run that took `alpha_walking` from 1.1700 m to 1.3862 m of
/// forward travel while keeping 0.98× of its sideways travel. Where a number
/// below looks arbitrary it came from that run.
final class WeightSearchTests: XCTestCase {

    private func layer(_ weights: [Float], _ biases: [Float] = [0, 0]) -> DuckPolicyWriter.Layer {
        DuckPolicyWriter.Layer(weights: weights, biases: biases,
                               inputs: weights.count / Swift.max(biases.count, 1),
                               outputs: biases.count)
    }

    // MARK: - the step is relative to each layer's own spread

    func testScalesAreEachLayersOwnSpread() {
        let flat = layer([1, 1, 1, 1])
        let spread = layer([0, 2, 0, 2])
        let scales = WeightSearch.scales(of: [flat, spread])
        XCTAssertEqual(scales[0], 0, accuracy: 1e-9)
        XCTAssertEqual(scales[1], 1, accuracy: 1e-9)
    }

    /// THE ONE THAT MATTERS. The four real layers differ 3.7× in spread, so a
    /// single absolute step is a nudge in one and most of a standard deviation
    /// in another.
    func testLayersWithDifferentSpreadsGetDifferentScales() {
        let wide = layer([-2, 2, -2, 2])
        let tight = layer([-0.05, 0.05, -0.05, 0.05])
        let scales = WeightSearch.scales(of: [wide, tight])
        XCTAssertGreaterThan(scales[0] / scales[1], 10)
    }

    // MARK: - a candidate is a seed, not a copy

    func testTheSameSeedGivesTheSameNoiseEveryTime() {
        let p = WeightSearch.Perturbation(seed: 12345)
        XCTAssertEqual(p.noise(count: 64), p.noise(count: 64))
    }

    /// `Hasher` is seeded per launch and would pass the test above while
    /// failing this one, which is the whole reason this generator exists.
    func testTheNoiseIsTheSameSequenceNotJustTheSameLength() {
        let first = WeightSearch.Perturbation(seed: 99).noise(count: 8)
        XCTAssertEqual(first[3], WeightSearch.Perturbation(seed: 99).noise(count: 8)[3])
        XCTAssertNotEqual(first, WeightSearch.Perturbation(seed: 100).noise(count: 8))
    }

    func testEveryPairAndGenerationGetsItsOwnNoise() {
        let root = WeightSearch.Perturbation(seed: 7)
        let a = root.forPair(0, generation: 1).noise(count: 16)
        let b = root.forPair(1, generation: 1).noise(count: 16)
        let c = root.forPair(0, generation: 2).noise(count: 16)
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testTheNoiseIsRoughlyStandardNormal() {
        let n = WeightSearch.Perturbation(seed: 4242).noise(count: 20_000)
        let mean = n.reduce(0, +) / Float(n.count)
        let variance = n.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) } / Float(n.count)
        XCTAssertEqual(Double(mean), 0, accuracy: 0.05)
        XCTAssertEqual(Double(variance.squareRoot()), 1, accuracy: 0.1)
    }

    func testAnOddCountStillComesBackFull() {
        XCTAssertEqual(WeightSearch.Perturbation(seed: 1).noise(count: 7).count, 7)
    }

    // MARK: - antithetic means the pair is symmetric

    func testThePairIsTheSamePerturbationBothWays() {
        let base = [layer([0.1, -0.2, 0.3, -0.4])]
        let scales = WeightSearch.scales(of: base)
        let p = WeightSearch.Perturbation(seed: 5)
        let plus = WeightSearch.candidate(from: base, scales: scales, perturbation: p,
                                          step: 0.05, adding: true)
        let minus = WeightSearch.candidate(from: base, scales: scales, perturbation: p,
                                           step: 0.05, adding: false)
        for k in base[0].weights.indices {
            let up = plus[0].weights[k] - base[0].weights[k]
            let down = base[0].weights[k] - minus[0].weights[k]
            XCTAssertEqual(up, down, accuracy: 1e-6)
        }
    }

    /// A bias is one number against a hundred weights feeding the same output,
    /// so moving it at the same relative scale moves the output far more.
    func testTheBiasesAreNotTouched() {
        let base = [layer([0.1, -0.2, 0.3, -0.4], [0.5, -0.5])]
        let out = WeightSearch.candidate(from: base, scales: WeightSearch.scales(of: base),
                                         perturbation: .init(seed: 3), step: 0.05, adding: true)
        XCTAssertEqual(out[0].biases, base[0].biases)
    }

    func testAStepOfZeroChangesNothing() {
        let base = [layer([0.1, -0.2, 0.3, -0.4])]
        let out = WeightSearch.candidate(from: base, scales: WeightSearch.scales(of: base),
                                         perturbation: .init(seed: 3), step: 0, adding: true)
        XCTAssertEqual(out[0].weights, base[0].weights)
    }

    // MARK: - the step comes from the order, not the size

    /// A TIE IS A TIE. Every candidate that fell over scores the same −1, so a
    /// generation that knocks half of them down would otherwise step along the
    /// average of their noise — which is noise.
    func testTiedRewardsShareARankAndSoCancel() {
        let r = WeightSearch.ranks(of: [1, 1, 1, 1])
        XCTAssertEqual(Set(r).count, 1)
        XCTAssertEqual(r[0] - r[1], 0, accuracy: 1e-12)
    }

    func testAPartialTieStillOrdersTheRest() {
        let r = WeightSearch.ranks(of: [5, 1, 1, 9])
        XCTAssertEqual(r[1], r[2], accuracy: 1e-12)
        XCTAssertLessThan(r[1], r[0])
        XCTAssertLessThan(r[0], r[3])
    }

    func testRanksSpanMinusHalfToPlusHalf() {
        let r = WeightSearch.ranks(of: [5, 1, 3, 2])
        XCTAssertEqual(r.min(), -0.5)
        XCTAssertEqual(r.max(), 0.5)
    }

    /// ONE LUCKY EPISODE MUST NOT OWN A GENERATION. These two reward sets have
    /// wildly different magnitudes and identical order, so they must produce
    /// identical steps.
    func testOnlyTheOrderOfTheRewardsMatters() {
        XCTAssertEqual(WeightSearch.ranks(of: [1, 2, 3, 4]),
                       WeightSearch.ranks(of: [1, 2, 3, 4_000_000]))
    }

    func testRanksOfOneRewardAreZeroRatherThanACrash() {
        XCTAssertEqual(WeightSearch.ranks(of: [7]), [0])
    }

    // MARK: - the step and the candidates must share their noise

    /// THE BUG THIS EXISTS FOR, AND IT WOULD BE INVISIBLE. If `stepped` derives
    /// its noise differently from `candidate`, every generation moves the
    /// network along a direction nothing was ever scored on — a search that
    /// runs, reports, costs an hour of bench time and does nothing. No gate
    /// downstream can see it, because the numbers all look reasonable.
    ///
    /// So: score a pair where the ADDING half wins by a mile, and check the
    /// network actually moved towards that half's weights.
    func testTheStepMovesTowardsTheHalfOfThePairThatWon() throws {
        let base = [layer([0.10, -0.20, 0.30, -0.40, 0.15, -0.25])]
        let scales = WeightSearch.scales(of: base)
        let seed = WeightSearch.Perturbation(seed: 2026)
        let settings = try WeightSearch.Settings(step: 0.05, rate: 0.5, pairs: 3, generations: 1)

        // Pair 0's adding half is the best thing in the generation and its
        // subtracting half the worst; the other two pairs tie, so they
        // contribute exactly nothing and the move is pair 0's noise alone.
        let rewards: [Double] = [10, -10, 1, 1, 1, 1]
        let moved = WeightSearch.stepped(base, scales: scales, seed: seed, generation: 1,
                                         rewards: rewards, settings: settings)

        let winner = WeightSearch.candidate(
            from: base, scales: scales,
            perturbation: seed.forPair(0, generation: 1), step: 0.05, adding: true)

        // The move and the winning candidate must point the same way on every
        // weight. A step built from unrelated noise agrees on about half.
        var agreed = 0
        for k in base[0].weights.indices {
            let towardsWinner = winner[0].weights[k] - base[0].weights[k]
            let actuallyMoved = moved[0].weights[k] - base[0].weights[k]
            if towardsWinner.sign == actuallyMoved.sign { agreed += 1 }
        }
        XCTAssertEqual(agreed, base[0].weights.count,
                       "the step used different noise from the candidates")
    }

    func testAGenerationWhereEveryPairTiedMovesNothing() throws {
        let base = [layer([0.1, -0.2, 0.3, -0.4])]
        let settings = try WeightSearch.Settings(step: 0.05, rate: 0.5, pairs: 3, generations: 1)
        // Ranks are symmetric within every pair, so every advantage is zero.
        let moved = WeightSearch.stepped(base, scales: WeightSearch.scales(of: base),
                                         seed: .init(seed: 1), generation: 1,
                                         rewards: [1, 1, 2, 2, 3, 3], settings: settings)
        for k in base[0].weights.indices {
            XCTAssertEqual(moved[0].weights[k], base[0].weights[k], accuracy: 1e-6)
        }
    }

    func testALayerWithNoSpreadIsLeftAlone() throws {
        let flat = layer([1, 1, 1, 1])
        let settings = try WeightSearch.Settings(step: 0.05, rate: 0.5, pairs: 3, generations: 1)
        let moved = WeightSearch.stepped([flat], scales: [0], seed: .init(seed: 1),
                                         generation: 1, rewards: [3, 1, 2, 0, 1, 0],
                                         settings: settings)
        XCTAssertEqual(moved[0].weights, flat.weights)
    }

    // MARK: - a duck that fell over has not walked

    func testAFallenDuckScoresBelowAnyWalk() {
        let fell = WeightSearch.reward(travelled: 9.9, standing: 3, episodes: 4)
        let walked = WeightSearch.reward(travelled: 0.01, standing: 4, episodes: 4)
        XCTAssertLessThan(fell, walked)
    }

    func testAStandingDuckIsWorthWhatItTravelled() {
        XCTAssertEqual(WeightSearch.reward(travelled: 1.3862, standing: 4, episodes: 4), 1.3862)
    }

    func testNoEpisodesIsNotAPass() {
        XCTAssertEqual(WeightSearch.reward(travelled: 5, standing: 0, episodes: 0), -1)
    }

    // MARK: - the settings refuse rather than clamp

    func testAStepThatReversesTheWalkIsRefusedByName() {
        // A quarter of a layer's spread measured −0.3702 m: backwards, while
        // passing every standing check.
        XCTAssertThrowsError(try WeightSearch.Settings(step: 0.25)) {
            XCTAssertEqual($0 as? WeightSearch.Refusal, .stepOutsideTheBand(0.25))
        }
    }

    func testAStepInsideTheMeasuredBandIsAccepted() {
        XCTAssertNoThrow(try WeightSearch.Settings(step: 0.05))
        XCTAssertNoThrow(try WeightSearch.Settings(step: 0.10))
    }

    func testTooFewPairsToRankIsRefused() {
        XCTAssertThrowsError(try WeightSearch.Settings(step: 0.05, pairs: 2)) {
            XCTAssertEqual($0 as? WeightSearch.Refusal, .tooFewPairs(2))
        }
    }

    func testTheCostIsTheMeasuredOne() throws {
        let s = try WeightSearch.Settings(step: 0.05, pairs: 10, generations: 8)
        XCTAssertEqual(s.callsPerGeneration, 21)
        // 21 × 8 × 2.33 s ≈ 391 s.
        XCTAssertEqual(s.seconds, 391.44, accuracy: 0.5)
    }

    // MARK: - the verdict, and the held-out commands

    func testTheMeasuredRunSurvives() {
        // The real one: +18.5% forward, 0.98× sideways, upright throughout.
        let v = WeightSearch.Verdict(gained: 1.1848, keptElsewhere: 0.98, stoodUp: true)
        XCTAssertTrue(v.survived)
        XCTAssertTrue(WeightSearch.verdictSaid(v).contains("kept"))
    }

    /// THE FAILURE THE TWENTY-EIGHT-NUMBER SEARCH SHIPPED. Four winners in
    /// eight gained forward reward and kept 1.6–2.0% of their sideways travel,
    /// and every gate passed them.
    func testAWinnerThatSoldItsSidewaysTravelDoesNotSurvive() {
        let v = WeightSearch.Verdict(gained: 1.95, keptElsewhere: 0.018, stoodUp: true)
        XCTAssertFalse(v.survived)
        XCTAssertTrue(WeightSearch.verdictSaid(v).contains("giving up"))
    }

    func testAFallenWinnerDoesNotSurviveHoweverFarItWent() {
        let v = WeightSearch.Verdict(gained: 3, keptElsewhere: 1, stoodUp: false)
        XCTAssertFalse(v.survived)
    }

    func testASearchThatWentBackwardsSaysSo() {
        let v = WeightSearch.Verdict(gained: 0.8, keptElsewhere: 1, stoodUp: true)
        XCTAssertFalse(v.survived)
        XCTAssertTrue(WeightSearch.verdictSaid(v).contains("still the better policy"))
    }

    /// The honest winners kept 82–86% and the farming ones 1.6–2.0%. Any line
    /// in that gap separates them; this pins that ours is in it.
    func testTheKeptFloorSitsInTheMeasuredGap() {
        XCTAssertGreaterThan(WeightSearch.Verdict.keptFloor, 0.02)
        XCTAssertLessThan(WeightSearch.Verdict.keptFloor, 0.82)
    }

    func testKeptIsAFractionOfWhatItUsedToDo() {
        XCTAssertEqual(WeightSearch.kept(after: 0.2923, before: 0.2980), 0.98, accuracy: 0.01)
        XCTAssertTrue(WeightSearch.kept(after: 1, before: 0).isNaN)
    }

    // MARK: - what a searched network is called

    /// A SEARCHED NETWORK IS NOT A TUNED ONE, and a folder full of both should
    /// say which is which.
    func testASearchedNetworkIsNamedApartFromATunedOne() throws {
        let base = try DuckPolicy.load(contentsOf: URL(fileURLWithPath:
            "/home/craigm26/projects/duck-studio/DuckStudio/Resources/alpha_walking.onnx"))
        let name = WeightSearch.filename(for: base)
        XCTAssertTrue(name.hasPrefix("searched-"))
        XCTAssertTrue(name.hasSuffix(".onnx"))
        XCTAssertNotEqual(name, DuckTuner.filename(for: base))
    }

    /// THE DIGEST, NOT THE BASE'S NAME: three runs against one network are
    /// three networks, and one filename for all of them is how the second
    /// overwrites the first on somebody's robot.
    func testTwoDifferentNetworksGetTwoDifferentNames() throws {
        let base = try DuckPolicy.load(contentsOf: URL(fileURLWithPath:
            "/home/craigm26/projects/duck-studio/DuckStudio/Resources/alpha_walking.onnx"))
        let p = base.parameters
        let moved = WeightSearch.candidate(from: p.layers,
                                           scales: WeightSearch.scales(of: p.layers),
                                           perturbation: .init(seed: 11),
                                           step: 0.05, adding: true)
        let other = try DuckPolicy.load(from: DuckPolicyWriter.encoded(
            mean: p.mean, std: p.std, layers: moved))
        XCTAssertNotEqual(WeightSearch.filename(for: base), WeightSearch.filename(for: other))
    }

    // MARK: - the sentences

    func testTheScreensWordsAreTheKits() {
        XCTAssertEqual(WeightSearch.percentSaid(0.05), "5.0%")
        XCTAssertEqual(WeightSearch.percentSaid(0.001), "0.1%")
        XCTAssertEqual(WeightSearch.benchRunsSaid(1), "1 run on the bench so far.")
        XCTAssertEqual(WeightSearch.benchRunsSaid(42), "42 runs on the bench so far.")
        for heading in [WeightSearch.whatThisRunIsHeading, WeightSearch.theNetworkHeading,
                        WeightSearch.howFarToLookHeading, WeightSearch.generationsHeading,
                        WeightSearch.whatCameOutHeading, WeightSearch.startFromSaid,
                        WeightSearch.noBaseSaid, WeightSearch.stepSaid,
                        WeightSearch.runItHereSaid, WeightSearch.stopSaid,
                        WeightSearch.keepThisNetworkSaid, WeightSearch.pairsSaid] {
            XCTAssertFalse(heading.isEmpty)
        }
    }

    func testEverySentenceIsWrittenOut() {
        for sentence in WeightSearch.everySentence {
            XCTAssertFalse(sentence.isEmpty)
            XCTAssertTrue(sentence.hasSuffix("."), "not a sentence: \(sentence)")
        }
    }

    /// The claim has to be true in BOTH directions on the same screen.
    func testTheClaimSaysWhatItDoesAndWhatItDoesNot() {
        XCTAssertTrue(WeightSearch.whatThisIs.contains("197,774"))
        XCTAssertTrue(WeightSearch.whatThisIs.contains("does not learn a network from nothing"))
    }

    /// THE CLAIM THAT WAS WRONG IN THE OTHER DIRECTION. The screen used to say
    /// nothing here trains and a phone has no Python, mjlab or GPU — true
    /// clause by clause, and read as "a phone cannot train", which is false.
    func testTheScreenClaimNamesBothPathsRatherThanDenyingOne() {
        let said = WeightSearch.bothPathsSaid
        XCTAssertTrue(said.contains("from nothing"), "the hand-off path is not named")
        XCTAssertTrue(said.contains("already have"), "the on-phone path is not named")
        XCTAssertFalse(said.contains("Nothing here has been trained."),
                       "this is the sentence that was wrong")
    }

    func testTheRefusalForNoCommandExplainsTheTrap() {
        // /tune with no schedule scores a duck standing still, and every
        // candidate then looks identical.
        XCTAssertTrue(WeightSearch.Refusal.noCommand.message.contains("standing still"))
    }
}
