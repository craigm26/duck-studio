import Foundation
import DuckKit

/// One episode: what it scored, why it ended, what a person made of it, and the
/// ticks it was watched through.
///
/// AN ERRORED TRIAL CANNOT CARRY A SCORE, AND THAT IS A CONSTRUCTOR AND NOT A
/// CONVENTION. Upstream records errored trials and never scores them, which is
/// the rule that keeps a run of thirty trials where eleven failed from
/// reporting an average over nineteen as though it were an average over thirty.
/// The initialiser drops `scores` whenever the status is not `success`, so
/// there is no call site anywhere that can push half a number through.
public struct EvalTrial: Equatable, Sendable {

    /// Their three words for how one trial ended.
    public enum Status: String, Equatable, Sendable, CaseIterable {
        case success, error, cancelled
    }

    public let sceneID: String
    /// Zero based, and it is the index into every parallel array in the log.
    public let epoch: Int
    public let status: Status
    /// Empty unless the status is `success`.
    public let scores: [String: Double]
    /// Their `termination_reasons` entry. Nil for anything that was not a
    /// success, which is what their own writer does.
    public let terminationReason: String?
    /// Control ticks this trial actually reported, or nil where the route
    /// reported none. Never seconds multiplied by a rate.
    public let ticks: Int?
    /// The bench's own words when it refused or diverged. Foreign text: draw it
    /// through `EvalText.foreign`, keep it whole in the log.
    public let error: String?
    public let metadata: [String: EvalLogJSON]
    /// Nil unless this trial has a trace, because a verdict on a run nobody
    /// could watch is a verdict about nothing.
    public let verdict: EvalVerdict?
    public let trace: EvalTrace?

    public init(sceneID: String, epoch: Int, status: Status, scores: [String: Double],
                terminationReason: String?, ticks: Int?, error: String?,
                metadata: [String: EvalLogJSON], verdict: EvalVerdict?, trace: EvalTrace?) {
        self.sceneID = sceneID
        self.epoch = epoch
        self.status = status
        // L8 and L21, both structural. A score or a verdict that should not
        // exist is dropped here rather than checked for later.
        self.scores = status == .success ? scores : [:]
        self.terminationReason = status == .success ? terminationReason : nil
        self.ticks = ticks
        self.error = error
        self.metadata = metadata
        self.verdict = trace == nil ? nil : verdict
        self.trace = trace
    }

    /// A trial the bench scored.
    public static func scored(sceneID: String, epoch: Int, scores: [String: Double],
                              terminationReason: String, ticks: Int?,
                              metadata: [String: EvalLogJSON],
                              verdict: EvalVerdict? = nil,
                              trace: EvalTrace? = nil) -> EvalTrial {
        EvalTrial(sceneID: sceneID, epoch: epoch, status: .success, scores: scores,
                  terminationReason: terminationReason, ticks: ticks, error: nil,
                  metadata: metadata, verdict: verdict, trace: trace)
    }

    /// A trial that was recorded and not scored. The bench's own words go in
    /// `why`, because a diverged episode has a reason and a tick number and
    /// this app has no better account of either.
    public static func errored(sceneID: String, epoch: Int, why: String,
                               metadata: [String: EvalLogJSON] = [:]) -> EvalTrial {
        EvalTrial(sceneID: sceneID, epoch: epoch, status: .error, scores: [:],
                  terminationReason: nil, ticks: nil, error: why,
                  metadata: metadata, verdict: nil, trace: nil)
    }

    public var wasScored: Bool { status == .success }
}

/// The one episode of a scene anybody could actually watch.
///
/// WHY THERE IS ONLY EVER ONE. `/tune` returns a trajectory for the FIRST drop
/// of a call and no other, capped at 500 ticks, which at `DuckModel.tickHz` is
/// ten seconds. That cap is why the horizon here stops at ten seconds: a traced
/// trial whose tick count was a truncation would be a recording that quietly
/// stops before the episode does.
public struct EvalTrace: Equatable, Sendable {

    /// The bench's `TRACE_CAP`, verified in `duckbench-core.mjs`.
    public static let cap = 500

    /// Per tick: the trunk's pose, MuJoCo's own free joint velocity, the same
    /// velocity as the trunk's own twist, the fourteen joint angles, the
    /// network's fourteen outputs, and the command.
    public let ticks: [DuckBench.Tuned.Tick]
    /// The drop height this trace belongs to, so it can never be shown against
    /// the wrong trial.
    public let dropHeight: Double
    /// The bench's own explanation of what a trace is. Foreign text.
    public let why: String?

    public init(ticks: [DuckBench.Tuned.Tick], dropHeight: Double, why: String?) {
        self.ticks = ticks
        self.dropHeight = dropHeight
        self.why = why
    }

    /// Whether the recording ran into the cap, which is the one thing a person
    /// watching it needs to know before they judge the ending.
    public var wasCapped: Bool { ticks.count >= Self.cap }

    public static let firstDropOnlySaid =
        "The bench returns a trajectory for the first drop of each call only, capped at 500 "
      + "ticks. That one episode is the only one anybody could watch, so it is the only one a "
      + "verdict was offered on."

    /// The other route, said where the sentence above would be a description of
    /// a mechanism the run did not use.
    ///
    /// A GRID CELL IS SCORED BY THE HARNESS AND NOT WATCHED. `/climb` and
    /// `/chase` answer with the cell's numbers and no ticks, so there is no
    /// recording, the verdict toggle has nothing to offer a person, and
    /// `total_steps` is zero. A log that carried the trace sentence anyway
    /// would be claiming an episode existed that nobody could produce.
    public static let noTraceOnAGridSaid =
        "Nothing was recorded to watch. A grid cell is scored by the harness, which answers with "
      + "the cell's own numbers and no trajectory, so there is no episode to play and no verdict "
      + "to give on one."
}

/// What a person made of the one trial they watched.
///
/// IT IS RECORDED AND IT IS NOT A SCORE. Their schema has three parallel fields
/// for exactly this, `operator_judgements`, `judgement_sources` and
/// `operator_notes`, and they are separate from `epochs` on purpose. One trial
/// of eight is watchable here, so a verdict turned into a metric would be an
/// average over one trial wearing an average's name, and a test asserts that no
/// scorer set anywhere contains `operator`.
public struct EvalVerdict: Equatable, Sendable {

    /// Their vocabulary, and only theirs. `_OPERATOR_SUCCESS` treats `yes` as a
    /// success and neither of the other two, so inventing a fourth word would
    /// make a log this app wrote read differently in their tools.
    public enum Answer: String, Equatable, Sendable, CaseIterable {
        case yes, no, partial

        public var said: String {
            switch self {
            case .yes: return "It did what the scene asked"
            case .no: return "It did not"
            case .partial: return "Partly"
            }
        }
    }

    /// Which path produced the verdict. `console`, `prompt`, `embodiment` and
    /// `vlm` are theirs; this app only ever writes `prompt`, because the only
    /// path here is a person answering a question on a screen.
    public enum Source: String, Equatable, Sendable, CaseIterable {
        case console, prompt, embodiment, vlm
    }

    public let answer: Answer
    public let source: Source
    /// The operator's own words. Foreign text on every screen it reaches: it
    /// goes into the log whole and is drawn through `EvalText.foreign`.
    public let note: String?

    public init(answer: Answer, source: Source = .prompt, note: String?) {
        self.answer = answer
        self.source = source
        self.note = note
    }

    public static let watchBeforeYouJudge =
        "Play the trial before you answer. A verdict on a run nobody watched is exactly the "
      + "kind of number this screen exists to keep out of a log."

    public static let recordedNotScoredSaid =
        "The bench returns a trajectory for the first drop of each scene only, so one trial in "
      + "eight is one a person could watch. Your verdict is written into the log beside that "
      + "trial and is not turned into a score, because an average over the one trial anybody saw "
      + "would be a number wearing an average's name."

    public static let vocabularySaid =
        "The three answers are inspect-robots' own: yes, no and partial, with the source "
      + "recorded beside each one. Keeping their words means a log written on this phone reads "
      + "in their tools the same way as one written anywhere else."
}
