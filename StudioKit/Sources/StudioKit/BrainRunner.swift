import Foundation
import DuckKit

// MARK: - the goal

/// The run's goal, from the person's own turn only (brains-layer.md 3.2; #76).
///
/// A planner, a tool, an MCP note, a camera picture and a model's own `.ask` never make one: the
/// runner takes it once, when the person starts the run, and every `PlannerAsk` and every drive
/// leg in that run gets exactly these words. What the person answers to an `.ask` goes in as
/// `PlannerAsk.utterance`, never as the goal.
public struct HumanGoal: Equatable, Sendable {
    public let text: String

    /// What the person typed or said to start the run. Nil when it holds nothing.
    public init?(personSaid: String) {
        let text = personSaid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        self.text = text
    }
}

// MARK: - the one way a planner picture is made in a run

/// Where a run's planner picture comes from. It can only be built from a camera picture, a face
/// blur and an encoder, and the runner hands those to `PlannerFrameGate.frame` itself, with the
/// consent switch read from the planner's own `PlannerSafetySettings`. There is no way to hand a
/// run a finished JPEG, so no picture reaches a planner without consent and without the blur.
/// The app passes `PlannerFrames.faceBlur` and `PlannerFrames.jpeg`.
public struct PlannerPictureSource: Sendable {
    let make: @Sendable (PlannerInfo, PlannerSafetySettings) async -> PlannerFrameGate.Outcome

    public init<Picture>(picture: @escaping @Sendable () async -> Picture?,
                         blur: PlannerFaceBlur<Picture>,
                         encode: @escaping @Sendable (Picture) -> Data?) {
        make = { info, settings in
            let shot = await picture()
            return PlannerFrameGate.frame(shot, for: info, settings: settings, blur: blur, encode: encode)
        }
    }

    private init(none: Void) {
        make = { _, _ in .noPicture }
    }

    /// No camera: no picture goes to any planner.
    public static let none = PlannerPictureSource(none: ())
}

// MARK: - the runner

/// Carries out a planner's decisions on a duck, one at a time (brains-layer.md 3.3).
///
/// A PLANNER CALLS NOTHING. This asks it for one `DuckDecision`, clamps the decision with
/// `ControlArbiter.clamp` to the run's time left, checks it with the run's `DuckEnvelopeGate`,
/// asks the person for a Go when the gate says to, carries it out, and asks again.
///
/// OWNED BY THE ARBITER. It runs only for a `ControlArbiter.Run` (which only the arbiter's
/// `.start` makes) of kind `.tell` or `.goal`; the run's duck sets the venue and its `endsBy` the
/// cap. It registers with `StopPath` as a goal, so every arbiter effect that calls the stop path
/// (Stop, a stick touch, the cap, a lost connection, leaving the foreground) cancels it, and it
/// never waits on a model to let go: a planner that never answers is abandoned at once.
///
/// WHAT CANNOT BE BYPASSED, BY CONSTRUCTION.
/// - The planner is an `AgreedPlanner`, never a bare `Planner`: no model is asked anything
///   without the adult's current agreement.
/// - Camera consent is read from that planner's `PlannerSafetySettings`, and a picture is made
///   only by `PlannerFrameGate.frame` (`PlannerPictureSource`).
/// - The goal is a `HumanGoal`, taken once from the person.
/// - The allowed set is `AllowedDecisions.forDuck` for this duck and this planner. A caller can
///   add `.drive` (by naming ready sources) and `.plan`, and nothing else.
/// - The gate is bound here, by the runner, before the first ask.
/// - The duck is reached only through a `LatchedPeer` on the stop path: after a Stop nothing moves
///   it until a person starts something again.
/// - Every step a model chose carries its `PlannerStepLabel`.
///
/// EVERY ENDING GOES THROUGH THE STOP PATH: done, a planner's stop, a cut, a limit, a refusal, a
/// failed planner. The person re-arms by starting again.
public struct BrainRunner: Sendable {

    // MARK: options and hooks

    public struct Options: Sendable {
        public var limits: DuckEnvelopeGate.Limits
        /// What `robot.skills` listed, for the real duck's allowlist.
        public var robotSkills: [String]?
        /// Sources a `.drive` may name. Empty means `.drive` is not allowed.
        public var driveSources: [PlannerLeg.DriveSource]
        /// Whether `.plan` is allowed.
        public var allowPlans: Bool
        /// Decisions of this run a planner sees, newest last.
        public var historyLength: Int

        public init(limits: DuckEnvelopeGate.Limits = .placeholderV1, robotSkills: [String]? = nil,
                    driveSources: [PlannerLeg.DriveSource] = [], allowPlans: Bool = false,
                    historyLength: Int = 8) {
            self.limits = limits
            self.robotSkills = robotSkills
            self.driveSources = driveSources
            self.allowPlans = allowPlans
            self.historyLength = historyLength
        }
    }

    /// What the app supplies: what the duck reports, the person's answers, and the clock.
    public struct Hooks: Sendable {
        /// What the duck reports now. The gate checks every row against it.
        public var reading: @Sendable () async -> PlannerLeg.Reading
        /// The Go/Cancel card. True for Go.
        public var confirm: @Sendable (ConfirmCard) async -> Bool
        /// The planner's question for the person. Nil when they closed it without answering.
        public var ask: @Sendable (String) async -> String?
        public var picture: PlannerPictureSource
        /// Read-only notes for the planner (5.3). They never set the goal or the allowed set.
        public var context: @Sendable () async -> [PlannerContextNote]
        /// The head camera's frames for a drive leg's source, oldest first.
        public var driveFrames: @Sendable () async -> [String]
        /// Each step as it is recorded, for the screen.
        public var step: @Sendable (BrainStep) async -> Void
        public var now: @Sendable () -> Date
        public var sleep: @Sendable (TimeInterval) async throws -> Void

        public init(reading: @escaping @Sendable () async -> PlannerLeg.Reading,
                    confirm: @escaping @Sendable (ConfirmCard) async -> Bool,
                    ask: @escaping @Sendable (String) async -> String?,
                    picture: PlannerPictureSource = .none,
                    context: @escaping @Sendable () async -> [PlannerContextNote] = { [] },
                    driveFrames: @escaping @Sendable () async -> [String] = { [] },
                    step: @escaping @Sendable (BrainStep) async -> Void = { _ in },
                    now: @escaping @Sendable () -> Date = Date.init,
                    sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
                        try await Task.sleep(nanoseconds: UInt64($0 * 1e9))
                    }) {
            self.reading = reading
            self.confirm = confirm
            self.ask = ask
            self.picture = picture
            self.context = context
            self.driveFrames = driveFrames
            self.step = step
            self.now = now
            self.sleep = sleep
        }
    }

    /// The Go/Cancel card for one decision.
    public struct ConfirmCard: Equatable, Sendable {
        /// The decision as the planner gave it.
        public let decided: Decided
        /// What will run on Go, after the arbiter's clamp.
        public let willRun: DuckDecision
        public let reasons: [DuckEnvelopeGate.ConfirmReason]
        /// "Chosen by an AI model, not a person", or nil for a fixed rule.
        public let label: PlannerStepLabel?
    }

    // MARK: endings

    /// Which per-run limit ended the run (3.3).
    public enum Limit: String, Equatable, Sendable, CaseIterable {
        case wallClock = "wall clock"
        case venueCap = "time cap for this duck"
        case decisions
        case hostedCalls = "hosted calls"
        case repeats = "the same decision again"
    }

    public enum Ending: Equatable, Sendable {
        /// The planner said the goal is met.
        case done(String)
        /// The planner asked for a stop.
        case plannerStopped(String)
        /// Stop, a stick touch or anything else on the stop path, or the latch.
        case stopped
        /// The gate cut the run.
        case gateCut(DuckEnvelopeGate.Rule)
        case limit(Limit)
        /// The person tapped Cancel on a Go card.
        case declined
        /// The person closed the planner's question without answering.
        case unanswered
        /// The planner gave no decision: no key, no credit, too slow, unreadable.
        case plannerFailed(String)
        /// Refused before anything moved, or the robot said no.
        case refused(String)
        /// A drive or plan leg ended another way after something may have moved.
        case legStopped(String)

        public var says: String {
            switch self {
            case .done: return BrainRunWords.done
            case .plannerStopped: return BrainRunWords.plannerStopped
            case .stopped: return BrainRunWords.stopped
            case .gateCut(let rule): return BrainRunWords.gateCut(rule)
            case .limit(let l): return BrainRunWords.limit(l)
            case .declined: return BrainRunWords.declined
            case .unanswered: return BrainRunWords.unanswered
            case .plannerFailed(let why), .refused(let why), .legStopped(let why): return why
            }
        }
    }

    // MARK: building one

    public let planner: AgreedPlanner
    /// The arbiter's run this runner carries out.
    public let arbiterRun: ControlArbiter.Run
    public let goal: HumanGoal
    public let stopPath: StopPath
    public let options: Options
    public let hooks: Hooks
    /// The duck as this runner reaches it: through the stop latch.
    public let peer: LatchedPeer

    /// Nil when the arbiter's run is not one a brain drives (a one-tap walk or an outside order).
    public init?(planner: AgreedPlanner, run: ControlArbiter.Run, goal: HumanGoal, peer: any DuckPeer,
                 stopPath: StopPath, options: Options = Options(), hooks: Hooks) {
        guard Self.mode(for: run.kind) != nil else { return nil }
        self.planner = planner
        self.arbiterRun = run
        self.goal = goal
        self.stopPath = stopPath
        self.options = options
        self.hooks = hooks
        self.peer = LatchedPeer(peer, latch: stopPath)
    }

    static func mode(for kind: ControlArbiter.RunKind) -> BrainMode? {
        switch kind {
        case .tell: return .tell
        case .goal: return .auto
        case .walk, .order: return nil
        }
    }

    public var mode: BrainMode { Self.mode(for: arbiterRun.kind) ?? .tell }
    public var venue: BrainVenue { BrainVenue(arbiterRun.duck) }
    /// Whether the planner runs anywhere but this phone. Its calls count as hosted calls.
    public var remote: Bool { planner.info.runsOn != .thisPhone }

    /// The closed set for this run: the duck's own set for this planner, plus `.drive` for the
    /// ready sources and `.plan` when asked for. Nothing else can be added.
    public var allowed: AllowedDecisions {
        var set = AllowedDecisions.forDuck(arbiterRun.duck, runsOn: planner.info.runsOn, robotSkills: options.robotSkills)
        if !options.driveSources.isEmpty { set = set.allowing(drive: options.driveSources.map(\.id)) }
        if options.allowPlans { set = set.allowingPlans() }
        return set
    }

    // MARK: running

    /// Run until an ending. Cancelling the caller cancels the run, and so does any Stop.
    public func run() async -> BrainRunSummary {
        let box = TokenBox()
        let work = Task { await self.body(box) }
        let token = stopPath.register(.goal, task: work)
        box.set(token)
        let summary = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        stopPath.finished(token)
        return summary
    }

    final class TokenBox: @unchecked Sendable {
        private let lock = NSLock()
        private var token: StopPath.Token?
        func set(_ t: StopPath.Token) { lock.lock(); token = t; lock.unlock() }
        var value: StopPath.Token? { lock.lock(); defer { lock.unlock() }; return token }
    }

    /// The run's mutable record.
    private final class Record: @unchecked Sendable {
        var steps: [BrainStep] = []
        var plannerCalls = 0
        var hostedCalls = 0
        var executed: [DuckDecision] = []
        var history: [Decided] = []
    }

    private func body(_ box: TokenBox) async -> BrainRunSummary {
        let start = hooks.now()
        let record = Record()
        var gateValue = DuckEnvelopeGate(limits: options.limits)
        gateValue.bind(.init(providerId: planner.info.id, modelVersion: planner.info.modelVersion, venue: venue,
                             mode: mode, remote: remote, allowed: allowed))
        let gate = GateHolder(gateValue)
        let limits = options.limits

        func finish(_ ending: Ending) async -> BrainRunSummary {
            // Leave first, so the stop below does not cancel a stranger, then the stop path.
            if let t = box.value { stopPath.finished(t) }
            stopPath.stop()
            let g = await gate.gate
            return BrainRunSummary(planner: planner.info, venue: venue, mode: mode, goal: goal.text,
                                   steps: record.steps, gateStats: g.stats, gateEvents: g.events,
                                   ending: ending, skillStillRunning: stopPath.skillRunning,
                                   plannerCalls: record.plannerCalls, hostedCalls: record.hostedCalls,
                                   seconds: max(0, hooks.now().timeIntervalSince(start)),
                                   limits: limits)
        }
        func elapsed() -> Double { hooks.now().timeIntervalSince(start) }
        func secondsLeft() -> Double {
            var left = min(limits.runWallClockS, limits.runCap(venue)) - elapsed()
            if let endsBy = arbiterRun.endsBy { left = min(left, endsBy.timeIntervalSince(hooks.now())) }
            return max(0, left)
        }
        func stopped() -> Bool { Task.isCancelled || !stopPath.admits }
        func note(_ step: BrainStep) async {
            record.steps.append(step)
            await hooks.step(step)
        }

        // THE AGREEMENT, BEFORE ANY MODEL IS ASKED ANYTHING.
        if PlannerDisclosure.isModel(planner.info) {
            do { try planner.settings.requireAgreement() } catch let r as PlannerSafetyRefusal {
                return await finish(.refused(r.says))
            } catch {
                return await finish(.refused(PlannerSafetyRefusal.noAgreement.says))
            }
        }

        var utterance: String? = nil
        var prepared = venue == .practice
        var lastSkill: String? = nil

        while true {
            if stopped() { return await finish(.stopped) }
            // THE PER-RUN LIMITS, BEFORE THE PLANNER IS ASKED (3.3).
            if elapsed() >= limits.runWallClockS { return await finish(.limit(.wallClock)) }
            if secondsLeft() <= 0 { return await finish(.limit(.venueCap)) }
            if record.plannerCalls >= limits.maxDecisions { return await finish(.limit(.decisions)) }
            if remote && record.hostedCalls >= limits.maxHostedCalls { return await finish(.limit(.hostedCalls)) }

            // ASK. The goal is the person's; the picture only through the frame gate.
            let reading = await hooks.reading()
            let shot = await hooks.picture.make(planner.info, planner.settings)
            let frame = shot.jpeg
            let frameTime: ContinuousClock.Instant? = frame == nil ? nil : ContinuousClock.now
            let frameDate: Date? = frame == nil ? nil : hooks.now()
            let ask = PlannerAsk(goal: goal.text, utterance: utterance, frame: frame, frameTimestamp: frameTime,
                                 state: snapshot(reading, lastSkill: lastSkill), allowed: allowed,
                                 history: Array(record.history.suffix(max(0, options.historyLength))),
                                 context: await hooks.context())
            record.plannerCalls += 1
            if remote { record.hostedCalls += 1 }
            let decided: Decided
            switch await Self.race(planner.info.decisionDeadline, { try await planner.decide(ask) }) {
            case .cancelled: return await finish(.stopped)
            case .timedOut: return await finish(.plannerFailed(PlannerError.timedOut.says))
            case .failed(let why): return await finish(stopped() ? .stopped : .plannerFailed(why))
            case .value(let d): decided = d
            }
            // A STOP DURING THE THINKING ENDS THE RUN; THE ANSWER IS NOT RUN. Nor does an answer
            // that came back after the run's time was up.
            if stopped() { return await finish(.stopped) }
            if elapsed() >= limits.runWallClockS { return await finish(.limit(.wallClock)) }
            if secondsLeft() <= 0 { return await finish(.limit(.venueCap)) }
            record.history.append(decided)
            let label = Self.label(for: decided, planner: planner.info)
            let t = elapsed()

            // THE ARBITER CLAMPS FIRST. The decision's own durations and counts are never trusted.
            let (clamped, cut) = ControlArbiter.clamp(decided.decision, secondsLeft: secondsLeft())
            let checked = Decided(decision: clamped, why: decided.why, confidence: decided.confidence,
                                  provider: decided.provider, latency: decided.latency)

            // The same decision, again and again, ends the run (3.3: three repeats).
            if !clamped.kind.onlyStops, record.executed.count >= limits.maxIdenticalInARow,
               record.executed.suffix(limits.maxIdenticalInARow).allSatisfy({ $0 == clamped }) {
                await note(BrainStep(index: record.steps.count, t: t, decided: decided, ran: nil, arbiterCut: cut,
                                     verdict: .cut, rule: .run, confirmations: [], confirmed: nil, label: label,
                                     outcome: .refused(BrainRunWords.limit(.repeats))))
                return await finish(.limit(.repeats))
            }

            // THE GATE.
            var check: DuckEnvelopeGate.DecisionCheck
            do { check = try await gate.check(checked, at: t, phoneUnlocked: reading.phoneUnlocked) } catch {
                return await finish(.refused(PlannerLeg.Words.gateNotBound))
            }
            func step(_ outcome: BrainStep.Outcome, ran: DuckDecision?, reasons: [DuckEnvelopeGate.ConfirmReason] = [],
                      confirmed: Bool? = nil) -> BrainStep {
                BrainStep(index: record.steps.count, t: t, decided: decided, ran: ran, arbiterCut: cut,
                          verdict: check.verdict, rule: check.rule, confirmations: reasons, confirmed: confirmed,
                          label: label, outcome: outcome)
            }
            if check.stopPath && !clamped.kind.onlyStops {
                await note(step(.refused(GateWords.name(check.rule ?? .run)), ran: nil))
                return await finish(.gateCut(check.rule ?? .run))
            }
            if check.verdict == .held && check.rule != .confirm {
                // Held by the allowlist, the skill cap, a locked phone or an open ask: nothing moves,
                // the planner is asked again, and the call counts toward the run's limits.
                await note(step(.held, ran: nil))
                continue
            }

            // A GO FROM THE PERSON, when the gate or the arbiter's clamp asks for one. The reasons
            // only ever grow: the gate's own (where confidence can only add), plus a clamp the
            // arbiter made of more than the gate's share.
            var reasons = check.verdict == .held ? check.confirmations : []
            if cut > limits.clampShareForGo, !clamped.kind.onlyStops, clamped.kind != .ask,
               !reasons.contains(.bigClamp) {
                reasons.append(.bigClamp)
            }
            var confirmed: Bool? = nil
            if !reasons.isEmpty {
                let card = ConfirmCard(decided: decided, willRun: clamped, reasons: reasons, label: label)
                switch await Self.race(nil, { await hooks.confirm(card) }) {
                case .value(true): confirmed = true
                case .value(false):
                    await note(step(.declined, ran: nil, reasons: reasons, confirmed: false))
                    return await finish(.declined)
                default: return await finish(.stopped)
                }
                if stopped() { return await finish(.stopped) }
                if check.verdict == .held {
                    do { check = try await gate.confirm(checked, at: elapsed(), phoneUnlocked: reading.phoneUnlocked) } catch {
                        return await finish(.refused(PlannerLeg.Words.gateNotBound))
                    }
                    if check.stopPath && !clamped.kind.onlyStops {
                        await note(step(.refused(GateWords.name(check.rule ?? .run)), ran: nil, reasons: reasons, confirmed: true))
                        return await finish(.gateCut(check.rule ?? .run))
                    }
                    if check.verdict == .held {
                        await note(step(.held, ran: nil, reasons: reasons, confirmed: true))
                        continue
                    }
                }
            }

            // WHAT RUNS: the gate's decision, clamped by the arbiter again to the time left now.
            let runs = ControlArbiter.clamp(check.decision, secondsLeft: secondsLeft()).decision
            if !runs.kind.onlyStops { record.executed.append(runs) }

            switch runs {
            case .stop(let reason):
                await note(step(.ended, ran: runs, reasons: reasons, confirmed: confirmed))
                return await finish(.plannerStopped(reason))

            case .done(let reason):
                await note(step(.ended, ran: runs, reasons: reasons, confirmed: confirmed))
                return await finish(.done(reason))

            case .ask(let question):
                let answer: String?
                switch await Self.race(nil, { await hooks.ask(question) }) {
                case .value(let a): answer = a
                default: return await finish(.stopped)
                }
                await gate.answered()
                if stopped() { return await finish(.stopped) }
                guard let answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    await note(step(.declined, ran: runs, reasons: reasons, confirmed: confirmed))
                    return await finish(.unanswered)
                }
                await note(step(.answered, ran: runs, reasons: reasons, confirmed: confirmed))
                utterance = answer

            case .sound(let name):
                // "quack" is Pollen's chirp, as in a Tell order.
                guard let tag = name == "quack" ? DuckOrder.defaultSound : DuckSound(rawValue: name) else {
                    await note(step(.refused(BrainRunWords.noSuchSound(name)), ran: nil, reasons: reasons, confirmed: confirmed))
                    continue
                }
                do {
                    let answer = RobotIntentAnswer.read(try await peer.call(.sound(tag)))
                    // A SOUND IS NOT WORTH ENDING A RUN FOR, as in a plan.
                    await note(step(answer.accepted ? .ran : .refused(answer.reason ?? BrainRunWords.noSuchSound(name)),
                                    ran: runs, reasons: reasons, confirmed: confirmed))
                } catch {
                    return await finish(stopped() ? .stopped : .refused(DuckOrderRunner.sentence(for: error)))
                }

            case .skill(let name):
                switch await skill(name) {
                case .ran:
                    lastSkill = name
                    await note(step(.skillStarted, ran: runs, reasons: reasons, confirmed: confirmed))
                case .stopped: return await finish(.stopped)
                case .refused(let why):
                    await note(step(.refused(why), ran: nil, reasons: reasons, confirmed: confirmed))
                    return await finish(.refused(why))
                }

            case .walk, .turn:
                if !prepared {
                    switch await prepare() {
                    case .ran: prepared = true
                    case .stopped: return await finish(.stopped)
                    case .refused(let why): return await finish(.refused(why))
                    }
                }
                let obsAge: (@Sendable () -> Double?) = { [now = hooks.now] in
                    frameDate.map { now().timeIntervalSince($0) }
                }
                switch await walk(runs, gate: gate, runStart: start, secondsLeft: secondsLeft(), observationAge: obsAge) {
                case .walked(let basis):
                    await note(step(.walked(basis), ran: runs, reasons: reasons, confirmed: confirmed))
                case .stopped: return await finish(.stopped)
                case .cut(let rule):
                    await note(step(.refused(GateWords.name(rule)), ran: runs, reasons: reasons, confirmed: confirmed))
                    return await finish(.gateCut(rule))
                case .refused(let why): return await finish(.refused(why))
                }

            case .drive:
                if !prepared {
                    switch await prepare() {
                    case .ran: prepared = true
                    case .stopped: return await finish(.stopped)
                    case .refused(let why): return await finish(.refused(why))
                    }
                }
                let ending = await PlannerLeg.drive(
                    runs, humanGoal: goal.text, allowed: allowed, secondsLeft: secondsLeft(),
                    sources: options.driveSources, gate: gate, runStart: start, on: peer,
                    frames: hooks.driveFrames, reading: hooks.reading, latch: stopPath,
                    sleep: hooks.sleep, now: hooks.now)
                switch ending {
                case .done: await note(step(.ran, ran: runs, reasons: reasons, confirmed: confirmed))
                case .refused(let why):
                    await note(step(.refused(why), ran: nil, reasons: reasons, confirmed: confirmed))
                case .gateCut(let rule):
                    await note(step(.refused(GateWords.name(rule)), ran: runs, reasons: reasons, confirmed: confirmed))
                    return await finish(.gateCut(rule))
                case .stopped(let why):
                    await note(step(.refused(why), ran: runs, reasons: reasons, confirmed: confirmed))
                    return await finish(stopped() ? .stopped : .legStopped(why))
                }

            case .plan:
                if !prepared {
                    switch await prepare() {
                    case .ran: prepared = true
                    case .stopped: return await finish(.stopped)
                    case .refused(let why): return await finish(.refused(why))
                    }
                }
                let ending = await PlannerLeg.plan(
                    runs, allowed: allowed, secondsLeft: secondsLeft(), request: goal.text, on: peer,
                    interval: 1 / DreamPilot.rowsPerSecond, sleep: hooks.sleep, now: hooks.now)
                switch ending {
                case .done: await note(step(.ran, ran: runs, reasons: reasons, confirmed: confirmed))
                case .refused(let why):
                    await note(step(.refused(why), ran: nil, reasons: reasons, confirmed: confirmed))
                case .gateCut(let rule): return await finish(.gateCut(rule))
                case .stopped(let why):
                    await note(step(.refused(why), ran: runs, reasons: reasons, confirmed: confirmed))
                    return await finish(stopped() ? .stopped : .legStopped(why))
                }
            }
        }
    }

    // MARK: the label

    /// The AI label for a step. Read from the planner the run was built with, so a model that
    /// claims to be a fixed rule in its answer still carries the label.
    static func label(for decided: Decided, planner: PlannerInfo) -> PlannerStepLabel? {
        if decided.provider.id == planner.id { return PlannerDisclosure.stepLabel(for: decided) }
        return PlannerDisclosure.stepLabel(for: planner)
    }

    // MARK: what a planner is told about the duck

    func snapshot(_ r: PlannerLeg.Reading, lastSkill: String?) -> DuckStateSnapshot {
        let margin = r.pose.flatMap { p -> Double? in
            guard p.x.isFinite, p.y.isFinite else { return nil }
            return min(options.limits.matHalfM - abs(p.x), options.limits.matHalfM - abs(p.y))
        }
        return DuckStateSnapshot(x: r.pose?.x, y: r.pose?.y, yaw: r.pose?.yaw, odomAgeMs: r.odomAgeMs,
                                 standing: nil, lastSkill: lastSkill, keepInMarginM: margin)
    }

    // MARK: executors

    enum Done: Equatable { case ran, stopped, refused(String) }

    /// A real duck stands and drives before the first motion, with the same steps a Tell walk
    /// sends (`DuckOrder.stand`: init and enable, or the sit toggle for a seated duck).
    private func prepare() async -> Done {
        let ready = await DuckOrder.Readiness.ask(peer)
        switch await DuckOrderRunner.run(.stand, ready: ready, on: peer, stopPath: stopPath, sleep: hooks.sleep) {
        case .finished, .handedOff: return .ran
        case .stopped: return .stopped
        case .refused(let why): return .refused(why)
        }
    }

    /// `.skill`: `robot.do` with the existing prerequisites (`DuckOrder.skill`: enable, standing, a
    /// zero twist first), then a zero twist while the skill holds the duck. A Stop zeroes the walk
    /// but a started skill finishes; `StopPath.skillRunning` says so, and the summary carries it.
    private func skill(_ name: String) async -> Done {
        let ready: DuckOrder.Readiness = venue == .practice ? .practiceDuck : await DuckOrder.Readiness.ask(peer)
        switch await DuckOrderRunner.run(.skill(name), ready: ready, on: peer, stopPath: stopPath, sleep: hooks.sleep) {
        case .finished: break
        case .stopped: return .stopped
        case .refused(let why): return .refused(why)
        case .handedOff: return .refused(BrainRunWords.noSuchSkill(name))
        }
        let holds = (RobotPlan.skillSeconds[name] ?? 1) + RobotPlan.settleSeconds
        let tick = 1 / DreamPilot.rowsPerSecond
        do {
            for _ in 0..<max(1, Int((holds / tick).rounded())) {
                if Task.isCancelled || !stopPath.admits { return .stopped }
                try await peer.notify(.move(.still))
                try await hooks.sleep(tick)
            }
        } catch {
            return .stopped
        }
        stopPath.skillEnded()
        return .ran
    }

    enum Walked: Equatable { case walked(BrainStep.DistanceBasis), stopped, cut(DuckEnvelopeGate.Rule), refused(String) }

    /// One walk or turn as a twist profile at the stick limits, every row through the gate.
    struct Profile: Equatable {
        let twist: GateTwist
        let seconds: Double
        /// Metres for a walk, radians for a turn.
        let target: Double
        let turning: Bool
    }

    static func profile(_ d: DuckDecision, limits: DuckEnvelopeGate.Limits, secondsLeft: Double) -> Profile? {
        let longest = min(DuckDecision.maxSeconds, max(0, secondsLeft))
        switch d {
        case .walk(let f, let s):
            let vx = f >= 0 ? limits.maxForward : limits.maxBackward
            let tf = vx > 0 ? abs(f) / vx : 0
            let ts = limits.maxSideways > 0 ? abs(s) / limits.maxSideways : 0
            let need = max(tf, ts)
            guard need > 0, need.isFinite else { return nil }
            return Profile(twist: GateTwist(vx: f / need, vy: s / need, vyaw: 0), seconds: min(need, longest),
                           target: (f * f + s * s).squareRoot(), turning: false)
        case .turn(let degrees):
            let rad = degrees * .pi / 180
            let need = limits.maxTurn > 0 ? abs(rad) / limits.maxTurn : 0
            guard need > 0, need.isFinite else { return nil }
            return Profile(twist: GateTwist(vx: 0, vy: 0, vyaw: rad / need), seconds: min(need, longest),
                           target: abs(rad), turning: true)
        default:
            return nil
        }
    }

    /// Distance from odometry when it is fresh at the start and the duck gets there; from time
    /// otherwise. The step says which.
    private func walk(_ d: DuckDecision, gate: GateHolder, runStart: Date, secondsLeft: Double,
                      observationAge: @escaping @Sendable () -> Double?) async -> Walked {
        let limits = options.limits
        guard let p = Self.profile(d, limits: limits, secondsLeft: secondsLeft) else { return .walked(.time) }
        let tick = 1 / DreamPilot.rowsPerSecond
        let rows = Int((p.seconds / tick).rounded(.up))
        func fresh(_ r: PlannerLeg.Reading) -> DuckEnvelopeGate.Pose? {
            guard let age = r.odomAgeMs, age.isFinite, age <= limits.maxStateAgeMs, let pose = r.pose,
                  pose.x.isFinite, pose.y.isFinite, pose.yaw.isFinite else { return nil }
            return pose
        }
        let origin = fresh(await hooks.reading())
        var reached = false
        do {
            for _ in 0..<rows {
                if Task.isCancelled || !stopPath.admits { return .stopped }
                let r = await hooks.reading()
                if let o = origin, let here = fresh(r) {
                    let progress: Double
                    if p.turning {
                        progress = abs(atan2(sin(here.yaw - o.yaw), cos(here.yaw - o.yaw)))
                    } else {
                        progress = ((here.x - o.x) * (here.x - o.x) + (here.y - o.y) * (here.y - o.y)).squareRoot()
                    }
                    if progress >= p.target { reached = true; break }
                }
                let row = DuckEnvelopeGate.Row(
                    t: hooks.now().timeIntervalSince(runStart), twist: p.twist, odomAgeMs: r.odomAgeMs,
                    observationAgeS: observationAge(), pose: r.pose, tiltDeg: r.tiltDeg,
                    phoneUnlocked: r.phoneUnlocked, phase: p.turning ? "turn" : "walk")
                let result: DuckEnvelopeGate.Result
                do { result = try await gate.act(row) } catch { return .refused(PlannerLeg.Words.gateNotBound) }
                if result.stopPath { return .cut(result.rule ?? .run) }
                if Task.isCancelled || !stopPath.admits { return .stopped }
                try await peer.notify(.move(result.sent.drive))
                try await hooks.sleep(tick)
            }
            try await peer.notify(.move(.still))
        } catch {
            return Task.isCancelled || !stopPath.admits ? .stopped : .refused(DuckOrderRunner.sentence(for: error))
        }
        return .walked(origin != nil && reached ? .odometry : .time)
    }

    // MARK: waiting on something that may never answer

    enum Raced<T: Sendable>: Sendable {
        case value(T), failed(String), cancelled, timedOut
    }

    /// Wait for `body`, but never past a cancel (a Stop) or the deadline. A model, a card or a
    /// question that never answers is let go at once; its task is cancelled and not awaited.
    static func race<T: Sendable>(_ deadline: Duration?,
                                  _ body: @escaping @Sendable () async throws -> T) async -> Raced<T> {
        let once = FirstAnswer<Raced<T>>()
        let work = Task {
            do { once.give(.value(try await body())) } catch is CancellationError {
                once.give(.cancelled)
            } catch let e as PlannerError {
                once.give(.failed(e.says))
            } catch let r as PlannerSafetyRefusal {
                once.give(.failed(r.says))
            } catch {
                once.give(.failed(KeyScrub.scrub(String(String(describing: error).prefix(200)))))
            }
        }
        let timer: Task<Void, Never>? = deadline.map { d in
            Task {
                try? await Task.sleep(for: d)
                if !Task.isCancelled { once.give(.timedOut) }
            }
        }
        let answer = await withTaskCancellationHandler { await once.value } onCancel: { once.give(.cancelled) }
        work.cancel()
        timer?.cancel()
        return answer
    }
}

// MARK: - one step, and the run's summary

/// One decision in a run: who chose it and why, what ran, what the gate said, and the label.
public struct BrainStep: Equatable, Sendable {
    public enum DistanceBasis: String, Equatable, Sendable { case odometry, time }

    public enum Outcome: Equatable, Sendable {
        /// It ran (a sound, a drive leg, a plan).
        case ran
        /// A walk or turn ran; the distance was judged by odometry or by time.
        case walked(DistanceBasis)
        /// The robot accepted a skill. It finishes even after a Stop.
        case skillStarted
        /// The gate held it; nothing moved.
        case held
        /// Refused, by the robot, the gate or the leg. Nothing more moved.
        case refused(String)
        /// The person tapped Cancel, or closed the question.
        case declined
        /// The person answered the planner's question.
        case answered
        /// A stop or done: the run ends here.
        case ended
    }

    public let index: Int
    /// Seconds since the run started.
    public let t: Double
    /// The decision as the planner gave it: provider, model version, reason, confidence, latency.
    public let decided: Decided
    /// What ran, after the arbiter's clamp and the gate. Nil when nothing ran.
    public let ran: DuckDecision?
    /// How much of the asked amount the arbiter cut, 0 to 1.
    public let arbiterCut: Double
    public let verdict: DuckEnvelopeGate.Verdict
    public let rule: DuckEnvelopeGate.Rule?
    /// Why a Go was asked. Empty when none was.
    public let confirmations: [DuckEnvelopeGate.ConfirmReason]
    /// Nil when no Go was asked.
    public let confirmed: Bool?
    /// "Chosen by an AI model, not a person", with the provider and model. Nil for a fixed rule.
    public let label: PlannerStepLabel?
    public let outcome: Outcome

    /// Where the decision came from, for the summary: provider id and model version.
    public var provenance: String { "\(decided.provider.id) \(decided.provider.modelVersion)" }
}

/// What a run did, as data (build 91 draws it later): the steps with their provenance and labels,
/// the gate's counts, and how the run ended.
public struct BrainRunSummary: Equatable, Sendable {
    public let planner: PlannerInfo
    public let venue: BrainVenue
    public let mode: BrainMode
    public let goal: String
    public let steps: [BrainStep]
    public let gateStats: GateStats
    public let gateEvents: [GateEvent]
    public let ending: BrainRunner.Ending
    /// A skill the robot started is still running: "Stopping after this move."
    public let skillStillRunning: Bool
    public let plannerCalls: Int
    public let hostedCalls: Int
    public let seconds: Double
    public let limits: DuckEnvelopeGate.Limits

    /// "Gate stepped in 3 times (speed 2, rate 1)".
    public var gateChip: String { gateStats.chip }

    /// Decisions that ran.
    public var decisionsRun: Int { steps.filter { $0.ran != nil }.count }

    /// The summary's lines: the gate's, then how it ended, then a running skill.
    public var lines: [String] {
        var out = gateStats.summary(venue: venue, limits: limits)
        out.append(ending.says)
        if skillStillRunning { out.append(StopPath.Words.stoppingAfterThisMove) }
        return out
    }
}

// MARK: - words

/// The runner's sentences. The gate is "the limits", never "safety".
public enum BrainRunWords {
    public static let done = "The planner says the goal is met. The duck was told to stop."
    public static let plannerStopped = "The planner asked for a stop. The duck was told to stop."
    public static let stopped = "Stopped."
    public static func gateCut(_ rule: DuckEnvelopeGate.Rule) -> String {
        "The duck reached one of its limits (\(GateWords.name(rule))), so the run stopped."
    }
    public static func limit(_ l: BrainRunner.Limit) -> String {
        switch l {
        case .wallClock: return "The run reached its 3 minute limit and stopped."
        case .venueCap: return "The run reached this duck's time limit and stopped."
        case .decisions: return "The run reached its limit of steps and stopped."
        case .hostedCalls: return "The run reached its limit of calls to the hosted planner and stopped."
        case .repeats: return "The planner chose the same step too many times in a row, so the run stopped."
        }
    }
    public static let declined = "You cancelled the step. The duck was told to stop."
    public static let unanswered = "The question was closed without an answer, so the run stopped."
    public static func noSuchSound(_ name: String) -> String { "The duck has no sound called \(name)." }
    public static func noSuchSkill(_ name: String) -> String { "The duck could not run \(name) here." }

    public static var all: [String] {
        [done, plannerStopped, stopped, declined, unanswered, noSuchSound("x"), noSuchSkill("x")]
            + DuckEnvelopeGate.Rule.allCases.map(gateCut)
            + BrainRunner.Limit.allCases.map(limit)
    }
}
