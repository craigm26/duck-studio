import Foundation
import DuckKit

/// How far out of distribution each of the 61 inputs is.
///
/// THE ONLY SCALE ON WHICH THESE NUMBERS ARE COMPARABLE. Slot 27 is a joint
/// velocity in rad/s and slot 5 is a gravity component with no unit at all;
/// side by side they say nothing. `(value − mean) / std`, against the
/// statistics baked into the policy itself, is what makes "4.2 training
/// standard deviations out on slot 27" the most useful sentence a policy
/// debugger can say.
///
/// The statistics are the network's own — `DuckPolicy.normalization` reads the
/// mean and std the training run accumulated and every inference divides by.
/// Nothing here estimates them.
public struct ZScoreStrip: Equatable, Sendable {

    public struct Reading: Equatable, Sendable, Identifiable {
        public let slot: ObservationSlot
        public let value: Float
        public let mean: Float
        public let standardDeviation: Float
        /// How many training standard deviations from the mean.
        public let z: Float
        public var id: Int { slot.index }

        /// Past three sigma. Not an error — the robot genuinely goes there —
        /// but the first place to look when a policy behaves oddly.
        public var isOutlier: Bool { abs(z) > 3 }
        /// The value cannot be varied through this app's own observations, so
        /// its z-score is a fact about the constant it is pinned to.
        public var isNeverEmitted: Bool { slot.isNeverEmitted }
    }

    public let readings: [Reading]

    public init(observation: DuckObservation, policy: DuckPolicy) {
        let (mean, std) = policy.normalization
        let values = observation.values
        readings = ObservationSlot.all.map { slot in
            let m = slot.index < mean.count ? mean[slot.index] : 0
            let s = slot.index < std.count ? std[slot.index] : 1
            let v = slot.index < values.count ? values[slot.index] : 0
            // A zero std would be a division by zero. The shipped policies have
            // none — the smallest is 0.0129 — but a policy somebody else
            // trained on a fixed command could, and the honest answer there is
            // "no spread to measure", not infinity.
            let z: Float = s > 0 ? (v - m) / s : 0
            return Reading(slot: slot, value: v, mean: m, standardDeviation: s, z: z)
        }
    }

    /// The readings furthest out of distribution, worst first. What a debugger
    /// actually opens the screen for.
    public func mostUnusual(limit: Int = 5) -> [Reading] {
        readings.filter { $0.standardDeviation > 0 }
            .sorted { abs($0.z) > abs($1.z) }
            .prefix(limit).map { $0 }
    }

    public var outliers: [Reading] { readings.filter(\.isOutlier) }

    /// One sentence for the top of the screen.
    public var summary: String {
        let count = outliers.count
        guard count > 0 else { return "Every input is within three standard deviations of training." }
        let worst = mostUnusual(limit: 1).first!
        return "\(count) input\(count == 1 ? "" : "s") outside three sigma. "
             + "Furthest: \(worst.slot.label) at \(String(format: "%+.1f", worst.z))σ."
    }
}
