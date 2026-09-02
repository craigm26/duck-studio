import Foundation

extension StairsChallenge {

    /// The fourteen cells a submission is scored over.
    ///
    /// WHY THERE IS A FALLBACK AT ALL. The bench answers the grid at
    /// `GET /climb/grid` precisely so a client never retypes it — a client
    /// that invented its own grid would produce a number that looks like a
    /// leaderboard entry and is not one. But the app has to be able to DRAW
    /// the fourteen rows before the first request comes back, and it has to be
    /// able to say what it is about to ask for. So the constants are pinned
    /// here, `StairsGridTests` asserts them against `climb/robust.mjs`'s own
    /// `PLANTS` / `DHS` / `EXT_DHS` / `EXT_PLANT`, and any bench that answers
    /// disagrees at its own request: `cells(from:)` prefers what the bench
    /// says, every time it says anything.
    ///
    /// THE ORDER IS THE HARNESS'S. `scoreRobust` runs the core nine first —
    /// each rise offset crossed with each plant — so a run stopped halfway is
    /// still the round-3 grid everybody's `k of 9` is quoted against, and only
    /// then the five the round-4 audit added. A progress list in a different
    /// order would show a partial score nobody could compare with anything.
    public enum Grid {

        /// A spawn-height and footpad-friction setting. Cell 0 is the nominal
        /// plant `rig3` itself uses.
        public struct Plant: Equatable, Sendable {
            public let drop: Double
            public let fmul: Double
            public init(drop: Double, fmul: Double) { self.drop = drop; self.fmul = fmul }
        }

        /// `climb/robust.mjs` `PLANTS`.
        public static let plants: [Plant] = [
            Plant(drop: 0.120, fmul: 1.0),
            Plant(drop: 0.130, fmul: 0.7),
            Plant(drop: 0.125, fmul: 1.3),
        ]
        /// `climb/robust.mjs` `DHS` — the rise offsets, in metres.
        public static let dhs: [Double] = [-0.010, 0.000, 0.010]
        /// `climb/robust.mjs` `EXT_DHS` — nominal plant only.
        public static let extendedDHs: [Double] = [-0.005, 0.005]
        /// `climb/robust.mjs` `EXT_PLANT` — the slippery plant, crossed with
        /// the three core rises. Friction ×0.5 at a 20 mm higher fall: the
        /// axis no family ever optimised against.
        public static let extendedPlant = Plant(drop: 0.140, fmul: 0.5)

        public static let coreCount = 9
        public static let count = 14

        /// The pinned fourteen, in `scoreRobust`'s order.
        public static let fallback: [DuckBench.Cell] = {
            var cells: [DuckBench.Cell] = []
            for dh in dhs {
                for plant in plants {
                    cells.append(DuckBench.Cell(dh: dh, drop: plant.drop, fmul: plant.fmul,
                                                tier: .core))
                }
            }
            for dh in extendedDHs {
                cells.append(DuckBench.Cell(dh: dh, drop: plants[0].drop, fmul: plants[0].fmul,
                                            tier: .ext))
            }
            for dh in dhs {
                cells.append(DuckBench.Cell(dh: dh, drop: extendedPlant.drop,
                                            fmul: extendedPlant.fmul, tier: .ext))
            }
            return cells
        }()

        /// Said when the app is drawing the pinned grid because the bench has
        /// not answered yet — not a warning, a statement of which grid is on
        /// screen.
        public static let fallbackNote =
            "This is the grid the audit published, drawn from the app's own copy. The bench is "
          + "asked for its grid before anything is scored, and its answer wins."

        /// Which half of the grid a cell belongs to, worked out from its own
        /// numbers. Used only when a bench answers a cell without a tier: a
        /// count that mixed the nine with the fourteen would not be comparable
        /// with any published row.
        public static func tier(dh: Double, drop: Double, fmul: Double) -> DuckBench.Cell.Tier {
            let nearlyEqual: (Double, Double) -> Bool = { abs($0 - $1) < 1e-9 }
            let isCoreRise = dhs.contains { nearlyEqual($0, dh) }
            let isCorePlant = plants.contains {
                nearlyEqual($0.drop, drop) && nearlyEqual($0.fmul, fmul)
            }
            return isCoreRise && isCorePlant ? .core : .ext
        }

        /// The grid to use: the bench's, when it answered; the pinned one
        /// otherwise.
        public static func cells(from answer: Data?) -> [DuckBench.Cell] {
            guard let answer, let read = try? DuckBench.readClimbGrid(answer),
                  !read.cells.isEmpty else { return fallback }
            return read.cells
        }

        /// Whether a bench's grid is the one every published number was
        /// produced on. A screen showing a score from a bench that answered a
        /// DIFFERENT grid must not call it a leaderboard number, and this is
        /// how it knows.
        public static func isPublishedGrid(_ cells: [DuckBench.Cell]) -> Bool {
            cells == fallback
        }

        public static let differentGridNote =
            "This bench scores a different grid from the one the leaderboard was produced on, so "
          + "what comes back is a measurement on that bench and not a comparable entry."
    }
}
