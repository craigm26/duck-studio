import Foundation

/// One named number a scorer reads off a recorded trial, and the rule that a
/// success can never travel alone.
///
/// A SCORER HERE IS A READER AND NEVER A RUNNER, which is `inspect-robots`'
/// own rule: `eval()` runs the rollout, records it, and hands the record to a
/// pure function. Everything in this type is read off an answer the bench
/// already sent. Nothing here asks for physics, and nothing here invents a
/// threshold: `travelled_m` is the metres the bench measured, not a share of
/// some floor this app chose.
///
/// The `name` becomes a key in `metrics`, in every scene's `reduced`, and in
/// every epoch entry, which is why it is spelled the way their builtins are
/// spelled and why a name is refused rather than renamed.
public struct EvalScorer: Equatable, Sendable, Identifiable {

    /// What a number is FOR, which is the whole mechanism behind the first
    /// refusal. A screen can put success and motion evidence side by side only
    /// if it knows which is which.
    public enum Role: String, Equatable, Sendable, CaseIterable {
        /// Did the episode end the way the bench's own criterion asks.
        case success
        /// Did the duck go anywhere. The number that keeps `success` honest.
        case motionEvidence
        /// Something to be spent as little of as possible.
        case cost
        /// Worth recording, not worth ranking on.
        case context
    }

    public var id: String { name }
    public let name: String
    /// What the number means, in this app's voice, for the row under it.
    public let said: String
    public let role: Role
    /// The unit as a person reads it, or empty for a share between 0 and 1.
    public let unit: String
    public let higherIsBetter: Bool

    public init(name: String, said: String, role: Role, unit: String, higherIsBetter: Bool) {
        self.name = name
        self.said = said
        self.role = role
        self.unit = unit
        self.higherIsBetter = higherIsBetter
    }

    // MARK: - the ones this app emits

    /// Their own builtin name, kept because it means here exactly what it means
    /// there: the episode ended the way the embodiment said success ends.
    public static let successAtEnd = EvalScorer(
        name: "success_at_end",
        said: "1 when the bench's own criterion was met at the last tick, 0 when it was not. "
            + "A duck that did nothing at all passes it, which is why travel is beside it.",
        role: .success, unit: "", higherIsBetter: true)

    public static let travelled = EvalScorer(
        name: "travelled_m",
        said: "Metres along the direction it was told to go, as the bench measured them.",
        role: .motionEvidence, unit: "m", higherIsBetter: true)

    public static let netDisplacement = EvalScorer(
        name: "net_displacement_m",
        said: "Metres from where it started to where it finished, in any direction. Far from "
            + "travel means it walked, but not where it was told.",
        role: .motionEvidence, unit: "m", higherIsBetter: true)

    public static let endHeight = EvalScorer(
        name: "end_height_m",
        said: "How high the trunk was at the last tick. Recorded because a duck can pass a "
            + "standing test on its knees.",
        role: .context, unit: "m", higherIsBetter: true)

    public static let clearedHonestly = EvalScorer(
        name: "cleared_honestly",
        said: "1 when the harness's own honest clear was met for this cell, 0 when it was not.",
        role: .success, unit: "", higherIsBetter: true)

    public static let peakAboveTread = EvalScorer(
        name: "peak_above_tread_mm",
        said: "The highest the trunk got above the tread at any tick, which is an upper bound "
            + "on what any landing could have turned into a clear.",
        role: .motionEvidence, unit: "mm", higherIsBetter: true)

    public static let maxTorque = EvalScorer(
        name: "max_torque_nm",
        said: "The most any servo was asked for. At the plant's ceiling a servo is saturated "
            + "and the move is asking for something the robot has not got.",
        role: .cost, unit: "N m", higherIsBetter: false)

    public static let ballTravel = EvalScorer(
        name: "ball_travel_mm",
        said: "How far the ball moved along its path, as the harness measured it.",
        role: .motionEvidence, unit: "mm", higherIsBetter: true)

    public static let ballNet = EvalScorer(
        name: "ball_net_mm",
        said: "How far the ball finished from where it started. Far from ball travel means it "
            + "was nudged about rather than sent anywhere.",
        role: .motionEvidence, unit: "mm", higherIsBetter: true)

    public static let closestApproach = EvalScorer(
        name: "closest_approach_mm",
        said: "The nearest the duck ever got to the ball. Recorded so a miss can be told from "
            + "a run that never went near it.",
        role: .context, unit: "mm", higherIsBetter: false)

    // MARK: - the ones this app does not emit, and why

    /// Their names, left empty rather than filled.
    ///
    /// THE RISK IS A NAME THAT MEANS SOMETHING ELSE. `min_distance_to_goal` and
    /// `reached_goal_state` read a distance to a goal, and no route on this
    /// bench reports one; `vlm` is a grader with a rubric and a wire protocol.
    /// A column with their name and this app's arithmetic under it would be
    /// worse than an empty column, because a reader comparing two logs would
    /// have no way to know.
    public static let reservedNames = ["min_distance_to_goal", "reached_goal_state", "vlm",
                                       "operator"]

    public static let notEmittedHere =
        "Three of their scorers are not emitted here. min_distance_to_goal and "
      + "reached_goal_state read a distance to a goal that no route on this bench reports, and "
      + "vlm is a grader this app does not run. A scorer of theirs that this app filled with a "
      + "number of its own would be the same name meaning something else."

    /// Said beside the six per-trial term values on the detail screen.
    ///
    /// THE SIX ARE NOT SCORES AND MUST NOT BE RANKED ON. A duck standing
    /// perfectly still wins five of the six, measured at 35 per cent of the
    /// weighted total, so a run sorted by them would put the duck that did
    /// nothing near the top. They are recorded per trial because they are what
    /// the tuner optimises and a reader deserves to see them; they are reward
    /// terms and they are not a score.
    public static let termsAreNotScoresSaid =
        "The six numbers under each trial are Pollen's own reward terms, as the bench computed "
      + "them. They are recorded, not scored: a duck standing still wins five of the six, so a "
      + "column that ranked on them would rank stillness first."
}

/// The scorers of one task, and the rule that makes a metrics block honest.
public struct EvalScorerSet: Equatable, Sendable {

    public let scorers: [EvalScorer]

    public var names: [String] { scorers.map(\.name) }

    public subscript(name: String) -> EvalScorer? { scorers.first { $0.name == name } }

    /// Why a set of scorers is not one.
    public enum Refusal: Error, Equatable {
        case empty
        case duplicateName(String)
        case reservedName(String)
        case successWithoutMotionEvidence(String)

        public var message: String {
            switch self {
            case .empty:
                return "An evaluation with no scorers would record what happened and say nothing "
                     + "about it."
            case .duplicateName(let name):
                return "Two scorers here are both called \(name), and the name is the key every "
                     + "number is filed under, so one of them would overwrite the other."
            case .reservedName(let name):
                return "\(name) is one of inspect-robots' own names and this app does not emit "
                     + "it. " + EvalScorer.notEmittedHere
            case .successWithoutMotionEvidence(let name):
                return "\(name) cannot be the only thing measured. A duck that is dropped and "
                     + "does nothing at all ends standing, so a success rate with no travel "
                     + "beside it is a number that rewards stillness. Add a scorer that says "
                     + "how far it went."
            }
        }
    }

    /// The only way to build one.
    ///
    /// THE FIRST REFUSAL IS A TYPE AND NOT A WARNING. `success_at_end` alone is
    /// the single most misleading number this app could publish, because the
    /// bench's own criterion is passed perfectly by a duck that never moves. A
    /// comment saying so would be read by nobody; a set that cannot be built
    /// without motion evidence is read by the compiler.
    public static func checked(_ scorers: [EvalScorer]) throws -> EvalScorerSet {
        guard !scorers.isEmpty else { throw Refusal.empty }
        var seen = Set<String>()
        for scorer in scorers {
            guard !EvalScorer.reservedNames.contains(scorer.name) else {
                throw Refusal.reservedName(scorer.name)
            }
            guard seen.insert(scorer.name).inserted else {
                throw Refusal.duplicateName(scorer.name)
            }
        }
        let hasMotionEvidence = scorers.contains { $0.role == .motionEvidence }
        if !hasMotionEvidence, let success = scorers.first(where: { $0.role == .success }) {
            throw Refusal.successWithoutMotionEvidence(success.name)
        }
        return EvalScorerSet(scorers: scorers)
    }

    /// Unchecked, and only reachable from inside, the way `DuckTuner`'s vector
    /// does it: `checked` is where the rule lives and the presets have already
    /// paid for it.
    init(scorers: [EvalScorer]) { self.scorers = scorers }

    // MARK: - the three sets this app uses

    public static let walk = EvalScorerSet(scorers: [
        .successAtEnd, .travelled, .netDisplacement, .endHeight,
    ])

    public static let stairs = EvalScorerSet(scorers: [
        .successAtEnd, .clearedHonestly, .peakAboveTread, .maxTorque,
    ])

    public static let ball = EvalScorerSet(scorers: [
        .successAtEnd, .ballTravel, .ballNet, .closestApproach,
    ])

    /// Every set this app can produce, so a test can walk all of them rather
    /// than the ones somebody remembered.
    public static let all: [EvalScorerSet] = [walk, stairs, ball]
}
