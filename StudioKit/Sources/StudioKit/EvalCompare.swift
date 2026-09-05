import Foundation

/// Two logs, side by side, and the four cases where putting them side by side
/// would be the lie.
///
/// THERE IS NO COMBINED NUMBER ANYWHERE IN THIS TYPE. A compare screen's whole
/// temptation is one number saying which run won, and every way of computing
/// one requires a weighting nobody measured: a policy that travels twice as far
/// and falls over twice as often is not behind or ahead, it is a different
/// trade. So this produces ROWS. Each row is one scorer name with the two
/// values that were measured under it and, when the scorer is one this app
/// knows, which direction is better. The reader does the arithmetic that
/// matters to them, which is the only person who can.
///
/// THE REFUSALS ARE WHERE THE WORK IS. Two numbers are comparable only when
/// almost everything around them was the same, and the log carries enough to
/// check three of those things before drawing anything: the world, the task and
/// whether the two files are the same file. A screen that drew the rows first
/// and warned second would be a screen where the warning is the thing scrolled
/// past.
public struct EvalCompare: Equatable, Sendable {

    /// One side, kept as the log plus the name on the shelf so a row can say
    /// which file it came out of without holding the bytes twice.
    public struct Side: Equatable, Sendable {
        public let name: String
        public let log: EvalLog

        public init(name: String, log: EvalLog) {
            self.name = name
            self.log = log
        }
    }

    public let left: Side
    public let right: Side

    init(left: Side, right: Side) {
        self.left = left
        self.right = right
    }

    // MARK: - refusals

    public enum Refusal: Error, Equatable {
        case sameLog(String)
        case differentEmbodiment(String, String)
        case differentTask(String, String)
        case nothingInCommon

        public var message: String {
            switch self {
            case .sameLog(let name):
                return "That is \(name) on both sides. A log compared with itself agrees with "
                     + "itself, which is not a measurement of anything."
            case .differentEmbodiment(let left, let right):
                return "These two ran in different worlds: \(left) and \(right). The world's "
                     + "digest is part of what a run is called, so these numbers were never on "
                     + "the same scale and this screen will not put them on one."
            case .differentTask(let left, let right):
                return "These two ran different tasks: \(left) and \(right). The scenes decide "
                     + "what a scorer is measuring, so the same scorer name on two tasks is two "
                     + "different questions."
            case .nothingInCommon:
                return "These two logs share no scorer, so there is no row that could carry "
                     + "both of them."
            }
        }
    }

    /// The only way to build one.
    ///
    /// AN IMPORTED LOG IS ALLOWED HERE, and that is the point of import
    /// existing: comparing a run from this phone with one somebody else
    /// published is the whole reason to read their file. What is refused is a
    /// comparison across worlds, not a comparison across machines.
    public static func checked(_ left: EvalLogFile, _ right: EvalLogFile) throws -> EvalCompare {
        try checked(Side(name: left.name, log: left.log),
                    Side(name: right.name, log: right.log))
    }

    public static func checked(_ left: Side, _ right: Side) throws -> EvalCompare {
        guard left.name != right.name else { throw Refusal.sameLog(left.name) }
        guard left.log.eval.embodiment == right.log.eval.embodiment else {
            throw Refusal.differentEmbodiment(left.log.eval.embodiment,
                                              right.log.eval.embodiment)
        }
        guard left.log.eval.task == right.log.eval.task else {
            throw Refusal.differentTask(left.log.eval.task, right.log.eval.task)
        }
        let shared = Set(left.log.results.metrics.keys)
            .intersection(right.log.results.metrics.keys)
        guard !shared.isEmpty else { throw Refusal.nothingInCommon }
        return EvalCompare(left: left, right: right)
    }

    // MARK: - the rows

    public struct Row: Equatable, Sendable, Identifiable {
        /// The scorer name, which is the key both logs filed the number under.
        public let name: String
        /// What the number means, when this app knows the scorer. Nil for a
        /// name out of somebody else's task, which is drawn under its own name
        /// and nothing else.
        public let said: String?
        public let left: Double?
        public let right: Double?
        /// Nil for a scorer this app does not know, because a direction it
        /// guessed would be an opinion about somebody else's measurement.
        public let higherIsBetter: Bool?
        public let unit: String

        public var id: String { name }

        /// Right minus left, when both sides have a number.
        ///
        /// A DIFFERENCE IS NOT A COMBINED METRIC. It is the same quantity,
        /// measured twice in the same world on the same task, subtracted. It
        /// does not weigh one scorer against another and it does not produce a
        /// verdict, which is what the refusals above spend their whole effort
        /// making possible.
        public var difference: Double? {
            guard let left, let right, left.isFinite, right.isFinite else { return nil }
            return right - left
        }

        /// Which side this scorer prefers, or nil when the app cannot say:
        /// either the scorer is not one of ours, the two agree, or one side has
        /// no number.
        public var better: Better? {
            guard let higherIsBetter, let difference, difference != 0 else { return nil }
            return (difference > 0) == higherIsBetter ? .right : .left
        }

        public enum Better: String, Equatable, Sendable { case left, right }
    }

    /// Every scorer either side carries, in reading order, so success and the
    /// evidence that keeps it honest stay adjacent here too.
    public var rows: [Row] {
        let names = Set(left.log.results.metrics.keys)
            .union(right.log.results.metrics.keys)
        return EvalReport.ordered(Array(names)).map { name in
            let scorer = EvalReport.scorer(named: name)
            return Row(name: name, said: scorer?.said,
                       left: left.log.results.metrics[name],
                       right: right.log.results.metrics[name],
                       higherIsBetter: scorer?.higherIsBetter,
                       unit: scorer?.unit ?? "")
        }
    }

    /// Rows a scorer only one side measured, which is a fact about the two
    /// tasks rather than a result and is said out loud rather than left as a
    /// blank cell.
    public var oneSidedRows: [Row] { rows.filter { $0.left == nil || $0.right == nil } }

    // MARK: - the sentences

    public static let neverCombinedSaid =
        "There is no single number here saying which run won. A policy that travels further and "
      + "falls over more often is a different trade rather than a better one, and any score "
      + "combining the two would be a weighting nobody measured."

    public static let differenceIsNotAScoreSaid =
        "A difference is the same quantity measured twice in the same world and subtracted. It "
      + "is not a score of either run, and it means nothing across two worlds, which is why "
      + "this screen refuses those before it draws anything."

    public static let oneSidedSaid =
        "A scorer only one of these two measured is shown with the side that has it and a blank "
      + "beside it. A blank is not a zero."

    public static let whatCanBeComparedSaid =
        "Two logs can be put side by side when they name the same task and the same world, "
      + "digest included. Everything else about them is allowed to differ, including which "
      + "machine ran them and who wrote the file."
}
