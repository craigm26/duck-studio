import Foundation

/// The two calls the ball challenge adds to a bench, and what comes back.
///
/// ONE CELL PER REQUEST, for the same reason `/climb` is one cell per request:
/// fourteen cells sent as one request is fourteen seconds of a phone holding a
/// socket open with nothing on screen moving, and a failure inside it names
/// nothing. Sent as fourteen, every one lands as a row a person can watch
/// arrive, a failure names the cell it happened in, and the per-request
/// deadline stays the size of `/tune`'s.
///
/// `/chase` DOES NOT LEAVE THE BALL WHERE IT PUT IT. The plant the bench holds
/// already contains a free ball; scoring a cell places it at a bearing and
/// range relative to the settled duck and then puts everything back. That is
/// the bench's contract rather than this file's, and it is why `/perform`,
/// `/measure`, `/tune`, `/ball` and `/state` answer exactly what they answered
/// before this endpoint existed.
///
/// THE BENCH DOES ONE CELL'S ARITHMETIC AND THIS APP DOES NONE.
/// `BallChallenge.Score` counts answers; every number below is the bench's
/// own, unrounded, because the parity gate that makes them worth showing
/// (`sim/chase_parity.mjs`) compares them against `chase_robust` at full float
/// digits and a reader that rounded on the way in would make that comparison
/// impossible to reproduce from the app.
extension DuckBench {

    // A policy entrant's command schedule is `DuckBench.Step`, the same type
    // `/record`, `/measure` and `/tune` already speak — one schedule shape,
    // four endpoints, rather than a fifth spelling of [t, {vx, vy, vyaw}].

    // MARK: - one cell of the grid

    /// ONE PLACEMENT OF THE BALL AND ONE SETTING OF THE PLANT: where the ball
    /// is put relative to the settled duck's heading, how high the duck is
    /// dropped in, and what its footpad friction is multiplied by.
    ///
    /// `bearing` IS IN DEGREES AND POSITIVE IS LEFT — the convention `POST
    /// /ball`, duckvision and the robot all use, so a trial reads the same way
    /// the detector reports. `drop` and `fmul` are the same two knobs
    /// `climb_score.mjs` perturbs, with the same numbers, so "the slippery
    /// plant" means the same thing in both challenges.
    public struct ChaseCell: Equatable, Sendable, Identifiable, Codable {

        /// The nine core cells every published number is quoted against, and
        /// the five extended ones. A count that mixed them would not be
        /// comparable with anything published.
        public enum Tier: String, Equatable, Sendable, Codable {
            case core
            case ext
        }

        /// Degrees off the duck's heading. Positive is LEFT.
        public let bearing: Double
        /// Metres from the duck's root to the ball's centre, after the settle.
        public let range: Double
        /// Metres the duck is dropped from at spawn.
        public let drop: Double
        /// Footpad friction multiplier.
        public let fmul: Double
        public let tier: Tier

        public init(bearing: Double, range: Double, drop: Double, fmul: Double, tier: Tier) {
            self.bearing = bearing; self.range = range
            self.drop = drop; self.fmul = fmul; self.tier = tier
        }

        /// Stable across a re-score, so a progress list can key on it.
        public var id: String { "\(bearing)/\(range)/\(drop)/\(fmul)/\(tier.rawValue)" }

        /// The harness's own label for a cell — `"+20°/0.70/.120/x1.0"`.
        public var said: String {
            var dropText = String(format: "%.3f", drop)
            if dropText.hasPrefix("0") { dropText.removeFirst() }
            return "\(BallChallenge.bearingSaid(bearing))/\(String(format: "%.2f", range))/"
                 + "\(dropText)/x\(String(format: "%.1f", fmul))"
        }

        /// The same cell in words, for a row that has room for them.
        public var longSaid: String {
            "ball \(BallChallenge.bearingSaid(bearing)) at \(BallChallenge.rangeSaid(range)), "
          + "drop \(String(format: "%.3f", drop)), friction ×\(String(format: "%.1f", fmul))"
        }

        var wire: HarnessJSON {
            .object([
                .init(key: "bearing", value: .number(bearing)),
                .init(key: "range", value: .number(range)),
                .init(key: "drop", value: .number(drop)),
                .init(key: "fmul", value: .number(fmul)),
            ])
        }
    }

    // MARK: - asking

    /// Score one cell of one entrant.
    ///
    /// `entrant` IS THE FILE, VERBATIM. It travels through `HarnessJSON`
    /// rather than `JSONSerialization` for the reason that type exists: the
    /// bench hashes the entrant object it receives, key order and digits
    /// included, and a dictionary has no key order. Unknown keys are carried
    /// across and hashed, never stripped — a file that also carries stairs
    /// fields is a different entrant, not a silently equivalent one.
    ///
    /// `seconds` TRAVELS AT THE TOP LEVEL as well as inside the entrant,
    /// because it is what the bench's deadline is computed from and what the
    /// answer echoes back.
    public static func chase(_ address: Address, entrant: Data, seconds: Double,
                             cell: ChaseCell, tail: String = "policy") throws -> Call {
        let parsed = try HarnessJSON.parse(entrant)
        guard case .object = parsed else {
            throw Refusal.malformed("that file is not a ball-challenge entrant object")
        }
        let body = HarnessJSON.object([
            .init(key: "entrant", value: parsed),
            .init(key: "seconds", value: .number(seconds)),
            .init(key: "cell", value: cell.wire),
            .init(key: "tail", value: .string(tail)),
        ])
        return Call(method: "POST", url: URL(string: "\(address.base)/chase")!,
                    body: body.encoded(.compact))
    }

    /// The same, from a parsed entrant — the seconds come from the entrant so
    /// they cannot disagree with the file that declared them.
    public static func chase(_ address: Address, entrant: BallChallenge.Entrant,
                             cell: ChaseCell, tail: String = "policy") throws -> Call {
        try chase(address, entrant: entrant.encoded(), seconds: entrant.seconds,
                  cell: cell, tail: tail)
    }

    /// The cell list itself, so a client never retypes the grid.
    public static func chaseGrid(_ address: Address) -> Call {
        Call(method: "GET", url: URL(string: "\(address.base)/chase/grid")!, body: nil)
    }

    // MARK: - what comes back

    /// One of the nine weighted reward terms the bench computed.
    ///
    /// THE WEIGHT TRAVELS WITH THE VALUE. A term's value means nothing without
    /// the weight the config gives it — `ball_forward_velocity` at +12.0 and
    /// `action_rate_l2` at −1.0 move a total in opposite directions — and a
    /// screen that showed nine unweighted numbers would be showing nine
    /// numbers nobody could add up.
    public struct RewardTerm: Equatable, Sendable, Identifiable {
        public let term: String
        public let weight: Double
        /// The per-tick mean over the DRIVEN SPAN — the entrant's own seconds,
        /// not the 50-tick tail. The tail is the bench's standing test, and
        /// averaging over it would put the bench's tail length into Pollen's
        /// reward.
        public let value: Double
        /// `action_rate_l2` only: the stage-0 weight, published beside the
        /// ramp end the trained policy actually lived under.
        public let weightStage0: Double?
        /// The config and mjlab lines this term was transcribed from. NOT a
        /// decoration: it is what makes the weight checkable against the file
        /// rather than believed.
        public let reference: String?
        public let formula: String?
        /// `action_rate_l2` only: which action the rate is over, "policy raw
        /// output" or "keyframe pose target". Nil on every other term.
        public let actionRateSource: String?

        public init(term: String, weight: Double, value: Double,
                    weightStage0: Double? = nil, reference: String? = nil,
                    formula: String? = nil, actionRateSource: String? = nil) {
            self.term = term; self.weight = weight; self.value = value
            self.weightStage0 = weightStage0; self.reference = reference
            self.formula = formula; self.actionRateSource = actionRateSource
        }

        public var id: String { term }

        /// Value × weight. The bench computes the cell; this is the one
        /// multiplication a display needs and it is done here rather than in
        /// the app, which does no arithmetic.
        public var weighted: Double { value * weight }

        public var weightSaid: String {
            weight > 0 ? "+\(Self.trim(weight))" : Self.trim(weight)
        }

        static func trim(_ value: Double) -> String {
            value == value.rounded() ? "\(Int(value))" : "\(value)"
        }
    }

    /// A term the bench would not compute, by name and with the reason.
    ///
    /// REFUSED, NEVER DROPPED. A reward table with three terms quietly missing
    /// looks like a reward table; a reward table that names what it could not
    /// compute and why is a measurement. The reasons are the bench's own
    /// words, which is what makes them checkable against the config.
    public struct RefusedTerm: Equatable, Sendable, Identifiable {
        public let term: String
        public let weight: Double
        public let reason: String

        public init(term: String, weight: Double, reason: String) {
            self.term = term; self.weight = weight; self.reason = reason
        }

        public var id: String { term }
    }

    /// One scored cell.
    ///
    /// THE EIGHT PLAIN FACTS ARE THE POINT and the nine terms are the context.
    /// `chased` is three of the facts, said as a sentence a person can watch
    /// happen; the terms are the reward the policies were trained on, reported
    /// so an edit can be watched moving them, and they are not the verdict.
    public struct Chased: Equatable, Sendable {
        /// sha256 of the normalised entrant — the identity the leaderboard is
        /// keyed by.
        public let hash: String
        public let cell: ChaseCell
        /// The episode length this cell was run for.
        public let seconds: Double

        // The eight plain facts, in the contract's order.

        /// Ball net displacement projected onto the duck's INITIAL heading in
        /// the world frame — the same frozen vector the reward's `kick_dir`
        /// uses. SIGNED: a ball pushed backwards scores negative.
        public let ballTravelMillimetres: Double
        /// Unsigned ‖end − start‖ in the plane. Travel and net differ exactly
        /// when the ball went sideways, which is the case worth seeing.
        public let ballNetMillimetres: Double
        /// Minimum over ticks of the smallest distance between any duck geom
        /// and the ball. Negative means interpenetration.
        public let closestMillimetres: Double
        /// Duck root to ball centre, in the plane, at the last tick.
        public let finalMillimetres: Double
        /// Any duck geometry within 3 mm of the ball at any tick.
        public let touched: Bool
        public let ballPeakSpeed: Double
        /// Upright at the last tick.
        public let upright: Bool
        public let uprightTailTicks: Int
        /// The tail the bench ran, so 45 of 50 is checkable rather than
        /// assumed.
        public let tailTicks: Int

        /// touched AND ballTravel ≥ 100 mm AND upright at the end.
        public let chased: Bool
        /// chased AND upright for at least 45 of the 50 tail ticks.
        public let stable: Bool

        public let terms: [RewardTerm]
        public let refused: [RefusedTerm]

        /// The entrant fell outside something the bench would score. An
        /// invalid cell is not a failed cell: it is a run that is not a
        /// result.
        public let invalid: Bool
        public let why: String?
        public let plantName: String?
        public let plantDigest: String?
        /// The bench's own sentence for what it scored.
        public let criterion: String
        /// Which action `action_rate_l2` was differenced over in this cell.
        public let actionRateSource: String?
        /// Ticks the entrant was driven for, and the ticks the action rate was
        /// averaged over — one fewer, because a rate needs two actions.
        public let drivenTicks: Int
        public let rateTicks: Int
        /// The twelve-character form of `hash`, exactly as the leaderboard
        /// prints it. The bench answers both; a client that truncated the long
        /// one itself would be inventing the identity rather than reading it.
        public let shortHash: String
        /// `"move"` or `"policy"`, and the network for a policy.
        public let kind: String?
        public let policy: String?
        /// Wall seconds this cell took.
        public let elapsedSeconds: Double
        /// The bench's answer, verbatim — key order and the exact digits it
        /// wrote. Nil for a row this app built rather than received.
        public let raw: HarnessJSON?

        public init(hash: String, cell: ChaseCell, seconds: Double,
                    ballTravelMillimetres: Double, ballNetMillimetres: Double,
                    closestMillimetres: Double, finalMillimetres: Double,
                    touched: Bool, ballPeakSpeed: Double, upright: Bool,
                    uprightTailTicks: Int, tailTicks: Int = BallChallenge.tailTicks,
                    chased: Bool, stable: Bool,
                    terms: [RewardTerm] = [], refused: [RefusedTerm] = [],
                    actionRateSource: String? = nil,
                    drivenTicks: Int = 0, rateTicks: Int = 0,
                    shortHash: String? = nil, kind: String? = nil, policy: String? = nil,
                    invalid: Bool = false, why: String? = nil,
                    plantName: String? = nil, plantDigest: String? = nil,
                    criterion: String = "unstated", elapsedSeconds: Double = 0,
                    raw: HarnessJSON? = nil) {
            self.hash = hash; self.cell = cell; self.seconds = seconds
            self.ballTravelMillimetres = ballTravelMillimetres
            self.ballNetMillimetres = ballNetMillimetres
            self.closestMillimetres = closestMillimetres
            self.finalMillimetres = finalMillimetres
            self.touched = touched; self.ballPeakSpeed = ballPeakSpeed
            self.upright = upright; self.uprightTailTicks = uprightTailTicks
            self.tailTicks = tailTicks
            self.chased = chased; self.stable = stable
            self.terms = terms; self.refused = refused
            self.actionRateSource = actionRateSource
            self.drivenTicks = drivenTicks; self.rateTicks = rateTicks
            self.shortHash = shortHash ?? String(hash.prefix(DuckBench.digestShown))
            self.kind = kind; self.policy = policy
            self.invalid = invalid; self.why = why
            self.plantName = plantName; self.plantDigest = plantDigest
            self.criterion = criterion; self.elapsedSeconds = elapsedSeconds
            self.raw = raw
        }

        /// A number exactly as the bench wrote it, when it wrote one.
        public func literal(_ key: String) -> HarnessJSON? {
            guard let value = raw?[key], case .number = value else { return nil }
            return value
        }

        /// Why this cell is not a chase, in the criterion's own order — the
        /// three clauses, so a person can see WHICH one failed rather than
        /// only that something did.
        public var whyNotChased: [String] {
            guard !chased else { return [] }
            var out: [String] = []
            if !touched {
                out.append("Never touched the ball — closest "
                         + "\(Self.round(closestMillimetres)) mm, and the bar is "
                         + "\(Self.round(BallChallenge.touchMillimetres)) mm.")
            }
            if ballTravelMillimetres < BallChallenge.travelMinimumMillimetres {
                out.append("The ball finished \(Self.round(ballTravelMillimetres)) mm along the "
                         + "duck's initial heading, and the bar is "
                         + "\(Self.round(BallChallenge.travelMinimumMillimetres)) mm.")
            }
            if !upright {
                out.append("The duck was not upright at the end of the episode.")
            }
            return out
        }

        static func round(_ value: Double) -> String { String(format: "%.1f", value) }
    }

    /// Read one scored cell, or say which bench cannot do this.
    ///
    /// THROUGH `HarnessJSON`, NOT `JSONSerialization`, for the measured reason
    /// `readClimbed` documents: `swift-corelibs-foundation`'s JSON number
    /// parsing is not correctly rounded, and the whole point of these fields
    /// is that they are the bench's own digits.
    ///
    /// A BENCH WITHOUT `/chase` IS NOT AN ERROR STATE. Every shell in this
    /// family answers an unknown path with `{"error": "no /chase here"}`,
    /// which is a fact about the bench: it arrives as `ReadError.bench`
    /// carrying the bench's own words, and `BallChallenge.noChaseHere(bench:)`
    /// is the sentence the screen shows instead of a failure.
    public static func readChased(_ data: Data) throws -> Chased {
        guard let top = try? HarnessJSON.parse(data), case .object = top else {
            throw ReadError.notJSON
        }
        if let error = top["error"]?.stringValue { throw ReadError.bench(error) }
        guard let hash = top["hash"]?.stringValue, !hash.isEmpty,
              let cellObject = top["cell"],
              let bearing = cellObject["bearing"]?.doubleValue,
              let range = cellObject["range"]?.doubleValue,
              let drop = cellObject["drop"]?.doubleValue,
              let fmul = cellObject["fmul"]?.doubleValue else {
            throw ReadError.empty
        }
        // The tier is the client's own knowledge of the grid — a bench that
        // states it is believed, and one that does not gets it from the pinned
        // grid rather than a guess.
        let tier = (cellObject["tier"]?.stringValue).flatMap(ChaseCell.Tier.init(rawValue:))
            ?? BallChallenge.Grid.tier(bearing: bearing, range: range, drop: drop, fmul: fmul)
        let cell = ChaseCell(bearing: bearing, range: range, drop: drop, fmul: fmul, tier: tier)

        let terms: [RewardTerm] = (top["terms"]?.arrayValue ?? []).compactMap { row in
            guard let term = row["term"]?.stringValue,
                  let value = row["value"]?.doubleValue else { return nil }
            // `source` on a term is the CONFIG LINE it was transcribed from,
            // and `action_rate_l2_source` is which action the rate is over.
            // Reading one as the other would print "cfg 301 (stage-0 −0.1)"
            // where a sentence about the entrant's actions belongs.
            return RewardTerm(term: term, weight: row["weight"]?.doubleValue ?? 0, value: value,
                              weightStage0: row["weightStage0"]?.doubleValue,
                              reference: row["source"]?.stringValue,
                              formula: row["formula"]?.stringValue,
                              actionRateSource: row["action_rate_l2_source"]?.stringValue)
        }
        let refused: [RefusedTerm] = (top["refused"]?.arrayValue ?? []).compactMap { row in
            guard let term = row["term"]?.stringValue else { return nil }
            return RefusedTerm(term: term, weight: row["weight"]?.doubleValue ?? 0,
                               reason: row["reason"]?.stringValue ?? "no reason given")
        }

        return Chased(
            hash: hash,
            cell: cell,
            seconds: top["seconds"]?.doubleValue ?? 0,
            ballTravelMillimetres: top["ballTravel_mm"]?.doubleValue ?? 0,
            ballNetMillimetres: top["ballNet_mm"]?.doubleValue ?? 0,
            closestMillimetres: top["closest_mm"]?.doubleValue ?? 0,
            finalMillimetres: top["final_mm"]?.doubleValue ?? 0,
            touched: top["touched"]?.boolValue ?? false,
            ballPeakSpeed: top["ballPeakSpeed_mps"]?.doubleValue ?? 0,
            upright: top["upright"]?.boolValue ?? false,
            uprightTailTicks: Int(top["uprightTailTicks"]?.doubleValue ?? 0),
            tailTicks: Int(top["tailTicks"]?.doubleValue ?? Double(BallChallenge.tailTicks)),
            chased: top["chased"]?.boolValue ?? false,
            stable: top["stable"]?.boolValue ?? false,
            terms: terms,
            refused: refused,
            actionRateSource: top["actionRateSource"]?.stringValue
                ?? terms.first { $0.term == "action_rate_l2" }?.actionRateSource,
            drivenTicks: Int(top["drivenTicks"]?.doubleValue ?? 0),
            rateTicks: Int(top["rateTicks"]?.doubleValue ?? 0),
            shortHash: top["entrant"]?.stringValue,
            kind: top["kind"]?.stringValue,
            policy: top["policy"]?.stringValue,
            invalid: top["invalid"]?.boolValue ?? false,
            why: top["why"]?.stringValue,
            plantName: top["plantName"]?.stringValue,
            plantDigest: top["plantDigest"]?.stringValue,
            criterion: top["criterion"]?.stringValue ?? "unstated",
            elapsedSeconds: top["elapsedSeconds"]?.doubleValue ?? 0,
            raw: top)
    }

    /// What a bench says about the ball challenge before anything is scored.
    ///
    /// IT CARRIES `chaseable` FOR ONE REASON, the same one `ClimbGrid` carries
    /// `climbable` for: a bench can hold a plant with no free ball and still
    /// answer the grid, because the fourteen cells are a constant. A client
    /// that read only the cells would draw fourteen rows and a Score button on
    /// a bench that is going to refuse every one of them.
    public struct ChaseGrid: Equatable, Sendable {
        public let cells: [ChaseCell]
        public let chaseable: Bool
        /// Why not, in the bench's own words, when it is not.
        public let why: String?
        public let uprightTailMinimum: Int
        public let tailTicks: Int
        public let touchMillimetres: Double
        public let travelMinimumMillimetres: Double
        /// How many of the cells are core and how many the whole grid is, as
        /// the bench counts them.
        public let coreCount: Int
        /// The ball caveat in the bench's own words: Pollen's ball is not this
        /// ball.
        public let caveat: String?
        /// The bench's own sentence for what `chased` and `stable` mean.
        public let criterion: String?
        public let plantName: String?
        public let plantDigest: String?

        public init(cells: [ChaseCell], chaseable: Bool = true, why: String? = nil,
                    uprightTailMinimum: Int = BallChallenge.uprightTailMinimum,
                    tailTicks: Int = BallChallenge.tailTicks,
                    touchMillimetres: Double = BallChallenge.touchMillimetres,
                    travelMinimumMillimetres: Double = BallChallenge.travelMinimumMillimetres,
                    coreCount: Int = BallChallenge.Grid.coreCount,
                    caveat: String? = nil,
                    criterion: String? = nil,
                    plantName: String? = nil, plantDigest: String? = nil) {
            self.cells = cells; self.chaseable = chaseable; self.why = why
            self.uprightTailMinimum = uprightTailMinimum
            self.tailTicks = tailTicks
            self.touchMillimetres = touchMillimetres
            self.travelMinimumMillimetres = travelMinimumMillimetres
            self.coreCount = coreCount
            self.caveat = caveat
            self.criterion = criterion
            self.plantName = plantName; self.plantDigest = plantDigest
        }
    }

    /// Read what `/chase/grid` answers.
    ///
    /// A bare array of cells is accepted as well as the full object, for the
    /// same reason `readClimbGrid` accepts one: a bench that answers the
    /// shorter form is not wrong, and a reader that refused it would send the
    /// app to its pinned fallback over punctuation.
    public static func readChaseGrid(_ data: Data) throws -> ChaseGrid {
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
        let cells: [ChaseCell] = rows.compactMap { row in
            guard let bearing = row["bearing"]?.doubleValue,
                  let range = row["range"]?.doubleValue,
                  let drop = row["drop"]?.doubleValue,
                  let fmul = row["fmul"]?.doubleValue else { return nil }
            let tier = (row["tier"]?.stringValue).flatMap(ChaseCell.Tier.init(rawValue:))
                ?? BallChallenge.Grid.tier(bearing: bearing, range: range, drop: drop, fmul: fmul)
            return ChaseCell(bearing: bearing, range: range, drop: drop, fmul: fmul, tier: tier)
        }
        guard !cells.isEmpty else { throw ReadError.empty }
        return ChaseGrid(
            cells: cells,
            chaseable: top["chaseable"]?.boolValue ?? true,
            why: top["why"]?.stringValue,
            uprightTailMinimum: Int(top["uprightTailMin"]?.doubleValue
                                    ?? Double(BallChallenge.uprightTailMinimum)),
            tailTicks: Int(top["tailTicks"]?.doubleValue ?? Double(BallChallenge.tailTicks)),
            touchMillimetres: top["touchMm"]?.doubleValue ?? BallChallenge.touchMillimetres,
            travelMinimumMillimetres: top["travelMinMm"]?.doubleValue
                ?? BallChallenge.travelMinimumMillimetres,
            coreCount: Int(top["nCore"]?.doubleValue ?? Double(BallChallenge.Grid.coreCount)),
            caveat: top["caveat"]?.stringValue,
            criterion: top["criterion"]?.stringValue,
            plantName: top["plantName"]?.stringValue,
            plantDigest: top["plantDigest"]?.stringValue)
    }
}
