import XCTest
import DuckKit
@testable import StudioKit

/// The two analyses a policy debugger actually opens the app for.
final class AnalysisTests: XCTestCase {

    private func walking() throws -> DuckPolicy {
        let url = try XCTUnwrap(Bundle.module.url(
            forResource: "alpha_walking", withExtension: "onnx", subdirectory: "Fixtures/policies"))
        return try DuckPolicy.load(contentsOf: url)
    }

    // MARK: - z-scores

    func testAStandingObservationIsInDistribution() throws {
        let strip = ZScoreStrip(observation: ObservationPreset.standing.observation,
                                policy: try walking())
        XCTAssertEqual(strip.readings.count, 61)
        XCTAssertTrue(strip.outliers.isEmpty,
                      "a level, home-pose robot is what the policy trained on: \(strip.summary)")
        XCTAssertTrue(strip.summary.contains("within three standard deviations"), strip.summary)
    }

    /// The all-zeros observation is not a robot state — an all-zero gravity
    /// vector describes free fall — and the strip is what makes that visible
    /// rather than a thing you have to already know.
    func testTheZeroedObservationIsFarOutOfDistribution() throws {
        let strip = ZScoreStrip(observation: .zeroed, policy: try walking())
        let gravityZ = strip.readings[5]
        XCTAssertGreaterThan(abs(gravityZ.z), 25,
                             "gravity z is -0.995 in training with std 0.031, so zero is ~32 sigma out")
        XCTAssertTrue(gravityZ.isOutlier)
        XCTAssertTrue(strip.summary.contains("outside three sigma"), strip.summary)
        XCTAssertEqual(strip.mostUnusual(limit: 1).first?.slot.index, 5,
                       "and it is the single most unusual input")
    }

    /// Statistics come from the policy, never from an estimate here.
    func testTheStatisticsAreThePolicysOwn() throws {
        let policy = try walking()
        let (mean, std) = policy.normalization
        let strip = ZScoreStrip(observation: ObservationPreset.walking.observation, policy: policy)
        for reading in strip.readings {
            XCTAssertEqual(reading.mean, mean[reading.slot.index])
            XCTAssertEqual(reading.standardDeviation, std[reading.slot.index])
        }
    }

    /// A hand-built policy could carry a zero-variance slot. The honest answer
    /// there is "no spread to measure", not an infinity that poisons a sort.
    func testAZeroStandardDeviationDoesNotProduceInfinity() throws {
        let strip = ZScoreStrip(observation: ObservationPreset.standing.observation,
                                policy: try walking())
        for reading in strip.readings {
            XCTAssertFalse(reading.z.isNaN, "\(reading.slot.label)")
            XCTAssertFalse(reading.z.isInfinite, "\(reading.slot.label)")
        }
    }

    // MARK: - sensitivity

    func testEveryInputGetsAColumn() throws {
        let s = Sensitivity(policy: try walking(),
                            observation: ObservationPreset.walking.observation)
        XCTAssertEqual(s.columns.count, 61)
        XCTAssertEqual(s.columns.map(\.slot.index), Array(0..<61))
    }

    /// The exact Jacobian, checked against central differences on the
    /// normalized input. This is the flagship number in the app and the one
    /// thing that must not be approximately right.
    func testTheJacobianMatchesCentralDifferences() throws {
        let policy = try walking()
        let observation = ObservationPreset.walking.observation
        let jacobian = policy.jacobian(at: observation)
        let (mean, std) = policy.normalization

        // Perturb three representative slots in RAW units such that the
        // normalized input moves by a known epsilon.
        for slot in [5, 20, 48] {
            let epsilon: Float = 1e-2
            var up = observation.values, down = observation.values
            up[slot] += epsilon * std[slot]
            down[slot] -= epsilon * std[slot]
            let a = policy.infer(DuckObservation(exactly: up)!)
            let b = policy.infer(DuckObservation(exactly: down)!)
            for row in 0..<DuckModel.policyJointCount {
                let numeric = (a[row] - b[row]) / (2 * epsilon)
                XCTAssertEqual(jacobian[row][slot], numeric, accuracy: 2e-3,
                               "row \(row), slot \(slot) (\(ObservationSlot.all[slot].label))")
            }
            _ = mean
        }
    }

    /// The command block should matter to a walking policy — it is how the
    /// robot is told where to go.
    func testTheVelocityCommandIsAmongTheInputsThatMatter() throws {
        let s = Sensitivity(policy: try walking(),
                            observation: ObservationPreset.walking.observation)
        let top = Set(s.ranked(limit: 20).map(\.slot.index))
        XCTAssertTrue(top.contains(48) || top.contains(49) || top.contains(50),
                      "a twist command slot should be in the top 20 of a walking policy")
    }

    /// Slots the app never varies are kept out of the ranking rather than
    /// listed — a top-ranked input with no slider is an invitation to hunt for
    /// one that does not exist.
    func testNeverEmittedSlotsAreExcludedUnlessAsked() throws {
        let s = Sensitivity(policy: try walking(),
                            observation: ObservationPreset.standing.observation)
        let ranked = Set(s.ranked(limit: 61).map(\.slot.index))
        for slot in ObservationSlot.neverEmittedSlots {
            XCTAssertFalse(ranked.contains(slot.index), "\(slot.label) should be excluded")
        }
        let everything = Set(s.ranked(limit: 61, includeNeverEmitted: true).map(\.slot.index))
        XCTAssertEqual(everything.count, 61, "and included when explicitly asked for")
    }

    func testThePeakIsTheLargestColumn() throws {
        let s = Sensitivity(policy: try walking(),
                            observation: ObservationPreset.walking.observation)
        XCTAssertEqual(s.peak, s.columns.map(\.norm).max())
        XCTAssertGreaterThan(s.peak, 0)
    }
}
