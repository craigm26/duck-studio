import Foundation
import DuckKit

/// Which inputs this policy actually listens to.
///
/// `DuckPolicy.jacobian` gives the exact 14×61 matrix of ∂action/∂normalized
/// input by reverse mode — not finite differences, which is the part that
/// matters. Choosing an ε across slots whose units span rad, rad/s and nothing
/// at all is exactly the kind of decision that produces a plausible-looking
/// wrong answer, and this has no ε to choose.
///
/// THE JACOBIAN IS AGAINST THE NORMALIZED INPUT, so its columns are already
/// comparable — a unit step in column j is one training standard deviation of
/// slot j, which is the only common currency these inputs have.
public struct Sensitivity: Equatable, Sendable {

    public struct Column: Equatable, Sendable, Identifiable {
        public let slot: ObservationSlot
        /// Euclidean norm of this input's effect across all 14 actions.
        public let norm: Float
        /// The action this input moves most, and by how much.
        public let strongestJoint: String
        public let strongestMagnitude: Float
        public var id: Int { slot.index }
    }

    public let columns: [Column]

    public init(jacobian: [[Float]]) {
        precondition(jacobian.count == DuckModel.policyJointCount,
                     "a row per action")
        var built: [Column] = []
        built.reserveCapacity(DuckObservation.length)
        for index in 0..<DuckObservation.length {
            var sum: Float = 0
            var best: Float = 0
            var bestRow = 0
            for row in 0..<jacobian.count {
                let value = index < jacobian[row].count ? jacobian[row][index] : 0
                sum += value * value
                if abs(value) > abs(best) { best = value; bestRow = row }
            }
            built.append(Column(
                slot: ObservationSlot.all[index],
                norm: sum.squareRoot(),
                strongestJoint: DuckModel.jointNames[DuckModel.jointOfPolicySlot(bestRow)],
                strongestMagnitude: best))
        }
        columns = built
    }

    public init(policy: DuckPolicy, observation: DuckObservation) {
        self.init(jacobian: policy.jacobian(at: observation))
    }

    /// Inputs ranked by how much they move the output, most first.
    ///
    /// Slots this app never varies are excluded rather than ranked. Their
    /// column is real — the network would respond if the value moved — but
    /// listing one near the top invites someone to go looking for a slider
    /// that does not exist.
    public func ranked(limit: Int = 10, includeNeverEmitted: Bool = false) -> [Column] {
        columns
            .filter { includeNeverEmitted || !$0.slot.isNeverEmitted }
            .sorted { $0.norm > $1.norm }
            .prefix(limit).map { $0 }
    }

    /// Inputs this policy is, to numerical precision, not using at all.
    ///
    /// A genuinely useful finding: a policy trained without a command block, or
    /// one that learned to ignore a sensor, shows up here rather than as a
    /// mystery in behaviour.
    public func ignored(threshold: Float = 1e-4) -> [Column] {
        columns.filter { $0.norm < threshold }
    }

    /// The largest column norm, for scaling a bar chart against something
    /// stable rather than against whichever value happens to be biggest.
    public var peak: Float { columns.map(\.norm).max() ?? 1 }
}
