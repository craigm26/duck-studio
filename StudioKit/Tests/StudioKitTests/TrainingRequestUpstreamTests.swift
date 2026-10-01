import XCTest
@testable import StudioKit

/// What importing every vocabulary term into microduck_rl `cfe1c2a` on mjlab
/// 1.3.0 found on 2026-09-30, held so it cannot come back.
final class TrainingRequestUpstreamTests: XCTestCase {

    private func request(_ base: TrainingRequest.Base, _ functions: [String]) -> TrainingRequest {
        TrainingRequest(name: "check", summary: "check", base: base,
                        rewards: functions.map { .init(function: $0, weight: 0.1, reason: "r") },
                        successCriterion: "s")
    }

    /// mjlab 1.3.0 has no `mjlab.managers.manager_term_config` and no
    /// `mjlab.utils.spec_config`; both lines made every emitted file fail to
    /// import.
    func testTheImportsAreOnesMjlab130Has() {
        let file = request(.velocity, ["is_alive"]).envConfig()
        XCTAssertTrue(file.contains("from mjlab.managers import RewardTermCfg"), file)
        XCTAssertTrue(file.contains("from mjlab.sensor import ContactSensorCfg"), file)
        XCTAssertTrue(file.contains("from mjlab.managers.scene_entity_config import SceneEntityCfg"), file)
        XCTAssertFalse(file.contains("manager_term_config"), file)
        XCTAssertFalse(file.contains("spec_config"), file)
    }

    /// FIVE TERMS REQUIRE ARGUMENTS, and `params={}` failed only once the
    /// reward manager called them — on a GPU, mid-run.
    func testTermsWithRequiredArgumentsGetThem() {
        let file = request(.groundPick, ["feet_grounded_reward", "self_collision_cost",
                                         "body_impact_cost", "height_target_gaussian",
                                         "height_l1_penalty"]).envConfig()
        XCTAssertTrue(file.contains(#""sensor_name": _sensor(cfg, "feet_ground_contact")"#), file)
        XCTAssertTrue(file.contains(#""sensor_name": _sensor(cfg, "self_collision")"#), file)
        XCTAssertTrue(file.contains(#""sensor_name": _sensor(cfg, "head_impact_contact"), "threshold": 1.0"#), file)
        XCTAssertEqual(file.components(separatedBy: #""target_height": STAND_Z"#).count - 1, 2, file)
        XCTAssertTrue(file.contains("STAND_Z = 0.115"), file)
        XCTAssertTrue(file.contains("def _sensor(cfg, name):"), file)
        // A term with no required argument still gets an empty dict.
        let plain = request(.velocity, ["is_alive"]).envConfig()
        XCTAssertTrue(plain.contains("params={},"), plain)
    }

    /// Only ground pick defines the head sensor; the request says so before
    /// any file is written, not when the task is built.
    func testAMissingSensorIsRefusedAtAuthoringTime() {
        XCTAssertTrue(request(.groundPick, ["body_impact_cost"]).refusals.isEmpty)
        let refused = request(.velocity, ["body_impact_cost"]).refusals
        XCTAssertEqual(refused, [.missingSensor(reward: "body_impact_cost",
                                                sensor: "head_impact_contact",
                                                base: "microduck_velocity_env_cfg.py")])
        XCTAssertTrue(refused[0].message.contains("ground pick does"), refused[0].message)
        for base in TrainingRequest.Base.allCases {
            XCTAssertTrue(request(base, ["feet_grounded_reward", "self_collision_cost"])
                .refusals.isEmpty, base.rawValue)
        }
    }
}
