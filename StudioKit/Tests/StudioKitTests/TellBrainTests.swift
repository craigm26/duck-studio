import XCTest
import DuckKit
@testable import StudioKit

/// Build 91, typed Tell (brains-layer.md 8 and 9): DuckTalk first, then a model planner through
/// `BrainRunner`, with the Go card, the question, the summary, and the practice duck's reading.
/// Each test is the app's own sequence in the kit's terms, and fails if its rule is taken out.
final class TellBrainTests: XCTestCase {

    typealias Scripted = BrainRunnerTests.Scripted
    typealias Duck = ControllerDuck
    typealias Clock = ControllerClock

    static let agreed = ParentalAgreement.Status.current(
        ParentalAgreement(agreedOn: "2026-11-14", appVersion: "2.0 (96)", textVersion: ParentalAgreementWords.textVersion))

    static func setup(_ choice: TellPlannerChoice = .apple, agreement: ParentalAgreement.Status = agreed,
                      apple: DuckDecider.Availability = .ready, duck: DuckIdentity.Kind? = .sim,
                      draft: ModelEndpoint.Kind? = nil, key: Bool = false) -> TellSetup {
        TellSetup(duck: duck, choice: choice, agreement: agreement, apple: apple, draftModel: draft, hostedKeySaved: key)
    }

    /// What the app's `apply` does with the arbiter's effects on the stop path.
    static func apply(_ d: ControlArbiter.Decision, to path: StopPath) {
        for e in d.effects {
            switch e {
            case .stopPath: _ = path.stop()
            case .rearm: path.rearm()
            default: break
            }
        }
    }

    struct Tell {
        let runner: BrainRunner
        let duck: Duck
        let path: StopPath
        let planner: Scripted
    }

    /// One typed Tell the way Play starts it: the arbiter's `.start(.tell)`, its effects applied,
    /// then a runner on that run with an `AgreedPlanner`.
    static func tell(_ planner: Scripted, said: String = "find the red mat", on kind: DuckIdentity.Kind = .sim,
                     duck: Duck? = nil, path: StopPath? = nil, arbiter: inout ControlArbiter,
                     settings: PlannerSafetySettings = BrainRunnerTests.settings(),
                     options: BrainRunner.Options = .init(),
                     confirm: @escaping @Sendable (BrainRunner.ConfirmCard) async -> Bool = { _ in true },
                     picture: PlannerPictureSource = .none) -> Tell {
        let duck = duck ?? Duck(kind: kind)
        let path = path ?? StopPath(peer: duck)
        let clock = Clock()
        let start = arbiter.handle(.start(.tell, duck: kind, owner: .app), at: clock.now())
        apply(start, to: path)
        let hooks = BrainRunner.Hooks(reading: { BrainRunnerTests.fresh }, confirm: confirm, ask: { _ in "yes" },
                                      picture: picture, now: { clock.now() }, sleep: { clock.advance($0) })
        let runner = BrainRunner(planner: AgreedPlanner(planner, settings: settings), run: arbiter.running!,
                                 goal: HumanGoal(personSaid: said)!, peer: duck, stopPath: path,
                                 options: options, hooks: hooks)!
        return Tell(runner: runner, duck: duck, path: path, planner: planner)
    }

    // MARK: DuckTalk first

    func testDuckTalkReadsFirstAndAModelOnlyGetsWhatItCannot() {
        let s = Self.setup()
        XCTAssertEqual(TellRouter.route("stop", setup: s), .order(.stop))
        XCTAssertEqual(TellRouter.route("no, stop the duck please", setup: s), .order(.stop), "a stop word is a stop")
        XCTAssertEqual(TellRouter.route("quack", setup: s), .order(.sound(.chirp)))
        XCTAssertEqual(TellRouter.route("walk to the ball", setup: s), .walkToBall)
        guard case .order(.walk)? = Optional(TellRouter.route("walk forward for two seconds", setup: s)) else {
            return XCTFail("DuckTalk reads a walk with its own numbers")
        }
        // What the phone cannot read goes to the chosen planner, and only then.
        XCTAssertEqual(TellRouter.route("go look behind the sofa", setup: s), .planner(.apple))
        XCTAssertEqual(TellRouter.route("go look behind the sofa", setup: Self.setup(.wordsOnly)),
                       .said(ControllerWords.heard("go look behind the sofa")), "no model when the person chose none")
    }

    func testAModelPlannerNeedsItsKeyOrServerAndAppleItsModel() {
        let text = "go look behind the sofa"
        XCTAssertEqual(TellRouter.route(text, setup: Self.setup(apple: .notEnabled)),
                       .said(TellWords.modelNotReady(text, DuckDecider.Availability.notEnabled.says)))
        XCTAssertEqual(TellRouter.route(text, setup: Self.setup(.anthropic)), .said(TellWords.noKey(text, .anthropic)))
        XCTAssertEqual(TellRouter.route(text, setup: Self.setup(.anthropic, key: true)), .planner(.anthropic))
        XCTAssertEqual(TellRouter.route(text, setup: Self.setup(.draftModel, draft: .appleOnDevice)),
                       .said(TellWords.noDraftModel(text)))
        XCTAssertEqual(TellRouter.route(text, setup: Self.setup(.draftModel, draft: .openAICompatible)),
                       .planner(.draftModel))
        XCTAssertEqual(TellPlannerChoice(stored: nil), .apple, "Apple's on-device model is the default")
        XCTAssertEqual(TellPlannerChoice(stored: "nonsense"), .apple)
    }

    // MARK: no model without the adult's agreement

    func testNoModelPlannerWithoutTheAgreement() async {
        let text = "go look behind the sofa"
        XCTAssertEqual(TellRouter.route(text, setup: Self.setup(agreement: .none)), .said(TellWords.needsAgreement(text)))
        let old = ParentalAgreement(agreedOn: "2026-01-01", appVersion: "1.0", textVersion: 0)
        XCTAssertEqual(TellRouter.route(text, setup: Self.setup(agreement: .outdated(old))),
                       .said(TellWords.needsAgreement(text)))

        // The second lock: a runner built anyway asks nothing and moves nothing.
        var arbiter = ControlArbiter()
        let planner = Scripted([.walk(forwardM: 0.3, sideM: 0)])
        let t = Self.tell(planner, arbiter: &arbiter, settings: BrainRunnerTests.settings(agreed: false))
        let summary = await t.runner.run()
        XCTAssertTrue(planner.asks.isEmpty, "no model is asked anything")
        XCTAssertTrue(t.duck.moving.isEmpty)
        XCTAssertEqual(summary.ending, .refused(ParentalAgreementWords.needed))
    }

    // MARK: no picture with consent off

    func testTellSendsNoPictureWithTheCameraSwitchOff() async throws {
        let source = PlannerPictureSource(picture: { "kitchen" }, blur: PlannerFaceBlur<String> { "blurred:" + $0 },
                                          encode: { Data($0.utf8) })
        var arbiter = ControlArbiter()
        let off = Scripted([.done(reason: "x")], info: BrainRunnerTests.hosted)
        _ = await Self.tell(off, arbiter: &arbiter, picture: source).runner.run()
        XCTAssertEqual(off.asks.count, 1)
        XCTAssertNil(off.asks.first?.frame, "off by default: no picture")

        // The same Tell with the switch on does send one, so the test above can fail.
        let settings = BrainRunnerTests.settings()
        try settings.setCameraConsent(true, for: BrainRunnerTests.hosted.id)
        let on = Scripted([.done(reason: "x")], info: BrainRunnerTests.hosted)
        _ = await Self.tell(on, arbiter: &arbiter, settings: settings, picture: source).runner.run()
        XCTAssertEqual(on.asks.first?.frame, Data("blurred:kitchen".utf8))

        // Apple's on-device model never takes one, switch or not.
        XCTAssertFalse(PlannerFrameGate.takesPictures(.appleOnDevice(system: "iOS 26")))
    }

    // MARK: the Go card

    func testAFirstUseSkillNeedsATappedGo() async {
        var arbiter = ControlArbiter()
        let cards = BrainRunnerTests.Cards()
        let planner = Scripted([.skill(name: "kick_left"), .turn(degrees: 10), .turn(degrees: -10)])
        let t = Self.tell(planner, on: .real, arbiter: &arbiter,
                          options: .init(robotSkills: ["kick_left"]), confirm: { cards.confirm($0) })
        _ = await t.runner.run()
        let kick = cards.cards.first { $0.decided.decision == .skill(name: "kick_left") }
        XCTAssertNotNil(kick, "a first-use skill shows a card")
        let card = TellGoCard(kick!)
        XCTAssertTrue(card.needsTap, "and it never goes by itself")
        XCTAssertNil(card.countdown)
        XCTAssertTrue(card.reasons.contains(TellWords.reason(.newSkill("kick_left"))!))
        XCTAssertEqual(card.step, "Do the move kick_left")
        XCTAssertEqual(card.label?.headline, PlannerSafetyWords.chosenByModel)

        // A turn after a turn has only Tell's countdown, so that card counts down.
        let second = cards.cards.filter { if case .turn = $0.decided.decision { return true } else { return false } }
        XCTAssertEqual(second.count, 2, "Tell always shows the card")
        XCTAssertTrue(TellGoCard(second[0]).needsTap, "the first turn is new")
        XCTAssertFalse(TellGoCard(second[1]).needsTap, "the second only counts down")
        XCTAssertEqual(TellGoCard(second[1]).countdown, TellGoCard.countdownSeconds)
    }

    func testCancelOnTheGoCardEndsTheRun() async {
        var arbiter = ControlArbiter()
        let slot = AnswerSlot<Bool>()
        let planner = Scripted([.walk(forwardM: 0.5, sideM: 0), .walk(forwardM: 0.5, sideM: 0)])
        let t = Self.tell(planner, arbiter: &arbiter, confirm: { _ in await slot.wait(ifCancelled: false) })
        let run = Task { await t.runner.run() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        slot.give(false)   // the person taps Cancel
        let summary = await run.value
        XCTAssertEqual(summary.ending, .declined)
        XCTAssertEqual(planner.asks.count, 1, "nothing more is asked")
        XCTAssertTrue(t.duck.moving.isEmpty, "and nothing moved")
        XCTAssertFalse(t.path.admits, "the run ended through the stop path")
    }

    func testAStopAbandonsAnOpenCardAtOnce() async {
        var arbiter = ControlArbiter()
        let planner = Scripted([.walk(forwardM: 0.5, sideM: 0)])
        let t = Self.tell(planner, arbiter: &arbiter, confirm: { _ in await AnswerSlot<Bool>().wait(ifCancelled: false) })
        let run = Task { await t.runner.run() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        _ = t.path.stop()   // the red disc: nothing answers the card
        let summary = await run.value
        XCTAssertEqual(summary.ending, .stopped)
        XCTAssertTrue(t.duck.moving.isEmpty)
    }

    // MARK: Stop latches; a new Tell re-arms

    func testStopLatchesAndANewTellReArms() async {
        var arbiter = ControlArbiter()
        let duck = Duck(kind: .sim)
        let path = StopPath(peer: duck)

        // A Tell starts and is stopped.
        let first = Self.tell(Scripted([.walk(forwardM: 0.3, sideM: 0)]), duck: duck, path: path, arbiter: &arbiter,
                              confirm: { _ in await AnswerSlot<Bool>().wait(ifCancelled: false) })
        let run = Task { await first.runner.run() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        Self.apply(arbiter.handle(.stop, at: Date()), to: path)
        _ = await run.value
        XCTAssertFalse(path.admits, "Stop shut the latch")

        // Nothing re-arms by itself: a runner on the old run moves nothing.
        let latched = LatchedPeer(duck, latch: path)
        do { try await latched.notify(.move(DuckDrive.Twist(vx: 0.1, vy: 0, vyaw: 0))); XCTFail("refused") } catch {}
        XCTAssertTrue(duck.moving.isEmpty)

        // A new Tell is the person's own action: the arbiter's start re-arms, and it walks.
        let again = Self.tell(Scripted([.walk(forwardM: 0.3, sideM: 0)]), duck: duck, path: path, arbiter: &arbiter)
        XCTAssertTrue(path.admits, "the new Tell re-armed")
        let summary = await again.runner.run()
        XCTAssertEqual(summary.steps.first?.outcome, .walked(.time))
        XCTAssertFalse(duck.moving.isEmpty)
    }

    // MARK: the practice duck reports its own position

    /// A bench whose world advances only inside a request, like duck-bench.
    final class World: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var x = 0.0, y = 0.0, yaw = 0.0, t = 0.0
        private var command = (0.0, 0.0, 0.0)

        func take(_ call: DuckBench.Call) throws -> Data {
            let body = call.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            lock.lock(); defer { lock.unlock() }
            if call.url.path.hasSuffix("/intent") {
                let vx = body["vx"] as? Double ?? 0, vy = body["vy"] as? Double ?? 0, vyaw = body["vyaw"] as? Double ?? 0
                let hold = body["hold"] as? Double ?? 0.1
                x += (vx * cos(yaw) - vy * sin(yaw)) * hold
                y += (vx * sin(yaw) + vy * cos(yaw)) * hold
                yaw += vyaw * hold
                t += hold
                command = (vx, vy, vyaw)
            } else if call.url.path.hasSuffix("/stop") {
                command = (0, 0, 0)
                t += body["settle"] as? Double ?? 0.5
            }
            return try JSONSerialization.data(withJSONObject: [
                "t": t, "joints": [Double](repeating: 0, count: DuckModel.policyJointCount),
                "height": 0.116, "upright": true, "position": [x, y, 0.116],
                "quaternion": [cos(yaw / 2), 0, 0, sin(yaw / 2)],
                "command": ["vx": command.0, "vy": command.1, "vyaw": command.2],
            ] as [String: Any])
        }
    }

    func practiceTell(_ world: World, reading: @escaping @Sendable (BenchPeer) async -> PlannerLeg.Reading)
        async throws -> (BrainRunSummary, World) {
        let bench = try BenchPeer(address: .init(host: "127.0.0.1", port: 8770)) { try world.take($0) }
        _ = try await bench.call(.stop)   // the bench has answered once, as it has by the time Play shows it
        let path = StopPath(peer: bench)
        var arbiter = ControlArbiter()
        let clock = Clock()
        Self.apply(arbiter.handle(.start(.tell, duck: .sim, owner: .app), at: clock.now()), to: path)
        let hooks = BrainRunner.Hooks(reading: { await reading(bench) }, confirm: { _ in true }, ask: { _ in nil },
                                      now: { clock.now() }, sleep: { clock.advance($0) })
        let runner = BrainRunner(planner: AgreedPlanner(Scripted([.walk(forwardM: 0.45, sideM: 0), .done(reason: "there")]),
                                                        settings: BrainRunnerTests.settings()),
                                 run: arbiter.running!, goal: HumanGoal(personSaid: "go to the mat")!,
                                 peer: bench, stopPath: path, hooks: hooks)!
        return (await runner.run(), world)
    }

    func testThePracticeDuckReportsItsOwnPositionSoAWalkIsNotCut() async throws {
        let (summary, world) = try await practiceTell(World()) { await $0.gateReading() }
        XCTAssertEqual(summary.ending, .done("there"))
        XCTAssertEqual(summary.gateStats.counts[.stale] ?? 0, 0, "never held for stale data")
        guard case .walked? = summary.steps.first?.outcome else { return XCTFail("the walk ran to its end") }
        XCTAssertGreaterThan(world.x, 0.3, "and the duck went most of the way (the gate eases the start)")

        // Without a reading, the same walk is held, then cut after 1 s: what #80 found.
        let (blind, still) = try await practiceTell(World()) { _ in .none }
        XCTAssertEqual(blind.ending, .gateCut(.stale))
        XCTAssertLessThan(still.x, 0.01)
    }

    func testThePracticeDuckReadingIsTheSimulationsOwn() {
        XCTAssertEqual(PracticeDuckReading.reading(nil), .none, "nothing said, nothing filled in")
        let half = Double.pi / 4
        let live = DuckDrive.Live(t: 2, stance: DuckStance(jointAngles: DuckModel.homePose,
                                                           root: .init(x: 0.4, y: -0.2, z: 0.116,
                                                                       quaternion: (cos(half), 0, 0, sin(half)))),
                                  height: 0.116, upright: true, policy: nil, command: .init(vx: 0, vy: 0, vyaw: 0))
        let r = PracticeDuckReading.reading(live)
        XCTAssertEqual(r.pose?.x, 0.4)
        XCTAssertEqual(r.pose?.y, -0.2)
        XCTAssertEqual(r.pose?.yaw ?? 0, .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(r.odomAgeMs, 0)
        XCTAssertEqual(r.tiltDeg ?? 99, 0, accuracy: 1e-9)
        // A duck on its side is tilted past the limit, so the tilt rule cuts it.
        let fallen = DuckDrive.Live(t: 2, stance: DuckStance(jointAngles: DuckModel.homePose,
                                                             root: .init(x: 0, y: 0, z: 0.05,
                                                                         quaternion: (cos(half), sin(half), 0, 0))),
                                    height: 0.05, upright: false, policy: nil, command: .init(vx: 0, vy: 0, vyaw: 0))
        XCTAssertGreaterThan(PracticeDuckReading.reading(fallen).tiltDeg ?? 0, DuckEnvelopeGate.Limits.placeholderV1.maxTiltDeg)
        // And the bench's state stream still says nothing about odometry.
        XCTAssertNil(BenchPeer.synthesised(from: live, receivedAt: Date()).odom)
    }

    func testARealDucksReadingIsWhatItSaid() {
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(RealDuckReading.reading(nil, now: now), .none)
        XCTAssertEqual(RealDuckReading.reading(DuckState(receivedAt: now), now: now), .none, "no odometry, none filled in")
        let said = DuckState(odom: .init(position: [0.1, 0.2], yaw: 0.3), receivedAt: now.addingTimeInterval(-0.05))
        let r = RealDuckReading.reading(said, now: now)
        XCTAssertEqual(r.pose, .init(x: 0.1, y: 0.2, yaw: 0.3))
        XCTAssertEqual(r.odomAgeMs ?? 0, 50, accuracy: 1e-3)
    }

    // MARK: Apple's on-device model, read back through the closed set

    func testTheOnDeviceAnswerIsReadThroughTheClosedSet() {
        let practice = AllowedDecisions.forDuck(.sim, runsOn: .thisPhone)
        let walk = OnDeviceDecision.read(kind: "walk", forwardM: 0.4, sideM: 0, degrees: 0, name: "none", text: "",
                                         why: "the mat is ahead", allowed: practice)
        XCTAssertEqual(walk.decision, .walk(forwardM: 0.4, sideM: 0))
        XCTAssertEqual(walk.why, "the mat is ahead")
        // A skill on the practice duck is outside its set: it becomes a question, never a guess.
        let kick = OnDeviceDecision.read(kind: "skill", forwardM: 0, sideM: 0, degrees: 0, name: "kick_left", text: "",
                                         why: "", allowed: practice)
        XCTAssertEqual(kick.refusal, .kindNotAllowed(.skill))
        guard case .ask = kick.decision else { return XCTFail("refused into a question") }
        XCTAssertEqual(OnDeviceDecision.read(kind: "done", forwardM: 0, sideM: 0, degrees: 0, name: "none",
                                             text: "on the mat", why: "", allowed: practice).decision,
                       .done(reason: "on the mat"))
        XCTAssertFalse(OnDeviceDecision.kindWords.contains("drive"))
        XCTAssertFalse(OnDeviceDecision.kindWords.contains("plan"))
        XCTAssertTrue(OnDeviceDecision.instructions(for: practice).contains("Kinds you may choose here: walk, turn, ask, done, stop."))
        let label = PlannerDisclosure.stepLabel(for: PlannerInfo.appleOnDevice(system: "iOS 26.1"))
        XCTAssertEqual(label?.model, OnDeviceDecision.modelName)
        XCTAssertEqual(label?.headline, PlannerSafetyWords.chosenByModel)
    }

    // MARK: the offer rule for Tell's planners

    func testWithNoEvidenceAHostedPlannerWithAKeyIsNotOfferedAndASavedChoiceFallsBack() {
        let hosted = HostedVendor.anthropic.info()
        XCTAssertNil(hosted.evidence, "no Anthropic row exists")
        let status = TellOffer.status(.anthropic, card: hosted, venue: .practice)
        XCTAssertEqual(status, .notOfferedYet(TellWords.notOfferedYet(TellWords.hidden(.noEvidence))))
        // The key is saved and the choice is stored, but Tell uses words only.
        let used = TellOffer.effective(.anthropic, status: status)
        XCTAssertEqual(used, .wordsOnly)
        let text = "go look behind the sofa"
        XCTAssertEqual(TellRouter.route(text, setup: Self.setup(used, key: true)), .said(ControllerWords.heard(text)))
        // The same for a model on your network and a downloaded one.
        let lan = ModelEndpoint(name: "Mac", kind: .openAICompatible, baseURL: "http://192.168.1.5:11434/v1",
                                model: "qwen3.5:4b")
        XCTAssertFalse(TellOffer.status(.draftModel, card: TellOffer.draftCard(lan), venue: .practice).isOffered)
        XCTAssertEqual(TellOffer.status(.draftModel, card: nil, venue: .practice),
                       .notOfferedYet(TellWords.notOfferedYet(TellWords.noModelPicked)))
    }

    func testAppleStaysOfferedWithNoEvidenceWhileAHostedOneDoesNot() {
        let apple = PlannerInfo.appleOnDevice(system: "iOS 26.1")
        XCTAssertEqual(OfferRule.offer(for: apple, mode: .tell, venue: .practice), .hidden(.noEvidence),
                       "the rule itself would hide it: the exemption is Tell's, by name")
        for venue in BrainVenue.allCases {
            XCTAssertEqual(TellOffer.status(.apple, card: apple, venue: venue), .offered)
            XCTAssertFalse(TellOffer.status(.openai, card: HostedVendor.openai.info(), venue: venue).isOffered)
        }
        XCTAssertEqual(TellOffer.effective(.apple, status: .offered), .apple)
        XCTAssertEqual(TellOffer.status(.wordsOnly, card: nil, venue: .real), .offered)
    }

    func testAPlannerThatPassesTheRuleStillWaitsForTheConfirmedBars() {
        let passing = OfferRuleTests.planner(gold: Tally(9, of: 10))
        guard case .offered = OfferRule.offer(for: passing, mode: .tell, venue: .practice) else {
            return XCTFail("the fixture passes the rule")
        }
        let status = TellOffer.status(.anthropic, card: passing, venue: .practice)
        if OfferRule.barsConfirmedByCraig {
            XCTAssertEqual(status, .offered)
        } else {
            XCTAssertEqual(status, .notOfferedYet(TellWords.notOfferedYet(TellWords.barsNotConfirmed)))
        }
    }

    // MARK: the summary and the words

    func testTheSummaryChipCarriesStepsGateCountsAndTheEnding() async {
        var arbiter = ControlArbiter()
        let t = Self.tell(Scripted([.turn(degrees: 20), .done(reason: "facing it")]), arbiter: &arbiter)
        let summary = TellSummary(await t.runner.run())
        XCTAssertTrue(summary.chip.hasPrefix(TellWords.stepsRan(2)))
        XCTAssertTrue(summary.chip.contains(summary.summary.gateChip))
        XCTAssertTrue(summary.chip.hasSuffix(BrainRunWords.done))
        XCTAssertEqual(summary.rows.map(\.what), ["Turn 20 degrees left", "Finish: facing it"])
        XCTAssertEqual(summary.rows.first?.outcome, TellWords.outcome(.walked(.time), venue: .practice))
        XCTAssertNotNil(summary.rows.first?.label, "every step a model chose is labelled")
    }

    func testAnAbandonedAnswerSlotLetsGo() async {
        let slot = AnswerSlot<Bool>()
        let waiting = Task { await slot.wait(ifCancelled: false) }
        waiting.cancel()
        let answered = await waiting.value
        XCTAssertFalse(answered)
        slot.give(true)   // a late tap changes nothing
        let given = AnswerSlot<String?>()
        given.give("yes")
        let got = await given.wait(ifCancelled: nil)
        XCTAssertEqual(got, "yes")
    }

    func testTellWordsArePlainAndClaimNoSafety() {
        for line in TellWords.all {
            XCTAssertFalse(line.lowercased().contains("safe"), line)
            XCTAssertFalse(line.contains("\u{2014}"), "no em-dash: \(line)")
            XCTAssertFalse(line.isEmpty)
        }
        XCTAssertEqual(TellWords.plain(.walk(forwardM: -0.2, sideM: 0.1)), "Walk 0.20 m back and 0.10 m left")
        XCTAssertEqual(TellWords.plain(.turn(degrees: -90)), "Turn 90 degrees right")
    }
}
