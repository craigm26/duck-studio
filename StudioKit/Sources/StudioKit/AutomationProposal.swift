import Foundation
import DuckKit

/// A rule as a language model states it, before anyone decides it is one.
///
/// FLAT AND PRIMITIVE ON PURPOSE. Everything here is a String or a Double,
/// because this is the shape a small on-device model can reliably fill — it
/// cannot be asked to construct a Swift enum with associated values. Turning
/// those loose primitives into an `Automation` is the interesting and dangerous
/// part, so it happens HERE, where `swift test` can check it on Linux, rather
/// than in a view where the only way to exercise it is to talk to a phone.
///
/// A PROPOSAL IS NOT A RULE. Nothing about being generated makes this
/// admissible; nothing about being typed makes it correct. `resolve` maps and
/// `AutomationValidator` judges, and both run whether a person or a model
/// produced the values.
public struct AutomationProposal: Equatable, Sendable {

    /// The vocabulary a model is given, verbatim. Listed as strings because
    /// that is what a model emits, and matched exactly rather than fuzzily —
    /// a rule that fires on "somethingClose" when the author wrote
    /// "somethingAhead" is a rule nobody wrote.
    public static let predicateNames = [
        "somethingAheadWithin", "wayAheadClearBeyond",
        "depthUnreliable", "fallen", "batteryBelow",
    ]

    public let name: String
    public let predicate: String
    /// Metres for the two distance predicates, a fraction for battery, ignored
    /// otherwise. One field rather than three because a model asked for three
    /// optional numbers fills all of them.
    public let value: Double
    public let intent: String

    public init(name: String, predicate: String, value: Double, intent: String) {
        self.name = name
        self.predicate = predicate
        self.value = value
        self.intent = intent
    }

    public enum Unresolvable: Error, Equatable {
        case unknownPredicate(String, closest: String?)

        public var message: String {
            switch self {
            case .unknownPredicate(let name, let closest):
                let hint = closest.map { " The nearest one is \($0)." } ?? ""
                return "\"\(name)\" is not something the robot can test for.\(hint)"
            }
        }
    }

    /// Turn the primitives into a rule, or say why they are not one.
    ///
    /// Resolution and validation are separate steps deliberately: this one
    /// answers "do these words name anything", the validator answers "is the
    /// rule they name admissible". Collapsing them would make an unknown
    /// predicate and an out-of-range distance the same kind of failure, and
    /// they need different things said about them.
    public func resolve(knownIntents: Set<String>,
                        origin: Automation.Origin = .model) throws -> Automation {
        let when: Automation.Predicate
        switch predicate {
        case "somethingAheadWithin": when = .somethingAheadWithin(metres: value)
        case "wayAheadClearBeyond":  when = .wayAheadClearBeyond(metres: value)
        case "depthUnreliable":      when = .depthUnreliable
        case "fallen":               when = .fallen
        case "batteryBelow":         when = .batteryBelow(fraction: value)
        default:
            throw Unresolvable.unknownPredicate(
                predicate,
                closest: AutomationValidator.closest(to: predicate,
                                                     in: Set(Self.predicateNames)))
        }
        let automation = Automation(name: name, when: when,
                                    then: .play(intent: intent), origin: origin)
        try AutomationValidator.validate(automation, knownIntents: knownIntents)
        return automation
    }

    /// The grounding a model needs to have any chance of proposing something
    /// admissible: the exact words it may use, and the exact motions that exist.
    ///
    /// Built from the live intent list rather than written out, so a model is
    /// never told about a clip that has since been removed — the commonest way
    /// a generated rule fails is naming a motion that sounds right.
    public static func grounding(knownIntents: Set<String>) -> String {
        """
        Predicates, use one of these exact words:
        \(predicateNames.map { "- \($0)" }.joined(separator: "\n"))

        somethingAheadWithin and wayAheadClearBeyond take a distance in metres, \
        between \(AutomationValidator.minimumRange) and \(AutomationValidator.maximumRange). \
        batteryBelow takes a fraction between 0 and 1. depthUnreliable and fallen take no value.

        Motions, use one of these exact names:
        \(knownIntents.sorted().map { "- \($0)" }.joined(separator: "\n"))

        Do not invent a predicate or a motion that is not listed.
        """
    }
}
