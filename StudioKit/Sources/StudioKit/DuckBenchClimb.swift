import Foundation

/// The two calls the stairs challenge adds to a bench, and what comes back.
///
/// ONE CELL PER REQUEST, ON PURPOSE. A full score is fourteen cells, each about
/// a second of physics; sent as one request that is fourteen seconds of a phone
/// holding a socket open with nothing on screen moving. Sent as fourteen, every
/// one of them lands as a row the person can watch arrive, a failure names the
/// cell it happened in, and the per-request deadline stays the same size as
/// `/tune`'s. The bench does the arithmetic for one cell and this app does none:
/// `StairsChallenge.Score` counts the answers.
///
/// `/climb` DOES NOT LEAVE THE STAIRS BEHIND IT. The plant contains a bank of
/// fourteen step blocks, and `/climb` scores its cell in an `MjData` OF ITS
/// OWN: it parks that copy's bank below the floor, lifts four of them into
/// place, and its `finally` puts the friction, the collision bits and the
/// blocks back before it answers. The live world is a different `MjData` and is
/// not touched. That is the bench's contract, not this file's, but it is why
/// `/perform`, `/measure` and `/tune` answer exactly what they answered before
/// this endpoint existed — and why the app can offer both on the same bench in
/// the same session.
///
/// THIS SENTENCE USED TO SAY THE BANK WAS "PARKED BELOW THE FLOOR", FULL STOP,
/// and that was true of the climb rig's world and false of the live one. Nothing
/// in the live lane has ever called `clearStairs`, so the world a person drives
/// in boots with all fourteen 200 kg blocks stacked at their compiled `qpos0` —
/// (0, 1.305, 0) — colliding on every tick. `DuckWorld.bareFloorIsAChange` is
/// the consequence of that, said where somebody is about to choose an empty
/// floor.
extension DuckBench {

    // MARK: - one cell of the grid

    /// ONE PERTURBATION OF THE ROBUSTNESS GRID: how far off the target rise
    /// this cell's steps are, how high the duck is dropped in, and what its
    /// footpad friction is multiplied by.
    ///
    /// The names are the harness's own (`climb/robust.mjs`, `PLANTS`, `DHS`,
    /// `EXT_DHS`, `EXT_PLANT`) rather than prettier ones, because the row this
    /// app shows has to be findable in the published results by somebody
    /// reading both.
    public struct Cell: Equatable, Sendable, Identifiable, Codable {

        /// The round-3 nine cells everybody's `k of 9` is quoted against, and
        /// the five the round-4 audit added on top. A count that mixed them
        /// would not be comparable with anything published.
        public enum Tier: String, Equatable, Sendable, Codable {
            case core
            case ext
        }

        /// Metres, added to the requested rise. One of −0.010, −0.005, 0,
        /// +0.005, +0.010.
        public let dh: Double
        /// Metres the duck is dropped from at spawn.
        public let drop: Double
        /// Footpad friction multiplier.
        public let fmul: Double
        public let tier: Tier

        public init(dh: Double, drop: Double, fmul: Double, tier: Tier) {
            self.dh = dh; self.drop = drop; self.fmul = fmul; self.tier = tier
        }

        /// Stable across a re-score, so a progress list can key on it.
        public var id: String { "\(dh)/\(drop)/\(fmul)/\(tier.rawValue)" }

        /// The harness's own label for a cell, at a given rise —
        /// `"60/.120/x1.0"`, the string `r6_judge-results.json` prints.
        public func said(rise: Double) -> String {
            let millimetres = Int(((rise + dh) * 1000).rounded())
            var dropText = String(format: "%.3f", drop)
            if dropText.hasPrefix("0") { dropText.removeFirst() }
            return "\(millimetres)/\(dropText)/x\(String(format: "%.1f", fmul))"
        }

        var wire: HarnessJSON {
            .object([
                .init(key: "dh", value: .number(dh)),
                .init(key: "drop", value: .number(drop)),
                .init(key: "fmul", value: .number(fmul)),
            ])
        }
    }

    // MARK: - asking

    /// Score one cell of one intent.
    ///
    /// `intent` is the harness intent JSON — the bytes of a challenge file, or
    /// what `StairsChallenge.Move.encoded()` writes after an edit. It travels
    /// through `HarnessJSON` rather than `JSONSerialization` for the reason
    /// that type exists: the bench hashes the object it receives, key order
    /// included, and a dictionary has no key order.
    public static func climb(_ address: Address, intent: Data, rise: Double,
                             cell: Cell, tail: String = "policy") throws -> Call {
        let parsed = try HarnessJSON.parse(intent)
        guard case .object = parsed else {
            throw Refusal.malformed("that file is not a harness intent object")
        }
        let body = HarnessJSON.object([
            .init(key: "intent", value: parsed),
            .init(key: "rise", value: .number(rise)),
            .init(key: "cell", value: cell.wire),
            .init(key: "tail", value: .string(tail)),
        ])
        return Call(method: "POST", url: URL(string: "\(address.base)/climb")!,
                    body: body.encoded(.compact))
    }

    public static func climb(_ address: Address, move: StairsChallenge.Move, rise: Double,
                             cell: Cell, tail: String = "policy") throws -> Call {
        try climb(address, intent: move.encoded(), rise: rise, cell: cell, tail: tail)
    }

    /// The cell list itself, so a client never retypes the grid.
    public static func climbGrid(_ address: Address) -> Call {
        Call(method: "GET", url: URL(string: "\(address.base)/climb/grid")!, body: nil)
    }

    // MARK: - what comes back

    /// One scored cell.
    ///
    /// Every field is the bench's, unrounded. THE ROUNDING IS THE DISPLAY'S
    /// JOB AND NOBODY ELSE'S: the parity gate that makes these numbers worth
    /// showing (`sim/climb_parity.mjs`) compares them against `robust.mjs` at
    /// full float digits, and a reader that rounded on the way in would make
    /// that comparison impossible to reproduce from the app.
    public struct Climbed: Equatable, Sendable {
        /// `intentHash` — the identity the leaderboard is keyed by.
        public let hash: String
        /// Metres, the rise this cell was asked for BEFORE `cell.dh`.
        public let rise: Double
        public let cell: Cell
        /// The criterion that counts (`climb/rig3.mjs` line 330).
        public let honest: Bool
        /// `honest` AND still upright for at least 45 of the 50 tail ticks.
        public let stable: Bool
        public let uprightTailTicks: Int
        /// The tail the bench ran, so 45 of 50 is checkable rather than
        /// assumed.
        public let tailTicks: Int
        /// The most feet that rested on a tread at ANY tick — the half of
        /// `reachedFlight` a final `feetOnTread` of 0 hides.
        public let feetOnTreadMax: Int
        /// Millimetres of trunk above the tread at the scored instant.
        public let aboveMillimetres: Double
        public let xMillimetres: Double
        public let dyMillimetres: Double
        public let feetOnTread: Int
        /// The trunk's PEAK height above the tread over the whole episode —
        /// `maxZ − (rise + dh)`. An upper bound on what any landing law could
        /// have turned into a clear, which is what makes `ceilingCore` mean
        /// something.
        public let peakAboveTreadMillimetres: Double
        /// N·m. 0.6405 is the plant's ceiling; at it, a servo is saturated.
        public let maxTorque: Double
        /// Millimetres of interpenetration; negative is into the geometry.
        /// Null from a bench that did not measure it, never zero — zero is a
        /// measurement and this is its absence.
        public let penetrationAtScoreMillimetres: Double?
        public let minPenetrationEpisodeMillimetres: Double?
        public let maxAbsDYMillimetres: Double
        /// The trunk crossed the riser line, or a foot rested on a tread, at
        /// some tick. A cell that did neither earns no upright credit.
        public let reachedFlight: Bool
        /// The intent fell outside its own declared search bounds. An invalid
        /// cell is not a failed cell: it is a file that is not a result.
        public let invalid: Bool
        public let why: String?
        public let plantName: String?
        public let plantDigest: String?
        /// The bench's own sentence for what it scored.
        public let criterion: String
        /// Wall seconds this cell took.
        public let seconds: Double
        /// The bench's answer, verbatim — key order and the exact digits it
        /// wrote. A submission bundle claims to carry the per-cell answers
        /// unrounded, and re-formatting a `Double` on the way out is how that
        /// claim quietly becomes false in the last place. Nil for a row this
        /// app built rather than received.
        public let raw: HarnessJSON?

        public init(hash: String, rise: Double, cell: Cell, honest: Bool, stable: Bool,
                    uprightTailTicks: Int, tailTicks: Int = 50, feetOnTreadMax: Int = 0,
                    aboveMillimetres: Double, xMillimetres: Double,
                    dyMillimetres: Double, feetOnTread: Int,
                    peakAboveTreadMillimetres: Double, maxTorque: Double,
                    penetrationAtScoreMillimetres: Double? = nil,
                    minPenetrationEpisodeMillimetres: Double? = nil,
                    maxAbsDYMillimetres: Double = 0, reachedFlight: Bool = false,
                    invalid: Bool = false, why: String? = nil,
                    plantName: String? = nil, plantDigest: String? = nil,
                    criterion: String = "unstated", seconds: Double = 0,
                    raw: HarnessJSON? = nil) {
            self.hash = hash; self.rise = rise; self.cell = cell
            self.honest = honest; self.stable = stable
            self.uprightTailTicks = uprightTailTicks
            self.tailTicks = tailTicks; self.feetOnTreadMax = feetOnTreadMax
            self.aboveMillimetres = aboveMillimetres; self.xMillimetres = xMillimetres
            self.dyMillimetres = dyMillimetres; self.feetOnTread = feetOnTread
            self.peakAboveTreadMillimetres = peakAboveTreadMillimetres
            self.maxTorque = maxTorque
            self.penetrationAtScoreMillimetres = penetrationAtScoreMillimetres
            self.minPenetrationEpisodeMillimetres = minPenetrationEpisodeMillimetres
            self.maxAbsDYMillimetres = maxAbsDYMillimetres
            self.reachedFlight = reachedFlight
            self.invalid = invalid; self.why = why
            self.plantName = plantName; self.plantDigest = plantDigest
            self.criterion = criterion; self.seconds = seconds
            self.raw = raw
        }

        /// A number exactly as the bench wrote it, when it wrote one.
        public func literal(_ key: String) -> HarnessJSON? {
            guard let value = raw?[key], case .number = value else { return nil }
            return value
        }

        /// Whether the trunk's PEAK ever cleared the 95 mm bar in this cell.
        public var overBar: Bool {
            peakAboveTreadMillimetres > StairsChallenge.barMillimetres
        }
    }

    /// Read one scored cell, or say which bench cannot do this.
    ///
    /// THROUGH `HarnessJSON`, NOT `JSONSerialization`, AND FOR A MEASURED
    /// REASON. `swift-corelibs-foundation`'s JSON number parsing is not
    /// correctly rounded: `116.17658662135791` off the wire comes back as
    /// `116.17658662135796`, one unit in the last place away from the value
    /// the bench computed and from what `Double("116.17658662135791")` gives.
    /// The whole point of these fields is that they are the bench's own
    /// digits — the parity gate compares them against `climb/robust.mjs` at
    /// full float precision, and a submission bundle claims to carry them
    /// unrounded — so the reader that quietly moved the last digit had to go.
    ///
    /// A BENCH WITHOUT `/climb` IS NOT AN ERROR STATE, for the same reason a
    /// bench without `/tune` is not: every shell in this family answers an
    /// unknown path with `{"error": "no /climb here"}`, which is a fact about
    /// the bench. It arrives as `ReadError.bench` carrying the bench's own
    /// words, and `StairsChallenge.noClimbHere(bench:)` is the sentence the
    /// screen shows instead of a failure.
    public static func readClimbed(_ data: Data) throws -> Climbed {
        guard let top = try? HarnessJSON.parse(data), case .object = top else {
            throw ReadError.notJSON
        }
        if let error = top["error"]?.stringValue { throw ReadError.bench(error) }
        guard let hash = top["hash"]?.stringValue, !hash.isEmpty,
              let rise = top["rise"]?.doubleValue,
              let cellObject = top["cell"],
              let dh = cellObject["dh"]?.doubleValue,
              let drop = cellObject["drop"]?.doubleValue,
              let fmul = cellObject["fmul"]?.doubleValue else {
            throw ReadError.empty
        }
        // The tier is the client's own knowledge of the grid — a bench that
        // states it is believed, and one that does not gets it from the
        // pinned grid rather than a guess.
        let tier = (cellObject["tier"]?.stringValue).flatMap(Cell.Tier.init(rawValue:))
            ?? StairsChallenge.Grid.tier(dh: dh, drop: drop, fmul: fmul)
        let cell = Cell(dh: dh, drop: drop, fmul: fmul, tier: tier)
        return Climbed(
            hash: hash,
            rise: rise,
            cell: cell,
            honest: top["honest"]?.boolValue ?? false,
            stable: top["stable"]?.boolValue ?? false,
            uprightTailTicks: Int(top["uprightTailTicks"]?.doubleValue ?? 0),
            tailTicks: Int(top["tailTicks"]?.doubleValue ?? 50),
            feetOnTreadMax: Int(top["feetOnTreadMax"]?.doubleValue ?? 0),
            aboveMillimetres: top["above_mm"]?.doubleValue ?? 0,
            xMillimetres: top["x_mm"]?.doubleValue ?? 0,
            dyMillimetres: top["dy_mm"]?.doubleValue ?? 0,
            feetOnTread: Int(top["feetOnTread"]?.doubleValue ?? 0),
            peakAboveTreadMillimetres: top["peakAboveTread_mm"]?.doubleValue ?? 0,
            maxTorque: top["maxTq"]?.doubleValue ?? 0,
            penetrationAtScoreMillimetres: top["penetrationAtScore_mm"]?.doubleValue,
            minPenetrationEpisodeMillimetres: top["minPenetrationEpisode_mm"]?.doubleValue,
            maxAbsDYMillimetres: top["maxAbsDY_mm"]?.doubleValue ?? 0,
            reachedFlight: top["reachedFlight"]?.boolValue ?? false,
            invalid: top["invalid"]?.boolValue ?? false,
            why: top["why"]?.stringValue,
            plantName: top["plantName"]?.stringValue,
            plantDigest: top["plantDigest"]?.stringValue,
            criterion: top["criterion"]?.stringValue ?? "unstated",
            seconds: top["seconds"]?.doubleValue ?? 0,
            raw: top)
    }

    /// What a bench says about the stairs challenge before anything is scored.
    ///
    /// IT CARRIES `climbable` FOR ONE REASON. A bench can hold a plant with
    /// no step bank, or a scene whose actuators are not in joint order, and
    /// still answer the grid — the fourteen cells are a constant. A client
    /// that read only the cells would draw fourteen rows and a Score button
    /// on a bench that is going to refuse every one of them.
    public struct ClimbGrid: Equatable, Sendable {
        public let cells: [Cell]
        public let climbable: Bool
        /// Why not, in the bench's own words, when it is not.
        public let why: String?
        public let bar: Int
        public let uprightTailMinimum: Int
        /// The bench's own sentence for what `honest` and `stable` mean.
        public let criterion: String?
        public let plantName: String?
        public let plantDigest: String?

        public init(cells: [Cell], climbable: Bool = true, why: String? = nil,
                    bar: Int = StairsChallenge.bar,
                    uprightTailMinimum: Int = StairsChallenge.uprightTailMinimum,
                    criterion: String? = nil,
                    plantName: String? = nil, plantDigest: String? = nil) {
            self.cells = cells; self.climbable = climbable; self.why = why
            self.bar = bar; self.uprightTailMinimum = uprightTailMinimum
            self.criterion = criterion
            self.plantName = plantName; self.plantDigest = plantDigest
        }
    }

    /// Read what `/climb/grid` answers.
    ///
    /// A bare array of cells is accepted as well as the full object, because a
    /// bench that answers the shorter form is not wrong and a reader that
    /// refused it would send the app to its pinned fallback over punctuation.
    public static func readClimbGrid(_ data: Data) throws -> ClimbGrid {
        guard let top = try? HarnessJSON.parse(data) else { throw ReadError.notJSON }
        var rows: [HarnessJSON] = []
        switch top {
        case .object:
            if let error = top["error"]?.stringValue { throw ReadError.bench(error) }
            rows = top["cells"]?.arrayValue ?? []
        case .array(let items):
            rows = items
        default:
            throw ReadError.notJSON
        }
        let cells: [Cell] = rows.compactMap { row in
            guard let dh = row["dh"]?.doubleValue, let drop = row["drop"]?.doubleValue,
                  let fmul = row["fmul"]?.doubleValue else { return nil }
            let tier = (row["tier"]?.stringValue).flatMap(Cell.Tier.init(rawValue:))
                ?? StairsChallenge.Grid.tier(dh: dh, drop: drop, fmul: fmul)
            return Cell(dh: dh, drop: drop, fmul: fmul, tier: tier)
        }
        guard !cells.isEmpty else { throw ReadError.empty }
        return ClimbGrid(
            cells: cells,
            climbable: top["climbable"]?.boolValue ?? true,
            why: top["why"]?.stringValue,
            bar: Int(top["bar"]?.doubleValue ?? Double(StairsChallenge.bar)),
            uprightTailMinimum: Int(top["uprightTailMin"]?.doubleValue
                                    ?? Double(StairsChallenge.uprightTailMinimum)),
            criterion: top["criterion"]?.stringValue,
            plantName: top["plantName"]?.stringValue,
            plantDigest: top["plantDigest"]?.stringValue)
    }

    /// JSON writes `0` for a whole number, and `as? Double` on that is nil.
    /// Every rounded value in a `/climb` answer would read as absent.
    static func number(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? NSNumber { return value.doubleValue }
        return nil
    }
}
