import Foundation

/// A trick run: chain the duck's moves against the odds they actually have.
///
/// THE SCORING IS THE MEASUREMENT. Every move in the corpus carries a success
/// rate from sixteen randomised MuJoCo rollouts — Pollen's own randomisation,
/// not a designer's guess — and this game is balanced on those numbers and
/// nothing else. A `roulade` lands sixteen times out of sixteen and is worth
/// one point. A `headspin` lands ONCE in sixteen and is worth sixteen. The
/// player is not being told a story about risk; they are playing against the
/// robot's real physics, and the odds on screen are the odds in the file.
///
/// WHY THAT IS THE RIGHT GAME FOR THIS APP. Everything else here is careful to
/// say what is measured and what is not. A trick game whose difficulty came
/// from a balance spreadsheet would be the first thing in the project to make a
/// number up. This one cannot: delete `intent-success.json` and there is no
/// game, because there are no odds.
///
/// DETERMINISTIC BY CONSTRUCTION. The die is a seeded generator, so a run can
/// be replayed, tested, and disputed. Nothing here reads the clock.
public struct TrickRun: Equatable, Sendable {

    /// One move a player can attempt.
    public struct Trick: Equatable, Sendable, Identifiable {
        /// The clip's name in the corpus — `roulade`, `headspin`, `sit`.
        public let id: String
        public let name: String
        /// Rollouts that achieved what the move is for.
        public let achieves: Int
        public let rollouts: Int
        /// What the measurement was actually judging.
        public let criterion: String

        public var odds: Double {
            rollouts > 0 ? Double(achieves) / Double(rollouts) : 0
        }

        /// Worth the inverse of its odds, rounded — sixteen-for-sixteen pays
        /// one, one-for-sixteen pays sixteen. A move nothing ever achieves is
        /// not scored at all rather than paying infinity.
        public var score: Int {
            guard achieves > 0 else { return 0 }
            return max(1, Int((Double(rollouts) / Double(achieves)).rounded()))
        }

        /// A move measured at 0/16 is not "very hard", it is not possible on
        /// this ground — the stair moves need a step the flat floor does not
        /// have. They are offered as a separate dare, never as a trick.
        public var isPossibleHere: Bool { achieves > 0 }
    }

    /// What happened to one attempt.
    public struct Attempt: Equatable, Sendable {
        public let trick: Trick
        public let landed: Bool
        /// Points added, after the combo multiplier.
        public let scored: Int
        public let comboAfter: Int
    }

    public private(set) var attempts: [Attempt] = []
    public private(set) var score = 0
    /// Consecutive landings. The multiplier is the combo, capped, because an
    /// unbounded one turns the whole game into "do the safest move forever".
    public private(set) var combo = 0
    public static let comboCap = 5

    public let tricks: [Trick]
    private var die: SplitMix64

    public init(tricks: [Trick], seed: UInt64) {
        self.tricks = tricks
        self.die = SplitMix64(seed: seed)
    }

    /// One measured move, as the corpus records it, with no DuckKit types.
    ///
    /// CASTORKIT STAYS DUCK-FREE. The Duck* types live in their own package so
    /// a soundboard does not link a hundred thousand triangles; this engine
    /// keeps that arrangement by taking the three numbers it needs and letting
    /// the app read `intent-success.json`.
    public struct Measurement: Equatable, Sendable {
        public let achieves: Int
        public let rollouts: Int
        public let criterion: String
        public init(achieves: Int, rollouts: Int, criterion: String) {
            self.achieves = achieves; self.rollouts = rollouts; self.criterion = criterion
        }
    }

    /// The names the card shows, keyed by the clip's name in the corpus.
    public static let labels: [String: String] = [
            "roulade": "Roulade", "back_roll": "Back roll", "wall_flip": "Wall flip",
            "headspin": "Headspin", "sit": "Sit down", "ground_pick": "Ground pick",
            "kick_left": "Left kick", "kick_right": "Right kick",
            "roller_crouch": "Crouch glide", "hold": "Hold still",
            "flamingo_left": "Flamingo, left", "flamingo_right": "Flamingo, right",
    ]

    /// Build the card from the corpus's own measurements.
    public init(measured: [String: Measurement], seed: UInt64) {
        let card = Self.labels.compactMap { key, label -> Trick? in
            guard let outcome = measured[key] else { return nil }
            return Trick(id: key, name: label, achieves: outcome.achieves,
                         rollouts: outcome.rollouts, criterion: outcome.criterion)
        }
        // Hardest first: the card should open on what is worth attempting.
        self.init(tricks: card.filter(\.isPossibleHere).sorted {
            $0.score != $1.score ? $0.score > $1.score : $0.id < $1.id
        }, seed: seed)
    }

    /// Attempt a trick. Returns what happened; `nil` if it is not on the card.
    @discardableResult
    public mutating func attempt(_ id: String) -> Attempt? {
        guard let trick = tricks.first(where: { $0.id == id }) else { return nil }
        let landed = die.next() < trick.odds
        let multiplier = landed ? min(combo + 1, Self.comboCap) : 0
        let scored = landed ? trick.score * multiplier : 0
        combo = landed ? min(combo + 1, Self.comboCap) : 0
        score += scored
        let attempt = Attempt(trick: trick, landed: landed, scored: scored,
                              comboAfter: combo)
        attempts.append(attempt)
        return attempt
    }

    public var landed: Int { attempts.filter(\.landed).count }

    /// What the run is worth saying afterwards, in the app's own voice.
    public var summary: String {
        guard !attempts.isEmpty else { return "No tricks attempted." }
        let best = attempts.filter(\.landed).max { $0.scored < $1.scored }
        let headline = "\(score) points from \(landed) of \(attempts.count) landed"
        guard let best else { return headline + "." }
        return headline + ", best was \(best.trick.name) for \(best.scored)."
    }

    /// What a trick run is made of, and where to go to change any of it.
    ///
    /// THE MODES READ AS EDITABLE AND ARE NOT, WHICH IS WHY THIS EXISTS. A
    /// person meeting Trick run sees named moves with scores and reasonably
    /// assumes the moves are theirs to tune — the operator's words were that
    /// "how to actually modify these, which seem to be policies and intents,
    /// is hard to decipher". Nothing on the screen said what the parts were.
    ///
    /// The parts are: a bundled RECORDING per move, a measured success rate
    /// from sixteen randomised rollouts that fixes the score, and no editable
    /// state at all. The two places a person can actually act are elsewhere in
    /// the app, so the sentence names them rather than implying a dial that is
    /// not there.
    public static let whatThisIsMadeOf =
        "Nothing on this card can be edited here, and that is the honest shape of it rather "
      + "than a missing screen. Each move is one recording that already exists, and its score "
      + "is fixed by how often that move actually landed — sixteen rollouts, measured, not "
      + "tuned. To change what a move DOES, open it in Intents and remix it into a motion of "
      + "your own: the remix is yours to edit, and it carries none of the recording's evidence, "
      + "so it starts with no odds at all. To change what DRIVES one, the network behind it is "
      + "in Policies."
}

/// A small seeded generator, so a run is reproducible and testable.
///
/// SplitMix64 rather than `Double.random`: the system generator cannot be
/// seeded, and a game whose outcome cannot be replayed cannot be disputed —
/// or tested.
struct SplitMix64: Equatable, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    /// A fraction in [0, 1).
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return Double(z >> 11) * (1.0 / 9007199254740992.0)
    }

}
