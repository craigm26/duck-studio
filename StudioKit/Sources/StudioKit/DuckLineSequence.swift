import Foundation

/// A number on the frame, so a reader can tell "the duck ignored me" from "the
/// link ate it".
///
/// WHY THIS EXISTS AT ALL. `duck-ipc-proto` has no sequence number — the
/// `Choreography` preamble already says so in the course of admitting that
/// nothing in the contract offers a synchronised start: "no 'begin at time T',
/// no sequence number, nothing a robot could use to wait for its partner." A
/// continuous intent is a notification, so it is never answered, which means a
/// twist that never arrives and a twist the robot decided against look
/// identical from this end: the duck does not move. That is the single most
/// expensive ambiguity in driving one of these, because the two have opposite
/// fixes — one is a network to look at and the other is a policy to look at —
/// and somebody with no number to count is going to spend an hour on the wrong
/// one.
///
/// AND IT IS NOT IN THE PARAMS, WHICH IS THE WHOLE POINT OF THE TYPE.
/// `robot.move` takes `{vx, vy, vyaw}` and nothing else. Pollen's contract
/// records what happens when a convention is not written down — the prototype
/// grew five sign flags "precisely because the convention was never written
/// down, so every new consumer determined it empirically and disagreed" — and
/// an extra key in a params block is a worse version of that: a strict
/// deserialiser refuses the whole call, a lenient one ignores it, and which of
/// those a given `robotd` build does is a thing nobody here has tested. So this
/// number rides on the FRAME, beside the bytes, where a transport may carry it
/// or may drop it. `DuckCall.line(id:)` is unchanged and its output is
/// unchanged; `Stamped` pairs a counter with those exact bytes and hands both
/// to the transport.
///
/// WHAT IT CAN AND CANNOT MEASURE IS THE SENTENCE PEOPLE WILL SKIP AND SHOULD
/// NOT — see `measuresLossNotReordering`. On an ordered channel a gap means
/// loss. On an unordered one a gap means nothing until the window closes, and
/// this type does not implement a window, so pointing it at an unordered
/// channel produces a loss count made of frames that arrived a moment later.
///
/// IT STOPS NOTHING. See `thisCounterStopsNothing`. A counter is a measurement,
/// not a control: nothing here retransmits, nothing blocks, and nothing on the
/// far end has ever seen one of these numbers, because no transport in this app
/// carries frame metadata yet.
public struct DuckLineSequence: Equatable, Sendable {

    /// The number the last frame was stamped with. Zero before anything has
    /// been stamped, so a stamped frame is always a number greater than zero
    /// and a zero in a log is an unstamped frame rather than the first one.
    public private(set) var last: UInt64 = 0

    public init() {}

    /// One line, and the number of the frame carrying it.
    ///
    /// THE BYTES ARE UNTOUCHED AND THAT IS ASSERTED BY A TEST, because the
    /// failure this type must never cause is a `robot.move` whose params grew a
    /// fourth key. `line` is exactly what `DuckCall.line(id:)` produced,
    /// terminator included.
    public struct Stamped: Equatable, Sendable {
        public let number: UInt64
        public let line: Data

        public init(number: UInt64, line: Data) {
            self.number = number
            self.line = line
        }
    }

    /// Stamp the next frame.
    ///
    /// IT WRAPS AT `UInt64.max` RATHER THAN TRAPPING. Sixty-four bits at 50 Hz
    /// is about eleven billion years, so this branch is unreachable in any
    /// universe containing the duck — but `&+` on an overflow that cannot
    /// happen is still better than a crash in somebody's hand if it somehow
    /// does, and a `Watcher` reads the wrap as one gap rather than as a fault.
    public mutating func stamp(_ line: Data) -> Stamped {
        last = last &+ 1
        return Stamped(number: last, line: line)
    }

    // MARK: - reading them back

    /// What one arriving number meant, given the ones before it.
    ///
    /// FOUR OUTCOMES AND NO `unknown`. Every number a watcher can be shown is
    /// one of these, and the two that are not "the next one" are kept apart on
    /// purpose: a gap and a duplicate have different causes, and collapsing
    /// them into "something is wrong with the link" is the kind of summary
    /// nobody can act on.
    public enum Reading: Equatable, Sendable {
        /// The first frame this watcher has seen. Nothing is known yet — in
        /// particular this is NOT proof that nothing was lost before it.
        case first
        /// Exactly one more than the last. Nothing was lost between them.
        case next
        /// A jump forward: this many frames were never seen.
        case missed(Int)
        /// A number this watcher has already been past — a duplicate on an
        /// ordered channel, or a frame that overtook one on an unordered one.
        /// Which of those it is, this type cannot say; see
        /// `measuresLossNotReordering`.
        case behind
    }

    /// Counts what arrived, and what did not.
    ///
    /// A SEPARATE TYPE FROM THE STAMPER because the two ends are separate
    /// machines. One phone stamps and another program reads; a single type
    /// holding both counters would only ever be half used, and the half in use
    /// would be the half the test happened to exercise.
    public struct Watcher: Equatable, Sendable {

        /// The highest number seen so far, or nil before the first frame.
        public private(set) var highest: UInt64?
        /// How many frames the gaps add up to.
        public private(set) var missed = 0
        /// How many numbers arrived that this watcher was already past.
        public private(set) var behind = 0
        /// How many frames arrived at all.
        public private(set) var seen = 0

        public init() {}

        @discardableResult
        public mutating func saw(_ number: UInt64) -> Reading {
            seen += 1
            guard let highest else {
                self.highest = number
                return .first
            }
            if number <= highest {
                behind += 1
                return .behind
            }
            let gap = number - highest - 1
            self.highest = number
            guard gap > 0 else { return .next }
            // A gap wider than an `Int` is a wrapped counter or a corrupted
            // number, and either way "everything" is the honest size of it.
            let counted = Int(clamping: gap)
            missed += counted
            return .missed(counted)
        }

        /// What this watcher has actually established, in words.
        ///
        /// IT REFUSES TO CALL A CLEAN RUN PROOF OF ANYTHING. Nothing missing
        /// means nothing was missing between the first frame seen and the last;
        /// it says nothing about what happened before the watcher started, and
        /// a sentence that read "no frames were lost" would be a claim about a
        /// period nobody was counting.
        public var says: String {
            guard seen > 0 else {
                return "No frames have been counted on this link yet, so nothing is known about "
                     + "whether any have been lost."
            }
            if missed == 0 && behind == 0 {
                return "\(seen) frames counted and none missing between the first and the last. "
                     + "That says nothing about anything sent before the counting started."
            }
            var parts: [String] = []
            if missed > 0 {
                parts.append("\(missed) never arrived")
            }
            if behind > 0 {
                parts.append("\(behind) arrived out of order or twice")
            }
            return "\(seen) frames counted, and \(parts.joined(separator: ", ")). "
                 + DuckLineSequence.measuresLossNotReordering
        }
    }

    // MARK: - what the number is worth

    /// The verdict on what a gap in these numbers actually proves.
    public static let measuresLossNotReordering =
        "On a channel that delivers in order — a reliable, ordered datachannel, or a BLE "
      + "characteristic written in sequence — a gap in these numbers is a frame that was lost, "
      + "because a frame that was merely late could not have arrived after a higher one. On a "
      + "channel that does not guarantee order, the same gap is a frame that may still be on its "
      + "way, and this counter has no window in which to wait for it: it would report loss the "
      + "instant a later frame overtook an earlier one. So the number measures loss on an ordered "
      + "channel and measures nothing dependable on an unordered one, and which kind a transport "
      + "is has to be established before the count means anything."

    /// A sentence saying, out loud, that this changes nothing about what the
    /// duck does.
    ///
    /// SAID BECAUSE A COUNTER LOOKS LIKE A GUARANTEE. Sequence numbers in most
    /// protocols come attached to retransmission, and somebody reading "frames
    /// are numbered" reasonably concludes that a missing one gets sent again.
    /// None of that is here, and the duck's own safety does not depend on it
    /// being here: `robot.move` expires on an age-based deadman, so a lost
    /// frame is a twist that never applied rather than a command left running.
    public static let thisCounterStopsNothing =
        "This counter measures and does nothing else. Nothing is retransmitted, nothing waits for "
      + "a gap to be filled, and no duck has ever been shown one of these numbers — no transport "
      + "in this app carries frame metadata yet, so today the count is a thing this end can prove "
      + "about what it sent. A missing twist is not a command left running either: robot.move "
      + "expires on the robot's own age-based deadman, which is what stops a duck whose frames "
      + "stopped arriving."
}
