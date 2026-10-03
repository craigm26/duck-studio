import XCTest
import DuckKit
@testable import StudioKit

final class PreferenceFeaturesTests: XCTestCase {

    /// A clip that walks straight along +x at `speed`, upright, joints swinging `swing`.
    private func clip(speed: Double, yawRate: Double = 0, roll: Double = 0,
                      swing: (Int) -> Double = { _ in 0 }, n: Int = 101) -> DuckIntentClip {
        let hz = 50.0
        var roots: [DuckIntentClip.Root] = [], frames: [[Double]] = []
        var x = 0.0, y = 0.0
        for t in 0..<n {
            let yaw = yawRate * Double(t) / hz
            // q = yaw about z, then roll about x.
            let qz = (cos(yaw / 2), 0.0, 0.0, sin(yaw / 2))
            let qx = (cos(roll / 2), sin(roll / 2), 0.0, 0.0)
            let q = (qz.0 * qx.0 - qz.3 * 0, qz.0 * qx.1, qz.3 * qx.1, qz.3 * qx.0)
            roots.append(.init(x: x, y: y, z: 0.115, quaternion: q))
            x += speed * cos(yaw) / hz; y += speed * sin(yaw) / hz
            frames.append([Double](repeating: swing(t), count: 14))
        }
        return DuckIntentClip(name: "t", hz: hz, frames: frames, roots: roots, netYaw: 0,
                              loops: false, startsFrom: .standing, endsIn: .standing,
                              policy: "t", authored: false,
                              environment: .init(ground: true, yaw: 0, steps: [], walls: []))
    }

    private func f(_ c: DuckIntentClip, _ cmd: (Double, Double, Double)) throws -> [String: Double] {
        let v = try PreferenceFeatures.measure(c, command: cmd).values
        return Dictionary(uniqueKeysWithValues: zip(PreferenceFeatures.names, v))
    }

    func testWalkingAtTheCommandHasNoTrackingError() throws {
        let m = try f(clip(speed: 0.3), (0.3, 0, 0))
        XCTAssertEqual(m["lin_err"]!, 0, accuracy: 1e-9)
        XCTAssertEqual(m["fell"], 0)
        XCTAssertEqual(m["down_frac"], 0)
        XCTAssertEqual(m["wobble"]!, 0, accuracy: 1e-9)
    }

    func testStandingWhenToldToWalkIsTheWholeCommandInError() throws {
        let m = try f(clip(speed: 0), (0.3, 0, 0))
        XCTAssertEqual(m["lin_err"]!, 0.3, accuracy: 1e-9)
    }

    /// The speed is read in the BODY frame, as mjlab's is: a duck turning while it walks
    /// forward is still walking forward.
    func testTurningWhileWalkingIsReadInTheBodyFrame() throws {
        let m = try f(clip(speed: 0.2, yawRate: 0.5), (0.2, 0, 0.5))
        XCTAssertEqual(m["lin_err"]!, 0, accuracy: 0.01)
        XCTAssertEqual(m["ang_err"]!, 0, accuracy: 1e-6)
    }

    func testOnItsSideIsDown() throws {
        let m = try f(clip(speed: 0, roll: .pi / 2), (0, 0, 0))
        XCTAssertEqual(m["fell"], 1)
        XCTAssertEqual(m["down_frac"]!, 1, accuracy: 1e-9)
    }

    func testTwitchyJointsScoreHigherJitter() throws {
        let smooth = try f(clip(speed: 0.3, swing: { 0.2 * sin(Double($0) / 10) }), (0.3, 0, 0))
        let twitchy = try f(clip(speed: 0.3, swing: { $0 % 2 == 0 ? 0.05 : -0.05 }), (0.3, 0, 0))
        XCTAssertGreaterThan(twitchy["jitter"]!, 10 * smooth["jitter"]!)
    }

    func testTooShortIsRefused() {
        XCTAssertThrowsError(try PreferenceFeatures.measure(clip(speed: 0, n: 2), command: (0, 0, 0)))
    }
}

final class PreferenceModelTests: XCTestCase {

    /// THE SAME NUMBERS AS duckbatch. The fixture was made by duckbatch's own
    /// `preference.fit` (numpy, Newton, L2 0.01) on these 40 picks.
    func testTheFitMatchesDuckbatch() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/preference-fit-duckbatch",
                                                  withExtension: "json"))
        let d = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let a = d["a"] as! [[Double]], b = d["b"] as! [[Double]]
        let left = d["left"] as! [Bool], y = d["y"] as! [Double]
        let picks = (0..<a.count).map { PreferenceModel.Pick(a: a[$0], b: b[$0], aWasLeft: left[$0],
                                                              outcome: y[$0]) }
        let taste = PreferenceModel.fit(picks)
        for (got, want) in zip(taste.weights, d["w"] as! [Double]) {
            XCTAssertEqual(got, want, accuracy: 1e-6)
        }
        XCTAssertEqual(taste.sideBias, d["beta"] as! Double, accuracy: 1e-6)
    }

    func testAnEvenTasteLeavesPollensWeights() {
        let taste = PreferenceModel.Taste(weights: [-1, -1, -0.5, -0.5, -0.5, -0.5, -1],
                                          sideBias: 0, picks: 100)
        let plan = PreferenceModel.rewardPlan(from: taste)
        for m in plan.multipliers.values { XCTAssertEqual(m, 1, accuracy: 1e-9) }
        XCTAssertEqual(plan.weights["track_linear_velocity"]!, 2.0, accuracy: 1e-9)
        XCTAssertEqual(plan.weights["action_rate_l2"]!, -1.0, accuracy: 1e-9)
        XCTAssertTrue(plan.reversed.isEmpty)
    }

    func testCaringMostAboutFallsDoublesUprightAtMost() {
        let taste = PreferenceModel.Taste(weights: [-0.1, -0.1, -5, -5, -0.1, -0.1, -0.1],
                                          sideBias: 0, picks: 100)
        let plan = PreferenceModel.rewardPlan(from: taste)
        XCTAssertEqual(plan.multipliers["upright"], 2.0)
        XCTAssertEqual(plan.weights["upright"]!, 4.0, accuracy: 1e-9)
        XCTAssertEqual(plan.multipliers["tracking"], 0.5)
    }

    /// A taste for MORE falls is not a reward to train toward: it stays at Pollen's and is said.
    func testAReversedPreferenceIsLeftAloneAndFlagged() {
        let taste = PreferenceModel.Taste(weights: [-1, -1, 2, 2, -1, -1, -1], sideBias: 0, picks: 100)
        let plan = PreferenceModel.rewardPlan(from: taste)
        XCTAssertEqual(plan.multipliers["upright"], 1)
        XCTAssertEqual(plan.reversed, ["upright"])
    }

    func testTheWordsSayWhatThisIsAndIsNot() {
        XCTAssertTrue(PreferenceModel.whatThisDoes.contains("human feedback"))
        XCTAssertTrue(PreferenceModel.whatThisDoes.contains("This is not a reward model"))
        XCTAssertTrue(PreferenceModel.notEnoughPicks(12).hasPrefix("12 of 100"))
    }

    /// A pick written by the app reads back as a pick the model can use; a motion pick does not.
    func testARecordedPickReadsBack() throws {
        let fa = PreferenceFeatures(values: [0.1, 0.2, 0, 0, 0.03, 0.01, 0.4])
        let fb = PreferenceFeatures(values: [0.3, 0.2, 1, 0.5, 0.05, 0.02, 0.9])
        func contender(_ n: String, _ kind: Compare.Contender.Kind = .behaviour) -> Compare.Contender {
            Compare.Contender(kind: kind, name: n,
                              digest: "sha256:" + String(repeating: n, count: 64),
                              source: .pollen, key: n)
        }
        let rec = try DuckFeedback.preference(
            a: contender("a"), b: contender("b"), choice: .a, where: .phoneBench, order: .aLeft,
            context: "duel", command: [0.3, 0, 0], features: (fa, fb), share: .local, client: "t")
        let motion = try DuckFeedback.preference(
            a: contender("c", .motion), b: contender("d", .motion), choice: .a, where: .phoneBench,
            order: .aLeft, context: "duel", share: .local, client: "t")
        let log = [rec.jsonLine(), motion.jsonLine()].joined(separator: "\n")
        let picks = PreferenceModel.picks(fromLog: log)
        XCTAssertEqual(picks, [.init(a: fa.values, b: fb.values, aWasLeft: true, outcome: 1)])
        XCTAssertTrue(rec.jsonLine().contains("\"joint_proxy\":[\"action_rate\",\"jitter\"]"))
    }
}
