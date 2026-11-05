import Foundation

/// A sentence on its way to becoming a run: from the words being asked, through the model's answer
/// and the preview beat, up to the moment the run starts.
///
/// NOTHING IS MOVING YET, AND A STOP STILL HAS TO END IT. The run that follows re-opens the latch,
/// so a plan left unregistered while a model thinks would undo a Stop pressed during Thinking,
/// and a model must never re-open the latch (`StopPath.rearm`). So the whole wait is one task,
/// registered with the one Stop like any run: Stop, Siri, the Control and leaving the foreground
/// all cancel it, and `run` is never reached after that.
///
/// THE TOKEN LEAVES BEFORE `run` IS CALLED. Starting a run stops whatever ran before it, and
/// this must not be the thing stopped.
@MainActor
public final class PendingPlan {

    public typealias Sleep = @Sendable (Double) async throws -> Void

    private let register: (@escaping @Sendable () -> Void) -> StopPath.Token
    private let finished: (StopPath.Token) -> Void
    private var work: Task<Void, Never>?
    private var token: StopPath.Token?
    private var latest = 0

    public init(register: @escaping (@escaping @Sendable () -> Void) -> StopPath.Token,
                finished: @escaping (StopPath.Token) -> Void) {
        self.register = register
        self.finished = finished
    }

    /// Whether a plan is being worked out or shown.
    public var isPending: Bool { work != nil }

    /// Ask for a plan, show it for `beat` seconds, then run it. A newer `begin` replaces this one.
    ///
    /// - Parameters:
    ///   - asking: Works out the plan; nil means there is nothing to run.
    ///   - show: Puts the plan on screen for its beat.
    ///   - gone: Called when a plan that was asked for will not run.
    ///   - run: Starts the run. Never called once this has been cancelled.
    public func begin<Plan: Sendable>(asking: @escaping @MainActor () async -> Plan?,
                                      show: @escaping @MainActor (Plan) -> Void,
                                      beat: Double,
                                      sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
                                      gone: @escaping @MainActor () -> Void = {},
                                      run: @escaping @MainActor (Plan) -> Void) {
        cancel()
        latest += 1
        let mine = latest
        let task = Task { @MainActor [weak self] in
            guard let plan = await asking(), !Task.isCancelled else {
                if self?.leave(mine) == true { gone() }
                return
            }
            show(plan)
            do { try await sleep(beat) } catch {}
            guard !Task.isCancelled else {
                if self?.leave(mine) == true { gone() }
                return
            }
            self?.leave(mine)
            run(plan)
        }
        work = task
        token = register { task.cancel() }
    }

    /// Drop the plan on its way, if there is one. It will not run.
    public func cancel() {
        work?.cancel()
        leave(latest)
    }

    /// This plan is over, unless a newer one has replaced it. Answers whether it was still the latest.
    @discardableResult
    private func leave(_ which: Int) -> Bool {
        guard which == latest else { return false }
        work = nil
        if let token { finished(token) }
        token = nil
        return true
    }
}
