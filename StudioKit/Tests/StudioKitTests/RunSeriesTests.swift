import XCTest
import DuckKit
@testable import StudioKit

final class RunSeriesTests: XCTestCase {

    private func clip(_ name: String) throws -> DuckIntentClip {
        try XCTUnwrap(try DuckIntentClip.bundled()[name])
    }

    func testEveryTrackHasOnePointPerTick() throws {
        let c = try clip("kick_left")
        for track in RunSeries(clip: c).tracks {
            XCTAssertEqual(track.points.count, c.frames.count, track.name)
            // Strictly increasing in time, or a chart draws a loop.
            for i in 1..<track.points.count {
                XCTAssertGreaterThan(track.points[i].time, track.points[i - 1].time, track.name)
            }
        }
    }

    /// The whole point: a summary says how far it tilted, the curve says when.
    /// Roulade goes past 90° in the MIDDLE and comes back; a fall would not.
    func testRouladeTiltsPastVerticalAndReturns() throws {
        let series = RunSeries(clip: try clip("roulade"))
        let tilt = try XCTUnwrap(series.tracks.first { $0.name == "Tilt" })
        let peak = tilt.points.max { $0.value < $1.value }!
        XCTAssertGreaterThan(peak.value, 90, "a forward roll goes over")
        XCTAssertLessThan(tilt.points.last!.value, 30, "and comes back upright")
        XCTAssertGreaterThan(peak.time, 0.2, "the peak is not at the very start")
        XCTAssertLessThan(peak.time, tilt.points.last!.time - 0.2, "nor at the very end")
    }

    /// Sit ends below the standing reference line, and the line is the thing
    /// that makes the curve readable.
    func testSittingFinishesBelowTheStandingLine() throws {
        let series = RunSeries(clip: try clip("sit"))
        let height = try XCTUnwrap(series.tracks.first { $0.name == "Trunk height" })
        let reference = try XCTUnwrap(height.reference)
        XCTAssertEqual(reference.value, DuckStance.standingHeight * 1000, accuracy: 1e-9)
        XCTAssertLessThan(height.points.last!.value, reference.value - 40,
                          "sitting ends a long way under standing")
    }

    /// A format-3 clip gets the two curves that only exist because the network's
    /// own output was recorded.
    func testTheActionCurvesAppearOnlyWhenTheActionsWereRecorded() throws {
        let recorded = RunSeries(clip: try clip("hold"))
        XCTAssertTrue(recorded.tracks.contains { $0.name == "Action rate" })
        XCTAssertTrue(recorded.tracks.contains { $0.name == "Turn rate" })

        let c = try clip("hold")
        let stripped = DuckIntentClip(
            name: c.name, hz: c.hz, frames: c.frames, roots: c.roots,
            netYaw: c.netYaw, loops: c.loops, startsFrom: c.startsFrom,
            endsIn: c.endsIn, policy: c.policy, authored: c.authored,
            environment: c.environment, credit: nil, telemetry: .none)
        let bare = RunSeries(clip: stripped)
        // FEWER TRACKS, never flat lines at zero — a chart of zeros would read
        // as a policy that emitted nothing.
        XCTAssertFalse(bare.tracks.contains { $0.name == "Action rate" })
        XCTAssertEqual(bare.tracks.count, 3)
    }

    /// A flat curve still needs a band, or the chart collapses onto a line.
    func testAFlatTrackStillHasARange() throws {
        let series = RunSeries(clip: try clip("hold"))
        for track in series.tracks {
            XCTAssertGreaterThan(track.range.upperBound - track.range.lowerBound, 1e-6,
                                 track.name)
        }
    }

    func testTheReadoutFindsTheNearestTick() throws {
        let c = try clip("kick_left")
        let series = RunSeries(clip: c)
        let readings = series.readings(at: 0.5)
        XCTAssertEqual(readings.count, series.tracks.count)
        XCTAssertTrue(readings.contains { $0.label == "Trunk height" })
        XCTAssertFalse(readings.contains { $0.value == "—" })
    }
}

// MARK: - which servos are moving, and which way

extension RunSeriesTests {

    func testEveryPolicyJointReportsAtEveryMoment() throws {
        let c = try clip("kick_left")
        for time in [0.0, 0.4, c.duration] {
            let joints = RunSeries.joints(of: c, at: time)
            XCTAssertEqual(joints.count, DuckModel.policyJointCount)
            XCTAssertFalse(joints.contains { $0.name == "mouth" })
        }
    }

    /// The sign IS the answer. Sitting down flexes the knees one way; the
    /// velocity during the descent must carry that sign, not just a magnitude.
    func testSittingKneesMoveWithASignDuringTheDescent() throws {
        let c = try clip("sit")
        // Mid-descent: the trunk is between standing and seated.
        let mid = c.roots.firstIndex { $0.z < 0.100 && $0.z > 0.070 }
        let time = Double(mid ?? c.frames.count / 3) / c.hz
        let joints = RunSeries.joints(of: c, at: time)
        let left = try XCTUnwrap(joints.first { $0.name == "left_knee" })
        let right = try XCTUnwrap(joints.first { $0.name == "right_knee" })
        XCTAssertTrue(left.isMoving || right.isMoving, "the knees drive the descent")
        // The knees are antisymmetric at home and flex in opposite signed
        // directions — the same physical bend.
        if left.isMoving && right.isMoving {
            XCTAssertLessThan(left.velocity * right.velocity, 0,
                              "antisymmetric joints flex with opposite signs")
        }
    }

    /// Holding still means holding still: no joint should read as moving.
    func testHoldingStillReadsAsStill() throws {
        let joints = RunSeries.joints(of: try clip("hold"), at: 1.0)
        XCTAssertTrue(joints.allSatisfy { !$0.isMoving },
                      "moving joints in hold: \(joints.filter(\.isMoving).map(\.name))")
    }

    /// The velocity agrees with the positions it was differenced from.
    func testVelocityMatchesTheFiniteDifference() throws {
        let c = try clip("roulade")
        let tick = 40
        let joints = RunSeries.joints(of: c, at: Double(tick) / c.hz)
        let expected = (c.frames[tick + 1][0] - c.frames[tick - 1][0]) * c.hz / 2
        XCTAssertEqual(joints[0].velocity, expected, accuracy: 1e-9)
    }

    /// The ends do not index off the clip.
    func testTheEndsUseOneSidedDifferences() throws {
        let c = try clip("kick_left")
        XCTAssertNoThrow(_ = RunSeries.joints(of: c, at: -1))
        XCTAssertNoThrow(_ = RunSeries.joints(of: c, at: c.duration + 5))
        let atEnd = RunSeries.joints(of: c, at: c.duration + 5)
        XCTAssertEqual(atEnd.count, DuckModel.policyJointCount)
    }
}
