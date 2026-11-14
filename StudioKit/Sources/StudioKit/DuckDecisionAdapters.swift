import Foundation
import DuckKit

/// One-way adapters from today's planner outputs to `DuckDecision` (3.2, "Conversion goes one
/// way").
///
/// `DuckTalk`, `ModelIntentPlanner` and `DuckDecider` keep their outputs exactly as they are.
/// These read those outputs and say the same thing as decisions, so a run can log, gate and
/// compare every planner in one shape. Nothing converts back.
///
/// WHEN A STEP HAS NO V1 DECISION, IT IS SAID, NOT DROPPED IN SILENCE. A head direction, a sit
/// or a saved run has no case yet. `Converted.left` names each one so the caller can show it.
public enum DecisionAdapter {

    public struct Converted: Equatable, Sendable {
        public let decisions: [DuckDecision]
        /// Steps with no v1 decision, in the person's words.
        public let left: [String]
    }

    /// A walk or turn decision for this twist held for this long. A stop word becomes `.stop`.
    ///
    /// A "stop" or "wait" in the middle of a sentence also becomes `.stop`, which ends the run
    /// early. That is the cautious reading: it does less than was asked, never more.
    static func decision(go: String, twist: DuckDrive.Twist, seconds: Double, said: String) -> DuckDecision {
        if go == "stop" { return .stop(reason: said) }
        if go.hasPrefix("turn") {
            return .turn(degrees: twist.vyaw * seconds * 180 / .pi)
        }
        return .walk(forwardM: twist.vx * seconds, sideM: twist.vy * seconds)
    }

    /// DuckTalk's reading. Each move's twist comes from `SequenceProposal.twist(for:share:)`,
    /// the same door the sequence itself goes through.
    public static func from(_ reading: DuckTalk.Reading) -> Converted {
        var out: [DuckDecision] = []
        var left: [String] = []
        for move in reading.moves {
            let share = min(move.speed ?? 1, 1)
            guard let twist = try? SequenceProposal.twist(for: move.go, share: share) else {
                left.append(move.go)
                continue
            }
            out.append(decision(go: move.go, twist: twist, seconds: move.seconds, said: move.go))
        }
        return Converted(decisions: out, left: left)
    }

    /// A plan from `ModelIntentPlanner` or the router. Discarded nodes are skipped, refusals
    /// become one `.ask`, skills keep robotd's names, and sounds keep their tags.
    public static func from(_ plan: DuckIntentPlan) -> Converted {
        var out: [DuckDecision] = []
        var left: [String] = []
        for node in plan.nodes where !node.discarded {
            if node.isRefusal {
                out.append(.ask(question: Words.couldNot(node.clause)))
                continue
            }
            if let slot = DuckIntentPlan.skills[node.action], let name = RobotPlan.robotdName[slot] {
                out.append(.skill(name: name))
                continue
            }
            if node.action == "make_sound" {
                out.append(.sound(name: node.labels["sound"] ?? "chirp"))
                continue
            }
            guard let go = DuckIntentPlan.goes[node.action] else {
                left.append(node.clause)
                continue
            }
            let head = node.labels["head"] ?? "straight"
            if head != "straight" { left.append(DuckIntentPlan.Vocabulary.words(head)) }
            let share = node.action == "stop" ? 1
                : DuckIntentPlan.shares[node.labels["speed"] ?? "normal"] ?? 2.0 / 3.0
            guard let twist = try? SequenceProposal.twist(for: go, share: share) else {
                left.append(node.clause)
                continue
            }
            out.append(decision(go: go, twist: twist, seconds: node.seconds, said: node.clause))
        }
        return Converted(decisions: out, left: left)
    }

    /// One order from `DuckDecider` or the command matcher. Nil for orders with no v1 decision
    /// (stand, sit, look, a goal, a saved run).
    public static func from(_ order: DuckOrder) -> DuckDecision? {
        switch order {
        case .stop: return .stop(reason: "stop")
        case .walk(let direction, let seconds):
            let twist = direction.twist
            switch direction {
            case .turnLeft, .turnRight: return .turn(degrees: twist.vyaw * seconds * 180 / .pi)
            default: return .walk(forwardM: twist.vx * seconds, sideM: twist.vy * seconds)
            }
        case .skill(let name): return .skill(name: name)
        case .sound(let sound): return .sound(name: sound.rawValue)
        case .stand, .sit, .look, .goal, .runMine: return nil
        }
    }

    public enum Words {
        public static func couldNot(_ clause: String) -> String {
            "The duck can't do \"\(clause)\". What should it do instead?"
        }
    }
}
