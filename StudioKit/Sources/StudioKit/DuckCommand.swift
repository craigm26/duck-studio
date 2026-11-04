import Foundation
import DuckKit

/// One thing a person asked the duck to do, from any surface.
///
/// App Intents, buttons, the pad, Speech and on-device model tools all produce one of these, and
/// nothing else talks to the transport (docs/plans/native-first-redesign.md, "Voice and system
/// surfaces"). Each case maps, purely, to the ordered `DuckCall`s it needs with the robot's real
/// prerequisites in front, and to whether it needs the phone unlocked.
///
/// THE NAME SHADOWS `DuckKit.DuckCommand` INSIDE THIS PACKAGE ON PURPOSE. The spec names this
/// layer `DuckCommand`; DuckKit's type of the same name is an observation's twist and head, and
/// the three places here that build one now say `DuckKit.DuckCommand`. A file that imports both
/// modules must qualify whichever it means.
///
/// THE ROBOT'S RULES, AS FOUND ON robotd 0.15.1 IN duck-sim (2026-10-03) AND IN ITS SOURCE:
/// - `robot.enable` needs `{"on": true}`; a bare one is refused. `DuckCall.enable` sends it.
/// - `robot.enable {on: true}` IS "start driving": robotd answers "enabled, driving". There is
///   no separate start call on the wire; the pad's Start is the same method with `toggle`.
/// - `robot.do` is refused unless the policy is driving, and refused for about a second while
///   the robot ramps to its home pose after an enable. The first `robot.do` after an enable is
///   therefore marked `retriesWhileHoming`.
/// - Sit and stand are ONE skill, `sit_toggle`. A duck on its feet stands with `robot.init`; a
///   seated duck is held by the toggle's latch, which `robot.init` argues with rather than
///   beats. So stand and sit need to know whether the duck is sitting, which robotd publishes
///   as `sitting` on `robot.policies` (proto v31). With no answer, Sit refuses rather than guess,
///   and Stand never sends the toggle.
/// - `robot.stop` zeroes the twist and does not cancel a skill already started.
public enum DuckCommand: Equatable, Sendable {
    case stop
    case stand
    case sit
    /// Walk for a while. The seconds are clamped to `walkSecondsRange` when planned.
    case walk(Direction, seconds: Double)
    /// One of the robot's one-shot skills, by the name `robot.skills` gave it.
    case skill(String)
    case sound(DuckSound)
    case look(LookTarget)
    /// A goal from Auto (the phone driver, Dream-1). Handed to the runner that owns it.
    case goal(String)
    /// One of the person's own saved sequences or plans, by id. Handed to its runner.
    case runMine(String)

    public enum Direction: String, Equatable, Sendable, CaseIterable {
        case forward, back, left, right, turnLeft, turnRight

        /// The twist this direction walks at: two thirds of `DuckDrive`'s limit on its one axis,
        /// in Pollen's signs (x forward, y left, positive vyaw turning left).
        public var twist: DuckDrive.Twist {
            let share = DuckCommand.walkShare
            switch self {
            case .forward: return DuckDrive.Twist(vx: DuckDrive.maxForward * share, vy: 0, vyaw: 0)
            case .back: return DuckDrive.Twist(vx: -DuckDrive.maxBackward * share, vy: 0, vyaw: 0)
            case .left: return DuckDrive.Twist(vx: 0, vy: DuckDrive.maxSideways * share, vyaw: 0)
            case .right: return DuckDrive.Twist(vx: 0, vy: -DuckDrive.maxSideways * share, vyaw: 0)
            case .turnLeft: return DuckDrive.Twist(vx: 0, vy: 0, vyaw: DuckDrive.maxTurn * share)
            case .turnRight: return DuckDrive.Twist(vx: 0, vy: 0, vyaw: -DuckDrive.maxTurn * share)
            }
        }

        public var said: String {
            switch self {
            case .forward: return "forward"
            case .back: return "back"
            case .left: return "left"
            case .right: return "right"
            case .turnLeft: return "turn left"
            case .turnRight: return "turn right"
            }
        }
    }

    public enum LookTarget: String, Equatable, Sendable, CaseIterable {
        /// v1 of "look at me": straight ahead. A face from the duck camera is v2.
        case me
        case ahead
    }

    // MARK: - numbers

    /// Walks never run longer than this from one command, whatever a surface asked for.
    public static let walkSecondsRange: ClosedRange<Double> = 0...5
    /// What a walk with no stated length runs for.
    public static let defaultWalkSeconds = 1.0
    /// A spoken or tapped walk goes at this share of the stick's top speed.
    public static let walkShare = 2.0 / 3.0
    /// `robot.move` is streamed at this interval during a walk.
    public static let walkTick = 0.1
    /// How long, and how often, the first `robot.do` after an enable is retried while robotd
    /// is still ramping to its home pose.
    public static let homingRetry = (every: 0.25, upTo: 2.0)

    /// A walk's length, as it will run: NaN and infinity become the default, the rest is
    /// clamped to `walkSecondsRange`.
    public static func walkSeconds(_ asked: Double) -> Double {
        guard asked.isFinite else { return defaultWalkSeconds }
        return min(max(asked, walkSecondsRange.lowerBound), walkSecondsRange.upperBound)
    }

    /// A walk of the default length.
    public static func walk(_ direction: Direction) -> DuckCommand {
        .walk(direction, seconds: defaultWalkSeconds)
    }

    // MARK: - who may run it

    /// Whether this starts motion. Read by the app to set `authenticationPolicy`.
    public var startsMotion: Bool {
        switch self {
        case .stop, .sit, .sound: return false
        case .stand, .walk, .skill, .look, .goal, .runMine: return true
        }
    }

    /// Whether the phone must be unlocked to run this from the Lock Screen, Siri or a Control.
    /// Motion yes; Stop, Sit and sounds no. Sit is a motion that ends in rest, and is allowed
    /// locked as the spec says.
    public var needsAuthenticationWhenLocked: Bool { startsMotion }

    // MARK: - the plan

    /// One step of a command, in order.
    public struct Step: Equatable, Sendable {
        public enum Action: Equatable, Sendable {
            /// An answered call; a refusal ends the command with the robot's reason.
            case call(DuckCall, retriesWhileHoming: Bool)
            /// `robot.move` at `walkTick` for this long, then a zero twist.
            case walk(DuckDrive.Twist, seconds: Double)
            /// The whole stop sequence, `StopPath.stop()`.
            case stopPath
            /// Not ours to run: the goal or saved run is handed to the runner that owns it.
            case handOff(HandOff)
        }

        public let action: Action
        /// The line a person sees while this step runs, or nil for a step nobody needs to read
        /// about (the prerequisites).
        public let caption: String?

        public init(_ action: Action, caption: String? = nil) {
            self.action = action
            self.caption = caption
        }

        static func call(_ c: DuckCall, caption: String? = nil, retriesWhileHoming: Bool = false) -> Step {
            Step(.call(c, retriesWhileHoming: retriesWhileHoming), caption: caption)
        }
    }

    public enum HandOff: Equatable, Sendable {
        case goal(String)
        case mine(String)
    }

    /// What the duck is known to be doing, as robotd says it. Nil is "it did not say".
    public struct Readiness: Equatable, Sendable {
        /// `robot.policies` `sitting` (proto v31).
        public var sitting: Bool?
        /// The skills `robot.skills` listed; nil when they have not been read.
        public var skills: [String]?

        public init(sitting: Bool? = nil, skills: [String]? = nil) {
            self.sitting = sitting
            self.skills = skills
        }

        public static let unknown = Readiness()
    }

    /// Why a command was not planned. The sentence is the one a person sees.
    public enum Refusal: Error, Equatable, Sendable {
        case sittingUnknown
        case notASkillName(String)
        case notOnThisDuck(String, has: [String])
        case emptyName

        public var says: String {
            switch self {
            case .sittingUnknown:
                return "This duck has not said whether it is sitting, so Sit waits rather than "
                     + "guess. A wrong guess would stand it up instead."
            case .notASkillName(let name):
                return "\"\(name)\" is not a move a duck can be asked for by name."
            case .notOnThisDuck(let name, let has):
                return has.isEmpty
                    ? "This duck has no moves to run, so \(name) was not sent."
                    : "This duck has no \(name). It has: \(has.joined(separator: ", "))."
            case .emptyName:
                return "That command named nothing to run."
            }
        }
    }

    /// The sentences a command puts on screen.
    public enum Words {
        public static let standUp = "Stand up"
        public static let sitDown = "Sit down"
        public static let alreadySitting = "Already sitting."
        public static func doing(_ skill: String) -> String { "Doing \(skill.replacingOccurrences(of: "_", with: " "))." }
        public static func walking(_ d: Direction, _ seconds: Double) -> String {
            String(format: "Walking %@ for %.1f s.", d.said, seconds)
        }
        public static let looking = "Looking up and ahead."
        public static func playing(_ s: DuckSound) -> String { "Playing \(s.rawValue)." }
    }

    /// "Quack": Pollen's `chirp` is the duck's ordinary quack.
    public static let defaultSound = DuckSound.chirp

    /// The robot's name for sit and stand.
    public static let sitToggle = "sit_toggle"

    /// The steps this command needs, in order, given what the duck has said about itself.
    public func plan(_ ready: Readiness = .unknown) throws -> [Step] {
        switch self {
        case .stop:
            return [Step(.stopPath)]

        case .stand:
            switch ready.sitting {
            case true?:
                // A seated duck is held by the toggle's latch: enable, then the toggle.
                return [.call(.enable),
                        .call(.doSkill(Self.sitToggle), caption: Words.standUp, retriesWhileHoming: true)]
            case false?, nil:
                // On its feet, or it did not say: robot.init stands it, and the toggle is never
                // sent blind, because on a standing duck it sits.
                return [.call(.initPose, caption: Words.standUp), .call(.enable)]
            }

        case .sit:
            switch ready.sitting {
            case true?: return []
            case nil: throw Refusal.sittingUnknown
            case false?:
                return Self.prerequisites
                    + [.call(.doSkill(Self.sitToggle), caption: Words.sitDown, retriesWhileHoming: true)]
            }

        case .walk(let direction, let asked):
            let seconds = Self.walkSeconds(asked)
            return Self.ready(ready) + [Step(.walk(direction.twist, seconds: seconds),
                                             caption: Words.walking(direction, seconds))]

        case .skill(let name):
            guard !name.isEmpty else { throw Refusal.emptyName }
            guard DuckCall.isSkillName(name) else { throw Refusal.notASkillName(name) }
            if let has = ready.skills, !has.contains(name) { throw Refusal.notOnThisDuck(name, has: has) }
            if name == Self.sitToggle { return try (ready.sitting == true ? DuckCommand.stand : .sit).plan(ready) }
            // A skill starts from a zero twist, as RobotPlanRunner and padd do.
            return Self.ready(ready)
                + [.call(.stop),
                   .call(.doSkill(name), caption: Words.doing(name), retriesWhileHoming: true)]

        case .sound(let tag):
            return [.call(.sound(tag), caption: Words.playing(tag))]

        case .look:
            return [.call(.look(.level), caption: Words.looking)]

        case .goal(let name):
            guard !name.isEmpty else { throw Refusal.emptyName }
            return [Step(.handOff(.goal(name)))]

        case .runMine(let id):
            guard !id.isEmpty else { throw Refusal.emptyName }
            return [Step(.handOff(.mine(id)))]
        }
    }

    /// `robot.init`, then `robot.enable {on: true}`, which is what starts the policy driving.
    public static let prerequisites: [Step] = [.call(.initPose), .call(.enable)]

    /// The prerequisites for a motion, with a visible "Stand up" step for a seated duck: a
    /// sitting duck accepts only stand, and `robot.init` would argue with its latch.
    static func ready(_ r: Readiness) -> [Step] {
        guard r.sitting == true else { return prerequisites }
        return [.call(.enable),
                .call(.doSkill(sitToggle), caption: Words.standUp, retriesWhileHoming: true)]
    }

    /// Just the calls, in order, for a reader that wants the wire and not the captions. A walk
    /// appears as its first `robot.move`, then a zero one.
    public func calls(_ ready: Readiness = .unknown) throws -> [DuckCall] {
        try plan(ready).flatMap { step -> [DuckCall] in
            switch step.action {
            case .call(let c, _): return [c]
            case .walk(let t, _): return [.move(t), .move(.still)]
            case .stopPath: return [.stop]
            case .handOff: return []
            }
        }
    }
}

// MARK: - running one

/// Runs a `DuckCommand`'s steps on a peer, asking `StopPath` before every step.
///
/// IT REGISTERS ITSELF WITH THE STOP PATH, so a stop cancels it, and it checks the latch before
/// each call and at every walk tick, so a step queued behind a stop never reaches the duck.
///
/// IT NEVER RE-ARMS THE LATCH. After a stop, a command returns `.stopped` until the app calls
/// `StopPath.rearm()` for a person's own action; a model or a bridge never does.
public enum DuckCommandRunner {

    public typealias Sleep = @Sendable (Double) async throws -> Void

    public enum Ended: Equatable, Sendable {
        case finished
        /// Stopped by the stop path, or cancelled. The caption is the stop's own.
        case stopped
        /// The robot said no, in its words.
        case refused(String)
        /// Not ours: the app runs the goal or the saved run.
        case handedOff(DuckCommand.HandOff)
    }

    public static func run(_ command: DuckCommand,
                           ready: DuckCommand.Readiness = .unknown,
                           on peer: any DuckPeer,
                           stopPath: StopPath,
                           said: @escaping @Sendable (String) async -> Void = { _ in },
                           sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) })
        async -> Ended {
        if case .stop = command {
            await said(stopPath.stop().caption)
            return .stopped
        }
        let steps: [DuckCommand.Step]
        do { steps = try command.plan(ready) } catch let r as DuckCommand.Refusal {
            return .refused(r.says)
        } catch { return .refused("\(error)") }

        if steps.isEmpty {
            if case .sit = command { await said(DuckCommand.Words.alreadySitting) }
            return .finished
        }
        // THE STEPS RUN IN THEIR OWN TASK, registered with the stop path, so a stop cancels them
        // without waiting for this caller, and cancelling this caller cancels them too.
        let work = Task { await perform(steps, peer: peer, stopPath: stopPath, said: said, sleep: sleep) }
        let token = stopPath.register(.command, task: work)
        defer { stopPath.finished(token) }
        return await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
    }

    private static func perform(_ steps: [DuckCommand.Step], peer: any DuckPeer, stopPath: StopPath,
                              said: @escaping @Sendable (String) async -> Void,
                              sleep: @escaping Sleep) async -> Ended {
        do {
            for (i, step) in steps.enumerated() {
                guard stopPath.admits, !Task.isCancelled else { return .stopped }
                if let caption = step.caption { await said(caption) }
                switch step.action {
                case .stopPath:
                    stopPath.stop()
                    return .stopped
                case .handOff(let h):
                    return .handedOff(h)
                case .call(let call, let retries):
                    let deadline = retries ? DuckCommand.homingRetry.upTo : 0
                    var waited = 0.0
                    while true {
                        let answer = RobotIntentAnswer.read(try await peer.call(call))
                        if answer.accepted { break }
                        guard waited < deadline, stopPath.admits, !Task.isCancelled else {
                            if !stopPath.admits || Task.isCancelled { return .stopped }
                            return .refused(answer.reason ?? "The duck said no to \(call.method.rawValue).")
                        }
                        try await sleep(DuckCommand.homingRetry.every)
                        waited += DuckCommand.homingRetry.every
                    }
                    if case .doSkill(let name) = call {
                        let holds = (RobotPlan.skillSeconds[name] ?? 1) + RobotPlan.settleSeconds
                        stopPath.skillStarted(seconds: holds)
                        // ONE MOVE AT A TIME: a step after a skill waits for it, feeding a zero
                        // twist so the deadman has nothing to catch.
                        if i < steps.count - 1 {
                            for _ in 0..<Int((holds / DuckCommand.walkTick).rounded()) {
                                guard stopPath.admits, !Task.isCancelled else { return .stopped }
                                try await peer.notify(.move(.still))
                                try await sleep(DuckCommand.walkTick)
                            }
                            stopPath.skillEnded()
                        }
                    }
                case .walk(let twist, let seconds):
                    let n = Int((seconds / DuckCommand.walkTick).rounded())
                    for _ in 0..<n {
                        guard stopPath.admits, !Task.isCancelled else { return .stopped }
                        try await peer.notify(.move(twist))
                        try await sleep(DuckCommand.walkTick)
                    }
                    try await peer.notify(.move(.still))
                }
            }
        } catch {
            if !stopPath.admits || Task.isCancelled { return .stopped }
            _ = try? await peer.notify(.move(.still))
            return .refused((error as? DuckCall.Misuse)?.message ?? "\(error)")
        }
        return .finished
    }
}
