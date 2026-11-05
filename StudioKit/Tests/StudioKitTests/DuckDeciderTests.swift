import XCTest
@testable import StudioKit
import DuckKit

/// Build 92: what each duck can be told, the real duck's readiness read from `robot.policies`,
/// Apple Intelligence as a decider over a closed set, captions that go away, and the real duck's
/// face buttons.
final class DuckDeciderTests: XCTestCase {

    // MARK: - the practice duck says no before anything is sent

    func testThePracticeDuckRefusesWhatItCannotDoInASentence() {
        XCTAssertEqual(DuckOrder.sit.notOn(.sim), DuckOrder.PracticeWords.cannotSit)
        XCTAssertEqual(DuckOrder.skill("sit_toggle").notOn(.sim), DuckOrder.PracticeWords.cannotSit)
        XCTAssertEqual(DuckOrder.skill("roulade").notOn(.sim), DuckOrder.PracticeWords.noSkills)
        XCTAssertEqual(DuckOrder.sound(.chirp).notOn(.sim), DuckOrder.PracticeWords.noVoice)
        XCTAssertEqual(DuckOrder.look(.me).notOn(.sim), DuckOrder.PracticeWords.noHead)
        for ok: DuckOrder in [.walk(.forward), .walk(.turnLeft), .stand, .stop] {
            XCTAssertNil(ok.notOn(.sim), "\(ok)")
        }
        for any: DuckOrder in [.sit, .stand, .walk(.back), .skill("kick_left"), .sound(.chirp), .look(.me)] {
            XCTAssertNil(any.notOn(.real), "a real duck is asked, and answers for itself")
        }
    }

    /// Every tile reads as an order, and every practice tile is one the practice duck can run.
    func testEveryTileReadsAndThePracticeTilesAllRunOnThePracticeDuck() {
        for tile in ControllerWords.tiles(for: .real) {
            XCTAssertNotNil(DuckOrderMatcher.match(tile.said, skills: Array(RobotPlan.skillSeconds.keys)), tile.said)
        }
        let practice = ControllerWords.tiles(for: .sim)
        XCTAssertFalse(practice.isEmpty)
        for tile in practice {
            let order = DuckOrderMatcher.match(tile.said)
            XCTAssertNotNil(order, tile.said)
            XCTAssertNil(order?.notOn(.sim), tile.said)
        }
        XCTAssertFalse(practice.contains { $0.said == "sit down" || $0.said == "quack" })
    }

    /// With the practice duck's readiness, Sit is never asked of the bench and a walk sends no
    /// robot.init (the bench refuses it).
    func testThePracticeDucksReadinessSkipsInit() throws {
        let calls = try DuckOrder.walk(.forward).calls(.practiceDuck)
        XCTAssertFalse(calls.contains(.initPose))
        XCTAssertFalse(calls.contains(.enable))
        XCTAssertEqual(try DuckOrder.stand.calls(.practiceDuck), [], "already standing")
    }

    // MARK: - robot.policies

    private func reply(_ json: String) -> DuckReply {
        DuckReply(id: 1, result: Data(json.utf8), failure: nil)
    }

    func testPoliciesIsReadForTheSittingLatchAndDriving() throws {
        let seated = DuckOrder.Readiness.read(policies: reply(
            #"{"mode":"walk","enabled":false,"sitting":true,"homed":true,"slots":[],"skills":["roulade"]}"#))
        XCTAssertEqual(seated, DuckOrder.Readiness(sitting: true, skills: ["roulade"], driving: nil, homed: true))

        // robotd's `enabled` is the config's [policy] enabled and `mode` is walk|roller: neither
        // says the policy is driving, so a limp duck must still get init and enable.
        let up = try XCTUnwrap(DuckOrder.Readiness.read(policies: reply(
            #"{"mode":"walk","enabled":true,"sitting":false,"homed":true}"#)))
        XCTAssertNil(up.driving)
        XCTAssertEqual(try DuckOrder.stand.calls(up), [.initPose, .enable], "a limp standing duck is stood up")
        XCTAssertEqual(Array(try DuckOrder.walk(.forward).calls(up).prefix(2)), [.initPose, .enable])
        XCTAssertEqual(try DuckOrder.sit.calls(up).last, .doSkill("sit_toggle"))

        let old = DuckOrder.Readiness.read(policies: reply(#"{"mode":"walk","enabled":true}"#))
        XCTAssertNil(old?.sitting, "an older robotd says nothing about sitting, and nil keeps Sit honest")

        XCTAssertNil(DuckOrder.Readiness.read(policies: DuckReply(id: 1, result: nil,
                                                                  failure: .init(code: -32601, message: "no"))))
    }

    func testThePoliciesCallIsALineWithNoParamsAndOnlyRobotdLinksCarryIt() throws {
        let top = try JSONSerialization.jsonObject(with: DuckCall.policies.line(id: 9)) as? [String: Any]
        XCTAssertEqual(top?["method"] as? String, "robot.policies")
        XCTAssertNil(top?["params"])
        XCTAssertTrue(DuckMethod.reach(for: .bridge).contains(.policies))
        XCTAssertTrue(DuckMethod.reach(for: .webRTC).contains(.policies))
        XCTAssertFalse(DuckMethod.reach(for: .bench).contains(.policies))
        XCTAssertFalse(DuckMethod.reach(for: .ble).contains(.policies))
        XCTAssertNotNil(BenchPeer.refusal(for: .policies))
    }

    func testAskingReadsAnAnswerAndNeverHangs() async {
        let duck = PoliciesDuck(body: #"{"mode":"walk","enabled":true,"sitting":false,"homed":true}"#)
        let ready = await DuckOrder.Readiness.ask(duck, timeout: 2)
        XCTAssertEqual(ready.sitting, false)
        XCTAssertNil(ready.driving)

        let silent = PoliciesDuck(body: nil)
        let started = Date()
        let unknown = await DuckOrder.Readiness.ask(silent, timeout: 0.2)
        XCTAssertEqual(unknown, .unknown)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.5, "a silent duck costs the timeout, no more")

        let old = PoliciesDuck(body: nil, carriesPolicies: false)
        let skipped = await DuckOrder.Readiness.ask(old, timeout: 5)
        XCTAssertEqual(skipped, .unknown)
        XCTAssertEqual(old.asked, 0, "a link without the method is not asked")
    }

    // MARK: - errors are sentences

    func testABenchRefusalReadsAsItsSentenceNotItsCaseName() async {
        let line = DuckOrderRunner.sentence(for: BenchPeer.Refusal.noVoice)
        XCTAssertFalse(line.contains("noVoice"))
        XCTAssertEqual(line, DuckOrderRunner.inOurWords(BenchPeer.Refusal.noVoice.message))
        XCTAssertFalse(DuckOrderRunner.sentence(for: BenchPeer.Refusal.resetIsNotTheInitialPose)
            .contains("resetIsNotTheInitialPose"))
        struct Odd: Error {}
        XCTAssertEqual(DuckOrderRunner.sentence(for: Odd()), DuckOrderRunner.Words.couldNotAsk)

        let duck = PoliciesDuck(body: nil, throwing: BenchPeer.Refusal.noVoice)
        let ended = await DuckOrderRunner.run(.sound(.chirp), on: duck, stopPath: StopPath(peer: duck))
        guard case .refused(let why) = ended else { return XCTFail("\(ended)") }
        XCTAssertFalse(why.contains("noVoice"), why)
        XCTAssertFalse(why.contains("\u{2014}"), why)
    }

    // MARK: - the decider

    private func step(_ a: String, _ d: String? = nil, _ s: Double? = nil, _ n: String? = nil) -> DuckDecider.Step {
        DuckDecider.Step(action: a, direction: d, seconds: s, name: n)
    }

    func testAGoodPlanReadsIntoOrders() {
        let plan = [step("stand"), step("walk", "forward", 2), step("turn", "left", 2), step("skill", nil, nil, "roulade"),
                    step("sound", nil, nil, "quack"), step("sit")]
        XCTAssertEqual(try DuckDecider.validate(plan, on: .real).get(),
                       [.stand, .walk(.forward, seconds: 2), .walk(.turnLeft, seconds: 2), .skill("roulade"),
                        .sound(.chirp), .sit])
    }

    func testThePlanIsHeldToTheClosedSetAndTheLimits() {
        XCTAssertEqual(DuckDecider.validate([], on: .real), .failure(.nothingPlanned))
        XCTAssertEqual(DuckDecider.validate(Array(repeating: step("stand"), count: 7), on: .real),
                       .failure(.tooManySteps(7)))
        XCTAssertEqual(DuckDecider.validate([step("fly")], on: .real), .failure(.unknownAction("fly")))
        XCTAssertEqual(DuckDecider.validate([step("walk", "up")], on: .real), .failure(.unknownDirection("up")))
        XCTAssertEqual(DuckDecider.validate([step("turn", "forward")], on: .real), .failure(.unknownDirection("forward")))
        XCTAssertEqual(DuckDecider.validate([step("skill", nil, nil, "backflip")], on: .real),
                       .failure(.unknownName("backflip")))
        XCTAssertEqual(DuckDecider.validate([step("skill", nil, nil, "roulade")], on: .real, skills: ["kick_left"]),
                       .failure(.unknownName("roulade")), "only what this robot listed")
        XCTAssertEqual(DuckDecider.validate([step("skill", nil, nil, "sit_toggle")], on: .real),
                       .failure(.unknownName("sit_toggle")), "sit and stand are their own actions")
        XCTAssertEqual(DuckDecider.validate([step("sound", nil, nil, "moo")], on: .real), .failure(.unknownName("moo")))
        // One bad step refuses the plan: nothing half-runs.
        XCTAssertEqual(DuckDecider.validate([step("walk", "forward", 1), step("fly")], on: .real),
                       .failure(.unknownAction("fly")))
        // A walk asks for at most 5 s, and a plan walks at most 15 s.
        XCTAssertEqual(try DuckDecider.validate([step("walk", "forward", 99)], on: .real).get(),
                       [.walk(.forward, seconds: 5)])
        XCTAssertEqual(DuckDecider.validate(Array(repeating: step("walk", "back", 5), count: 4), on: .real),
                       .failure(.tooMuchWalking(20)))
        XCTAssertEqual(try DuckDecider.validate([step("walk", "left", .nan)], on: .real).get(),
                       [.walk(.left, seconds: 1)])
    }

    func testThePracticeDuckIsOfferedOnlyWalkingAndTurning() {
        XCTAssertEqual(DuckDecider.actions(on: .sim), [.walk, .turn])
        XCTAssertEqual(DuckDecider.validate([step("sit")], on: .sim),
                       .failure(.notOnThisDuck(DuckOrder.PracticeWords.cannotSit)))
        XCTAssertEqual(DuckDecider.validate([step("sound", nil, nil, "quack")], on: .sim),
                       .failure(.notOnThisDuck(DuckOrder.PracticeWords.noVoice)))
        let told = DuckDecider.instructions(on: .sim, skills: nil)
        XCTAssertTrue(told.contains("Use only these actions: walk, turn."), told)
        XCTAssertFalse(told.contains("roulade"))
        XCTAssertTrue(DuckDecider.instructions(on: .real, skills: ["kick_left", "sit_toggle"]).contains("kick_left"))
        XCTAssertFalse(DuckDecider.instructions(on: .real, skills: ["kick_left", "sit_toggle"]).contains("sit_toggle"))
    }

    func testTheDecodersVocabularyCoversEveryNameAndDirection() {
        for name in DuckDecider.skillNames(on: .real, skills: nil) + DuckDecider.soundNames(on: .real) {
            XCTAssertTrue(DuckDecider.nameWords.contains(name), name)
        }
        for d in DuckDecider.walkDirections + DuckDecider.turnDirections {
            XCTAssertTrue(DuckDecider.directionWords.contains(d), d)
        }
    }

    func testTheCardIsHonestAndHasNoEmDash() {
        let lines = DuckDecider.Words.all + DuckOrder.PracticeWords.all + ShortcutWords.all + MicWords.all
            + [DuckDecider.Refusal.nothingPlanned, .tooManySteps(7), .tooMuchWalking(20), .unknownAction("x")].map(\.says)
            + [DuckPadMap.Effect.practiceOnly, DuckOrderRunner.Words.couldNotAsk]
        for line in lines {
            XCTAssertFalse(line.contains("\u{2014}"), line)
            for shop in ["policy", "bench", "robotd", "onnx"] {
                XCTAssertFalse(line.lowercased().contains(shop), "\(shop) in \(line)")
            }
        }
        XCTAssertTrue(DuckDecider.Words.siriLine.contains("Sit the duck down in Microduck Studio"))
        XCTAssertFalse(DuckDecider.Availability.ready.instead != nil)
        XCTAssertNotNil(DuckDecider.Availability.notEnabled.instead)
    }

    func testEveryStepHasAChip() {
        for order: DuckOrder in [.stand, .sit, .walk(.forward, seconds: 2), .walk(.turnRight), .skill("kick_left"),
                                 .sound(.chirp), .look(.me)] {
            XCTAssertFalse(DuckDecider.chip(for: order).title.isEmpty)
        }
        XCTAssertEqual(DuckDecider.chip(for: .walk(.forward, seconds: 2)).title, "Walk forward 2 s")
        XCTAssertEqual(DuckDecider.chip(for: .sound(.chirp)).title, "Quack")
    }

    // MARK: - captions

    func testACaptionGoesAway() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let short = CaptionLine("Done.", at: t0)
        XCTAssertEqual(short.seconds, CaptionLine.shortest)
        XCTAssertTrue(short.isShowing(at: t0.addingTimeInterval(3.9)))
        XCTAssertFalse(short.isShowing(at: t0.addingTimeInterval(4.0)))
        let long = CaptionLine(String(repeating: "word ", count: 60), at: t0)
        XCTAssertEqual(long.seconds, CaptionLine.longest)
        XCTAssertFalse(long.isShowing(at: t0.addingTimeInterval(8)))
    }

    // MARK: - the real duck's face buttons

    func testTheShippedFaceButtonsRunTheRealDucksOwnSkills() {
        XCTAssertEqual(DuckPadMap.Effect.loadSlot(.groundPick).realDuckOrder, .skill("ground_pick"))
        XCTAssertEqual(DuckPadMap.Effect.loadSlot(.roulade).realDuckOrder, .skill("roulade"))
        XCTAssertEqual(DuckPadMap.Effect.stop.realDuckOrder, .stop)
        XCTAssertNil(DuckPadMap.Effect.reset.realDuckOrder)
        XCTAssertNil(DuckPadMap.Effect.drive.realDuckOrder)
        XCTAssertNil(DuckPadMap.Effect.notYet("x").realDuckOrder)
    }

    // MARK: - Auto's other helpers

    func testDreamComesFirstAndAsksForAKeyWhenThereIsNone() {
        XCTAssertEqual(AutoGoal.allCases, [.dream, .walkToBall])
        XCTAssertEqual(AutoGoal.dream.availability(on: .sim, driverInstalled: false, dreamReady: false),
                       .unavailable(AutoGoal.Words.needsKey))
        XCTAssertEqual(AutoGoal.dream.action(on: .sim, driverInstalled: false, dreamReady: false), AutoGoal.Words.addKey)
        XCTAssertEqual(AutoGoal.dream.action(on: .sim, driverInstalled: false, dreamReady: true), AutoGoal.Words.go)
        XCTAssertEqual(AutoGoal.dream.subtitle(on: .real, driverInstalled: false), AutoGoal.Words.opensDream)
        XCTAssertFalse(AutoGoal.dream.subtitle(on: .real, driverInstalled: false).contains("on the card"),
                       "the card has no field, so it must not say to type on it")
    }
}

/// A duck that answers `robot.policies` with a body, or never, or throws.
final class PoliciesDuck: DuckPeer, @unchecked Sendable {
    let identity = DuckIdentity(name: "Pip", kind: .real)
    let transportKind: DuckTransportKind = .bridge
    let reach: Set<DuckMethod>
    private let body: String?
    private let throwing: Error?
    private let lock = NSLock()
    private var _asked = 0
    var asked: Int { lock.lock(); defer { lock.unlock() }; return _asked }

    init(body: String?, carriesPolicies: Bool = true, throwing: Error? = nil) {
        self.body = body
        self.throwing = throwing
        var r = Set(DuckMethod.allCases)
        if !carriesPolicies { r.remove(.policies) }
        reach = r
    }

    func call(_ c: DuckCall) async throws -> DuckReply {
        if let throwing { throw throwing }
        if c.method == .policies {
            lock.lock(); _asked += 1; lock.unlock()
            guard let body else {
                while !Task.isCancelled { try? await Task.sleep(nanoseconds: 20_000_000) }
                throw CancellationError()
            }
            return DuckReply(id: 1, result: Data(body.utf8), failure: nil)
        }
        return DuckReply(id: 1, result: Data(#"{"accepted":true}"#.utf8), failure: nil)
    }

    func notify(_ c: DuckCall) async throws {}
    nonisolated func states() -> AsyncStream<DuckState> { AsyncStream { $0.finish() } }
    func lastCommand() async -> DuckDrive.Twist? { nil }

    /// Build 93: every "Try saying" sentence works on the duck it is offered for. Without Apple
    /// Intelligence each is one order the matcher reads; with it, each step of the sentence is.
    func testEveryTrySayingExampleRunsOnItsDuck() {
        let skills = Array(RobotPlan.skillSeconds.keys)
        for duck in [DuckIdentity.Kind.sim, .real] {
            for ready in [false, true] {
                let examples = DuckDecider.Words.examples(on: duck, modelReady: ready)
                XCTAssertFalse(examples.isEmpty)
                for example in examples {
                    let steps = DuckDecider.Words.exampleSteps(example)
                    if !ready { XCTAssertEqual(steps.count, 1, example) }
                    for step in steps {
                        guard let order = DuckOrderMatcher.match(step, skills: skills) else {
                            XCTFail("\(step) is not read on \(duck)"); continue
                        }
                        XCTAssertNil(order.notOn(duck), "\(step) cannot run on \(duck)")
                    }
                }
            }
        }
        XCTAssertEqual(DuckDecider.Words.exampleSteps("stand up, then quack"), ["stand up", "quack"])
        for duck in [DuckIdentity.Kind.sim, .real] {
            for ready in [false, true] {
                for example in DuckDecider.Words.examples(on: duck, modelReady: ready) {
                    let plan = DuckDecider.Words.examplePlan(example, on: duck, skills: skills)
                    XCTAssertEqual(plan?.count, DuckDecider.Words.exampleSteps(example).count, example)
                }
            }
        }
        // A real duck's sentence is refused on the practice duck rather than half-run.
        XCTAssertNil(DuckDecider.Words.examplePlan("stand up, then quack", on: .sim, skills: skills))
    }
}
