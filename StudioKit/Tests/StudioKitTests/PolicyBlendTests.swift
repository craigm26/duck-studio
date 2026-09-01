import XCTest
import DuckKit
@testable import StudioKit

/// Blending is arithmetic and the file is always valid, so what these tests
/// guard is the honesty: that the app never presents "it loaded" as "it works".
final class PolicyBlendTests: XCTestCase {

    private typealias P = (mean: [Float], std: [Float], layers: [DuckPolicyWriter.Layer])

    private func policy(_ fill: Float) -> P {
        let widths = DuckPolicy.expectedWidths
        return (mean: [Float](repeating: fill, count: DuckObservation.length),
                std: [Float](repeating: 1, count: DuckObservation.length),
                layers: widths.map { w in
                    DuckPolicyWriter.Layer(
                        weights: [Float](repeating: fill, count: w.0 * w.1),
                        biases: [Float](repeating: fill, count: w.1),
                        inputs: w.0, outputs: w.1)
                })
    }

    func testAHalfAndHalfBlendIsTheAverageAndStillLoads() throws {
        let data = try PolicyBlend.mix([(policy(1), 0.5), (policy(3), 0.5)])
        let loaded = try DuckPolicy.load(from: data)
        XCTAssertEqual(loaded.parameters.layers[0].weights.first, 2)
        XCTAssertEqual(loaded.parameters.mean.first, 2)
    }

    func testAnUnevenBlendWeightsTheParts() throws {
        let data = try PolicyBlend.mix([(policy(0), 0.25), (policy(4), 0.75)])
        XCTAssertEqual(try DuckPolicy.load(from: data).parameters.layers[0].biases.first, 3)
    }

    // MARK: - the refusals

    func testOnePolicyIsNotABlend() {
        XCTAssertThrowsError(try PolicyBlend.mix([(policy(1), 1.0)])) {
            XCTAssertEqual($0 as? PolicyBlend.Refusal, .needsTwo)
        }
    }

    /// A MIXTURE WHOSE PARTS DO NOT MAKE A WHOLE IS NOT AN AVERAGE. Shares of
    /// 0.5 and 0.9 would scale every weight by 1.4, which is not a blend of two
    /// networks — it is a differently-scaled network, and nothing has measured
    /// what that does.
    func testSharesThatDoNotSumToOneAreRefused() {
        XCTAssertThrowsError(try PolicyBlend.mix([(policy(1), 0.5), (policy(2), 0.9)])) {
            guard case .sharesDoNotSum(let total)? = $0 as? PolicyBlend.Refusal else {
                return XCTFail("wrong refusal")
            }
            XCTAssertEqual(total, 1.4, accuracy: 1e-9)
            XCTAssertTrue(($0 as! PolicyBlend.Refusal).message.contains("1.400"))
        }
    }

    // MARK: - what it says about itself

    /// THE PRIOR IS STATED BEFORE THE MINUTE IS SPENT, or the first failure
    /// reads as a bug in the app rather than the expected outcome it is.
    func testItWarnsBeforeRunningThatItProbablyWillNotWork() {
        let s = PolicyBlend.beforeYouRunIt
        XCTAssertTrue(s.contains("the honest expectation is that it will not"), s)
        XCTAssertTrue(s.contains("share an ancestor"), s)
        XCTAssertTrue(s.contains("Run it on a bench and find out"), s)
    }

    /// LOADING IS NOT WORKING, and the sentence for an unmeasured blend says
    /// exactly that, because "it loaded" is the free claim and the tempting one.
    func testAnUnrunBlendSaysLoadingProvesNothing() {
        XCTAssertEqual(PolicyBlend.notYetMeasured,
                       "This blend has not been run. It loads, which says nothing about whether "
                     + "it works.")
    }

    /// A rate always travels with its criterion, because "8 of 16" alone is the
    /// shape of every misleading benchmark.
    func testAMeasuredBlendQuotesItsCriterionAndItsPlant() {
        let s = PolicyBlend.measured(.init(
            achieves: 0, rollouts: 16, criterion: "ends standing, trunk at least 100 mm up",
            travelled: 0.176, liveliestIngredientTravelled: 1.207,
            plant: "On scene.mjb, sha256 3f8c9ab9b409."))
        XCTAssertTrue(s.hasPrefix("0 of 16 — ends standing, trunk at least 100 mm up."), s)
        XCTAssertTrue(s.contains("scene.mjb"), s)
        XCTAssertTrue(s.contains("the usual outcome and not a fault in the blend"), s)
    }

    /// THE ROW THAT NEARLY SHIPPED AS A SUCCESS, and the reason `Behaviour`
    /// carries a distance at all.
    ///
    /// These are the real numbers off the duckbench: `alpha_walking` averaged
    /// 75/25 with `alpha_stand`, commanded forward at vx = 0.5, ends
    /// upright in all 16 rollouts — a perfect score against "ends standing,
    /// trunk at least 100 mm up" — while travelling two millimetres where the
    /// walking policy it was made from covers 1.207 m. It did not keep the
    /// walk; it became the standing policy, and standing passes an uprightness
    /// test trivially. The earlier version of `measured` called this "a
    /// genuinely surprising result worth keeping".
    func testABlendThatStoodStillIsNotCalledASuccess() {
        let s = PolicyBlend.measured(.init(
            achieves: 16, rollouts: 16, criterion: "ends standing, trunk at least 100 mm up",
            travelled: 0.002, liveliestIngredientTravelled: 1.207, plant: "On scene.mjb."))
        XCTAssertTrue(s.contains("stopped doing the thing"), s)
        XCTAssertTrue(s.contains("The blend did not keep the behaviour"), s)
        XCTAssertFalse(s.contains("genuinely surprising"),
                       "a blend that travels 2 mm is not a surprising success")
        XCTAssertFalse(s.contains("mostly works"), s)
        XCTAssertTrue(s.contains("2 mm"), "the distance is shown, not just alluded to: \(s)")
        XCTAssertTrue(s.contains("1.21 m"), s)
    }

    /// And a blend that really did keep the behaviour still gets its due — the
    /// guard must not swallow the good case.
    func testABlendThatKeptTheBehaviourIsStillCalledSurprising() {
        let s = PolicyBlend.measured(.init(
            achieves: 14, rollouts: 16, criterion: "c", travelled: 1.1,
            liveliestIngredientTravelled: 1.207, plant: "p"))
        XCTAssertTrue(s.contains("genuinely surprising"), s)
    }

    /// WHEN NOTHING IN THE MIXTURE TRAVELS, distance carries no information and
    /// the sentence must not pretend otherwise. Two standing policies averaged
    /// give a standing policy, and calling that "stopped doing the thing" would
    /// be its own false claim.
    func testTravelIsIgnoredWhenTheIngredientsNeverTravelled() {
        let s = PolicyBlend.measured(.init(
            achieves: 16, rollouts: 16, criterion: "c", travelled: 0.001,
            liveliestIngredientTravelled: 0.001, plant: "p"))
        XCTAssertFalse(s.contains("stopped doing the thing"), s)
        XCTAssertFalse(s.contains("travelled"), "no yardstick, no distance claim: \(s)")
        XCTAssertTrue(s.contains("genuinely surprising"), s)
    }

    /// A blend that fell over is reported as falling, not as going inert —
    /// they are different failures and the fix for each is different.
    func testFallingIsNotReportedAsGoingInert() {
        let s = PolicyBlend.measured(.init(
            achieves: 2, rollouts: 16, criterion: "c", travelled: 0.176,
            liveliestIngredientTravelled: 1.207, plant: "p"))
        XCTAssertFalse(s.contains("stopped doing the thing"), s)
        XCTAssertTrue(s.contains("sometimes works"), s)
    }

    /// FINGERPRINTS, NOT FILENAMES. Anybody can call a file alpha_walking.onnx;
    /// a blend whose ingredients cannot be named exactly is an anecdote.
    func testTheRecipeNamesEachNetworkByDigest() {
        let r = PolicyBlend.recipe([
            .init(name: "alpha_walking.onnx", fingerprint: "abc123def456789", share: 0.7),
            .init(name: "alpha_stand.onnx", fingerprint: nil, share: 0.3),
        ])
        XCTAssertTrue(r.contains("70% alpha_walking.onnx (abc123def456)"), r)
        XCTAssertTrue(r.contains("no digest, so which network this was cannot be checked"), r)
    }
}
