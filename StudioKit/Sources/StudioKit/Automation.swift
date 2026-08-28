import Foundation
import DuckKit

/// When something is true of what the robot senses, do one thing.
///
/// THE VOCABULARY IS DELIBERATELY SMALL, and it is bounded by what a phone can
/// actually observe and command today: predicates over the head's depth sensor
/// and the robot's own reported state, actions that name one recorded intent.
/// Everything in both lists exists — no predicate reads a sensor the robot does
/// not have, and no action names a motion nobody recorded.
///
/// NOTHING HERE RUNS YET, AND SAYING SO IS PART OF THE TYPE. An adversarial
/// review checked and `DuckToF` and `DuckState` are both INBOUND DECODERS —
/// they read what the robot reports and have no output channel at all. So an
/// `Automation` is a rule you can write, validate, read back and share; it is
/// not a rule that fires. Executing one needs `DuckRPC` and a robot that does
/// not exist yet. A UI presenting these must not imply otherwise.
///
/// A PROPOSED AUTOMATION IS NOT AN ADMITTED ONE. These values are cheap to make
/// and anything can make one — a person tapping a form, or a language model
/// turning a sentence into a struct. `AutomationValidator` is the single
/// choke-point that decides whether a proposal may run, and it re-checks
/// everything regardless of where the proposal came from. Structured
/// generation shapes what a model emits; it is not a guarantee about it.
public struct Automation: Equatable, Sendable, Identifiable {

    /// Something that can be true of the world, as the robot senses it.
    public enum Predicate: Equatable, Sendable {
        /// Something is closer than this, in metres, in the MIDDLE of the depth
        /// sensor's field of view. The middle matters: a duck on a floor sees
        /// that floor in its bottom rows permanently, so "anything close?"
        /// answers yes forever and is useless as a trigger.
        case somethingAheadWithin(metres: Double)
        /// Nothing is within this distance ahead — the way is clear.
        case wayAheadClearBeyond(metres: Double)
        /// The depth frame is too degraded to act on. Glass and bright sun both
        /// do this, and an automation that cannot tell "empty" from "could not
        /// see" will drive into what it failed to range.
        case depthUnreliable
        /// The robot reports it has fallen.
        case fallen
        /// Battery below a fraction of full.
        case batteryBelow(fraction: Double)

        public var described: String {
            switch self {
            case .somethingAheadWithin(let m):
                return String(format: "something is within %.2f m ahead", m)
            case .wayAheadClearBeyond(let m):
                return String(format: "nothing is within %.2f m ahead", m)
            case .depthUnreliable: return "the depth sensor cannot see reliably"
            case .fallen: return "the robot has fallen"
            case .batteryBelow(let f): return "battery is below \(Int(f * 100))%"
            }
        }
    }

    /// The one thing an automation does. Naming a recorded intent, and nothing
    /// else: no raw joint commands, no arbitrary velocities. An automation can
    /// only ask for a motion somebody already recorded and looked at.
    public enum Action: Equatable, Sendable {
        case play(intent: String)

        public var described: String {
            switch self { case .play(let intent): return "play \(intent)" }
        }
    }

    public let id: UUID
    public let name: String
    public let when: Predicate
    public let then: Action
    /// Where this came from. A proposal a model wrote and a rule a person typed
    /// are both admissible, and a reader deserves to know which is which.
    public let origin: Origin

    public enum Origin: String, Equatable, Sendable {
        case person, model
        public var described: String {
            self == .model ? "drafted by the on-device model" : "written by you"
        }
    }

    public init(id: UUID = UUID(), name: String, when: Predicate,
                then: Action, origin: Origin) {
        self.id = id; self.name = name; self.when = when
        self.then = then; self.origin = origin
    }

    /// One sentence, in the order it happens.
    public var sentence: String { "When \(when.described), \(then.described)." }
}

/// The choke-point every automation passes, whoever proposed it.
///
/// Its job is not to be clever. It is to make sure the two halves of a rule
/// refer to things that exist, and to refuse in a way that says what was wrong
/// — because the most likely author is a language model that named a plausible
/// intent nobody recorded.
public enum AutomationValidator {

    public enum Refusal: Error, Equatable {
        case unknownIntent(String, closest: String?)
        case unnamed
        case distanceOutOfRange(Double)
        case fractionOutOfRange(Double)

        public var message: String {
            switch self {
            case .unknownIntent(let name, let closest):
                let suggestion = closest.map { " Did you mean \($0)?" } ?? ""
                return "There is no recorded intent called \"\(name)\".\(suggestion)"
            case .unnamed:
                return "An automation needs a name, so you can find it again."
            case .distanceOutOfRange(let m):
                return String(format: "%.2f m is outside what the depth sensor can report. "
                              + "It ranges to about 4 m, and closer than 2 cm is inside the robot.", m)
            case .fractionOutOfRange(let f):
                return "\(f) is not a fraction between 0 and 1."
            }
        }
    }

    /// The sensor's usable range. Beyond it a rule can never fire, which is
    /// worse than an error because it looks like it is working.
    public static let minimumRange = 0.02
    public static let maximumRange = 4.0

    public static func validate(_ automation: Automation,
                                knownIntents: Set<String>) throws {
        guard !automation.name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw Refusal.unnamed
        }
        switch automation.when {
        case .somethingAheadWithin(let m), .wayAheadClearBeyond(let m):
            guard m >= minimumRange, m <= maximumRange else {
                throw Refusal.distanceOutOfRange(m)
            }
        case .batteryBelow(let f):
            guard f > 0, f <= 1 else { throw Refusal.fractionOutOfRange(f) }
        case .depthUnreliable, .fallen:
            break
        }
        switch automation.then {
        case .play(let intent):
            guard knownIntents.contains(intent) else {
                throw Refusal.unknownIntent(intent, closest: closest(to: intent, in: knownIntents))
            }
        }
    }

    /// The nearest known intent by simple edit distance, for the "did you mean"
    /// — a model that writes `sit_down` when the clip is `sit` should be told
    /// which, not just refused.
    static func closest(to name: String, in known: Set<String>) -> String? {
        known.map { ($0, distance(name.lowercased(), $0.lowercased())) }
            .filter { $0.1 <= max(3, name.count / 2) }
            .min { $0.1 < $1.1 }?.0
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        var row = Array(0...y.count)
        for i in 1...max(x.count, 1) where !x.isEmpty {
            var previous = row[0]
            row[0] = i
            for j in 1...max(y.count, 1) where !y.isEmpty {
                let temporary = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1,
                             previous + (x[i - 1] == y[j - 1] ? 0 : 1))
                previous = temporary
            }
        }
        return y.isEmpty ? x.count : row[y.count]
    }
}
