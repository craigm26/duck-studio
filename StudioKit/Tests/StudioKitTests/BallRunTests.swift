import XCTest
import DuckKit
@testable import StudioKit

/// A Walk to the ball run on the practice duck: the start M1 used, the watch, and the card.
final class BallRunTests: XCTestCase {
    private static func state(t: Double = 1, x: Double = 0, y: Double = 0, ball: [Double]? = [0.8, 0, 0.05],
                              upright: Bool = true) -> Data {
        var body: [String: Any] = [
            "t": t, "joints": [Double](repeating: 0.25, count: DuckModel.policyJointCount),
            "height": 0.116, "upright": upright, "position": [x, y, 0.116], "quaternion": [1, 0, 0, 0],
            "command": ["vx": 0.0, "vy": 0.0, "vyaw": 0.0], "ballRadius": 0.05,
        ]
        if let ball { body["ball"] = ball }
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private func live(t: Double = 1, x: Double = 0, y: Double = 0, upright: Bool = true,
                      ball: Double = 0.8) throws -> DuckDrive.Live {
        try DuckDrive.readLive(Self.state(t: t, x: x, y: y, ball: [ball, 0, 0.05], upright: upright))
    }

    private actor Calls {
        var seen: [DuckBench.Call] = []
        func add(_ c: DuckBench.Call) { seen.append(c) }
    }

    // MARK: - the start

    /// Numbers from `scripts/m1_trial.py`'s `start_of`, run in Python.
    func testASeedIsTheSameStartAsInM1() {
        let cases: [(UInt64, Double, Double)] = [
            (8001, -155.96361818659844, 0.8867043639788079),
            (8002, -16.46909620057494, 1.1285157881948993),
            (5001, -157.03796966398056, 1.385460027026058),
        ]
        for (seed, bearing, range) in cases {
            let start = BallRunStart(seed: seed)
            XCTAssertEqual(start.bearing, bearing, accuracy: 1e-9)
            XCTAssertEqual(start.range, range, accuracy: 1e-9)
        }
    }

    func testEveryStartIsInsideTheRangeTheDriverLearned() {
        for seed in UInt64(1)...500 {
            let start = BallRunStart(seed: seed)
            XCTAssertTrue((-180...180).contains(start.bearing))
            XCTAssertTrue((0.5...1.4).contains(start.range))
        }
        XCTAssertLessThanOrEqual(1.4 + DuckWorld.ballRadius, DuckWorld.Bank.pinned.arenaInner,
                                 "from the reset spot no ball is outside the walls")
    }

    func testLayingOutIsM1sOrderAndThePeerKeepsTheBall() async throws {
        let calls = Calls()
        let peer = try BenchPeer(address: DuckBench.Address(host: "127.0.0.1", port: 1)) { call in
            await calls.add(call)
            return Self.state(ball: call.url.path == "/stop" ? [0.3, 0.2, 0.05] : nil)
        }
        let start = BallRunStart(seed: 8001)
        try await peer.layOut(start)

        let seen = await calls.seen
        XCTAssertEqual(seen.map(\.url.path), ["/reset", "/policy", "/ball", "/stop"])
        func body(_ i: Int) throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(seen[i].body)) as? [String: Any])
        }
        XCTAssertEqual(try body(1)["policy"] as? String, "alpha_walking.onnx")
        XCTAssertEqual(try XCTUnwrap(try body(2)["bearing"] as? Double), start.bearing, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(try body(2)["range"] as? Double), start.range, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(try body(3)["settle"] as? Double), DriverTrial.preRoll, accuracy: 1e-9)
        for call in seen { XCTAssertTrue(DuckBench.routes.contains(call.url.path), call.url.path) }
        let ball = await peer.live?.ball
        XCTAssertEqual(ball?.x, 0.3, "the camera draws `live`, so `live` must hold the placed ball")
    }

    func testABenchThatRefusesStopsTheLayingOut() async throws {
        let calls = Calls()
        let peer = try BenchPeer(address: DuckBench.Address(host: "127.0.0.1", port: 1)) { call in
            await calls.add(call)
            if call.url.path == "/policy" { return Data(#"{"error":"unknown policy: alpha_walking.onnx"}"#.utf8) }
            return Self.state()
        }
        do {
            try await peer.layOut(BallRunStart(seed: 1))
            XCTFail("laid out")
        } catch DuckBench.ReadError.bench(let said) {
            XCTAssertTrue(said.contains("unknown policy"))
        }
        let paths = await calls.seen.map(\.url.path)
        XCTAssertEqual(paths, ["/reset", "/policy"])
    }

    /// WHAT A PERSON SEES IS WHAT THE DRIVER SEES: the head camera and the stage draw the bench's
    /// ball, at the bench's place and size. The world's fixed ball stands in only with no bench ball.
    func testTheHeadCameraAndTheStageDrawTheSameBall() throws {
        let now = try DuckDrive.readLive(Self.state(ball: [0.31, -0.42, 0.05]))
        let camera = DreamPracticeWorld.ball(in: now)
        XCTAssertEqual([camera.x, camera.y, camera.z], [0.31, -0.42, 0.05])
        XCTAssertEqual(camera.radius, DuckWorld.ballRadius)
        // The stage's prop, moved by `rolling` to `live.ball`.
        let stage = DuckScene.ball(x: 0, y: 0)
        XCTAssertEqual(Double(stage.thicknessMillimetres) / 2000, camera.radius, accuracy: 1e-9)
    }

    func testStairsAreRefusedAndAMovedBallIsNot() throws {
        XCTAssertNil(BallRunStart.refusal(world: nil))
        let moved = try DuckBench.readWorld(Data(#"""
        {"world":{"set":true,"name":"Ball ahead"},"steps":[],"ball":[0.8,0,0.05],"props":[]}
        """#.utf8))
        XCTAssertTrue(moved.isSet)
        XCTAssertNil(BallRunStart.refusal(world: moved))
        let stairs = try DuckBench.readWorld(Data(#"""
        {"world":{"set":true,"name":"Stairs"},"steps":[{"x":0.4,"top":0.06}],"ball":[0.8,0,0.05],"props":[]}
        """#.utf8))
        XCTAssertEqual(BallRunStart.refusal(world: stairs), BallRunStart.Words.needsPlainFloor)
        // The world a bench boots in has its blocks stacked out of the way, and every M1 run ran in it.
        let booted = try DuckBench.readWorld(Data(#"""
        {"world":{"set":false},"steps":[{"x":0,"top":0.06}],"ball":[0.8,0,0.05],"props":[]}
        """#.utf8))
        XCTAssertNil(BallRunStart.refusal(world: booted))
    }

    // MARK: - the watch

    func testParkedIsM1sDefinition() throws {
        var watch = BallRunWatch()
        XCTAssertFalse(watch.see(try live(t: 2, x: 0)))
        var x = 0.0, t = 2.0
        while x < 0.47 { x += 0.03; t += 0.1; XCTAssertFalse(watch.see(try live(t: t, x: x)), "walking") }
        guard case .reached = watch.outcome else { return XCTFail("\(watch.outcome)") }
        var done = false
        for _ in 0..<14 { t += 0.1; done = watch.see(try live(t: t, x: x)); if done { break } }
        XCTAssertTrue(done, "still for a second, within 0.40 m")
        guard case .parked(let after?, let metres) = watch.outcome else { return XCTFail("\(watch.outcome)") }
        XCTAssertGreaterThan(after, 0)
        XCTAssertEqual(metres, 0.8 - x, accuracy: 1e-6)
        XCTAssertTrue(watch.line(pilotSaid: DuckDream.Words.stopped, p50: 9).hasPrefix("Reached the ball in "))
        XCTAssertTrue(watch.line(pilotSaid: DuckDream.Words.stopped, p50: 9).hasSuffix("It answered in about 9 ms."))
    }

    func testStandingFarFromTheBallIsNotParked() throws {
        var watch = BallRunWatch()
        for i in 0..<30 { XCTAssertFalse(watch.see(try live(t: Double(i) * 0.1, x: 0.2))) }
        XCTAssertEqual(watch.outcome, .missed(closest: 0.6000000000000001))
        XCTAssertEqual(watch.line(pilotSaid: DuckDream.Words.timeUp, p50: nil), "Did not reach the ball. Closest: 0.60 m.")
    }

    func testWalkingThroughIsReachedAndNotStopped() throws {
        var watch = BallRunWatch()
        var t = 0.0
        for i in 0..<40 { t = Double(i) * 0.1; XCTAssertFalse(watch.see(try live(t: t, x: Double(i) * 0.06))) }
        guard case .reached(let after) = watch.outcome else { return XCTFail("\(watch.outcome)") }
        XCTAssertEqual(watch.line(pilotSaid: DuckDream.Words.timeUp, p50: 12),
                       String(format: "Reached the ball in %.1f s but did not stop. It answered in about 12 ms.", after))
    }

    func testAFallEndsTheRun() throws {
        var watch = BallRunWatch()
        XCTAssertFalse(watch.see(try live(t: 0)))
        XCTAssertTrue(watch.see(try live(t: 0.1, upright: false)))
        XCTAssertEqual(watch.outcome, .fell)
        XCTAssertEqual(watch.line(pilotSaid: nil, p50: nil), BallRunWatch.Words.fell)
    }

    func testThePilotsOwnReasonIsKept() {
        XCTAssertEqual(BallRunWatch().line(pilotSaid: DuckDream.Words.tooHot, p50: nil), DuckDream.Words.tooHot)
        XCTAssertEqual(BallRunWatch().line(pilotSaid: DuckDream.Words.stopped, p50: nil), DuckDream.Words.stopped)
    }

    // MARK: - the card

    func testGetShowsTheSizeAndTheHonestNumber() {
        let card = DriverCard(phase: .absent, duck: .sim)
        XCTAssertEqual(card.actions, [.get])
        XCTAssertEqual(card.title(.get, release: .walkToBall), "Get (4.4 MB)")
        XCTAssertEqual(card.lines, ["Simulator test: reached the ball 20 of 20 times, stopped there 12 of 20. It often bumps the ball first.",
                                    "Runs on this device. Not made by Pollen."])
    }

    func testDownloadingShowsProgressAndCancel() {
        let card = DriverCard(phase: .getting(done: 1_100_000, total: 4_400_000), duck: .sim)
        XCTAssertEqual(card.progress, 0.25)
        XCTAssertEqual(card.actions, [.cancel])
        XCTAssertEqual(card.lines.first, "Getting the driver: 25%")
        XCTAssertEqual(DriverCard(phase: .checking, duck: .sim).lines.first, DriverCard.Words.checking)
    }

    func testAFailureSaysWhyAndOffersItAgain() {
        let card = DriverCard(phase: .failed("The download stopped: no route"), duck: .sim)
        XCTAssertEqual(card.lines.first, "The download stopped: no route")
        XCTAssertEqual(card.actions, [.tryAgain])
    }

    func testInstalledIsGoOnThePracticeDuckOnly() {
        XCTAssertEqual(DriverCard(phase: .installed, duck: .sim).actions, [.go, .delete])
        let real = DriverCard(phase: .installed, duck: .real)
        XCTAssertEqual(real.actions, [.delete], "no Go on a real duck")
        XCTAssertTrue(real.lines.contains(AutoGoal.Words.practiceOnlyForNow))
        XCTAssertTrue(real.lines.contains { $0.hasPrefix("Practice duck only for now") })
        XCTAssertTrue(DriverCard(phase: .absent, duck: .real).lines.contains(AutoGoal.Words.practiceOnlyForNow))
        XCTAssertEqual(DriverCard(phase: .installed, duck: nil).actions, [.delete])
    }

    func testAPhoneThatCannotDrawTheCameraHasNoGo() {
        let card = DriverCard(phase: .installed, duck: .sim, cameraMissing: true)
        XCTAssertEqual(card.actions, [.delete])
        XCTAssertTrue(card.lines.contains(DriverCard.Words.needsNewerSystem))
    }

    /// iOS 17: a download that could never run is not offered, on either duck.
    func testAPhoneThatCannotDrawTheCameraIsNotOfferedGet() {
        for duck in [DuckIdentity.Kind.sim, .real] {
            let card = DriverCard(phase: .absent, duck: duck, cameraMissing: true)
            XCTAssertEqual(card.actions, [])
            XCTAssertTrue(card.lines.contains(DriverCard.Words.needsNewerSystem))
        }
    }

    /// The sentence after a run does not hide a ball that moved.
    func testTheLineSaysTheBallMoved() throws {
        var watch = BallRunWatch()
        var t = 2.0
        _ = watch.see(try live(t: t, x: 0))
        // Reached with the ball moved on by 0.2 m, then a second standing still.
        for x in stride(from: 0.03, through: 0.48, by: 0.03) { t += 0.1; _ = watch.see(try live(t: t, x: x, ball: 0.8)) }
        var done = false
        for _ in 0..<14 where !done { t += 0.1; done = watch.see(try live(t: t, x: 0.7, ball: 1.0)) }
        XCTAssertTrue(done)
        XCTAssertTrue(watch.line(pilotSaid: nil, p50: nil).hasSuffix("The ball moved 0.20 m."),
                      watch.line(pilotSaid: nil, p50: nil))
    }

    func testTheLastRunTakesTheHonestLinesPlace() {
        let card = DriverCard(phase: .installed, duck: .sim, lastRun: "Reached the ball in 9.5 s and stopped.")
        XCTAssertEqual(card.lines.first, "Reached the ball in 9.5 s and stopped.")
    }

    /// Every sentence, in the one test a word list gets: no em-dash, and said in full.
    func testEveryWordIsPlain() {
        for line in DriverCard.Words.all(.walkToBall) + AutoGoal.all {
            XCTAssertFalse(line.contains("\u{2014}"), line)
            XCTAssertFalse(line.isEmpty)
        }
    }
}
