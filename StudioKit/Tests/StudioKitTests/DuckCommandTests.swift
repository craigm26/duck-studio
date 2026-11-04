import XCTest
@testable import StudioKit

final class DuckCommandTests: XCTestCase {

    private let standing = DuckCommand.Readiness(sitting: false)
    private let seated = DuckCommand.Readiness(sitting: true)

    // MARK: - prerequisites

    func testASkillOnAStandingDuckGetsInitEnableZeroThenDo() throws {
        for ready in [standing, .unknown] {
            XCTAssertEqual(try DuckCommand.skill("kick_left").calls(ready),
                           [.initPose, .enable, .stop, .doSkill("kick_left")])
        }
    }

    func testASeatedDuckStandsUpVisiblyFirstAndNeverGetsInit() throws {
        let steps = try DuckCommand.skill("roulade").plan(seated)
        XCTAssertEqual(steps.map(\.action), [
            .call(.enable, retriesWhileHoming: false),
            .call(.doSkill("sit_toggle"), retriesWhileHoming: true),
            .call(.stop, retriesWhileHoming: false),
            .call(.doSkill("roulade"), retriesWhileHoming: true),
        ])
        XCTAssertEqual(steps[1].caption, "Stand up", "the inserted stand-up is a visible step")
        XCTAssertFalse(try DuckCommand.walk(.forward).calls(seated).contains(.initPose))
    }

    func testEveryRobotDoComesAfterAnEnableAndTheEnableIsNeverBare() throws {
        let commands: [DuckCommand] = [.stand, .sit, .walk(.left), .skill("ground_pick"), .sound(.chirp),
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
        XCTAssertEqual(try DuckCommand.stand.calls(standing), [.initPose, .enable])
        XCTAssertEqual(try DuckCommand.stand.calls(.unknown), [.initPose, .enable])
        XCTAssertEqual(try DuckCommand.stand.calls(seated), [.enable, .doSkill("sit_toggle")])
    }

    func testSitRefusesToGuess() throws {
        XCTAssertEqual(try DuckCommand.sit.calls(standing), [.initPose, .enable, .doSkill("sit_toggle")])
        XCTAssertEqual(try DuckCommand.sit.calls(seated), [])
        XCTAssertThrowsError(try DuckCommand.sit.plan(.unknown)) {
            XCTAssertEqual($0 as? DuckCommand.Refusal, .sittingUnknown)
        }
        // The toggle by name is read as the stand or the sit it would be.
        XCTAssertEqual(try DuckCommand.skill("sit_toggle").calls(seated), try DuckCommand.stand.calls(seated))
        XCTAssertEqual(try DuckCommand.skill("sit_toggle").calls(standing), try DuckCommand.sit.calls(standing))
    }

    // MARK: - walk

    func testWalkIsClampedToFiveSeconds() throws {
        XCTAssertEqual(DuckCommand.walkSeconds(30), 5)
        XCTAssertEqual(DuckCommand.walkSeconds(-1), 0)
        XCTAssertEqual(DuckCommand.walkSeconds(.nan), 1)
        XCTAssertEqual(DuckCommand.walkSeconds(.infinity), 1)
        XCTAssertEqual(DuckCommand.walkSeconds(2.5), 2.5)
        let steps = try DuckCommand.walk(.forward, seconds: 60).plan(standing)
        guard case .walk(_, let s) = steps.last?.action else { return XCTFail("a walk ends in a walk step") }
        XCTAssertEqual(s, 5)
        XCTAssertEqual(DuckCommand.walk(.back), .walk(.back, seconds: 1))
    }

    func testWalkDirectionsUsePollensSigns() {
        XCTAssertGreaterThan(DuckCommand.Direction.forward.twist.vx, 0)
        XCTAssertLessThan(DuckCommand.Direction.back.twist.vx, 0)
        XCTAssertGreaterThan(DuckCommand.Direction.left.twist.vy, 0, "y is left")
        XCTAssertLessThan(DuckCommand.Direction.right.twist.vy, 0)
        XCTAssertGreaterThan(DuckCommand.Direction.turnLeft.twist.vyaw, 0, "positive vyaw turns left")
        XCTAssertLessThan(DuckCommand.Direction.turnRight.twist.vyaw, 0)
        for d in DuckCommand.Direction.allCases {
            XCTAssertEqual(DuckCommand.Direction(rawValue: d.rawValue), d)
            XCTAssertLessThanOrEqual(abs(d.twist.vx), DuckDrive.maxForward)
            XCTAssertLessThanOrEqual(abs(d.twist.vy), DuckDrive.maxSideways)
            XCTAssertLessThanOrEqual(abs(d.twist.vyaw), DuckDrive.maxTurn)
        }
    }

    // MARK: - the rest

    func testSoundLookStopAndHandOffs() throws {
        XCTAssertEqual(try DuckCommand.sound(.chirp).calls(), [.sound(.chirp)], "a sound needs no driving")
        XCTAssertEqual(DuckCommand.defaultSound, .chirp)
        XCTAssertEqual(try DuckCommand.look(.me).calls(), [.look(.level)])
        XCTAssertEqual(try DuckCommand.stop.plan().map(\.action), [.stopPath])
        XCTAssertEqual(try DuckCommand.goal("walk to the ball").plan().map(\.action), [.handOff(.goal("walk to the ball"))])
        XCTAssertEqual(try DuckCommand.runMine("seq-1").plan().map(\.action), [.handOff(.mine("seq-1"))])
        XCTAssertThrowsError(try DuckCommand.goal("").plan())
    }

    func testSkillNamesAreCheckedBeforeAnythingIsSent() {
        XCTAssertThrowsError(try DuckCommand.skill("Kick Left").plan()) {
            XCTAssertEqual($0 as? DuckCommand.Refusal, .notASkillName("Kick Left"))
        }
        let has = DuckCommand.Readiness(sitting: false, skills: ["kick_right", "roulade"])
        XCTAssertThrowsError(try DuckCommand.skill("kick_left").plan(has)) {
            XCTAssertEqual(($0 as? DuckCommand.Refusal)?.says, "This duck has no kick_left. It has: kick_right, roulade.")
        }
        XCTAssertNoThrow(try DuckCommand.skill("roulade").plan(has))
    }

    // MARK: - locked phone

    func testWhichCommandsNeedThephoneUnlocked() {
        let free: [DuckCommand] = [.stop, .sit, .sound(.chirp)]
        let locked: [DuckCommand] = [.stand, .walk(.forward), .skill("kick_left"), .look(.me),
                                     .goal("ball"), .runMine("m")]
        for c in free { XCTAssertFalse(c.needsAuthenticationWhenLocked, "\(c)") }
        for c in locked { XCTAssertTrue(c.needsAuthenticationWhenLocked, "\(c)") }
    }

    // MARK: - words

    func testNoSentenceHasAnEmDash() {
        var said: [String] = [
            DuckCommand.Words.standUp, DuckCommand.Words.sitDown, DuckCommand.Words.alreadySitting,
            DuckCommand.Words.looking, DuckCommand.Words.doing("kick_left"),
            DuckCommand.Words.playing(.chirp),
        ]
        said += DuckCommand.Direction.allCases.map { DuckCommand.Words.walking($0, 1) }
        said += [DuckCommand.Refusal.sittingUnknown, .notASkillName("X"), .notOnThisDuck("a", has: []),
                 .notOnThisDuck("a", has: ["b"]), .emptyName].map(\.says)
        for s in said { XCTAssertFalse(s.contains("\u{2014}"), s) }
        XCTAssertEqual(DuckCommand.Words.doing("kick_left"), "Doing kick left.")
        XCTAssertEqual(DuckCommand.Words.walking(.turnLeft, 1), "Walking turn left for 1.0 s.")
    }

    // MARK: - running

    func testAWalkStreamsThenZeroes() async {
        let duck = StopTestDuck()
        let path = StopPath(peer: duck)
        let ended = await DuckCommandRunner.run(.walk(.forward, seconds: 0.3), ready: standing,
                                                on: duck, stopPath: path, sleep: { _ in })
        XCTAssertEqual(ended, .finished)
        XCTAssertEqual(duck.sent, ["robot.init", "robot.enable", "robot.move", "robot.move", "robot.move", "robot.move 0"])
        XCTAssertEqual(path.registered, [], "a finished run leaves the stop path")
    }

    func testTheFirstDoAfterAnEnableWaitsOutTheHomingRefusal() async {
        let duck = StopTestDuck()
        duck.refuse(.doSkill, ["the robot is still going to its home pose; try again in a moment",
                               "the robot is still going to its home pose; try again in a moment"])
        let ended = await DuckCommandRunner.run(.skill("kick_right"), on: duck, stopPath: StopPath(peer: duck),
                                                sleep: { _ in })
        XCTAssertEqual(ended, .finished)
        XCTAssertEqual(duck.sent.filter { $0 == "robot.do" }.count, 3)
    }

    func testARefusalThatDoesNotClearIsSaidInTheRobotsWords() async {
        let duck = StopTestDuck()
        duck.refuse(.doSkill, Array(repeating: "the policy is not driving, press Start on the pad", count: 20))
        let ended = await DuckCommandRunner.run(.skill("kick_right"), on: duck, stopPath: StopPath(peer: duck),
                                                sleep: { _ in })
        XCTAssertEqual(ended, .refused("the policy is not driving, press Start on the pad"))
        let tries = duck.sent.filter { $0 == "robot.do" }.count
        XCTAssertEqual(tries, Int(DuckCommand.homingRetry.upTo / DuckCommand.homingRetry.every) + 1)
    }

    func testAStopCommandIsTheStopPath() async {
        let duck = StopTestDuck()
        let path = StopPath(peer: duck)
        let said = Said()
        let ended = await DuckCommandRunner.run(.stop, on: duck, stopPath: path, said: { await said.add($0) })
        XCTAssertEqual(ended, .stopped)
        XCTAssertFalse(path.admits)
        let words = await said.all
        XCTAssertEqual(words, ["Stopped."])
    }

    func testARefusedPlanSendsNothing() async {
        let duck = StopTestDuck()
        let ended = await DuckCommandRunner.run(.sit, on: duck, stopPath: StopPath(peer: duck))
        XCTAssertEqual(ended, .refused(DuckCommand.Refusal.sittingUnknown.says))
        XCTAssertEqual(duck.sent, [])
    }

    private actor Said {
        var all: [String] = []
        func add(_ s: String) { all.append(s) }
    }
}
