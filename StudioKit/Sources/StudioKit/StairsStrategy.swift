import Foundation

extension StairsChallenge {

    /// WHAT A LEADERBOARD ROW ACTUALLY DOES, IN ONE WORD.
    ///
    /// A published table of nineteen rows called `best_r6_ceilvaultB_60mm` and
    /// `best_r4_famB_beat1_120mm` is a table only its author can read. The
    /// files themselves know better: every entry carries a `family` string
    /// naming the search it came out of, and between them the nineteen describe
    /// eight distinct ideas about how to get a duck onto a step. This turns
    /// that string into the word and the picture a row wears.
    ///
    /// IT IS A LABEL, NOT A TAXONOMY. Nothing is scored differently for having
    /// one, no number changes, and a row whose family this cannot read gets NO
    /// badge rather than a guessed one — which is why `Row.strategy` is
    /// optional and the app draws nothing when it is nil. The alternative,
    /// falling back to some "other" case, is how a screen starts telling people
    /// that a new search is an old one.
    ///
    /// THERE IS NO BLOCK-PUSH CASE because there is no block-push entrant. The
    /// corpus is nineteen files and every one of them is one of these eight;
    /// `StairsStrategyTests` fails if a case here is unreachable from them, so
    /// this list cannot quietly grow a strategy the app has never seen.
    public enum Strategy: String, CaseIterable, Equatable, Sendable {
        /// Plant the beak on the tread, lock the neck as a strut, and pivot the
        /// whole body over the duck's own head.
        case beakStrutVault
        /// The same launch, searched against how high the trunk gets rather
        /// than against whether it lands.
        case ceilingVault
        /// A beak-strut launch with a landing that fires on a condition rather
        /// than at a time.
        case eventLanding
        /// A landing law rewritten every tick from the plant. An upper bound,
        /// not a move a robot could run.
        case servoLanding
        /// Two pushes off the floor instead of one.
        case twoBeat
        /// Brace on the wall in the corner and climb the two surfaces together.
        case cornerClimb
        /// Not a climb: a duck spawned already standing on the tread.
        case placedSpawn
        /// A duck that stands still.
        case doNothing

        /// The word on the row.
        public var word: String {
            switch self {
            case .beakStrutVault: return "Beak-strut vault"
            case .ceilingVault:   return "Ceiling vault"
            case .eventLanding:   return "Event landing"
            case .servoLanding:   return "Servoed landing"
            case .twoBeat:        return "Two-beat"
            case .cornerClimb:    return "Corner climb"
            case .placedSpawn:    return "Placed spawn"
            case .doNothing:      return "Do nothing"
            }
        }

        /// An SF Symbol beside the word.
        public var glyph: String {
            switch self {
            case .beakStrutVault: return "arrow.up.forward"
            case .ceilingVault:   return "arrow.up.to.line"
            case .eventLanding:   return "bolt"
            case .servoLanding:   return "eye"
            case .twoBeat:        return "2.circle"
            case .cornerClimb:    return "arrow.up.right"
            case .placedSpawn:    return "mappin"
            case .doNothing:      return "pause"
            }
        }

        /// The sentence under the move, for somebody about to open it and
        /// wonder what they are looking at.
        public var whatItDoes: String {
            switch self {
            case .beakStrutVault:
                return "The beak is planted on the tread, the neck locks straight as a strut, "
                     + "the hips extend, and the trunk pivots up over the duck's own head. "
                     + "Every ranked entry in this table is a version of this."
            case .ceilingVault:
                return "The same beak-strut launch, searched against how high the trunk gets "
                     + "rather than against whether it lands — which is how round six measured "
                     + "that the bar was never reachable at this scale."
            case .eventLanding:
                return "A beak-strut launch whose landing fires on a condition rather than at a "
                     + "fixed time. Measured against the launch it came from, it moved the "
                     + "trunk by 0 mm in all fourteen cells."
            case .servoLanding:
                return "The landing is rewritten every tick from numbers read straight out of "
                     + "the simulator — the tread's height and edge — which no robot can do. "
                     + "It is published as an upper bound on a landing, not as an entry."
            case .twoBeat:
                return "Two pushes off the floor instead of one. The best moves in the corpus "
                     + "at 90 mm and 120 mm are this shape, and neither of them clears a cell."
            case .cornerClimb:
                return "The duck braces in the corner where the flight meets the wall and works "
                     + "both surfaces at once. The best 180 mm move in the corpus, and it "
                     + "clears nothing."
            case .placedSpawn:
                return "Not a climb. The duck is spawned already standing on the tread, to "
                     + "prove the criterion can be passed at all."
            case .doNothing:
                return "The duck stands still, to prove the criterion cannot be passed for free."
            }
        }

        /// Which strategy a row is, off the file's own fields.
        ///
        /// THE LADDER IS ORDERED, AND THE ORDER IS THE POINT. A servoed
        /// landing and an event-triggered landing are both bolted onto a
        /// beak-strut launch and both say "beak-strut" in their family string,
        /// so a ladder that looked for the launch first would label all three
        /// the same and hide the only difference anybody cares about — that one
        /// of them reads the plant. The two landing laws are read off the
        /// FILE's own `servo` and `event` objects rather than off its prose,
        /// because those are what the scorer runs; the prose is only consulted
        /// for the launches, which have no field of their own.
        ///
        /// Controls first, because a control is not an entry and must never
        /// wear an entry's badge.
        public static func of(family: String?, hasEvent: Bool, hasServo: Bool,
                              hasSpawn: Bool, isControl: Bool) -> Strategy? {
            if isControl { return hasSpawn ? .placedSpawn : .doNothing }
            if hasServo { return .servoLanding }
            if hasEvent { return .eventLanding }
            guard let family else { return nil }
            let said = family.lowercased()
            if said.contains("ceiling") { return .ceilingVault }
            if said.contains("corner") { return .cornerClimb }
            if said.contains("two-beat") || said.contains("two_beat") { return .twoBeat }
            if said.contains("beak-strut") || said.contains("beak_strut") {
                return .beakStrutVault
            }
            return nil
        }
    }
}

extension StairsChallenge {

    /// Whether each bundled file carries a landing law or a spawn, read from
    /// the files ONCE.
    ///
    /// FROM THE FILES, NOT FROM THE TABLE. `event`, `servo` and `spawn` are
    /// objects inside the intent, and they are inside its identity hash — the
    /// bench runs what is in the file. A boolean retyped into the leaderboard
    /// beside them would be a second copy of a fact, free to disagree with the
    /// first. Decoding nineteen small files once, on first use, costs less than
    /// that risk.
    static let fileFlags: [String: (event: Bool, servo: Bool, spawn: Bool)] = {
        var map: [String: (event: Bool, servo: Bool, spawn: Bool)] = [:]
        for row in leaderboard {
            guard let move = try? move(for: row) else { continue }
            map[row.file] = (move.hasEvent, move.hasServo, move.hasSpawn)
        }
        return map
    }()
}

extension StairsChallenge.Row {

    /// What this row does, or nil where the file's family is one this build
    /// has never seen. A screen draws the badge only when there is one.
    public var strategy: StairsChallenge.Strategy? {
        guard let flags = StairsChallenge.fileFlags[file] else { return nil }
        return StairsChallenge.Strategy.of(family: family,
                                           hasEvent: flags.event, hasServo: flags.servo,
                                           hasSpawn: flags.spawn, isControl: isControl)
    }
}
