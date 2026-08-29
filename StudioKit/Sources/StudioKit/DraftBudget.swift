import Foundation

/// How many turns a run gets and how long it gets, against a clock somebody
/// else owns.
///
/// MIRRORS quackd's `safety.Budget`, INCLUDING WHERE THE COUNTER LANDS.
/// `check()` runs BEFORE the increment, so `maxSteps = 40` allows exactly forty
/// steps and the run dies on the forty-first with `spent` reading 40, not 41.
/// That is worth pinning rather than leaving to taste: `spent` is the number
/// that ends up in the refusal a person reads, and a budget reporting "41 of
/// 40 spent" looks like the bug instead of the limit.
///
/// THE DEADLINE IS A STRICT `>`. A run that lands exactly on its last second
/// is inside its budget. The same comparison as quackd's, and the same reason:
/// a boundary that rejects the boundary makes "five minutes" mean "just under
/// five minutes" and nobody can say which by reading it.
///
/// THE CLOCK IS INJECTED, AND THAT IS THE POINT. `now` is supplied by the
/// caller — quackd's real callers hand it the TRANSPORT's clock rather than
/// the wall clock, so a run under simulation is budgeted in simulated seconds
/// and a test can drive a deadline to its exact edge without sleeping. Reach
/// for `Date()` in here and both of those stop being possible: the tests
/// become slow and flaky, and a budget can no longer follow the thing it is
/// supposed to be measuring. There is deliberately no default.
public struct DraftBudget: Sendable {

    public let maxSteps: Int
    public let maxSeconds: Double

    private let now: @Sendable () -> Double
    /// Read once, at construction: a budget measures from when it was made.
    private let started: Double

    /// Steps actually taken. See the note above about where this lands when
    /// the budget runs out.
    public private(set) var spent: Int = 0

    public init(maxSteps: Int, maxSeconds: Double, now: @escaping @Sendable () -> Double) {
        self.maxSteps = maxSteps
        self.maxSeconds = maxSeconds
        self.now = now
        self.started = now()
    }

    /// On the injected clock, in whatever seconds that clock counts.
    public var elapsed: Double { now() - started }

    public enum Exhausted: Error, Equatable {
        case outOfSteps(spent: Int, allowed: Int)
        case outOfTime(elapsed: Double, allowed: Double)

        /// The reason, in words, because this is what gets shown.
        public var message: String {
            switch self {
            case .outOfSteps(let spent, let allowed):
                return "That is \(spent) of \(allowed) tries used up, which is all of them."
            case .outOfTime(let elapsed, let allowed):
                return String(format: "Time is up: %.0f s of the %.0f s this was given.",
                              elapsed, allowed)
            }
        }
    }

    /// Refuse, or say nothing. Does not count anything — see `spend()`.
    public func check() throws {
        guard spent < maxSteps else {
            throw Exhausted.outOfSteps(spent: spent, allowed: maxSteps)
        }
        // Written as the strict comparison rather than its inverse so that it
        // reads the same as the rule above it.
        let age = elapsed
        if age > maxSeconds {
            throw Exhausted.outOfTime(elapsed: age, allowed: maxSeconds)
        }
    }

    /// The single call a step makes: check FIRST, then count.
    public mutating func spend() throws {
        try check()
        spent += 1
    }
}
