import Foundation

/// The challenges this app carries, as one list.
///
/// WHY AN ENUM RATHER THAN TWO SCREENS. Until there was a second challenge,
/// "the challenge" was a place in the app and `StairsChallenge` was the thing
/// that lived there. A ball challenge that arrived as its own tab would have
/// split the one habit the stairs rail is built around — open a published
/// move, edit a keyframe, score it, keep what helps — into two habits with two
/// vocabularies. So the place stays, the screen there becomes a list, and this
/// enum is the list.
///
/// EVERY MEMBER ANSWERS THE SAME QUESTIONS. A row needs a name, the one
/// sentence that says what the task is, the criterion it is judged by, the
/// grid it is scored over, and whether there is a published leaderboard to
/// show yet. `Challenge` answers all five for both, so the list screen has no
/// `switch` in it and a third challenge is a case rather than a rewrite.
///
/// `isMeasured` IS COMPUTED, NEVER DECLARED. Whether a challenge has published
/// rows is a fact about the bundled leaderboard, so it is read off the
/// leaderboard. A constant saying "the ball challenge has no rows yet" would
/// go on saying it for a build after the rows landed.
public enum Challenge: String, CaseIterable, Equatable, Sendable, Identifiable, Codable {

    /// Get the duck onto a step and leave it standing there.
    case stairs
    /// Get the duck to reach a ball and move it, from wherever the ball is.
    case ball

    public var id: String { rawValue }

    /// The word on the list row. Short, because the row also carries the
    /// sentence.
    public var name: String {
        switch self {
        case .stairs: return "Stairs"
        case .ball:   return "Ball"
        }
    }

    /// The heading on the challenge's own screen.
    public var title: String {
        switch self {
        case .stairs: return StairsChallenge.title
        case .ball:   return BallChallenge.title
        }
    }

    /// What the task is, in the one sentence the row shows.
    public var oneSentence: String {
        switch self {
        case .stairs: return StairsChallenge.oneSentence
        case .ball:   return BallChallenge.oneSentence
        }
    }

    /// The sentence the bench exports for what it scored. For the stairs that
    /// is `climb_score.mjs`'s; for the ball, `chase_score.mjs`'s
    /// `CRITERION_SENTENCE`.
    public var criterion: String {
        switch self {
        case .stairs: return StairsChallenge.criterionSentence
        case .ball:   return BallChallenge.criterionSentence
        }
    }

    /// How many cells a submission is scored over, and how many of them are
    /// the core the published numbers are quoted against.
    public var coreCount: Int {
        switch self {
        case .stairs: return StairsChallenge.Grid.coreCount
        case .ball:   return BallChallenge.Grid.coreCount
        }
    }

    public var cellCount: Int {
        switch self {
        case .stairs: return StairsChallenge.Grid.count
        case .ball:   return BallChallenge.Grid.count
        }
    }

    /// The two endpoints this challenge needs on a bench.
    public var routes: (score: String, grid: String) {
        switch self {
        case .stairs: return ("/climb", "/climb/grid")
        case .ball:   return ("/chase", "/chase/grid")
        }
    }

    public var datasetURL: URL {
        switch self {
        case .stairs: return StairsChallenge.datasetURL
        case .ball:   return BallChallenge.datasetURL
        }
    }

    public var harnessURL: URL {
        switch self {
        case .stairs: return StairsChallenge.harnessURL
        case .ball:   return BallChallenge.harnessURL
        }
    }

    /// The sentence that has to appear wherever the app offers to send one of
    /// these to a robot. Not softenable in either challenge.
    public var realDuckCaveat: String {
        switch self {
        case .stairs: return StairsChallenge.realDuckCaveat
        case .ball:   return BallChallenge.realDuckCaveat
        }
    }

    /// A bench that cannot score this one, named with what to do about it.
    public func notYetHere(bench: String) -> String {
        switch self {
        case .stairs: return StairsChallenge.noClimbHere(bench: bench)
        case .ball:   return BallChallenge.noChaseHere(bench: bench)
        }
    }

    /// The lead of the provenance line a draft lifted out of this challenge
    /// carries. It is the first thing somebody reads in the Studio's draft
    /// list, and it is how they find out the move is not theirs.
    public var provenanceLead: String {
        switch self {
        case .stairs: return "From the Microduck Stairs Challenge"
        case .ball:   return "From the Microduck Ball Challenge"
        }
    }

    /// How many published rows this challenge ships, controls included.
    public var rowCount: Int {
        switch self {
        case .stairs: return StairsChallenge.leaderboard.count
        case .ball:   return BallChallenge.leaderboard.count
        }
    }

    /// Whether there is a measured leaderboard in this build at all.
    public var isMeasured: Bool { rowCount > 0 }

    /// The second line of the list row: what is in the build, said as a fact
    /// rather than as a badge.
    /// How many of those rows are reference controls rather than entries.
    public var controlCount: Int {
        switch self {
        case .stairs: return StairsChallenge.leaderboard.filter { $0.isControl }.count
        case .ball:   return BallChallenge.leaderboard.filter { $0.isControl }.count
        }
    }
    /// The second line of the list row: what is in the build, said as a fact
    /// rather than as a badge. A CONTROL IS NOT AN ENTRY: a challenge whose
    /// every row is a reference control has no entries yet, and says so.
    public var rowsSaid: String {
        guard isMeasured else { return pendingSaid }
        let entries = rowCount - controlCount
        if entries == 0 {
            return "\(controlCount) reference controls and no entries yet, scored over \(cellCount) cells."
        }
        return "\(entries) published entries and \(controlCount) reference controls, scored over "
             + "\(cellCount) cells."
    }
    /// Said when a challenge ships with no measured rows at all.
    public var pendingSaid: String {
        switch self {
        case .stairs: return "No measured rows in this build yet."
        case .ball:   return BallChallenge.leaderboardPending
        }
    }
    /// The one word over the list of challenges, wherever it is drawn.
    public static let listTitle = "Challenges"
}
