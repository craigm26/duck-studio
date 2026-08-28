import XCTest
import DuckKit
@testable import StudioKit

/// The slot table is a claim about what Pollen trained against, so these check
/// it against the one source in this project that also knows: DuckKit.
final class ObservationSlotTests: XCTestCase {

    func testSixtyOneSlotsInOrder() {
        XCTAssertEqual(ObservationSlot.all.count, DuckObservation.length)
        XCTAssertEqual(ObservationSlot.all.map(\.index), Array(0..<61),
                       "indices must be dense and in order — the table is read positionally")
    }

    /// The block widths ARE the observation layout. If these drift, the table
    /// is describing a different network from the one DuckKit runs.
    func testBlockWidthsMatchTheObservationContract() {
        let widths = Dictionary(grouping: ObservationSlot.all, by: \.block)
            .mapValues(\.count)
        XCTAssertEqual(widths[.angularVelocity], 3)
        XCTAssertEqual(widths[.projectedGravity], 3)
        XCTAssertEqual(widths[.jointPosition], DuckModel.policyJointCount)
        XCTAssertEqual(widths[.jointVelocity], DuckModel.policyJointCount)
        XCTAssertEqual(widths[.lastAction], DuckModel.policyJointCount)
        let command = (widths[.twist] ?? 0) + (widths[.headCommand] ?? 0) + (widths[.bodyCommand] ?? 0)
        XCTAssertEqual(command, DuckObservation.commandLength, "the command block is 13 wide")
    }

    /// Blocks must be contiguous. A joint position appearing among the
    /// velocities would make every offset after it wrong while the count
    /// still added up.
    func testBlocksAreContiguous() {
        var seen: [ObservationSlot.Block] = []
        for slot in ObservationSlot.all where seen.last != slot.block {
            XCTAssertFalse(seen.contains(slot.block),
                           "\(slot.block) appears in two runs — the table is interleaved")
            seen.append(slot.block)
        }
        XCTAssertEqual(seen.first, .angularVelocity)
        XCTAssertEqual(seen.last, .bodyCommand)
    }

    /// Joint slots must line up with the robot's own joints, in the policy's
    /// order — which skips the mouth.
    func testJointSlotsNameTheRightJoints() {
        let positions = ObservationSlot.slots(in: .jointPosition)
        for (slot, position) in positions.enumerated() {
            let joint = DuckModel.jointNames[DuckModel.jointOfPolicySlot(slot)]
            let readable = joint.replacingOccurrences(of: "_", with: " ")
            XCTAssertTrue(position.label.contains(readable),
                          "slot \(position.index) says \"\(position.label)\", expected \(readable)")
        }
        XCTAssertFalse(positions.contains { $0.label.contains("mouth") },
                       "the mouth is outside every policy's action space")
    }

    /// Units must be the ones the quantity actually has — a joint position in
    /// m/s would make a z-score meaningless in a way no test of counts catches.
    func testUnitsMatchTheirBlocks() {
        for slot in ObservationSlot.all {
            switch slot.block {
            case .angularVelocity: XCTAssertEqual(slot.unit, .radiansPerSecond, slot.label)
            case .projectedGravity: XCTAssertEqual(slot.unit, .dimensionless, slot.label)
            case .jointPosition: XCTAssertEqual(slot.unit, .radians, slot.label)
            case .jointVelocity: XCTAssertEqual(slot.unit, .radiansPerSecond, slot.label)
            case .lastAction: XCTAssertEqual(slot.unit, .dimensionless, slot.label)
            default: break
            }
        }
    }

    func testEveryBoundIsAnActualInterval() {
        for slot in ObservationSlot.all {
            XCTAssertLessThanOrEqual(slot.lower, slot.upper, "slot \(slot.index) \(slot.label)")
        }
    }

    /// The three slots DuckKit never emits. Anything that normalises or ranks
    /// has to skip them: their variance is zero, so a z-score is a division by
    /// zero and a sensitivity column is meaningless.
    func testTheConstantSlotsAreIdentified() {
        let constant = ObservationSlot.constantSlots.map(\.index)
        XCTAssertEqual(constant, [55, 56, 60], "body x, body y and body yaw")
        for slot in ObservationSlot.constantSlots {
            XCTAssertEqual(slot.lower, 0)
            XCTAssertEqual(slot.upper, 0)
            XCTAssertEqual(slot.block, .bodyCommand)
        }
    }

    /// Joint position bounds are relative to the home pose, so each must be
    /// reachable: the joint's own travel, offset by where home sits in it.
    func testJointPositionBoundsAreReachable() {
        for (slot, entry) in ObservationSlot.slots(in: .jointPosition).enumerated() {
            let joint = DuckModel.jointOfPolicySlot(slot)
            let range = DuckModel.jointRanges[joint]
            let home = DuckModel.homePose[joint]
            // The table carries four decimal places, so a bound sitting exactly
            // on a travel limit lands up to 5e-5 outside it. That is rounding,
            // not a joint being asked for more than it has.
            let reach = 5e-5
            XCTAssertGreaterThanOrEqual(entry.lower, range.lower - home - reach,
                                        "\(entry.label) can go below its own travel")
            XCTAssertLessThanOrEqual(entry.upper, range.upper - home + reach,
                                     "\(entry.label) can go above its own travel")
        }
    }
}
