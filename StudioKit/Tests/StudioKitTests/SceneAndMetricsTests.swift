import XCTest
import DuckKit
@testable import StudioKit

final class DuckSceneTests: XCTestCase {

    func testTheStaircaseGeneratorDefaultsToWhatTheRobotCanActuallyClimb() {
        let scene = DuckScene.staircase()
        XCTAssertEqual(scene.steps.count, 4)
        XCTAssertTrue(scene.problems.isEmpty,
                      "the default flight must not warn about itself: \(scene.problems)")
        XCTAssertEqual(scene.steps[0].top, DuckScene.measuredStepCeiling, accuracy: 1e-9)
    }

    /// The number this editor exists to put in front of somebody.
    func testAStaircaseTallerThanTheMeasuredCeilingSaysSo() {
        let scene = DuckScene.staircase(count: 3, rise: 0.04)
        let unreachable = scene.problems.filter { $0.severity == .unreachable }
        XCTAssertEqual(unreachable.count, 3, "every riser is over the ceiling")
        XCTAssertTrue(unreachable[0].text.contains("40 mm"))
        XCTAssertTrue(unreachable[0].text.contains("10 mm"))
    }

    /// A flight is judged riser by riser, not by absolute height — ten 10 mm
    /// steps reach 100 mm and are climbable; one 100 mm block is not.
    func testAFlightIsJudgedByRiseNotByTotalHeight() {
        let tall = DuckScene.staircase(count: 10, rise: 0.010)
        XCTAssertEqual(tall.steps.last?.top ?? 0, 0.10, accuracy: 1e-9)
        XCTAssertTrue(tall.problems.isEmpty)

        let block = DuckScene(name: "b", steps: [
            .init(x: 0.4, y: 0, top: 0.10, halfHeight: 0.10)
        ])
        XCTAssertEqual(block.problems.filter { $0.severity == .unreachable }.count, 1)
    }

    func testAFloatingStepIsBroken() {
        let scene = DuckScene(name: "f", steps: [
            .init(x: 0.4, y: 0, top: 0.30, halfHeight: 0.02)
        ])
        XCTAssertTrue(scene.problems.contains { $0.severity == .broken
                                             && $0.text.contains("floats") })
    }

    func testAWallThroughTheStartIsBroken() {
        let scene = DuckScene(name: "w", walls: [.init(x: 0, y: 0)])
        XCTAssertTrue(scene.problems.contains { $0.text.contains("where the robot starts") })
    }

    /// A scene lifted off a recording round-trips, so "play this clip somewhere
    /// else" starts from the world it was actually recorded in.
    func testASceneLiftedFromARecordingKeepsItsProps() throws {
        let clips = try DuckIntentClip.bundled()
        let withProps = try XCTUnwrap(clips.values.first { $0.environment.hasProps })
        let scene = DuckScene(name: withProps.name, recorded: withProps.environment)
        XCTAssertEqual(scene.steps.count, withProps.environment.steps.count)
        XCTAssertEqual(scene.walls.count, withProps.environment.walls.count)
        XCTAssertEqual(scene.environment.steps.first?.top,
                       withProps.environment.steps.first?.top)
        XCTAssertTrue(scene.provenance.contains("Lifted"))
    }

    func testAScenePersistsThroughJSON() throws {
        let scene = DuckScene.staircase(count: 3)
        let back = try JSONDecoder().decode(
            DuckScene.self, from: JSONEncoder().encode(scene))
        XCTAssertEqual(back, scene)
    }
}

final class RunMetricsTests: XCTestCase {

    private func clip(_ name: String) throws -> DuckIntentClip {
        try XCTUnwrap(try DuckIntentClip.bundled()[name])
    }

    /// Upright is 1 when the trunk is level and collapses as it goes over.
    func testUprightIsOneWhenLevelAndZeroOnItsSide() {
        XCTAssertEqual(RunMetrics.gravityXYSquared((1, 0, 0, 0)), 0, accuracy: 1e-12)
        // A quarter turn about x: the trunk is on its side, and gravity is
        // entirely horizontal in its frame.
        let h = (2.0).squareRoot() / 2
        XCTAssertEqual(RunMetrics.gravityXYSquared((h, h, 0, 0)), 1, accuracy: 1e-9)
    }

    func testTiltIsZeroUprightAndPiInverted() {
        XCTAssertEqual(RunMetrics.tilt((1, 0, 0, 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(RunMetrics.tilt((0, 1, 0, 0)), .pi, accuracy: 1e-9)
    }

    /// The headspin is the corpus's hard case: it ends balanced on its head, so
    /// a tilt measure that worked only for a duck standing up would call it
    /// level.
    func testTheHeadspinReportsALargeTilt() throws {
        let metrics = RunMetrics(clip: try clip("headspin"))
        let peak = try XCTUnwrap(metrics.attitude.first { $0.label == "Peak tilt" })
        let degrees = Double(peak.value.replacingOccurrences(of: "°", with: "")) ?? 0
        XCTAssertGreaterThan(degrees, 90, "it is upside down at some point")
    }

    /// A clip recorded from a policy whose training config this build cannot
    /// name gets measurements and NO reward. A wrong weight table is worse than
    /// none, because every number on the panel inherits its authority.
    func testAnUnknownTaskScoresNoReward() throws {
        let metrics = RunMetrics(clip: try clip("headspin"))
        XCTAssertNil(metrics.task, "headspin.onnx is somebody else's policy")
        XCTAssertTrue(metrics.rewards.isEmpty)
        XCTAssertFalse(metrics.travel.isEmpty, "the measurements still stand")
        XCTAssertTrue(metrics.provenance.contains("not one this build can name"))
    }

    func testAKnownTaskNamesTheConfigItReadTheWeightsFrom() throws {
        let metrics = RunMetrics(clip: try clip("roulade"))
        XCTAssertEqual(metrics.task, .roulade)
        XCTAssertTrue(metrics.provenance.contains("microduck_roulade_env_cfg.py"))
        let angular = try XCTUnwrap(metrics.rewards.first { $0.name == "body_ang_vel" })
        // Roulade's own weight, not the velocity config's −0.05.
        XCTAssertEqual(angular.weight, -0.002, accuracy: 1e-12)
        XCTAssertTrue(angular.purpose.contains("the point"))
    }

    /// Roulade replaces `upright` with its own after-the-roll variant, so the
    /// shared term must not be claimed for it.
    func testRouladeDoesNotClaimTheSharedUprightTerm() throws {
        let metrics = RunMetrics(clip: try clip("roulade"))
        XCTAssertFalse(metrics.rewards.contains { $0.name == "upright" })
    }

    func testTheKickScoresUprightAtTheKickConfigsWeight() throws {
        let metrics = RunMetrics(clip: try clip("kick_left"))
        XCTAssertEqual(metrics.task, .ballKick)
        let upright = try XCTUnwrap(metrics.rewards.first { $0.name == "upright" })
        XCTAssertEqual(upright.weight, 2.0, accuracy: 1e-12)
        guard case .evaluated(let mean, let weighted) = upright.standing else {
            return XCTFail("the kick stays upright, so this is evaluable")
        }
        XCTAssertGreaterThan(mean, 0.5, "a kick that stays on its feet scores well")
        XCTAssertEqual(weighted, mean * 2.0, accuracy: 1e-12)
    }

    /// Every clip in the bundle is format 3, so nothing should be reporting a
    /// missing action stream.
    func testTheBundledCorpusHasTheActionsTheRewardTermsNeed() throws {
        for (name, c) in try DuckIntentClip.bundled() {
            let metrics = RunMetrics(clip: c)
            XCTAssertFalse(metrics.telemetryMissing, name)
            XCTAssertTrue(metrics.control.contains { $0.label == "Action rate" }, name)
        }
    }

    /// The ball-kick config carries terms that read the ball and the contact
    /// sensor. Those are named, not silently dropped.
    func testTermsARecordingCannotAnswerAreListedWithTheReason() throws {
        let metrics = RunMetrics(clip: try clip("kick_left"))
        XCTAssertTrue(metrics.unevaluated.contains { $0.label == "ball_forward_velocity" })
        let contact = try XCTUnwrap(metrics.unevaluated.first { $0.label == "self_collisions" })
        XCTAssertEqual(contact.detail, "reads a collision sensor")
    }

    /// Sit and stand were recorded from a config that DELETES `fell_over`, and
    /// the panel says so where it matters rather than in a footnote.
    func testSittingIsMeasuredAsSeatedRatherThanAsAFall() throws {
        let metrics = RunMetrics(clip: try clip("sit"))
        let posture = try XCTUnwrap(metrics.attitude.first { $0.label == "Starts / ends" })
        XCTAssertTrue(posture.value.contains("seated"), posture.value)
    }
}

final class DuckStanceTests: XCTestCase {

    /// The standing height is the one the recorder actually settles at — not a
    /// round number that would bury the feet.
    func testHomeStandsAtTheHeightTheStandingClipSettlesAt() throws {
        let hold = try XCTUnwrap(try DuckIntentClip.bundled()["hold"])
        let settled = hold.roots.suffix(20).map(\.z).reduce(0, +) / 20
        XCTAssertEqual(DuckStance.standingHeight, settled, accuracy: 0.002,
                       "the home height must match what the standing policy does")
        XCTAssertEqual(DuckStance.home.root.z, DuckStance.standingHeight)
        XCTAssertEqual(DuckStance.home.jointAngles.count, DuckModel.jointCount)
    }

    /// Standing on a step means the trunk clears the step's top, not the floor.
    func testStandingOnAStepAddsTheStepsHeight() {
        let step = DuckScene.Step(x: 0.5, y: 0.1, top: 0.04)
        let stance = DuckStance.onTop(of: step)
        XCTAssertEqual(stance.root.z, 0.04 + DuckStance.standingHeight, accuracy: 1e-12)
        XCTAssertEqual(stance.root.x, 0.5)
        XCTAssertEqual(stance.root.y, 0.1)
    }
}
