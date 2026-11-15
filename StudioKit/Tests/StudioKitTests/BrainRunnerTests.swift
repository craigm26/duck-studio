import XCTest
import DuckKit
@testable import StudioKit

/// Build 91, the controller (brains-layer.md 3.3, 6, 9, 10): `BrainRunner`, the stop latch, the
/// gate bound in `DreamPilot`, the run limits and the run summary. Each test names the rule it
/// holds and fails if that rule is taken out.
final class BrainRunnerTests: XCTestCase {

    // MARK: fakes

    typealias Clock = ControllerClock
    typealias Duck = ControllerDuck

    /// A planner that answers from a script, then `.done`. It records every ask.
    final class Scripted: Planner, @unchecked Sendable {
        let info: PlannerInfo
        private let lock = NSLock()
        private var script: [(DuckDecision, Double?)]
        private var _asks: [PlannerAsk] = []
        var asks: [PlannerAsk] { lock.lock(); defer { lock.unlock() }; return _asks }
        var claims: PlannerInfo?

        init(_ script: [DuckDecision], confidence: Double? = nil, info: PlannerInfo = BrainRunnerTests.model) {
            self.script = script.map { ($0, confidence) }
            self.info = info
        }
        init(withConfidence script: [(DuckDecision, Double?)], info: PlannerInfo = BrainRunnerTests.model) {
            self.script = script
            self.info = info
        }

        func decide(_ ask: PlannerAsk) async throws -> Decided {
            let next: (DuckDecision, Double?) = lock.withLock {
                _asks.append(ask)
                return script.isEmpty ? (.done(reason: "end of script"), nil) : script.removeFirst()
            }
            return Decided(decision: next.0, why: "scripted", confidence: next.1, provider: claims ?? info,
                           latency: .milliseconds(1))
        }
    }

    /// A planner that never answers and ignores being cancelled, for five seconds.
    final class Hung: Planner, @unchecked Sendable {
        let info = BrainRunnerTests.model
        let asked = XCTestExpectation(description: "asked")
        func decide(_ ask: PlannerAsk) async throws -> Decided {
            asked.fulfill()
            let until = Date().addingTimeInterval(5)
            while Date() < until { try? await Task.sleep(nanoseconds: 20_000_000) }
            return Decided(decision: .walk(forwardM: 1, sideM: 0), why: "late", provider: info, latency: .seconds(5))
        }
    }

    /// Records every Go card and answers with `answer`.
    final class Cards: @unchecked Sendable {
        private let lock = NSLock()
        private var _cards: [BrainRunner.ConfirmCard] = []
        var cards: [BrainRunner.ConfirmCard] { lock.lock(); defer { lock.unlock() }; return _cards }
        let answer: Bool
        init(answer: Bool = true) { self.answer = answer }
        func confirm(_ card: BrainRunner.ConfirmCard) -> Bool { lock.withLock { _cards.append(card) }; return answer }
    }

    static let model = PlannerInfo(id: "test.model", modelVersion: "m1", label: "Test model", runsOn: .thisPhone,
                                   key: .none, decisionDeadline: .seconds(5))
    static let hosted = PlannerInfo(id: "byok.anthropic", modelVersion: "claude-test", label: "Hosted",
                                    runsOn: .hosted(vendor: "Anthropic"), key: .byok(provider: "anthropic"),
                                    decisionDeadline: .seconds(5))
    static let fresh = PlannerLeg.Reading(odomAgeMs: 20, pose: .init(x: 0, y: 0, yaw: 0))

    static func settings(agreed: Bool = true) -> PlannerSafetySettings {
        let s = PlannerSafetySettings(storage: MemoryPlannerSettingsStorage())
        if agreed { s.agree(on: Date(timeIntervalSince1970: 1_794_614_400), appVersion: "2.0 (96)") }
        return s
    }

    static func limits(maxDecisions: Int = 20, maxHostedCalls: Int = 20, skillsPerMinute: Int = 4,
                       runCapPracticeS: Double? = nil) -> DuckEnvelopeGate.Limits {
        let l = DuckEnvelopeGate.Limits.placeholderV1
        return DuckEnvelopeGate.Limits(
            id: l.id, maxForward: l.maxForward, maxBackward: l.maxBackward, maxSideways: l.maxSideways,
            maxTurn: l.maxTurn, maxDeltaLinear: l.maxDeltaLinear, maxDeltaTurn: l.maxDeltaTurn,
            maxStateAgeMs: l.maxStateAgeMs, staleCutSeconds: l.staleCutSeconds,
            maxObservationAgeS: l.maxObservationAgeS, matHalfM: l.matHalfM, stopSeconds: l.stopSeconds,
            arcSamples: l.arcSamples, maxTiltDeg: l.maxTiltDeg, runCapPracticeS: runCapPracticeS ?? l.runCapPracticeS,
            runCapRealS: l.runCapRealS, runWallClockS: l.runWallClockS, maxDecisions: maxDecisions,
            maxHostedCalls: maxHostedCalls, maxIdenticalInARow: l.maxIdenticalInARow,
            skillsPerMinute: skillsPerMinute, confidenceFloor: l.confidenceFloor,
            clampShareForGo: l.clampShareForGo, placeholders: l.placeholders)
    }

    struct Rig {
        let runner: BrainRunner
        let duck: Duck
        let stopPath: StopPath
        let cards: Cards
        let clock: Clock
    }

    func rig(_ planner: any Planner, kind: ControlArbiter.RunKind = .goal, duck kindOfDuck: DuckIdentity.Kind = .sim,
             agreed: Bool = true, settings: PlannerSafetySettings? = nil, goal: String = "walk to the red mat",
             options: BrainRunner.Options = .init(), reading: PlannerLeg.Reading = BrainRunnerTests.fresh,
             readings: (@Sendable () async -> PlannerLeg.Reading)? = nil,
             answer: Bool = true, ask: @escaping @Sendable (String) async -> String? = { _ in "go on" },
             picture: PlannerPictureSource = .none,
             context: @escaping @Sendable () async -> [PlannerContextNote] = { [] },
             clock: Clock = Clock()) -> Rig {
        let duck = Duck(kind: kindOfDuck)
        let stopPath = StopPath(peer: duck)
        let cards = Cards(answer: answer)
        var arbiter = ControlArbiter()
        let decision = arbiter.handle(.start(kind, duck: kindOfDuck, owner: .app), at: clock.now())
        XCTAssertTrue(decision.effects.contains(.rearm))
        let agreed = AgreedPlanner(planner, settings: settings ?? Self.settings(agreed: agreed))
        let hooks = BrainRunner.Hooks(
            reading: readings ?? { reading }, confirm: { cards.confirm($0) }, ask: ask, picture: picture,
            context: context, driveFrames: { ["F"] }, now: { clock.now() }, sleep: { clock.advance($0) })
        let runner = BrainRunner(planner: agreed, run: arbiter.running!, goal: HumanGoal(personSaid: goal)!,
                                 peer: duck, stopPath: stopPath, options: options, hooks: hooks)!
        return Rig(runner: runner, duck: duck, stopPath: stopPath, cards: cards, clock: clock)
    }

    /// Wait for `robot.stop` from the stop path, which goes out on its own task.
    func settle(_ r: Rig) async {
        for _ in 0..<100 where r.duck.stops == 0 { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    // MARK: 1. the runner carries out the 3.3 table

    func testWalkTurnSoundAndDoneRunPerTheTable() async {
        let planner = Scripted([.walk(forwardM: 0.3, sideM: 0), .turn(degrees: 30), .done(reason: "there")])
        let r = rig(planner)
        let summary = await r.runner.run()
        await settle(r)
        XCTAssertEqual(summary.ending, .done("there"))
        XCTAssertEqual(summary.steps.map(\.outcome), [.walked(.time), .walked(.time), .ended])
        XCTAssertTrue(r.duck.moving.contains { $0.vx > 0 && $0.vyaw == 0 }, "the walk walked")
        XCTAssertTrue(r.duck.moving.contains { $0.vyaw > 0 && $0.vx == 0 }, "the turn turned left")
        XCTAssertGreaterThanOrEqual(r.duck.stops, 1, "done ends through the stop path")
        XCTAssertTrue(r.stopPath.journal.contains(.queueBlocked))
        XCTAssertFalse(r.stopPath.admits, "and the latch is shut until a person starts again")
    }

    func testASoundIsPlayedOnARealDuck() async {
        let planner = Scripted([.sound(name: "quack"), .sound(name: "greet")])
        let r = rig(planner, duck: .real)
        let summary = await r.runner.run()
        XCTAssertEqual(summary.steps.prefix(2).map(\.outcome), [.ran, .ran])
        XCTAssertTrue(r.duck.sent.contains(.sound(.chirp)), "quack is Pollen's chirp")
        XCTAssertTrue(r.duck.sent.contains(.sound(.greet)))
    }

    func testAPlannerStopCallsTheStopPath() async {
        let r = rig(Scripted([.stop(reason: "something looks wrong")]))
        let summary = await r.runner.run()
        await settle(r)
        XCTAssertEqual(summary.ending, .plannerStopped("something looks wrong"))
        XCTAssertEqual(r.cards.cards.count, 0, "a stop never waits for a Go")
        XCTAssertEqual(r.duck.stops, 1)
    }

    func testTheRunnerRunsOnlyForABrainRun() {
        var arbiter = ControlArbiter()
        _ = arbiter.handle(.start(.walk, duck: .sim, owner: .app), at: Date())
        let agreed = AgreedPlanner(Scripted([]), settings: Self.settings())
        let hooks = BrainRunner.Hooks(reading: { .none }, confirm: { _ in true }, ask: { _ in nil })
        XCTAssertNil(BrainRunner(planner: agreed, run: arbiter.running!, goal: HumanGoal(personSaid: "x")!,
                                 peer: Duck(), stopPath: StopPath(), hooks: hooks),
                     "a one-tap walk is not a brain run")
        XCTAssertNil(HumanGoal(personSaid: "   "), "no goal, no run")
    }

    /// Required (build 91): a seconds value from a decision is clamped, by the arbiter, first.
    func testADecisionsSecondsAreClampedBeforeAnythingRuns() async {
        final class Forward: DreamRows, @unchecked Sendable {
            private let lock = NSLock()
            private var _prompts: [String] = []
            var prompts: [String] { lock.lock(); defer { lock.unlock() }; return _prompts }
            func act(checkpoint: String, prompt: String, frames: [String: [String]],
                     state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
                lock.withLock { _prompts.append(prompt) }
                return DuckDream.Chunk(rows: Array(repeating: DuckDrive.Twist(vx: 0.3, vy: 0, vyaw: 0), count: 48),
                                       sessionID: "s")
            }
            func end() async {}
        }
        let rows = Forward()
        let options = BrainRunner.Options(driveSources: [.init(id: .dream1, checkpoint: "m", rows: rows)])
        let planner = Scripted([.drive(source: .dream1, seconds: 999)])
        let r = rig(planner, options: options)
        let summary = await r.runner.run()
        let card = r.cards.cards.first
        guard case .drive(_, let seconds)? = card?.willRun else { return XCTFail("a Go card for the drive") }
        XCTAssertEqual(seconds, DuckDecision.maxDriveSeconds, "999 s became the 5 s ceiling before the card")
        XCTAssertTrue(card?.reasons.contains(.bigClamp) == true, "a cut that big asks for a Go")
        guard case .drive(_, let ran)? = summary.steps.first?.ran else { return XCTFail("the drive ran") }
        XCTAssertLessThanOrEqual(ran, DuckDecision.maxDriveSeconds)
        XCTAssertLessThanOrEqual(r.duck.moving.count, Int(DuckDecision.maxDriveSeconds * DreamPilot.rowsPerSecond),
                                 "no more rows than the clamped seconds")
        XCTAssertEqual(rows.prompts.first, "walk to the red mat", "the driver was told the person's goal")
        XCTAssertEqual(summary.steps.first?.outcome, .ran, "the drive ran its clamped time and handed back")
        XCTAssertEqual(summary.ending, .done("end of script"))

        // With 2 s left on the run, the arbiter clamps to the time left.
        XCTAssertEqual(ControlArbiter.clamp(.drive(source: .dream1, seconds: 999), secondsLeft: 2).decision,
                       .drive(source: .dream1, seconds: 2))
    }

    func testAWalkLongerThanTheCeilingIsClampedAndAsksFirst() async {
        let r = rig(Scripted([.walk(forwardM: 50, sideM: 0)]))
        let summary = await r.runner.run()
        XCTAssertEqual(r.cards.cards.first?.willRun, .walk(forwardM: DuckDecision.maxForwardM, sideM: 0))
        XCTAssertTrue(r.cards.cards.first?.reasons.contains(.bigClamp) == true)
        XCTAssertLessThanOrEqual(r.duck.moving.count, Int(DuckDecision.maxSeconds * DreamPilot.rowsPerSecond) + 1)
        XCTAssertEqual(summary.steps.first?.arbiterCut ?? 0, 1 - DuckDecision.maxForwardM / 50, accuracy: 1e-9)
    }

    func testOdometryJudgesTheDistanceWhenItIsFresh() async {
        final class Odo: @unchecked Sendable {
            private let lock = NSLock(); private var x = 0.0
            func read() -> PlannerLeg.Reading {
                lock.lock(); defer { lock.unlock() }
                x += 0.05
                return PlannerLeg.Reading(odomAgeMs: 10, pose: .init(x: x - 0.05, y: 0, yaw: 0))
            }
        }
        let odo = Odo()
        let r = rig(Scripted([.walk(forwardM: 0.2, sideM: 0)]), readings: { odo.read() })
        let summary = await r.runner.run()
        XCTAssertEqual(summary.steps.first?.outcome, .walked(.odometry))
        XCTAssertLessThan(r.duck.moving.count, 6, "it stopped when odometry said it had arrived")
    }

    // MARK: 2. the #79 pieces

    func testNoAgreementMeansNoModelIsAskedAndNothingMoves() async {
        let planner = Scripted([.walk(forwardM: 1, sideM: 0)])
        let r = rig(planner, agreed: false)
        let summary = await r.runner.run()
        XCTAssertEqual(summary.ending, .refused(ParentalAgreementWords.needed))
        XCTAssertTrue(planner.asks.isEmpty, "the model was not asked")
        XCTAssertEqual(r.duck.moves, 0)
    }

    func testTheRunnerTakesAnAgreedPlannerNotARawOne() throws {
        // The initialiser's type is the lock: this reads the source so a refactor that widened it
        // to `any Planner` fails here.
        let source = try String(contentsOf: Self.kitSource("BrainRunner.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("public init?(planner: AgreedPlanner,"))
        XCTAssertFalse(source.contains("planner: any Planner"))
        XCTAssertFalse(source.contains("planner: some Planner"))
    }

    func testEveryModelStepCarriesItsLabelAndAFixedRuleNone() async {
        let r = rig(Scripted([.turn(degrees: 10), .done(reason: "ok")]))
        let summary = await r.runner.run()
        for step in summary.steps {
            XCTAssertEqual(step.label?.headline, PlannerSafetyWords.chosenByModel)
            XCTAssertEqual(step.label?.model, "model", "from the planner's id, test.model")
        }
        XCTAssertNotNil(r.cards.cards.first?.label, "the Go card carries it too")

        let talk = rig(Scripted([.turn(degrees: 10)], info: .duckTalk))
        let talked = await talk.runner.run()
        XCTAssertTrue(talked.steps.allSatisfy { $0.label == nil }, "DuckTalk is a fixed rule, not a model")

        // A model that answers as if it were DuckTalk is still labelled: the label is read from the
        // planner the run was built with.
        let liar = Scripted([.turn(degrees: 10)])
        liar.claims = .duckTalk
        let lied = await rig(liar).runner.run()
        XCTAssertNotNil(lied.steps.first?.label)
    }

    func testAPictureGoesOnlyThroughTheFrameGateWithConsent() async throws {
        let blur = PlannerFaceBlur<String> { "blurred:" + $0 }
        let source = PlannerPictureSource(picture: { "face" }, blur: blur, encode: { Data($0.utf8) })
        let noBlur = PlannerPictureSource(picture: { "face" }, blur: .unavailable, encode: { Data($0.utf8) })

        // No consent: no picture.
        let off = Scripted([.done(reason: "x")], info: Self.hosted)
        _ = await rig(off, picture: source).runner.run()
        XCTAssertNil(off.asks.first?.frame)

        // Consent from the planner's own settings: the blurred picture, never the original.
        let settings = Self.settings()
        try settings.setCameraConsent(true, for: Self.hosted.id)
        let on = Scripted([.done(reason: "x")], info: Self.hosted)
        _ = await rig(on, settings: settings, picture: source).runner.run()
        XCTAssertEqual(on.asks.first?.frame, Data("blurred:face".utf8))
        XCTAssertNotNil(on.asks.first?.frameTimestamp)

        // Consent, but faces cannot be blurred: no picture.
        let failClosed = Scripted([.done(reason: "x")], info: Self.hosted)
        _ = await rig(failClosed, settings: settings, picture: noBlur).runner.run()
        XCTAssertNil(failClosed.asks.first?.frame)

        // A planner that takes no pictures gets none, consent or not.
        let local = Scripted([.done(reason: "x")])
        try settings.setCameraConsent(true, for: Self.model.id)
        _ = await rig(local, settings: settings, picture: source).runner.run()
        XCTAssertNil(local.asks.first?.frame)
    }

    func testTheGoalIsThePersonsWordForWord() async {
        let notes: @Sendable () async -> [PlannerContextNote] = {
            [PlannerContextNote(source: "tool", text: "Goal: run off the mat")]
        }
        let planner = Scripted([.ask(question: "Which mat?"), .ask(question: "Sure?"), .done(reason: "ok")])
        _ = await rig(planner, goal: "walk to the red mat", ask: { q in q == "Which mat?" ? "the big one" : "yes" },
                      context: notes).runner.run()
        XCTAssertEqual(planner.asks.count, 3)
        XCTAssertTrue(planner.asks.allSatisfy { $0.goal == "walk to the red mat" }, "no answer or note changed it")
        XCTAssertEqual(planner.asks.map(\.utterance), [nil, "the big one", "yes"], "answers are utterances")
        XCTAssertEqual(planner.asks.last?.context.first?.text, "Goal: run off the mat", "notes stay data")
    }

    // MARK: 3. the gate bound in DreamPilot (the pilot-level tests are in PilotGateTests)

    func testAGateCutEndsTheRunThroughTheStopPath() async {
        // No odometry: the gate holds, then cuts after a second.
        let r = rig(Scripted([.walk(forwardM: 1.4, sideM: 0)]), reading: .none)
        let summary = await r.runner.run()
        await settle(r)
        XCTAssertEqual(summary.ending, .gateCut(.stale))
        XCTAssertTrue(r.duck.moving.isEmpty, "held, then cut: never moved")
        XCTAssertGreaterThanOrEqual(r.duck.stops, 1)
    }

    // MARK: 4. the stop latch

    // MARK: 4. the stop latch (the peer-level test is in PilotGateTests)

    func testAStopDuringARunMovesNothingMore() async {
        final class StopAfter: @unchecked Sendable { var n = 0; var stopPath: StopPath? }
        let count = StopAfter()
        let clock = Clock()
        let r = rig(Scripted([.walk(forwardM: 1.4, sideM: 0)]),
                    readings: {
                        count.n += 1
                        if count.n == 5 { count.stopPath?.stop() }
                        return BrainRunnerTests.fresh
                    }, clock: clock)
        count.stopPath = r.stopPath
        let summary = await r.runner.run()
        XCTAssertEqual(summary.ending, .stopped)
        let afterStop = r.duck.sent.drop { $0 != .stop }.dropFirst()
        XCTAssertFalse(afterStop.contains { if case .move(let t) = $0 { return t != .still } else { return false } },
                       "no move reached the duck after the stop")
    }

    /// The top kill criterion (10): Stop reaches the duck within 50 ms on the kit path while a
    /// planner hangs, and the runner lets go without waiting for it.
    func testStopWhileThePlannerHangs() async {
        let hung = Hung()
        let r = rig(hung)
        let run = Task { await r.runner.run() }
        await fulfillment(of: [hung.asked], timeout: 5)
        let pressed = Date()
        let wire = r.stopPath.stop().wire
        await wire?.value
        XCTAssertLessThan(Date().timeIntervalSince(pressed), 0.05, "robot.stop answered within 50 ms")
        let summary = await run.value
        XCTAssertLessThan(Date().timeIntervalSince(pressed), 1, "the runner let go of the hung planner")
        XCTAssertEqual(summary.ending, .stopped)
        XCTAssertEqual(r.duck.moves, 0)
    }

    /// Thumbs win: a stick touch in the arbiter cancels the runner through the stop path.
    func testAStickTouchCancelsTheRunner() async {
        let hung = Hung()
        let clock = Clock()
        let duck = Duck()
        let stopPath = StopPath(peer: duck)
        var arbiter = ControlArbiter()
        _ = arbiter.handle(.start(.goal, duck: .sim, owner: .app), at: clock.now())
        let hooks = BrainRunner.Hooks(reading: { BrainRunnerTests.fresh }, confirm: { _ in true }, ask: { _ in nil },
                                      now: { clock.now() }, sleep: { clock.advance($0) })
        let runner = BrainRunner(planner: AgreedPlanner(hung, settings: Self.settings()), run: arbiter.running!,
                                 goal: HumanGoal(personSaid: "go")!, peer: duck, stopPath: stopPath, hooks: hooks)!
        let run = Task { await runner.run() }
        await fulfillment(of: [hung.asked], timeout: 5)
        let touched = arbiter.handle(.stickTouch, at: clock.now())
        XCTAssertTrue(touched.passInput, "the person's stick drives")
        for effect in touched.effects {
            switch effect {
            case .stopPath: stopPath.stop()
            case .rearm: stopPath.rearm()
            default: break
            }
        }
        let summary = await run.value
        XCTAssertEqual(summary.ending, .stopped)
        XCTAssertEqual(arbiter.lastEnding, .tookOver)
        XCTAssertEqual(duck.moves, 0, "the runner moved nothing after the touch")
    }

    // MARK: 5. allowlist, first use, caps and run limits

    func testSkillsNeedTheAllowlistAndAGoTheFirstTime() async {
        let options = BrainRunner.Options(robotSkills: ["kick_left", "kick_right"])
        let planner = Scripted([.skill(name: "kick_left"), .skill(name: "kick_left"), .skill(name: "roulade")])
        let r = rig(planner, duck: .real, options: options)
        let summary = await r.runner.run()
        XCTAssertEqual(r.duck.sent.filter { $0 == .doSkill("kick_left") }.count, 2)
        XCTAssertFalse(r.duck.sent.contains(.doSkill("roulade")), "off the allowlist")
        XCTAssertEqual(summary.steps.map(\.outcome).prefix(3), [.skillStarted, .skillStarted, .held])
        XCTAssertEqual(summary.steps[2].rule, .allowlist)
        let first = r.cards.cards.first { $0.decided.decision == .skill(name: "kick_left") }
        XCTAssertTrue(first?.reasons.contains(.newSkill("kick_left")) == true, "the first use asks")
        XCTAssertEqual(r.cards.cards.filter { $0.decided.decision == .skill(name: "kick_left") }.count, 1,
                       "the second use does not")
        // The prerequisites came first: init, enable, a zero twist, then the skill.
        let firstSkill = r.duck.index(of: .doSkill("kick_left"))!
        XCTAssertEqual(Array(r.duck.sent[..<firstSkill].suffix(3)), [.initPose, .enable, .stop])
    }

    func testAHostedPlannerGetsNoSkillsOnARealDuck() async {
        let planner = Scripted([.skill(name: "kick_left")], info: Self.hosted)
        let r = rig(planner, duck: .real, options: .init(robotSkills: ["kick_left"]))
        _ = await r.runner.run()
        XCTAssertFalse(planner.asks.first?.allowed.kinds.contains(.skill) ?? true)
        XCTAssertFalse(r.duck.sent.contains(.doSkill("kick_left")))
    }

    func testSkillsPerMinuteAreCapped() async {
        let options = BrainRunner.Options(robotSkills: ["kick_left", "kick_right"])
        let kicks: [DuckDecision] = ["kick_left", "kick_right", "kick_left", "kick_right", "kick_left"].map { .skill(name: $0) }
        let r = rig(Scripted(kicks), duck: .real, options: options)
        let summary = await r.runner.run()
        XCTAssertEqual(r.duck.sent.filter { if case .doSkill = $0 { return true } else { return false } }.count, 4)
        XCTAssertEqual(summary.steps[4].outcome, .held)
        XCTAssertEqual(summary.steps[4].rule, .allowlist)
    }

    /// Required (build 91): confidence never removes a confirmation.
    func testConfidenceOnlyAddsConfirmations() async {
        // Tell always asks, however sure the planner says it is.
        let tell = rig(Scripted([.turn(degrees: 10), .turn(degrees: -10)], confidence: 1.0), kind: .tell)
        _ = await tell.runner.run()
        XCTAssertEqual(tell.cards.cards.count, 2)
        XCTAssertTrue(tell.cards.cards.allSatisfy { $0.reasons.contains(.tellCountdown) })
        XCTAssertTrue(tell.cards.cards[0].reasons.contains(.newKind(.turn)), "a sure planner still asks the first time")

        // Auto: a kind already seen runs without a Go, unless the planner is unsure.
        let auto = rig(Scripted(withConfidence: [(.turn(degrees: 10), 1.0), (.turn(degrees: -10), 1.0),
                                                 (.turn(degrees: 10), 0.1)]))
        _ = await auto.runner.run()
        XCTAssertEqual(auto.cards.cards.count, 2)
        XCTAssertTrue(auto.cards.cards[0].reasons.contains(.newKind(.turn)))
        XCTAssertEqual(auto.cards.cards[1].reasons, [.lowConfidence])

        // Every confidence gives a superset of the reasons with none.
        for c in [0.0, 0.3, 0.6, 0.99, 1.0, 2.0, .nan, .infinity] {
            let plain = rig(Scripted([.turn(degrees: 10)]), kind: .tell)
            let sure = rig(Scripted([.turn(degrees: 10)], confidence: c), kind: .tell)
            _ = await plain.runner.run()
            _ = await sure.runner.run()
            let without = Set(plain.cards.cards.first?.reasons ?? [])
            let with = Set(sure.cards.cards.first?.reasons ?? [])
            XCTAssertTrue(without.isSubset(of: with), "confidence \(c) removed a reason")
        }
    }

    func testCancelOnAGoCardEndsTheRunWithNothingMoved() async {
        let r = rig(Scripted([.walk(forwardM: 1, sideM: 0)]), answer: false)
        let summary = await r.runner.run()
        XCTAssertEqual(summary.ending, .declined)
        XCTAssertEqual(summary.steps.first?.confirmed, false)
        XCTAssertTrue(r.duck.moving.isEmpty)
    }

    func testTheRunLimitsEndTheRun() async {
        // 20 decisions.
        let turns: [DuckDecision] = (0..<30).map { .turn(degrees: $0 % 2 == 0 ? 5 : -5) }
        let decisions = rig(Scripted(turns))
        let a = await decisions.runner.run()
        XCTAssertEqual(a.ending, .limit(.decisions))
        XCTAssertEqual(a.plannerCalls, 20)

        // 20 hosted calls (here 3, to keep it short).
        let hosted = rig(Scripted(turns, info: Self.hosted), options: .init(limits: Self.limits(maxHostedCalls: 3)))
        let b = await hosted.runner.run()
        XCTAssertEqual(b.ending, .limit(.hostedCalls))
        XCTAssertEqual(b.hostedCalls, 3)

        // Three identical repeats, then the fourth ends the run.
        let same = rig(Scripted(Array(repeating: .turn(degrees: 5), count: 6)))
        let c = await same.runner.run()
        XCTAssertEqual(c.ending, .limit(.repeats))
        XCTAssertEqual(c.decisionsRun, 3)

        // Wall clock: three minutes, planner time included.
        let clock = Clock()
        final class Slow: Planner, @unchecked Sendable {
            let info = BrainRunnerTests.model
            let clock: Clock
            init(_ c: Clock) { clock = c }
            func decide(_ ask: PlannerAsk) async throws -> Decided {
                clock.advance(100)
                return Decided(decision: .ask(question: "?"), why: "", provider: info, latency: .seconds(100))
            }
        }
        // A Tell run has no arbiter cap; the practice duck's 60 s is lengthened here, as Studio may.
        let slow = rig(Slow(clock), kind: .tell, options: .init(limits: Self.limits(runCapPracticeS: 600)), clock: clock)
        let d = await slow.runner.run()
        XCTAssertEqual(d.ending, .limit(.wallClock))
        XCTAssertEqual(d.plannerCalls, 2, "the answer that came back after 3 minutes was not run")

        // On the practice duck's own 60 s cap, a Goal run ends at the cap.
        let capped = Clock()
        let e = await rig(Slow(capped), clock: capped).runner.run()
        XCTAssertEqual(e.ending, .limit(.venueCap))
    }

    func testOnlyOneAskIsEverOpen() async {
        final class Open: @unchecked Sendable {
            private let lock = NSLock(); var now = 0, most = 0
            func enter() { lock.withLock { now += 1; most = max(most, now) } }
            func leave() { lock.withLock { now -= 1 } }
        }
        let open = Open()
        let planner = Scripted([.ask(question: "a"), .ask(question: "b"), .ask(question: "c")])
        let r = rig(planner, ask: { _ in open.enter(); try? await Task.sleep(nanoseconds: 1_000_000); open.leave(); return "x" })
        _ = await r.runner.run()
        XCTAssertEqual(open.most, 1)
        let unanswered = await rig(Scripted([.ask(question: "a")]), ask: { _ in nil }).runner.run()
        XCTAssertEqual(unanswered.ending, .unanswered)
    }

    // MARK: 6. the run summary

    func testTheSummaryCarriesCountsProvenanceLabelsAndTheEnding() async {
        let r = rig(Scripted([.walk(forwardM: 0.6, sideM: 0), .done(reason: "there")]))
        let summary = await r.runner.run()
        XCTAssertEqual(summary.planner, Self.model)
        XCTAssertEqual(summary.goal, "walk to the red mat")
        XCTAssertEqual(summary.ending, .done("there"))
        XCTAssertEqual(summary.steps.first?.provenance, "test.model m1")
        XCTAssertEqual(summary.steps.first?.decided.why, "scripted")
        XCTAssertNotNil(summary.steps.first?.label)
        XCTAssertGreaterThan(summary.gateStats.counts[.rate] ?? 0, 0, "the walk was eased in")
        XCTAssertTrue(summary.gateChip.hasPrefix("Gate stepped in"))
        XCTAssertTrue(summary.gateEvents.contains { $0.phase == "decide" })
        XCTAssertTrue(summary.gateEvents.contains { $0.phase == "walk" })
        XCTAssertEqual(summary.lines.first, summary.gateChip)
        XCTAssertTrue(summary.lines.contains(GateWords.noObstacleSensing))
        XCTAssertEqual(summary.lines.last, BrainRunWords.done)
    }

    func testTheWordsHaveNoEmDashAndNeverSaySafe() {
        for line in BrainRunWords.all + LatchWords.all {
            XCTAssertFalse(line.contains("\u{2014}"), line)
            XCTAssertFalse(line.lowercased().contains("safe"), line)
        }
    }

    // MARK: sources

    static func kitSource(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/StudioKit/\(name)")
    }
}
