import XCTest
@testable import StudioKit

final class TrainingRequestTests: XCTestCase {

    private func request(prop: DuckScene.Prop? = nil,
                         rewards: [TrainingRequest.Reward]? = nil,
                         seconds: Double = 5) -> TrainingRequest {
        TrainingRequest(
            name: "Drag the broom",
            summary: "Take hold of a handle and tow it",
            base: .groundPick,
            episodeSeconds: seconds,
            rewards: rewards ?? [
                .init(function: "mouth_ground_proximity", weight: 3,
                      reason: "get the mouth to the handle"),
                .init(function: "forward_speed_reward", weight: 2, reason: "then tow it"),
                .init(function: "is_alive", weight: 0.5, reason: "and stay up"),
            ],
            prop: prop,
            successCriterion: "the broom moves 0.5 m and the duck is still standing")
    }

    /// Every reward named has to exist upstream. A config naming one that does
    /// not will not import, and a training machine is a slow place to find a
    /// typo.
    func testOnlyRewardsThatExistAreAllowed() {
        XCTAssertTrue(request().isTrainable)
        let invented = request(rewards: [.init(function: "reward_dragging_nicely",
                                               weight: 1, reason: "made up")])
        XCTAssertFalse(invented.isTrainable)
        XCTAssertEqual(invented.refusals.first, .unknownReward("reward_dragging_nicely"))
    }

    /// Every name in the vocabulary was read out of upstream's mdp.py.
    func testTheVocabularyNamesRealFunctions() {
        for name in ["mouth_ground_proximity", "mouth_perpendicular_to_ground",
                     "pose_target_match", "joint_torques_l2", "is_alive",
                     "feet_grounded_reward", "body_impact_cost"] {
            XCTAssertNotNil(TrainingRequest.vocabulary[name], name)
        }
    }

    func testATaskWithNoRewardsHasNoGradient() {
        let empty = request(rewards: [])
        XCTAssertFalse(empty.isTrainable)
        XCTAssertEqual(empty.refusals.first, .noRewards)
    }

    /// THE CHECK THAT SAVES GPU HOURS. Two kilos hanging off the beak is
    /// arithmetic, not training: 19.6 N against a neck that stalls at 7.7.
    func testAskingForTwoKilosIsRefusedBeforeAnybodyTrainsIt() {
        let brick = DuckScene.Prop(name: "Brick", x: 0.5, y: 0, grams: 2000,
                                   thicknessMillimetres: 60, length: 0.2)
        let plan = request(prop: brick)
        XCTAssertFalse(plan.isTrainable)
        guard case .pastTheTorque(let needed, let ceiling)? = plan.refusals.first else {
            return XCTFail("expected the torque ceiling, got \(plan.refusals)")
        }
        XCTAssertEqual(needed, 19.62, accuracy: 0.05)
        XCTAssertEqual(ceiling, 7.66, accuracy: 0.05)
        XCTAssertTrue(plan.refusals.first!.message.contains("arithmetic, not training"))
    }

    /// And the broom is NOT refused: 600 g is 5.9 N, inside the neck's 7.7.
    func testTheBroomIsWorthTraining() {
        let plan = request(prop: DuckScene.broom())
        XCTAssertTrue(plan.isTrainable, "\(plan.refusals.map(\.message))")
    }

    /// What the OLD policy was shown is not a limit on a new one. 600 g is far
    /// past the 10–40 g alpha_ground_pick saw, and that must not refuse it.
    func testThePreviousTrainingSetIsNotALimit() {
        let heavy = DuckScene.Prop(name: "Jug", x: 0.4, y: 0, grams: 500,
                                   thicknessMillimetres: 40, length: 0.2)
        XCTAssertFalse(heavy.stick.isLiftable, "far past what the old policy was trained on")
        XCTAssertTrue(request(prop: heavy).isTrainable, "which says nothing about a new one")
    }

    func testGeometryIsNotSomethingTrainingChanges() {
        let thin = DuckScene.Prop(name: "Wire", x: 0.4, y: 0, grams: 5,
                                  thicknessMillimetres: 3, length: 0.3)
        XCTAssertEqual(request(prop: thin).refusals.first, .underTheBite(millimetres: 3))
        let high = DuckScene.Prop(name: "Shelf thing", x: 0.4, y: 0, grams: 20,
                                  thicknessMillimetres: 30, length: 0.2,
                                  graspHeightMillimetres: 500)
        XCTAssertEqual(request(prop: high).refusals.first, .pastTheReach(millimetres: 500))
    }

    /// A long episode is a warning, not a refusal — it is a judgement about
    /// wasted compute, not about possibility.
    func testALongEpisodeWarnsWithoutStopping() {
        let slow = request(seconds: 30)
        XCTAssertTrue(slow.isTrainable)
        XCTAssertEqual(slow.refusals.first, .episodeTooLong(30))
    }

    // MARK: - what gets handed over

    func testTheConfigIsHonestAboutBeingASkeleton() {
        let python = request(prop: DuckScene.broom()).envConfig()
        XCTAssertTrue(python.contains("A SKELETON, NOT A TRAINED TASK"))
        XCTAssertTrue(python.contains("microduck_ground_pick_env_cfg.py"))
        XCTAssertTrue(python.contains("microduck_mdp.mouth_ground_proximity"))
        XCTAssertTrue(python.contains("def make_drag_the_broom_env_cfg"))
        // The prop is named AND the config says it is not in the scene yet,
        // which is the first job for whoever runs this.
        XCTAssertTrue(python.contains("Broom"))
        XCTAssertTrue(python.contains("It is NOT in this config"))
    }

    func testTheFileIsNamedTheWayUpstreamNamesThem() {
        XCTAssertEqual(request().fileName, "microduck_drag_the_broom_env_cfg.py")
    }

    func testTheBriefCarriesTheNumbersAndTheDisclaimer() {
        let brief = request(prop: DuckScene.broom()).brief()
        XCTAssertTrue(brief.contains("Nothing here has been trained"))
        XCTAssertTrue(brief.contains("7.7 N"))
        XCTAssertTrue(brief.contains("0.6405"))
        XCTAssertTrue(brief.contains("not a limit on a new one"))
        XCTAssertTrue(brief.contains("mouth_ground_proximity"))
    }

    func testARefusedRequestSaysSoInItsBrief() {
        let brick = DuckScene.Prop(name: "Brick", x: 0.5, y: 0, grams: 2000,
                                   thicknessMillimetres: 60, length: 0.2)
        XCTAssertTrue(request(prop: brick).brief().contains("REFUSED:"))
    }
}

/// Regression tests written from what a real local model actually returned.
extension TrainingRequestTests {

    /// qwen3.5:2b, asked to name a task, handed back the base config's
    /// FILENAME. The naive slug turned that into
    /// microduck_microduck_ground_pick_env_cfg_py_env_cfg.py.
    func testANameThatIsAlreadyAFilenameDoesNotDoubleUp() {
        let echoed = TrainingRequest(
            name: "microduck_ground_pick_env_cfg.py",
            summary: "grab and drag", base: .groundPick,
            rewards: [.init(function: "is_alive", weight: 1, reason: "stay up")],
            successCriterion: "it moves")
        XCTAssertEqual(echoed.slug, "ground_pick")
        XCTAssertEqual(echoed.fileName, "microduck_ground_pick_env_cfg.py")
    }

    func testAnEmptyOrPunctuationNameStillProducesAFile() {
        let blank = TrainingRequest(name: "...", summary: "", base: .velocity,
                                    rewards: [.init(function: "is_alive", weight: 1, reason: "x")],
                                    successCriterion: "y")
        XCTAssertEqual(blank.fileName, "microduck_new_task_env_cfg.py")
    }

    /// The whole reply qwen3.5:2b gave for "teach it to grab a broom handle off
    /// the floor and drag it two metres" — three real reward functions, the
    /// right base, and nothing invented.
    func testARealLocalModelsRequestSurvivesTheChecker() throws {
        let json = """
        {"name":"Drag the broom","summary":"grab a broom handle and drag it",
         "base":"microduck_ground_pick_env_cfg.py","episodeSeconds":6.0,
         "successCriterion":"the broom moves two metres",
         "rewards":[{"function":"mouth_perpendicular_to_ground","weight":2.0,"reason":"point the beak at it"},
                    {"function":"feet_grounded_reward","weight":1.5,"reason":"keep both feet down"},
                    {"function":"forward_speed_reward","weight":3.0,"reason":"then tow it"}],
         "openQuestions":["how heavy the broom is"]}
        """
        let request = try ChatDraft.training(fromJSON: json, prop: DuckScene.broom())
        XCTAssertEqual(request.base, .groundPick)
        XCTAssertEqual(request.rewards.count, 3)
        XCTAssertTrue(request.isTrainable, "\(request.refusals.map(\.message))")
        XCTAssertEqual(request.fileName, "microduck_drag_the_broom_env_cfg.py")
        XCTAssertTrue(request.envConfig().contains("microduck_mdp.forward_speed_reward"))
        XCTAssertTrue(request.brief().contains("how heavy the broom is"))
    }

    /// A model that invents a reward gets caught here rather than on a GPU.
    func testAnInventedRewardFromAModelIsCaught() throws {
        let json = """
        {"name":"Tow","base":"microduck_velocity_env_cfg.py",
         "rewards":[{"function":"reward_towing","weight":2.0,"reason":"tow"}]}
        """
        let request = try ChatDraft.training(fromJSON: json)
        XCTAssertFalse(request.isTrainable)
        XCTAssertEqual(request.refusals.first, .unknownReward("reward_towing"))
    }

    // MARK: - the config has to import, and it did not

    /// EVERY CONFIG THIS APP EVER WROTE FAILED ON ITS IMPORT LINE. The emitter
    /// stripped `microduck_` off the module name to build the factory call, so
    /// `microduck_velocity_env_cfg` became `make_velocity_env_cfg`. Upstream
    /// defines `make_microduck_velocity_env_cfg` — checked against all five
    /// modules at pollen-robotics/microduck_rl main on 2026-08-31.
    func testTheFactoryNameIsTheOneUpstreamActuallyDefines() {
        for base in TrainingRequest.Base.allCases {
            XCTAssertEqual(base.factoryName, "make_\(base.moduleName)")
            XCTAssertTrue(base.factoryName.hasPrefix("make_microduck_"),
                          "\(base.factoryName) is not a name upstream defines")
            XCTAssertFalse(base.moduleName.hasSuffix(".py"))
        }
        XCTAssertEqual(TrainingRequest.Base.velocity.factoryName,
                       "make_microduck_velocity_env_cfg")
    }

    /// `self_collision_cost` is mjlab's, not microduck's, and was emitted with
    /// the wrong qualifier — an AttributeError at config time.
    func testTheOneFunctionThatIsNotMicroducksIsQualifiedAsMjlabs() {
        XCTAssertEqual(TrainingRequest.moduleFor("self_collision_cost"), "mjlab_mdp")
        XCTAssertEqual(TrainingRequest.moduleFor("fallen_state_penalty"), "microduck_mdp")
    }

    // MARK: - the sign that trains the duck to fall over

    /// THE NAME DOES NOT TELL YOU THE SIGN, which is why this table exists.
    /// Both of these end in `_penalty` and want opposite weights:
    /// `fallen_state_penalty` returns `fallen.float()` (non-negative),
    /// `pose_l1_penalty` returns `-torch.abs(...)`.
    func testTwoPenaltiesWithTheSameSuffixWantOppositeSigns() {
        XCTAssertEqual(TrainingRequest.weightSigns["fallen_state_penalty"], .negative)
        XCTAssertEqual(TrainingRequest.weightSigns["pose_l1_penalty"], .positive)
    }

    /// Every function the app offers has a sign, or the warning silently skips it.
    func testEveryVocabularyTermKnowsWhichWayItsWeightPoints() {
        for name in TrainingRequest.vocabulary.keys {
            XCTAssertNotNil(TrainingRequest.weightSigns[name],
                            "\(name) is offered with no sign, so a wrong weight passes unremarked")
        }
    }

    /// A weight pointing the wrong way is named, with what it will cause.
    func testAWeightPointingTheWrongWayIsCalledOut() {
        let bad = TrainingRequest(
            name: "farm the fall", summary: "s", base: .velocity, episodeSeconds: 5,
            rewards: [.init(function: "fallen_state_penalty", weight: 2.0, reason: "r")],
            prop: nil, successCriterion: "c", openQuestions: [])
        XCTAssertEqual(bad.wrongSigns.count, 1)
        XCTAssertTrue(bad.wrongSigns[0].contains("NEGATIVE weight"), bad.wrongSigns[0])
        XCTAssertTrue(bad.brief().contains("butt-hopping, crash-sits"),
                      "the brief must carry upstream's own words for what this causes")

        let good = TrainingRequest(
            name: "fine", summary: "s", base: .velocity, episodeSeconds: 5,
            rewards: [.init(function: "fallen_state_penalty", weight: -2.0, reason: "r"),
                      .init(function: "pose_l1_penalty", weight: 1.0, reason: "r")],
            prop: nil, successCriterion: "c", openQuestions: [])
        XCTAssertTrue(good.wrongSigns.isEmpty)
        XCTAssertFalse(good.brief().contains("Check these signs"))
    }

    /// And the brief no longer claims every function is in one module.
    func testTheBriefNoLongerClaimsEveryFunctionIsInMicroducksModule() {
        let r = TrainingRequest(
            name: "n", summary: "s", base: .velocity, episodeSeconds: 5,
            rewards: [.init(function: "self_collision_cost", weight: -1, reason: "r")],
            prop: nil, successCriterion: "c", openQuestions: [])
        XCTAssertFalse(r.brief().contains("Every function named above exists in `mjlab_microduck/tasks/mdp.py`."))
        XCTAssertTrue(r.brief().contains("not all in one module"))
        XCTAssertTrue(r.envConfig().contains("mjlab_mdp.self_collision_cost"))
    }

    // MARK: - the head as a lever

    /// A CLIMB THAT USES THE HEAD GETS THE ARITHMETIC, EVEN WITH NO PROP. The
    /// neck check used to run only for a prop's grams, so the exact request
    /// Craig asked about — the head pushing the body up a step — passed with
    /// no refusal at all.
    func testAHeadLeverClimbGetsTheStallArithmeticAsAnAdvisory() {
        let climb = TrainingRequest(
            name: "Lever up a step",
            summary: "Press the head against the riser and lever the body onto the tread",
            base: .groundPick,
            episodeSeconds: 6,
            rewards: [.init(function: "mouth_ground_proximity", weight: 2, reason: "head to the riser"),
                      .init(function: "is_alive", weight: 0.5, reason: "and stay up")],
            prop: nil,
            successCriterion: "both feet on the first stair tread")
        let lever = climb.refusals.first { if case .leverAtTheStall = $0 { return true }; return false }
        XCTAssertNotNil(lever, "\(climb.refusals)")
        XCTAssertEqual(lever?.isFatal, false)
        XCTAssertTrue(lever?.message.contains("margin") == true, lever?.message ?? "")
        XCTAssertTrue(lever?.message.contains("stayed on the floor") == true)
        // The broom request has a mouth reward and no prop too, but says
        // nothing about climbing — no lever arithmetic is offered.
        XCTAssertFalse(request().refusals.contains { if case .leverAtTheStall = $0 { return true }; return false })
        XCTAssertTrue(TrainingRequest.readsAsAClimb(name: "x", summary: "a mantle onto a ledge", success: ""))
        XCTAssertFalse(TrainingRequest.readsAsAClimb(name: "Drag the broom", summary: "tow it", success: "moves"))
    }

    /// The brief's claim about upstream carries the three things a person
    /// editing the config by hand would otherwise find the slow way.
    func testTheBriefNamesTheThreeVocabularyGotchas() {
        let brief = request().brief()
        XCTAssertTrue(brief.contains("pose_target_match"), brief)
        XCTAssertTrue(brief.contains("defined twice"), brief)
        XCTAssertTrue(brief.contains("ground-pick task"), brief)
        XCTAssertTrue(brief.contains("2026-09-01"), brief)
    }
}
