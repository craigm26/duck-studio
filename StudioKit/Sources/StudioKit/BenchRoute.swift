import Foundation

/// WHICH BENCH ROUTE A DRAFT SHOULD GO DOWN, DECIDED ONCE.
///
/// THE ROUTE IS A CLAIM, WHICH IS WHY IT IS NOT A VIEW'S BUSINESS. Sending a
/// stairs-challenge draft to `/perform` plays it on a bare bench and reports
/// "8 of 8 stayed upright" over a picture of a staircase that was not in the
/// physics — the exact falsehood this build exists to delete. Sending an edited
/// room to `/climb` publishes a number against a flight nobody laid. Three
/// screens make this decision and a fourth will; they ask here.
///
/// NOTHING IS EVER DISABLED. A route that cannot be taken is a `notYet` with a
/// sentence saying why, beside a control that still does something — a room
/// that was edited is still playable, and says so.
public enum BenchRoute: Equatable, Sendable {

    /// The harness's own scoring route, for the room the score is scored in.
    case climb(rise: Double, cell: DuckBench.Cell, intent: Data,
               room: DuckScene.ChallengeRoom)
    /// The perform route, with the world to stand in — or none at all, when
    /// the scene draws nothing a bench can lay.
    case perform(standing: DuckWorld.Standing?, because: String?)
    case notYet(Blocked)

    /// Why a route cannot be taken, in one sentence each.
    public enum Blocked: Equatable, Sendable {
        case roomWasEdited
        /// The /perform route's box: a blend above one is CLAMPED there and
        /// reported unclamped, a number nobody ran.
        case blendOutsideTheBox(Double)
        /// The challenge's own box, [0.7, 2.4]: a cell outside it is answered
        /// unscored. A different refusal with a different reason.
        case blendOutsideTheScoredBox(Double)
        case sideOutsideTheBox(Double)
        case planRefused(DuckWorld.Refusal, movedToTheBank: Bool)
        case tooFewKeyframes(Int)

        public var message: String {
            switch self {
            case .roomWasEdited:
                return StairsChallenge.roomWasEdited
            case .blendOutsideTheBox(let blend):
                return DuckBench.blendWouldBeClamped(blend)
            case .blendOutsideTheScoredBox(let blend):
                return StairsChallenge.outsideTheScoredBox(
                    param: "blend", value: blend,
                    low: StairsChallenge.blendBox.low, high: StairsChallenge.blendBox.high)
            case .sideOutsideTheBox(let side):
                return StairsChallenge.outsideTheScoredBox(
                    param: "side", value: side,
                    low: StairsChallenge.sideBox.low, high: StairsChallenge.sideBox.high)
            case .planRefused(let refusal, let moved):
                return moved ? DuckWorld.movedThenRefused(refusal) : refusal.message
            case .tooFewKeyframes(let count):
                return "This draft has \(count) keyframe\(count == 1 ? "" : "s") at or after "
                     + "zero, and a track the bench can run needs two: one to start from and "
                     + "one to move to. Add a pose further along the timeline."
            }
        }
    }

    /// The line under the button, naming what the route actually is.
    public var footnote: String {
        switch self {
        case .climb:
            return StairsChallenge.scoredWhereItIsScored
        case .perform:
            return Pipeline.eightRolloutsSaid
        case .notYet(let blocked):
            return blocked.message
        }
    }

    /// The world this route would send, when it sends one.
    public var standing: DuckWorld.Standing? {
        if case .perform(let standing, _) = self { return standing }
        return nil
    }

    /// THE DECISION, IN ORDER, AND THE ORDER IS THE CONTRACT.
    ///
    /// 1. a draft with fewer than two keyframes has no track to send
    /// 2. no scene, or a scene that draws nothing: perform with no world at all
    /// 3. the challenge room, edited: perform, and say it cannot be scored
    /// 4. the scored room with a blend outside the box: not yet
    /// 5. the scored room with a side outside the box: not yet
    /// 6. the scored room: climb, on the source file when there is one
    /// 7. any other scene the bank refuses: not yet, with the refusal
    /// 8. any other scene: perform, with the world and the spawn
    /// 9. any perform route whose blend /perform would clamp: not yet
    public static func of(draft: IntentDraft,
                          scene: DuckScene?,
                          bank: DuckWorld.Bank = .pinned,
                          graspables: [DuckBench.Health.Graspable] = [],
                          cell: DuckBench.Cell = StairsChallenge.Grid.nominal,
                          blend: Double = 1) -> BenchRoute {
        let track = draft.benchTrack
        guard track.count >= 2 else { return .notYet(.tooFewKeyframes(track.count)) }

        // A CLAMPED BLEND IS A NUMBER NOBODY RAN, wherever the perform route
        // is taken. Checked once, here, so every perform branch below is
        // covered by it.
        let performable: (DuckWorld.Standing?, String?) -> BenchRoute = { standing, because in
            if blend > 1 || blend < 0 { return .notYet(.blendOutsideTheBox(blend)) }
            return .perform(standing: standing, because: because)
        }

        guard let scene, !scene.steps.isEmpty || !scene.props.isEmpty else {
            return performable(nil, nil)
        }

        switch scene.roomReading {
        case .editedSinceItWasOpened:
            // PLAYABLE, NOT SCORABLE. The button still runs; the sentence says
            // what the run is not.
            let standing = DuckWorld.standing(for: scene, on: bank, graspables: graspables)
            if let refusal = standing.refusal {
                return .notYet(.planRefused(refusal, movedToTheBank: standing.spawn != nil))
            }
            return performable(standing, StairsChallenge.roomWasEdited)

        case .theScoredRoom(let room):
            guard blend >= StairsChallenge.blendBox.low,
                  blend <= StairsChallenge.blendBox.high else {
                return .notYet(.blendOutsideTheScoredBox(blend))
            }
            guard room.side >= StairsChallenge.sideBox.low,
                  room.side <= StairsChallenge.sideBox.high else {
                return .notYet(.sideOutsideTheBox(room.side))
            }
            // A SOURCE FILE IS ALWAYS PREFERRED TO A FRESH ONE, because
            // `applying(draft:)` keeps `event`, `servo`, `bounds` and `params`
            // — every one of which the leaderboard hash folds in — and
            // `Move.authored` has none of them to keep.
            let intent: Data
            if let source = draft.challengeIntent,
               let move = try? StairsChallenge.Move.decode(source),
               let edited = try? move.applying(draft: draft) {
                intent = edited.encoded()
            } else if let fresh = try? StairsChallenge.Move.authored(draft: draft, room: room,
                                                                     blend: blend) {
                intent = fresh.encoded()
            } else {
                return .notYet(.tooFewKeyframes(track.count))
            }
            return .climb(rise: room.rise, cell: cell, intent: intent, room: room)

        case .notAChallengeRoom:
            let standing = DuckWorld.standing(for: scene, on: bank, graspables: graspables)
            if let refusal = standing.refusal {
                return .notYet(.planRefused(refusal, movedToTheBank: standing.spawn != nil))
            }
            return performable(standing, nil)
        }
    }
}
