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
        // The scene is deliberately called something the clip is not, because
        // conflating the two names is the defect the initializer's second
        // argument exists to prevent.
        let scene = DuckScene(name: "Somewhere else", liftedFrom: withProps.name,
                              recorded: withProps.environment)
        XCTAssertEqual(scene.steps.count, withProps.environment.steps.count)
        XCTAssertEqual(scene.walls.count, withProps.environment.walls.count)
        XCTAssertEqual(scene.environment.steps.first?.top,
                       withProps.environment.steps.first?.top)
        XCTAssertEqual(scene.provenance, "Lifted from the recording of \(withProps.name)")
    }

    /// THE SENTENCE NAMES THE RECORDING, NEVER THE SCENE. A scene can be
    /// renamed the moment after it is lifted; the recording it came off cannot,
    /// so a provenance line built from the scene's name would go on to name a
    /// recording nobody ever made.
    func testALiftedScenesProvenanceNamesTheRecordingAndNotTheScene() {
        let scene = DuckScene(name: "Back porch", liftedFrom: "step_up_0003",
                              recorded: .bareFloor)
        XCTAssertEqual(scene.provenance, "Lifted from the recording of step_up_0003")
        XCTAssertFalse(scene.provenance.contains("Back porch"))
        XCTAssertEqual(scene.name, "Back porch")
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

extension RunMetricsTests {

    /// The panel shows the criterion beside the rate, always. "0 of 16" with no
    /// statement of what was being counted is a number nobody can act on.
    func testARateAlwaysArrivesWithItsCriterion() throws {
        let success = try DuckIntentSuccess.bundled()
        let clip = try XCTUnwrap(try DuckIntentClip.bundled()["climb"])
        let metrics = RunMetrics(clip: clip, success: success)
        let achieves = try XCTUnwrap(metrics.success.first { $0.label == "Does what it is for" })
        XCTAssertEqual(achieves.value, "0 of 16")
        XCTAssertTrue(achieves.detail?.contains("on the flight") == true)
        XCTAssertEqual(metrics.achievedFraction, 0)

        let repeats = try XCTUnwrap(metrics.success.first { $0.label == "Ends as it was recorded" })
        XCTAssertTrue(repeats.detail?.contains("standing") == true)
        XCTAssertGreaterThan(metrics.repeatedFraction ?? 0, 0.5)
    }

    /// The distribution is on screen with the rate, attributed.
    func testTheRandomisationIsShownWithTheRate() throws {
        let metrics = RunMetrics(clip: try XCTUnwrap(try DuckIntentClip.bundled()["hold"]),
                                 success: try DuckIntentSuccess.bundled())
        let varied = try XCTUnwrap(metrics.success.first { $0.label == "Varied between runs" })
        XCTAssertTrue(varied.detail?.contains("microduck_rl") == true)
        XCTAssertTrue(varied.detail?.contains("Footpad friction") == true)
    }

    /// A motion nobody has rolled out gets no rate at all, rather than a zero.
    func testAnUnmeasuredMotionShowsNothingRatherThanZero() throws {
        let clip = try XCTUnwrap(try DuckIntentClip.bundled()["hold"])
        let renamed = DuckIntentClip(
            name: "somebody else's motion", hz: clip.hz, frames: clip.frames,
            roots: clip.roots, netYaw: clip.netYaw, loops: false,
            startsFrom: clip.startsFrom, endsIn: clip.endsIn,
            policy: clip.policy, authored: false, environment: clip.environment)
        let metrics = RunMetrics(clip: renamed, success: try DuckIntentSuccess.bundled())
        XCTAssertTrue(metrics.success.isEmpty)
        XCTAssertNil(metrics.achievedFraction)
    }
}

extension RunMetricsTests {

    /// Every joint appears exactly once, busiest first.
    func testThePerJointTableCoversAllFourteenSortedByWork() throws {
        let metrics = RunMetrics(clip: try clip("kick_left"))
        XCTAssertEqual(metrics.perJoint.count, DuckModel.policyJointCount)
        XCTAssertEqual(Set(metrics.perJoint.map(\.name)).count, DuckModel.policyJointCount)
        XCTAssertFalse(metrics.perJoint.contains { $0.name == "mouth" },
                       "the mouth is outside every policy's action space")
        for i in 1..<metrics.perJoint.count {
            XCTAssertGreaterThanOrEqual(metrics.perJoint[i - 1].travel,
                                        metrics.perJoint[i].travel)
        }
    }

    /// A left kick is led by the left LEG and a right kick by the right leg —
    /// the assertion that catches a mouth-index off-by-one, which would
    /// silently attribute every joint's numbers to its neighbour.
    ///
    /// LEGS SPECIFICALLY, because the busiest joint overall is not always one:
    /// in `kick_right` the head does more work than any leg joint (1.21 rad of
    /// travel against the right knee's 0.99), which is the policy swinging the
    /// head as a counterweight. A test written against "the busiest joint is on
    /// the kicking side" fails on a correct implementation.
    func testEachKickIsLedByItsOwnLeg() throws {
        for (name, side) in [("kick_left", "left_"), ("kick_right", "right_")] {
            let metrics = RunMetrics(clip: try clip(name))
            let busiestLeg = try XCTUnwrap(metrics.perJoint.first {
                $0.name.hasPrefix("left_") || $0.name.hasPrefix("right_")
            })
            XCTAssertTrue(busiestLeg.name.hasPrefix(side),
                          "\(name) should be led by a \(side) joint, not \(busiestLeg.name)")
        }
    }

    /// Travel and deviation answer different questions: a gait travels a long
    /// way without ever going far from home.
    func testTravelAndDeviationAreNotTheSameNumber() throws {
        let metrics = RunMetrics(clip: try clip("hold"))
        for reading in metrics.perJoint {
            XCTAssertGreaterThanOrEqual(reading.travel, 0)
            XCTAssertGreaterThanOrEqual(reading.peakDeviation, 0)
            XCTAssertGreaterThanOrEqual(reading.usedFraction, 0)
            XCTAssertLessThanOrEqual(reading.usedFraction, 1)
            XCTAssertGreaterThanOrEqual(reading.atStopFraction, 0)
            XCTAssertLessThanOrEqual(reading.atStopFraction, 1)
        }
        // Standing still travels almost nothing — 0.01 rad summed over four
        // seconds — while sitting up to 0.12 rad away from `homePose`, because
        // the STANDING POLICY'S settled stance is not the model's home pose.
        // The two numbers being this far apart is the point: travel says how
        // much a joint moved, deviation says where it sat.
        let busiest = try XCTUnwrap(metrics.perJoint.first)
        XCTAssertLessThan(busiest.travel, 0.05, "holding still barely moves")
        XCTAssertGreaterThan(metrics.perJoint.map(\.peakDeviation).max() ?? 0, 0.05,
                             "and yet it does not sit at the model's home pose")
        XCTAssertLessThan(metrics.perJoint.map(\.peakDeviation).max() ?? 0, 0.15)
    }

    /// The deviation timestamp has to be inside the clip.
    func testTheDeviationMomentIsWithinTheRun() throws {
        let c = try clip("roulade")
        let metrics = RunMetrics(clip: c)
        for reading in metrics.perJoint {
            XCTAssertGreaterThanOrEqual(reading.peakDeviationAt, 0, reading.name)
            XCTAssertLessThanOrEqual(reading.peakDeviationAt, c.duration + 1e-9, reading.name)
        }
    }
}

extension RunMetricsTests {

    /// The reading that stops a tail label speaking for a whole clip. Headspin
    /// ends inverted AND spends most of its run that way; a motion could do one
    /// without the other, which is exactly why both are shown.
    func testItReportsWhatTheMotionSpentItsTimeDoing() throws {
        let metrics = RunMetrics(clip: try clip("headspin"))
        let mostly = try XCTUnwrap(metrics.attitude.first { $0.label == "Mostly" })
        XCTAssertTrue(mostly.value.contains("inverted"), mostly.value)
        // 3.5 s of a 4.0 s clip.
        XCTAssertTrue(mostly.value.contains("3."), mostly.value)
        XCTAssertNotNil(mostly.detail, "the other postures are worth showing too")
    }

    /// A clip that stands still the whole way spends all of it standing.
    func testHoldingStillIsReportedAsStandingThroughout() throws {
        let metrics = RunMetrics(clip: try clip("hold"))
        let mostly = try XCTUnwrap(metrics.attitude.first { $0.label == "Mostly" })
        XCTAssertTrue(mostly.value.hasPrefix("standing"), mostly.value)
        XCTAssertNil(mostly.detail, "there is only one posture to report")
    }

    /// A roll passes through being upside down and comes back, so it has more
    /// than one posture and the breakdown says so.
    func testARollReportsMoreThanOnePosture() throws {
        let metrics = RunMetrics(clip: try clip("roulade"))
        let mostly = try XCTUnwrap(metrics.attitude.first { $0.label == "Mostly" })
        XCTAssertNotNil(mostly.detail)
        XCTAssertTrue(mostly.detail!.contains("·"), mostly.detail!)
    }
}

final class ClipNoteTests: XCTestCase {

    func testAPollenClipGetsNoContributedNote() throws {
        let clip = try XCTUnwrap(try DuckIntentClip.bundled()["roulade"])
        XCTAssertNil(clip.credit)
        XCTAssertNil(ClipNote.provenance(for: clip))
        XCTAssertFalse(ClipNote.needsPlantCaveat(clip))
    }

    func testAContributedClipSaysWhatTheReplayIsAndIsNot() throws {
        let clip = try XCTUnwrap(try DuckIntentClip.bundled()["headspin"])
        let note = try XCTUnwrap(ClipNote.provenance(for: clip))
        XCTAssertTrue(note.contains("did not train it"))
        XCTAssertTrue(note.contains("not a reproduction"))
        XCTAssertTrue(note.contains("file's own declaration"))
        XCTAssertTrue(ClipNote.needsPlantCaveat(clip))
    }

    /// The caveat has to name measured facts — and the first version named a
    /// checkable fact that was FALSE ("no collision geometry on the head"; the
    /// head carries three collision meshes). This pins the corrected claims.
    func testThePlantCaveatNamesMeasuredFacts() {
        XCTAssertTrue(ClipNote.plantCaveat.contains("placed into the headstand"))
        XCTAssertTrue(ClipNote.plantCaveat.contains("never mounts"))
        XCTAssertTrue(ClipNote.plantCaveat.contains("full-collision"))
        XCTAssertTrue(ClipNote.plantCaveat.contains("position servo"))
        XCTAssertFalse(ClipNote.plantCaveat.contains("no collision geometry on the head"))
        XCTAssertFalse(ClipNote.plantCaveat.lowercased().contains("may differ"))
    }
}

// MARK: - the reward table matches the configs, term by term

extension RunMetricsTests {

    /// roller_crouch's config DELETES every reward not in {upright,
    /// body_ang_vel, angular_momentum, action_rate_l2} and its command is a
    /// phase clock, not a twist. A first version scored three tracking terms
    /// the config deletes and denied the upright term it keeps.
    func testRollerCrouchKeepsUprightAndIsNotATwist() {
        let task = RunMetrics.Task.rollerCrouch
        XCTAssertTrue(task.hasSharedUpright)
        XCTAssertEqual(task.upright.weight, 2.0)
        XCTAssertEqual(task.upright.variance, 0.2)
        XCTAssertFalse(task.commandIsATwist,
                       "GroundPickPhaseCommand is cos/sin of a phase, not a velocity")
    }

    /// Every config ramps action_rate_l2; the figure shown is the ramp end.
    /// Read from each config's weight_stages, not assumed uniform: roulade's
    /// ceiling was deliberately softened to −0.4 and ground-pick runs to −2.0.
    func testActionRateWeightsAreTheRampEnds() {
        XCTAssertEqual(RunMetrics.Task.velocity.actionRateWeight, -1.0)
        XCTAssertEqual(RunMetrics.Task.ballKick.actionRateWeight, -1.0)
        XCTAssertEqual(RunMetrics.Task.sitstand.actionRateWeight, -1.0)
        XCTAssertEqual(RunMetrics.Task.rollerCrouch.actionRateWeight, -1.0)
        XCTAssertEqual(RunMetrics.Task.roulade.actionRateWeight, -0.4)
        XCTAssertEqual(RunMetrics.Task.groundPick.actionRateWeight, -2.0)
    }
}
