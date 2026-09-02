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
/// WHAT IS KNOWN NOW, from a second round scored from saved files by an
/// adversarial audit (duck-sounds/climb/audit_r2-results.json): on a flight
/// repaired so its blocks stop colliding with one another, and nowhere else,
/// a beak-strut vault carried the duck from the floor onto a 40 mm step once
/// and onto a 60 mm step once. Both are real stances — the feet finish at the
/// same height above the tread as a duck placed there — and no cheat was
/// found: the lateral gate held, a do-nothing control fails, a placed duck
/// passes, servo torque never exceeds the plant's ceiling, nothing tunnels.
/// Both are also brittle: the 40 mm move survives 1 of 7 perturbations and
/// the 60 mm move 3 of 7; neither survives a 10 mm change of rise or a 30%
/// change of foot friction. Nothing above 60 mm has cleared in roughly
/// 21,000 searched attempts, and on the flight as shipped both score zero.
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
    /// The tallest rise anything cleared on the plant AS SHIPPED. Zero.
    public let metres: Double
    /// The tallest rise anything cleared on the repaired flight, and every
    /// rise that did, in metres. Each is one deterministic attempt from one
    /// exact start; see `robustness`.
    public let repairedMetres: Double
    public let clearedRises: [Double]
    /// How each clear fared under perturbation, in the audit's own words.
    public let robustness: String
    /// Rises below this the criterion cannot resolve; no number is reported
    /// for them, in either direction.
    public let resolvableAbove: Double
    /// The rise below which the flight as shipped throws a standing duck off
    /// the tread, so no result on it below here is a result about climbing.
    public let shippedFlightSoundAbove: Double
    /// Searched attempts across every round, to the nearest thousand.
    public let episodes: Int
    public let rounds: Int
    public let move: String
    public let repair: String
    public let criterion: String
    public let evidence: String
    /// ISO date of the audit. A string, because the kit reads no clock.
    public let measuredOn: String
    /// The rise the scene editor starts a staircase at and adds a step by. It
    /// sits UNDER the resolvable floor on purpose: the editor's flag stays
    /// quiet there not because 10 mm is known to be climbable, but because
    /// nothing is known about it either way.
    public let editorRise: Double

    public init(metres: Double, repairedMetres: Double, clearedRises: [Double], robustness: String,
                resolvableAbove: Double, shippedFlightSoundAbove: Double, episodes: Int, rounds: Int,
                move: String, repair: String, criterion: String, evidence: String,
                measuredOn: String, editorRise: Double) {
        self.metres = metres
        self.repairedMetres = repairedMetres
        self.clearedRises = clearedRises
        self.robustness = robustness
        self.resolvableAbove = resolvableAbove
        self.shippedFlightSoundAbove = shippedFlightSoundAbove
        self.episodes = episodes
        self.rounds = rounds
        self.move = move
        self.repair = repair
        self.criterion = criterion
        self.evidence = evidence
        self.measuredOn = measuredOn
        self.editorRise = editorRise
    }

    /// The measurement this app ships with.
    public static let current = StepCeiling(
        metres: 0,
        repairedMetres: 0.060,
        clearedRises: [0.040, 0.060],
        robustness: "the 40 mm move survives 1 of 7 perturbations and the 60 mm move 3 of 7, "
                  + "and neither survives a 10 mm change of step height or a 30% change of foot friction",
        resolvableAbove: 0.011,
        shippedFlightSoundAbove: 0.150,
        episodes: 21_000,
        rounds: 2,
        move: "a beak-strut vault",
        repair: "a staircase repaired so its step blocks stop colliding with one another",
        criterion: "upright, within the 340 mm-wide flight, the trunk past the riser face and more than "
                 + "95 mm above the tread, both feet resting on the tread past that same line, "
                 + "scored a second after the move ends",
        evidence: "duck-sounds climb/audit_r2-results.json",
        measuredOn: "2026-09-02",
        editorRise: 0.010)

    /// Whether the check can say anything about a rise this small.
    public func canResolve(rise: Double) -> Bool { rise >= resolvableAbove - 1e-9 }

    /// Whether this exact rise is one of the repaired-flight clears (to the
    /// millimetre — a clear that dies 10 mm either side is that narrow).
    public func clearedOnRepairedFlight(rise: Double) -> Bool {
        clearedRises.contains { abs($0 - rise) < 0.0005 }
    }

    /// The clears, as "a 40 mm step and a 60 mm step".
    private var clearedList: String {
        let words = clearedRises.map { String(format: "a %.0f mm step", $0 * 1000) }
        switch words.count {
        case 0: return "nothing"
        case 1: return words[0]
        default: return words.dropLast().joined(separator: ", ") + " and " + words[words.count - 1]
        }
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
        if clearedOnRepairedFlight(rise: rise) {
            body = String(format: "In simulation, on %@, %@ got up this rise once, from one exact start, "
                          + "and not at 10 mm either side; %@. On the staircase as shipped it scores zero. "
                          + "One coincidence is not a climb the robot can be shown to have.",
                          repair, move, robustness)
        } else if rise <= repairedMetres + 1e-9 {
            body = String(format: "In simulation, on %@, %@ got up %@ once each and nothing in between; "
                          + "%@. On the staircase as shipped nothing has cleared at all, so nothing "
                          + "this app has can be shown to get up this one.",
                          repair, move, clearedList, robustness)
        } else {
            body = String(format: "Nothing above %.0f mm has cleared in roughly %@ searched attempts over "
                          + "%d rounds, and on the staircase as shipped nothing has cleared at all, so "
                          + "nothing this app has can be shown to get up this one.",
                          repairedMetres * 1000, Self.thousands(episodes), rounds)
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
        String(format: "In simulation only, and only on %@, the duck has climbed a stair twice in roughly "
               + "%@ searched attempts over %d rounds: %@ onto %@, each re-verified from its saved "
               + "file (%@, %@). %@. Nothing above %.0f mm has cleared, and on the staircase as "
               + "shipped both score zero. Rises under %.0f mm cannot be resolved by the check. "
               + "Criterion: %@.",
               repair, Self.thousands(episodes), rounds, move, clearedList, evidence, measuredOn,
               robustness.prefix(1).uppercased() + robustness.dropFirst(),
               repairedMetres * 1000, resolvableAbove * 1000, criterion)
    }

    /// Why the earlier count is gone, for anyone who saw it.
    public var whyTheOldCountIsGone: String {
        String(format: "An earlier audit reported 0 of 54 replays clearing rises from 20 to 180 mm. Its "
               + "staircase pushed its own step blocks apart at every rise under %.0f mm and threw a "
               + "standing duck to the floor, so below that it measured the staircase, not the robot.",
               shippedFlightSoundAbove * 1000)
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
