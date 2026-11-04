import Foundation

/// Decides who is driving when a person's hands, a Tell chain and an Auto goal all want the duck.
///
/// THE TAKEOVER RULES OF docs/plans/native-first-redesign.md ("Auto", "Rules across all modes"),
/// as a pure state machine: it is fed events with the time they happened and answers with the
/// effects the app must carry out, in order. It holds no clock, no peer and no task, so every
/// rule below is a Linux test.
///
/// - ANY STICK TOUCH, PAD INPUT OR MOVE PRESS ENDS A TELL RUN OR AN AUTO GOAL through StopPath,
///   snaps the switch to Drive and says "You took over." The input that took over is the
///   person's own, so it passes and the latch is re-opened for it (a person's action is the one
///   thing `StopPath.rearm()` is for).
/// - HAND-BACK IS STOP ONLY. Stop, a heard "stop", the Live Activity's Stop, a cap, a lost
///   connection and leaving the foreground answer `.stopPath` and nothing that moves: no stand,
///   no re-arm, no input passed.
/// - CAPS: 30 s on the real duck, 60 s on the practice duck, for Auto goals. Studio may lengthen
///   them; nothing may switch them off.
/// - A STOPPED GOAL NEVER RE-ARMS ITSELF. No event but a person's `.start` begins a run, so a
///   reconnect, a return to the foreground or a tick after a stop starts nothing.
/// - LEAVING THE FOREGROUND ENDS EVERY RUN, except one an intent started that holds a Live
///   Activity. That one keeps going while the app process runs and still ends the moment the
///   connection drops. A start that arrives while the app is already off screen (Siri, a
///   Control) is REFUSED unless it holds a Live Activity: the `.background` that would have
///   ended it has already passed, so nothing else would.
public struct ControlArbiter: Equatable, Sendable {

    /// The top switch.
    public enum Mode: String, Equatable, Sendable, CaseIterable {
        case drive, tell, auto
    }

    /// What is running on the duck on someone's behalf other than the person's thumbs.
    public enum RunKind: String, Equatable, Sendable {
        /// A Tell command, chain, sequence or plan.
        case tell
        /// An Auto goal: the phone driver, Dream-1.
        case goal
    }

    /// Who started a run.
    public enum Owner: Equatable, Sendable {
        /// The app on screen.
        case app
        /// An App Intent whose run holds a Live Activity, so it may outlive the foreground.
        case intentWithLiveActivity
        /// An App Intent without one, which ends with the foreground like the app's own runs.
        case intent
    }

    public struct Run: Equatable, Sendable {
        public let kind: RunKind
        public let duck: DuckIdentity.Kind
        public let owner: Owner
        public let startedAt: Date
        /// When it is stopped for running too long, or nil for a run without a cap.
        public let endsBy: Date?
    }

    /// How long an Auto goal may run before it is stopped.
    public struct Caps: Equatable, Sendable {
        public static let realDuckDefault = 30.0
        public static let practiceDuckDefault = 60.0

        public let realDuck: Double
        public let practiceDuck: Double

        /// A cap that is not a positive finite number is the default: a cap cannot be turned off.
        public init(realDuck: Double = realDuckDefault, practiceDuck: Double = practiceDuckDefault) {
            self.realDuck = realDuck.isFinite && realDuck > 0 ? realDuck : Self.realDuckDefault
            self.practiceDuck = practiceDuck.isFinite && practiceDuck > 0 ? practiceDuck : Self.practiceDuckDefault
        }

        public static let standard = Caps()

        public func seconds(on duck: DuckIdentity.Kind) -> Double {
            duck == .real ? realDuck : practiceDuck
        }
    }

    public enum Event: Equatable, Sendable {
        /// A person started something. The only event that begins a run.
        case start(RunKind, duck: DuckIdentity.Kind, owner: Owner)
        /// The run ended on its own.
        case finished
        case stickTouch
        case padInput
        case movePress
        /// Any Stop: the disc, the pill, a heard "stop", Siri, the Live Activity, a Control.
        case stop
        case connectionLost
        case background
        case foreground
        /// Time passed; checks the cap.
        case tick
        case selectMode(Mode)
    }

    public enum Effect: Equatable, Sendable {
        /// Call `StopPath.stop()`.
        case stopPath
        /// Call `StopPath.rearm()`: only ever for a person's own action.
        case rearm
        /// Move the top switch.
        case setMode(Mode)
        /// The one line under the controls.
        case caption(String)
        /// End the run's Live Activity now.
        case endLiveActivity
    }

    public struct Decision: Equatable, Sendable {
        public let effects: [Effect]
        /// Whether the event's own input (a stick sample, a pad button, a move) goes on to drive.
        public let passInput: Bool

        static let nothing = Decision(effects: [], passInput: false)
    }

    /// Why the last run ended.
    public enum Ending: Equatable, Sendable {
        case finished, tookOver, stopped, capped, connectionLost, leftForeground
    }

    public enum Words {
        public static let tookOver = "You took over."
        public static func capped(_ seconds: Double) -> String {
            String(format: "Stopped at the %.0f s limit for this duck. Start it again to keep going.",
                   seconds)
        }
        public static let connectionLost = "Stopped. The connection to the duck dropped."
        public static let leftForeground = "Stopped when the app left the screen."
        public static let notOnScreen = "Nothing started, because the app is not on screen. Open it to start this."

        public static let all: [String] = [tookOver, capped(30), capped(60), connectionLost, leftForeground,
                                           notOnScreen]
    }

    public private(set) var mode: Mode
    public private(set) var running: Run?
    public private(set) var lastEnding: Ending?
    public private(set) var inForeground = true
    public let caps: Caps

    public init(mode: Mode = .drive, caps: Caps = .standard) {
        self.mode = mode
        self.caps = caps
    }

    /// Feed one event that happened at `now`, and get what to do about it.
    public mutating func handle(_ event: Event, at now: Date) -> Decision {
        switch event {
        case .start(let kind, let duck, let owner):
            // Off screen, only a run with a Live Activity may begin: anything else would run
            // with nothing left to end it. Refused before anything else, so the latch stays
            // shut and whatever is running keeps its own rules.
            if !inForeground, owner != .intentWithLiveActivity {
                return Decision(effects: [.caption(Words.notOnScreen)], passInput: false)
            }
            // A person's own action: the one place a run begins, and so the one place the latch
            // reopens. Whatever ran before is stopped first; two runs never share the duck.
            var effects: [Effect] = []
            if running != nil { effects.append(contentsOf: end(.stopped)) }
            let endsBy = kind == .goal ? now.addingTimeInterval(caps.seconds(on: duck)) : nil
            running = Run(kind: kind, duck: duck, owner: owner, startedAt: now, endsBy: endsBy)
            lastEnding = nil
            if kind == .goal, mode != .auto { mode = .auto; effects.append(.setMode(.auto)) }
            return Decision(effects: effects + [.rearm], passInput: true)

        case .finished:
            guard running != nil else { return .nothing }
            let la = running?.owner == .intentWithLiveActivity
            running = nil
            lastEnding = .finished
            return Decision(effects: la ? [.endLiveActivity] : [], passInput: false)

        case .stickTouch, .padInput, .movePress:
            if running != nil {
                var effects = end(.tookOver)
                effects.append(.rearm)
                if mode != .drive { mode = .drive; effects.append(.setMode(.drive)) }
                effects.append(.caption(Words.tookOver))
                return Decision(effects: effects, passInput: true)
            }
            if mode == .auto, event == .stickTouch {
                // "Touching the stick in Auto drops to Drive."
                mode = .drive
                return Decision(effects: [.setMode(.drive)], passInput: true)
            }
            return Decision(effects: [], passInput: true)

        case .stop:
            // Stop is honoured with or without a run: it is idempotent, and a person who pressed
            // it wants the wire to hear it.
            if running != nil { return Decision(effects: end(.stopped), passInput: false) }
            return Decision(effects: [.stopPath], passInput: false)

        case .connectionLost:
            guard running != nil else { return .nothing }
            return Decision(effects: end(.connectionLost) + [.caption(Words.connectionLost)],
                            passInput: false)

        case .background:
            inForeground = false
            guard let run = running, run.owner != .intentWithLiveActivity else { return .nothing }
            return Decision(effects: end(.leftForeground) + [.caption(Words.leftForeground)],
                            passInput: false)

        case .foreground:
            // Coming back starts nothing. A goal that was stopped stays stopped.
            inForeground = true
            return .nothing

        case .tick:
            guard let run = running, let endsBy = run.endsBy, now >= endsBy else { return .nothing }
            let cap = caps.seconds(on: run.duck)
            return Decision(effects: end(.capped) + [.caption(Words.capped(cap))], passInput: false)

        case .selectMode(let next):
            guard next != mode else { return .nothing }
            // Leaving a mode with something running in it stops it; the switch never moves a duck.
            var effects: [Effect] = running != nil ? end(.stopped) : []
            mode = next
            effects.append(.setMode(next))
            return Decision(effects: effects, passInput: false)
        }
    }

    /// End the run through StopPath. Never a motion, never a re-arm.
    private mutating func end(_ why: Ending) -> [Effect] {
        let la = running?.owner == .intentWithLiveActivity
        running = nil
        lastEnding = why
        return la ? [.stopPath, .endLiveActivity] : [.stopPath]
    }
}
