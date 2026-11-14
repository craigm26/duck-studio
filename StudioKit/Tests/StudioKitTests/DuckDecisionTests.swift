import XCTest
@testable import StudioKit

/// The decision, its wire, and the closed set (brains-layer.md 3.2).
final class DuckDecisionTests: XCTestCase {

    static let every: [DuckDecision] = [
        .skill(name: "kick_left"), .walk(forwardM: 0.5, sideM: -0.25), .turn(degrees: 90),
        .sound(name: "greet"), .ask(question: "Which ball?"), .done(reason: "at the ball"),
        .stop(reason: "asked to"),
        .drive(source: .dream1, goal: "walk to the red ball", seconds: 3),
        .plan(RobotPlanProposal(beats: [.init(action: "walk_forward", speed: "slow", seconds: 2),
                                        .init(action: "kick_left", speed: "normal", seconds: 0)])),
    ]

    func decode(_ json: String) throws -> DuckDecision {
        try JSONDecoder().decode(DuckDecision.self, from: Data(json.utf8))
    }

    func testEveryCaseRoundTrips() throws {
        XCTAssertEqual(Set(Self.every.map(\.kind)), Set(DuckDecision.Kind.allCases))
        for d in Self.every {
            let data = try JSONEncoder().encode(d)
            XCTAssertEqual(try JSONDecoder().decode(DuckDecision.self, from: data), d)
        }
    }

    func testTheWireIsFlatAndSnakeCase() throws {
        XCTAssertEqual(try decode(#"{"kind":"walk","forward_m":0.5,"side_m":0}"#),
                       .walk(forwardM: 0.5, sideM: 0))
        let obj = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(DuckDecision.walk(forwardM: 1, sideM: 2))) as? [String: Any]
        XCTAssertEqual(Set((obj ?? [:]).keys), ["kind", "forward_m", "side_m"])
    }

    /// `drive` and `plan` are decisions now (roadmap item 4). `look_at` and `walk_to` still are not.
    func testTheLaterCasesAreNotDecisions() {
        for kind in ["look_at", "lookAt", "walk_to", "move"] {
            XCTAssertThrowsError(try decode(#"{"kind":"\#(kind)"}"#)) { error in
                XCTAssertEqual(error as? DuckDecision.WireError, .unknownKind(kind))
            }
        }
    }

    func testTheReaderRefusesRatherThanRepairs() {
        XCTAssertThrowsError(try decode(#"{"kind":"turn","degrees":90,"speed":"fast"}"#)) {
            XCTAssertEqual($0 as? DuckDecision.WireError, .unexpectedField("speed"))
        }
        XCTAssertThrowsError(try decode(#"{"kind":"walk","forward_m":0.5}"#)) {
            XCTAssertEqual($0 as? DuckDecision.WireError, .missingField("side_m"))
        }
        XCTAssertThrowsError(try decode(#"{"kind":"turn","degrees":"ninety"}"#)) {
            XCTAssertEqual($0 as? DuckDecision.WireError, .wrongType("degrees"))
        }
        XCTAssertThrowsError(try decode(#"{"name":"kick_left"}"#)) {
            XCTAssertEqual($0 as? DuckDecision.WireError, .missingField("kind"))
        }
        let long = String(repeating: "a", count: DuckDecision.maxTextLength + 1)
        XCTAssertThrowsError(try decode(#"{"kind":"ask","question":"\#(long)"}"#)) {
            XCTAssertEqual($0 as? DuckDecision.WireError, .textTooLong("question"))
        }
    }

    func testOneDecisionsLimitsComeFromTheDriveLimits() {
        XCTAssertEqual(DuckDecision.maxSeconds, 5)
        XCTAssertEqual(DuckDecision.maxForwardM, 1.5, accuracy: 1e-12)
        XCTAssertEqual(DuckDecision.maxTurnDegrees, 5 * 180 / .pi, accuracy: 1e-9)
        let (walk, cut) = DuckDecision.walk(forwardM: 3, sideM: 0).clamped()
        XCTAssertEqual(walk, .walk(forwardM: 1.5, sideM: 0))
        XCTAssertEqual(cut, 0.5, accuracy: 1e-12)
        XCTAssertEqual(DuckDecision.turn(degrees: 45).clamped().cut, 0)
        XCTAssertEqual(DuckDecision.turn(degrees: -1000).clamped().decision,
                       .turn(degrees: -DuckDecision.maxTurnDegrees))
    }

    // MARK: the closed set

    func testStopDoneAndAskAreAlwaysAllowed() {
        let none = AllowedDecisions(kinds: [])
        XCTAssertEqual(none.kinds, [.stop, .done, .ask])
        XCTAssertEqual(try none.read(Data(#"{"kind":"stop","reason":"x"}"#.utf8)), .stop(reason: "x"))
    }

    func testThePracticeDuckOnlyWalksAndTurns() {
        let set = AllowedDecisions.forDuck(.sim, runsOn: .thisPhone)
        XCTAssertEqual(set.kinds, [.walk, .turn, .stop, .done, .ask])
        XCTAssertTrue(set.skills.isEmpty)
        XCTAssertThrowsError(try set.read(Data(#"{"kind":"sound","name":"greet"}"#.utf8))) {
            XCTAssertEqual($0 as? AllowedDecisions.Refusal, .kindNotAllowed(.sound))
        }
    }

    func testARealDuckOffersSkillsOnlyToAPlannerOnThisPhone() {
        let local = AllowedDecisions.forDuck(.real, runsOn: .thisPhone, robotSkills: ["kick_left", "sit_toggle"])
        XCTAssertEqual(local.skills, ["kick_left"])
        XCTAssertTrue(local.kinds.contains(.skill))
        XCTAssertTrue(local.sounds.contains("greet"))
        let hosted = AllowedDecisions.forDuck(.real, runsOn: .hosted(vendor: "anthropic"), robotSkills: ["kick_left"])
        XCTAssertFalse(hosted.kinds.contains(.skill))
        XCTAssertTrue(hosted.skills.isEmpty)
    }

    func testANameOutsideTheSetIsRefusedByName() {
        let set = AllowedDecisions(kinds: [.skill, .sound], skills: ["kick_left"], sounds: ["greet"])
        XCTAssertThrowsError(try set.read(Data(#"{"kind":"skill","name":"backflip"}"#.utf8))) {
            XCTAssertEqual($0 as? AllowedDecisions.Refusal, .unknownSkill("backflip"))
        }
        XCTAssertThrowsError(try set.read(Data(#"{"kind":"sound","name":"moo"}"#.utf8))) {
            XCTAssertEqual($0 as? AllowedDecisions.Refusal, .unknownSound("moo"))
        }
        XCTAssertThrowsError(try set.read(Data("not json".utf8))) {
            XCTAssertEqual($0 as? AllowedDecisions.Refusal, .notADecision)
        }
    }

    func testOutsideTheSetBecomesAnAskNeverAGuess() {
        let set = AllowedDecisions(kinds: [.walk])
        guard case .ask(let q) = set.readOrAsk(Data(#"{"kind":"look_at","x":1}"#.utf8)) else {
            return XCTFail("expected an ask")
        }
        XCTAssertTrue(q.contains("look_at"))
        XCTAssertEqual(set.readOrAsk(Data(#"{"kind":"walk","forward_m":1,"side_m":0}"#.utf8)),
                       .walk(forwardM: 1, sideM: 0))
    }

    func testAStoredSetCannotDropStop() throws {
        let set = try JSONDecoder().decode(AllowedDecisions.self, from: Data(#"{"kinds":["walk"]}"#.utf8))
        XCTAssertTrue(set.kinds.isSuperset(of: AllowedDecisions.alwaysAllowed))
    }

    func testRefusalWordsHaveNoEmDash() {
        let all: [AllowedDecisions.Refusal] = [.notADecision, .unknownKind("x"), .kindNotAllowed(.skill),
                                               .unknownSkill("x"), .unknownSound("x"), .badField("x")]
        for r in all { XCTAssertFalse(r.says.contains("\u{2014}"), r.says) }
    }

    // MARK: a planner

    struct Fixed: Planner {
        let info = PlannerInfo(id: "test.fixed", modelVersion: "1", label: "Test", runsOn: .thisPhone,
                               key: .none, decisionDeadline: .seconds(1))
        func decide(_ ask: PlannerAsk) async throws -> Decided {
            let d = ask.allowed.readOrAsk(Data(#"{"kind":"walk","forward_m":0.3,"side_m":0}"#.utf8))
            return Decided(decision: d, why: ask.goal, provider: info, latency: .milliseconds(3))
        }
    }

    func testAPlannerAnswersInsideItsSet() async throws {
        let walking = PlannerAsk(goal: "go", state: DuckStateSnapshot(), allowed: .forDuck(.sim, runsOn: .thisPhone))
        let got = try await Fixed().decide(walking)
        XCTAssertEqual(got.decision, .walk(forwardM: 0.3, sideM: 0))
        let soundOnly = PlannerAsk(goal: "go", state: DuckStateSnapshot(), allowed: AllowedDecisions(kinds: [.sound]))
        guard case .ask = try await Fixed().decide(soundOnly).decision else { return XCTFail("expected an ask") }
    }
}
