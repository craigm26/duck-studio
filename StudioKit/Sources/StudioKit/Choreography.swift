import Foundation
import DuckKit

// MARK: - the namespace, and the sentence the rest of the file is about

/// Several ducks moving to one timed score.
///
/// THIS IS A PLAYER PIANO AND NOT A FLOCK, AND THE DIFFERENCE IS THE WHOLE
/// FILE. A flock is animals reacting to each other: each bird sees its
/// neighbours and adjusts, and the pattern is produced by the birds. Nothing
/// here can do that, and the reason is not a missing feature — it is the shape
/// of the robot. The Microduck's observation is 61 values: 48 of
/// proprioception, three of commanded twist, four of head pose, six of body
/// pose. Every one of those is about the duck's own body or about what it was
/// just told. THERE IS NO SLOT FOR ANOTHER ROBOT. A duck cannot see, hear,
/// smell or infer a second duck, so no duck in a score is reacting to any other
/// duck in it; each one is following instructions it would follow identically
/// in an empty room. All of the coordination is in this app's clock, and if
/// this app's clock is wrong then the ducks are wrong together and none of them
/// will notice or correct.
///
/// THE APPEALING READING IS THE ONE THIS CANNOT DO, which is why the warning
/// is the first paragraph rather than a footnote. "Swarm", "formation",
/// "they're dancing together" — every one of those describes ducks that are
/// aware of each other, and a person watching two Microducks turn at the same
/// moment will reach for exactly those words. What they are actually watching
/// is two independent playback heads that were started with an offset. The
/// types below are named for the pianola and not for the flock — `Score`,
/// `Step`, a `Skew` that reports how far apart the notes actually landed —
/// because a person reading `Flock.formation` in a stack trace will believe
/// something about the robot that is not true.
///
/// THREE THINGS BOUND WHAT A SCORE CAN PROMISE, and each of them is a type in
/// this file rather than a sentence in a comment, because a comment is not
/// checked by anything. One of the three cannot be enforced from this side at
/// all, and the first job of its type is to say so:
///
/// 1. SKEW. There are N independent links with independent jitter, no shared
///    clock between the ducks, and no synchronised-start primitive anywhere in
///    `duck-ipc-proto` — no "begin at time T", no sequence number, nothing a
///    robot could use to wait for its partner. The best available is to send
///    each duck's command early by that link's measured one-way delay so the
///    commands LAND together rather than being SENT together, and then to
///    report the residual honestly. `Skew` is that residual, and it is named
///    for what was ACHIEVED rather than what was asked for.
///
/// 2. ONE WRITER — AND THIS APP CANNOT ACTUALLY ARRANGE ONE. `intents.rs`
///    holds a single command slot, last-writer-wins. Two clients pushing
///    twists at 50 Hz "interleave into one slot, producing a robot that obeys
///    neither" — and the first symptom is a duck ignoring BOTH inputs, not a
///    duck obeying the wrong one, which is exactly the symptom somebody debugs
///    as a dead link for an hour. The fix their contract names is a
///    single-writer token, and a token is a thing a DUCK hands out:
///    `duck-ipc-proto` has no method by which a client could claim one, hold a
///    lease, or even announce a writer identity, and Pollen's roadmap has the
///    work at M6 marked UNSOLVED. So what is in this file is
///    `LocalWriterAdvisory` — a note this app keeps to itself, which stops this
///    app from driving one duck from two of its own screens and stops nothing
///    else at all. It is named for what it does because the previous name
///    claimed exclusion, and an exclusion nobody can enforce is worse than no
///    exclusion, since the second operator has been told they are alone.
///
/// 3. THE DEADMAN. The robot's safety gate is `safety.gate(command, twist_age)`
///    — age-based, and per robot. That is a good property and it has a sharp
///    edge in a score: when one duck's link drops, that duck stops, and every
///    OTHER duck carries on performing a duet with a robot that is standing
///    still. Nothing on the robot side can notice, because of the 61 values in
///    the paragraph above. So the abort is the app's job: any fault aborts the
///    whole score and emits `robot.stop` to every duck in it.
public enum Choreography {

    /// How long a note about who is driving stands without being renewed,
    /// seconds.
    ///
    /// A NOTE THAT LAPSES RATHER THAN ONE THAT STANDS FOREVER, BECAUSE THE
    /// WRITER IS A SCREEN THAT CAN BE TORN DOWN. A note that were held until
    /// somebody released it would be held by every screen that was dismissed
    /// mid-drive, by every view model that was deallocated before its `defer`
    /// ran, and by the driving loop that threw — and the duck would then be
    /// undrivable from this app until it was relaunched. Two seconds is long
    /// enough to survive a stutter in a driving loop that renews at 50 Hz, and
    /// short enough that a screen which has gone away does not keep the duck
    /// for the rest of the afternoon. `ScoreRun` renews on every advance and
    /// covers the whole length of the score it is playing, so a long score is
    /// not made of lapsed two-second notes.
    ///
    /// THIS IS THE APP'S BOOKKEEPING AND NOT THE ROBOT'S DEADMAN. Letting a
    /// note lapse stops nobody: it only means this app will let the next asker
    /// take the write handle. What actually stops an undriven duck is the
    /// robot's own age-based gate, which is a different clock in a different
    /// process and does not consult this one.
    public static let defaultNoteSeconds = 2.0

    /// Frames per second for a held continuous intent.
    ///
    /// DERIVED FROM `DuckModel.tickHz` RATHER THAN WRITTEN OUT AGAIN. It used
    /// to be a literal `50.0` here, pinned by a test that compared it to
    /// another literal `50.0`, so the two numbers could only ever agree with
    /// themselves: a change to the robot's control rate would have moved
    /// DuckKit and left this file confidently holding the old figure, and both
    /// the value and its test would still have passed. The symptom would not
    /// have been an error — it would have been held notes going out at a rate
    /// the robot no longer runs, which looks like a stutter in the gait.
    ///
    /// IT IS THE SAME 50 Hz SEEN FROM BOTH ENDS, which is why deriving it is
    /// honest and not merely tidy. `DuckModel.tickHz` is the control loop's
    /// rate; `padd` sends `robot.move` at 50 Hz flat, polling the sticks so the
    /// last known value keeps going out whether or not the pad reported
    /// anything new; and `duck-ipc-proto` gives 20–50 Hz as the band for
    /// continuous intents. A score that holds a walk therefore repeats at the
    /// rate a person has already driven the robot at, so a held note in a score
    /// and a held stick are one thing.
    public static let defaultRateHz = DuckModel.tickHz

    /// The slowest rate at which a held command stays held.
    ///
    /// POLLEN'S OWN BAND, NOT A GUESS: `duck-ipc-proto` describes continuous
    /// intents as "sent as notifications, 20-50 Hz, last-writer-wins,
    /// expiring". 20 is the bottom of it, so a score below this is asking the
    /// robot to hold something it will have forgotten before the next frame.
    public static let slowestSustainedHz = 20.0

    /// Everything this file refuses to do, and why.
    ///
    /// ONE VOCABULARY OF REFUSALS FOR THE WHOLE FILE, matching how `DuckCall`
    /// keeps `Misuse` in one place: these are sentences a person reads while a
    /// score has just failed to start in front of an audience, and the worst
    /// possible thing to hand them is two error types with two wordings for the
    /// same event.
    public enum Problem: Error, Equatable {

        /// A link was described with no timings at all.
        case noSamples

        /// A duration that is not a duration — a NaN, an infinity, or a
        /// negative number of seconds.
        case notASecond(Double)

        /// A step placed at a time a score cannot contain.
        case stepOutOfOrder(Double)

        /// A duck appears in the score with no measurement of its link.
        case unmeasuredLink(DuckID)

        /// Another screen of THIS app is already noted as driving this duck.
        /// It says nothing about anybody outside this process — see
        /// `LocalWriterAdvisory`.
        case alreadyDrivenInThisApp(DuckID, by: LocalWriterAdvisory.Writer)

        /// A clearing or a renewal from somebody who is not the noted driver.
        case notTheNotedDriver(DuckID, LocalWriterAdvisory.Writer)

        /// A score was pointed at a duck this driver is not noted for.
        /// Distinct from `notTheNotedDriver` on purpose: this is the gate on
        /// starting a performance, and it is the one somebody will hit.
        case notNotedForThisScore(DuckID, LocalWriterAdvisory.Writer)

        /// A discrete call was asked to be held down. See `Score.holding`.
        case notSustainable(DuckMethod)

        /// A frame rate of zero or less, which would produce either no frames
        /// or infinitely many.
        case rateIsNotPositive(Double)
        /// A held note at a rate the robot's deadman outlives.
        case rateTooSlowToHold(Double)

        /// A hold whose frame count is past what this file will build. See
        /// `Score.frameCeiling`.
        case tooManyFrames(seconds: Double, hz: Double)

        /// Two ducks in one cast answer to the same key. See `DuckCast`.
        case sameKeyTwice(String)

        /// A score or an emission names a duck the cast has no peer for.
        case unknownDuck(DuckID)

        /// A peer is present but its link does not carry everything the score
        /// needs from it.
        case linkCannotCarry(DuckID, Set<DuckMethod>)

        public var message: String {
            switch self {
            case .noSamples:
                return "A link with no timings on it. The whole scheduling trick is to send "
                     + "early by a link's measured delay, so a link nobody has timed cannot be "
                     + "in a score — guessing a delay would move the error from a refusal into "
                     + "the performance."
            case .notASecond(let value):
                return "\(value) is not a number of seconds. Durations here are finite and not "
                     + "negative, and a NaN reaching the scheduler would produce send times that "
                     + "compare false against everything and simply never fire."
            case .stepOutOfOrder(let at):
                return "A step at \(at) s. A score starts at zero and runs forward; a step "
                     + "before the downbeat has no instant to be sent at."
            case .unmeasuredLink(let duck):
                return "\(duck) is in the score but its link has never been timed. Scheduling "
                     + "it against an assumed delay would put a made-up number in the one place "
                     + "this whole file exists to be honest about."
            case .alreadyDrivenInThisApp(let duck, let driver):
                return "\(driver) is already driving \(duck) from this app, and two of this "
                     + "app's own screens on one duck is the one collision this app can "
                     + "actually see: `intents.rs` keeps a single command slot, so two writers "
                     + "at 50 Hz interleave into it and the duck obeys neither of them. Close "
                     + "that screen or drive from it. Note that this refusal is about this app "
                     + "only — another phone, a gamepad or robotctl could be writing to "
                     + "\(duck) as well, and nothing here can tell."
            case .notTheNotedDriver(let duck, let driver):
                return "This app has not noted \(driver) as \(duck)'s driver, so there is "
                     + "nothing here for it to hand back or renew."
            case .notNotedForThisScore(let duck, let driver):
                return "\(driver) cannot run a score against \(duck) without this app first "
                     + "noting it as the driver. Take the note deliberately, and while looking "
                     + "at who else might be driving that duck right now — this app can only "
                     + "see its own screens, so the looking is a person's job."
            case .notSustainable(let method):
                return "\(method.rawValue) is answered once, so it cannot be held down. Only "
                     + "the continuous intents repeat, because only they expire."
            case .rateIsNotPositive(let hz):
                return "\(hz) Hz is not a frame rate. A held intent is repeated frames, and "
                     + "zero frames a second is not a hold, it is a gap the robot's expiry ends."
            case .rateTooSlowToHold(let hz):
                let asked = String(format: "%g", hz)
                let floor = String(format: "%g", Choreography.slowestSustainedHz)
                return "A held command at \(asked) Hz is not held: a continuous intent expires "
                     + "on the robot's deadman, and Pollen send these at 20-50 Hz for that "
                     + "reason. Below \(floor) the duck stops between frames, which looks like "
                     + "a stuttering policy rather than a score built wrong."
            case .tooManyFrames(let seconds, let hz):
                return "A hold of \(seconds) s at \(hz) Hz is more frames than this file will "
                     + "build. A held note is one `Step` per frame in an array, and the ceiling "
                     + "is \(Score.frameCeiling) of them — an hour at "
                     + "\(Int(Choreography.defaultRateHz)) Hz, which is far longer than any "
                     + "performance anybody punches on purpose. The usual cause is "
                     + "milliseconds where seconds were meant: 2000 is an ordinary number of "
                     + "milliseconds and a preposterous number of seconds."
            case .sameKeyTwice(let name):
                return "Two ducks here both call themselves \"\(name)\". A name is not an "
                     + "identity — `SimDuckConfig` says so about its own field, \"a name for a "
                     + "peer in a list, not an identifier\" — and `SimDuckConfig.stock()` names "
                     + "every duck it makes \"Duck\", so two stock simulators are the ordinary "
                     + "way to arrive here. A score keys ducks by that string, so these two "
                     + "would collapse into one: some commands would reach whichever peer won "
                     + "the key and the other duck would stand still while every screen looked "
                     + "correct. Rename one of them."
            case .unknownDuck(let duck):
                return "\(duck) is named in this score but there is no peer for it in the "
                     + "cast. A score is a list of names and a cast is what turns a name into "
                     + "something this app can write to; without the second one there is "
                     + "nowhere for that duck's commands to go."
            case .linkCannotCarry(let duck, let missing):
                let names = missing.map(\.rawValue).sorted().joined(separator: ", ")
                return "\(duck)'s link does not carry \(names). `DuckPeer.vet` would refuse "
                     + "each of those by name once the score had started, which is a row of "
                     + "buttons failing one at a time in front of an audience; this is the "
                     + "same refusal, arrived at before anything moved."
            }
        }
    }

    /// Milliseconds, for the sentences below.
    ///
    /// SKEW IS ALWAYS READ IN MILLISECONDS and never in seconds, because the
    /// interesting figures are two digits of them and "0.084 s" is a number
    /// somebody has to convert in their head before they can judge it.
    ///
    /// ANYTHING THAT ROUNDS TO ZERO PRINTS AS "0 ms", NEVER AS "-0 ms", AND
    /// THAT IS NOT COSMETIC. `%.0f` of a negative zero is the string "-0", and
    /// negative zero is the ordinary case here rather than an exotic one:
    /// `RoundTrip.typical` is the LOWER median, so a link timed an even number
    /// of times has `fastest == typical` exactly, `Skew.earliestSeconds` is
    /// `+0.0`, and `Skew.says` negates it to say how early a duck can land.
    /// Two samples is the fewest `isEvidenced` accepts, so "-0 ms early" was
    /// what the common case printed. A minus sign in front of a measurement is
    /// read as a direction, and there is no such thing as landing minus-zero
    /// milliseconds early. The same branch also catches a real value that
    /// rounds to zero — minus four tenths of a millisecond is "0 ms", not a
    /// signed zero.
    static func ms(_ seconds: Double) -> String {
        let whole = (seconds * 1000).rounded()
        return whole == 0 ? "0 ms" : String(format: "%.0f ms", whole)
    }
}

// MARK: - which duck

/// The key a score refers to one duck by.
///
/// IT IS A KEY THE CALLER CHOSE AND NOT AN IDENTITY THE ROBOT ISSUED, and that
/// sentence is the whole doc comment, because the type is a `String` in a
/// wrapper and everything interesting about it is what it is NOT. Nothing in
/// `duck-ipc-proto` returns an identifier for a duck: `hello` is a greeting,
/// and what this app has to go on is `DuckIdentity.name` — a hostname over BLE,
/// or whatever a person typed into a bench. `SimDuckConfig` says the same thing
/// about its own field in its own words: "a name for a peer in a list, not an
/// identifier: nothing in this app resolves a duck by name."
///
/// SO A NAME BECOMES A KEY IN EXACTLY ONE PLACE, AND THAT PLACE REFUSES
/// COLLISIONS. `DuckCast.init` is the only thing in this file that turns a
/// `DuckIdentity` into a `DuckID`, and it throws `sameKeyTwice` when two peers
/// answer to one name rather than letting the second quietly replace the first.
/// It has to, because `SimDuckConfig.stock()` names every duck it makes "Duck":
/// two stock simulators in one score is not a corner case, it is the second
/// thing anybody does. There is deliberately no `DuckID(some DuckIdentity)`
/// initialiser, because that is precisely the convenience that would put the
/// collision back everywhere.
///
/// A TYPE RATHER THAN A `String` FOR ONE REASON THAT IS NOT TIDINESS: it is
/// `Comparable`, so every list this file produces — the ducks in a score, the
/// stops in an abort, the two ducks named in a `Skew` — has a defined order
/// even though it comes out of a `Set` or a `Dictionary`. Those are unordered,
/// and an unordered result is a test that passes four times and fails the
/// fifth, which is the kind of flake that gets a whole test file deleted.
public struct DuckID: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let value: String

    /// - Parameter value: Whatever the caller has decided to call this duck
    ///   within this score. It is not read off the robot and nothing verifies
    ///   it; two ducks given one string are one duck as far as everything below
    ///   is concerned, which is why `DuckCast` checks for that.
    public init(_ value: String) { self.value = value }

    public static func < (lhs: DuckID, rhs: DuckID) -> Bool { lhs.value < rhs.value }

    public var description: String { value }
}

// MARK: - how far away a duck is, in time

/// What a link's delay has actually been measured to be.
///
/// SAMPLES RATHER THAN A NUMBER, BECAUSE THE SPREAD IS THE ANSWER. A single
/// figure for "the latency" is exactly the thing that makes a score look
/// synchronised on paper: correct the send time by it and every command lands
/// on the beat, in the model. Real links do not have a latency, they have a
/// distribution, and the width of that distribution is the floor on how tightly
/// two independent ducks can be made to move together. Keeping the samples is
/// what lets `Skew` report that floor instead of quietly assuming it away.
///
/// THE HALVING IS AN ASSUMPTION AND IT IS WORTH SAYING OUT LOUD. One-way delay
/// is taken as half of the round trip, which assumes the path is symmetric —
/// that a command takes as long to reach the duck as its answer takes to come
/// back. Nothing here has verified that, and on an asymmetric link (an uplink
/// sharing a channel with a video stream, say) it is wrong by half the
/// asymmetry. It is the same assumption NTP makes, and it is the standard
/// first-order error rather than a novel one; measuring one-way delay properly
/// would need a clock on the duck that this app can read, which
/// `duck-ipc-proto` does not offer.
public struct RoundTrip: Equatable, Sendable {

    /// Full round trips, seconds, ascending. Sorted at construction so the
    /// median and the extremes are reads rather than computations.
    public let samples: [Double]

    /// - Parameter samples: Measured round trips in seconds — a request sent
    ///   and its reply read, which is the only interval this app can time
    ///   without a clock on the duck.
    public init(samples: [Double]) throws {
        guard !samples.isEmpty else { throw Choreography.Problem.noSamples }
        for sample in samples where !sample.isFinite || sample < 0 {
            throw Choreography.Problem.notASecond(sample)
        }
        self.samples = samples.sorted()
    }

    /// One timing. HONEST BUT NOT USEFUL FOR SKEW: one sample cannot show
    /// jitter, and `Skew.isEvidenced` will say so rather than reporting a
    /// spread of zero as though it had been established.
    public init(seconds: Double) throws {
        try self.init(samples: [seconds])
    }

    public var fastest: Double { samples[0] }
    public var slowest: Double { samples[samples.count - 1] }

    /// The typical round trip: the lower median.
    ///
    /// A MEDIAN RATHER THAN A MEAN BECAUSE ONE STALL SHOULD NOT MOVE THE BEAT.
    /// Latency distributions have a long right tail — one retransmission, one
    /// radio scan, one garbage collection — and a mean chases that tail, so a
    /// single 400 ms outlier in twenty samples would shift every send time by
    /// twenty milliseconds. The LOWER median on an even count, rather than the
    /// average of the middle two, so the figure the schedule is built on is a
    /// delay that actually happened rather than one interpolated between two
    /// that did.
    ///
    /// ONE CONSEQUENCE IS WORTH KNOWING ABOUT WHERE IT BITES: on an even
    /// number of samples the lower median can BE the fastest sample, which
    /// makes `Skew.earliestSeconds` exactly zero. `Choreography.ms` is where
    /// that is handled, and its doc comment says why.
    public var typical: Double {
        samples.count % 2 == 1 ? samples[samples.count / 2] : samples[samples.count / 2 - 1]
    }

    public var oneWayTypical: Double { typical / 2 }
    public var oneWayFastest: Double { fastest / 2 }
    public var oneWaySlowest: Double { slowest / 2 }

    /// The width of the measured distribution, full round trip.
    public var jitterSeconds: Double { slowest - fastest }

    /// Whether these timings can say anything about jitter at all.
    ///
    /// ONE SAMPLE HAS A SPREAD OF ZERO AND THAT IS NOT A MEASUREMENT OF
    /// ANYTHING. It is the reason this flag exists rather than the code simply
    /// reporting `jitterSeconds`: a zero that means "perfectly steady link" and
    /// a zero that means "timed once" are the same number and opposite claims.
    public var isEvidenced: Bool { samples.count >= 2 }

    public var says: String {
        guard isEvidenced else {
            return "Timed once, at \(Choreography.ms(typical)) round trip — enough to aim a "
                 + "schedule with, not enough to know how far it will miss."
        }
        return "\(samples.count) timings: \(Choreography.ms(typical)) typical, "
             + "\(Choreography.ms(fastest)) to \(Choreography.ms(slowest)) round trip."
    }
}

// MARK: - bound one: what the schedule actually achieved

/// How far apart commands aimed at one instant can actually land.
///
/// THIS IS ACHIEVED, NOT REQUESTED, AND THE NAMING IS THE POINT. A score asks
/// for two ducks to turn at the same moment; what it gets is two commands
/// arriving at two instants some distance apart, and this type is that
/// distance. There is deliberately no way to ask for a skew — no target, no
/// tolerance, no `Skew(within:)` — because a requested skew is a promise, and
/// this app has no mechanism capable of keeping one: `duck-ipc-proto` has no
/// scheduled execution, no "start at time T", and no clock on the duck for such
/// a T to refer to. The commands are sent early and they land when they land.
///
/// WHERE THE NUMBER COMES FROM. Each duck's send time is pulled forward by that
/// link's TYPICAL one-way delay, so a command lands on the beat exactly when
/// the link behaves typically. When it does not, the command lands early by
/// however much faster the link ran, or late by however much slower. Those two
/// residuals, taken across every duck in the score, are the earliest and the
/// latest instant any of them can arrive at — and the spread between them is
/// the worst distance two ducks can be apart while both doing what they were
/// told. It is a bound from measured samples rather than a prediction: a link
/// that has never yet been slower than 90 ms may still be, and the bound moves
/// when it is.
///
/// A SCORE WITH ONE DUCK STILL REPORTS ITS OWN JITTER RATHER THAN ZERO. There
/// is nothing for a single duck to be out of step with, so a zero would be
/// defensible and it is not what this returns, because the figure a person
/// actually needs is "how far off the beat can this land", which is the same
/// number and is not zero. Rounding it down would be the claim of synchrony
/// this type exists to refuse.
///
/// AND IT COVERS EVERY DUCK IT WAS ASKED ABOUT OR IT REFUSES TO ANSWER. See
/// `across`: a bound that quietly skipped the ducks nobody had timed would be
/// describing a smaller score than the one about to be played, while
/// `isEvidenced` went on saying `true`.
public struct Skew: Equatable, Sendable {

    /// The earliest a command can land, relative to the instant it was aimed
    /// at. Zero or negative.
    public let earliestSeconds: Double

    /// The latest it can land. Zero or positive.
    public let latestSeconds: Double

    /// Which duck can be earliest and which can be latest. Nil only for a score
    /// with no ducks in it.
    public let earliestDuck: DuckID?
    public let latestDuck: DuckID?

    /// The fewest timings any one link in this score was measured with, which
    /// is what the whole figure is only as good as.
    public let leastSamples: Int

    public init(earliestSeconds: Double, latestSeconds: Double,
                earliestDuck: DuckID?, latestDuck: DuckID?, leastSamples: Int) {
        self.earliestSeconds = earliestSeconds
        self.latestSeconds = latestSeconds
        self.earliestDuck = earliestDuck
        self.latestDuck = latestDuck
        self.leastSamples = leastSamples
    }

    /// A score with nothing in it: nothing to be out of step.
    public static let silence = Skew(earliestSeconds: 0, latestSeconds: 0,
                                     earliestDuck: nil, latestDuck: nil, leastSamples: 0)

    /// The worst achieved spread.
    public var seconds: Double { latestSeconds - earliestSeconds }

    /// Whether every link in the score was timed more than once. WHEN THIS IS
    /// FALSE, `seconds` IS A FLOOR AND NOT A BOUND — a link timed once shows no
    /// jitter because nothing was there to compare, and the resulting zero is
    /// an absence of evidence rather than a steady link.
    public var isEvidenced: Bool { leastSamples >= 2 }

    /// What the screen says instead of "synchronised".
    ///
    /// PHRASED HERE RATHER THAN IN A VIEW, like every other sentence in this
    /// package, and phrased so that the good case is still not a claim of
    /// synchrony: "up to 12 ms apart" is a fact, "in sync" is a story.
    public var says: String {
        guard let earliestDuck, let latestDuck else {
            return "No ducks in this score, so nothing to be out of step."
        }
        guard isEvidenced else {
            return "Achieved skew: unmeasured. At least one link was timed only once, and one "
                 + "timing shows no spread at all — that is an absence of evidence, not a "
                 + "pair of ducks landing on the same beat."
        }
        if earliestDuck == latestDuck {
            return "Achieved skew: up to \(Choreography.ms(seconds)) — \(earliestDuck) can land "
                 + "\(Choreography.ms(-earliestSeconds)) early or "
                 + "\(Choreography.ms(latestSeconds)) late against the beat it was aimed at."
        }
        return "Achieved skew: up to \(Choreography.ms(seconds)) apart — \(earliestDuck) can "
             + "land \(Choreography.ms(-earliestSeconds)) early while \(latestDuck) lands "
             + "\(Choreography.ms(latestSeconds)) late. They were aimed at one instant; these "
             + "are the instants they can arrive at."
    }

    /// The spread across a set of links, each corrected by its own typical
    /// one-way delay.
    ///
    /// A DUCK WITH NO MEASUREMENT IS A REFUSAL AND NOT A SKIP, WHICH IS A
    /// CHANGE FROM WHAT THIS USED TO DO. It used to `continue` past any duck
    /// missing from `roundTrips` and return a bound built from the rest, with
    /// `isEvidenced` still reporting `true` — so a score of four ducks, one of
    /// them never timed, produced a confident sentence about three of them and
    /// named it the achieved skew of the performance. The duck left out is
    /// exactly the one whose link nobody knows anything about, which makes it
    /// the likeliest to be the one that misses the beat. `Score.schedule`
    /// already throws `unmeasuredLink` for this and always has; this is the
    /// same refusal in the same words, so the two cannot disagree about whether
    /// a score is runnable.
    ///
    /// TIES GO TO THE ALPHABETICALLY FIRST DUCK, which is why `ducks` is walked
    /// in sorted order rather than in dictionary order: two identical links
    /// must name the same duck on every run, or a test asserting the sentence
    /// fails intermittently. The refusal is ordered by the same rule, so the
    /// duck it names is the same one on every run too.
    ///
    /// - Throws: `Choreography.Problem.unmeasuredLink` for the first duck, in
    ///   sorted order, that has no entry in `roundTrips`.
    public static func across(_ ducks: [DuckID],
                              roundTrips: [DuckID: RoundTrip]) throws -> Skew {
        var earliest = 0.0, latest = 0.0
        var earliestDuck: DuckID?, latestDuck: DuckID?
        var leastSamples = Int.max

        for duck in ducks.sorted() {
            guard let trip = roundTrips[duck] else {
                throw Choreography.Problem.unmeasuredLink(duck)
            }
            leastSamples = min(leastSamples, trip.samples.count)
            let low = trip.oneWayFastest - trip.oneWayTypical
            let high = trip.oneWaySlowest - trip.oneWayTypical
            if earliestDuck == nil || low < earliest { earliest = low; earliestDuck = duck }
            if latestDuck == nil || high > latest { latest = high; latestDuck = duck }
        }

        guard earliestDuck != nil else { return .silence }
        return Skew(earliestSeconds: earliest, latestSeconds: latest,
                    earliestDuck: earliestDuck, latestDuck: latestDuck,
                    leastSamples: leastSamples == Int.max ? 0 : leastSamples)
    }
}

// MARK: - the score itself

/// A timed list of things to say to named ducks.
///
/// THE PLAYER-PIANO SENTENCE FROM THE TOP OF THIS FILE APPLIES TO THIS TYPE
/// MOST OF ALL, because this is the one somebody will build a screen around. A
/// `Score` is a roll of punched holes: it says what to send, to whom, and how
/// far after the downbeat. It contains no rule that reads one duck's state and
/// changes another duck's step, and it cannot be extended to contain one,
/// because the robot has no channel over which such a rule could be observed —
/// the 61-value observation has no slot for another robot.
///
/// A STEP HAS A TIME AND NO DURATION, WHICH IS THE ROBOT'S SHAPE AND NOT A
/// SIMPLIFICATION. The continuous intents EXPIRE: one `robot.move` notification
/// buys tens of milliseconds of walking and then the age-based gate takes the
/// command away. So "walk forward for two seconds" is not one step with a
/// length, it is a hundred and one steps at 50 Hz, and `holding` is the
/// function that says so in code. Giving `Step` a `duration` would let somebody
/// write a two-second walk that the robot ends after one frame, and the bug
/// would look like a robot that refuses to walk.
public struct Score: Equatable, Sendable {

    /// The most frames one `holding` will build.
    ///
    /// AN HOUR AT THE PAD'S RATE, AND THE CEILING EXISTS BECAUSE THE
    /// ALTERNATIVE WAS A CRASH. `holding` turns a duration into an array with
    /// one `Step` per frame, and the count came from `Int((seconds *
    /// hz).rounded())` on two numbers that were each checked for being finite
    /// and never checked as a product. A parsed score file with a large
    /// duration in it, or the ordinary milliseconds-for-seconds slip, produced
    /// a `Double` past `Int.max` and `Int(_:)` traps on that — so the app died
    /// rather than refusing, and it died inside the function whose entire job
    /// is to refuse things.
    ///
    /// AN HOUR RATHER THAN SOME ROUNDER NUMBER because a score is a
    /// performance and a performance is minutes: an hour is more than an order
    /// of magnitude of headroom over anything anybody punches deliberately, and
    /// past it the overwhelmingly likely explanation is a units mistake rather
    /// than an ambitious piece. It is derived from `Choreography.defaultRateHz`
    /// so that it stays an hour if the control rate ever moves.
    public static let frameCeiling = Int(3600 * Choreography.defaultRateHz)

    /// One thing to say, and when.
    public struct Step: Equatable, Sendable {

        /// Seconds after the downbeat. NOT a wall clock and not a robot clock —
        /// a position on the roll. `schedule` is where it becomes an instant.
        public let at: Double

        /// Which duck this hole is punched for.
        public let duck: DuckID

        /// What to say. `DuckCall` already knows whether it is a notification
        /// or a request, so a score does not have to carry that and cannot
        /// disagree with the contract about it.
        public let call: DuckCall

        public init(at: Double, duck: DuckID, call: DuckCall) {
            self.at = at
            self.duck = duck
            self.call = call
        }
    }

    /// Sorted by time, then by duck, then by the order they were given in.
    ///
    /// SORTED AT CONSTRUCTION SO EVERY LATER READ IS TOTAL. `seconds` is the
    /// last step's time, the emissions come out in send order, and two scores
    /// written in different orders with the same holes are `==`. Sorting later,
    /// per read, would be three chances to sort differently.
    public let steps: [Step]

    /// - Throws: `Choreography.Problem.stepOutOfOrder` for a step before the
    ///   downbeat or at a time that is not a number. A score runs forward from
    ///   zero; there is no instant before the start for a negative step to be
    ///   sent at, and a NaN step would silently never come due.
    public init(_ steps: [Step]) throws {
        for step in steps where !step.at.isFinite || step.at < 0 {
            throw Choreography.Problem.stepOutOfOrder(step.at)
        }
        self.steps = steps.enumerated().sorted { a, b in
            if a.element.at != b.element.at { return a.element.at < b.element.at }
            if a.element.duck != b.element.duck { return a.element.duck < b.element.duck }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// How long the score is: the last step's time. An empty score is zero
    /// seconds long, which is true and is not the same as "instant".
    public var seconds: Double { steps.last?.at ?? 0 }

    /// Every duck the score speaks to, in a defined order.
    public var ducks: [DuckID] {
        var seen = Set<DuckID>()
        var ordered: [DuckID] = []
        for step in steps where seen.insert(step.duck).inserted { ordered.append(step.duck) }
        return ordered.sorted()
    }

    /// What a duck's link has to carry for this score to be runnable on it.
    ///
    /// `robot.stop` IS IN HERE EVEN WHEN THE SCORE NEVER ASKS FOR ONE, because
    /// the abort path is part of the score rather than an extra: a duck that
    /// cannot be stopped cannot be in a performance that another duck's fault
    /// might have to abort.
    ///
    /// WHICH LINKS THAT RULES OUT IS `DuckMethod.reach(for:)`'S ANSWER AND NOT
    /// THIS COMMENT'S. There used to be a hand-copied set here — the five
    /// methods Bluetooth carries, written out in a doc comment — and a
    /// transcription of a table is a second copy of that table that nothing
    /// compares against the first, so a routing change in `DuckPeer` would have
    /// left this paragraph confidently describing the old columns. The tests
    /// ask `DuckMethod.reach(for:)` instead of restating it, so the day
    /// Bluetooth's row changes, an assertion moves rather than a comment
    /// rotting.
    public func methodsNeeded(of duck: DuckID) -> Set<DuckMethod> {
        var needed: Set<DuckMethod> = [.stop]
        for step in steps where step.duck == duck { needed.insert(step.call.method) }
        return needed
    }

    /// Whether a link that carries exactly `reach` can perform this score.
    ///
    /// A CONVENIENCE OVER `DuckPeer.vet`, NOT A REPLACEMENT FOR IT. `vet` is
    /// the gate every transport runs before it writes a byte, and it stays the
    /// authority; this is the same question asked once, up front, so a screen
    /// can grey out a duck instead of letting somebody start a performance that
    /// will refuse its first note.
    public func isPerformable(by duck: DuckID, over reach: Set<DuckMethod>) -> Bool {
        methodsNeeded(of: duck).isSubset(of: reach)
    }

    /// The same question about an actual peer.
    ///
    /// IT EXISTS SO A SCREEN DOES NOT HAVE TO REACH INTO `peer.reach` ITSELF,
    /// which is the small step that ends with a screen deciding what a link
    /// carries. See `DuckCast.vet` for the version that answers for a whole
    /// score at once and names what is missing rather than returning a `Bool`.
    public func isPerformable(by duck: DuckID, over peer: any DuckPeer) -> Bool {
        isPerformable(by: duck, over: peer.reach)
    }

    // MARK: - holding a continuous intent down

    /// The frames that hold one continuous intent for a while.
    ///
    /// THIS IS WHERE "FOR TWO SECONDS" BECOMES SOMETHING THE ROBOT WILL DO. A
    /// continuous intent is last-writer-wins and expiring, so a duck walks for
    /// exactly as long as frames keep arriving and then stops on its own. That
    /// is a safety property worth keeping — it is the same age-based gate that
    /// stops a duck whose driver vanished — and it means a held note is a
    /// repeat rate, not a duration field.
    ///
    /// THE FENCEPOST IS DELIBERATE. A one-second hold at 50 Hz is fifty-ONE
    /// frames: one on the downbeat and one on the final instant. Fifty frames
    /// would end the hold a frame early and leave the robot's expiry to finish
    /// the move, which is the deadman doing the app's job — it would work, and
    /// it would make every held note in every score end at a slightly different
    /// moment depending on the link.
    ///
    /// - Throws: `Choreography.Problem.notSustainable` for a discrete call. A
    ///   `robot.stop` repeated at 50 Hz is fifty answered requests a second
    ///   arriving at a robot that stopped after the first.
    /// - Throws: `Choreography.Problem.tooManyFrames` when the duration and the
    ///   rate MULTIPLY to something past `frameCeiling`. Both arguments are
    ///   checked on their own above and both can be perfectly reasonable while
    ///   their product is not, which is how the trap this replaces was reached.
    public static func holding(_ call: DuckCall, on duck: DuckID,
                               from start: Double, for seconds: Double,
                               hz: Double = Choreography.defaultRateHz) throws -> [Step] {
        guard call.isNotification else {
            throw Choreography.Problem.notSustainable(call.method)
        }
        guard hz.isFinite, hz > 0 else { throw Choreography.Problem.rateIsNotPositive(hz) }
        // A HELD NOTE SLOWER THAN THE ROBOT FORGETS IS NOT A HELD NOTE. A
        // continuous intent expires on robotd's age-based deadman, so frames
        // spaced further apart than that leave the duck stopping and starting
        // between them — which reads as a stuttering policy rather than as a
        // score built wrong. Pollen send `robot.move` at 20-50 Hz for this
        // reason; anything below the bottom of that band is refused by name.
        guard hz >= Choreography.slowestSustainedHz else {
            throw Choreography.Problem.rateTooSlowToHold(hz)
        }
        guard seconds.isFinite, seconds >= 0 else {
            throw Choreography.Problem.notASecond(seconds)
        }
        guard start.isFinite, start >= 0 else {
            throw Choreography.Problem.stepOutOfOrder(start)
        }
        // COUNTED IN `Double` AND CHECKED BEFORE IT BECOMES AN `Int`, because
        // `Int(_:)` is the trap: it is a runtime failure and not an error, so
        // there is no catching it and nothing to print. The comparison is made
        // in the wider type on purpose — converting first and comparing after
        // is the same crash with an extra line of code in front of it.
        let counted = (seconds * hz).rounded() + 1
        guard counted.isFinite, counted <= Double(frameCeiling) else {
            throw Choreography.Problem.tooManyFrames(seconds: seconds, hz: hz)
        }
        let frames = Int(counted)
        return (0..<frames).map { Step(at: start + Double($0) / hz, duck: duck, call: call) }
    }

    // MARK: - bound one: scheduling

    /// One command, aimed.
    ///
    /// IT NAMES A DUCK AND NOT A PEER, AND `DuckCast` IS HOW THE NAME BECOMES
    /// SOMETHING YOU CAN WRITE TO. Putting a `DuckPeer` in here would put a
    /// live connection inside a value that a test compares with `==` and that a
    /// plan holds hundreds of, and it would drag networking into the one
    /// package that is built to be run on Linux with no robot in the room.
    public struct Emission: Equatable, Sendable {

        /// When this app should hand the line to the transport, on the app's
        /// own clock — the same clock `startingAt` was given on.
        public let sendAt: Double

        /// When it is INTENDED to arrive. Intended, because the only thing
        /// standing behind it is a median of past round trips; `Skew` is how
        /// far from this it can actually be.
        public let landsAt: Double

        public let duck: DuckID
        public let call: DuckCall

        public init(sendAt: Double, landsAt: Double, duck: DuckID, call: DuckCall) {
            self.sendAt = sendAt
            self.landsAt = landsAt
            self.duck = duck
            self.call = call
        }
    }

    /// A score turned into send times, with the honest caveat attached.
    public struct Plan: Equatable, Sendable {

        /// The instant the plan was built for, on the app's clock.
        public let startedAt: Double

        /// How long the downbeat is delayed so that even the slowest link can
        /// be sent to early enough. See `schedule`.
        public let leadSeconds: Double

        /// Send order: by `sendAt`, then by duck, then by the score's order.
        public let emissions: [Emission]

        /// What this plan achieves, as opposed to what it aims at. THE FIELD IS
        /// ON THE PLAN RATHER THAN RETURNED BESIDE IT so that a caller cannot
        /// hold a schedule without holding its error bar.
        public let skew: Skew

        /// Each duck's typical one-way delay, kept so an abort can time its
        /// stops without re-consulting the measurements.
        public let oneWaySeconds: [DuckID: Double]

        public init(startedAt: Double, leadSeconds: Double, emissions: [Emission],
                    skew: Skew, oneWaySeconds: [DuckID: Double]) {
            self.startedAt = startedAt
            self.leadSeconds = leadSeconds
            self.emissions = emissions
            self.skew = skew
            self.oneWaySeconds = oneWaySeconds
        }

        public var ducks: [DuckID] { oneWaySeconds.keys.sorted() }

        /// When the last command is intended to land. Not when the ducks are
        /// finished: what a duck does after a command arrives is the duck's
        /// business and this app cannot see it.
        public var landsLastAt: Double { emissions.map(\.landsAt).max() ?? startedAt }

        public var says: String {
            guard !emissions.isEmpty else { return "An empty score. Nothing to send." }
            return "\(emissions.count) commands to \(ducks.count) "
                 + "\(ducks.count == 1 ? "duck" : "ducks"), over "
                 + String(format: "%.1f s", landsLastAt - startedAt - leadSeconds)
                 + ". Every duck is sent to early by its own measured delay, after a "
                 + "\(Choreography.ms(leadSeconds)) lead-in, so the commands land together "
                 + "rather than leaving together. " + skew.says
        }
    }

    /// Turn the roll into send times.
    ///
    /// `Plan.says` USED TO CLAIM "the slowest link is sent to first", AND THAT
    /// IS NOT WHAT THIS DOES. The lead-in is `max` over every duck's one-way
    /// delay, so the duck owning that maximum is sent to first only if it
    /// happens to have a step on the downbeat. Give the slow duck its first
    /// step two seconds in and a fast duck a step at zero, and the fast one is
    /// sent to first — correctly, because each is offset by ITS OWN delay
    /// rather than ordered against the others. The sentence now describes the
    /// rule instead of one of its consequences.
    ///
    /// THE WHOLE TRICK IS THAT COMMANDS LAND TOGETHER RATHER THAN LEAVING
    /// TOGETHER, and it is worth being precise about why the obvious version is
    /// wrong. Sending every duck its command at the same instant means the duck
    /// on the 20 ms link starts moving 60 ms before the duck on the 80 ms link,
    /// and a person watching sees exactly that: a stagger, in link order, that
    /// looks like one robot being slow. Sending each duck early by its own
    /// measured one-way delay removes the part of the stagger that was
    /// predictable, and leaves only the part that was not — which is `Skew`.
    ///
    /// THE LEAD-IN EXISTS BECAUSE YOU CANNOT SEND INTO THE PAST. If the score's
    /// downbeat were `startingAt` itself, the duck on the slowest link would
    /// have needed its command sent before the caller asked for the score at
    /// all. So the whole score is pushed back by the largest one-way delay in
    /// it: the first send happens at `startingAt`, to the slowest duck, and the
    /// downbeat lands one lead later. That is a real, visible cost — a score
    /// with one bad link starts late for everybody — and it is reported in
    /// `Plan.leadSeconds` rather than hidden, because the fix a person will
    /// want is to put that duck on a better link, and they cannot want it if
    /// they cannot see it.
    ///
    /// - Parameters:
    ///   - startingAt: An instant on the app's own monotonic clock, in seconds.
    ///     TAKEN AS A PARAMETER RATHER THAN READ FROM `Date()` — this package's
    ///     rule, and here it is the difference between a schedule that can be
    ///     asserted in a test and one that can only be watched.
    ///   - roundTrips: A measurement per duck in the score. A duck with no
    ///     entry is refused rather than assumed to be fast.
    public func schedule(startingAt: Double,
                         roundTrips: [DuckID: RoundTrip]) throws -> Plan {
        guard startingAt.isFinite else { throw Choreography.Problem.notASecond(startingAt) }

        var oneWay: [DuckID: Double] = [:]
        for duck in ducks {
            guard let trip = roundTrips[duck] else {
                throw Choreography.Problem.unmeasuredLink(duck)
            }
            oneWay[duck] = trip.oneWayTypical
        }

        let lead = oneWay.values.max() ?? 0
        let downbeat = startingAt + lead

        var built: [Emission] = []
        built.reserveCapacity(steps.count)
        for step in steps {
            guard let half = oneWay[step.duck] else {
                throw Choreography.Problem.unmeasuredLink(step.duck)
            }
            built.append(Emission(sendAt: downbeat + step.at - half,
                                  landsAt: downbeat + step.at,
                                  duck: step.duck, call: step.call))
        }

        // Send order, resolved totally: a tie on `sendAt` is broken by duck and
        // then by the score's own order, so the same score always produces the
        // same list of lines in the same sequence.
        let ordered = built.enumerated().sorted { a, b in
            if a.element.sendAt != b.element.sendAt { return a.element.sendAt < b.element.sendAt }
            if a.element.duck != b.element.duck { return a.element.duck < b.element.duck }
            return a.offset < b.offset
        }.map(\.element)

        return Plan(startedAt: startingAt, leadSeconds: lead, emissions: ordered,
                    skew: try Skew.across(ducks, roundTrips: roundTrips),
                    oneWaySeconds: oneWay)
    }
}

// MARK: - bound two: one writer per duck, and what this app can actually do about it

/// A note this app keeps about which of ITS OWN screens is driving which duck.
///
/// READ THE NEXT PARAGRAPH BEFORE BELIEVING THE NAME OF ANY METHOD BELOW. This
/// type used to be called `WriterRoll`, its entries were called tokens, and one
/// of them printed "nobody else can while it does". None of that was true and
/// none of it could have been: what is underneath is a `Dictionary` in this
/// process's memory. Two phones running this app each hold their own, both
/// empty; both would grant the same duck to their own operator, both would
/// print that sentence, and the two of them would then discover the fault
/// together.
///
/// WHAT IT ACTUALLY PREVENTS: this app driving one duck from two of its own
/// screens at once. That is worth preventing and it is a real bug — a drive
/// screen and a score screen open on the same duck is an ordinary way to arrive
/// at it. WHAT IT DOES NOTHING ABOUT: a second phone running this app, a
/// gamepad plugged into `padd`, `robotctl` on somebody's laptop, a bench
/// harness, or any other client anybody writes. None of those can see this
/// dictionary and none of them can be made to.
///
/// AN EXCLUSIVE CLAIM WOULD HAVE TO COME FROM THE DUCK, AND THE DUCK HAS NO
/// METHOD FOR IT. `duck-ipc-proto`'s whole surface is `hello`, the robot
/// intents (`robot.move`, `head`, `look`, `stop`, `enable`, `init`, `relax`),
/// `system.pairingPin` and `system.setPairingPin`, and the `update` family.
/// There is nothing in it a client can call to claim a duck, take a lease, or
/// even say who it is — so no amount of code on this side produces exclusion,
/// only a note to itself. `DuckPeer`, `BenchPeer` and `SimDuck` each say the
/// same sentence from their own end: the accepted fix is a single-writer token,
/// "which is a thing a duck hands out and therefore lives a layer above this".
/// Pollen have the work in their roadmap at M6 and mark it UNSOLVED.
///
/// THE FAULT THAT IS ONLY HALF PREVENTED IS WORTH DESCRIBING, because it is the
/// reason to keep an advisory rather than delete it and the reason its
/// sentences say what they say. `intents.rs` keeps ONE command slot and takes
/// the last write, so two clients each sending twists at 50 Hz do not fight for
/// control and do not take turns — their frames interleave into that single
/// slot, "producing a robot that obeys neither". The duck stands there, or
/// lurches, while both operators watch their own sticks doing nothing. Nobody
/// debugs that as contention; they debug it as a broken robot, and they debug
/// it for a long time, because each of them can see their own commands leaving.
/// Half of that — this app against itself — is a state this type can refuse.
/// The other half is a sentence a person has to be told, which is why
/// `Note.says` tells them.
public struct LocalWriterAdvisory: Equatable, Sendable {

    /// Which part of this app is doing the writing: a drive screen, a score
    /// screen, a bench harness in a test.
    ///
    /// IT IS NOT "WHO", IT IS "WHICH OF OURS". A writer here is always inside
    /// this process — there is no way for anything outside it to appear in this
    /// dictionary, so a name like "Ada's phone" would be a name for something
    /// this type has never heard of and cannot ever hear of.
    public struct Writer: Hashable, Sendable, CustomStringConvertible {
        public let name: String
        public init(_ name: String) { self.name = name }
        public var description: String { name }
    }

    /// One line in the note: this screen, this duck, until this instant.
    ///
    /// IT CARRIES ITS OWN EXPIRY RATHER THAN ASKING THE ADVISORY, so a note
    /// that has been passed to a run is still checkable after the advisory it
    /// came from has moved on. `isLive(at:)` is the only way to ask, and it
    /// takes the clock, because a note that decided for itself what time it was
    /// would be the hidden `Date()` this package does not allow.
    public struct Note: Equatable, Sendable {
        public let duck: DuckID
        public let driver: Writer
        public let notedAt: Double
        public let expiresAt: Double

        public init(duck: DuckID, driver: Writer, notedAt: Double, expiresAt: Double) {
            self.duck = duck
            self.driver = driver
            self.notedAt = notedAt
            self.expiresAt = expiresAt
        }

        public func isLive(at now: Double) -> Bool { now < expiresAt }

        /// THE SENTENCE THIS TYPE EXISTS TO GET RIGHT. It used to read "nobody
        /// else can while it does", which was the claim of exclusivity a
        /// process-local dictionary cannot make. What it says now is what is
        /// actually true from here: this app will not hand the duck to another
        /// of its own screens, and this app has no idea whether anything else
        /// is writing.
        public var says: String {
            "\(driver) is the screen this app is driving \(duck) from. That keeps this app's "
            + "other screens off it and nothing else: another phone, a gamepad or robotctl "
            + "could be writing to \(duck) at this moment, and there is no method in the "
            + "duck's protocol by which this app could claim it or find out."
        }
    }

    /// How long a note stands without renewal. See
    /// `Choreography.defaultNoteSeconds`.
    public let noteSeconds: Double

    private var notes: [DuckID: Note] = [:]

    /// - Note: A note that lasts no time at all is not a short note, it is no
    ///   advisory: `isLive(at: now)` is `now < now`, false immediately, so
    ///   every duck reads as undriven and the one thing this type does stops
    ///   happening — silently, with every method still returning success. A
    ///   non-positive or non-finite value is refused rather than honoured.
    public init(noteSeconds: Double = Choreography.defaultNoteSeconds) {
        precondition(noteSeconds.isFinite && noteSeconds > 0,
                     "A note has to last some seconds; \(noteSeconds) would switch the advisory "
                   + "off while leaving every call returning success.")
        self.noteSeconds = noteSeconds
    }

    /// Write down that one of this app's screens is driving one duck.
    ///
    /// RE-NOTING BY THE SAME SCREEN EXTENDS THE NOTE RATHER THAN FAILING,
    /// because that is what a running score does: a driving loop renews every
    /// frame, and an advisory that refused the second call would make driving a
    /// duck for longer than one note impossible.
    ///
    /// A RENEWAL NEVER SHORTENS A NOTE. `ScoreRun` extends its ducks' notes to
    /// cover the whole score it is playing, and a 50 Hz drive loop renewing the
    /// same duck two seconds at a time must not cut that back to two seconds
    /// and let the note lapse in the middle of a five-minute piece.
    ///
    /// - Parameter until: When the note should stand until, on the caller's
    ///   clock. Defaults to `noteSeconds` from now, which is the drive-loop
    ///   case; `ScoreRun` passes the end of its score instead.
    /// - Throws: `Choreography.Problem.alreadyDrivenInThisApp` when a different
    ///   screen of this app has a live note. The refusal names it, because
    ///   "the duck is busy" sends a person looking at the duck and "the drive
    ///   screen has it" sends them to the drive screen. It is NOT a claim that
    ///   nothing outside this app is writing.
    @discardableResult
    public mutating func note(_ duck: DuckID, driver: Writer, at now: Double,
                              through until: Double? = nil) throws -> Note {
        guard now.isFinite else { throw Choreography.Problem.notASecond(now) }
        let asked = until ?? (now + noteSeconds)
        guard asked.isFinite else { throw Choreography.Problem.notASecond(asked) }

        let live = notes[duck].flatMap { $0.isLive(at: now) ? $0 : nil }
        if let live, live.driver != driver {
            throw Choreography.Problem.alreadyDrivenInThisApp(duck, by: live.driver)
        }
        // A RENEWAL KEEPS ITS ORIGINAL `notedAt`, so "how long has this screen
        // been driving that duck" survives fifty renewals a second. A note that
        // had lapsed is a fresh start and its clock begins again, because in
        // between it was genuinely nobody's — as far as this app can see, which
        // is the only distance this type ever sees.
        let written = Note(duck: duck, driver: driver,
                           notedAt: live?.notedAt ?? now,
                           expiresAt: max(asked, live?.expiresAt ?? asked))
        notes[duck] = written
        return written
    }

    /// Rub the note out.
    ///
    /// - Throws: `Choreography.Problem.notTheNotedDriver` when the caller is
    ///   not the screen written down. A clearing that silently succeeded for
    ///   anybody would be a way for one screen to take a duck off another by
    ///   asking politely.
    public mutating func clear(_ duck: DuckID, from driver: Writer) throws {
        guard let existing = notes[duck], existing.driver == driver else {
            throw Choreography.Problem.notTheNotedDriver(duck, driver)
        }
        notes[duck] = nil
    }

    /// Which of this app's screens is driving this duck, if any. A lapsed note
    /// reads as none, which is the whole point of a note that lapses.
    ///
    /// A `nil` HERE MEANS "NOT FROM THIS APP", NOT "NOBODY". There is no
    /// question this type can be asked that would answer the second one.
    public func driver(of duck: DuckID, at now: Double) -> Writer? {
        guard let existing = notes[duck], existing.isLive(at: now) else { return nil }
        return existing.driver
    }

    public func isNoted(_ duck: DuckID, as driver: Writer, at now: Double) -> Bool {
        self.driver(of: duck, at: now) == driver
    }

    /// The sentence to put in front of somebody before a performance.
    ///
    /// IT IS HERE RATHER THAN IN A VIEW for the same reason every other
    /// sentence in this package is, and it exists at all because the note above
    /// is the moment a person is most likely to believe the ducks have been
    /// reserved for them.
    public var says: String {
        "The screens that share this advisory will not drive one duck from two places at once. "
        + "It cannot do more than that: the duck's protocol has no method for claiming a "
        + "writer, so a second phone, a "
        + "gamepad or robotctl can write to any of these ducks at any moment. The robot keeps "
        + "one command slot and takes the last write, so the first sign of that is a duck that "
        + "obeys neither of you rather than a duck that obeys the other one."
    }
}

// MARK: - the seam: which peer is which duck

/// Which peer is which duck, resolved once and refusing the ambiguities.
///
/// THE SEAM BETWEEN A SCORE AND SOMETHING YOU CAN ACTUALLY WRITE TO. A `Score`
/// names ducks by `DuckID` and an `Emission` carries one, and until this type
/// existed nothing in the package turned either into a `DuckPeer` — so every
/// screen that wanted to play a score hand-wrote its own id-to-peer loop, each
/// one keyed a little differently, and each one got the collision below wrong
/// in its own way.
///
/// IT CARRIES NO NETWORKING AND THAT IS DELIBERATE. What is here is a
/// dictionary and two refusals; the sending, the sleeping and the sockets stay
/// in the app, for exactly the reason `ScoreRun` gives about being asserted in
/// a unit test on Linux in microseconds. `DuckPeer` is `AnyObject` because a
/// transport is a connection, so this type holds references and is not
/// `Equatable`: two casts over one set of peers are the same links, and
/// comparing them by value would be comparing sockets.
///
/// BUILD THE CAST FIRST AND WRITE THE SCORE AGAINST `ducks`. That order is what
/// makes the name collision below a refusal at the top of a screen instead of a
/// duck that silently never moves.
public struct DuckCast: Sendable {

    private let peers: [DuckID: any DuckPeer]

    /// - Throws: `Choreography.Problem.sameKeyTwice` when two peers answer to
    ///   one name. THIS IS THE ONE PLACE A NAME BECOMES A KEY, and it refuses
    ///   rather than letting the second peer overwrite the first, because
    ///   `SimDuckConfig.stock()` calls every duck it makes "Duck" and two stock
    ///   simulators is the second thing anybody tries. The silent version costs
    ///   a duck that stands still through a whole score while every screen in
    ///   the app looks correct.
    public init(_ peers: [any DuckPeer]) throws {
        var built: [DuckID: any DuckPeer] = [:]
        for peer in peers {
            let key = DuckID(peer.identity.name)
            guard built[key] == nil else {
                throw Choreography.Problem.sameKeyTwice(peer.identity.name)
            }
            built[key] = peer
        }
        self.peers = built
    }

    /// The keys a score written against this cast may use, in a defined order.
    public var ducks: [DuckID] { peers.keys.sorted() }

    public func peer(for duck: DuckID) -> (any DuckPeer)? { peers[duck] }

    /// The line's destination.
    ///
    /// - Throws: `Choreography.Problem.unknownDuck` when the cast has no peer
    ///   for it. A `nil` here would be a line quietly dropped in the middle of
    ///   a performance, which is the failure this whole file is arranged to
    ///   turn into a refusal.
    public func peer(for emission: Score.Emission) throws -> any DuckPeer {
        guard let found = peers[emission.duck] else {
            throw Choreography.Problem.unknownDuck(emission.duck)
        }
        return found
    }

    /// Every refusal this score is going to meet, asked before it starts.
    ///
    /// `DuckPeer.vet` REMAINS THE AUTHORITY AND THIS DOES NOT REPLACE IT. `vet`
    /// runs on every single call inside every transport, which is where it has
    /// to be; this asks the same question once for a whole score so that the
    /// answer arrives while a person is looking at a start button rather than
    /// as a row of commands refused one at a time by name in front of an
    /// audience. Note that `methodsNeeded` always includes `robot.stop`, so a
    /// link that cannot stop a duck fails here even for a score that never asks
    /// for one — the abort path is part of the score.
    ///
    /// - Throws: `Choreography.Problem.unknownDuck` for a name with no peer,
    ///   and `Choreography.Problem.linkCannotCarry` naming exactly what the
    ///   link is missing. Ducks are walked in the score's own sorted order, so
    ///   the duck named is the same one on every run.
    public func vet(_ score: Score) throws {
        for duck in score.ducks {
            guard let peer = peers[duck] else {
                throw Choreography.Problem.unknownDuck(duck)
            }
            let missing = score.methodsNeeded(of: duck).subtracting(peer.reach)
            guard missing.isEmpty else {
                throw Choreography.Problem.linkCannotCarry(duck, missing)
            }
        }
    }
}

// MARK: - bound three: performing, and stopping everything

/// A plan being played out against a clock somebody else owns.
///
/// NO TIMERS AND NO TASKS IN HERE, ON PURPOSE. This is a state machine that is
/// told what time it is and answers with the lines that are now due; the thing
/// that actually sleeps and writes bytes lives in the app, over a `DuckPeer` it
/// found through a `DuckCast`. That split is why a whole performance —
/// including the abort — can be asserted in a unit test on Linux in
/// microseconds, and it is the same split every other engine in this package
/// uses.
///
/// IT IS HANDED THE ADVISORY ON EVERY ADVANCE AND THAT IS A FIX FOR A REAL BUG.
/// This type used to take the advisory by value in `init`, check that it held
/// every duck once, and then keep neither the advisory nor the notes; `due` never
/// asked again. The default note is two seconds and a score is minutes, so every
/// real performance ran on a note that had lapsed in its first bar, another of
/// this app's screens could take a duck in the middle of it, and the run went on
/// reporting itself as the driver of ducks it had not checked since the downbeat.
/// So `due` now takes the advisory `inout`: it renews every duck through the end
/// of the score on each advance, and a renewal it cannot get is a fault like any
/// other — the score ends and every duck is stopped. A type in this file does not
/// report a state it has not just verified.
///
/// STOPPING EVERYTHING IS THE POINT OF THIS TYPE. The robot's deadman is
/// `safety.gate(command, twist_age)`: age-based, and evaluated on each robot
/// about its own commands. That is exactly right for one duck and it has a
/// sharp edge for several. When one duck's link partitions, that duck's
/// commands age out and it stops — correctly, promptly, with no help from this
/// app — and every other duck plays the rest of the score at a partner that is
/// no longer moving. It cannot notice: there is no slot in its 61-value
/// observation for another robot. Nobody in the system except this app is in a
/// position to know that the piece has fallen apart, so the abort is this
/// app's: one fault stops all of them.
///
/// THE STOPS GO TO EVERY DUCK INCLUDING THE ONE THAT FAULTED. Two reasons, and
/// neither is thoroughness for its own sake. First, a fault is not proof of a
/// partition — a duck that refused one call by name is perfectly reachable and
/// will keep walking on its last twist unless told otherwise. Second, when it
/// really has gone, the stop costs one write into a socket nobody is reading,
/// while the robot's own age-based gate does the actual stopping. The expensive
/// mistake is the other way round.
public struct ScoreRun: Equatable, Sendable {

    /// Why a performance ended early.
    public struct Fault: Equatable, Sendable {

        /// The duck whose trouble this was, or nil when there was none to
        /// blame.
        ///
        /// OPTIONAL BECAUSE `abandon` HAD NOTHING TRUE TO PUT HERE. A person
        /// pressing the stop button is not a duck dropping out, and this field
        /// used to be filled anyway: with `plan.ducks.first` on a score that
        /// had ducks — so the sentence blamed whichever duck sorted first for a
        /// thing a person did — and with `DuckID("")` on a score that had none,
        /// which rendered as " dropped out: …", a sentence beginning with a
        /// space and naming a duck that does not exist.
        public let duck: DuckID?

        /// What went wrong, in the words of whoever noticed — a refusal
        /// message from `DuckReply.Failure.says`, a transport error, a person
        /// pressing the button.
        public let reason: String

        /// When, on the app's clock.
        public let atSeconds: Double

        public init(duck: DuckID?, reason: String, atSeconds: Double) {
            self.duck = duck
            self.reason = reason
            self.atSeconds = atSeconds
        }

        public var says: String {
            let aftermath = "The score is off, and every duck in it has been sent a stop — the "
                          + "others cannot tell that anything happened, so nothing but this app "
                          + "was going to end it."
            guard let duck else {
                return "The score was ended: \(reason). \(aftermath)"
            }
            return "\(duck) dropped out: \(reason). \(aftermath)"
        }
    }

    public enum Phase: Equatable, Sendable {
        /// Built, its ducks noted for the length of the score, nothing sent
        /// yet.
        case waiting
        /// At least one command has gone out.
        case running
        /// Every command has been handed to a transport. NOT "the ducks are
        /// done": what a duck did with a command is not visible from here, and
        /// `Plan.skew` is the size of the gap between the two claims.
        case finished
        /// Something faulted, everything was stopped, and nothing more will be
        /// sent from this run.
        case abandoned(Fault)
    }

    public let plan: Score.Plan

    /// Which of this app's screens is playing this. NOT an exclusive claim on
    /// these ducks — see `LocalWriterAdvisory`, which is where the limits of
    /// that word are written down.
    public let driver: LocalWriterAdvisory.Writer

    public private(set) var phase: Phase
    /// How many of the plan's emissions have been handed out.
    public private(set) var sent: Int = 0
    /// The furthest forward this run has been told the clock is.
    public private(set) var clockReached: Double

    /// - Parameter advisory: Taken `inout` because the run does not merely read
    ///   it — it extends every one of its ducks' notes to cover the whole
    ///   score, so that a five-minute piece is not built on a two-second note
    ///   that lapses before the first bar is over.
    /// - Throws: `Choreography.Problem.notNotedForThisScore` for the first duck
    ///   in the plan this screen is not noted as driving. THIS IS BOUND TWO'S
    ///   GATE, and it is worth being exact about what it gates: it stops this
    ///   app playing a score against a duck another of its own screens is
    ///   driving. It says nothing about a second phone, and it cannot.
    public init(plan: Score.Plan, driver: LocalWriterAdvisory.Writer,
                advisory: inout LocalWriterAdvisory, at now: Double) throws {
        guard now.isFinite else { throw Choreography.Problem.notASecond(now) }
        for duck in plan.ducks where !advisory.isNoted(duck, as: driver, at: now) {
            throw Choreography.Problem.notNotedForThisScore(duck, driver)
        }
        self.plan = plan
        self.driver = driver
        self.clockReached = now
        self.phase = plan.emissions.isEmpty ? .finished : .waiting

        if let lost = renew(at: now, in: &advisory) {
            throw Choreography.Problem.notNotedForThisScore(lost, driver)
        }
    }

    /// Extend every note in this plan to cover the rest of the score.
    ///
    /// THROUGH THE END OF THE SCORE PLUS ONE NOTE'S WORTH OF SLACK, rather than
    /// through one note's worth from now, so that an app which polls slowly —
    /// or a score with a long gap in the middle of it — does not drop its own
    /// notes between advances and find them taken. The slack past the last
    /// landing is there so `due` at the final instant is still inside the note
    /// it is checking.
    ///
    /// - Returns: The first duck, in plan order, whose note could not be
    ///   renewed, or nil if every one of them stands.
    private func renew(at now: Double,
                       in advisory: inout LocalWriterAdvisory) -> DuckID? {
        let through = max(now, plan.landsLastAt) + advisory.noteSeconds
        for duck in plan.ducks {
            do {
                try advisory.note(duck, driver: driver, at: now, through: through)
            } catch {
                return duck
            }
        }
        return nil
    }

    /// The lines that are due by `now`, in send order.
    ///
    /// A CLOCK THAT WENT BACKWARDS IS IGNORED RATHER THAN OBEYED. Nothing due
    /// is ever un-sent, so rewinding could only re-send commands that have
    /// already gone — which for a discrete call means asking a duck to stand up
    /// twice, and for a notification means a stale twist landing after a fresh
    /// one in a slot that keeps the last write. The caller is expected to pass
    /// a monotonic clock; this is what happens when it does not.
    ///
    /// THE NOTES ARE RE-ASKED HERE AND NOT ONLY AT THE DOWNBEAT. That is the
    /// whole reason this takes the advisory: a run that checked once and never
    /// again would spend a minutes-long score reporting itself the driver of
    /// ducks another screen had taken, on the strength of a two-second note
    /// nobody had renewed. When a note cannot be renewed the run ABANDONS and
    /// this method returns the stops rather than the next notes — the caller's
    /// loop sends what it is given either way, and `phase` is how it finds out
    /// which it got.
    ///
    /// - Parameter advisory: Taken `inout` because every advance renews. A run
    ///   that has finished or been abandoned renews nothing: it is over, and
    ///   holding the ducks after that would be this app keeping something it is
    ///   not using.
    public mutating func due(at now: Double,
                             in advisory: inout LocalWriterAdvisory) -> [Score.Emission] {
        guard now.isFinite, now >= clockReached else { return [] }
        clockReached = now
        switch phase {
        case .finished, .abandoned:
            return []
        case .waiting, .running:
            break
        }
        if let lost = renew(at: now, in: &advisory) {
            return end(blaming: lost,
                       "this app's note that \(driver) was driving it is gone — it lapsed while "
                     + "nothing was being sent, and another of this app's screens has taken it "
                     + "since",
                       at: now, in: &advisory)
        }
        var out: [Score.Emission] = []
        while sent < plan.emissions.count, plan.emissions[sent].sendAt <= now {
            out.append(plan.emissions[sent])
            sent += 1
        }
        if sent >= plan.emissions.count {
            phase = .finished
        } else if !out.isEmpty {
            phase = .running
        }
        return out
    }

    /// How many commands are still to go out.
    public var remaining: Int { plan.emissions.count - sent }

    /// One duck is in trouble: end the score and stop every duck in it.
    ///
    /// - Returns: A `robot.stop` for each duck in the plan, in duck order, to
    ///   be sent immediately. Empty if this run was already abandoned, because
    ///   a second fault must not produce a second round of stops for a score
    ///   that is already over.
    @discardableResult
    public mutating func fault(_ duck: DuckID, _ reason: String, at now: Double,
                               in advisory: inout LocalWriterAdvisory) -> [Score.Emission] {
        end(blaming: duck, reason, at: now, in: &advisory)
    }

    /// The same abort, without a duck to blame — the button a person presses.
    ///
    /// NOTHING IS BLAMED, WHICH IS A CHANGE. This used to forward to
    /// `fault(plan.ducks.first!, …)`, so a person pressing stop produced "ada
    /// dropped out: hands off the sticks" about a duck that had done nothing
    /// wrong — and on a plan with no ducks in it, `Fault(duck: DuckID(""))`,
    /// which rendered as a sentence beginning with a space and naming a duck
    /// that does not exist. `Fault.duck` is optional now and this passes nil.
    @discardableResult
    public mutating func abandon(_ reason: String, at now: Double,
                                 in advisory: inout LocalWriterAdvisory) -> [Score.Emission] {
        end(blaming: nil, reason, at: now, in: &advisory)
    }

    /// The one path that ends a run, so that the two doors into it cannot come
    /// to differ about what ending means.
    ///
    /// IT GIVES THE NOTES BACK, AND THE FIRST VERSION DID NOT. `renew` extends
    /// every duck's note through the END OF THE SCORE plus slack — deliberately,
    /// so a slow-polling app does not drop its own notes between advances. The
    /// consequence, when a run ends early, is that those notes outlive it by the
    /// whole remaining length of a score that is no longer playing. A person
    /// pressing stop on a five-minute piece at ten seconds locked their own
    /// ducks for the other four-fifty, and the refusal another screen then got
    /// named the screen that had pressed stop — which by then could not send
    /// another byte. A note is a claim that something is driving; nothing is.
    private mutating func end(blaming duck: DuckID?, _ reason: String, at now: Double,
                              in advisory: inout LocalWriterAdvisory) -> [Score.Emission] {
        if case .abandoned = phase { return [] }
        clockReached = max(clockReached, now.isFinite ? now : clockReached)
        phase = .abandoned(Fault(duck: duck, reason: reason, atSeconds: clockReached))
        // CLEARED FOR THIS DRIVER ONLY. `clear` refuses a duck this run does not
        // hold, which is exactly the duck whose note was taken from under it —
        // the one that caused the fault. Ending must not throw, so a refusal
        // here is the expected case and is dropped.
        for duck in plan.ducks {
            try? advisory.clear(duck, from: driver)
        }
        return stops(at: clockReached)
    }

    /// A stop aimed at every duck in the plan.
    ///
    /// SENT NOW, NOT SCHEDULED. `Score.schedule`'s lead-in exists so commands
    /// LAND together, and paying it here would delay every stop by the slowest
    /// link's delay in order to make the ducks stop tidily in unison. A stop is
    /// the one command where landing early is strictly better than landing
    /// together, so `sendAt` is the fault's own instant for all of them and
    /// `landsAt` is simply when each one gets there — staggered, and honestly
    /// so, because a stop cannot be synchronised either.
    public func stops(at now: Double) -> [Score.Emission] {
        plan.ducks.map { duck in
            Score.Emission(sendAt: now,
                           landsAt: now + (plan.oneWaySeconds[duck] ?? 0),
                           duck: duck, call: .stop)
        }
    }

    public var says: String {
        switch phase {
        case .waiting:
            // THE CAVEAT GOES HERE AND NOWHERE ELSE IN THIS SWITCH, because
            // this is the moment somebody is about to start a performance and
            // is most likely to believe the ducks have been reserved for them.
            // Repeating it while the score plays would put it on a screen fifty
            // times a second, where it would be read once and then never again.
            return "Ready. \(plan.emissions.count) commands to go. \(plan.skew.says) "
                 + "Nothing here has claimed these ducks against anybody outside this app: "
                 + "another phone, a gamepad or robotctl can write to any of them at any "
                 + "point, and the first sign of it would be a duck that obeys neither of you."
        case .running:
            return "Playing — \(remaining) commands to go. \(plan.skew.says)"
        case .finished:
            return "Every command has been sent. What the ducks did with them is not something "
                 + "this app can see: they carry no sense of each other, so the only evidence "
                 + "of the piece is in the room. \(plan.skew.says)"
        case .abandoned(let fault):
            return fault.says
        }
    }
}
