import XCTest
import DuckKit
import DuckEvidence
@testable import StudioKit

/// What a plan sends to a real duck: Pollen's method names and param shapes, every skill
/// checked against what the robot listed before anything moves, and a stop at the end.
final class RobotPlanTests: XCTestCase {

    /// A robotd stand-in that records every line and answers the way robotd does.
    private final class FakeRobot: DuckPeer, @unchecked Sendable {
        let identity = DuckIdentity(name: "Pip", kind: .real)
        let transportKind: DuckTransportKind
        let reach: Set<DuckMethod>
        private let lock = NSLock()
        private var _sent: [String] = []
        var sent: [String] { lock.lock(); defer { lock.unlock() }; return _sent }
        var skillsJSON = #"{"skills":[{"name":"kick_left","duration":0.5},{"name":"kick_right"},{"name":"roulade","duration":1.0}],"built_in":["ground_pick","sit_toggle"]}"#
        var refuseDo: String?

        init(_ transport: DuckTransportKind = .bridge) {
            transportKind = transport
            reach = DuckMethod.reach(for: transport)
        }

        private func record(_ c: DuckCall) throws {
            let line = String(decoding: try c.line(id: c.isNotification ? nil : 1), as: UTF8.self)
            lock.lock(); _sent.append(line.trimmingCharacters(in: .newlines)); lock.unlock()
        }

        func call(_ c: DuckCall) async throws -> DuckReply {
            try vet(c, asNotification: false)
            try record(c)
            let body: String
            switch c {
            case .skills: body = skillsJSON
            case .doSkill:
                body = refuseDo.map { #"{"accepted":false,"reason":"\#($0)"}"# } ?? #"{"accepted":true}"#
            default: body = #"{"accepted":true}"#
            }
            return DuckReply(id: 1, result: Data(body.utf8), failure: nil)
        }

        func notify(_ c: DuckCall) async throws {
            try vet(c, asNotification: true)
            try record(c)
        }

        nonisolated func states() -> AsyncStream<DuckState> { AsyncStream { $0.finish() } }
    }

    private static let noWait: RobotPlanRunner.Sleep = { _ in }

    private func plan(_ steps: [(String, [String: String])]) throws -> DuckIntentPlan {
        let rows = steps.map { clause, labels -> [String: Any] in
            ["clause": clause, "labels": labels,
             "confidence": Dictionary(uniqueKeysWithValues: labels.keys.map { ($0, 0.9) })]
        }
        let json: [String: Any] = ["format": DuckIntentPlan.format, "request": "test",
                                   "model": "t", "steps": rows]
        return try DuckIntentPlan.read(JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - the wire

    func testTheThreeRobotCallsArePollensShapes() throws {
        XCTAssertEqual(String(decoding: try DuckCall.doSkill("kick_left").line(id: 3), as: UTF8.self),
                       #"{"id":3,"jsonrpc":"2.0","method":"robot.do","params":{"skill":"kick_left"}}"# + "\n")
        XCTAssertEqual(String(decoding: try DuckCall.skills.line(id: 4), as: UTF8.self),
                       #"{"id":4,"jsonrpc":"2.0","method":"robot.skills"}"# + "\n")
        XCTAssertEqual(String(decoding: try DuckCall.sound(.greet).line(id: 5), as: UTF8.self),
                       #"{"id":5,"jsonrpc":"2.0","method":"robot.sound","params":{"tag":"greet"}}"# + "\n")
    }

    func testASkillNameThatCouldCarryANewlineIsStoppedHere() {
        XCTAssertThrowsError(try DuckCall.doSkill("kick\n{\"method\":\"system.update\"}").line(id: 1)) {
            XCTAssertEqual($0 as? DuckCall.Misuse, .notASkillName("kick\n{\"method\":\"system.update\"}"))
        }
        XCTAssertThrowsError(try DuckCall.doSkill("").line(id: 1))
    }

    /// Pollen's `SoundTag` names are DuckSound's exactly; if either side gains one, this fails.
    func testEverySoundTagIsOneThePlannerMayName() {
        XCTAssertEqual(Set(DuckSound.allCases.map(\.rawValue)), Set(DuckIntentPlan.Vocabulary.sounds))
    }

    func testRoutingSkillsAndSoundsReachADuckAndNotABenchOrBluetooth() {
        for m in [DuckMethod.doSkill, .skills, .sound] {
            XCTAssertTrue(DuckMethod.reach(for: .bridge).contains(m))
            XCTAssertTrue(DuckMethod.reach(for: .webRTC).contains(m))
            XCTAssertFalse(DuckMethod.reach(for: .bench).contains(m))
            XCTAssertFalse(DuckMethod.reach(for: .ble).contains(m))
            XCTAssertFalse(m.mutatesTheRecoveryPath)
        }
        XCTAssertEqual(BenchPeer.refusal(for: .doSkill("kick_left")), .skillsAreTheBenchsOwn(.doSkill))
        XCTAssertEqual(BenchPeer.refusal(for: .sound(.chirp)), .noVoice)
    }

    // MARK: - the plan

    func testEverySkillLabelHasARobotdName() {
        for (label, slot) in DuckIntentPlan.skills {
            XCTAssertNotNil(RobotPlan.robotdName[slot], label)
            XCTAssertNotNil(RobotPlan.skillSeconds[RobotPlan.robotdName[slot]!], label)
        }
    }

    func testOnARobotASkillMaySitAnywhereAndSoundsArePlayed() throws {
        let p = try RobotPlan(plan([
            ("walk forward", ["action": "walk_forward", "speed": "slow"]),
            ("kick it", ["action": "kick_left"]),
            ("say hello", ["action": "make_sound", "sound": "greet"]),
            ("sit down", ["action": "sit_or_stand"]),
        ]))
        XCTAssertEqual(p.beats.count, 4)
        guard case .move(let t, let s, _) = p.beats[0] else { return XCTFail() }
        XCTAssertEqual(t, try SequenceProposal.twist(for: "forward", share: 1.0 / 3.0))
        XCTAssertEqual(s, DuckIntentPlan.defaultSeconds)
        XCTAssertEqual(p.beats[1], .skill("kick_left", seconds: 0.5, clause: "kick it"))
        XCTAssertEqual(p.beats[2], .sound(.greet, clause: "say hello"))
        XCTAssertEqual(p.skillNames, ["kick_left", "sit_toggle"])
        XCTAssertTrue(p.notSent.isEmpty)
    }

    func testAPlanOfOnlyRefusalsIsRefused() throws {
        XCTAssertThrowsError(try RobotPlan(plan([("fly", ["action": "unsupported"])]))) {
            XCTAssertEqual($0 as? RobotPlan.Refusal, .nothingToRun)
        }
    }

    // MARK: - running

    func testARunStreamsTheMoveThenKicksThenStops() async throws {
        let duck = FakeRobot()
        let p = try RobotPlan(plan([
            ("walk", ["action": "walk_forward"]),
            ("kick", ["action": "kick_right"]),
        ]))
        let outcome = try await RobotPlanRunner.run(p, on: duck, interval: 0.1, sleep: Self.noWait)
        XCTAssertEqual(outcome, .finished)
        let sent = duck.sent
        XCTAssertTrue(sent[0].contains("robot.skills"), "the list is read before anything moves")
        let moves = sent.prefix(while: { !$0.contains("robot.stop") }).filter { $0.contains("robot.move") }
        XCTAssertEqual(moves.count, 20, "two seconds at ten a second")
        let doAt = try XCTUnwrap(sent.firstIndex { $0.contains("robot.do") })
        XCTAssertTrue(sent[doAt - 1].contains("robot.stop"), "a skill starts from a zero twist")
        XCTAssertTrue(sent[doAt].contains(#""skill":"kick_right""#))
        // kick_right has no duration in the listing: the manifest's 0.5 s + 1 s settle, fed.
        let after = sent[(doAt + 1)...].filter { $0.contains("robot.move") }
        XCTAssertEqual(after.count, 15)
        XCTAssertTrue(after.allSatisfy { $0.contains(#""vx":0"#) })
        XCTAssertTrue(sent.last!.contains("robot.stop"))
    }

    func testASkillTheDuckDoesNotHaveIsRefusedBeforeAnythingMoves() async throws {
        let duck = FakeRobot()
        duck.skillsJSON = #"{"skills":[{"name":"kick_left"}],"built_in":["sit_toggle"]}"#
        let p = try RobotPlan(plan([
            ("walk", ["action": "walk_forward"]),
            ("roll", ["action": "roll"]),
        ]))
        do {
            _ = try await RobotPlanRunner.run(p, on: duck, interval: 0.1, sleep: Self.noWait)
            XCTFail("ran")
        } catch let r as RobotPlanRunner.Refusal {
            XCTAssertEqual(r, .missingSkills(["roulade"], has: ["kick_left", "sit_toggle"]))
            XCTAssertTrue(r.message.contains("It has kick_left, sit_toggle"))
        }
        XCTAssertFalse(duck.sent.contains { $0.contains("robot.move") })
    }

    func testARefusedSkillStopsThePlanWithRobotdsReason() async throws {
        let duck = FakeRobot()
        duck.refuseDo = "the policy is not driving — press Start on the pad"
        let p = try RobotPlan(plan([
            ("kick", ["action": "kick_left"]),
            ("walk", ["action": "walk_forward"]),
        ]))
        let outcome = try await RobotPlanRunner.run(p, on: duck, interval: 0.1, sleep: Self.noWait)
        XCTAssertEqual(outcome, .refused(beat: 0, reason: "the policy is not driving — press Start on the pad"))
        XCTAssertFalse(duck.sent.contains { $0.contains("robot.move") })
        XCTAssertTrue(duck.sent.last!.contains("robot.stop"))
    }

    func testABenchIsToldWhyBeforeASkillIsSent() async throws {
        let bench = FakeRobot(.bench)
        let p = try RobotPlan(plan([("kick", ["action": "kick_left"])]))
        do {
            _ = try await RobotPlanRunner.run(p, on: bench, interval: 0.1, sleep: Self.noWait)
            XCTFail("ran")
        } catch let r as RobotPlanRunner.Refusal {
            guard case .outOfReach(_, .bench) = r else { return XCTFail("\(r)") }
        }
        XCTAssertTrue(bench.sent.isEmpty)
    }

    func testACancelledRunStillSendsAStop() async throws {
        let duck = FakeRobot()
        let p = try RobotPlan(plan([("walk", ["action": "walk_forward"])]))
        let task = Task {
            try await RobotPlanRunner.run(p, on: duck, interval: 0.1,
                                          sleep: { _ in try await Task.sleep(nanoseconds: 5_000_000) })
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        _ = await task.result
        XCTAssertTrue(duck.sent.last!.contains("robot.stop"))
    }

    func testSkillsAndAnswersReadAsRobotdWritesThem() {
        let skills = RobotSkills.read(DuckReply(id: 1, result: Data(
            #"{"skills":[{"name":"kick_left","duration":0.5}],"built_in":["ground_pick","sit_toggle"]}"#.utf8),
            failure: nil))
        XCTAssertEqual(skills, RobotSkills(names: ["kick_left", "ground_pick", "sit_toggle"],
                                           seconds: ["kick_left": 0.5]))
        let no = RobotIntentAnswer.read(DuckReply(id: 1, result: Data(
            #"{"accepted":false,"reason":"this robot has no voice"}"#.utf8), failure: nil))
        XCTAssertEqual(no, RobotIntentAnswer(accepted: false, reason: "this robot has no voice"))
    }
}
