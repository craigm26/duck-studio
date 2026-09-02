import Foundation

extension BallChallenge {

    /// The fourteen cells an entrant is scored over.
    ///
    /// WHY THERE IS A FALLBACK AT ALL, and it is the same reason the stairs
    /// grid has one: the bench answers `GET /chase/grid` precisely so a client
    /// never retypes the grid, but the app has to be able to DRAW fourteen
    /// rows before the first request comes back and to say what it is about to
    /// ask for. So the constants are pinned here, `BallGridTests` asserts them
    /// against `sim/chase_score.mjs`'s own, and any bench that disagrees wins:
    /// `cells(from:)` prefers what the bench says, every time it says
    /// anything.
    ///
    /// WHY THESE AXES. Bearing is the axis that makes this a chase. A ball
    /// dead ahead can be reached by a policy that only walks forward; a ball
    /// at ±20° cannot, and at ±40° certainly cannot. The grid is built so the
    /// bundled entrants pass some cells and fail others BY CONSTRUCTION — the
    /// off-bearing cells are what the challenge is about, and a leaderboard
    /// that only ever ran bearing 0 would look solved while nothing could
    /// chase anything.
    ///
    /// WHY THESE RANGES. Pollen's kick task spawns the ball 90 mm in front of
    /// the toe, so the NEAREST cell here is five times the distance the kick
    /// policies were trained at. None of the three core ranges is reachable
    /// without locomotion, deliberately. That gap is the finding this
    /// challenge exists to expose, not a mistake in the grid.
    ///
    /// THE ORDER IS THE HARNESS'S: the core nine first — each range crossed
    /// with each bearing — so a run stopped halfway is still the core grid
    /// every `k of 9` is quoted against, and only then the five extended.
    public enum Grid {

        /// A spawn-height and footpad-friction setting. Cell 0 is the nominal
        /// plant, and the other two are lifted verbatim from
        /// `climb_score.mjs`'s `PLANTS[1]` and `PLANTS[2]`, so "the slippery
        /// plant" means the same thing in both challenges.
        public struct Plant: Equatable, Sendable {
            public let drop: Double
            public let fmul: Double
            public init(drop: Double, fmul: Double) { self.drop = drop; self.fmul = fmul }
        }

        public static let nominal = Plant(drop: 0.120, fmul: 1.0)
        /// The centre cell on a slippery, higher-spawning plant.
        public static let slippery = Plant(drop: 0.130, fmul: 0.7)
        /// The centre cell on a grippy plant.
        public static let grippy = Plant(drop: 0.125, fmul: 1.3)

        /// `chase_score.mjs` `BEARINGS`, degrees, positive is LEFT.
        public static let bearings: [Double] = [-20, 0, 20]
        /// `chase_score.mjs` `RANGES`, metres.
        public static let ranges: [Double] = [0.45, 0.70, 0.95]
        /// The two bearings only the extended grid visits.
        public static let extendedBearings: [Double] = [-40, 40]
        /// The one range only the extended grid visits.
        public static let extendedRange = 1.20
        /// The range the off-plant and off-bearing extended cells sit at.
        public static let centreRange = 0.70
        public static let centreBearing = 0.0

        public static let coreCount = 9
        public static let extendedCount = 5
        public static let count = 14

        /// The pinned fourteen, in `chase_robust`'s order: the nine core, then
        /// the two plant perturbations of the centre cell, then the two wide
        /// bearings, then the far cell.
        public static let fallback: [DuckBench.ChaseCell] = {
            var cells: [DuckBench.ChaseCell] = []
            for range in ranges {
                for bearing in bearings {
                    cells.append(DuckBench.ChaseCell(bearing: bearing, range: range,
                                                     drop: nominal.drop, fmul: nominal.fmul,
                                                     tier: .core))
                }
            }
            for plant in [slippery, grippy] {
                cells.append(DuckBench.ChaseCell(bearing: centreBearing, range: centreRange,
                                                 drop: plant.drop, fmul: plant.fmul, tier: .ext))
            }
            for bearing in extendedBearings {
                cells.append(DuckBench.ChaseCell(bearing: bearing, range: centreRange,
                                                 drop: nominal.drop, fmul: nominal.fmul,
                                                 tier: .ext))
            }
            cells.append(DuckBench.ChaseCell(bearing: centreBearing, range: extendedRange,
                                             drop: nominal.drop, fmul: nominal.fmul, tier: .ext))
            return cells
        }()

        /// The nine, for a screen that wants to show the core grid alone.
        public static var core: [DuckBench.ChaseCell] { fallback.filter { $0.tier == .core } }
        public static var extended: [DuckBench.ChaseCell] { fallback.filter { $0.tier == .ext } }

        /// THE CENTRE CELL — bearing 0 at 0.70 m on the nominal plant — which
        /// is the one the two plant perturbations perturb, and the cell a
        /// screen should show first if it can only show one.
        public static var centre: DuckBench.ChaseCell {
            DuckBench.ChaseCell(bearing: centreBearing, range: centreRange,
                                drop: nominal.drop, fmul: nominal.fmul, tier: .core)
        }

        /// Said when the app is drawing the pinned grid because the bench has
        /// not answered yet — not a warning, a statement of which grid is on
        /// screen.
        public static let fallbackNote =
            "This is the grid chase_robust scores, drawn from the app's own copy. The bench is "
          + "asked for its grid before anything is scored, and its answer wins."

        /// What each half of the grid is for, said where the two are drawn
        /// apart.
        public static let coreNote =
            "The nine core cells: the ball at −20°, 0 and +20°, at 0.45, 0.70 and 0.95 m, on the "
          + "nominal plant. Every published k of 9 is quoted against these."
        public static let extendedNote =
            "The five extended cells: the centre cell on a slippery and on a grippy plant, the "
          + "ball at ±40°, and the ball straight ahead at 1.20 m — a walk rather than a lunge."

        /// Which half of the grid a cell belongs to, worked out from its own
        /// numbers. Used only when a bench answers a cell without a tier: a
        /// count that mixed the nine with the fourteen would not be comparable
        /// with any published row.
        public static func tier(bearing: Double, range: Double,
                                drop: Double, fmul: Double) -> DuckBench.ChaseCell.Tier {
            let nearlyEqual: (Double, Double) -> Bool = { abs($0 - $1) < 1e-9 }
            let isCoreBearing = bearings.contains { nearlyEqual($0, bearing) }
            let isCoreRange = ranges.contains { nearlyEqual($0, range) }
            let isNominal = nearlyEqual(drop, nominal.drop) && nearlyEqual(fmul, nominal.fmul)
            return isCoreBearing && isCoreRange && isNominal ? .core : .ext
        }

        /// The grid to use: the bench's, when it answered; the pinned one
        /// otherwise.
        public static func cells(from answer: Data?) -> [DuckBench.ChaseCell] {
            guard let answer, let read = try? DuckBench.readChaseGrid(answer),
                  !read.cells.isEmpty else { return fallback }
            return read.cells
        }

        /// Whether a bench's grid is the one the published numbers are
        /// produced on. A score from a bench that answered a DIFFERENT grid
        /// must not be called a leaderboard number, and this is how a screen
        /// knows.
        public static func isPublishedGrid(_ cells: [DuckBench.ChaseCell]) -> Bool {
            cells == fallback
        }

        public static let differentGridNote =
            "This bench scores a different grid from the one the leaderboard is produced on, so "
          + "what comes back is a measurement on that bench and not a comparable entry."
    }
}
