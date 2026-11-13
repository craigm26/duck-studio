import XCTest
import DuckKit
@testable import StudioKit

/// Today's planner outputs, read as decisions. One way only; the outputs themselves are
/// unchanged (their own tests still pin them).
final class DecisionAdapterTests: XCTestCase {

    func walk(_ d: DuckDecision?) -> (Double, Double)? {
        if case .walk(let f, let s)? = d { return (f, s) }
        return nil
    }

    func degrees(_ d: DuckDecision?) -> Double? {
        if case .turn(let deg)? = d { return deg }
        return nil
    }

    func testDuckTalkWalksAndTurns() throws {
        let got = DecisionAdapter.from(DuckTalk.read("forward for two seconds then turn left"))
        XCTAssertEqual(got.decisions.count, 2)
        let (f, s) = try XCTUnwrap(walk(got.decisions.first))
        XCTAssertEqual(f, DuckDrive.maxForward * 2, accuracy: 1e-12)
        XCTAssertEqual(s, 0)
        XCTAssertEqual(try XCTUnwrap(degrees(got.decisions.last)), DuckDrive.maxTurn * 1 * 180 / .pi, accuracy: 1e-9)
        XCTAssertTrue(got.left.isEmpty)
    }

    func testDuckTalkDegreesComeBackAsDegrees() throws {
        let got = DecisionAdapter.from(DuckTalk.read("turn right 90 degrees"))
        XCTAssertEqual(try XCTUnwrap(degrees(got.decisions.first)), -90, accuracy: 1e-9)
    }

    func testDuckTalkGentlyHalvesTheDistance() throws {
        let got = DecisionAdapter.from(DuckTalk.read("back gently for 2 seconds"))
        let (f, _) = try XCTUnwrap(walk(got.decisions.first))
        XCTAssertEqual(f, -DuckDrive.maxBackward * 0.5 * 2, accuracy: 1e-12)
    }

    func testAStopWordIsAStop() {
        let got = DecisionAdapter.from(DuckTalk.read("forward then stop"))
        XCTAssertEqual(got.decisions.last?.kind, .stop)
    }

    func testNothingReadIsNothingDecided() {
        XCTAssertTrue(DecisionAdapter.from(DuckTalk.read("xyzzy")).decisions.isEmpty)
    }

    func testAModelPlanBecomesDecisions() throws {
        let reply = #"{"steps":[{"skill":"walk_forward","speed":"slow","seconds":3},{"skill":"kick_left"},"#
            + #"{"skill":"make_sound","sound":"greet"},{"skill":"turn_left","head":"look_left","seconds":1},"#
            + #"{"skill":"unsupported"}]}"#
        let plan = try ModelIntentPlanner.read(reply: reply, request: "r", model: "m")
        let got = DecisionAdapter.from(plan)
        XCTAssertEqual(got.decisions.count, 5)
        let (f, _) = try XCTUnwrap(walk(got.decisions[0]))
        XCTAssertEqual(f, DuckDrive.maxForward / 3 * 3, accuracy: 1e-12)
        XCTAssertEqual(got.decisions[1], .skill(name: "kick_left"))
        XCTAssertEqual(got.decisions[2], .sound(name: "greet"))
        XCTAssertEqual(try XCTUnwrap(degrees(got.decisions[3])), DuckDrive.maxTurn * 2 / 3 * 180 / .pi, accuracy: 1e-9)
        XCTAssertEqual(got.decisions[4].kind, .ask)
        XCTAssertEqual(got.left, ["Look left"], "a head direction has no v1 decision and is said, not dropped")
    }

    func testSkillsKeepRobotdsNames() throws {
        let plan = try ModelIntentPlanner.read(reply: #"{"steps":[{"skill":"roll"},{"skill":"peck_ground"}]}"#,
                                               request: "r", model: "m")
        XCTAssertEqual(DecisionAdapter.from(plan).decisions, [.skill(name: "roulade"), .skill(name: "ground_pick")])
    }

    func testEveryDecisionFromAPlanIsInsideARealDucksSet() throws {
        let plan = try ModelIntentPlanner.read(
            reply: #"{"steps":[{"skill":"kick_right"},{"skill":"make_sound","sound":"wheee"},{"skill":"walk_backward"}]}"#,
            request: "r", model: "m")
        let set = AllowedDecisions.forDuck(.real, runsOn: .thisPhone)
        for d in DecisionAdapter.from(plan).decisions {
            XCTAssertNoThrow(try set.admit(d).get(), "\(d)")
        }
    }

    func testDeciderOrders() throws {
        XCTAssertEqual(DecisionAdapter.from(DuckOrder.skill("kick_left")), .skill(name: "kick_left"))
        XCTAssertEqual(DecisionAdapter.from(DuckOrder.sound(.greet)), .sound(name: "greet"))
        XCTAssertEqual(DecisionAdapter.from(DuckOrder.stop)?.kind, .stop)
        let (f, s) = try XCTUnwrap(walk(DecisionAdapter.from(DuckOrder.walk(.left, seconds: 3))))
        XCTAssertEqual(f, 0)
        XCTAssertEqual(s, DuckDrive.maxSideways * DuckOrder.walkShare * 3, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(degrees(DecisionAdapter.from(DuckOrder.walk(.turnRight, seconds: 1)))),
                       -DuckDrive.maxTurn * DuckOrder.walkShare * 180 / .pi, accuracy: 1e-9)
        XCTAssertNil(DecisionAdapter.from(DuckOrder.sit))
        XCTAssertNil(DecisionAdapter.from(DuckOrder.goal("ball")))
    }
}
