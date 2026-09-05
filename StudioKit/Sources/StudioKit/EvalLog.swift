import Foundation

/// The evaluation log, exactly as inspect-robots defines it, and THE ONLY FILE
/// IN THIS PACKAGE THAT SPELLS ONE OF ITS FORTY WIRE KEYS.
///
/// WHY ONE FILE. A schema key written in two places is a schema with two
/// spellings, and the second one is always found by somebody reading a file
/// that will not open. `scripts/check_evallog_schema.sh` asserts that each of
/// the forty quoted key literals below appears in exactly this file and nowhere
/// under `DuckStudio/Sources`. Everything else in the app therefore reaches a
/// field through a named Swift property, and there is no second opinion about
/// what a key is called.
///
/// WHY NOTHING IS EVER ADDED TO THE SCHEMA. Their reader is
/// `EvalLog.from_dict`, which builds `EvalSpec(**data["eval"])`: one extra key
/// in that object is `TypeError: EvalSpec.__init__() got an unexpected keyword
/// argument`, measured this session against 0.58.0. So every app-specific fact
/// this project wants to record rides inside one of the four free-form maps,
/// `policy_config`, `embodiment_info`, `scene_metadata` or `trial_metadata`,
/// which their reader passes through untouched.
///
/// The five structs are theirs, name for name: `EvalLog`, `EvalSpec`,
/// `EvalResults`, `EvalStats` and `SceneResult`, which is `Sample` here so it
/// cannot be confused with `EvalSceneResult`, the run-side type in
/// `EvalRun.swift` that a scene is reduced into before it becomes one of these.
public struct EvalLog: Equatable, Sendable {

    /// Their `SCHEMA_VERSION`. `read_eval_log` refuses anything else, by
    /// design, so this is a hard number rather than a range.
    public static let schemaVersion = 1

    /// Their four words. `started` exists in their vocabulary for a log written
    /// while a run is still going; this app writes a log only when a run has
    /// stopped, so it never writes that one, and it can still read one.
    public enum Status: String, Equatable, Sendable, CaseIterable {
        case started, success, error, cancelled
    }

    public let version: Int
    public let status: Status
    public let eval: Spec
    public let results: Results
    public let stats: Stats
    public let samples: [Sample]
    public let error: String?

    public init(status: Status, eval: Spec, results: Results, stats: Stats,
                samples: [Sample], error: String?) {
        self.version = Self.schemaVersion
        self.status = status
        self.eval = eval
        self.results = results
        self.stats = stats
        self.samples = samples
        self.error = error
    }

    /// Used only by the reader, so a file that carries a version can be told
    /// apart from one this app built.
    init(version: Int, status: Status, eval: Spec, results: Results, stats: Stats,
         samples: [Sample], error: String?) {
        self.version = version
        self.status = status
        self.eval = eval
        self.results = results
        self.stats = stats
        self.samples = samples
        self.error = error
    }

    // MARK: - the spec

    public struct Spec: Equatable, Sendable {
        public let task: String
        public let policy: String
        public let embodiment: String
        /// ISO 8601 with a UTC offset, the way `datetime.now(UTC).isoformat()`
        /// writes it.
        public let created: String
        /// Which library wrote this. This app writes a sentence here that names
        /// itself and denies them, because their own report prints this field
        /// verbatim in its footer and a version number there would say a Python
        /// library ran.
        public let inspectRobotsVersion: String
        public let gitCommit: String?
        public let policyConfig: [String: EvalLogJSON]
        public let embodimentInfo: [String: EvalLogJSON]
        /// ALWAYS NIL FOR A RUN THIS APP MADE, AND THERE IS NO PARAMETER FOR
        /// IT. No route on this bench reads a seed, so a number here would name
        /// a control nothing used. It is a stored property rather than a
        /// computed `nil` only so a log written elsewhere reads back with the
        /// seed it really had.
        public let seed: Int?
        public let maxSteps: Int?
        public let maxSeconds: Double?

        /// The only public way to build one, and it takes no seed.
        public init(task: String, policy: String, embodiment: String, created: String,
                    producer: String, policyConfig: [String: EvalLogJSON],
                    embodimentInfo: [String: EvalLogJSON],
                    maxSteps: Int?, maxSeconds: Double?) {
            self.task = task
            self.policy = policy
            self.embodiment = embodiment
            self.created = created
            self.inspectRobotsVersion = producer
            // Deliberately null. A commit baked into a build can go stale, and
            // their viewer renders a missing one as "git unknown", which is
            // accurate.
            self.gitCommit = nil
            self.policyConfig = policyConfig
            self.embodimentInfo = embodimentInfo
            self.seed = nil
            self.maxSteps = maxSteps
            self.maxSeconds = maxSeconds
        }

        init(task: String, policy: String, embodiment: String, created: String,
             inspectRobotsVersion: String, gitCommit: String?,
             policyConfig: [String: EvalLogJSON], embodimentInfo: [String: EvalLogJSON],
             seed: Int?, maxSteps: Int?, maxSeconds: Double?) {
            self.task = task
            self.policy = policy
            self.embodiment = embodiment
            self.created = created
            self.inspectRobotsVersion = inspectRobotsVersion
            self.gitCommit = gitCommit
            self.policyConfig = policyConfig
            self.embodimentInfo = embodimentInfo
            self.seed = seed
            self.maxSteps = maxSteps
            self.maxSeconds = maxSeconds
        }
    }

    // MARK: - the results

    public struct Results: Equatable, Sendable {
        public let totalScenes: Int
        public let totalTrials: Int
        public let metrics: [String: Double]
        public let erroredTrials: Int

        public init(totalScenes: Int, totalTrials: Int,
                    metrics: [String: Double], erroredTrials: Int) {
            self.totalScenes = totalScenes
            self.totalTrials = totalTrials
            self.metrics = metrics
            self.erroredTrials = erroredTrials
        }
    }

    // MARK: - the stats

    public struct Stats: Equatable, Sendable {
        public let startedAt: String
        public let completedAt: String
        public let durationSeconds: Double
        /// Control ticks a route actually reported, and nothing else. Never
        /// seconds multiplied by a tick rate.
        public let totalSteps: Int
        /// Always nil for a run this app made: the phone times a round trip
        /// over Wi-Fi to another machine, which is not the policy's inference
        /// time, and reporting one as the other would be a network measurement
        /// wearing a model's name.
        public let meanInferenceLatencySeconds: Double?
        /// Always nil for a run this app made: their `FrameStore` writes side
        /// cars beside the log, and a path to a directory that will not exist
        /// on the reader's machine is a claim rather than a record.
        public let framesDir: String?

        public init(startedAt: String, completedAt: String, durationSeconds: Double,
                    totalSteps: Int) {
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.durationSeconds = durationSeconds
            self.totalSteps = totalSteps
            self.meanInferenceLatencySeconds = nil
            self.framesDir = nil
        }

        init(startedAt: String, completedAt: String, durationSeconds: Double, totalSteps: Int,
             meanInferenceLatencySeconds: Double?, framesDir: String?) {
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.durationSeconds = durationSeconds
            self.totalSteps = totalSteps
            self.meanInferenceLatencySeconds = meanInferenceLatencySeconds
            self.framesDir = framesDir
        }
    }

    // MARK: - one scene

    /// Their `SceneResult`. EIGHT PARALLEL ARRAYS, and they are parallel or the
    /// file lies: entry `i` of every one of them describes trial `i` of this
    /// scene, so a ragged set would put one trial's verdict beside another
    /// trial's score. `EvalSceneResult` builds them all from one list of trials
    /// and cannot build them ragged; the test asserts the eight lengths agree.
    public struct Sample: Equatable, Sendable {
        public let sceneID: String
        public let status: Status
        public let reduced: [String: Double]
        public let epochs: [[String: Double]]
        public let error: String?
        public let instruction: String?
        public let sceneMetadata: [String: EvalLogJSON]
        public let operatorJudgements: [String?]
        public let judgementSources: [String?]
        public let operatorNotes: [String?]
        public let operatorMessages: [[EvalLogJSON]]
        public let trialMetadata: [[String: EvalLogJSON]]
        public let terminationReasons: [String?]
        public let policyTranscripts: [EvalLogJSON]

        public init(sceneID: String, status: Status, reduced: [String: Double],
                    epochs: [[String: Double]], error: String?, instruction: String?,
                    sceneMetadata: [String: EvalLogJSON], operatorJudgements: [String?],
                    judgementSources: [String?], operatorNotes: [String?],
                    operatorMessages: [[EvalLogJSON]],
                    trialMetadata: [[String: EvalLogJSON]], terminationReasons: [String?],
                    policyTranscripts: [EvalLogJSON]) {
            self.sceneID = sceneID
            self.status = status
            self.reduced = reduced
            self.epochs = epochs
            self.error = error
            self.instruction = instruction
            self.sceneMetadata = sceneMetadata
            self.operatorJudgements = operatorJudgements
            self.judgementSources = judgementSources
            self.operatorNotes = operatorNotes
            self.operatorMessages = operatorMessages
            self.trialMetadata = trialMetadata
            self.terminationReasons = terminationReasons
            self.policyTranscripts = policyTranscripts
        }

        /// The eight arrays that have to agree, by name, so a test can say
        /// which one is short.
        public var parallelLengths: [String: Int] {
            [Key.epochs: epochs.count,
             Key.operatorJudgements: operatorJudgements.count,
             Key.judgementSources: judgementSources.count,
             Key.operatorNotes: operatorNotes.count,
             Key.operatorMessages: operatorMessages.count,
             Key.trialMetadata: trialMetadata.count,
             Key.terminationReasons: terminationReasons.count,
             Key.policyTranscripts: policyTranscripts.count]
        }
    }

    // MARK: - the forty keys

    /// EVERY WIRE KEY, ONCE. Nothing else in either shipping tree may spell one
    /// of these, and `scripts/check_evallog_schema.sh` is what makes that true
    /// rather than intended.
    public enum Key {
        // top level, 7
        public static let error = "error"
        public static let eval = "eval"
        public static let results = "results"
        public static let samples = "samples"
        public static let stats = "stats"
        public static let status = "status"
        public static let version = "version"
        // eval, 11
        public static let created = "created"
        public static let embodiment = "embodiment"
        public static let embodimentInfo = "embodiment_info"
        public static let gitCommit = "git_commit"
        public static let inspectRobotsVersion = "inspect_robots_version"
        public static let maxSeconds = "max_seconds"
        public static let maxSteps = "max_steps"
        public static let policy = "policy"
        public static let policyConfig = "policy_config"
        public static let seed = "seed"
        public static let task = "task"
        // results, 4
        public static let erroredTrials = "errored_trials"
        public static let metrics = "metrics"
        public static let totalScenes = "total_scenes"
        public static let totalTrials = "total_trials"
        // stats, 6
        public static let completedAt = "completed_at"
        public static let durationSeconds = "duration_s"
        public static let framesDir = "frames_dir"
        public static let meanInferenceLatencySeconds = "mean_inference_latency_s"
        public static let startedAt = "started_at"
        public static let totalSteps = "total_steps"
        // one sample, 14
        public static let epochs = "epochs"
        public static let instruction = "instruction"
        public static let judgementSources = "judgement_sources"
        public static let operatorJudgements = "operator_judgements"
        public static let operatorMessages = "operator_messages"
        public static let operatorNotes = "operator_notes"
        public static let policyTranscripts = "policy_transcripts"
        public static let reduced = "reduced"
        public static let sceneID = "scene_id"
        public static let sceneMetadata = "scene_metadata"
        public static let terminationReasons = "termination_reasons"
        public static let trialMetadata = "trial_metadata"

        /// The union, which is forty because `error` and `status` sit at two
        /// levels each. The schema guard reads this list from the plan rather
        /// than from here, so the two are independent statements of the same
        /// fact.
        public static let all: [String] = [
            error, eval, results, samples, stats, status, version,
            created, embodiment, embodimentInfo, gitCommit, inspectRobotsVersion,
            maxSeconds, maxSteps, policy, policyConfig, seed, task,
            erroredTrials, metrics, totalScenes, totalTrials,
            completedAt, durationSeconds, framesDir, meanInferenceLatencySeconds,
            startedAt, totalSteps,
            epochs, instruction, judgementSources, operatorJudgements, operatorMessages,
            operatorNotes, policyTranscripts, reduced, sceneID, sceneMetadata,
            terminationReasons, trialMetadata,
        ]

        /// Which keys each object may carry, so the reader can name the object
        /// an unknown key sat in rather than just the key.
        static let topLevel: Set<String> = [error, eval, results, samples, stats, status, version]
        static let spec: Set<String> = [created, embodiment, embodimentInfo, gitCommit,
                                        inspectRobotsVersion, maxSeconds, maxSteps, policy,
                                        policyConfig, seed, task]
        static let resultsBlock: Set<String> = [erroredTrials, metrics, totalScenes, totalTrials]
        static let statsBlock: Set<String> = [completedAt, durationSeconds, framesDir,
                                              meanInferenceLatencySeconds, startedAt, totalSteps]
        static let sample: Set<String> = [epochs, error, instruction, judgementSources,
                                          operatorJudgements, operatorMessages, operatorNotes,
                                          policyTranscripts, reduced, sceneID, sceneMetadata,
                                          status, terminationReasons, trialMetadata]
    }

    // MARK: - writing it

    /// The whole log as a value tree, ready for `EvalLogJSON.encoded()`.
    ///
    /// EVERY KEY IS WRITTEN, INCLUDING THE NULL ONES, because their writer is
    /// `dataclasses.asdict` and writes every field. A log that dropped its null
    /// fields would still parse for them and would not be the same bytes, and
    /// the byte comparison is the only fidelity claim that can be checked
    /// without running their library.
    public var json: EvalLogJSON {
        .object([
            Key.error: .maybe(error),
            Key.eval: eval.json,
            Key.results: results.json,
            Key.samples: .array(samples.map(\.json)),
            Key.stats: stats.json,
            Key.status: .string(status.rawValue),
            Key.version: .integer(version),
        ])
    }

    public func encoded() -> Data { json.encoded() }
}

extension EvalLog.Spec {
    public var json: EvalLogJSON {
        .object([
            EvalLog.Key.created: .string(created),
            EvalLog.Key.embodiment: .string(embodiment),
            EvalLog.Key.embodimentInfo: .object(embodimentInfo),
            EvalLog.Key.gitCommit: .maybe(gitCommit),
            EvalLog.Key.inspectRobotsVersion: .string(inspectRobotsVersion),
            EvalLog.Key.maxSeconds: .maybe(maxSeconds),
            EvalLog.Key.maxSteps: .maybe(maxSteps),
            EvalLog.Key.policy: .string(policy),
            EvalLog.Key.policyConfig: .object(policyConfig),
            EvalLog.Key.seed: .maybe(seed),
            EvalLog.Key.task: .string(task),
        ])
    }
}

extension EvalLog.Results {
    public var json: EvalLogJSON {
        .object([
            EvalLog.Key.erroredTrials: .integer(erroredTrials),
            EvalLog.Key.metrics: .numbers(metrics),
            EvalLog.Key.totalScenes: .integer(totalScenes),
            EvalLog.Key.totalTrials: .integer(totalTrials),
        ])
    }
}

extension EvalLog.Stats {
    public var json: EvalLogJSON {
        .object([
            EvalLog.Key.completedAt: .string(completedAt),
            EvalLog.Key.durationSeconds: .number(durationSeconds),
            EvalLog.Key.framesDir: .maybe(framesDir),
            EvalLog.Key.meanInferenceLatencySeconds: .maybe(meanInferenceLatencySeconds),
            EvalLog.Key.startedAt: .string(startedAt),
            EvalLog.Key.totalSteps: .integer(totalSteps),
        ])
    }
}

extension EvalLog.Sample {
    public var json: EvalLogJSON {
        .object([
            EvalLog.Key.epochs: .array(epochs.map { EvalLogJSON.numbers($0) }),
            EvalLog.Key.error: .maybe(error),
            EvalLog.Key.instruction: .maybe(instruction),
            EvalLog.Key.judgementSources: .array(judgementSources.map { EvalLogJSON.maybe($0) }),
            EvalLog.Key.operatorJudgements:
                .array(operatorJudgements.map { EvalLogJSON.maybe($0) }),
            EvalLog.Key.operatorMessages: .array(operatorMessages.map { EvalLogJSON.array($0) }),
            EvalLog.Key.operatorNotes: .array(operatorNotes.map { EvalLogJSON.maybe($0) }),
            EvalLog.Key.policyTranscripts: .array(policyTranscripts),
            EvalLog.Key.reduced: .numbers(reduced),
            EvalLog.Key.sceneID: .string(sceneID),
            EvalLog.Key.sceneMetadata: .object(sceneMetadata),
            EvalLog.Key.status: .string(status.rawValue),
            EvalLog.Key.terminationReasons: .array(terminationReasons.map { EvalLogJSON.maybe($0) }),
            EvalLog.Key.trialMetadata: .array(trialMetadata.map { EvalLogJSON.object($0) }),
        ])
    }
}

// MARK: - reading one

/// Why a file is not an evaluation log, in the file's own vocabulary.
///
/// AS STRICT AS `EvalLog.from_dict`, ON PURPOSE. Their reader raises on an
/// unknown key because it builds a frozen dataclass by keyword; a reader here
/// that shrugged one off would let this app display a log their own tools
/// refuse to open, which is worse than refusing it. So an unknown key is named,
/// and so is the object it sat in, because `status` in the wrong object is a
/// different fault from `status` missing.
public enum EvalLogRefusal: Error, Equatable {
    case notJSON(String)
    case notAnObject(String)
    case unsupportedVersion(String)
    case unknownKey(String, in: String)
    case missing(String, in: String)
    case wrongType(String, in: String, wanted: String)

    public var message: String {
        switch self {
        case .notJSON(let why):
            return why
        case .notAnObject(let what):
            return "That file's \(what) is not a JSON object, so there is nothing to read."
        case .unsupportedVersion(let found):
            return "That log says it is version \(found). This app reads version "
                 + "\(EvalLog.schemaVersion), which is the only version inspect-robots reads too."
        case .unknownKey(let key, let object):
            return "That log has a key this schema has no field for: \(key), inside \(object). "
                 + "Their own reader refuses it as well, so showing it here would be a promise "
                 + "this file cannot keep."
        case .missing(let key, let object):
            return "That log has no \(key) inside \(object), and the schema requires one."
        case .wrongType(let key, let object, let wanted):
            return "That log's \(key) inside \(object) is not \(wanted)."
        }
    }
}

extension EvalLog {

    public static func decoded(from data: Data) throws -> EvalLog {
        let json: EvalLogJSON
        do { json = try EvalLogJSON.parse(data) }
        catch let error as EvalLogJSON.ParseError { throw EvalLogRefusal.notJSON(error.message) }
        return try decoded(from: json)
    }

    public static func decoded(from json: EvalLogJSON) throws -> EvalLog {
        let top = try object(json, "the log")
        try refuseUnknown(top, allowed: Key.topLevel, object: "the log")
        let version = try integer(top, Key.version, in: "the log")
        guard version == schemaVersion else {
            throw EvalLogRefusal.unsupportedVersion(String(version))
        }
        return EvalLog(
            version: version,
            status: try status(top, Key.status, in: "the log"),
            eval: try Spec(top[Key.eval] ?? .null),
            results: try Results(top[Key.results] ?? .null),
            stats: try Stats(top[Key.stats] ?? .null),
            samples: try (top[Key.samples]?.arrayValue ?? []).map { try Sample($0) },
            error: optionalString(top, Key.error))
    }

    // MARK: field readers, which are the same three shapes over and over

    static func object(_ json: EvalLogJSON?, _ name: String) throws -> [String: EvalLogJSON] {
        guard let members = json?.objectValue else { throw EvalLogRefusal.notAnObject(name) }
        return members
    }

    static func refuseUnknown(_ members: [String: EvalLogJSON], allowed: Set<String>,
                              object name: String) throws {
        for key in members.keys.sorted() where !allowed.contains(key) {
            throw EvalLogRefusal.unknownKey(key, in: name)
        }
    }

    static func string(_ members: [String: EvalLogJSON], _ key: String,
                       in name: String) throws -> String {
        guard let value = members[key] else { throw EvalLogRefusal.missing(key, in: name) }
        guard let text = value.stringValue else {
            throw EvalLogRefusal.wrongType(key, in: name, wanted: "text")
        }
        return text
    }

    static func optionalString(_ members: [String: EvalLogJSON], _ key: String) -> String? {
        members[key]?.stringValue
    }

    static func integer(_ members: [String: EvalLogJSON], _ key: String,
                        in name: String) throws -> Int {
        guard let value = members[key] else { throw EvalLogRefusal.missing(key, in: name) }
        guard let number = value.integerValue else {
            throw EvalLogRefusal.wrongType(key, in: name, wanted: "a whole number")
        }
        return number
    }

    static func double(_ members: [String: EvalLogJSON], _ key: String,
                       in name: String) throws -> Double {
        guard let value = members[key] else { throw EvalLogRefusal.missing(key, in: name) }
        guard let number = value.doubleValue else {
            throw EvalLogRefusal.wrongType(key, in: name, wanted: "a number")
        }
        return number
    }

    static func status(_ members: [String: EvalLogJSON], _ key: String,
                       in name: String) throws -> Status {
        let word = try string(members, key, in: name)
        guard let value = Status(rawValue: word) else {
            throw EvalLogRefusal.wrongType(key, in: name,
                                           wanted: "one of "
                                                 + Status.allCases.map(\.rawValue)
                                                     .joined(separator: ", "))
        }
        return value
    }

    static func doubleMap(_ json: EvalLogJSON?) -> [String: Double] {
        var out: [String: Double] = [:]
        for (key, value) in json?.objectValue ?? [:] { out[key] = value.doubleValue }
        return out
    }
}

extension EvalLog.Spec {
    init(_ json: EvalLogJSON) throws {
        let members = try EvalLog.object(json, "eval")
        try EvalLog.refuseUnknown(members, allowed: EvalLog.Key.spec, object: "eval")
        self.init(
            task: try EvalLog.string(members, EvalLog.Key.task, in: "eval"),
            policy: try EvalLog.string(members, EvalLog.Key.policy, in: "eval"),
            embodiment: try EvalLog.string(members, EvalLog.Key.embodiment, in: "eval"),
            created: try EvalLog.string(members, EvalLog.Key.created, in: "eval"),
            inspectRobotsVersion: try EvalLog.string(members,
                                                     EvalLog.Key.inspectRobotsVersion, in: "eval"),
            gitCommit: EvalLog.optionalString(members, EvalLog.Key.gitCommit),
            policyConfig: members[EvalLog.Key.policyConfig]?.objectValue ?? [:],
            embodimentInfo: members[EvalLog.Key.embodimentInfo]?.objectValue ?? [:],
            seed: members[EvalLog.Key.seed]?.integerValue,
            maxSteps: members[EvalLog.Key.maxSteps]?.integerValue,
            maxSeconds: members[EvalLog.Key.maxSeconds]?.doubleValue)
    }
}

extension EvalLog.Results {
    init(_ json: EvalLogJSON) throws {
        let members = try EvalLog.object(json, "results")
        try EvalLog.refuseUnknown(members, allowed: EvalLog.Key.resultsBlock, object: "results")
        self.init(
            totalScenes: try EvalLog.integer(members, EvalLog.Key.totalScenes, in: "results"),
            totalTrials: try EvalLog.integer(members, EvalLog.Key.totalTrials, in: "results"),
            metrics: EvalLog.doubleMap(members[EvalLog.Key.metrics]),
            erroredTrials: members[EvalLog.Key.erroredTrials]?.integerValue ?? 0)
    }
}

extension EvalLog.Stats {
    init(_ json: EvalLogJSON) throws {
        let members = try EvalLog.object(json, "stats")
        try EvalLog.refuseUnknown(members, allowed: EvalLog.Key.statsBlock, object: "stats")
        self.init(
            startedAt: try EvalLog.string(members, EvalLog.Key.startedAt, in: "stats"),
            completedAt: try EvalLog.string(members, EvalLog.Key.completedAt, in: "stats"),
            durationSeconds: try EvalLog.double(members, EvalLog.Key.durationSeconds, in: "stats"),
            totalSteps: try EvalLog.integer(members, EvalLog.Key.totalSteps, in: "stats"),
            meanInferenceLatencySeconds:
                members[EvalLog.Key.meanInferenceLatencySeconds]?.doubleValue,
            framesDir: EvalLog.optionalString(members, EvalLog.Key.framesDir))
    }
}

extension EvalLog.Sample {
    init(_ json: EvalLogJSON) throws {
        let members = try EvalLog.object(json, "a sample")
        try EvalLog.refuseUnknown(members, allowed: EvalLog.Key.sample, object: "a sample")
        let name = "a sample"
        self.init(
            sceneID: try EvalLog.string(members, EvalLog.Key.sceneID, in: name),
            status: try EvalLog.status(members, EvalLog.Key.status, in: name),
            reduced: EvalLog.doubleMap(members[EvalLog.Key.reduced]),
            epochs: (members[EvalLog.Key.epochs]?.arrayValue ?? []).map { EvalLog.doubleMap($0) },
            error: EvalLog.optionalString(members, EvalLog.Key.error),
            instruction: EvalLog.optionalString(members, EvalLog.Key.instruction),
            sceneMetadata: members[EvalLog.Key.sceneMetadata]?.objectValue ?? [:],
            operatorJudgements: (members[EvalLog.Key.operatorJudgements]?.arrayValue ?? [])
                .map(\.stringValue),
            judgementSources: (members[EvalLog.Key.judgementSources]?.arrayValue ?? [])
                .map(\.stringValue),
            operatorNotes: (members[EvalLog.Key.operatorNotes]?.arrayValue ?? [])
                .map(\.stringValue),
            operatorMessages: (members[EvalLog.Key.operatorMessages]?.arrayValue ?? [])
                .map { $0.arrayValue ?? [] },
            trialMetadata: (members[EvalLog.Key.trialMetadata]?.arrayValue ?? [])
                .map { $0.objectValue ?? [:] },
            terminationReasons: (members[EvalLog.Key.terminationReasons]?.arrayValue ?? [])
                .map(\.stringValue),
            policyTranscripts: members[EvalLog.Key.policyTranscripts]?.arrayValue ?? [])
    }
}
