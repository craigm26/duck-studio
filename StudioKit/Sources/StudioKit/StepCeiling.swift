import Foundation

/// What the robot has been measured to climb, with the measurement attached.
///
/// A NUMBER THAT SHIPS WITHOUT ITS COUNT IS A CLAIM, NOT A MEASUREMENT. The
/// app once carried `measuredStepCeiling = 0.010` and printed "the robot has
/// been measured at 10 mm" under every staircase somebody drew. Then it
/// carried "0 of 54 audited replays cleared anything from 20 to 180 mm". On
/// 2026-09-02 that second sentence turned out to rest on a broken instrument:
/// the harness's four-step flight is built from 200 mm-tall blocks whose top
/// is the tread, so at any rise under 200 mm adjacent blocks interpenetrate,
/// and because they collide with each other and sit on frictionless slides
/// the solver shoves them apart. Below about 150 mm a duck simply STANDING on
/// the first tread is thrown to the floor within ten control ticks. Every
/// replay in that audit was scored on that flight, so below 150 mm it says
/// nothing about climbing at all. That sentence is gone.
///
/// WHAT IS KNOWN NOW, after six rounds and roughly 55,000 searched attempts,
/// each claim re-scored from its saved file by an adversarial audit
/// (duck-sounds/climb/r4_judge-results.json) on a robustness grid — the rise
/// 10 mm either side crossed with three spawn-height and foot-friction
/// plants, nine cells per candidate: the tallest step the duck can get onto
/// is UNRELIABLE AT EVERY HEIGHT. The best open-loop move, a beak-strut vault
/// (beak planted on the tread, neck locked as a strut, hips extend, the trunk
/// pivots over the head, the feet land on the tread), clears 2 of 9 cells at
/// 40 mm, 2 of 9 at 50, 4 of 9 at 60, 2 of 9 at 70 and 1 of 9 at 80 — and the
/// 60, 70 and 80 mm figures are ONE vector scored at three heights — and 0 of
/// 9 at 90 mm or taller, against 9 of 9 for a duck simply placed on the tread
/// and 0 of 9 for doing nothing on the same plant. Ten of those eleven clears
/// are still upright fifty ticks later. The clears are isolated points, not a
/// basin: one control tick of shift in the landing takes the 60 mm move from
/// 4 of 9 to 1 of 9, and a 5 mm change of rise either side of 60 reads no.
/// Above 80 mm the ceiling is a lift budget, measured from two directions:
/// everything tried buys about 38 mm of trunk lift where the criterion needs
/// 59 mm at 80 and 99 mm at 120, with every servo saturated at the plant's
/// 0.6405 N·m in every row. No cheat was found in any clear.
///
/// AND THE SEARCH IS FINISHED AT THIS SCALE, against a bar of 7 of 9 stable
/// cells at 60 mm. Round five tried a landing servoed onto the tread from
/// measured trunk state every tick instead of a single throw; every servoed
/// move cleared 0 of 9 stably. Round six searched the trunk's peak height
/// alone, with no landing in the objective, over 394 distinct launches: the
/// trunk gets past the 95 mm bar in at most 5 of 9 cells, and the cells
/// trade rather than accumulate. Because a clear needs the trunk above the
/// bar, that ceiling bounds every landing law there could be, so 7 was never
/// reachable. The limit is the strut, measured on a torque trace that
/// reproduces the scorer exactly: at the pose the vault depends on, the
/// neck's lever to the beak is 88 to 90 mm, where the servo's 0.6405 N·m
/// yields 7.16 to 7.34 N against a 7.23 N body weight. A shorter lever is
/// as good as a stronger motor, and either is a change to the robot, not
/// to the search.
///
/// AND BELOW ABOUT 11 mm THE CHECK CANNOT SEE A STEP AT ALL. The criterion
/// counts a foot as "on the tread" when it is within 5 mm of the tread's
/// height, and a foot resting on the floor has its geometry centred 5.5 mm
/// up — so for any rise under 10.5 mm a foot on the FLOOR passes the height
/// test. This type refuses to report a number under that floor rather than a
/// flattering one.
///
/// Pollen's own training config caps its stair terrain at 15 mm with the
/// reason written beside it — "the robot can only lift its feet ~1-2 cm" —
/// and the policies the robot loads are deliberately blind to terrain.
public struct StepCeiling: Equatable, Sendable {
    /// One rise on the robustness grid: how many of its cells the best
    /// distinct move cleared.
    public struct Attempt: Equatable, Sendable {
        public let rise: Double
        public let cleared: Int
        public let of: Int
        public init(rise: Double, cleared: Int, of: Int) {
            self.rise = rise; self.cleared = cleared; self.of = of
        }
    }

    /// The tallest rise anything cleared RELIABLY (at least `reliableCleared`
    /// of a rise's cells). Zero: nothing has.
    public let metres: Double
    /// The best move's count at every rise it cleared any cell of, ascending.
    public let attempts: [Attempt]
    /// The rise from which the figures are ONE vector scored at several
    /// heights, not several moves. Zero: every rise is its own move.
    public let oneVectorFrom: Double
    /// How many of the clears were still upright fifty ticks after the move
    /// ended, of how many clears.
    public let stableClears: Int
    public let clearsInAll: Int
    /// Cells of nine a move must clear before a rise counts as climbable.
    public let reliableCleared: Int
    /// The band verdicts after the last round, in the audit's own words.
    public let bandVerdict: String
    /// Rises below this the criterion cannot resolve; no number is reported
    /// for them, in either direction.
    public let resolvableAbove: Double
    /// The rise below which the flight AS IT WAS threw a standing duck off the
    /// tread, so no result on it below here was a result about climbing.
    public let brokenFlightSoundAbove: Double
    /// Searched attempts across every round, to the nearest thousand.
    public let episodes: Int
    public let rounds: Int
    public let move: String
    public let flight: String
    public let grid: String
    public let criterion: String
    public let evidence: String
    /// ISO date of the audit. A string, because the kit reads no clock.
    public let measuredOn: String
    /// The rise the scene editor starts a staircase at and adds a step by. It
    /// sits UNDER the resolvable floor on purpose: the editor's flag stays
    /// quiet there not because 10 mm is known to be climbable, but because
    /// nothing is known about it either way.
    public let editorRise: Double

    public init(metres: Double, attempts: [Attempt], oneVectorFrom: Double = 0,
                stableClears: Int = 0, clearsInAll: Int = 0,
                reliableCleared: Int, bandVerdict: String = "", resolvableAbove: Double,
                brokenFlightSoundAbove: Double, episodes: Int, rounds: Int, move: String, flight: String,
                grid: String, criterion: String, evidence: String, measuredOn: String, editorRise: Double) {
        self.metres = metres
        self.attempts = attempts
        self.oneVectorFrom = oneVectorFrom
        self.stableClears = stableClears
        self.clearsInAll = clearsInAll
        self.reliableCleared = reliableCleared
        self.bandVerdict = bandVerdict
        self.resolvableAbove = resolvableAbove
        self.brokenFlightSoundAbove = brokenFlightSoundAbove
        self.episodes = episodes
        self.rounds = rounds
        self.move = move
        self.flight = flight
        self.grid = grid
        self.criterion = criterion
        self.evidence = evidence
        self.measuredOn = measuredOn
        self.editorRise = editorRise
    }

    /// The measurement this app ships with.
    public static let current = StepCeiling(
        metres: 0,
        attempts: [Attempt(rise: 0.040, cleared: 2, of: 9), Attempt(rise: 0.050, cleared: 2, of: 9),
                   Attempt(rise: 0.060, cleared: 4, of: 9), Attempt(rise: 0.070, cleared: 2, of: 9),
                   Attempt(rise: 0.080, cleared: 1, of: 9)],
        oneVectorFrom: 0.060,
        stableClears: 10,
        clearsInAll: 11,
        reliableCleared: 7,
        bandVerdict: "The search is finished at this scale, against a bar of 7 of 9 stable cells at "
                   + "60 mm: a landing servoed from measured trunk state cleared 0 of 9 stably, and a "
                   + "search of the trunk's peak height alone over 394 distinct launches gets it past "
                   + "the 95 mm bar in at most 5 of 9 cells, which bounds every way of landing. The "
                   + "limit is the strut: at the pose the vault depends on, the neck's lever to the "
                   + "beak is about 89 mm, where the servo's 0.6405 N·m yields 7.2 N against a 7.23 N "
                   + "body weight. Above 80 mm the lift budget is about 38 mm where 59 to 99 mm are "
                   + "needed. What is left is a shorter lever or a stronger neck servo, or a move "
                   + "that does not ask the duck to lift its own trunk unaided: a second duck, a "
                   + "wall or rail to react against, a lever or ramp placed first.",
        resolvableAbove: 0.011,
        brokenFlightSoundAbove: 0.150,
        episodes: 55_000,
        rounds: 6,
        move: "a beak-strut vault",
        flight: "the simulator's four-step staircase, repaired on 2026-09-02 so its blocks stop "
              + "colliding with one another",
        grid: "the rise 10 mm either side crossed with three spawn-height and foot-friction plants",
        criterion: "upright, within the 340 mm-wide flight, the trunk past the riser face and more than "
                 + "95 mm above the tread, both feet resting on the tread past that same line, "
                 + "scored a second after the move ends",
        evidence: "duck-sounds climb/r6_judge-results.json",
        measuredOn: "2026-09-02",
        editorRise: 0.010)

    /// The tallest rise any cell was ever cleared at. Zero: none.
    public var tallestAnyCell: Double { attempts.map(\.rise).max() ?? 0 }

    /// Whether the check can say anything about a rise this small.
    public func canResolve(rise: Double) -> Bool { rise >= resolvableAbove - 1e-9 }

    /// The grid row for this exact rise, to the millimetre.
    public func attempt(at rise: Double) -> Attempt? {
        attempts.first { abs($0.rise - rise) < 0.0005 }
    }

    /// "40 mm in 2 of 9, 50 mm in 2 of 9, 60 mm in 4 of 9, 70 mm in 2 of 9
    /// and 80 mm in 1 of 9".
    private var attemptList: String {
        let words = attempts.map { String(format: "%.0f mm in %d of %d", $0.rise * 1000, $0.cleared, $0.of) }
        switch words.count {
        case 0: return "nothing"
        case 1: return words[0]
        default: return words.dropLast().joined(separator: ", ") + " and " + words[words.count - 1]
        }
    }

    /// "the 60, 70 and 80 mm figures are one move scored at three heights",
    /// or nothing when every rise is its own move.
    private var oneVectorClause: String {
        guard oneVectorFrom > 0 else { return "" }
        let rises = attempts.map(\.rise).filter { $0 >= oneVectorFrom - 1e-9 }
        guard rises.count > 1 else { return "" }
        let mm = rises.map { String(format: "%.0f", $0 * 1000) }
        let list = mm.dropLast().joined(separator: ", ") + " and " + mm[mm.count - 1]
        return String(format: " (the %@ mm figures are one move scored at %d heights)", list, rises.count)
    }

    /// "ten of those eleven clears still upright fifty ticks later".
    private var stabilityClause: String {
        guard clearsInAll > 0 else { return "" }
        return String(format: ", %d of those %d clears still upright fifty ticks later",
                      stableClears, clearsInAll)
    }

    /// The sentence for one rise, in the words the measurement supports.
    public func verdict(rise: Double) -> String {
        let mm = rise * 1000
        if !canResolve(rise: rise) {
            return String(format: "A %.0f mm rise. Below %.0f mm the bench's check cannot tell a foot "
                          + "on the tread from a foot on the floor, so nothing this small is "
                          + "measured as climbable or not.",
                          mm, resolvableAbove * 1000)
        }
        let head = String(format: "A %.0f mm rise. ", mm)
        let body: String
        if let a = attempt(at: rise) {
            body = String(format: "In simulation, on %@, %@ gets up this rise in %d of %d perturbed attempts "
                          + "(%@), never reliably; a duck placed on the tread passes %d of %d and doing "
                          + "nothing 0 of %d. Unreliable at every height is not a climb the robot can be "
                          + "shown to have.",
                          flight, move, a.cleared, a.of, grid, a.of, a.of, a.of)
        } else if rise <= tallestAnyCell + 1e-9 {
            body = String(format: "In simulation, on %@, %@ gets up %@ perturbed attempts (%@)%@, and "
                          + "nothing reliably, so nothing this app has can be shown to get up this one.",
                          flight, move, attemptList, grid, oneVectorClause)
        } else {
            body = String(format: "Nothing has got up %.0f mm or taller in any of roughly %@ searched attempts "
                          + "over %d rounds (0 of 9 perturbed attempts), so nothing this app has can be "
                          + "shown to get up this one.",
                          (tallestAnyCell + 0.010) * 1000, Self.thousands(episodes), rounds)
        }
        return head + body
    }

    /// The sentence under the staircase generator's default rise. It used to
    /// say the robot had been measured to clear it; nothing has been.
    public var editorSentence: String {
        String(format: "The staircase starts at %.0f mm a step. That is under the smallest rise the "
               + "bench's check can measure, not a rise the robot is known to clear. Raise it and "
               + "the editor says what was measured.", editorRise * 1000)
    }

    /// One line for a settings or scene footer: the whole claim, with its
    /// caveats in the same breath.
    public var says: String {
        String(format: "In simulation only, after %d rounds of search and roughly %@ attempts, the tallest "
               + "step the Microduck can get onto is unreliable at every height: judged by the criterion "
               + "(%@) on a grid of %@, the best open-loop move, %@, clears %@%@, and 0 of 9 at %.0f mm or "
               + "taller%@, against 9 of 9 for a duck placed on the tread and 0 of 9 for doing nothing on "
               + "the same plant (%@, %@). %@ Rises under %.0f mm cannot be resolved by the check.",
               rounds, Self.thousands(episodes), criterion, grid, move, attemptList, oneVectorClause,
               (tallestAnyCell + 0.010) * 1000, stabilityClause, evidence, measuredOn,
               bandVerdict, resolvableAbove * 1000)
    }

    /// Why the earlier count is gone, for anyone who saw it.
    public var whyTheOldCountIsGone: String {
        String(format: "An earlier audit reported 0 of 54 replays clearing rises from 20 to 180 mm. Its "
               + "staircase pushed its own step blocks apart at every rise under %.0f mm and threw a "
               + "standing duck to the floor, so below that it measured the staircase, not the robot.",
               brokenFlightSoundAbove * 1000)
    }

    /// "21,000", in the kit's own words rather than a locale's.
    private static func thousands(_ n: Int) -> String {
        let s = String(n)
        var out = ""
        for (i, ch) in s.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return String(out.reversed())
    }
}
