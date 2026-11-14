import Foundation

// MARK: - the arbiter's clamp

extension ControlArbiter {
    /// A planner's decision held to one decision's limits AND to the time this run has left
    /// (brains-layer.md 3.3: "the arbiter clamps every duration and count to the run caps, and
    /// the decision's own values are never trusted"). Returns how much was cut, 0 to 1.
    ///
    /// - `.drive`: seconds at most `DuckDecision.maxDriveSeconds` and at most `secondsLeft`.
    /// - `.plan`: at most `RobotPlanProposal.maxBeats` beats, and timed beats at most
    ///   `RobotPlanProposal.maxWalkSeconds` and at most `secondsLeft` in all.
    /// - everything else: `DuckDecision.clamped()`.
    public static func clamp(_ decision: DuckDecision, secondsLeft: Double) -> (decision: DuckDecision, cut: Double) {
        let left = secondsLeft.isFinite ? max(secondsLeft, 0) : 0
        switch decision {
        case .drive(let source, let goal, let s):
            let cs = min(max(s, 0), DuckDecision.maxDriveSeconds, left)
            return (.drive(source: source, goal: goal, seconds: cs), s > 0 ? max(0, 1 - cs / s) : 0)
        case .plan(let p):
            let (cp, cut) = p.clamped(walkSeconds: min(RobotPlanProposal.maxWalkSeconds, left))
            return (.plan(cp), cut)
        default:
            return decision.clamped()
        }
    }
}

// MARK: - one gate for a run, shared by its decisions and its rows

/// The run's `DuckEnvelopeGate`, behind an actor so a drive leg's rows and the run's decision
/// checks go through the same one. A cut from either side cuts the other: after a row is cut,
/// every later motion decision in the run is cut too, until a person starts a new run.
public actor GateHolder {
    public private(set) var gate: DuckEnvelopeGate

    public init(_ gate: DuckEnvelopeGate) { self.gate = gate }

    public var isBound: Bool { gate.binding != nil }

    public func check(_ decided: Decided, at t: Double, phoneUnlocked: Bool = true) throws -> DuckEnvelopeGate.DecisionCheck {
        try gate.check(decided, at: t, phoneUnlocked: phoneUnlocked)
    }

    public func confirm(_ decided: Decided, at t: Double, phoneUnlocked: Bool = true) throws -> DuckEnvelopeGate.DecisionCheck {
        try gate.confirm(decided, at: t, phoneUnlocked: phoneUnlocked)
    }

    public func act(_ row: DuckEnvelopeGate.Row) throws -> DuckEnvelopeGate.Result {
        try gate.act(row)
    }
}

// MARK: - carrying out a `.drive` or a `.plan`

/// Carries out one `.drive` or `.plan` decision, then hands control back (3.3, later rows).
///
/// THIS IS NOT THE BRAIN RUNNER. Build 91's `BrainRunner` (the loop that asks a planner, checks
/// each decision, runs it and asks again) does not exist yet, and neither do the v1 executors for
/// `.skill`, `.walk` and `.turn`. These are the two later rows of the executor table, as kit
/// functions a runner will call: each one re-checks and re-clamps its decision itself, runs it,
/// and returns an `Ending` that says why control came back. Nothing in the app calls them yet.
///
/// WHAT EACH ONE TRUSTS: NOTHING IN THE DECISION. Both re-admit the decision against the run's
/// `AllowedDecisions` and re-clamp it with `ControlArbiter.clamp` before anything moves, even if
/// the gate already did, so a caller that skipped the gate still cannot send a long drive, an
/// unknown source or a seven-beat plan.
public enum PlannerLeg {

    /// Why control came back to the planner.
    public enum Ending: Equatable, Sendable {
        /// The drive ran its clamped time, or the plan finished.
        case done
        /// The gate cut the leg (keep-in, stale odometry, tilt, run cap). The duck was told to
        /// stop, and every later motion decision in this run is cut too.
        case gateCut(DuckEnvelopeGate.Rule)
        /// It ended another way after something may have moved: the source failed, a Stop, a
        /// skill the robot refused mid-plan, a card that did not arrive. The words say which.
        case stopped(String)
        /// Refused before anything moved.
        case refused(String)
    }

    public enum Words {
        public static func noSuchSource(_ id: String) -> String {
            "The planner asked for the driver \(id), and this app has no such driver ready. Nothing moved."
        }
        public static let gateNotBound = "The limits were not set up for this run, so nothing moved."
        public static let noTimeLeft = "This run has no time left for the driver. Nothing moved."
        public static let notThisKind = "That decision is not one this step carries out. Nothing moved."
        public static let gateCut = "The duck reached one of its limits, so the driver was stopped."

        public static let all = [noSuchSource("x"), gateNotBound, noTimeLeft, notThisKind, gateCut]
    }

    // MARK: .drive

    /// An action source the app has ready for this run, by its id in the closed set.
    public struct DriveSource: Sendable {
        public let id: ActionSourceID
        /// The model or checkpoint the source is asked for.
        public let checkpoint: String
        public let rows: any DreamRows

        public init(id: ActionSourceID, checkpoint: String, rows: any DreamRows) {
            self.id = id
            self.checkpoint = checkpoint
            self.rows = rows
        }
    }

    /// What the duck reports when a row is made: what the gate checks it against.
    public struct Reading: Equatable, Sendable {
        public let odomAgeMs: Double?
        public let pose: DuckEnvelopeGate.Pose?
        public let tiltDeg: Double?
        public let observationAgeS: Double?
        public let phoneUnlocked: Bool

        public init(odomAgeMs: Double?, pose: DuckEnvelopeGate.Pose?, tiltDeg: Double? = nil,
                    observationAgeS: Double? = nil, phoneUnlocked: Bool = true) {
            self.odomAgeMs = odomAgeMs
            self.pose = pose
            self.tiltDeg = tiltDeg
            self.observationAgeS = observationAgeS
            self.phoneUnlocked = phoneUnlocked
        }

        /// Nothing reported. The gate holds, then cuts: keep-in cannot be checked blind.
        public static let none = Reading(odomAgeMs: nil, pose: nil)
    }

    /// Hand the duck to the named source with the gate bound on every row, for at most the
    /// clamped seconds. `runStart` is when the planner's run began, for the gate's run cap.
    ///
    /// THE GATE IS THE RUN'S OWN. It must already be bound (`DuckEnvelopeGate.bind`); an unbound
    /// gate refuses the leg. Each row goes through `act` after the stick clamp, and the gate's
    /// twist is what is sent. A cut or invalid row ends the leg through `DreamPilot`'s own ending:
    /// `robot.stop`, then the source's `end`.
    ///
    /// NO ASSIST. `DuckAssist` does not exist yet, so the source drives plain. The spec allows a
    /// plain source ("Dream-1 (plain)"), and "+ assist" is a label only a measured row may earn.
    public static func drive(_ decision: DuckDecision,
                             allowed: AllowedDecisions,
                             secondsLeft: Double,
                             sources: [DriveSource],
                             gate: GateHolder,
                             runStart: Date,
                             on peer: any DuckPeer,
                             frames: @escaping @Sendable () async -> [String],
                             reading: @escaping @Sendable () async -> Reading,
                             events: @escaping @Sendable (DreamPilot.Event) async -> Void = { _ in },
                             sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) },
                             now: @escaping @Sendable () -> Date = Date.init) async -> Ending {
        guard case .drive = decision else { return .refused(Words.notThisKind) }
        if case .failure(let r) = allowed.admit(decision) { return .refused(r.says) }
        guard case .drive(let id, let goal, let seconds) = ControlArbiter.clamp(decision, secondsLeft: secondsLeft).decision
        else { return .refused(Words.notThisKind) }
        guard seconds >= 1 / DreamPilot.rowsPerSecond else { return .refused(Words.noTimeLeft) }
        guard let source = sources.first(where: { $0.id == id }) else { return .refused(Words.noSuchSource(id.rawValue)) }
        guard await gate.isBound else { return .refused(Words.gateNotBound) }

        let cut = CutBox()
        let ended = SaidBox()
        let pilot = DreamPilot(checkpoint: source.checkpoint, prompt: goal, limit: seconds)
        await pilot.run(on: peer, rows: source.rows, frames: frames,
                        events: { e in
                            switch e {
                            case .ended(let said):
                                await ended.set(said)
                            case .asked:
                                // WAIT: the pilot has just sent a zero twist (A2). It goes in the
                                // gate's log as a row too, so the rate rule eases the next chunk
                                // in from still and a cut found while standing ends the leg.
                                let r = await reading()
                                let row = DuckEnvelopeGate.Row(
                                    t: now().timeIntervalSince(runStart), twist: .still,
                                    odomAgeMs: r.odomAgeMs, observationAgeS: nil, pose: r.pose,
                                    tiltDeg: r.tiltDeg, phoneUnlocked: r.phoneUnlocked, phase: "wait")
                                if let result = try? await gate.act(row), result.stopPath {
                                    await cut.set(result.rule ?? .run)
                                }
                            default:
                                break
                            }
                            await events(e)
                        },
                        sleep: sleep, now: now,
                        filter: { twist in
                            let r = await reading()
                            let row = DuckEnvelopeGate.Row(
                                t: now().timeIntervalSince(runStart), twist: GateTwist(twist),
                                odomAgeMs: r.odomAgeMs, observationAgeS: r.observationAgeS, pose: r.pose,
                                tiltDeg: r.tiltDeg, phoneUnlocked: r.phoneUnlocked, phase: "drive")
                            guard let result = try? await gate.act(row) else {
                                return .end(Words.gateNotBound)
                            }
                            if result.stopPath {
                                await cut.set(result.rule ?? .run)
                                return .end(Words.gateCut)
                            }
                            return .send(result.sent.drive)
                        })
        if let rule = await cut.rule { return .gateCut(rule) }
        let said = await ended.said ?? DuckDream.Words.stopped
        return said == DuckDream.Words.timeUp ? .done : .stopped(said)
    }

    private actor CutBox {
        var rule: DuckEnvelopeGate.Rule?
        func set(_ r: DuckEnvelopeGate.Rule) { if rule == nil { rule = r } }
    }

    private actor SaidBox {
        var said: String?
        func set(_ s: String) { said = s }
    }

    // MARK: .plan

    /// Run the plan with `RobotPlanRunner`, after the arbiter's clamp. `RobotPlan`'s refusals
    /// and the runner's refusal before anything moves (the link's reach, the robot's skill list)
    /// apply unchanged, because this is the same `RobotPlan(DuckIntentPlan)` door every plan uses.
    public static func plan(_ decision: DuckDecision,
                            allowed: AllowedDecisions,
                            secondsLeft: Double,
                            request: String,
                            on peer: any DuckPeer,
                            interval: Double,
                            sleep: @escaping RobotPlanRunner.Sleep,
                            event: @escaping @Sendable (RobotPlanRunner.Event) async -> Void = { _ in },
                            state: RobotPlanRunner.State? = nil,
                            now: @escaping @Sendable () -> Date = { Date() }) async -> Ending {
        guard case .plan = decision else { return .refused(Words.notThisKind) }
        if case .failure(let r) = allowed.admit(decision) { return .refused(r.says) }
        guard case .plan(let proposal) = ControlArbiter.clamp(decision, secondsLeft: secondsLeft).decision
        else { return .refused(Words.notThisKind) }
        let plan: RobotPlan
        do {
            // Already clamped to `secondsLeft`; the build clamps again to the plan ceiling.
            plan = try proposal.robotPlan(request: request)
        } catch let r as RobotPlan.Refusal {
            return .refused(r.message)
        } catch {
            return .refused(error.localizedDescription)
        }
        do {
            switch try await RobotPlanRunner.run(plan, on: peer, interval: interval, sleep: sleep,
                                                 event: event, state: state, now: now) {
            case .finished: return .done
            case .refused(_, let reason): return .stopped(reason)
            case .stopped(_, let reason): return .stopped(reason)
            }
        } catch let r as RobotPlanRunner.Refusal {
            return .refused(r.message)
        } catch is CancellationError {
            return .stopped(DuckDream.Words.stopped)
        } catch {
            return .stopped(error.localizedDescription)
        }
    }
}
