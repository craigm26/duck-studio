import Foundation

/// What the robot has been measured to climb, with the measurement attached.
///
/// A NUMBER THAT SHIPS WITHOUT ITS COUNT IS A CLAIM, NOT A MEASUREMENT. The
/// app carried `measuredStepCeiling = 0.010` and printed "the robot has been
/// measured at 10 mm" under every staircase somebody drew. On 2026-09-01 the
/// four authored stair moves were run against a four-step flight on the very
/// plant the bench serves (`scene.mjb`, digest 3f8c9ab9b409), at every rise
/// from 1 mm to a 170 mm code riser, from three start offsets each. Nothing
/// cleared 10 mm. Nothing cleared 16 mm. Nothing cleared anything above it —
/// 0 of 3, every rise, every move, and they fail by standing upright on the
/// floor short of the riser, trunk never leaving 116 mm.
///
/// AND BELOW ABOUT 11 mm THE CHECK CANNOT SEE A STEP AT ALL. The criterion
/// counts a foot as "on the tread" when it is within 5 mm of the tread's
/// height, and a foot resting on the floor has its geometry centred 5.5 mm
/// up — so for any rise under 10.5 mm a foot on the FLOOR passes the height
/// test, and the whole check collapses to "did the trunk drift forward". That
/// is how earlier runs came to report 1 and 2 mm as cleared. So this type has
/// a resolution limit, and it refuses to report a number under it rather than
/// a flattering one.
///
/// Pollen's own training config caps its stair terrain at 15 mm with the
/// reason written beside it — "the robot can only lift its feet ~1-2 cm" —
/// and the policies the robot loads are deliberately blind to terrain. None
/// of that is a tuning gap. It is the size of the robot's own leg travel.
public struct StepCeiling: Equatable, Sendable {
    /// The tallest rise anything cleared under `criterion`. Zero: nothing did.
    public let metres: Double
    /// Rises below this the criterion cannot resolve; no number is reported
    /// for them, in either direction.
    public let resolvableAbove: Double
    /// The lowest and highest rises actually tried under a check that could
    /// see them.
    public let triedFrom: Double
    public let triedTo: Double
    /// Cleared / attempted at every tried rise, for the moves named.
    public let cleared: Int
    public let of: Int
    public let moves: [String]
    public let criterion: String
    public let plant: String
    public let plantDigest: String
    /// ISO date of the measurement. A string, because the kit reads no clock.
    public let measuredOn: String
    /// The rise the scene editor starts a staircase at and adds a step by. It
    /// sits UNDER the resolvable floor on purpose: the editor's flag stays
    /// quiet there not because 10 mm is known to be climbable, but because
    /// nothing is known about it either way.
    public let editorRise: Double

    public init(metres: Double, resolvableAbove: Double, triedFrom: Double, triedTo: Double,
                cleared: Int, of: Int, moves: [String], criterion: String,
                plant: String, plantDigest: String, measuredOn: String, editorRise: Double) {
        self.metres = metres
        self.resolvableAbove = resolvableAbove
        self.triedFrom = triedFrom
        self.triedTo = triedTo
        self.cleared = cleared
        self.of = of
        self.moves = moves
        self.criterion = criterion
        self.plant = plant
        self.plantDigest = plantDigest
        self.measuredOn = measuredOn
        self.editorRise = editorRise
    }

    /// The measurement this app ships with.
    public static let current = StepCeiling(
        metres: 0,
        resolvableAbove: 0.011,
        triedFrom: 0.020,
        triedTo: 0.180,
        cleared: 0,
        of: 54,
        // THE MOVES ARE THE SEARCHED ONES, because their replays are the evidence
        // on disk: eighteen best tracks from three whole-body strategies — a
        // beak hook with a wall walk, a head press with a trunk twist, and the
        // same with forward drive — each replayed at three start offsets by an
        // adversarial audit (duck-sounds/climb/audit_replay-results.json). The
        // four authored stair moves scored the same zero across a ladder run
        // whose results file was later overwritten by a finer one, so they are
        // named here as what was tried, not as the count.
        moves: ["eighteen searched whole-body tracks (beak hook, head press, head press with drive)",
                "and the four authored stair moves"],
        criterion: "upright, past the first riser, both feet at or above the first tread, "
                 + "the trunk 95 mm above that tread, and still there a second after the move ends",
        plant: "scene.mjb",
        plantDigest: "3f8c9ab9b409",
        measuredOn: "2026-09-01",
        editorRise: 0.010)

    /// Whether the check can say anything about a rise this small.
    public func canResolve(rise: Double) -> Bool { rise >= resolvableAbove - 1e-9 }

    /// The sentence for one rise, in the words the measurement supports.
    public func verdict(rise: Double) -> String {
        let mm = rise * 1000
        if !canResolve(rise: rise) {
            return String(format: "A %.0f mm rise. Below %.0f mm the bench's check cannot tell a foot "
                          + "on the tread from a foot on the floor, so nothing this small is "
                          + "measured as climbable or not.",
                          mm, resolvableAbove * 1000)
        }
        let list = moves.joined(separator: " ")
        return String(format: "A %.0f mm rise. %@ cleared %d of %d audited replays at rises from %.0f to %.0f mm "
                      + "on %@ (%@, %@), so nothing this app has can be shown to get up this one.",
                      mm, list, cleared, of, triedFrom * 1000, triedTo * 1000,
                      plant, plantDigest, measuredOn)
    }

    /// The sentence under the staircase generator's default rise. It used to
    /// say the robot had been measured to clear it; nothing has been.
    public var editorSentence: String {
        String(format: "The staircase starts at %.0f mm a step. That is under the smallest rise the "
               + "bench's check can measure, not a rise the robot is known to clear. Raise it and "
               + "the editor says what was measured.", editorRise * 1000)
    }

    /// One line for a settings or scene footer.
    public var says: String {
        String(format: "Measured %@ on %@ (%@): %@ cleared %d of %d audited replays at rises from %.0f to %.0f "
               + "mm. Rises under %.0f mm cannot be resolved by the check. Criterion: %@.",
               measuredOn, plant, plantDigest, moves.joined(separator: " "), cleared, of,
               triedFrom * 1000, triedTo * 1000, resolvableAbove * 1000, criterion)
    }
}
