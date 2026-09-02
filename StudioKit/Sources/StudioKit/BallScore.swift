import Foundation

extension BallChallenge {

    /// Fourteen answered cells, counted the way the harness counts them.
    ///
    /// THE APP DOES NO ARITHMETIC AND THE BENCH DOES NONE BEYOND ONE CELL.
    /// `/chase` scores one cell and says what happened in it; this counts.
    /// That split is what makes a score reproducible: every number below is a
    /// tally over answers a person can read one at a time, so a disagreement
    /// with `chase_robust.mjs` is findable in a single row rather than
    /// somewhere inside an aggregate.
    ///
    /// FOUR COUNTS. `kChased` is the nine core cells under the criterion and
    /// it is what the leaderboard sorts on; `kStable` is the same nine minus
    /// any the duck toppled in during the tail, and it is the stricter one
    /// printed beside it. `kExt` and `kExtStable` are the FIVE EXTENDED CELLS
    /// ONLY, not all fourteen — the extended half is the half nothing was
    /// tuned against, so it is worth being able to read on its own.
    public struct Score: Equatable, Sendable {

        /// Every answer, in the order the grid was walked.
        public let cells: [DuckBench.Chased]

        /// Of the nine core cells.
        public let kChased: Int
        public let kStable: Int
        /// Of the five extended cells.
        public let kExt: Int
        public let kExtStable: Int

        /// How many core and extended cells actually came back — a three out
        /// of a grid that only answered four cells is not a three.
        public let coreAnswered: Int
        public let extendedAnswered: Int
        public let answered: Int
        /// Cells the bench refused to score. Any at all and this is not a
        /// result.
        public let invalidCells: Int

        // The facts, summarised over the cells that answered. EACH ONE IS AN
        // EXTREME OR A COUNT, never a mean: an average of fourteen ball
        // travels over a grid where nine of them are zero is a number that
        // describes nothing that happened.

        /// The furthest the ball was ever moved along the duck's initial
        /// heading, over every cell.
        public let bestBallTravelMillimetres: Double
        /// The closest the duck ever got to the ball, over every cell.
        public let closestMillimetres: Double
        /// How many cells the duck touched the ball in at all.
        public let touchedCells: Int
        /// The fastest the ball ever went.
        public let ballPeakSpeed: Double
        /// How many cells ended with the duck upright.
        public let uprightCells: Int

        public let hash: String?
        public let plantName: String?
        public let plantDigest: String?
        /// The bench's own criterion sentence, when every cell agreed on one.
        public let criterion: String?

        public init(cells: [DuckBench.Chased]) {
            self.cells = cells
            let core = cells.filter { $0.cell.tier == .core }
            let extended = cells.filter { $0.cell.tier == .ext }
            kChased = core.filter { $0.chased && !$0.invalid }.count
            kStable = core.filter { $0.stable && !$0.invalid }.count
            kExt = extended.filter { $0.chased && !$0.invalid }.count
            kExtStable = extended.filter { $0.stable && !$0.invalid }.count
            coreAnswered = core.count
            extendedAnswered = extended.count
            answered = cells.count
            invalidCells = cells.filter(\.invalid).count

            let scored = cells.filter { !$0.invalid }
            bestBallTravelMillimetres = scored.map(\.ballTravelMillimetres).max() ?? 0
            closestMillimetres = scored.map(\.closestMillimetres).min() ?? 0
            touchedCells = scored.filter(\.touched).count
            ballPeakSpeed = scored.map(\.ballPeakSpeed).max() ?? 0
            uprightCells = scored.filter(\.upright).count

            hash = cells.first?.hash
            plantName = cells.compactMap(\.plantName).first
            plantDigest = cells.compactMap(\.plantDigest).first
            let criteria = Set(cells.map(\.criterion))
            criterion = criteria.count == 1 ? criteria.first : nil
        }

        // MARK: - what it means

        /// Every cell of the grid answered.
        public var isComplete: Bool { answered == Grid.count }

        /// Whether more than one hash came back. It can only happen if the
        /// entrant changed under the run, and a score assembled from two
        /// entrants is not a score of either.
        public var isMixed: Bool { Set(cells.map(\.hash)).count > 1 }

        /// Whether the bench's own criterion sentence is the one this build
        /// was written against. A bench running an older `chase_score.mjs`
        /// would answer honestly and mean something else by `chased`.
        public var criterionMatches: Bool {
            guard let criterion else { return cells.isEmpty }
            return criterion == BallChallenge.criterionSentence
        }

        /// THE VERDICT. `kChased` first because it is what the leaderboard
        /// sorts on, `kStable` beside it because "the ball moved" and "the
        /// duck is still a robot afterwards" are two different claims.
        public var verdict: String {
            "Chased the ball in \(kChased) of \(Grid.coreCount) core cells, "
          + "\(kStable) of them still standing."
        }

        /// The claim underneath the verdict: this is not a new criterion.
        public var sameCriterion: String {
            BallChallenge.sameCriterion(plantDigest: plantDigest)
        }

        /// The extended grid, said only where it is worth saying — the two
        /// plant perturbations, the two wide bearings and the far cell are
        /// where an entrant that looks like a chaser stops looking like one.
        public var extendedSaid: String {
            "Over the five extended cells — the centre cell on two other plants, the ball at "
          + "±40°, and the ball at 1.20 m — \(kExt) chased and \(kExtStable) of those still "
          + "standing."
        }

        /// The facts, in one line, for a screen that has already shown the
        /// verdict and wants to say what actually happened.
        public var factsSaid: String {
            "Touched the ball in \(touchedCells) of \(answered) cells; the furthest it went "
          + "along the duck's heading was \(Self.round(bestBallTravelMillimetres)) mm; the "
          + "closest the duck ever got was \(Self.round(closestMillimetres)) mm; peak ball speed "
          + "\(String(format: "%.2f", ballPeakSpeed)) m/s."
        }

        /// One line, for a submission body and anywhere a table needs a cell
        /// rather than a paragraph.
        public var line: String {
            "\(kChased)/\(Grid.coreCount) chased · \(kStable)/\(Grid.coreCount) stable · "
          + "\(kExt)/\(Grid.extendedCount) extended · touched \(touchedCells)/\(answered)"
        }

        static func round(_ value: Double) -> String { String(format: "%.1f", value) }

        /// What is wrong with this score, if anything, in the order it
        /// matters. EMPTY IS A CLAIM — that every cell of the published grid
        /// answered, on one entrant, under the criterion this build was
        /// written against — so it is worth being strict about.
        public var problems: [String] {
            var out: [String] = []
            if invalidCells > 0 {
                out.append("\(invalidCells) of \(answered) cells came back INVALID: the bench "
                         + "would not score them, which makes this a run that did not happen "
                         + "rather than a result.")
            }
            if isMixed {
                out.append("The cells do not all carry the same entrant hash, so this is not one "
                         + "entrant's score. Run it again without editing in between.")
            }
            if !isComplete {
                out.append("\(answered) of \(Grid.count) cells answered. A partial grid cannot "
                         + "be compared with a published row.")
            }
            // THE PLANT, BECAUSE A SCORE FROM ANOTHER WORLD IS ANOTHER NUMBER.
            if let plantDigest, plantDigest != BallChallenge.plantDigest {
                out.append("Scored in plant \(plantDigest.prefix(DuckBench.digestShown)), not the "
                         + "challenge's \(BallChallenge.plantDigest.prefix(DuckBench.digestShown)). "
                         + "A number from a different world is not comparable with a published row.")
            } else if plantDigest == nil, answered > 0 {
                out.append("The bench did not identify its plant, so nothing says this was scored "
                         + "in the world the published rows are.")
            }
            // THE CRITERION, BECAUSE A BENCH CAN MEAN SOMETHING ELSE BY THE
            // SAME WORD. `chased` from an older chase_score is a different
            // verdict wearing this one's name.
            if answered > 0, !criterionMatches {
                out.append("This bench's criterion sentence is not the one this build was "
                         + "written against, so `chased` here and `chased` on the leaderboard "
                         + "may not be the same test. Update the bench, or read its sentence "
                         + "before comparing.")
            }
            if answered > 0, touchedCells == 0 {
                out.append("The duck never touched the ball in any cell. That is a real "
                         + "measurement of this entrant on this bench, and it is not a "
                         + "leaderboard entry.")
            }
            return out
        }

        /// Whether this is comparable with the leaderboard at all.
        public var isPublishable: Bool { problems.isEmpty }

        /// What one edit bought or cost, against the score it was started
        /// from — the sentence of the edit-score-keep loop.
        public func change(from previous: Score) -> String {
            let before = previous.kChased, after = kChased
            let cells = "\(Grid.coreCount)"
            if after > before {
                return "Better: \(after) of \(cells) chased where it was \(before). Keep it."
            }
            if after == before {
                // THE SECOND NUMBER MATTERS HERE. Two runs can chase the same
                // count and differ in every fact underneath, and an edit that
                // moved the ball 40 mm further without crossing the bar is an
                // edit worth keeping going from.
                let moved = bestBallTravelMillimetres - previous.bestBallTravelMillimetres
                if abs(moved) >= 1 {
                    let direction = moved > 0 ? "further" : "less far"
                    return "The same: \(after) of \(cells) chased before and after. The ball went "
                         + "\(Self.round(abs(moved))) mm \(direction) than it did, which the "
                         + "criterion cannot see but you can."
                }
                return "The same: \(after) of \(cells) chased before and after. The edit changed "
                     + "nothing the criterion can see."
            }
            return "Worse: \(after) of \(cells) chased where it was \(before). Put it back, or "
                 + "keep going from here on purpose."
        }

        /// How it sits against the row it was started from — the sentence that
        /// stops a screen implying somebody beat a record they matched.
        public func against(_ row: Row) -> String {
            // THE EPISODE LENGTH IS PART OF THE MEASUREMENT. Four seconds of
            // walking and five seconds of walking are not the same task, so
            // two counts at different lengths are not one comparison.
            guard let mine = cells.first?.seconds, abs(mine - row.seconds) < 1e-9 else {
                let mineSaid = cells.first.map { BallChallenge.secondsSaid($0.seconds) }
                    ?? "an unstated length"
                return "Scored over \(mineSaid); the published row for \(row.hash) is over "
                     + "\(BallChallenge.secondsSaid(row.seconds)). A longer episode is a "
                     + "different task, so the two counts are not compared."
            }
            if kChased > row.kChased {
                return "That is better than the published \(row.kChased) of \(Grid.coreCount) "
                     + "for \(row.hash). Worth submitting."
            }
            if kChased == row.kChased {
                return "That is the published \(row.kChased) of \(Grid.coreCount) for "
                     + "\(row.hash), reproduced here."
            }
            return "The published row for \(row.hash) is \(row.kChased) of \(Grid.coreCount); "
                 + "this run got \(kChased). Different bench, different plant, or an edit — the "
                 + "cells above say which."
        }

        /// Every term the bench refused, deduplicated across the cells. THE
        /// SCREEN SHOWS THIS EVEN WHEN EVERY CELL PASSED: three named
        /// refusals with reasons are what makes the nine reported terms a
        /// transcription rather than a selection.
        public var refused: [DuckBench.RefusedTerm] {
            var seen: Set<String> = []
            var out: [DuckBench.RefusedTerm] = []
            for cell in cells {
                for refusal in cell.refused where !seen.contains(refusal.term) {
                    seen.insert(refusal.term)
                    out.append(refusal)
                }
            }
            return out
        }

        /// Which action `action_rate_l2` was differenced over, when every cell
        /// agreed — which they do unless a run mixed a move and a policy, and
        /// that is exactly the case a screen must not print one label for.
        public var actionRateSource: String? {
            let sources = Set(cells.compactMap(\.actionRateSource))
            return sources.count == 1 ? sources.first : nil
        }

        /// Each reward term's mean value and weight over the cells that
        /// answered it, in the order the first cell listed them.
        ///
        /// A MEAN IS HONEST HERE AND NOT FOR THE FACTS, because a term is a
        /// per-tick reward already averaged over an episode: averaging
        /// fourteen episode means is what a training run's own logging does.
        /// A ball travel is one event and averaging it describes nothing.
        public var terms: [DuckBench.RewardTerm] {
            guard let first = cells.first else { return [] }
            return first.terms.map { template in
                let values = cells.compactMap { cell in
                    cell.terms.first { $0.term == template.term }?.value
                }
                let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                return DuckBench.RewardTerm(term: template.term, weight: template.weight,
                                            value: mean,
                                            weightStage0: template.weightStage0,
                                            reference: template.reference,
                                            formula: template.formula,
                                            actionRateSource: template.actionRateSource)
            }
        }
    }

    /// A score being built, one cell at a time, so a screen has something
    /// truthful to draw while fourteen requests are in flight.
    public struct ScoreProgress: Equatable, Sendable {
        public let grid: [DuckBench.ChaseCell]
        public let done: [DuckBench.Chased]
        public let failures: [String]

        public init(grid: [DuckBench.ChaseCell], done: [DuckBench.Chased] = [],
                    failures: [String] = []) {
            self.grid = grid; self.done = done; self.failures = failures
        }

        public var remaining: Int { max(grid.count - done.count - failures.count, 0) }

        public var isFinished: Bool { done.count + failures.count >= grid.count }

        /// "Cell 6 of 14 — +20°/0.70/.120/x1.0".
        public var said: String {
            let index = done.count + failures.count
            guard index < grid.count else {
                return "\(grid.count) of \(grid.count) cells scored."
            }
            return "Cell \(index + 1) of \(grid.count) — \(grid[index].said)"
        }

        public var score: Score { Score(cells: done) }
    }
}
