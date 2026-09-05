import Foundation

/// How many times a scene is run, what changes between the runs, and how the
/// answers are collapsed into one.
///
/// THE AXIS HAS TWO CASES AND NEITHER OF THEM IS "HOW MANY TIMES". Upstream's
/// `Epochs` is a repeat count, which is right for a stochastic policy in a
/// stochastic world. Neither is true here: `/tune` at a fixed drop height is
/// deterministic, so five epochs of one episode would be one number written out
/// five times and then averaged, which is a spread of zero and a confident lie.
/// What actually varies on this bench is the height the duck is dropped from,
/// so that is the axis, and there is no `.repeats(n)` case for a control to
/// bind to.
///
/// The five reducers are theirs, arithmetic for arithmetic (`scorer.py`
/// `_REDUCERS`), down to the last place: `mean` goes through `ExactMean`,
/// which sums exactly and rounds once the way `statistics.mean` does rather
/// than rounding after every addition, and `mode` breaks ties on the printed
/// form the way theirs does. `pass_at_k` is theirs too and is implemented here
/// for READING A LOG SOMEBODY ELSE WROTE and for nothing else: see
/// `noPassAtK`.
public struct EvalEpochs: Equatable, Sendable {

    /// What changes between the epochs of one scene.
    public enum Axis: Equatable, Sendable {
        /// One episode per drop height, in the order given. The bench answers
        /// them all in one call.
        case dropHeights([Double])
        /// One episode. Used where the task's own grid is the axis, so an
        /// epoch count on top of it would be the same cell scored twice.
        case single

        public var count: Int {
            switch self {
            case .dropHeights(let values): return values.count
            case .single: return 1
            }
        }

        public var dropValues: [Double]? {
            if case .dropHeights(let values) = self { return values }
            return nil
        }
    }

    /// Their five, and no sixth. `pass_at_<k>` is resolved by name in their
    /// code rather than being a member of `_REDUCERS`, and it is not offered
    /// here at all.
    public enum Reducer: String, Equatable, Sendable, CaseIterable {
        case mean, median, max, min, mode

        public var said: String {
            switch self {
            case .mean: return "the average of the epochs"
            case .median: return "the middle epoch"
            case .max: return "the best epoch"
            case .min: return "the worst epoch"
            case .mode: return "the answer that came up most"
            }
        }
    }

    public let axis: Axis
    public let reducer: Reducer

    public var count: Int { axis.count }

    init(axis: Axis, reducer: Reducer) {
        self.axis = axis
        self.reducer = reducer
    }

    // MARK: - building one

    /// The bench's own validation, reimplemented in the bench's own words.
    ///
    /// WHY REIMPLEMENTED AND NOT LEFT TO THE BENCH. A drop list the bench
    /// refuses costs a round trip, a spinner and a dialogue after the tap. The
    /// same rule in front of the Start button costs a sentence under the
    /// control. The words are theirs so the two can never disagree about what
    /// was wrong.
    public enum Refusal: Error, Equatable {
        case noDrops
        case outOfRange
        case tooMany(Int)
        case duplicateDrop

        public var message: String {
            switch self {
            case .noDrops:
                return "An evaluation needs at least one drop height to run from."
            case .outOfRange:
                return "The bench says: every drop height must be a finite number of metres "
                     + "between 0 and 1."
            case .tooMany(let count):
                return "The bench says: at most 32 drop heights in one call. That list has "
                     + "\(count)."
            case .duplicateDrop:
                return "The bench says: the drop heights repeat; every drop is one "
                     + "deterministic episode, and the same height twice is the same episode "
                     + "counted twice."
            }
        }
    }

    public static func drops(_ values: [Double], reducer: Reducer) throws -> EvalEpochs {
        guard !values.isEmpty else { throw Refusal.noDrops }
        guard values.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1 }) else {
            throw Refusal.outOfRange
        }
        guard values.count <= 32 else { throw Refusal.tooMany(values.count) }
        // Nine decimal places, because that is the comparison the bench makes.
        let spelled = values.map { String(format: "%.9f", $0) }
        guard Set(spelled).count == values.count else { throw Refusal.duplicateDrop }
        return EvalEpochs(axis: .dropHeights(values), reducer: reducer)
    }

    public static func single(reducer: Reducer) -> EvalEpochs {
        EvalEpochs(axis: .single, reducer: reducer)
    }

    // MARK: - what a person reads

    /// Written into `policy_config` and drawn under the epoch control, so the
    /// axis is a sentence rather than a number a reader has to reverse engineer
    /// out of a list.
    public var said: String {
        switch axis {
        case .single:
            return "One episode per scene. The task's own grid is the axis here, so an epoch "
                 + "count on top of it would score the same cell twice."
        case .dropHeights(let values):
            let low = String(format: "%.4f", values.min() ?? 0)
            let high = String(format: "%.4f", values.max() ?? 0)
            let word = Self.counted(values.count)
            return "\(word) drop \(values.count == 1 ? "height" : "heights"), \(low) m to "
                 + "\(high) m, each run once. Nothing else varies between the epochs of a scene."
        }
    }

    /// Small numbers in words, because "3 drop heights" reads like a
    /// measurement and "Three drop heights" reads like a sentence. Anything
    /// past eight is a numeral, which is where the app's other copy draws the
    /// line too.
    static func counted(_ value: Int) -> String {
        switch value {
        case 1: return "One"
        case 2: return "Two"
        case 3: return "Three"
        case 4: return "Four"
        case 5: return "Five"
        case 6: return "Six"
        case 7: return "Seven"
        case 8: return "Eight"
        default: return String(value)
        }
    }

    /// Two sentences, and the second one is the point: saying "no seed" without
    /// saying what DOES vary leaves a reader thinking the epochs are copies.
    public static let noSeedSaid =
        "No seed was recorded, because no route on this bench reads one and a seed here would "
      + "name a control nothing used. What varies between the epochs of a scene is the height "
      + "the duck is dropped from, and every height is listed."

    /// The same fact on the axis that has no drop list.
    ///
    /// IT IS A SEPARATE CONSTANT BECAUSE THE SECOND HALF IS A DIFFERENT FACT.
    /// A grid run has one episode per scene and no drop height anywhere in it,
    /// so the sentence above would sit two keys away from an `epoch_axis`
    /// saying the grid is the axis and contradict it in the same dictionary.
    public static let noSeedOnAGridSaid =
        "No seed was recorded, because no route on this bench reads one and a seed here would "
      + "name a control nothing used. What varies here is the challenge's own grid, one episode "
      + "per cell, and every cell is a scene of its own."

    /// Which of the two the axis of this run is entitled to.
    public var seedNote: String {
        switch axis {
        case .single: return Self.noSeedOnAGridSaid
        case .dropHeights: return Self.noSeedSaid
        }
    }

    /// Under the progress bar on the run screen, because the bar moves in
    /// steps somebody would otherwise think were a stall.
    ///
    /// THE REQUEST SHAPE IS THE BENCH'S AND NOT A CHOICE MADE HERE. One `/tune`
    /// call is given the whole drop list and answers all of it at once, so the
    /// epochs of a scene arrive together and a scene is the unit of progress
    /// and of cancellation. A bar counting trials would sit still for the fifty
    /// seconds a scene takes and then jump by eight.
    public static let wholeSceneAtOnceSaid =
        "A scene is asked for in one request and answers all of its epochs at once, so progress "
      + "moves a scene at a time and stopping takes effect at the end of the scene that is "
      + "running."

    public static let noPassAtK =
        "pass at k is not offered. It estimates how often a success would appear in k "
      + "independent draws, and these epochs are not draws. They are a fixed list of drop "
      + "heights the bench walks in order, so the estimator's assumption is false here and its "
      + "number would look like a probability without being one."

    // MARK: - the arithmetic, which is theirs

    /// One scene's epoch values, collapsed. Nil for an empty list, which is
    /// what an all-errored scene has, because errored trials are recorded and
    /// never scored.
    public func reduce(_ values: [Double]) -> Double? {
        Self.reduce(values, with: reducer)
    }

    public static func reduce(_ values: [Double], with reducer: Reducer) -> Double? {
        guard !values.isEmpty else { return nil }
        switch reducer {
        case .mean:
            // `statistics.mean` and not a running sum: theirs adds exactly and
            // rounds once, and a running sum rounds after every addition. See
            // `ExactMean`, which is what makes "arithmetic for arithmetic" a
            // statement rather than an aspiration.
            return ExactMean.mean(values)
        case .median:
            // `statistics.median` averages the two middle values at even n
            // rather than picking one, which is the half a hand-rolled median
            // usually gets wrong.
            let sorted = values.sorted()
            let middle = sorted.count / 2
            if sorted.count % 2 == 1 { return sorted[middle] }
            return (sorted[middle - 1] + sorted[middle]) / 2
        case .max:
            return values.max()
        case .min:
            return values.min()
        case .mode:
            return mode(values)
        }
    }

    /// `max(values, key=lambda v: (counts[v], str(v)))`.
    ///
    /// THE TIE BREAK IS PART OF THE ANSWER. Their reducer is deterministic on
    /// purpose, and it is deterministic because ties are broken on the value's
    /// PRINTED FORM, comparing by code point. A Swift implementation that broke
    /// ties on the numeric value would agree with theirs on every list where no
    /// two answers came up equally often, and disagree exactly where the tie
    /// break was the whole reason the rule exists.
    static func mode(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        var counts: [(value: Double, count: Int, spelled: String)] = []
        for value in values {
            if let index = counts.firstIndex(where: { $0.value == value }) {
                counts[index].count += 1
            } else {
                counts.append((value, 1, EvalLogJSON.spelled(value)))
            }
        }
        return counts.max { a, b in
            if a.count != b.count { return a.count < b.count }
            return a.spelled.utf8.lexicographicallyPrecedes(b.spelled.utf8)
        }?.value
    }

    /// Their `pass_at_k`, FOR READING A LOG SOMEBODY ELSE WROTE.
    ///
    /// It is here so an imported log that used `pass_at_3` reduces on this
    /// phone the way it reduced on the machine that wrote it. It is not offered
    /// as a reducer for a run this app makes, and `Reducer` has no case for it,
    /// so there is nothing for a picker to show. See `noPassAtK`.
    public enum PassAtKRefusal: Error, Equatable {
        case kBelowOne(Int)
        case notEnoughEpochs(k: Int, epochs: Int)
    }

    public static func passAtK(_ k: Int, over values: [Double]) throws -> Double {
        guard k >= 1 else { throw PassAtKRefusal.kBelowOne(k) }
        let n = values.count
        guard k <= n else { throw PassAtKRefusal.notEnoughEpochs(k: k, epochs: n) }
        let c = values.filter { $0 >= 0.5 }.count
        guard n - c >= k else { return 1.0 }
        return 1.0 - combinations(n - c, k) / combinations(n, k)
    }

    /// n choose k as a Double, multiplied a term at a time so the intermediate
    /// stays small: a factorial of 32 does not fit anywhere useful.
    static func combinations(_ n: Int, _ k: Int) -> Double {
        guard k >= 0, k <= n else { return 0 }
        var result = 1.0
        for step in 0..<min(k, n - k) {
            result = result * Double(n - step) / Double(step + 1)
        }
        return result.rounded()
    }
}
