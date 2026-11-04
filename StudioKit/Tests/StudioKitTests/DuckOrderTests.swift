import XCTest
@testable import StudioKit

final class DuckOrderTests: XCTestCase {

    private let standing = DuckOrder.Readiness(sitting: false)
    private let seated = DuckOrder.Readiness(sitting: true)
    private let driving = DuckOrder.Readiness(sitting: false, driving: true, homed: true)

    // MARK: - prerequisites

    func testASkillOnAStandingDuckGetsInitEnableZeroThenDo() throws {
        for ready in [standing, .unknown] {
            XCTAssertEqual(try DuckOrder.skill("kick_left").calls(ready),
                           [.initPose, .enable, .stop, .doSkill("kick_left")])
        }
    }

    func testASeatedDuckStandsUpVisiblyFirstAndNeverGetsInit() throws {
        let steps = try DuckOrder.skill("roulade").plan(seated)
        XCTAssertEqual(steps.map(\.action), [
            .call(.enable, retriesWhileHoming: false),
            .call(.doSkill("sit_toggle"), retriesWhileHoming: true),
            .call(.stop, retriesWhileHoming: false),
            .call(.doSkill("roulade"), retriesWhileHoming: true),
        ])
        XCTAssertEqual(steps[1].caption, "Stand up", "the inserted stand-up is a visible step")
        XCTAssertFalse(try DuckOrder.walk(.forward).calls(seated).contains(.initPose))
    }

    func testEveryRobotDoComesAfterAnEnableAndTheEnableIsNeverBare() throws {
        let commands: [DuckOrder] = [.stand, .sit, .walk(.left), .skill("ground_pick"), .sound(.chirp),
                                       .look(.me), .goal("ball"), .runMine("m1"), .stop]
        for ready in [standing, seated, .unknown] {
            for command in commands {
                guard let calls = try? command.calls(ready) else { continue }
                if let firstDo = calls.firstIndex(where: { $0.method == .doSkill }) {
                    XCTAssertNotNil(calls[..<firstDo].firstIndex(of: .enable), "\(command) \(ready)")
                }
                if let firstMove = calls.firstIndex(where: { $0.method == .move }) {
                    XCTAssertNotNil(calls[..<firstMove].firstIndex(of: .enable), "\(command) walks driven")
                }
            }
        }
        let line = try JSONSerialization.jsonObject(with: DuckCall.enable.line(id: 1)) as? [String: Any]
        XCTAssertEqual((line?["params"] as? [String: Any])?["on"] as? Bool, true)
    }

    // MARK: - sit and stand are one toggle

    func testStandNeverSendsTheToggleUnlessTheDuckSaysItIsSitting() throws {
        XCTAssertEqual(try DuckOrder.stand.calls(standing), [.initPose, .enable])
        XCTAssertEqual(try DuckOrder.stand.calls(.unknown), [.initPose, .enable])
        XCTAssertEqual(try DuckOrder.stand.calls(seated), [.enable, .doSkill("sit_toggle")])
    }

    func testSitRefusesToGuess() throws {
        XCTAssertEqual(try DuckOrder.sit.calls(standing), [.initPose, .enable, .doSkill("sit_toggle")])
        XCTAssertEqual(try DuckOrder.sit.calls(seated), [])
        XCTAssertThrowsError(try DuckOrder.sit.plan(.unknown)) {
            XCTAssertEqual($0 as? DuckOrder.Refusal, .sittingUnknown)
        }
        // The toggle by name is read as the stand or the sit it would be.
        XCTAssertEqual(try DuckOrder.skill("sit_toggle").calls(seated), try DuckOrder.stand.calls(seated))
        XCTAssertEqual(try DuckOrder.skill("sit_toggle").calls(standing), try DuckOrder.sit.calls(standing))
    }

    // MARK: - a duck already driving

    /// robot.init on a duck already up re-homes it over robotd's 2 s HOME_RAMP: a walk would be
    /// eaten and a skill refused. A driving duck gets neither init nor enable.
    func testADrivingDuckGetsNoInitAndNoEnable() throws {
        XCTAssertEqual(try DuckOrder.walk(.forward, seconds: 0.2).calls(driving), [.move(DuckOrder.Direction.forward.twist), .move(.still)])
        XCTAssertEqual(try DuckOrder.skill("kick_left").calls(driving), [.stop, .doSkill("kick_left")])
        XCTAssertEqual(try DuckOrder.sit.calls(driving), [.doSkill("sit_toggle")])
        XCTAssertEqual(try DuckOrder.stand.calls(driving), [], "already up and driving")
        XCTAssertFalse(try DuckOrder.walk(.forward).plan(driving).contains { if case .settle = $0.action { return true }; return false })
    }

    func testAWalkWaitsOutTheRampWhenInitIsSentOrTheDuckIsStillGoingHome() throws {
        for ready in [standing, .unknown, DuckOrder.Readiness(sitting: false, driving: true, homed: false)] {
            let steps = try DuckOrder.walk(.left).plan(ready)
            guard let w = steps.firstIndex(where: { if case .walk = $0.action { return true }; return false }) else {
                return XCTFail("no walk")
            }
            XCTAssertEqual(steps[w - 1].action, .settle(seconds: DuckOrder.settleSeconds), "\(ready)")
        }
        XCTAssertGreaterThan(DuckOrder.settleSeconds, DuckOrder.homeRampSeconds)
        XCTAssertGreaterThanOrEqual(DuckOrder.homingRetry.upTo, 2 * DuckOrder.homeRampSeconds)
    }

    func testDrivingIsReadFromTheStatesPolicyLabel() {
        XCTAssertTrue(DuckOrder.Readiness.policyIsDriving("walk"))
        XCTAssertTrue(DuckOrder.Readiness.policyIsDriving("stand"))
        XCTAssertFalse(DuckOrder.Readiness.policyIsDriving("held"))
        XCTAssertFalse(DuckOrder.Readiness.policyIsDriving(""))
    }

    /// Sit is allowed from a locked phone, but only when it is the toggle alone.
    func testALockedSitThatWouldStandTheDuckUpFirstIsRefused() async throws {
        XCTAssertEqual(try DuckOrder.sit.calls(driving, whileLocked: true), [.doSkill("sit_toggle")])
        XCTAssertEqual(try DuckOrder.sit.calls(seated, whileLocked: true), [])
        XCTAssertThrowsError(try DuckOrder.sit.plan(standing, whileLocked: true)) {
            XCTAssertEqual($0 as? DuckOrder.Refusal, .unlockToStartDriving)
        }
        let duck = StopTestDuck()
        let ended = await DuckOrderRunner.run(.sit, ready: standing, whileLocked: true, on: duck,
                                              stopPath: StopPath(peer: duck), sleep: { _ in })
        XCTAssertEqual(ended, .refused(DuckOrder.Refusal.unlockToStartDriving.says))
        XCTAssertEqual(duck.sent, [])
    }

    // MARK: - look

    /// robotd answers robot.look with a LookResult and no `accepted`; that is a yes.
    func testALookIsAPointAndItsAnswerIsAYes() async throws {
        let line = try JSONSerialization.jsonObject(with: DuckCall.look(.ahead).line(id: 1)) as? [String: Any]
        let params = line?["params"] as? [String: Any]
        XCTAssertEqual(Set(params?.keys.map { $0 } ?? []), ["x", "y", "z", "neck_pitch"],
                       "LookParams is deny_unknown_fields {x, y, z, neck_pitch}")
        let duck = StopTestDuck()
        let ended = await DuckOrderRunner.run(.look(.me), on: duck, stopPath: StopPath(peer: duck), sleep: { _ in })
        XCTAssertEqual(ended, .finished)
        XCTAssertEqual(duck.sent, ["robot.look"])
        let failed = DuckReply(id: 1, result: nil, failure: DuckReply.Failure(code: -32602, message: "bad"))
        XCTAssertFalse(DuckOrderRunner.answer(failed, to: .look(.ahead)).accepted)
    }

    // MARK: - walk

    func testWalkIsClampedToFiveSeconds() throws {
        XCTAssertEqual(DuckOrder.walkSeconds(30), 5)
        XCTAssertEqual(DuckOrder.walkSeconds(-1), 0)
        XCTAssertEqual(DuckOrder.walkSeconds(.nan), 1)
        XCTAssertEqual(DuckOrder.walkSeconds(.infinity), 1)
        XCTAssertEqual(DuckOrder.walkSeconds(2.5), 2.5)
        let steps = try DuckOrder.walk(.forward, seconds: 60).plan(standing)
        guard case .walk(_, let s) = steps.last?.action else { return XCTFail("a walk ends in a walk step") }
        XCTAssertEqual(s, 5)
        XCTAssertEqual(DuckOrder.walk(.back), .walk(.back, seconds: 1))
    }

    func testWalkDirectionsUsePollensSigns() {
        XCTAssertGreaterThan(DuckOrder.Direction.forward.twist.vx, 0)
        XCTAssertLessThan(DuckOrder.Direction.back.twist.vx, 0)
        XCTAssertGreaterThan(DuckOrder.Direction.left.twist.vy, 0, "y is left")
        XCTAssertLessThan(DuckOrder.Direction.right.twist.vy, 0)
        XCTAssertGreaterThan(DuckOrder.Direction.turnLeft.twist.vyaw, 0, "positive vyaw turns left")
        XCTAssertLessThan(DuckOrder.Direction.turnRight.twist.vyaw, 0)
        for d in DuckOrder.Direction.allCases {
            XCTAssertEqual(DuckOrder.Direction(rawValue: d.rawValue), d)
            XCTAssertLessThanOrEqual(abs(d.twist.vx), DuckDrive.maxForward)
            XCTAssertLessThanOrEqual(abs(d.twist.vy), DuckDrive.maxSideways)
            XCTAssertLessThanOrEqual(abs(d.twist.vyaw), DuckDrive.maxTurn)
        }
    }

    // MARK: - the rest

    func testSoundLookStopAndHandOffs() throws {
        XCTAssertEqual(try DuckOrder.sound(.chirp).calls(), [.sound(.chirp)], "a sound needs no driving")
        XCTAssertEqual(DuckOrder.defaultSound, .chirp)
        XCTAssertEqual(try DuckOrder.look(.me).calls(), [.look(.ahead)])
        XCTAssertEqual(try DuckOrder.stop.plan().map(\.action), [.stopPath])
        XCTAssertEqual(try DuckOrder.goal("walk to the ball").plan().map(\.action), [.handOff(.goal("walk to the ball"))])
        XCTAssertEqual(try DuckOrder.runMine("seq-1").plan().map(\.action), [.handOff(.mine("seq-1"))])
        XCTAssertThrowsError(try DuckOrder.goal("").plan())
    }

    func testSkillNamesAreCheckedBeforeAnythingIsSent() {
        XCTAssertThrowsError(try DuckOrder.skill("Kick Left").plan()) {
            XCTAssertEqual($0 as? DuckOrder.Refusal, .notASkillName("Kick Left"))
        }
        let has = DuckOrder.Readiness(sitting: false, skills: ["kick_right", "roulade"])
        XCTAssertThrowsError(try DuckOrder.skill("kick_left").plan(has)) {
            XCTAssertEqual(($0 as? DuckOrder.Refusal)?.says, "This duck has no kick_left. It has: kick_right, roulade.")
        }
        XCTAssertNoThrow(try DuckOrder.skill("roulade").plan(has))
    }

    // MARK: - locked phone

    func testWhichCommandsNeedThephoneUnlocked() {
        let free: [DuckOrder] = [.stop, .sit, .sound(.chirp)]
        let locked: [DuckOrder] = [.stand, .walk(.forward), .skill("kick_left"), .look(.me),
                                     .goal("ball"), .runMine("m")]
        for c in free { XCTAssertFalse(c.needsAuthenticationWhenLocked, "\(c)") }
        for c in locked { XCTAssertTrue(c.needsAuthenticationWhenLocked, "\(c)") }
    }

    // MARK: - words

    func testNoSentenceHasAnEmDash() {
        var said: [String] = [
            DuckOrder.Words.standUp, DuckOrder.Words.sitDown, DuckOrder.Words.alreadySitting,
            DuckOrder.Words.looking, DuckOrder.Words.doing("kick_left"),
            DuckOrder.Words.playing(.chirp), DuckOrder.Words.alreadyStanding,
        ]
        said += DuckOrder.Direction.allCases.map { DuckOrder.Words.walking($0, 1) }
        said += [DuckOrder.Refusal.sittingUnknown, .notASkillName("X"), .notOnThisDuck("a", has: []),
                 .notOnThisDuck("a", has: ["b"]), .emptyName, .unlockToStartDriving].map(\.says)
        for s in said { XCTAssertFalse(s.contains("\u{2014}"), s) }
        XCTAssertEqual(DuckOrder.Words.doing("kick_left"), "Doing kick left.")
        XCTAssertEqual(DuckOrder.Words.walking(.turnLeft, 1), "Walking turn left for 1.0 s.")
    }

    // MARK: - running

    func testAWalkStreamsThenZeroes() async {
        let duck = StopTestDuck()
        let path = StopPath(peer: duck)
        let ended = await DuckOrderRunner.run(.walk(.forward, seconds: 0.3), ready: standing,
                                                on: duck, stopPath: path, sleep: { _ in })
        XCTAssertEqual(ended, .finished)
        let settle = Array(repeating: "robot.move 0", count: Int((DuckOrder.settleSeconds / DuckOrder.walkTick).rounded()))
        XCTAssertEqual(duck.sent, ["robot.init", "robot.enable"] + settle
                       + ["robot.move", "robot.move", "robot.move", "robot.move 0"],
                       "after robot.init the walk waits out the home ramp, then streams")
        XCTAssertEqual(path.registered, [], "a finished run leaves the stop path")
    }

    func testTheFirstDoAfterAnEnableWaitsOutTheHomingRefusal() async {
        let duck = StopTestDuck()
        duck.refuse(.doSkill, ["the robot is still going to its home pose; try again in a moment",
                               "the robot is still going to its home pose; try again in a moment"])
        let ended = await DuckOrderRunner.run(.skill("kick_right"), on: duck, stopPath: StopPath(peer: duck),
                                                sleep: { _ in })
        XCTAssertEqual(ended, .finished)
        XCTAssertEqual(duck.sent.filter { $0 == "robot.do" }.count, 3)
    }

    func testARefusalThatDoesNotClearIsSaidInTheRobotsWords() async {
        let duck = StopTestDuck()
        duck.refuse(.doSkill, Array(repeating: "the policy is not driving, press Start on the pad", count: 20))
        let ended = await DuckOrderRunner.run(.skill("kick_right"), on: duck, stopPath: StopPath(peer: duck),
                                                sleep: { _ in })
        XCTAssertEqual(ended, .refused("the policy is not driving, press Start on the pad"))
        let tries = duck.sent.filter { $0 == "robot.do" }.count
        XCTAssertEqual(tries, Int(DuckOrder.homingRetry.upTo / DuckOrder.homingRetry.every) + 1)
    }

    func testTheRobotsEmDashNeverReachesTheScreen() async {
        let duck = StopTestDuck()
        duck.refuse(.doSkill, Array(repeating: "the policy is not driving \u{2014} press Start on the pad", count: 20))
        let ended = await DuckOrderRunner.run(.skill("kick_right"), on: duck, stopPath: StopPath(peer: duck),
                                              sleep: { _ in })
        XCTAssertEqual(ended, .refused("the policy is not driving, press Start on the pad"))
        XCTAssertEqual(DuckOrderRunner.inOurWords("a\u{2014}b"), "a, b")
    }

    func testAStopCommandIsTheStopPath() async {
        let duck = StopTestDuck()
        let path = StopPath(peer: duck)
        let said = Said()
        let ended = await DuckOrderRunner.run(.stop, on: duck, stopPath: path, said: { await said.add($0) })
        XCTAssertEqual(ended, .stopped)
        XCTAssertFalse(path.admits)
        let words = await said.all
        XCTAssertEqual(words, ["Stopped."])
    }

    func testARefusedPlanSendsNothing() async {
        let duck = StopTestDuck()
        let ended = await DuckOrderRunner.run(.sit, on: duck, stopPath: StopPath(peer: duck))
        XCTAssertEqual(ended, .refused(DuckOrder.Refusal.sittingUnknown.says))
        XCTAssertEqual(duck.sent, [])
    }

    private actor Said {
        var all: [String] = []
        func add(_ s: String) { all.append(s) }
    }
}
