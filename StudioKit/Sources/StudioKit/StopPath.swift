import Foundation

/// The one way anything in this app stops the duck.
///
/// EVERY SURFACE CALLS THIS AND NOTHING ELSE: the red disc and the Stop pill, magic tap, Space
/// or Escape on the Mac, the pad's B-hold, a heard "stop", Siri, the Control, the Lock Screen,
/// the Live Activity and the Action button (docs/plans/native-first-redesign.md, "Rules across
/// all modes"). A surface that grew its own stop would be the one that forgot a step. A run
/// that writes to the duck registers here, or the Stop this file promises does not reach it.
///
/// THE ORDER IS THE BRAINS-LAYER ONE (docs/plans/brains-layer.md 6.1), not the older list in the
/// redesign plan, because nothing may be awaited before the stop goes out:
/// 1. `robot.stop` is put on its way to the duck first, in its own task, awaiting nothing
///    (the approach the build-90 stop-first fix took on the hosted-driver screen);
/// 2. the latch is set, so every queued step is refused from here on;
/// 3. every registered run (pilot, chain, plan, goal, walk, command) is cancelled, and none of
///    them is awaited. A run hung inside a model call cannot hold the stop back.
///
/// IT IMPORTS FOUNDATION AND NOTHING ELSE, and it names no model, planner or pilot type. A
/// model may ask for a stop; that request calls this like any other surface. The reverse
/// dependency, a stop that waits on a model, is the failure this file exists to make
/// impossible, and `StopPathTests` reads this source to keep it that way.
///
/// IT CANNOT CANCEL A SKILL THE ROBOT HAS ALREADY STARTED. robotd's `robot.stop` zeroes the
/// twist and nothing else (found on robotd 0.15.1 in duck-sim, 2026-10-03), so a kick or a roll
/// runs to its end. While one is running the caption is "Stopping after this move." and no
/// sentence in this app may describe Stop as cancelling a skill.
///
/// IDEMPOTENT, BUT NEVER SILENCED. A second press within `resendAfter` of a `robot.stop` that
/// has not been answered yet sends nothing more and returns the same wire task (a double tap,
/// or the disc and a heard "stop" together); the latch is already set and the runs are already
/// gone. Any later press sends `robot.stop` again, answered or not, which robotd treats the
/// same as the first (it zeroes an already-zero twist). The window is short and time-bound on
/// purpose: `LinePeer.call` has no timeout, so a `robot.stop` lost on a half-open link never
/// answers, and a dedupe keyed on "still waiting" alone would make every later Stop send
/// nothing. `attach(_:)` forgets the unanswered stop too, so Stop on a new connection always
/// reaches the new duck.
public final class StopPath: @unchecked Sendable {

    /// The app's one instance. Tests make their own.
    public static let shared = StopPath()

    /// What a registered run is, so a test and a log can say what was cancelled.
    public enum RunKind: String, Sendable, CaseIterable {
        case pilot, chain, plan, goal, walk, command
    }

    /// A registered run, handed back so it can leave when it ends on its own.
    public struct Token: Hashable, Sendable {
        fileprivate let id: Int
    }

    /// One thing a stop did, in the order it did it.
    public enum Step: Equatable, Sendable {
        /// `robot.stop` was put on its way (or there was no duck to send it to).
        case robotStop(sent: Bool)
        /// The latch went from open to shut: queued steps are refused from here.
        case queueBlocked
        /// These runs were told to cancel, in the order they registered.
        case runsCancelled([RunKind])
    }

    /// What a press of Stop answers with.
    public struct Pressed: Sendable {
        /// The `robot.stop` call, for a caller (or a test) that wants to know it was answered.
        /// Nobody on the stop path awaits it.
        public let wire: Task<Void, Never>?
        /// The one line under the Stop button.
        public let caption: String
    }

    /// The sentences a stop puts on screen.
    public enum Words {
        public static let stopped = "Stopped."
        /// While a robot skill runs. `robot.stop` does not cancel a started skill.
        public static let stoppingAfterThisMove = "Stopping after this move."
    }

    private let lock = NSLock()
    private var peer: (any DuckPeer)?
    private var runs: [(token: Token, kind: RunKind, cancel: @Sendable () -> Void)] = []
    private var nextID = 0
    private var latched = false
    private var inFlight: Task<Void, Never>?
    private var inFlightSince: Date?
    private var wireGeneration = 0
    private var skillUntil: Date?
    private var _journal: [Step] = []
    private let now: @Sendable () -> Date

    /// How long an unanswered `robot.stop` stands in for a second press. Past this, a press
    /// writes `robot.stop` again whether or not the first was answered.
    public static let resendAfter = 0.25

    public init(peer: (any DuckPeer)? = nil, now: @escaping @Sendable () -> Date = { Date() }) {
        self.peer = peer
        self.now = now
    }

    // MARK: - which duck

    /// The duck a stop goes to: the one the app is connected to now. Nil when there is none,
    /// and a stop then still latches and cancels. A `robot.stop` still waiting on the old
    /// connection is forgotten, so the next Stop is written to this one.
    public func attach(_ peer: (any DuckPeer)?) {
        lock.lock()
        self.peer = peer
        inFlight = nil
        inFlightSince = nil
        wireGeneration += 1
        lock.unlock()
    }

    // MARK: - stop

    /// Stop. Synchronous, so no surface can put an `await` in front of it.
    @discardableResult
    public func stop() -> Pressed {
        // 1. THE WIRE FIRST. The task is created before anything else is touched, and nothing
        //    here waits for it.
        lock.lock()
        let target = peer
        let pressedAt = now()
        var wire: Task<Void, Never>? = nil
        if let pending = inFlight, let since = inFlightSince,
           pressedAt.timeIntervalSince(since) < Self.resendAfter {
            wire = pending
        }
        var sent = false
        if wire == nil, let target {
            wireGeneration += 1
            let generation = wireGeneration
            wire = Task.detached(priority: .high) { [weak self] in
                _ = try? await target.call(.stop)
                self?.answered(generation)
            }
            inFlight = wire
            inFlightSince = pressedAt
            sent = true
        }
        if sent || target == nil { _journal.append(.robotStop(sent: sent)) }

        // 2. THE LATCH. Every queued step asks `admits` before it goes, and is refused now.
        if !latched {
            latched = true
            _journal.append(.queueBlocked)
        }

        // 3. THE RUNS, cancelled outside the lock and never awaited.
        let cancelling = runs
        runs.removeAll()
        if !cancelling.isEmpty { _journal.append(.runsCancelled(cancelling.map(\.kind))) }
        trimJournalLocked()
        let caption = skillRunningLocked() ? Words.stoppingAfterThisMove : Words.stopped
        lock.unlock()

        for run in cancelling { run.cancel() }
        return Pressed(wire: wire, caption: caption)
    }

    private func trimJournalLocked() {
        if _journal.count > 64 { _journal.removeFirst(_journal.count - 64) }
    }

    private func answered(_ generation: Int) {
        lock.lock()
        if generation == wireGeneration { inFlight = nil; inFlightSince = nil }
        lock.unlock()
    }

    // MARK: - the latch

    /// Whether a queued step may go to the duck. False from a stop until a person starts
    /// something new. Every runner asks this before each step it sends.
    public var admits: Bool {
        lock.lock(); defer { lock.unlock() }
        return !latched
    }

    /// Open the latch. ONLY A PERSON'S OWN ACTION in this app calls this: a tap on a move, a
    /// stick touch, a spoken command they gave. A model, a bridge or an MCP client never does,
    /// so nothing re-arms itself after a stop.
    public func rearm() {
        lock.lock(); latched = false; lock.unlock()
    }

    // MARK: - runs

    /// Register something that runs on the duck, with how to cancel it. Cancelling must not
    /// block; `Task.cancel()` does not.
    @discardableResult
    public func register(_ kind: RunKind, cancel: @escaping @Sendable () -> Void) -> Token {
        lock.lock(); defer { lock.unlock() }
        nextID += 1
        let token = Token(id: nextID)
        runs.append((token, kind, cancel))
        return token
    }

    /// Register a task as a run; a stop cancels it.
    @discardableResult
    public func register<T, E>(_ kind: RunKind, task: Task<T, E>) -> Token {
        register(kind) { task.cancel() }
    }

    /// A run that ended on its own leaves, so a later stop does not cancel a stranger.
    public func finished(_ token: Token) {
        lock.lock(); runs.removeAll { $0.token == token }; lock.unlock()
    }

    /// The runs a stop would cancel now, in registration order.
    public var registered: [RunKind] {
        lock.lock(); defer { lock.unlock() }
        return runs.map(\.kind)
    }

    // MARK: - a skill the robot is running

    /// A runner says a robot skill was accepted and roughly how long it holds the duck, so a
    /// stop in that window says "Stopping after this move." rather than claiming it cancelled.
    public func skillStarted(seconds: Double) {
        lock.lock()
        skillUntil = now().addingTimeInterval(max(0, seconds.isFinite ? seconds : 0))
        lock.unlock()
    }

    /// The skill's own end, when the runner knows it.
    public func skillEnded() {
        lock.lock(); skillUntil = nil; lock.unlock()
    }

    /// Whether a robot skill is believed to be running now.
    public var skillRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return skillRunningLocked()
    }

    private func skillRunningLocked() -> Bool {
        guard let until = skillUntil else { return false }
        return now() < until
    }

    // MARK: - for tests and logs

    /// Every step every stop took, oldest first.
    public var journal: [Step] {
        lock.lock(); defer { lock.unlock() }
        return _journal
    }
}
