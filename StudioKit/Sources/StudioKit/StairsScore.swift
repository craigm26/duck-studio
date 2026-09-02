import Foundation

extension StairsChallenge {

    /// Fourteen answered cells, counted the way the audit counts them.
    ///
    /// THE APP DOES NO ARITHMETIC AND NEITHER DOES THE BENCH BEYOND ONE CELL.
    /// `/climb` scores one cell and says what happened in it; this counts. That
    /// split is what makes a score reproducible: every number below is a
    /// tally over answers a person can read one at a time, so a disagreement
    /// with `climb/robust.mjs` is findable in a single row rather than
    /// somewhere inside an aggregate.
    ///
    /// FIVE COUNTS, NOT ONE, BECAUSE THE PUBLISHED TABLE HAS FIVE COLUMNS.
    /// `kCore` is the round-3 nine cells under `honest`; `kCoreStable` is the
    /// same cells minus any the duck toppled in during the tail, and it is the
    /// column the leaderboard is ordered by. `kExt` and `kExtStable` are the
    /// fourteen. `ceilingCore` counts the core cells whose PEAK trunk height
    /// ever got over the 95 mm bar — an upper bound on what any landing law
    /// could have turned into a clear, which is the measurement that closed
    /// this challenge.
    public struct Score: Equatable, Sendable {

        /// Metres, the rise asked for.
        public let rise: Double
        /// Every answer, in the order the grid was walked.
        public let cells: [DuckBench.Climbed]

        public let kCore: Int
        public let kCoreStable: Int
        public let kExt: Int
        public let kExtStable: Int
        public let ceilingCore: Int
        /// How many core and extended cells actually came back — a score of
        /// five out of a grid that only answered six cells is not a five.
        public let coreAnswered: Int
        public let answered: Int
        /// Cells the bench refused as out of the intent's own declared search
        /// bounds. Any at all and this is not a result.
        public let invalidCells: Int

        public let hash: String?
        public let plantName: String?
        public let plantDigest: String?
        /// The bench's own criterion sentence, when every cell agreed on one.
        public let criterion: String?
        /// The greatest torque any servo reached, over every cell. 0.6405 N·m
        /// is the plant's ceiling.
        public let maxTorque: Double

        public init(rise: Double, cells: [DuckBench.Climbed]) {
            self.rise = rise
            self.cells = cells
            let core = cells.filter { $0.cell.tier == .core }
            kCore = core.filter { $0.honest && !$0.invalid }.count
            kCoreStable = core.filter { $0.stable && !$0.invalid }.count
            kExt = cells.filter { $0.honest && !$0.invalid }.count
            kExtStable = cells.filter { $0.stable && !$0.invalid }.count
            ceilingCore = core.filter { $0.overBar && !$0.invalid }.count
            coreAnswered = core.count
            answered = cells.count
            invalidCells = cells.filter(\.invalid).count
            hash = cells.first?.hash
            plantName = cells.compactMap(\.plantName).first
            plantDigest = cells.compactMap(\.plantDigest).first
            let criteria = Set(cells.map(\.criterion))
            criterion = criteria.count == 1 ? criteria.first : nil
            maxTorque = cells.map(\.maxTorque).max() ?? 0
        }

        // MARK: - what it means

        /// Every cell of the grid answered.
        public var isComplete: Bool { answered == Grid.count }

        /// Whether it met the bar. `kCoreStable`, never `kCore` — the bar is
        /// about a duck still standing.
        public var meetsBar: Bool { kCoreStable >= StairsChallenge.bar }

        /// Whether more than one hash came back. It can only happen if the
        /// intent changed under the run, and a score assembled from two moves
        /// is not a score of either.
        public var isMixed: Bool { Set(cells.map(\.hash)).count > 1 }

        /// The verdict. BOTH NUMBERS, because "5 of 9" and "the trunk got over
        /// the bar in 5 of 9" together say something neither says alone: that
        /// this move landed every cell it ever could have.
        public var verdict: String {
            "Cleared \(kCoreStable) of \(Grid.coreCount) stably at "
          + "\(StairsChallenge.riseSaid(rise)) against a bar of \(StairsChallenge.bar); "
          + "the trunk reached the bar in \(ceilingCore) of \(Grid.coreCount)."
        }

        /// The claim underneath the verdict: this is not a new criterion.
        public var sameCriterion: String {
            StairsChallenge.sameCriterion(plantDigest: plantDigest)
        }

        /// The extended grid, said only where it is worth saying — it is the
        /// half no family optimised against, so it is where a move that looks
        /// robust stops looking robust.
        public var extendedSaid: String {
            "Over all \(Grid.count) cells, including the five the round-4 audit added: "
          + "\(kExtStable) cleared and standing, \(kExt) cleared."
        }

        /// One line, for a submission body and for anywhere a table needs a
        /// cell rather than a paragraph.
        public var line: String {
            "\(kCoreStable)/\(Grid.coreCount) stable · \(kCore)/\(Grid.coreCount) honest · "
          + "\(kExtStable)/\(Grid.count) extended · ceiling \(ceilingCore)/\(Grid.coreCount) · "
          + "\(StairsChallenge.riseSaid(rise))"
        }

        /// What is wrong with this score, if anything, in the order it matters.
        /// EMPTY IS A CLAIM — that every cell of the published grid answered,
        /// on one move, inside its declared bounds — so it is worth being
        /// strict about.
        public var problems: [String] {
            var out: [String] = []
            if invalidCells > 0 {
                out.append("\(invalidCells) of \(answered) cells came back INVALID: this move "
                         + "falls outside its own declared search bounds, which makes it a "
                         + "search that left its box rather than a result.")
            }
            if isMixed {
                out.append("The cells do not all carry the same move hash, so this is not one "
                         + "move's score. Run it again without editing in between.")
            }
            if !isComplete {
                out.append("\(answered) of \(Grid.count) cells answered. A partial grid cannot "
                         + "be compared with a published row.")
            }
            // THE PLANT, BECAUSE A SCORE FROM ANOTHER WORLD IS ANOTHER NUMBER.
            // Every published row was produced in one plant; a bench that
            // names a different one, or none, is measuring something else.
            if let plantDigest, plantDigest != StairsChallenge.plantDigest {
                out.append("Scored in plant \(plantDigest.prefix(DuckBench.digestShown)), not the "
                         + "challenge's \(StairsChallenge.plantDigest.prefix(DuckBench.digestShown)). "
                         + "A number from a different world is not comparable with a published row.")
            } else if plantDigest == nil, answered > 0 {
                out.append("The bench did not identify its plant, so nothing says this was scored "
                         + "in the world the published rows were.")
            }
            if answered > 0, kExt == 0, kCore == 0, ceilingCore == 0 {
                out.append("Nothing in this run reached the flight. That is a real measurement of "
                         + "this move on this bench, and it is not a leaderboard entry.")
            }
            return out
        }

        /// Whether this run and a published row were scored at the same rise.
        public func sameRise(as row: Row) -> Bool {
            Int((rise * 1000).rounded()) == row.riseMillimetres
        }

        /// What one edit bought or cost, against the score it was started
        /// from — the sentence of the edit-score-keep loop.
        public func change(from previous: Score) -> String {
            let before = previous.kCoreStable, after = kCoreStable
            let cells = "\(Grid.coreCount)"
            if after > before {
                return "Better: \(after) of \(cells) stable where it was \(before). Keep it."
            }
            if after == before {
                return "The same: \(after) of \(cells) stable before and after. The edit changed "
                     + "nothing the criterion can see."
            }
            return "Worse: \(after) of \(cells) stable where it was \(before). Put it back, or "
                 + "keep going from here on purpose."
        }

        /// Whether this is comparable with the leaderboard at all.
        public var isPublishable: Bool { problems.isEmpty }

        /// How it sits against the row it was started from — the sentence that
        /// stops a screen implying somebody beat a record they matched.
        public func against(_ row: Row) -> String {
            // A LOWER RISE IS A STRICTLY EASIER TASK, so two counts at
            // different rises are not one comparison. Say both rises and stop.
            guard sameRise(as: row) else {
                return "Scored at \(StairsChallenge.riseSaid(rise)); the published row for "
                     + "\(row.hash) is at \(row.riseMillimetres) mm. A lower rise is a strictly "
                     + "easier task, so the two counts are not compared."
            }
            if kCoreStable > row.kCoreStable {
                return "That is better than the published \(row.kCoreStable) of "
                     + "\(Grid.coreCount) for \(row.hash). Worth submitting."
            }
            if kCoreStable == row.kCoreStable {
                return "That is the published \(row.kCoreStable) of \(Grid.coreCount) for "
                     + "\(row.hash), reproduced here."
            }
            return "The published row for \(row.hash) is \(row.kCoreStable) of "
                 + "\(Grid.coreCount); this run got \(kCoreStable). Different bench, different "
                 + "plant, or an edit — the cells above say which."
        }
    }

    /// A score being built, one cell at a time, so a screen has something
    /// truthful to draw while fourteen requests are in flight.
    public struct ScoreProgress: Equatable, Sendable {
        public let grid: [DuckBench.Cell]
        public let done: [DuckBench.Climbed]
        public let failures: [String]

        public init(grid: [DuckBench.Cell], done: [DuckBench.Climbed] = [],
                    failures: [String] = []) {
            self.grid = grid; self.done = done; self.failures = failures
        }

        public var remaining: Int { max(grid.count - done.count - failures.count, 0) }

        public var isFinished: Bool { done.count + failures.count >= grid.count }

        /// "Cell 6 of 14 — 60/.120/x1.0". The rise is needed because a cell's
        /// own label is a rise, and the label is what the published results
        /// print.
        public func said(rise: Double) -> String {
            let index = done.count + failures.count
            guard index < grid.count else {
                return "\(grid.count) of \(grid.count) cells scored."
            }
            return "Cell \(index + 1) of \(grid.count) — \(grid[index].said(rise: rise))"
        }

        public func score(rise: Double) -> Score { Score(rise: rise, cells: done) }
    }
}
