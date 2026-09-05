import Foundation

/// One scene's trials, reduced, with the eight parallel arrays built from them
/// rather than beside them.
///
/// RAGGEDNESS IS MADE UNREACHABLE RATHER THAN CHECKED FOR. Their schema puts
/// trial `i`'s verdict, termination reason, metadata and messages at index `i`
/// of four separate arrays. Any code that appended to them independently would
/// eventually append to five of six, and the file would then file one trial's
/// verdict against another trial's score with nothing to show for it. Here
/// there is one list of trials and every array is a `map` over it, so a short
/// one cannot be written.
public struct EvalSceneResult: Equatable, Sendable, Identifiable {

    public let scene: EvalScene
    public let reducer: EvalEpochs.Reducer
    public let trials: [EvalTrial]
    /// A fault that belongs to the scene rather than to one trial: a reducer
    /// that threw, or a halt. Not set merely because a trial errored.
    public let error: String?

    public var id: String { scene.id }

    public init(scene: EvalScene, reducer: EvalEpochs.Reducer, trials: [EvalTrial],
                error: String? = nil) {
        self.scene = scene
        self.reducer = reducer
        self.trials = trials
        self.error = error
    }

    /// Their scene status: `error` as soon as one trial errored, which is what
    /// `eval.py` does. The RUN's status is a different question, answered in
    /// `EvalRun`.
    public var status: EvalLog.Status {
        if error != nil { return .error }
        if trials.contains(where: { $0.status == .error }) { return .error }
        if trials.contains(where: { $0.status == .cancelled }) { return .cancelled }
        return .success
    }

    /// One entry per trial, empty for a trial that was not scored, which is how
    /// an errored trial stays visible without being counted.
    public var epochValues: [[String: Double]] { trials.map(\.scores) }

    /// Every scorer name that got at least one value, reduced.
    public var reduced: [String: Double] {
        var byName: [String: [Double]] = [:]
        for trial in trials where trial.wasScored {
            for (name, value) in trial.scores { byName[name, default: []].append(value) }
        }
        var out: [String: Double] = [:]
        for (name, values) in byName {
            if let value = EvalEpochs.reduce(values, with: reducer) { out[name] = value }
        }
        return out
    }

    public var terminationReasons: [String?] { trials.map(\.terminationReason) }
    public var operatorJudgements: [String?] { trials.map { $0.verdict?.answer.rawValue } }
    public var judgementSources: [String?] { trials.map { $0.verdict?.source.rawValue } }
    public var operatorNotes: [String?] { trials.map { $0.verdict?.note } }
    /// Always empty here. Their `operator_messages` is live feedback drained
    /// during a trial, and nothing on this phone drains any.
    public var operatorMessages: [[EvalLogJSON]] { trials.map { _ in [] } }
    /// Always null here. Their `policy_transcripts` is a policy's own audit
    /// record, and a network has none to give.
    public var policyTranscripts: [EvalLogJSON] { trials.map { _ in .null } }

    /// Each trial's own metadata, plus the three facts every trial has whatever
    /// route it came from. The keys are `EvalMeta`'s, which is the one place
    /// this project's own key names are spelled.
    ///
    /// THE REASON IS IN `EvalMeta.why`. Their schema has one `error` per scene,
    /// so a scene of eight drops where two diverged has one reason and loses
    /// the other. Each reason goes in its own trial's metadata instead, where
    /// their reader passes it through and both reports print it beside the
    /// trial it belongs to.
    public var trialMetadata: [[String: EvalLogJSON]] {
        trials.map { trial in
            var metadata = trial.metadata
            metadata[EvalMeta.ticksReported] = .maybe(trial.ticks)
            metadata[EvalMeta.traced] = .bool(trial.trace != nil)
            if let why = trial.error { metadata[EvalMeta.why] = .string(why) }
            return metadata
        }
    }

    public var erroredTrials: Int { trials.filter { $0.status == .error }.count }

    /// Control ticks this scene actually reported.
    public var reportedSteps: Int { trials.compactMap(\.ticks).reduce(0, +) }
}

/// A finished run: what it was, what it measured, and what it will not claim.
///
/// EVERY DERIVED NUMBER IS COMPUTED HERE AND NOWHERE ELSE. The app target draws
/// and does not compute (`scripts/check_no_studio_math.sh`), so a metric tile,
/// an epoch grid and a share are all read off this type. That is not only a
/// house rule: `metrics` is a mean over scenes, and a second mean written in a
/// `View` would be the second implementation that quietly disagrees.
public struct EvalRun: Equatable, Sendable {

    public let task: EvalTask
    public let policy: EvalPolicy
    public let embodiment: EvalEmbodiment
    public let startedAt: Date
    public let completedAt: Date
    public let scenes: [EvalSceneResult]
    public let wasCancelled: Bool
    /// A fault that stopped the whole run: the plant changed under it, a tail
    /// the task never declared came back, or the bench stopped answering. In
    /// this app's words, and it becomes the log's own `error`.
    public let haltedBy: String?

    public init(task: EvalTask, policy: EvalPolicy, embodiment: EvalEmbodiment,
                startedAt: Date, completedAt: Date, scenes: [EvalSceneResult],
                wasCancelled: Bool, haltedBy: String? = nil) {
        self.task = task
        self.policy = policy
        self.embodiment = embodiment
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.scenes = scenes
        self.wasCancelled = wasCancelled
        self.haltedBy = haltedBy
    }

    // MARK: - the derived numbers

    public var totalTrials: Int { scenes.reduce(0) { $0 + $1.trials.count } }
    public var erroredTrials: Int { scenes.reduce(0) { $0 + $1.erroredTrials } }

    /// L9. Only ticks a route actually reported. Never seconds times a rate.
    public var totalSteps: Int { scenes.reduce(0) { $0 + $1.reportedSteps } }

    public var durationSeconds: Double { completedAt.timeIntervalSince(startedAt) }

    /// `metrics[name]` is the arithmetic mean over the scenes whose `reduced`
    /// carries it, and is absent where no scene carries it. That is
    /// `eval.py`'s rule exactly, mean of means over scenes rather than a mean
    /// over trials, so a scene with more epochs does not weigh more.
    public var metrics: [String: Double] {
        var out: [String: Double] = [:]
        for scorer in task.scorers.scorers {
            let values = scenes.compactMap { $0.reduced[scorer.name] }
            guard !values.isEmpty else { continue }
            out[scorer.name] = values.reduce(0, +) / Double(values.count)
        }
        return out
    }

    /// Scorers that produced a value no JSON file can hold.
    ///
    /// THE NAME IS SHOWN AND THE VALUE IS NULLED. `json_log._sanitize` maps a
    /// non-finite float to null, which is correct and is also invisible: a
    /// metric that quietly became null is a metric nobody investigates. So the
    /// value goes to null in the file the way theirs does, and the scorer's
    /// name comes back out here for the screen.
    public var nonFiniteScores: [String] {
        var names = Set<String>()
        for scene in scenes {
            for trial in scene.trials {
                for (name, value) in trial.scores where !value.isFinite { names.insert(name) }
            }
        }
        return names.sorted()
    }

    /// The four rules, in order, each with a test.
    ///
    /// A DIVERGED EPISODE DOES NOT MAKE THE RUN AN ERROR. It makes the trial an
    /// error and the scene an error, which is what `eval.py` does, and the run
    /// goes on: two failed episodes out of twenty-four is data about the policy
    /// rather than a broken run. The run itself is an error only when it was
    /// halted, when a scene's own reduction failed, or when there was nothing
    /// left to score at all.
    public var status: EvalLog.Status {
        if wasCancelled { return .cancelled }
        if haltedBy != nil { return .error }
        if scenes.contains(where: { $0.error != nil }) { return .error }
        if totalTrials > 0, erroredTrials == totalTrials { return .error }
        return .success
    }

    public var error: String? {
        if let haltedBy { return haltedBy }
        if let sceneError = scenes.compactMap(\.error).first { return sceneError }
        if totalTrials > 0, erroredTrials == totalTrials { return Self.allTrialsErrored(totalTrials) }
        return nil
    }

    /// Whether any trial in the run came back with a trajectory, which is the
    /// only honest reason to claim the `renderable` capability.
    public var anyTrialTraced: Bool {
        scenes.contains { $0.trials.contains { $0.trace != nil } }
    }

    // MARK: - the sentences

    /// UPSTREAM'S OWN WORDING, CHARACTER FOR CHARACTER (`eval.py`). A run where
    /// every trial errored and the log said success would hide a total failure,
    /// and saying it in their words means a reader who has seen one of their
    /// logs recognises this one.
    public static func allTrialsErrored(_ count: Int) -> String {
        "all \(count) trial(s) errored; nothing was scored"
    }

    /// L17. The first answer's plant is the run's; a later answer with a
    /// different one stops everything.
    public static func plantChangedMidRun(from: String, to: String) -> String {
        "The bench changed world in the middle of this run, from "
      + "\(from.prefix(DuckBench.digestShown)) to \(to.prefix(DuckBench.digestShown)). The "
      + "scenes before the change and the scenes after it are not one measurement, so the run "
      + "stopped rather than mixing them."
    }

    /// L18. A grid score quoted against a tail nobody ran.
    public static func tailNotDeclared(declared: Int, reported: Int) -> String {
        "This task declared a \(declared) tick tail and the harness scored a \(reported) tick "
      + "one. The tail is what standing at the end means, so the two numbers are not the same "
      + "measurement and this trial was recorded rather than scored."
    }

    public static let erroredNotScoredSaid =
        "Errored trials are recorded and never scored. They are in the log with the reason the "
      + "bench gave, they are counted, and they are not in any average, because a partial trial "
      + "counted as data is how a broken run reads as a good one."

    /// Two sentences, for `policy_config`.
    public static let stepCountsSaid =
        "total steps counts only control ticks a route actually reported. This bench reports "
      + "them for the one traced episode of each scene and for no other, so the number is the "
      + "traced episodes and nothing else, and every trial says whether it was one of them."

    public static let noLatencySaid =
        "Nothing here timed the policy. The phone times a round trip over Wi-Fi to another "
      + "machine, which is a network measurement, and writing it down as inference time would be "
      + "one number wearing another's name."

    public static let noFramesSaid =
        "No frames were stored. Their frame store writes side cars beside the log, and a path to "
      + "a directory that will not exist on the reader's machine is a claim rather than a "
      + "record."

    /// The two fixed clauses `producerSaid` is made of, spelled once so the
    /// sentence and the reader of it below cannot drift apart. A parser holding
    /// its own copy of the words it is looking for is a parser that goes on
    /// finding nothing after somebody improves the sentence.
    static let producerLead = "none; written by "
    static let producerTail = ". No inspect-robots ran: an iPhone cannot run Python."

    /// `eval.inspect_robots_version`, which their own report prints verbatim in
    /// its footer. A version number there would say a Python library ran.
    public static func producerSaid(version: String, build: String) -> String {
        producerLead + EvalLogWriter.wroteIt(version: version, build: build) + producerTail
    }

    /// The `Microduck Studio 1.1 (58)` clause back out of a log's own producer
    /// sentence, or nil for one this app did not write.
    ///
    /// IT COMES OUT OF THE LOG AND NOT OFF THE RUNNING BUILD, which is the
    /// whole point of reading it rather than stamping it: an archived log was
    /// written by whichever build made the run, and today's version on it would
    /// make every old file claim to be new. Nil is what
    /// `EvalReport.shareSentence` turns into `passedOnSaid`, which is the
    /// honest thing to say about a file that arrived from somewhere else.
    public static func wroteItSaid(from producer: String) -> String? {
        guard producer.hasPrefix(producerLead), producer.hasSuffix(producerTail) else {
            return nil
        }
        let start = producer.index(producer.startIndex, offsetBy: producerLead.count)
        let end = producer.index(producer.endIndex, offsetBy: -producerTail.count)
        guard start < end else { return nil }
        return String(producer[start..<end])
    }

    // MARK: - how long to wait

    /// Thirty seconds for the health probe, the way `StairsRun` does it.
    public static let probeSeconds = 30

    /// One `/tune` call answers every drop of a scene, so the wait is the
    /// physics plus the transport rather than a fixed number somebody guessed:
    /// eight six second drops is forty-eight seconds of simulation before a
    /// byte moves.
    public static func callTimeout(seconds: Double, episodes: Int) -> Int {
        Swift.max(180, Int((seconds * Double(episodes)).rounded(.up)) + 90)
    }
}
