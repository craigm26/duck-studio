import Foundation
import DuckKit

/// What stands between a language model and a draft: how many tries it gets,
/// how long it gets, and when to stop asking it.
///
/// WHAT WAS MISSING. `MotionProposal` resolves and validates, and it does both
/// well — but nothing counted attempts, nothing noticed a model failing the
/// same way over and over, and nothing had a deadline. A model that cannot say
/// "left knee" is not going to learn to on the fifth try, and asking it again
/// is how a drafting screen turns into a loop that nobody chose to start.
///
/// THE ENFORCEMENT ORDER IS quackd's `safety.py`, AND SO IS THE RECORDER'S
/// PLACE IN IT. There the order is: abort flag, allowlist, params, confirm,
/// budget, abort conditions, preconditions, dry-run, execute with timeout,
/// record — and the consecutive-failure abort fires POST-execution, inside the
/// recorder, resetting on any success. The order matters more than the number
/// of stages: a refusal that costs a try is a different thing from a refusal
/// that does not, and putting `params` before `budget` is what decides which.
///
/// FIVE OF THOSE STAGES ARE NOTHING HERE, and saying so is better than
/// building them empty:
/// - **allowlist** — there is one thing to call, `resolve()`, so the list has
///   one entry and checking it is theatre. The vocabulary check people expect
///   to find here is not an allowlist; it is what `resolve()` does, and a word
///   it refuses is a FAILURE, which is the recorder's business.
/// - **confirm** — nothing here reaches hardware. The rules do not fire and a
///   draft is a file; there is no irreversible act to hold a person over.
/// - **abort conditions** — quackd's are about the robot's own state. This
///   runs on a phone with no robot attached to have a state.
/// - **preconditions** — the robot's travel is the only one, and `resolve()`
///   already clamps into it rather than asking permission.
/// - **dry-run** — the preview IS the dry run, and it happens after this, in
///   the editor, where a person can watch it.
///
/// WHAT THIS DOES NOT BOUND, stated plainly: a params rejection returns
/// feedback without spending a try, exactly as quackd's ordering says it must,
/// so a caller that retried malformed proposals by itself would not be stopped
/// by this. Today the only thing that retries is a person typing again, and a
/// person typing is not a runaway.
public struct DraftGate {

    /// - `maxConsecutiveFailures` is 5 because that is the shape of the
    ///   problem: a model that has failed the same way five times is not one
    ///   try away from succeeding.
    /// - `maxDrafts` and `maxSeconds` are A POLICY, NOT A MEASUREMENT, and
    ///   there is nothing honest to derive them from — no drafting rate has
    ///   been measured, and the on-device model's speed varies by device. 40
    ///   tries and 5 minutes are more than any real sitting at the keyboard,
    ///   and the only claim made for them is that they are finite.
    public struct Limits: Equatable, Sendable {
        public var maxDrafts: Int
        public var maxSeconds: Double
        public var maxConsecutiveFailures: Int

        public init(maxDrafts: Int = 40, maxSeconds: Double = 300,
                    maxConsecutiveFailures: Int = 5) {
            self.maxDrafts = maxDrafts
            self.maxSeconds = maxSeconds
            self.maxConsecutiveFailures = maxConsecutiveFailures
        }
    }

    /// Three outcomes, and the difference between the last two is the whole
    /// point: `feedback` means say what went wrong and let them try again;
    /// `stopped` means this run is over and trying again will not help.
    public enum Outcome: Equatable {
        case drafted(IntentDraft)
        case feedback(String)
        case stopped(String)
    }

    public let limits: Limits
    public private(set) var budget: DraftBudget
    /// Failures since the last success. Reset by any success, which is what
    /// makes it "the model is stuck" rather than "the model has had a bad day".
    public private(set) var consecutiveFailures = 0
    /// Set once, and once set the gate answers nothing else.
    public private(set) var stopReason: String?

    public var isStopped: Bool { stopReason != nil }

    /// `now` is the caller's clock, not the wall clock. See `DraftBudget`.
    public init(limits: Limits = Limits(), now: @escaping @Sendable () -> Double) {
        self.limits = limits
        self.budget = DraftBudget(maxSteps: limits.maxDrafts,
                                  maxSeconds: limits.maxSeconds, now: now)
    }

    /// One attempt at turning a model's proposal into an editable draft.
    public mutating func draft(_ proposal: MotionProposal) -> Outcome {
        // 1. THE ABORT FLAG. Once stopped, stopped — and it repeats the reason
        //    rather than inventing a second one, so a caller that keeps asking
        //    keeps getting the same sentence instead of a growing story.
        if let stopReason { return .stopped(stopReason) }

        // 2. allowlist — nothing to check. See the note on this type.

        // 3. PARAMS, and deliberately before the budget: a proposal that is
        //    not arithmetic is a broken call, not a failed try, and it should
        //    not cost one.
        if let complaint = Self.malformedParameters(proposal) { return .feedback(complaint) }

        // 4. confirm — nothing irreversible to confirm.

        // 5. THE BUDGET, checked and spent in one call so the check cannot
        //    drift away from the increment.
        do {
            try budget.spend()
        } catch let exhausted as DraftBudget.Exhausted {
            return stop(exhausted.message + " Nothing was drafted from that last sentence. "
                      + "The keyframes are still there to write by hand.")
        } catch {
            return stop("The budget could not be checked: \(error)")
        }

        // 6. abort conditions, 7. preconditions, 8. dry-run — none here.

        // 9. EXECUTE.
        do {
            let draft = try proposal.resolve()
            // 10. RECORD. A draft that resolved is a success even when the
            //     editor will flag it: `IntentDraft.problems` is a report on a
            //     motion that exists, and this counter is about whether the
            //     model can produce one at all.
            return record(success: draft)
        } catch let unresolvable as MotionProposal.Unresolvable {
            return record(failure: unresolvable.message)
        } catch {
            return record(failure: "That could not be turned into a motion: \(error)")
        }
    }

    // MARK: - the recorder

    private mutating func record(success draft: IntentDraft) -> Outcome {
        consecutiveFailures = 0
        return .drafted(draft)
    }

    private mutating func record(failure reason: String) -> Outcome {
        consecutiveFailures += 1
        guard consecutiveFailures >= limits.maxConsecutiveFailures else {
            return .feedback(reason)
        }
        // THE REASON IN WORDS, INCLUDING THE LAST ONE. "The model failed" is
        // not something anybody can act on; the sentence it failed with is.
        return stop("Stopped asking after \(consecutiveFailures) drafts in a row that could not "
                  + "be resolved. The last one said: \(reason) Try describing the motion "
                  + "differently, or write the keyframes by hand.")
    }

    private mutating func stop(_ reason: String) -> Outcome {
        stopReason = reason
        return .stopped(reason)
    }

    // MARK: - params

    /// The one thing about a proposal that is not a failure but a broken call:
    /// a number that is not a number.
    ///
    /// WHY IT IS CHECKED AT ALL. `resolve()` clamps every angle into the
    /// joint's travel with `min`/`max`, and those propagate NaN rather than
    /// clamping it — Swift's `max(.nan, lower)` is `.nan`. So a NaN survives
    /// resolution, survives validation, and first becomes visible at export,
    /// where `JSONSerialization` refuses to write it. Catching it here means
    /// the complaint names the model's output instead of a serialiser.
    static func malformedParameters(_ proposal: MotionProposal) -> String? {
        for key in proposal.keys {
            if !key.atSeconds.isFinite {
                return "A keyframe has no real time on it — the model wrote a number that is "
                     + "not a number. Nothing can be placed on a timeline from that."
            }
            if !key.mouthOpen.isFinite {
                return "The beak was given a number that is not a number."
            }
            for move in key.moves where !move.degrees.isFinite {
                return "\"\(move.joint)\" was given a number that is not a number, so there is "
                     + "no angle to clamp into its travel."
            }
        }
        return nil
    }
}
