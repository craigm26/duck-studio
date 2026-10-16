import XCTest
import DuckKit
@testable import StudioKit

/// Walk and Turn cards on odometry: the vectors the card reader is held to, robotd's pose, and
/// the runner closing a card plan on a duck that reports odometry and timing it on one that does
/// not.
final class DuckCardLoopTests: XCTestCase {

    // MARK: - the vectors

    struct Vector {
        let name: String, action: String, speed: String?
        let board: [Double], boardAfter: [Double]
        let trace: [[Double]]
        let expect: [Any]
        /// The lead the card is given, and the coast it must have measured, when any.
        let leadDeg: Double?, coastDeg: Double?
        /// The Walk lead the card is given, and the coast it must have measured (duck-card-loop/2).
        let leadM: Double?, coastM: Double?
    }

    func vectors() throws -> [Vector] {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/DuckCards/vectors/cardloop", withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { url in
            let top = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            return Vector(name: top["name"] as? String ?? "", action: top["action"] as? String ?? "",
                          speed: top["speed"] as? String,
                          board: top["board"] as? [Double] ?? [], boardAfter: top["board_after"] as? [Double] ?? [],
                          trace: top["trace"] as? [[Double]] ?? [], expect: top["expect"] as? [Any] ?? [],
                          leadDeg: top["lead_deg"] as? Double, coastDeg: top["coast_deg"] as? Double,
                          leadM: top["lead_m"] as? Double, coastM: top["coast_m"] as? Double)
        }
    }

    func testEveryVector() throws {
        let all = try vectors()
        XCTAssertGreaterThanOrEqual(all.count, 10)
        for v in all {
            var card = try XCTUnwrap(DuckCardLoop.Card(action: v.action, board: .init(x: v.board[0], y: v.board[1], h: v.board[2]),
                                                       speed: v.speed, leadDeg: v.leadDeg, leadM: v.leadM), v.name)
            XCTAssertEqual(v.trace.count, v.expect.count, v.name)
            for (sample, want) in zip(v.trace, v.expect) {
                let got = card.step(.init(x: sample[1], y: sample[2], h: sample[3]), t: sample[0])
                if let word = want as? String {
                    XCTAssertEqual(got, .done(try XCTUnwrap(DuckCardLoop.Done(rawValue: word))), "\(v.name) t=\(sample[0])")
                } else if let pair = want as? [Double], case .send(let vx, let vyaw) = got {
                    XCTAssertEqual(vx, pair[0], accuracy: 1e-6, "\(v.name) t=\(sample[0])")
                    XCTAssertEqual(vyaw, pair[1], accuracy: 1e-6, "\(v.name) t=\(sample[0])")
                } else {
                    XCTFail("\(v.name) t=\(sample[0]): wanted \(want), got \(got)")
                }
            }
            XCTAssertEqual(card.boardAfter.x, v.boardAfter[0], accuracy: 1e-6, v.name)
            XCTAssertEqual(card.boardAfter.y, v.boardAfter[1], accuracy: 1e-6, v.name)
            XCTAssertEqual(card.boardAfter.h, v.boardAfter[2], accuracy: 1e-6, v.name)
            if let want = v.coastDeg {
                XCTAssertEqual(try XCTUnwrap(card.coastDeg, v.name), want, accuracy: 1e-5, v.name)
            } else {
                XCTAssertNil(card.coastDeg, v.name)
            }
            if let want = v.coastM {
                XCTAssertEqual(try XCTUnwrap(card.coastM, v.name), want, accuracy: 1e-6, v.name)
            } else {
                XCTAssertNil(card.coastM, v.name)
            }
        }
    }

    // MARK: - Pollen's envelope

    func testTheEnvelopeIsPollensPadDriveDefaultsAtACitedCommit() {
        let env = DuckCardLoop.envelope
        XCTAssertEqual(env.vx, [-0.4, 0.4]); XCTAssertEqual(env.vy, [-0.3, 0.3]); XCTAssertEqual(env.vyaw, [-1.0, 1.0])
        XCTAssertTrue(env.source.contains("robotd-params/src/lib.rs"), env.source)
        XCTAssertTrue(env.source.contains("PadDriveParams"), env.source)
        XCTAssertEqual(env.commit.count, 40)
    }

    func testNoCardCommandsMoreThanPollensEnvelope() throws {
        XCTAssertEqual(DuckCardLoop.envelopeProblems(DuckCardLoop.spec), [])
        // And it can fail, in the reader's words: the same spec with two numbers past it.
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(contentsOf: try XCTUnwrap(DuckCardLoop.specURL))) as? [String: Any])
        var walk = try XCTUnwrap(json["walk"] as? [String: Any])
        walk["back_speed"] = ["slow": 0.4, "normal": 0.4, "fast": 0.45]
        json["walk"] = walk
        var turn = try XCTUnwrap(json["turn"] as? [String: Any])
        turn["yaw_rate"] = ["slow": 1.5, "normal": 1.0, "fast": 1.0]
        json["turn"] = turn
        let bad = try DuckCardLoop.Spec.read(try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(DuckCardLoop.envelopeProblems(bad),
                       ["walk.back_speed.fast is 0.45, past Pollen's pad envelope of 0.4",
                        "turn.yaw_rate.slow is 1.5, past Pollen's pad envelope of 1"])
    }

    func testTheSpecLoadsAndOnlyFourCardsClose() {
        XCTAssertEqual(DuckCardLoop.spec.format, DuckCardLoop.format)
        XCTAssertGreaterThan(DuckCardLoop.spec.squareM, 0)
        XCTAssertNil(DuckCardLoop.Card(action: "kick_left", board: .init(x: 0, y: 0, h: 0)))
        XCTAssertNil(DuckCardLoop.Card(action: "stop", board: .init(x: 0, y: 0, h: 0)))
    }

    // MARK: - robotd's pose

    func testRobotdsThreeElementPositionIsAPose() {
        let s = DuckState(odom: .init(position: [0.1, -0.2, 0.12], yaw: 0.5), receivedAt: Date())
        XCTAssertEqual(DuckCardLoop.pose(of: s), .init(x: 0.1, y: -0.2, h: 0.5))
        XCTAssertNil(s.odom?.x, "DuckKit's own x reads only a pair, which is why the pose is read here")
    }

    func testARobotdWithoutOdometryHasNoPose() {
        XCTAssertNil(DuckCardLoop.pose(of: DuckState(receivedAt: Date())))
        XCTAssertNil(DuckCardLoop.pose(of: DuckState(odom: .init(position: [0.1], yaw: 0), receivedAt: Date())))
        XCTAssertNil(DuckCardLoop.pose(of: DuckState(odom: .init(position: [0, 0, 0], yaw: nil), receivedAt: Date())))
        XCTAssertNil(DuckCardLoop.pose(of: nil))
    }

    // MARK: - running a card plan

    /// A duck that goes where it is told, at a fraction of the command, and reports odometry.
    final class FakeDuck: DuckPeer, @unchecked Sendable {
        let identity = DuckIdentity(name: "Pip", kind: .real)
        let transportKind = DuckTransportKind.bridge
        let reach = DuckMethod.reach(for: .bridge)
        let odom: Bool
        /// How far it walks per unit of vx, and the metres from the start at which it falls.
        let walk: Double, fallsAt: Double?
        private let lock = NSLock()
        private var x = 0.0, y = 0.0, h = 0.0, vx = 0.0, vyaw = 0.0
        private var _moves: [DuckDrive.Twist] = []
        private var _calls: [String] = []
        /// Its own clock, advanced by `advance`; starts at the wall clock so the default `now` sees
        /// fresh states.
        private var _clock = Date()

        init(odom: Bool = true, walk: Double = 0.45, fallsAt: Double? = nil) {
            self.odom = odom; self.walk = walk; self.fallsAt = fallsAt
        }

        var clock: Date { lock.lock(); defer { lock.unlock() }; return _clock }

        var moves: [DuckDrive.Twist] { lock.lock(); defer { lock.unlock() }; return _moves }
        var calls: [String] { lock.lock(); defer { lock.unlock() }; return _calls }
        var where_: (Double, Double, Double) { lock.lock(); defer { lock.unlock() }; return (x, y, h) }

        func call(_ c: DuckCall) async throws -> DuckReply {
            lock.withLock {
                _calls.append(c.method.rawValue)
                if case .doSkill = c { x += 0.05 * cos(h); y += 0.05 * sin(h) }
            }
            let body = c == .skills ? #"{"skills":[],"built_in":["kick_left"]}"# : #"{"accepted":true}"#
            return DuckReply(id: 1, result: Data(body.utf8), failure: nil)
        }

        func notify(_ c: DuckCall) async throws {
            guard case .move(let t) = c else { return }
            lock.withLock { _moves.append(t); vx = t.vx; vyaw = t.vyaw }
        }

        func advance(_ dt: Double) {
            lock.lock()
            h += 0.9 * vyaw * dt
            x += walk * vx * dt * cos(h); y += walk * vx * dt * sin(h)
            _clock = _clock.addingTimeInterval(dt)
            lock.unlock()
        }

        func state() -> DuckState? {
            let (x, y, h) = where_
            let fallen = fallsAt.map { (x * x + y * y).squareRoot() >= $0 } ?? false
            guard odom else { return DuckState(safety: .init(fallen: fallen), receivedAt: clock) }
            return DuckState(safety: .init(fallen: fallen), odom: .init(position: [x, y, 0.12], yaw: h),
                             receivedAt: clock)
        }

        nonisolated func states() -> AsyncStream<DuckState> { AsyncStream { $0.finish() } }
    }

    /// A Duck Cards plan. Measured cards on by default here, as "Measure my duck" turns them on: they
    /// ship off for real ducks (`testTheSwitchShipsOff...`).
    private func cardPlan(_ actions: [String], measured: Bool = true) throws -> RobotPlan {
        let rows = actions.map { a -> [String: Any] in
            let labels = ["action": a]
            return ["clause": a, "labels": labels, "confidence": ["action": 1.0]]
        }
        let json: [String: Any] = ["format": DuckIntentPlan.format, "request": "cards",
                                   "model": DuckCards.model, "steps": rows]
        return try RobotPlan(DuckIntentPlan.read(try JSONSerialization.data(withJSONObject: json)),
                             measuredCards: measured)
    }

    private final class Said: @unchecked Sendable {
        private let lock = NSLock()
        private var _lines: [String] = []
        func add(_ s: String) { lock.lock(); _lines.append(s); lock.unlock() }
        var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
    }

    private func run(_ plan: RobotPlan, on duck: FakeDuck, said: Said, state: Bool = true) async throws
        -> RobotPlanRunner.Outcome {
        try await RobotPlanRunner.run(
            plan, on: duck, interval: 0.05, sleep: { duck.advance($0) },
            event: { if case .said(let s) = $0 { said.add(s) } },
            state: state ? { @Sendable () async -> DuckState? in duck.state() } : nil)
    }

    // MARK: - the off switch

    func testTheSwitchShipsOffAndUnvalidatedWithItsSentence() {
        XCTAssertFalse(DuckCardLoop.spec.enabledOnRobot)
        XCTAssertNil(DuckCardLoop.spec.validated)
        XCTAssertEqual(DuckCardLoop.offNote,
                       "Walk and Turn cards on a duck are timed for now: two seconds each, and the duck does not "
                     + "land on board squares. Measured cards are being tested.")
    }

    func testOffACardPlanRunsTimedMovesEvenWithOdometryAndSaysSoOnce() async throws {
        let plan = try cardPlan(["walk_forward", "turn_left", "walk_forward", "kick_left"], measured: false)
        XCTAssertEqual(plan, try RobotPlan(DuckIntentPlan.read(try JSONSerialization.data(withJSONObject: [
            "format": DuckIntentPlan.format, "request": "cards", "model": DuckCards.model,
            "steps": ["walk_forward", "turn_left", "walk_forward", "kick_left"].map {
                ["clause": $0, "labels": ["action": $0], "confidence": ["action": 1.0]] as [String: Any] }]))),
            "off is the default")
        XCTAssertTrue(plan.cardsTimed)
        XCTAssertFalse(plan.closesOnOdometry)
        guard case .move(let t, 2.0, _) = plan.beats[0] else { return XCTFail("\(plan.beats[0])") }
        XCTAssertEqual(t, try SequenceProposal.twist(for: "forward", share: 2.0 / 3.0))
        let duck = FakeDuck(), said = Said()
        _ = try await run(plan, on: duck, said: said)
        XCTAssertEqual(said.lines.filter { $0 == DuckCardLoop.offNote }.count, 1)
        XCTAssertFalse(said.lines.contains(DuckCardLoop.timedNote))
        XCTAssertEqual(duck.moves.filter { $0 != .still }.count, 3 * Int((DuckIntentPlan.defaultSeconds / 0.05).rounded()))
        XCTAssertFalse(try cardPlan(["stop", "kick_left"], measured: false).cardsTimed)
    }

    func testACardPlanHasCardBeatsAndOtherPlansDoNot() throws {
        let p = try cardPlan(["walk_forward", "turn_left", "stop", "kick_left"])
        guard case .card("walk_forward", nil, let t, 2.0, _) = p.beats[0] else { return XCTFail("\(p.beats[0])") }
        XCTAssertEqual(t, try SequenceProposal.twist(for: "forward", share: 2.0 / 3.0), "the timed fallback is unchanged")
        guard case .card("turn_left", _, _, _, _) = p.beats[1] else { return XCTFail() }
        guard case .move = p.beats[2] else { return XCTFail("stop is not a distance") }
        XCTAssertTrue(RobotPlan.spelled(p.beats[0]).contains("one square"))
        XCTAssertTrue(p.closesOnOdometry)
        XCTAssertFalse(try cardPlan(["stop", "kick_left"]).closesOnOdometry)
    }

    func testWalkTurnWalkLandsOnTheBoard() async throws {
        let duck = FakeDuck(), said = Said()
        let outcome = try await run(try cardPlan(["walk_forward", "turn_left", "walk_forward"]), on: duck, said: said)
        XCTAssertEqual(outcome, .finished)
        let d = DuckCardLoop.spec.squareM, (x, y, h) = duck.where_
        XCTAssertEqual(x, d, accuracy: 0.03)
        XCTAssertEqual(y, d, accuracy: 0.03)
        XCTAssertLessThan(abs(DuckCardLoop.wrap(h - .pi / 2)), DuckCardLoop.spec.turn.toleranceDeg * .pi / 180 + 0.05)
        XCTAssertFalse(said.lines.contains(DuckCardLoop.timedNote))
        XCTAssertEqual(duck.calls.last, "robot.stop")
    }

    /// duck-card-loop/2, THE WALK LEAD: the first Walk card back stops the approach short; a later
    /// one leads by the row's measured coast back. This duck stops dead (no coast), so the second
    /// card stops on its square, not the approach short of it (`cardloop` tests the same).
    func testALaterWalkBackLeadsByTheRowsMeasuredCoast() async throws {
        let duck = FakeDuck(), said = Said()
        let outcome = try await run(try cardPlan(["walk_backward", "walk_backward"]), on: duck, said: said)
        XCTAssertEqual(outcome, .finished)
        XCTAssertEqual(duck.where_.0, -2 * DuckCardLoop.spec.squareM, accuracy: 0.012)
        let one = FakeDuck()
        _ = try await run(try cardPlan(["walk_backward"]), on: one, said: Said())
        XCTAssertEqual(one.where_.0, -DuckCardLoop.spec.squareM + DuckCardLoop.spec.walk.backApproachM, accuracy: 0.012)
    }

    func testRowLeadIsTheMeanOrNothing() {
        XCTAssertNil(DuckCardLoop.rowLead([]))
        XCTAssertEqual(try XCTUnwrap(DuckCardLoop.rowLead([0.02, 0.04])), 0.03, accuracy: 1e-12)
    }

    func testASkillPutsTheBoardSquareWhereTheDuckStands() async throws {
        let duck = FakeDuck(), said = Said()
        _ = try await run(try cardPlan(["walk_forward", "kick_left", "walk_forward"]), on: duck, said: said)
        XCTAssertEqual(duck.where_.0, 2 * DuckCardLoop.spec.squareM + 0.05, accuracy: 0.03)
    }

    func testADuckWithoutOdometryRunsTheTimedCardsAndSaysSoOnce() async throws {
        let duck = FakeDuck(odom: false), said = Said()
        _ = try await run(try cardPlan(["walk_forward", "turn_right"]), on: duck, said: said)
        XCTAssertEqual(said.lines.filter { $0 == DuckCardLoop.timedNote }.count, 1)
        XCTAssertEqual(duck.moves.count, 2 * Int((DuckIntentPlan.defaultSeconds / 0.05).rounded()))
        XCTAssertEqual(duck.moves.first, try SequenceProposal.twist(for: "forward", share: 2.0 / 3.0))
    }

    func testNoStateAtAllIsTimedToo() async throws {
        let duck = FakeDuck(), said = Said()
        _ = try await run(try cardPlan(["walk_forward"]), on: duck, said: said, state: false)
        XCTAssertEqual(said.lines, [DuckCardLoop.timedNote])
    }

    func testAFallMidCardEndsTheRowStillAndSaysSo() async throws {
        let duck = FakeDuck(fallsAt: 0.1), said = Said()
        let outcome = try await run(try cardPlan(["walk_forward", "turn_left", "walk_forward"]), on: duck, said: said)
        XCTAssertEqual(outcome, .stopped(beat: 0, reason: DuckCardLoop.fellNote))
        XCTAssertEqual(said.lines.last, DuckCardLoop.fellNote)
        XCTAssertEqual(duck.moves.last, .still)
        XCTAssertEqual(duck.calls.last, "robot.stop")
        XCTAssertLessThan(duck.where_.0, 0.2, "the row did not go on")
    }

    func testACardThatMakesNoProgressIsStuckAndEndsTheRow() async throws {
        let duck = FakeDuck(walk: 0), said = Said()     // stands still
        let outcome = try await run(try cardPlan(["walk_forward", "turn_left"]), on: duck, said: said)
        guard case .stopped(0, let reason) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(reason, RobotPlanRunner.CardEnd.stuck.said)
        XCTAssertEqual(duck.calls.last, "robot.stop")
    }

    func testACardThatRunsOutOfTimeEndsTheRow() async throws {
        let duck = FakeDuck(walk: 0.07), said = Said()  // creeps: never stalls, never arrives in max_s
        let outcome = try await run(try cardPlan(["walk_forward", "turn_left"]), on: duck, said: said)
        guard case .stopped(0, let reason) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertEqual(reason, RobotPlanRunner.CardEnd.outOfTime.said)
        XCTAssertFalse(duck.moves.contains { $0.vyaw > 0.7 }, "the Turn card never ran")
        XCTAssertEqual(duck.calls.last, "robot.stop")
    }

    func testTheEndingsSayTheReadersWords() {
        // cardreader runner.ENDED, word for word.
        XCTAssertEqual(RobotPlanRunner.CardEnd.lost.said, "The duck stopped reporting where it is, so the row stopped there.")
        XCTAssertEqual(RobotPlanRunner.CardEnd.fell.said, "The duck fell, so the row stopped there.")
        XCTAssertEqual(RobotPlanRunner.CardEnd.outOfTime.said,
                       "The card ran out of time before it got there, so the row stopped there.")
        XCTAssertEqual(RobotPlanRunner.CardEnd.trimmedOut.said,
                       "The card stopped short of a quarter turn after its trims, so the row stopped there.")
        XCTAssertEqual(RobotPlanRunner.CardEnd.stuck.said,
                       "The duck could not do this card at the speeds it may be sent, so the row stopped there.")
        XCTAssertNil(RobotPlanRunner.CardEnd.reached.said)
    }

    func testAPoseThatStopsArrivingStopsTheCard() async throws {
        let duck = FakeDuck(), said = Said()
        let stale = DuckState(odom: .init(position: [0, 0, 0], yaw: 0), receivedAt: Date())
        let asked = Said()
        _ = try await RobotPlanRunner.run(
            try cardPlan(["walk_forward"]), on: duck, interval: 0.05, sleep: { duck.advance($0) },
            event: { if case .said(let s) = $0 { said.add(s) } },
            state: { stale },
            now: {
                // The same frame, read again and again while the clock runs on: after three
                // reads it is ten seconds old.
                asked.add("now")
                return stale.receivedAt.addingTimeInterval(asked.lines.count > 3 ? 10 : 0)
            })
        XCTAssertTrue(said.lines.contains(DuckCardLoop.lostNote))
    }
}
