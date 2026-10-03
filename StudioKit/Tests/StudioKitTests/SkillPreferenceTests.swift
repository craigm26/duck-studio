import XCTest
import DuckKit
@testable import StudioKit

/// Per-skill RLHF: a kick pack's picks carry the simulator's kick features, are read only into
/// the kick's own taste, and turn into a BallKick menu.
final class SkillPreferenceTests: XCTestCase {

    /// A two-policy, one-condition, two-env kick pack in `export_kick_pairs_for_app.py`'s shape.
    static func pack(skill: String? = "kick_right", features: Bool = true) -> Data {
        let frame = [0.0, 0.0, 0.116, 1, 0, 0, 0] + [Double](repeating: 0, count: 15)
        let clip = [[frame, frame], [frame, frame]]
        var doc: [String: Any] = [
            "format": RolloutPairs.format, "hz": 25.0, "seconds": 5.0, "envs": 2,
            "source": ["batch": "kp001-right", "seed": 4001],
            "policies": [
                "pollen_kick_right": ["repo": "pollen-robotics/microduck-policies",
                                      "file": "ball_kick_right.onnx",
                                      "fingerprint": "sha256:" + String(repeating: "a", count: 64)],
                "k001": ["repo": "craigm26/duckbatch-records",
                         "fingerprint": "sha256:" + String(repeating: "b", count: 64)],
            ],
            "commands": ["plain": [0.0, 0.0, 0.0]],
            "close_first": ["plain": [["a": "pollen_kick_right", "b": "k001"]]],
            "clips": ["pollen_kick_right__plain": clip, "k001__plain": clip],
            "ball": ["pollen_kick_right__plain": [[[0.1, 0, 0.035], [0.5, 0.1, 0.035]],
                                                  [[0.1, 0, 0.035], [0.4, 0, 0.035]]],
                     "k001__plain": [[[0.1, 0, 0.035], [0.6, 0, 0.035]],
                                     [[0.1, 0, 0.035], [0.6, 0, 0.035]]]],
        ]
        if let skill { doc["skill"] = skill }
        if features {
            doc["features"] = ["names": PreferenceModel.Profile.kickFeatureNames, "measured": "simulator",
                               "values": ["pollen_kick_right__plain": [[0.15, 0.3, 0, 0.03, 0.03, 0.034, 0.43],
                                                                       [0.16, 0.3, 0, 0.03, 0.03, 0.034, 0.44]],
                                          "k001__plain": [[0.05, 0.26, 0, 0.033, 0.035, 0.038, 0.5],
                                                          [0.05, 0.26, 0, 0.033, 0.035, 0.038, 0.5]]]]
        }
        return try! JSONSerialization.data(withJSONObject: doc)
    }

    func testAKickPackReadsItsSkillBallAndFeatures() throws {
        let p = try RolloutPairs.read(Self.pack())
        XCTAssertEqual(p.skill, "kick_right")
        XCTAssertTrue(p.hasBall)
        let b = try XCTUnwrap(p.ball("k001", "plain", env: 0, at: 0.02))
        XCTAssertEqual(b.x, 0.35, accuracy: 1e-9, "halfway between 0.1 and 0.6 at 25 Hz")
        XCTAssertEqual(p.features("k001", "plain", env: 1)?.first, 0.05)
    }

    /// A phone cannot measure a kick, so a skill pack without the simulator's numbers is refused.
    func testASkillPackWithoutFeaturesIsRefused() {
        XCTAssertThrowsError(try RolloutPairs.read(Self.pack(features: false)))
    }

    func testAWalkingPackIsUnchanged() throws {
        let p = try RolloutPairs.read(Self.pack(skill: nil, features: false))
        XCTAssertNil(p.skill)
        XCTAssertTrue(p.featureNames.isEmpty)
    }

    private func log(_ picks: [(RolloutPairs.Pick, DuckFeedback.Order, Int)]) throws -> String {
        let p = try RolloutPairs.read(Self.pack())
        return try picks.map { pick, order, env in
            try p.record(pick, reasons: [], for: .init(command: "plain", env: env, a: "pollen_kick_right",
                                                       b: "k001", order: order),
                         share: .local, client: "t").jsonLine()
        }.joined(separator: "\n")
    }

    func testAKickPickCarriesTheSkillAndTheSimulatorsFeatures() throws {
        let line = try log([(.right, .aLeft, 0)])
        XCTAssertTrue(line.contains(#""skill":"kick_right""#))
        XCTAssertTrue(line.contains(#""measured":"simulator""#))
        let picks = PreferenceModel.picks(fromLog: line, profile: .kickRight)
        XCTAssertEqual(picks, [.init(a: [0.15, 0.3, 0, 0.03, 0.03, 0.034, 0.43],
                                     b: [0.05, 0.26, 0, 0.033, 0.035, 0.038, 0.5],
                                     aWasLeft: true, outcome: 0)])
    }

    /// A kick pick never moves the walking taste, and never the other foot's.
    func testAKickPickIsReadOnlyIntoItsOwnProfile() throws {
        let line = try log([(.left, .bLeft, 1)])
        XCTAssertTrue(PreferenceModel.picks(fromLog: line, profile: .walk).isEmpty)
        XCTAssertTrue(PreferenceModel.picks(fromLog: line, profile: .kickLeft).isEmpty)
        XCTAssertEqual(PreferenceModel.picks(fromLog: line, profile: .kickRight).count, 1)
    }

    /// Someone who always picks the straighter kick: straightness gets the most weight, and
    /// smoothness, which Pollen's curriculum owns, maps to no term.
    func testPickingTheStraighterKickWeighsStraightnessMost() {
        var picks: [PreferenceModel.Pick] = []
        for i in 0..<120 {
            let wobbly = Double(i % 7) / 10
            let a = [0.05 + Double(i % 5) / 100, 0.3, 0, 0.03, 0.03, 0.03, 0.4 + wobbly]
            let b = [0.15 + Double(i % 3) / 100, 0.3, 0, 0.03, 0.03, 0.03, 0.4 + (0.6 - wobbly)]
            picks.append(.init(a: a, b: b, aWasLeft: i % 2 == 0, outcome: 1))
        }
        let taste = PreferenceModel.fit(picks)
        XCTAssertEqual(taste.weights.count, 7)
        let plan = PreferenceModel.rewardPlan(from: taste, profile: .kickRight)
        let straight = try! XCTUnwrap(plan.multipliers["straight"])
        XCTAssertGreaterThan(straight, 1.9)
        XCTAssertEqual(straight, plan.multipliers.values.max()!)
        XCTAssertEqual(plan.weights["ball_lateral_speed"]!, -12.0 * straight, accuracy: 1e-9)
        XCTAssertNil(plan.weights["action_rate_l2"], "the kick curriculum owns action_rate_l2")
    }

    func testTheSkillRecipeIsK001sMenuReweighted() {
        let taste = PreferenceModel.Taste(weights: [-5, -1, -1, -1, -1, -1, -1], sideBias: 0, picks: 120)
        let plan = PreferenceModel.rewardPlan(from: taste, profile: .kickLeft)
        let r = HubTraining.SkillRecipe(name: "Straighter left kick", profile: .kickLeft,
                                        fromPicks: .init(taste: taste, plan: plan))
        XCTAssertNil(r.refusal)
        let y = r.menuYAML(batchID: "app-straighter-left-kick-20261003-1200")
        XCTAssertTrue(y.contains("task: Duckbatch-BallKick-Left-Flat-MicroDuck"))
        XCTAssertTrue(y.contains("eval_tasks: [Duckbatch-BallKick-Left-Flat-MicroDuck, Duckbatch-BallKick-Left-Flat-Backlash-MicroDuck]"))
        XCTAssertTrue(y.contains("student: teachers/ball_kick_left.onnx"))
        XCTAssertTrue(y.contains("func: duckbatch.rewards.ball_lateral_speed"))
        XCTAssertTrue(y.contains("    upright: {weight:"))
        XCTAssertFalse(y.contains("ball_lateral_speed: {weight"), "an added term is not re-weighted")
        XCTAssertTrue(y.contains("120 picks between two left kicks"))
    }

    func testWalkingIsNotASkillRecipe() {
        let taste = PreferenceModel.Taste(weights: [Double](repeating: -1, count: 7), sideBias: 0, picks: 100)
        let r = HubTraining.SkillRecipe(name: "w", profile: .walk,
                                        fromPicks: .init(taste: taste, plan: PreferenceModel.rewardPlan(from: taste)))
        XCTAssertNotNil(r.refusal)
    }
}
