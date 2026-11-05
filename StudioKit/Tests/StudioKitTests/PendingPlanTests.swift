import XCTest
@testable import StudioKit

/// Stop has to reach a plan before it is a run: the model may answer after the Stop was pressed.
@MainActor
final class PendingPlanTests: XCTestCase {

    /// One suspended step that a test releases by hand.
    private final class Gate: @unchecked Sendable {
        private var waiter: CheckedContinuation<Void, Never>?
        private var opened = false
        private let lock = NSLock()
        func wait() async {
            await withCheckedContinuation { c in
                lock.lock(); defer { lock.unlock() }
                if opened { c.resume() } else { waiter = c }
            }
        }
        func open() {
            lock.lock(); defer { lock.unlock() }
            opened = true
            waiter?.resume()
            waiter = nil
        }
    }

    private func make(_ path: StopPath) -> PendingPlan {
        PendingPlan(register: { path.register(.plan, cancel: $0) }, finished: { path.finished($0) })
    }

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }

    func testAnAnsweredPlanShowsThenRuns() async {
        let path = StopPath()
        let plan = make(path)
        var shown: [Int] = []
        var ran: [Int] = []
        var registeredWhenRun: [StopPath.RunKind]?
        plan.begin(asking: { 7 }, show: { shown.append($0) }, beat: 0, sleep: { _ in },
                   run: { ran.append($0); registeredWhenRun = path.registered })
        XCTAssertEqual(path.registered, [.plan])
        await settle()
        XCTAssertEqual(shown, [7])
        XCTAssertEqual(ran, [7])
        // Left before the run, or the run's own start would stop it.
        XCTAssertEqual(registeredWhenRun, [])
        XCTAssertFalse(plan.isPending)
    }

    /// The blocker: Stop during Thinking, then the model answers.
    func testStopWhileThinkingMeansALateAnswerNeverRuns() async {
        let path = StopPath()
        let plan = make(path)
        let model = Gate()
        var ran = 0, shown = 0, gone = 0
        plan.begin(asking: { () async -> Int? in await model.wait(); return 7 },
                   show: { _ in shown += 1 }, beat: 0, sleep: { _ in },
                   gone: { gone += 1 }, run: { _ in ran += 1 })
        await settle()
        path.stop()
        XCTAssertEqual(path.registered, [])
        XCTAssertFalse(path.admits)
        model.open()
        await settle()
        XCTAssertEqual(ran, 0)
        XCTAssertEqual(shown, 0)
        XCTAssertEqual(gone, 1)
        XCTAssertFalse(path.admits, "nothing may re-open the latch after a Stop")
    }

    /// Stop from anywhere during the preview beat: Siri, the Control, leaving the screen.
    func testStopDuringThePreviewBeatNeverRuns() async {
        let path = StopPath()
        let plan = make(path)
        var ran = 0, gone = 0
        plan.begin(asking: { 7 }, show: { _ in }, beat: 30, gone: { gone += 1 }, run: { _ in ran += 1 })
        await settle()
        path.stop()
        await settle()
        XCTAssertEqual(ran, 0)
        XCTAssertEqual(gone, 1)
        XCTAssertFalse(plan.isPending)
    }

    func testCancelLeavesNothingRegistered() async {
        let path = StopPath()
        let plan = make(path)
        var ran = 0
        plan.begin(asking: { 7 }, show: { _ in }, beat: 30, run: { _ in ran += 1 })
        plan.cancel()
        XCTAssertEqual(path.registered, [])
        await settle()
        XCTAssertEqual(ran, 0)
    }

    func testANilAnswerRunsNothingAndLeaves() async {
        let path = StopPath()
        let plan = make(path)
        var ran = 0
        plan.begin(asking: { nil as Int? }, show: { _ in }, beat: 0, sleep: { _ in }, run: { _ in ran += 1 })
        await settle()
        XCTAssertEqual(ran, 0)
        XCTAssertEqual(path.registered, [])
    }

    /// A newer sentence replaces the older one, whose late end must not touch the newer token.
    func testANewerBeginReplacesTheOlder() async {
        let path = StopPath()
        let plan = make(path)
        let slow = Gate()
        var ran: [Int] = []
        plan.begin(asking: { () async -> Int? in await slow.wait(); return 1 },
                   show: { _ in }, beat: 0, sleep: { _ in }, run: { ran.append($0) })
        await settle()
        plan.begin(asking: { 2 }, show: { _ in }, beat: 30, run: { ran.append($0) })
        await settle()
        slow.open()
        await settle()
        XCTAssertEqual(ran, [])
        XCTAssertEqual(path.registered, [.plan], "the older plan's end left the newer one in place")
        plan.cancel()
    }
}
