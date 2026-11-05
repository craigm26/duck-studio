import Foundation
import DuckKit

// MARK: - what each duck can be told

extension DuckOrder {

    /// Why this order cannot run on this kind of duck, as the sentence a person sees, or nil
    /// when it can.
    ///
    /// THE PRACTICE DUCK IS PHYSICS, NOT ROBOTD. It walks and turns; it has no sitting latch, no
    /// voice bank, no head to aim and no one-shot skills by robotd's names (`BenchPeer.refusal`).
    /// Asking it anyway used to reach the bench and come back as a Swift case name
    /// (`resetIsNotTheInitialPose`, `noVoice`), so the refusal is said here, before anything is
    /// sent, in a sentence that also says where the move does work.
    public func notOn(_ duck: DuckIdentity.Kind) -> String? {
        guard duck == .sim else { return nil }
        switch self {
        case .sit: return PracticeWords.cannotSit
        case .skill(let name) where name == DuckOrder.sitToggle: return PracticeWords.cannotSit
        case .skill: return PracticeWords.noSkills
        case .sound: return PracticeWords.noVoice
        case .look: return PracticeWords.noHead
        case .stop, .stand, .walk, .goal, .runMine: return nil
        }
    }

    /// The practice duck's refusals.
    public enum PracticeWords {
        public static let cannotSit = "The practice duck can't sit. Your own duck can."
        public static let noVoice = "The practice duck has no voice. Quack works on your own duck."
        public static let noSkills = "The practice duck has no moves of its own. Your own duck does."
        public static let noHead = "The practice duck can't aim its head. Your own duck can."

        public static let all = [cannotSit, noVoice, noSkills, noHead]
    }
}

extension DuckOrder.Readiness {

    /// The practice duck: on its feet and walking whenever it is upright, with nothing to
    /// initialise and no sitting latch.
    public static let practiceDuck = DuckOrder.Readiness(sitting: false, skills: [], driving: true,
                                                         homed: true)

    /// `robot.policies`, read: the sitting latch and the home ramp (proto v31) and the skills list.
    ///
    /// `driving` IS NEVER READ FROM HERE. robotd's `enabled` is the config's `[policy] enabled`
    /// (are policies loaded at all) and `mode` is `walk` or `roller` (which slot defaults apply);
    /// neither says whether `robot.enable` has the policy driving now. Reading them as "driving"
    /// made a limp duck look up and walking, so Stand sent nothing and a walk skipped init and
    /// enable. Left nil, a motion sends init and enable first, which is always safe.
    ///
    /// A FIELD THE ROBOT DID NOT SEND STAYS NIL. An older robotd has no `sitting`, and nil is
    /// what keeps Sit from guessing. Nil overall means the answer was a refusal or not an object.
    public static func read(policies reply: DuckReply) -> DuckOrder.Readiness? {
        guard reply.failure == nil, let data = reply.result,
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        var ready = DuckOrder.Readiness()
        ready.sitting = top["sitting"] as? Bool
        ready.homed = top["homed"] as? Bool
        if let skills = top["skills"] as? [String] { ready.skills = skills }
        return ready
    }

    /// Ask the duck how it stands, waiting at most `timeout` seconds. A link that does not carry
    /// `robot.policies`, a refusal, a thrown error or a slow answer is `.unknown`, which is the
    /// cautious plan (init and enable first; Sit refuses to guess). Never throws, never hangs.
    public static func ask(_ peer: any DuckPeer, timeout: Double = 1.0) async -> DuckOrder.Readiness {
        guard peer.reach.contains(.policies) else { return .unknown }
        let once = FirstAnswer<DuckOrder.Readiness>()
        let call = Task {
            let reply = try? await peer.call(.policies)
            once.give(reply.flatMap(read(policies:)) ?? .unknown)
        }
        let timer = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
            once.give(.unknown)
            call.cancel()
        }
        let answer = await once.value
        timer.cancel()
        return answer
    }
}

/// A value given once, by whichever of several racers gets there first.
final class FirstAnswer<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var answer: T?
    private var waiting: CheckedContinuation<T, Never>?

    func give(_ value: T) {
        lock.lock()
        guard answer == nil else { lock.unlock(); return }
        answer = value
        let k = waiting
        waiting = nil
        lock.unlock()
        k?.resume(returning: value)
    }

    var value: T {
        get async {
            await withCheckedContinuation { k in
                lock.lock()
                if let answer { lock.unlock(); k.resume(returning: answer); return }
                waiting = k
                lock.unlock()
            }
        }
    }
}

// MARK: - the decider: a few steps from a closed set

/// Apple Intelligence as a DECIDER, not a driver (docs/plans/brains-layer.md, 3.2).
///
/// The on-device model reads what a person said and answers with a short list of steps. Every
/// step names one action from a CLOSED set (stand, sit, walk, turn, skill, sound, look) and the
/// kit turns each into a `DuckOrder`. The model never picks a number the duck obeys unclamped,
/// never names a method, and never runs anything: `validate` refuses a plan with an unknown
/// action, an unknown name, a step this duck cannot do, too many steps or too much walking,
/// and the app runs what is left through `DuckOrderRunner` under the arbiter's cap and Stop.
///
/// IT PLANS FROM WORDS, NOT FROM THE PICTURE. "Go to the ball" becomes walking, not seeking; the
/// card says so.
public enum DuckDecider {

    /// At most this many steps in one plan (the plan doc's limit for model-built plans).
    public static let maxSteps = 6
    /// All the walking and turning in one plan, added up, may not pass this.
    public static let maxPlanWalkSeconds = 15.0
    /// How long the plan shows before it runs, with Cancel, so a model-built plan never moves the
    /// duck without a beat to read it.
    public static let previewSeconds = 1.5

    /// The closed set.
    public enum Action: String, CaseIterable, Sendable {
        case stand, sit, walk, turn, skill, sound, look
    }

    /// Every action word, for a constrained decoder.
    public static let actionWords: [String] = Action.allCases.map(\.rawValue)

    /// Directions a walk may take, and a turn.
    public static let walkDirections = ["forward", "back", "left", "right"]
    public static let turnDirections = ["left", "right"]
    /// Every direction word, for a constrained decoder that has one field for both.
    public static let directionWords = ["forward", "back", "left", "right", "none"]

    /// One step as a model wrote it. Strings, because that is what a constrained decoder emits;
    /// nothing here is trusted until `order(_:on:skills:)` reads it.
    public struct Step: Equatable, Sendable, Codable {
        public var action: String
        public var direction: String?
        public var seconds: Double?
        public var name: String?

        public init(action: String, direction: String? = nil, seconds: Double? = nil, name: String? = nil) {
            self.action = action
            self.direction = direction
            self.seconds = seconds
            self.name = name
        }
    }

    public enum Refusal: Error, Equatable, Sendable {
        case nothingPlanned
        case tooManySteps(Int)
        case unknownAction(String)
        case unknownDirection(String)
        case unknownName(String)
        case notOnThisDuck(String)
        case tooMuchWalking(Double)

        public var says: String {
            switch self {
            case .nothingPlanned:
                return "I couldn't turn that into steps. Try something like \"walk forward, then turn left\"."
            case .tooManySteps(let n):
                return "That came out as \(n) steps, and a plan here is at most \(DuckDecider.maxSteps). "
                     + "Try asking for less at once."
            case .unknownAction(let word):
                return "The plan asked for \"\(word)\", which is not something the duck can be told to do."
            case .unknownDirection(let word):
                return "The plan asked to go \"\(word)\", which is not a direction the duck walks."
            case .unknownName(let word):
                return "The plan named \"\(word)\", which is not one of this duck's moves or sounds."
            case .notOnThisDuck(let why):
                return why
            case .tooMuchWalking(let s):
                return String(format: "That plan walks for %.0f s, and a plan here walks at most %.0f s. "
                            + "Try a shorter one.", s, DuckDecider.maxPlanWalkSeconds)
            }
        }
    }

    /// The actions offered on this duck. The practice duck walks and turns, nothing else.
    public static func actions(on duck: DuckIdentity.Kind) -> [Action] {
        duck == .sim ? [.walk, .turn] : Action.allCases
    }

    /// The skill names a plan may use on this duck: the robot's list when it gave one, Pollen's
    /// stock set otherwise, never the sit toggle (sit and stand are their own actions).
    public static func skillNames(on duck: DuckIdentity.Kind, skills: [String]?) -> [String] {
        guard duck == .real else { return [] }
        let names = skills ?? Array(RobotPlan.skillSeconds.keys)
        return names.filter { $0 != DuckOrder.sitToggle && DuckCall.isSkillName($0) }.sorted()
    }

    /// The sound names a plan may use: Pollen's tags, plus "quack".
    public static func soundNames(on duck: DuckIdentity.Kind) -> [String] {
        guard duck == .real else { return [] }
        return ["quack"] + DuckSound.allCases.map(\.rawValue).sorted()
    }

    /// Every name a constrained decoder may write in the name field, for any duck: the stock
    /// skills, the sounds, and "none". `validate` narrows it to this duck.
    public static let nameWords: [String] = {
        let skills = RobotPlan.skillSeconds.keys.filter { $0 != DuckOrder.sitToggle }.sorted()
        return skills + ["quack"] + DuckSound.allCases.map(\.rawValue).sorted() + ["none"]
    }()

    /// One step, read. Throws the refusal a person sees.
    public static func order(_ step: Step, on duck: DuckIdentity.Kind, skills: [String]?) throws -> DuckOrder {
        let word = step.action.trimmingCharacters(in: .whitespaces).lowercased()
        guard let action = Action(rawValue: word) else { throw Refusal.unknownAction(step.action) }
        let direction = step.direction?.trimmingCharacters(in: .whitespaces).lowercased()
        let name = step.name?.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: " ", with: "_")
        let seconds = DuckOrder.walkSeconds(step.seconds.map { $0 > 0 ? $0 : DuckOrder.defaultWalkSeconds }
                                            ?? DuckOrder.defaultWalkSeconds)
        let order: DuckOrder
        switch action {
        case .stand: order = .stand
        case .sit: order = .sit
        case .look: order = .look(.ahead)
        case .walk:
            switch direction {
            case "forward"?: order = .walk(.forward, seconds: seconds)
            case "back"?, "backward"?: order = .walk(.back, seconds: seconds)
            case "left"?: order = .walk(.left, seconds: seconds)
            case "right"?: order = .walk(.right, seconds: seconds)
            default: throw Refusal.unknownDirection(step.direction ?? "")
            }
        case .turn:
            switch direction {
            case "left"?: order = .walk(.turnLeft, seconds: seconds)
            case "right"?: order = .walk(.turnRight, seconds: seconds)
            default: throw Refusal.unknownDirection(step.direction ?? "")
            }
        case .skill:
            guard let name, !name.isEmpty else { throw Refusal.unknownName(step.name ?? "") }
            if duck == .sim { throw Refusal.notOnThisDuck(DuckOrder.PracticeWords.noSkills) }
            guard skillNames(on: duck, skills: skills).contains(name) else { throw Refusal.unknownName(name) }
            order = .skill(name)
        case .sound:
            guard let name, !name.isEmpty else { throw Refusal.unknownName(step.name ?? "") }
            if duck == .sim { throw Refusal.notOnThisDuck(DuckOrder.PracticeWords.noVoice) }
            guard let sound = DuckOrderMatcher.soundWords[name] ?? DuckSound(rawValue: name) else {
                throw Refusal.unknownName(name)
            }
            order = .sound(sound)
        }
        if let why = order.notOn(duck) { throw Refusal.notOnThisDuck(why) }
        return order
    }

    /// A whole plan, read: every step must read, and the plan must fit the limits. One bad step
    /// refuses the plan, because running the half that read would be doing something else.
    public static func validate(_ steps: [Step], on duck: DuckIdentity.Kind,
                                skills: [String]? = nil) -> Result<[DuckOrder], Refusal> {
        guard !steps.isEmpty else { return .failure(.nothingPlanned) }
        guard steps.count <= maxSteps else { return .failure(.tooManySteps(steps.count)) }
        var orders: [DuckOrder] = []
        do {
            for step in steps { orders.append(try order(step, on: duck, skills: skills)) }
        } catch let r as Refusal {
            return .failure(r)
        } catch {
            return .failure(.nothingPlanned)
        }
        let walking = orders.reduce(0.0) { sum, o in
            if case .walk(_, let s) = o { return sum + s }
            return sum
        }
        guard walking <= maxPlanWalkSeconds else { return .failure(.tooMuchWalking(walking)) }
        return .success(orders)
    }

    /// The model's instructions: the closed set for THIS duck, in plain words.
    public static func instructions(on duck: DuckIdentity.Kind, skills: [String]?) -> String {
        let acts = actions(on: duck)
        var lines = [
            "You plan short action sequences for a small robot duck.",
            "Answer with 1 to \(maxSteps) steps, in order. Each step has one action.",
            "Use only these actions: " + acts.map(\.rawValue).joined(separator: ", ") + ".",
        ]
        if acts.contains(.walk) {
            lines.append("walk needs a direction: forward, back, left or right, and seconds from 1 to 5.")
        }
        if acts.contains(.turn) {
            lines.append("turn needs a direction: left or right, and seconds from 1 to 3. About 2 seconds is a quarter turn.")
        }
        let skillList = skillNames(on: duck, skills: skills)
        if acts.contains(.skill), !skillList.isEmpty {
            lines.append("skill needs a name, one of: " + skillList.joined(separator: ", ") + ".")
        }
        if acts.contains(.sound) {
            lines.append("sound needs a name, one of: " + soundNames(on: duck).joined(separator: ", ") + ".")
        }
        if acts.contains(.sit) {
            lines.append("sit and stand need nothing else. The duck must stand before it walks after sitting.")
        }
        lines.append("Use name none and direction none when a step does not need them.")
        lines.append("You cannot see the room. If the person asks for something you cannot do with these actions, "
                     + "do the nearest thing you can, or answer with no steps.")
        if duck == .sim {
            lines.append("This is the practice duck on the screen. It can only walk and turn.")
        }
        return lines.joined(separator: "\n")
    }

    /// A step as a short chip in the preview.
    public static func chip(for order: DuckOrder) -> (title: String, symbol: String) {
        switch order {
        case .stop: return ("Stop", "stop.fill")
        case .stand: return ("Stand up", "figure.stand")
        case .sit: return ("Sit down", "chair")
        case .walk(let d, let s):
            let symbol: String
            switch d {
            case .forward: symbol = "arrow.up"
            case .back: symbol = "arrow.down"
            case .left: symbol = "arrow.left"
            case .right: symbol = "arrow.right"
            case .turnLeft: symbol = "arrow.counterclockwise"
            case .turnRight: symbol = "arrow.clockwise"
            }
            let verb = (d == .turnLeft || d == .turnRight) ? d.said.capitalized : "Walk \(d.said)"
            return (String(format: "%@ %.0f s", verb, s), symbol)
        case .skill(let name): return (name.replacingOccurrences(of: "_", with: " ").capitalized, "figure.run")
        case .sound(let s): return (s == .chirp ? "Quack" : s.rawValue.capitalized, "speaker.wave.2")
        case .look: return ("Look up", "eyes")
        case .goal(let g): return (g, "sparkles")
        case .runMine: return ("My move", "list.bullet.rectangle")
        }
    }

    /// Whether Apple Intelligence can plan here, said plainly, with the next thing to try.
    public enum Availability: Equatable, Sendable {
        case ready
        case deviceNotEligible
        case notEnabled
        case modelNotReady
        case needsNewerSystem
        case unavailable

        public var isReady: Bool { self == .ready }

        public var says: String {
            switch self {
            case .ready: return Words.readyLine
            case .deviceNotEligible:
                return "This device doesn't have Apple Intelligence, so it can't plan from a sentence."
            case .notEnabled:
                return "Apple Intelligence is off. Turn it on in Settings to plan from a sentence."
            case .modelNotReady:
                return "Apple Intelligence is still getting ready on this device. Try again in a little while."
            case .needsNewerSystem:
                return "Planning from a sentence needs iOS 26 or macOS 26 with Apple Intelligence."
            case .unavailable:
                return "Apple Intelligence isn't available right now."
            }
        }

        /// What to try instead, when it is not ready.
        public var instead: String? {
            isReady ? nil : "Short commands still work in Tell, and Dream-1 is on the right."
        }
    }

    /// The Apple Intelligence card's words.
    public enum Words {
        public static let title = "Ask the duck"
        public static let provenance = "Apple Intelligence, on this device. Nothing you say leaves it."
        public static let readyLine = "Say or type a goal. It plans a few steps from your words, shows them, then runs them."
        /// What tapping a "Try saying" chip does.
        public static let exampleHint = "Shows the plan for a moment, then runs it."
        public static let placeholder = "Walk forward, turn left, then sit"
        public static let go = "Plan"
        public static let thinking = "Planning."
        public static let startingSoon = "Starting in a moment."
        public static let cancel = "Cancel"
        public static let cancelled = "Cancelled. Nothing was sent."
        public static let cantSee = "It plans from your words. It can't see the room yet."
        public static func step(_ i: Int, of n: Int) -> String { "Step \(i) of \(n)" }
        public static let done = "Done."
        public static let modelFailed = "Apple Intelligence couldn't answer that. Try saying it another way."
        /// The Siri line under the field. Must match a phrase in DuckShortcuts (the app's AppShortcutsProvider).
        public static let siriLine = "Or ask Siri: \"Sit the duck down in Microduck Studio\""

        /// The hint row under the field (build 93): a few sentences to tap, so a first try works.
        public static let trySaying = "Try saying"

        /// What to try on this duck. WITHOUT APPLE INTELLIGENCE every sentence is one the matcher
        /// reads exactly, so a tap works on any phone; with it, a two-step sentence shows what
        /// planning adds, and each step is still one the matcher reads on its own.
        public static func examples(on duck: DuckIdentity.Kind?, modelReady: Bool) -> [String] {
            switch (duck, modelReady) {
            case (.sim?, false): return ["walk forward", "turn left"]
            case (.sim?, true): return ["walk forward, then turn left", "turn right"]
            case (_, false): return ["stand up", "quack"]
            case (_, true): return ["stand up, then quack", "walk forward, then sit down"]
            }
        }

        /// The steps of an example, as the matcher reads them one at a time.
        public static func exampleSteps(_ example: String) -> [String] {
            example.components(separatedBy: ", then ").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        /// A tapped example as a plan, read with no model, or nil if any step does not run on this
        /// duck. A tap therefore works the same with Apple Intelligence on or off.
        public static func examplePlan(_ example: String, on duck: DuckIdentity.Kind,
                                       skills: [String]) -> [DuckOrder]? {
            var orders: [DuckOrder] = []
            for step in exampleSteps(example) {
                guard let order = DuckOrderMatcher.match(step, skills: skills), order.notOn(duck) == nil
                else { return nil }
                orders.append(order)
            }
            return orders.isEmpty ? nil : orders
        }

        public static var all: [String] {
            [title, provenance, readyLine, exampleHint, placeholder, go, thinking, startingSoon, cancel, cancelled, cantSee,
             step(1, of: 3), done, modelFailed, siriLine, trySaying]
                + [DuckIdentity.Kind.sim, .real].flatMap { d in
                    [false, true].flatMap { examples(on: d, modelReady: $0) } }
                + [Availability.deviceNotEligible, .notEnabled, .modelNotReady, .needsNewerSystem, .unavailable]
                    .flatMap { [$0.says, $0.instead ?? ""] }
        }
    }
}

// MARK: - a caption that goes away

/// One line under the controller's top row that expires.
///
/// BUILD 91 HELD ONE REFUSAL ON SCREEN IN EVERY MODE UNTIL STOP. A caption now lasts long
/// enough to read (about 4 s, longer for a long line, never past 8 s), and the controller also
/// clears it on a mode change, a stick drive and the next tap.
public struct CaptionLine: Equatable, Sendable {
    public let text: String
    public let shownAt: Date
    public let seconds: Double

    public static let shortest = 4.0
    public static let longest = 8.0

    public init(_ text: String, at now: Date) {
        self.text = text
        self.shownAt = now
        self.seconds = Self.seconds(for: text)
    }

    /// How long a line stays: four seconds, plus a little for a long line, at most eight.
    public static func seconds(for text: String) -> Double {
        min(max(2.0 + Double(text.count) * 0.05, shortest), longest)
    }

    public var hidesAt: Date { shownAt.addingTimeInterval(seconds) }

    public func isShowing(at now: Date) -> Bool { now < hidesAt }
}

// MARK: - the real duck's face buttons

extension DuckPadMap.Effect {
    /// What this binding asks of a REAL duck, or nil when it is a practice-duck control.
    ///
    /// The shipped A and X load the Ground pick and Roulade networks into a bench slot; a real
    /// duck holds those as one-shot skills, so on robotd the same button runs `robot.do` by
    /// robotd's name. Stop is Stop everywhere. Loading a file, a motion, a replay and Reset are
    /// the bench's, and stay dead on a real duck with the reason drawn.
    public var realDuckOrder: DuckOrder? {
        switch self {
        case .loadSlot(let slot):
            guard let name = RobotPlan.robotdName[slot] else { return nil }
            return .skill(name)
        case .stop: return .stop
        case .play, .drive, .run, .reset, .notYet: return nil
        }
    }

    public static let practiceOnly = "This button works on the practice duck. Your duck runs only its own moves."
}

// MARK: - Siri and Shortcuts

/// What the App Shortcuts answer. The phrases themselves are literals in the app's
/// AppShortcutsProvider, because Siri reads them at build time.
public enum ShortcutWords {
    public static let noDuck = "Open Microduck Studio and pick a duck first, then ask again."
    public static let nothingToStop = "Microduck Studio isn't connected to a duck right now, so there was nothing to stop from here."
    public static let didNotUnderstand = "I didn't understand that as a duck command. Open Ask the duck in Microduck Studio for longer plans."
    public static let all = [noDuck, nothingToStop, didNotUnderstand]
}

// MARK: - the mic

/// The mic on Tell and on Ask the duck: on-device speech only.
public enum MicWords {
    public static let speak = "Speak"
    public static let listening = "Listening. Tap the mic again when you're done."
    public static let notAllowed = "Microphone or speech access is off. Turn it on in Settings to talk to the duck."
    public static let notOnDevice = "This device can't recognise speech on its own, so the mic is off. Typing still works."
    public static let heardStop = "Heard \"stop\"."
    public static let heardNothing = "I didn't catch that. Try again."
    public static let all = [speak, listening, notAllowed, notOnDevice, heardStop, heardNothing]
}
