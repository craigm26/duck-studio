import Foundation
import DuckKit

/// Changing a motion you already have, in a sentence.
///
/// DRAFTING AND TWEAKING ARE DIFFERENT JOBS. `MotionProposal` writes a motion
/// from nothing: a model invents keyframes and the app checks them. That is the
/// wrong shape for "make the bow deeper" — asking for a whole new motion throws
/// away everything already adjusted, and a model asked to reproduce fourteen
/// joints across five keyframes will quietly change three of them it was not
/// asked about.
///
/// So a tweak is a LIST OF EDITS against the motion in front of you. It names a
/// moment and a joint and a number, or it adds, removes or moves a keyframe.
/// Everything it does not mention is left exactly as it was, which is the only
/// behaviour that makes a second sentence safe to send.
public struct MotionTweak: Equatable, Sendable {

    public enum Edit: Equatable, Sendable {
        /// Set one joint at the keyframe nearest `at`, in degrees from home.
        case joint(at: Double, word: String, degrees: Double)
        /// A new keyframe at `at`, holding whatever the motion was already
        /// doing there.
        case addKey(at: Double)
        case removeKey(at: Double)
        case moveKey(at: Double, to: Double)
        case rename(String)
    }

    public let summary: String
    public let edits: [Edit]

    public init(summary: String, edits: [Edit]) {
        self.summary = summary; self.edits = edits
    }

    public enum Failure: Error, Equatable, Sendable {
        case noEdits
        case unknownJoint(String)
        case noKeyframeNear(Double)
        case wouldEmptyTheMotion
        /// The destination already belongs to another keyframe.
        case timeAlreadyTaken(Double)
        /// The removal would leave a motion with nowhere to happen.
        case wouldLeaveNoTimeToHappenIn

        /// Why one instruction could not be applied. One sentence, no verdict
        /// on the rest of the list — the two properties below add that, and
        /// they differ, which is the whole reason this is split out.
        public var reason: String {
            switch self {
            case .noEdits:
                return "Nothing in that changed anything. Try naming a joint and a moment — "
                     + "\"bow deeper at half a second\"."
            case .unknownJoint(let word):
                return "\(word) is not a joint this robot has. It has a neck, a head that nods, "
                     + "turns and tilts, a beak, and hips, knees and ankles on both sides."
            case .noKeyframeNear(let time):
                return String(format: "There is no keyframe near %.2f s to change.", time)
            case .wouldEmptyTheMotion:
                return "That would remove every keyframe, and a motion with none is not a motion."
            case .timeAlreadyTaken(let time):
                return String(format: "There is already a keyframe at %.2f s, and two keyframes "
                                    + "cannot share one instant.", time)
            case .wouldLeaveNoTimeToHappenIn:
                return "That would leave the motion with no time to happen in. Move a keyframe "
                     + "later — half a second is plenty — or remove a different one."
            }
        }

        /// The refusal when NOTHING was applied, which is the only case this
        /// type is thrown in. IT SAYS SO OUT LOUD: the old message stopped at
        /// the reason, and a person reading "neck (-110° to 40°) is not a
        /// joint this robot has" had no way to tell whether the other four
        /// edits in the same sentence had landed.
        public var message: String {
            switch self {
            case .noEdits: return reason
            default: return reason + " Nothing was changed."
            }
        }

        /// The refusal for ONE instruction in a list whose other instructions
        /// were applied — see `Outcome`.
        public var skipped: String { reason + " That instruction was skipped." }
    }

    /// Everything a list of edits did, and everything it could not do.
    ///
    /// A PARTIAL FAILURE KEEPS THE GOOD EDITS. `applied(to:)` used to throw out
    /// of the middle of the loop, so "bow deeper and look left" with one joint
    /// word the resolver did not know threw away the deeper bow as well and
    /// reported only the word it refused. Nothing said the rest had been
    /// dropped, so the obvious retry — type it again — dropped it again.
    ///
    /// The refusals are kept SEPARATE from the notes because they are not the
    /// same claim: `notes` is what the motion now does, `refusals` is what it
    /// still does not. `applied(to:)` flattens both into one chronological list
    /// for the caller that cannot tell them apart yet; a caller that can should
    /// use this and render them differently.
    public struct Outcome: Equatable, Sendable {
        /// The motion with every edit that could be applied already in it.
        public let draft: IntentDraft
        /// What changed, one sentence per instruction that did something.
        public let notes: [String]
        /// The instructions that could not be applied, and why — one sentence
        /// each, naming the instruction, in the order they were asked for.
        public let refusals: [String]

        public init(draft: IntentDraft, notes: [String], refusals: [String]) {
            self.draft = draft; self.notes = notes; self.refusals = refusals
        }
    }

    /// How close two keyframes may be before they are the same instant.
    ///
    /// THE SAME WINDOW EVERY OTHER MOVER IN THE APP USES — `.addKey` here, and
    /// `retime`/`nudged` in the editor, which carry the comment "refusing a
    /// collision rather than creating one". NOT `nearEnough`, which answers a
    /// different question ("which keyframe did you mean"): at 0.26 s it would
    /// refuse most legitimate retimes.
    ///
    /// EXACT EQUALITY IS NOT ENOUGH. A move to 1.599 s beside a keyframe at
    /// 1.6 s sorts fine and plays, and asks a neck for 524 rad/s to get there
    /// — an `.impossible` instead of a `.broken`, which is a worse outcome
    /// than the duplicate because it EXPORTS.
    public static let sameInstant = 0.005

    /// How far the clamp has to bite before the note mentions it, in degrees.
    ///
    /// NOT ZERO, AND THAT IS DELIBERATE. `neck_pitch`'s real headroom is
    /// 39.998° from home, so an ordinary "bow to 40°" clamps by 0.002° — and a
    /// note that reported every difference would announce "asked for 40°,
    /// stopped at 40°" on the happy path, which is a lie of the opposite kind.
    static let noticeableClamp = 0.5

    /// How close a named moment has to be to an existing keyframe to count as
    /// that one. A model asked about "the bow at 1.5" and given keyframes at
    /// 1.48 and 2.0 means the first, and demanding an exact match would refuse
    /// a correct answer over rounding.
    public static let nearEnough = 0.26

    /// Apply the edits, and say what actually happened.
    ///
    /// IT RETURNS THE NOTES AS WELL AS THE DRAFT, because an edit that silently
    /// did nothing is worse than one that failed: the screen redraws, the
    /// motion looks unchanged, and the person types the same sentence again.
    public func applied(to draft: IntentDraft) throws -> (draft: IntentDraft, notes: [String]) {
        let outcome = try self.outcome(applyingTo: draft)
        // Chronological, because a caller that renders one flat list is showing
        // the person the order they asked for things in.
        return (outcome.draft, outcome.notes + outcome.refusals)
    }

    /// The same edits, with what was applied and what was refused kept apart.
    ///
    /// IT THROWS ONLY WHEN NOTHING SURVIVED. A refusal beside a change is a
    /// sentence in `refusals`; a refusal beside nothing at all is a `Failure`,
    /// because at that point the refusal IS the answer and the caller has an
    /// unchanged draft to keep.
    public func outcome(applyingTo draft: IntentDraft) throws -> Outcome {
        guard !edits.isEmpty else { throw Failure.noEdits }
        var result = draft
        /// Chronological, so the order of the sentences is the order of the
        /// instructions rather than all the good news first.
        var log: [(text: String, refused: Bool)] = []
        var firstFailure: Failure?

        func note(_ text: String) { log.append((text, false)) }
        /// Record a refusal. The FIRST one is kept so that a list where
        /// nothing landed can still throw the specific reason rather than a
        /// vague "some of that did not work".
        func refuse(_ failure: Failure) {
            if firstFailure == nil { firstFailure = failure }
            log.append((failure.skipped, true))
        }
        func refuse(sentence: String) { log.append((sentence, true)) }

        for edit in edits {
            switch edit {
            case .rename(let name):
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    // A DROPPED RENAME USED TO BE INVISIBLE. `{"name":"  "}` is
                    // a shape a model produces, and skipping it silently left
                    // the panel with nothing to say about an instruction the
                    // person watched themselves send.
                    refuse(sentence: "An empty name is not a name, so the motion is still "
                                   + "called \"\(result.name)\".")
                    continue
                }
                result.name = trimmed
                note("Renamed to \"\(trimmed)\".")

            case .addKey(let at):
                let time = max(at, 0)
                guard !result.keys.contains(where: {
                    abs($0.time - time) < MotionTweak.sameInstant
                }) else {
                    refuse(.timeAlreadyTaken(time))
                    continue
                }
                // The pose the motion was ALREADY passing through, which pins
                // every pose that was pinned before.
                //
                // IT IS STILL NOT A NO-OP, and pretending otherwise was wrong.
                // Each span is smoothstepped separately, easing in and out at
                // both ends, so cutting one span into two makes the duck slow
                // down in the middle where it used to sail through — about two
                // degrees at the half-second on a simple bow. Capturing the
                // interpolated pose is the least surprising choice available,
                // not a free one.
                result.keys.append(.init(time: time, pose: result.pose(at: time)))
                note(String(format: "Added a keyframe at %.2f s.", time))

            case .removeKey(let at):
                guard let index = MotionTweak.nearestIndex(to: at, in: result) else {
                    refuse(.noKeyframeNear(at))
                    continue
                }
                let when = result.keys[index].time
                var trimmed = result
                trimmed.keys.remove(at: index)
                guard !trimmed.keys.isEmpty else {
                    refuse(.wouldEmptyTheMotion)
                    continue
                }
                // THE TWEAK AND THE DRAFT MUST AGREE ON WHAT A MOTION IS. The
                // old guard here refused only the LAST keyframe, while
                // `IntentDraft.problems` calls a lone keyframe at 0.00 s broken
                // — so "drop the second pose" on a two-keyframe motion reported
                // success and left something that will not play or export.
                //
                // The rule tested is the DRAFT's own, not a second copy of it:
                // one pose is a motion provided it has time to happen in, so
                // what is refused is a removal that takes the time away.
                //
                // ORDER MATTERS AND THAT IS THE PRICE. "Remove the 0.5 and put
                // one at 1.0" answered as remove-then-add is refused on its
                // first half, because the motion is momentarily timeless; the
                // add still happens and the sentence says which half did not.
                // Refusing loudly beats the alternative, which silently shipped
                // an unplayable draft under a checkmark.
                guard trimmed.duration > 1e-6 else {
                    refuse(.wouldLeaveNoTimeToHappenIn)
                    continue
                }
                result = trimmed
                note(String(format: "Removed the keyframe at %.2f s.", when))

            case .moveKey(let at, let to):
                guard let index = MotionTweak.nearestIndex(to: at, in: result) else {
                    refuse(.noKeyframeNear(at))
                    continue
                }
                let from = result.keys[index].time
                let time = max(to, 0)
                // TWO KEYFRAMES ON ONE INSTANT IS NOT AN UNPLAYABLE MOTION, IT
                // IS A CRASH WAITING FOR A CALLER. `DuckMove.init(name:
                // keyframes:)` has `precondition(... $0.time < $1.time ...)`,
                // which traps rather than throws. Nothing in this app reaches
                // it — `IntentDraft.move()` goes through the raw validating
                // door, which throws `.timesNotIncreasing` — and
                // `MotionTweakTests` pins that. But the app used to CREATE the
                // duplicate and call it a success: the stage fell back to the
                // home stance at every playhead position because `pose(at:)`
                // swallows the throw, export refused, and the Ask panel said
                // "Moved 0.80 s to 1.60 s." with a checkmark.
                //
                // The moved keyframe is excluded BY ID, not by time: its own
                // current time sits inside the window, so a time-only test
                // would refuse legal small retimes and every no-op self-move.
                guard !result.keys.contains(where: {
                    $0.id != result.keys[index].id
                        && abs($0.time - time) < MotionTweak.sameInstant
                }) else {
                    refuse(.timeAlreadyTaken(time))
                    continue
                }
                result.keys[index].time = time
                note(String(format: "Moved %.2f s to %.2f s.", from, time))

            case .joint(let at, let word, let degrees):
                guard let targets = MotionTweak.targets(for: word) else {
                    // The RAW word back, not the normalised one: quoting the
                    // person's own string is what makes a refusal checkable.
                    refuse(.unknownJoint(word))
                    continue
                }
                guard let index = MotionTweak.nearestIndex(to: at, in: result) else {
                    refuse(.noKeyframeNear(at))
                    continue
                }
                let when = result.keys[index].time
                var achieved: [(word: String, degrees: Double)] = []
                for (joint, mirror) in targets {
                    guard let slot = DuckModel.jointIndex(of: joint),
                          result.keys[index].pose.indices.contains(slot) else { continue }
                    let radians = degrees * mirror * .pi / 180
                    let home = DuckModel.homePose[slot]
                    let range = DuckModel.jointRanges[slot]
                    // CLAMPED TO THE SERVO'S TRAVEL, exactly as a slider is. A
                    // sentence is not a licence to ask for an angle the robot
                    // does not have.
                    let wanted = min(max(home + radians, range.lower), range.upper)
                    result.keys[index].pose[slot] = wanted
                    // READ BACK WHAT WAS WRITTEN, THROUGH THE MIRROR. The note
                    // used to be formatted from the model's own number, so
                    // "neck 500°" printed "neck set to 500°" over a keyframe
                    // holding 40° — the app's success list stating an act it
                    // did not perform, which sends the person back to type a
                    // bigger number that clamps to the same 40° again.
                    // Dividing by the mirror is what stops the right-hand half
                    // of a pair reporting its angle negated.
                    achieved.append((MotionTweak.plainName(joint),
                                     (wanted - home) * 180 / .pi / mirror))
                }
                guard !achieved.isEmpty else {
                    // Only reachable on a keyframe whose pose is the wrong
                    // width, which `IntentDraft.problems` already calls broken
                    // — but silence here would be the app claiming an edit it
                    // could not have made.
                    refuse(sentence: String(format: "%@ is not in the pose at %.2f s, so nothing "
                                                  + "was set there.",
                                            MotionProposal.normalised(word), when))
                    continue
                }
                note(MotionTweak.jointNote(word: MotionProposal.normalised(word),
                                           asked: degrees, achieved: achieved, at: when))
            }
        }

        result.keys.sort { $0.time < $1.time }
        let notes = log.filter { !$0.refused }.map(\.text)
        // NOTHING LANDED, SO THE REFUSAL IS THE WHOLE ANSWER. Returning an
        // unchanged draft with a sentence attached would leave the caller
        // deciding whether to save it; throwing says plainly that there is
        // nothing to save.
        if notes.isEmpty, let failure = firstFailure { throw failure }
        return Outcome(draft: result, notes: notes,
                       refusals: log.filter(\.refused).map(\.text))
    }

    /// The sentence for one joint edit, built from WHAT WAS WRITTEN.
    ///
    /// A GROUP WORD HAS NO SINGLE ACHIEVED NUMBER, and "legs" is the case that
    /// proves it: at 100° the hips reach 100° and the knees stop at 90°, so
    /// neither the request nor any one achieved angle is an honest summary.
    /// When the stops bite unevenly the sentence names the joints that hit one.
    static func jointNote(word: String, asked: Double,
                          achieved: [(word: String, degrees: Double)],
                          at time: Double) -> String {
        let stopped = achieved.filter { abs($0.degrees - asked) > noticeableClamp }
        guard let first = stopped.first else {
            return String(format: "%@ set to %.0f° at %.2f s.", word, asked, time)
        }
        if stopped.count == achieved.count,
           stopped.allSatisfy({ abs($0.degrees - first.degrees) <= noticeableClamp }) {
            return String(format: "%@ asked for %.0f° at %.2f s and stopped at %.0f° — that is "
                                + "the end of its travel.", word, asked, time, first.degrees)
        }
        let named = stopped.map { String(format: "%@ at %.0f°", $0.word, $0.degrees) }
            .joined(separator: ", ")
        return String(format: "%@ set to %.0f° at %.2f s, except %@, which stopped at the end "
                            + "of travel.", word, asked, time, named)
    }

    /// A joint's plain word, for a sentence a person reads — "left knee", not
    /// "left_knee". Falls back to the wire name rather than saying nothing.
    static func plainName(_ joint: String) -> String {
        MotionProposal.jointVocabulary.first { $0.joint == joint }?.word ?? joint
    }

    /// Where the keyframe a stated moment means lives.
    ///
    /// BY INDEX, AND ONLY BY INDEX. Every caller here goes on to write to that
    /// keyframe, and the old shape — find the key, then search again for its
    /// id — was two lookups that could disagree, with a bare `continue` on the
    /// second one covering the case where they did.
    static func nearestIndex(to time: Double, in draft: IntentDraft) -> Int? {
        draft.keys.indices
            .filter { abs(draft.keys[$0].time - time) <= nearEnough }
            .min { abs(draft.keys[$0].time - time) < abs(draft.keys[$1].time - time) }
    }

    /// A word, as one or more joints with their mirror signs — the same
    /// vocabulary drafting uses, so "both hips" means the same thing in a
    /// sentence that writes a motion and a sentence that edits one.
    ///
    /// IT WAS NOT THE SAME VOCABULARY, AND THE PROMPT ITSELF PROVED IT.
    /// `ChatDraft.tweakInstructions(for:)` embeds `MotionProposal.grounding()`
    /// verbatim, which teaches the travel annotation — "neck (-110° to 40°)" —
    /// and a small model echoes what it was just shown. Drafting forgives that
    /// string through `MotionProposal.normalised`; this ladder only lowercased
    /// and trimmed spaces, so the tweak path told the person that the neck the
    /// app had just named is not a joint this robot has. Same for "head-turn",
    /// for "left_hip", and for any word arriving with a trailing newline.
    ///
    /// THE LADDER IS DELIBERATELY `MotionProposal.expand`'s, RUNG FOR RUNG,
    /// including the raw-lowercased wire fallback at the bottom — after
    /// normalising, underscores are spaces, so a sixteenth DuckKit joint would
    /// otherwise be forgiven when drafting and refused when editing, which is
    /// exactly the drift that produced this bug. Two copies of one ladder is
    /// still two copies: `MotionTweakTests` compares this against `expand` for
    /// every offered word, synonym and wire name, and fails when they part.
    static func targets(for word: String) -> [(joint: String, mirror: Double)]? {
        let lowered = MotionProposal.normalised(word)
        if let entry = MotionProposal.jointVocabulary.first(where: { $0.word == lowered })
            ?? MotionProposal.jointVocabulary.first(where: { $0.joint == lowered }) {
            return [(entry.joint, 1)]
        }
        if let wire = MotionProposal.synonyms[lowered],
           DuckModel.jointIndex(of: wire) != nil {
            return [(wire, 1)]
        }
        if let group = MotionProposal.groups[lowered] { return group }
        if DuckModel.jointIndex(of: word.lowercased()) != nil { return [(word.lowercased(), 1)] }
        return nil
    }

    /// What the model needs to know to edit THIS motion: the moments that
    /// exist and where the joints are now.
    ///
    /// WITHOUT THIS IT IS GUESSING. A model told only "make it deeper" does not
    /// know whether there is a keyframe at 0.5 s or 5, and will invent one of
    /// each. Describing the motion is what turns a tweak from a re-draft into
    /// an edit.
    public static func describe(_ draft: IntentDraft) -> String {
        let rows = draft.keys.sorted { $0.time < $1.time }.map { key -> String in
            let moved = MotionProposal.jointVocabulary.compactMap { entry -> String? in
                guard let slot = DuckModel.jointIndex(of: entry.joint),
                      key.pose.indices.contains(slot) else { return nil }
                let degrees = (key.pose[slot] - DuckModel.homePose[slot]) * 180 / .pi
                guard abs(degrees) >= 1 else { return nil }
                return String(format: "%@ %+.0f°", entry.word, degrees)
            }
            return String(format: "  %.2f s: %@", key.time,
                          moved.isEmpty ? "standing" : moved.joined(separator: ", "))
        }.joined(separator: "\n")
        return """
        The motion being edited is called "\(draft.name)" and has \
        \(draft.keys.count) keyframe\(draft.keys.count == 1 ? "" : "s"):
        \(rows)
        Degrees are offsets from standing.
        """
    }
}
