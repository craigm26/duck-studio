import XCTest
import DuckKit
@testable import StudioKit

/// A duck that writes down every line, can hold `robot.stop`'s answer, and can hang any other
/// call until it is cancelled.
final class StopTestDuck: DuckPeer, @unchecked Sendable {
    let identity = DuckIdentity(name: "Pip", kind: .real)
    let transportKind: DuckTransportKind = .bridge
    let reach = Set(DuckMethod.allCases)
    private let lock = NSLock()
    private var _sent: [String] = []
    private var refusals: [DuckMethod: [String]] = [:]
    private var stopGates: [CheckedContinuation<Void, Never>] = []
    private var holdStop = false
    /// Methods whose calls never answer until the caller is cancelled.
    var hang: Set<DuckMethod> = []

    var sent: [String] { lock.lock(); defer { lock.unlock() }; return _sent }
    var stops: Int { sent.filter { $0 == "robot.stop" }.count }

    /// Refuse the next calls of `method`, one reason each.
    func refuse(_ method: DuckMethod, _ reasons: [String]) {
        lock.lock(); refusals[method, default: []] += reasons; lock.unlock()
    }

    /// Keep `robot.stop` waiting for its answer until `release()`.
    func holdStopAnswers() { lock.lock(); holdStop = true; lock.unlock() }
    func release() {
        lock.lock(); holdStop = false; let gs = stopGates; stopGates = []; lock.unlock()
        for g in gs { g.resume() }
    }

    private func record(_ c: DuckCall) {
        lock.lock(); _sent.append(c.method.rawValue); lock.unlock()
    }

    func call(_ c: DuckCall) async throws -> DuckReply {
        try vet(c, asNotification: false)
        record(c)
        if c.method == .stop {
            lock.lock(); let hold = holdStop; lock.unlock()
            if hold { await withCheckedContinuation { g in lock.lock(); stopGates.append(g); lock.unlock() } }
        }
        if hang.contains(c.method) {
            let box = Box()
            await withTaskCancellationHandler {
                await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in box.set(k) }
            } onCancel: { box.resume() }
            throw CancellationError()
        }
        lock.lock()
        let reason = refusals[c.method]?.isEmpty == false ? refusals[c.method]!.removeFirst() : nil
        lock.unlock()
        // robotd answers robot.look with a LookResult (the joints it chose), never `accepted`.
        if c.method == .look {
            let look = #"{"head":{"neck_pitch":0,"head_pitch":-0.2,"head_yaw":0,"head_roll":0},"clamped":false}"#
            return DuckReply(id: 1, result: Data(look.utf8), failure: nil)
        }
        let body = reason.map { #"{"accepted":false,"reason":"\#($0)"}"# } ?? #"{"accepted":true}"#
        return DuckReply(id: 1, result: Data(body.utf8), failure: nil)
    }

    func notify(_ c: DuckCall) async throws {
        try vet(c, asNotification: true)
        if case .move(let t) = c, t == .still { lock.lock(); _sent.append("robot.move 0"); lock.unlock(); return }
        record(c)
    }

    nonisolated func states() -> AsyncStream<DuckState> { AsyncStream { $0.finish() } }

    /// A continuation that resumes exactly once, whichever of set and resume comes first.
    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var k: CheckedContinuation<Void, Never>?
        private var done = false
        func set(_ k: CheckedContinuation<Void, Never>) {
            lock.lock()
            if done { lock.unlock(); k.resume(); return }
            self.k = k; lock.unlock()
        }
        func resume() {
            lock.lock(); done = true; let k = self.k; self.k = nil; lock.unlock()
            k?.resume()
        }
    }
}

final class StopPathTests: XCTestCase {

    // MARK: - what it may depend on

    func testTheFileImportsFoundationAndNamesNoModel() throws {
        let here = URL(fileURLWithPath: #filePath)
        let source = here.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/StudioKit/StopPath.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        let imports = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") || $0.hasPrefix("@_exported import ") }
        XCTAssertEqual(imports, ["import Foundation"], "StopPath imports Foundation and nothing else")
        for name in ["DreamPilot", "DreamRows", "Planner", "PhoneModel", "ModelEndpoint", "DuckTalk",
                     "FoundationModels", "LanguageModel", "DuckOrder", "await self", "Dream"] {
            XCTAssertFalse(text.contains(name), "StopPath must not name \(name)")
        }
    }

    // MARK: - order

    func testRobotStopFirstThenTheLatchThenTheRuns() async {
        let duck = StopTestDuck()
        let path = StopPath(peer: duck)
        path.register(.pilot) {}
        path.register(.plan) {}
        let pressed = path.stop()
        XCTAssertEqual(path.journal, [.robotStop(sent: true), .queueBlocked, .runsCancelled([.pilot, .plan])])
        await pressed.wire?.value
        XCTAssertEqual(duck.sent, ["robot.stop"])
        XCTAssertFalse(path.admits)
        XCTAssertEqual(path.registered, [])
    }

    /// The wire task is started before any run is cancelled: a slow cancel finds robot.stop
    /// already on the wire while it is still running.
    func testRobotStopIsOnTheWireWhileASlowCancelIsStillRunning() {
        let duck = StopTestDuck()
        let path = StopPath(peer: duck)
        let sawStop = StopFlag()
        path.register(.chain) {
            let until = Date().addingTimeInterval(1)
            while Date() < until {
                if duck.stops > 0 { sawStop.set(); return }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        path.stop()
        XCTAssertTrue(sawStop.value, "robot.stop reached the wire before the cancel finished")
    }

    // MARK: - idempotence

    func testTwiceIsOnce() async {
        let duck = StopTestDuck()
        duck.holdStopAnswers()
        let path = StopPath(peer: duck)
        let cancels = StopCounter()
        path.register(.goal) { _ = cancels.next() }
        let first = path.stop()
        let journal = path.journal
        let second = path.stop()
        XCTAssertEqual(path.journal, journal, "a second press adds nothing")
        XCTAssertEqual(first.caption, second.caption)
        XCTAssertEqual(cancels.next(), 2, "cancelled once")
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(duck.stops, 1, "one robot.stop while the first is unanswered")
        duck.release()
        await first.wire?.value
        await second.wire?.value
        XCTAssertFalse(path.admits)
    }

    /// A robot.stop that never answers (a half-open link) must not silence later presses.
    func testAnUnansweredStopDoesNotSilenceALaterPress() async {
        let duck = StopTestDuck()
        duck.holdStopAnswers()
        let clock = StopClock()
        let path = StopPath(peer: duck, now: { clock.now })
        _ = path.stop()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(duck.stops, 1)
        clock.advance(StopPath.resendAfter + 0.01)
        _ = path.stop()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(duck.stops, 2, "past the window, a press writes robot.stop again")
        duck.release()
    }

    /// The answer is held, the duck is re-attached on a new connection, and Stop must reach it.
    func testAStopAfterAReattachIsWrittenToTheNewDuck() async {
        let old = StopTestDuck()
        old.holdStopAnswers()
        let path = StopPath(peer: old)
        _ = path.stop()
        try? await Task.sleep(nanoseconds: 30_000_000)
        let fresh = StopTestDuck()
        path.attach(fresh)
        let pressed = path.stop()
        await pressed.wire?.value
        XCTAssertEqual(fresh.sent, ["robot.stop"], "the new connection hears the stop at once")
        XCTAssertEqual(old.stops, 1)
        old.release()
    }

    /// A stop that lands while a caption is being said keeps the step behind it off the wire.
    func testAStopDuringTheCaptionKeepsTheStepOffTheWire() async {
        let duck = StopTestDuck()
        let path = StopPath(peer: duck)
        let ended = await DuckOrderRunner.run(.skill("kick_left"), ready: DuckOrder.Readiness(driving: true, homed: true),
                                              on: duck, stopPath: path,
                                              said: { _ in path.stop() }, sleep: { _ in })
        XCTAssertEqual(ended, .stopped)
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertFalse(duck.sent.contains("robot.do"), "robot.do never went out: \(duck.sent)")
    }

    /// A stop that lands during the homing retry's sleep keeps the next try off the wire.
    func testAStopDuringAHomingRetryEndsTheRetries() async {
        let duck = StopTestDuck()
        duck.refuse(.doSkill, Array(repeating: "the robot is still going to its home pose; try again in a moment",
                                    count: 5))
        let path = StopPath(peer: duck)
        let ended = await DuckOrderRunner.run(.skill("kick_left"), ready: DuckOrder.Readiness(driving: true),
                                              on: duck, stopPath: path, sleep: { _ in path.stop() })
        XCTAssertEqual(ended, .stopped)
        XCTAssertEqual(duck.sent.filter { $0 == "robot.do" }.count, 1, "one try, then the stop")
    }

    func testAPressAfterTheAnswerSendsStopAgain() async {
        let duck = StopTestDuck()
        let path = StopPath(peer: duck)
        await path.stop().wire?.value
        await path.stop().wire?.value
        XCTAssertEqual(duck.stops, 2, "a stop is never refused")
        XCTAssertEqual(path.journal.filter { $0 == .queueBlocked }.count, 1)
    }

    func testNoDuckStillLatchesAndCancels() {
        let path = StopPath()
        let cancelled = StopFlag()
        path.register(.walk) { cancelled.set() }
        let pressed = path.stop()
        XCTAssertNil(pressed.wire)
        XCTAssertTrue(cancelled.value)
        XCTAssertEqual(path.journal, [.robotStop(sent: false), .queueBlocked, .runsCancelled([.walk])])
    }

    // MARK: - queued steps

    func testQueuedStepsAreBlocked() async {
        let duck = StopTestDuck()
        let path = StopPath(peer: duck)
        let ticks = StopCounter()
        let ended = await DuckOrderRunner.run(.walk(.forward, seconds: 5),
                                              ready: DuckOrder.Readiness(sitting: false, driving: true, homed: true),
                                              on: duck, stopPath: path,
                                                sleep: { _ in if ticks.next() == 3 { path.stop() } })
        XCTAssertEqual(ended, .stopped)
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(duck.sent.filter { $0 == "robot.move" }.count, 3, "nothing after the stop")
        XCTAssertEqual(duck.stops, 1)

        // A step queued after the stop goes nowhere until a person re-arms.
        let before = duck.sent
        let again = await DuckOrderRunner.run(.skill("kick_left"), on: duck, stopPath: path, sleep: { _ in })
        XCTAssertEqual(again, .stopped)
        XCTAssertEqual(duck.sent, before)
        path.rearm()
        let fresh = await DuckOrderRunner.run(.sound(.chirp), on: duck, stopPath: path, sleep: { _ in })
        XCTAssertEqual(fresh, .finished)
    }

    // MARK: - a hung run

    func testAHungRunDoesNotDelayTheStop() async {
        let duck = StopTestDuck()
        duck.hang = [.dream]
        let path = StopPath(peer: duck)
        let run = Task { _ = try? await duck.call(.dream(.status)) }
        path.register(.pilot, task: run)
        try? await Task.sleep(nanoseconds: 20_000_000)
        let pressed = Date()
        let press = path.stop()
        XCTAssertLessThan(Date().timeIntervalSince(pressed), 0.05, "stop() returned at once")
        await press.wire?.value
        XCTAssertLessThan(Date().timeIntervalSince(pressed), 0.05, "robot.stop answered within 50 ms")
        XCTAssertEqual(duck.sent.last, "robot.stop")
        await run.value
    }

    func testARunningCommandIsCancelledByAStop() async {
        let duck = StopTestDuck()
        duck.hang = [.doSkill]
        let path = StopPath(peer: duck)
        let run = Task { await DuckOrderRunner.run(.skill("roulade"), on: duck, stopPath: path, sleep: { _ in }) }
        while !duck.sent.contains("robot.do") { try? await Task.sleep(nanoseconds: 2_000_000) }
        XCTAssertEqual(path.registered, [.command])
        path.stop()
        let ended = await run.value
        XCTAssertEqual(ended, .stopped)
        XCTAssertEqual(path.registered, [])
    }

    // MARK: - the words

    func testCaptionWhileASkillRunsDoesNotClaimACancel() {
        let path = StopPath()
        XCTAssertEqual(path.stop().caption, "Stopped.")
        path.skillStarted(seconds: 2)
        XCTAssertEqual(path.stop().caption, "Stopping after this move.")
        path.skillEnded()
        XCTAssertEqual(path.stop().caption, "Stopped.")
        for words in [StopPath.Words.stopped, StopPath.Words.stoppingAfterThisMove] {
            XCTAssertFalse(words.contains("\u{2014}"))
            XCTAssertFalse(words.lowercased().contains("cancel"))
        }
    }

    func testASkillWindowEndsOnTheClock() {
        let clock = StopClock()
        let path = StopPath(now: { clock.now })
        path.skillStarted(seconds: 1.5)
        XCTAssertTrue(path.skillRunning)
        clock.advance(2)
        XCTAssertFalse(path.skillRunning)
    }
}

final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return _value }
    func set() { lock.lock(); _value = true; lock.unlock() }
}

final class StopCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
}

final class StopClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t = Date(timeIntervalSince1970: 0)
    var now: Date { lock.lock(); defer { lock.unlock() }; return t }
    func advance(_ s: Double) { lock.lock(); t = t.addingTimeInterval(s); lock.unlock() }
}
