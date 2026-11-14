import XCTest
import DuckKit
@testable import StudioKit

/// Roadmap item 4: `.drive` and `.plan` from a planner, with the arbiter's clamps
/// (brains-layer.md 3.2, 3.3, 6.5). Each test names the clamp or refusal it holds, and fails
/// if that one is taken out.
final class PlannerLegTests: XCTestCase {

    // MARK: fakes

    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = Date(timeIntervalSince1970: 1_000)
        func now() -> Date { lock.lock(); defer { lock.unlock() }; return t }
        func advance(_ s: TimeInterval) { lock.lock(); t += s; lock.unlock() }
    }

    /// A robotd stand-in that records every call and answers as robotd does.
    private final class Duck: DuckPeer, @unchecked Sendable {
        let identity = DuckIdentity(name: "Pip", kind: .real)
        let transportKind: DuckTransportKind = .bridge
        let reach = DuckMethod.reach(for: .bridge)
        var skillsJSON = #"{"skills":[{"name":"kick_left","duration":0.5}],"built_in":["sit_toggle"]}"#
        private let lock = NSLock()
        private var _sent: [DuckCall] = []
        var sent: [DuckCall] { lock.lock(); defer { lock.unlock() }; return _sent }

        var movingTwists: [DuckDrive.Twist] {
            sent.compactMap { if case .move(let t) = $0, t.vx != 0 || t.vy != 0 || t.vyaw != 0 { return t } else { return nil } }
        }
        var moves: Int { sent.filter { if case .move = $0 { return true } else { return false } }.count }

        private func record(_ c: DuckCall) { lock.lock(); _sent.append(c); lock.unlock() }

        func call(_ c: DuckCall) async throws -> DuckReply {
            try vet(c, asNotification: false)
            record(c)
            let body: String
            if case .skills = c { body = skillsJSON } else { body = #"{"accepted":true}"# }
            return DuckReply(id: 1, result: Data(body.utf8), failure: nil)
        }

        func notify(_ c: DuckCall) async throws {
            try vet(c, asNotification: true)
            record(c)
        }

        nonisolated func states() -> AsyncStream<DuckState> { AsyncStream { $0.finish() } }
    }

    /// A source that always wants to walk forward at the stick limit, 48 rows a chunk.
    private final class Forward: DreamRows, @unchecked Sendable {
        private let lock = NSLock()
        private var _acts = 0, _ended = false, _prompts: [String] = []
        var acts: Int { lock.lock(); defer { lock.unlock() }; return _acts }
        var ended: Bool { lock.lock(); defer { lock.unlock() }; return _ended }
        var prompts: [String] { lock.lock(); defer { lock.unlock() }; return _prompts }
        func act(checkpoint: String, prompt: String, frames: [String: [String]],
                 state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
            lock.withLock { _acts += 1; _prompts.append(prompt) }
            return DuckDream.Chunk(rows: Array(repeating: DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0), count: 48),
                                   sessionID: "s")
        }
        func end() async { lock.withLock { _ended = true } }
    }

    private static let planner = PlannerInfo(id: "test.planner", modelVersion: "1", label: "Test",
                                             runsOn: .thisPhone, key: .none, decisionDeadline: .seconds(1))

    private static let allowed = AllowedDecisions(kinds: [.walk, .turn, .skill], skills: ["kick_left", "roulade"])
        .allowing(drive: [.dream1]).allowingPlans()

    private static let fresh = PlannerLeg.Reading(odomAgeMs: 20, pose: .init(x: 0, y: 0, yaw: 0))

    private func boundGate(_ allowed: AllowedDecisions = PlannerLegTests.allowed,
                           venue: BrainVenue = .practice, remote: Bool = false) -> GateHolder {
        var gate = DuckEnvelopeGate()
        gate.bind(.init(providerId: Self.planner.id, modelVersion: "1", venue: venue, mode: .auto,
                        remote: remote, allowed: allowed))
        return GateHolder(gate)
    }

    private func decided(_ d: DuckDecision) -> Decided {
        Decided(decision: d, why: "test", provider: Self.planner, latency: .milliseconds(1))
    }

    private func drive(_ d: DuckDecision, allowed: AllowedDecisions = PlannerLegTests.allowed,
                       secondsLeft: Double = 60, sources: [ActionSourceID] = [.dream1],
                       gate: GateHolder? = nil, reading: PlannerLeg.Reading = PlannerLegTests.fresh,
                       duck: Duck, rows: Forward, clock: Clock) async -> PlannerLeg.Ending {
        let start = clock.now()
        return await PlannerLeg.drive(
            d, allowed: allowed, secondsLeft: secondsLeft,
            sources: sources.map { PlannerLeg.DriveSource(id: $0, checkpoint: "m", rows: rows) },
            gate: gate ?? boundGate(allowed), runStart: start, on: duck, frames: { ["F"] },
            reading: { reading }, sleep: { clock.advance($0) }, now: { clock.now() })
    }

    // MARK: the wire and the closed set

    func testDriveAndPlanAreOffByDefault() throws {
        for duck in [DuckIdentity.Kind.sim, .real] {
            for runsOn in [RunsOn.thisPhone, .hosted(vendor: "anthropic"), .lanComputer] {
                let set = AllowedDecisions.forDuck(duck, runsOn: runsOn, robotSkills: ["kick_left"])
                XCTAssertFalse(set.kinds.contains(.drive))
                XCTAssertFalse(set.kinds.contains(.plan))
                XCTAssertTrue(set.sources.isEmpty)
                XCTAssertFalse(HostedPlanner.tools(for: set).map(\.name).contains("drive"))
                XCTAssertFalse(HostedPlanner.tools(for: set).map(\.name).contains("plan"))
                let local = LocalDecisionPrompt.tools(for: set).compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
                XCTAssertFalse(local.contains("drive") || local.contains("plan"))
                XCTAssertFalse(LocalDecisionPrompt.instructions(for: set).contains(#""kind":"drive""#))
            }
        }
        // A drive with nowhere to drive is not allowed at all.
        XCTAssertFalse(AllowedDecisions(kinds: [.drive]).kinds.contains(.drive))
    }

    func testADisallowedKindIsRefusedByNameAndBecomesAnAsk() async throws {
        let set = AllowedDecisions.forDuck(.real, runsOn: .thisPhone, robotSkills: ["kick_left"])
        let driveJSON = Data(#"{"kind":"drive","source":"dreamlabs.dream-1","goal":"go","seconds":3}"#.utf8)
        let planJSON = Data(#"{"kind":"plan","beats":[{"action":"walk_forward","speed":"slow","seconds":1}]}"#.utf8)
        XCTAssertThrowsError(try set.read(driveJSON)) { XCTAssertEqual($0 as? AllowedDecisions.Refusal, .kindNotAllowed(.drive)) }
        XCTAssertThrowsError(try set.read(planJSON)) { XCTAssertEqual($0 as? AllowedDecisions.Refusal, .kindNotAllowed(.plan)) }
        guard case .ask = set.readOrAsk(driveJSON), case .ask = set.readOrAsk(planJSON) else {
            return XCTFail("outside the set is an ask")
        }
        // A hosted model that calls a tool it was not given gets an ask, never the drive.
        let (d, _) = HostedPlanner.decision(
            from: [.init(name: "drive", arguments: Data(#"{"source":"dreamlabs.dream-1","goal":"go","seconds":3,"why":"x"}"#.utf8))],
            allowed: set)
        guard case .ask = d else { return XCTFail("expected an ask, got \(d)") }
        // And a leg handed a disallowed decision moves nothing.
        let duck = Duck(), rows = Forward(), clock = Clock()
        let ending = await drive(.drive(source: .dream1, goal: "go", seconds: 3), allowed: set,
                                 duck: duck, rows: rows, clock: clock)
        XCTAssertEqual(ending, .refused(AllowedDecisions.Refusal.kindNotAllowed(.drive).says))
        XCTAssertTrue(duck.sent.isEmpty)
        XCTAssertEqual(rows.acts, 0)
    }

    func testAnUnknownSourceIsRefused() async throws {
        // Outside the kit's closed set: refused by the reader.
        let openpi = Data(#"{"kind":"drive","source":"openpi.pi0","goal":"go","seconds":3}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(DuckDecision.self, from: openpi)) {
            XCTAssertEqual($0 as? DuckDecision.WireError, .unknownSource("openpi.pi0"))
        }
        XCTAssertThrowsError(try Self.allowed.read(openpi)) {
            XCTAssertEqual($0 as? AllowedDecisions.Refusal, .unknownSource("openpi.pi0"))
        }
        // Inside the kit's set but not this run's: refused by the run.
        let phone = Data(#"{"kind":"drive","source":"phone.ducknet-s1","goal":"go","seconds":3}"#.utf8)
        XCTAssertThrowsError(try Self.allowed.read(phone)) {
            XCTAssertEqual($0 as? AllowedDecisions.Refusal, .unknownSource("phone.ducknet-s1"))
        }
        // Allowed, but the app has no such source ready: the leg refuses before anything moves.
        let duck = Duck(), rows = Forward(), clock = Clock()
        let ending = await drive(.drive(source: .dream1, goal: "go", seconds: 3), sources: [.phoneDriver],
                                 duck: duck, rows: rows, clock: clock)
        XCTAssertEqual(ending, .refused(PlannerLeg.Words.noSuchSource("dreamlabs.dream-1")))
        XCTAssertTrue(duck.sent.isEmpty)
        XCTAssertEqual(rows.acts, 0)
    }

    func testEmptyGoalsAndNonPositiveSecondsAreRefusedNotGuessed() {
        XCTAssertEqual(try? Self.allowed.admit(.drive(source: .dream1, goal: "  ", seconds: 3)).get(), nil)
        XCTAssertEqual(try? Self.allowed.admit(.drive(source: .dream1, goal: "go", seconds: 0)).get(), nil)
        XCTAssertEqual(try? Self.allowed.admit(.drive(source: .dream1, goal: "go", seconds: -4)).get(), nil)
        XCTAssertThrowsError(try JSONDecoder().decode(DuckDecision.self, from: Data(
            #"{"kind":"plan","beats":[{"action":"make_sound","speed":"slow","seconds":1}]}"#.utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(DuckDecision.self, from: Data(
            #"{"kind":"plan","beats":[{"action":"walk_forward","speed":"slow","seconds":1,"vx":9}]}"#.utf8))) {
            XCTAssertEqual($0 as? DuckDecision.WireError, .unexpectedField("vx"))
        }
        XCTAssertThrowsError(try JSONDecoder().decode(DuckDecision.self, from: Data(#"{"kind":"plan","beats":[]}"#.utf8)))
    }

    // MARK: the clamps

    func testADrivesSecondsAreClamped() async throws {
        // The decision's own clamp, and the arbiter's on top of it for the time the run has left.
        let long = DuckDecision.drive(source: .dream1, goal: "go", seconds: 60)
        XCTAssertEqual(long.clamped().decision, .drive(source: .dream1, goal: "go", seconds: DuckDecision.maxDriveSeconds))
        XCTAssertEqual(ControlArbiter.clamp(long, secondsLeft: 60).decision,
                       .drive(source: .dream1, goal: "go", seconds: 5))
        XCTAssertEqual(ControlArbiter.clamp(long, secondsLeft: 2).decision,
                       .drive(source: .dream1, goal: "go", seconds: 2))
        XCTAssertEqual(ControlArbiter.clamp(long, secondsLeft: 60).cut, 1 - 5.0 / 60, accuracy: 1e-12)

        // The gate hands back the clamped decision, and counts it under the run rule.
        let gate = boundGate()
        let check = try await gate.confirm(decided(long), at: 0)
        XCTAssertEqual(check.decision, .drive(source: .dream1, goal: "go", seconds: 5))
        XCTAssertEqual(check.verdict, .clamped)
        XCTAssertEqual(check.rule, .run)

        // And the leg re-clamps on its own: handed the raw 60 s decision, it drives 5 s.
        let duck = Duck(), rows = Forward(), clock = Clock()
        let start = clock.now()
        let ending = await drive(long, duck: duck, rows: rows, clock: clock)
        XCTAssertEqual(ending, .done)
        XCTAssertLessThanOrEqual(duck.movingTwists.count, 51, "5 s at ten rows a second, not 60 s")
        XCTAssertGreaterThan(duck.movingTwists.count, 20)
        XCTAssertLessThanOrEqual(clock.now().timeIntervalSince(start), 5.2)
        XCTAssertTrue(rows.prompts.allSatisfy { $0 == "go" }, "the source gets the goal only")
        XCTAssertTrue(rows.ended)
        if case .stop = duck.sent.last {} else { XCTFail("ends in robot.stop") }
    }

    func testADriveWithNoTimeLeftDoesNotStart() async {
        let duck = Duck(), rows = Forward(), clock = Clock()
        let ending = await drive(.drive(source: .dream1, goal: "go", seconds: 3), secondsLeft: 0,
                                 duck: duck, rows: rows, clock: clock)
        XCTAssertEqual(ending, .refused(PlannerLeg.Words.noTimeLeft))
        XCTAssertTrue(duck.sent.isEmpty)
    }

    func testEveryDriveRowGoesThroughTheGate() async {
        // From still, the gate's rate rule eases the source's 0.3 m/s in 0.1 a row.
        let duck = Duck(), rows = Forward(), clock = Clock()
        _ = await drive(.drive(source: .dream1, goal: "go", seconds: 1), duck: duck, rows: rows, clock: clock)
        let vx = duck.movingTwists.map(\.vx)
        XCTAssertEqual(vx.prefix(3).map { ($0 * 10).rounded() / 10 }, [0.1, 0.2, 0.3])
    }

    func testASevenBeatPlanIsCutToSix() async throws {
        let seven = RobotPlanProposal(beats: (0..<7).map { i in
            RobotPlanProposal.Beat(action: i % 2 == 0 ? "walk_forward" : "turn_left", speed: "slow", seconds: 0.5)
        })
        let (six, cut) = seven.clamped()
        XCTAssertEqual(six.beats.count, RobotPlanProposal.maxBeats)
        XCTAssertEqual(six.beats, Array(seven.beats.prefix(6)), "cut from the end, nothing reordered")
        XCTAssertEqual(cut, 1.0 / 7, accuracy: 1e-12)
        XCTAssertEqual(try seven.robotPlan(request: "r").beats.count, 6)

        // The leg runs six beats, never the seventh.
        let duck = Duck(), clock = Clock()
        let began = Began()
        let ending = await PlannerLeg.plan(.plan(seven), allowed: Self.allowed, secondsLeft: 60, request: "r",
                                           on: duck, interval: 0.1, sleep: { clock.advance($0) },
                                           event: { if case .began(let i, _) = $0 { await began.add(i) } })
        XCTAssertEqual(ending, .done)
        let indices = await began.indices
        XCTAssertEqual(indices, Array(0..<6))
    }

    func testAPlansWalkOverFiveSecondsIsClamped() async throws {
        let long = RobotPlanProposal(beats: [
            .init(action: "walk_forward", speed: "normal", seconds: 4),
            .init(action: "turn_left", speed: "normal", seconds: 4),
            .init(action: "kick_left", speed: "normal", seconds: 0),
        ])
        let (cut, share) = long.clamped()
        XCTAssertEqual(cut.beats, [.init(action: "walk_forward", speed: "normal", seconds: 4),
                                   .init(action: "turn_left", speed: "normal", seconds: 1)],
                       "the turn is shortened to the budget and the plan ends there: no kick")
        XCTAssertEqual(share, 1 - 5.0 / 8, accuracy: 1e-12, "3 of the 8 seconds asked for were cut")
        // One long beat alone is held to 5 s.
        XCTAssertEqual(RobotPlanProposal(beats: [.init(action: "walk_forward", speed: "slow", seconds: 30)])
            .clamped().proposal.beats.first?.seconds, 5)
        // The run's time left is a tighter budget when it is shorter.
        XCTAssertEqual(ControlArbiter.clamp(.plan(long), secondsLeft: 2).decision,
                       .plan(RobotPlanProposal(beats: [.init(action: "walk_forward", speed: "normal", seconds: 2)])))

        // On the wire: 5 s of moves at ten a second, then the stop. No robot.do.
        let duck = Duck(), clock = Clock()
        let ending = await PlannerLeg.plan(.plan(long), allowed: Self.allowed, secondsLeft: 60, request: "r",
                                           on: duck, interval: 0.1, sleep: { clock.advance($0) })
        XCTAssertEqual(ending, .done)
        XCTAssertEqual(duck.movingTwists.count, 50)
        XCTAssertFalse(duck.sent.contains { if case .doSkill = $0 { return true } else { return false } })
    }

    func testAPlansSkillBeatsAreSkillsForTheClosedSetAndTheGate() async throws {
        let roll = RobotPlanProposal(beats: [.init(action: "roll")])
        let noSkills = AllowedDecisions(kinds: [.walk]).allowingPlans()
        XCTAssertEqual(noSkills.admit(.plan(roll)), .failure(.unknownSkill("roulade")))
        XCTAssertEqual(Self.allowed.admit(.plan(roll)), .success(.plan(roll)))
        // The hosted tool offers only the skill beats this run allows.
        let tool = try XCTUnwrap(HostedPlanner.tools(for: noSkills).first { $0.name == "plan" })
        guard case .object(let props) = tool.schema["properties"], case .object(let beats) = props["beats"],
              case .object(let items) = beats["items"], case .object(let ip) = items["properties"],
              case .object(let action) = ip["action"], case .array(let names) = action["enum"] else {
            return XCTFail("plan tool shape")
        }
        XCTAssertEqual(names, RobotPlanProposal.timedActions.map { .string($0) })
        // A hosted planner on a real duck gets no skills, in a plan or out of one.
        let gate = boundGate(Self.allowed, venue: .real, remote: true)
        let check = try await gate.confirm(decided(.plan(roll)), at: 0)
        XCTAssertEqual(check.verdict, .held)
        XCTAssertEqual(check.rule, .allowlist)
        // Each new skill in a plan asks for a Go, like a `.skill` would.
        let local = boundGate()
        let first = try await local.check(decided(.plan(roll)), at: 0)
        XCTAssertTrue(first.confirmations.contains(.newSkill("roulade")))
        XCTAssertTrue(first.confirmations.contains(.newKind(.plan)))
    }

    func testRobotPlanRunnersRefusalBeforeAnythingMovesStillFires() async {
        // Allowed by the run, but this duck has no roll: the runner refuses before the walk.
        let duck = Duck(), clock = Clock()
        let p = DuckDecision.plan(RobotPlanProposal(beats: [.init(action: "walk_forward", speed: "slow", seconds: 1),
                                                           .init(action: "roll")]))
        let ending = await PlannerLeg.plan(p, allowed: Self.allowed, secondsLeft: 60, request: "r",
                                           on: duck, interval: 0.1, sleep: { clock.advance($0) })
        XCTAssertEqual(ending, .refused(RobotPlanRunner.Refusal.missingSkills(["roulade"], has: ["kick_left", "sit_toggle"]).message))
        XCTAssertEqual(duck.moves, 0, "nothing moved")
    }

    // MARK: control comes back

    func testAGateCutReturnsControlAndCutsTheRestOfTheRun() async throws {
        let duck = Duck(), rows = Forward(), clock = Clock()
        let gate = boundGate()
        let start = clock.now()
        // Odometry says the duck is already off the mat: the first row is cut.
        let ending = await drive(.drive(source: .dream1, goal: "go", seconds: 5), gate: gate,
                                 reading: .init(odomAgeMs: 20, pose: .init(x: 1.2, y: 0, yaw: 0)),
                                 duck: duck, rows: rows, clock: clock)
        XCTAssertEqual(ending, .gateCut(.keepIn))
        XCTAssertTrue(duck.movingTwists.isEmpty, "the cut row was never sent")
        if case .stop = duck.sent.last {} else { XCTFail("ends in robot.stop") }
        XCTAssertTrue(rows.ended, "the source's seat is given back")
        XCTAssertLessThan(clock.now().timeIntervalSince(start), 1, "it came back at once, not at the time limit")
        // Back with the planner, a motion decision is cut; a stop still passes.
        let next = try await gate.confirm(decided(.walk(forwardM: 0.2, sideM: 0)), at: 1)
        XCTAssertEqual(next.verdict, .cut)
        let stop = try await gate.check(decided(.stop(reason: "done")), at: 1)
        XCTAssertEqual(stop.verdict, .pass)
    }

    func testStaleOdometryHoldsThenCutsTheDrive() async {
        let duck = Duck(), rows = Forward(), clock = Clock()
        let ending = await drive(.drive(source: .dream1, goal: "go", seconds: 5), reading: .none,
                                 duck: duck, rows: rows, clock: clock)
        XCTAssertEqual(ending, .gateCut(.stale))
        XCTAssertTrue(duck.movingTwists.isEmpty, "held rows are zero twists")
    }

    func testAnUnboundGateRefusesTheDrive() async {
        let duck = Duck(), rows = Forward(), clock = Clock()
        let ending = await drive(.drive(source: .dream1, goal: "go", seconds: 3),
                                 gate: GateHolder(DuckEnvelopeGate()), duck: duck, rows: rows, clock: clock)
        XCTAssertEqual(ending, .refused(PlannerLeg.Words.gateNotBound))
        XCTAssertTrue(duck.sent.isEmpty)
    }

    func testTheDrivesSourceIsNewAndAsksForAGo() async throws {
        let gate = boundGate()
        let first = try await gate.check(decided(.drive(source: .dream1, goal: "go", seconds: 2)), at: 0)
        XCTAssertEqual(first.verdict, .held)
        XCTAssertTrue(first.confirmations.contains(.newSource("dreamlabs.dream-1")))
    }

    // MARK: what the planners are shown

    func testHostedAndLocalPlannersAreShownDriveAndPlanOnlyWhenAllowed() throws {
        let tools = HostedPlanner.tools(for: Self.allowed)
        XCTAssertEqual(Array(tools.map(\.name).suffix(2)), ["drive", "plan"])
        for tool in tools {
            let kind = try XCTUnwrap(DuckDecision.Kind(rawValue: tool.name))
            XCTAssertEqual(tool.schema["required"], .array((kind.fields + ["why"]).map { .string($0) }))
            XCTAssertEqual(tool.schema["additionalProperties"], .bool(false))
        }
        let drive = try XCTUnwrap(tools.first { $0.name == "drive" })
        guard case .object(let props) = drive.schema["properties"], case .object(let source) = props["source"] else {
            return XCTFail("drive tool shape")
        }
        XCTAssertEqual(source["enum"], .array([.string("dreamlabs.dream-1")]))

        let text = LocalDecisionPrompt.instructions(for: Self.allowed)
        XCTAssertTrue(text.contains(#""kind":"drive""#) && text.contains("dreamlabs.dream-1"))
        XCTAssertFalse(text.contains("phone.ducknet-s1"))
        XCTAssertTrue(text.contains(#""kind":"plan""#))
        let schema = LocalDecisionPrompt.schema(for: Self.allowed)
        XCTAssertEqual((schema["anyOf"] as? [[String: Any]])?.count, Self.allowed.kinds.count)

        // A local model's plan answer is read through the same closed set.
        let reading = try LocalDecisionPrompt.read(
            reply: #"{"kind":"plan","beats":[{"action":"walk_forward","speed":"fast","seconds":2}],"why":"go"}"#,
            allowed: Self.allowed)
        XCTAssertEqual(reading.decision, .plan(RobotPlanProposal(beats: [.init(action: "walk_forward", speed: "fast", seconds: 2)])))
    }

    func testTheWordsHaveNoEmDash() {
        for w in PlannerLeg.Words.all + [AllowedDecisions.Refusal.unknownSource("x").says] {
            XCTAssertFalse(w.contains("\u{2014}"), w)
        }
    }

    private actor Began {
        var indices: [Int] = []
        func add(_ i: Int) { indices.append(i) }
    }
}
