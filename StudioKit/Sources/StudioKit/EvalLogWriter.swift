import Foundation

/// The keys this app puts INSIDE their four free-form maps, spelled once.
///
/// WHY THIS EXISTS BESIDE `EvalLog.Key`. `EvalLog.Key` holds the forty keys
/// inspect-robots defines, and `scripts/check_evallog_schema.sh` proves none of
/// them is spelled twice. These are the other half: the keys this project
/// invents inside `policy_config`, `embodiment_info`, `scene_metadata` and
/// `trial_metadata`, which their reader passes through untouched and which no
/// guard outside this package can check. They have exactly the same failure
/// mode. A scene written with `drop_heights_m` and read with `drop_heights`
/// gives a report that quietly loses its axis, and nothing goes red.
///
/// The values are the wire spelling, snake case, because they sit beside their
/// own keys in the same objects and a reader should not be able to tell which
/// half of a log this app wrote.
public enum EvalMeta {

    // in scene_metadata
    public static let route = "route"
    public static let reducer = "reducer"
    public static let seconds = "seconds"
    public static let schedule = "schedule"
    public static let dropHeights = "drop_heights_m"
    public static let cell = "cell"
    public static let cellLabel = "cell_label"
    public static let riseMetres = "rise_m"
    public static let termsRefused = "terms_refused"
    public static let tailTicksDeclared = "tail_ticks_declared"

    // in trial_metadata
    public static let dropMetres = "drop_m"
    public static let ticksReported = "ticks_reported"
    public static let traced = "traced"
    public static let diverged = "diverged"
    public static let ranToHorizon = "ran_to_horizon"
    public static let terms = "terms"
    public static let cellInvalid = "cell_invalid"
    /// The bench's own words for one trial that was recorded and not scored.
    ///
    /// THEIR SCHEMA HAS ONE `error` PER SCENE AND WE HAVE ONE PER TRIAL. A walk
    /// scene of eight drops where two diverged has two different reasons, and a
    /// file that kept only the first would lose the second with nothing to show
    /// for it. So each reason rides in that trial's own metadata, where their
    /// reader passes it through and both reports can print it beside the trial
    /// it belongs to.
    public static let why = "why"

    // in embodiment_info
    public static let plantName = "plant_name"
    public static let plantDigest = "plant_sha256"
    public static let benchAddress = "bench_address"

    // in policy_config
    public static let criterion = "criterion"
    public static let epochAxis = "epoch_axis"
}

/// Turning a finished run into the file, and giving the file its name.
///
/// THE WRITER IS THE ONLY THING THAT BUILDS AN `EvalLog` FROM A RUN. Every
/// derived number is already computed once, on `EvalRun`; this assembles them
/// and spells no arithmetic of its own. A second place that built a log would
/// be a second opinion about what `total_steps` counts.
public enum EvalLogWriter {

    // MARK: - the file's own name

    /// Their `_SLUG_MAX`. The comment on it says why: the derived filename has
    /// to stay inside a 255 byte name with room for the underscore, the eight
    /// hex and `.json.tmp`.
    public static let slugCap = 200

    /// `json_log._slug`, character for character.
    ///
    /// `[^a-z0-9]+` becomes one hyphen, the ends are stripped, the result is
    /// cut at two hundred and stripped again, and a name with nothing left
    /// becomes `eval`.
    ///
    /// THE `"eval"` BELOW IS A FILENAME STEM AND NOT A WIRE KEY, which matters
    /// because `scripts/check_evallog_schema.sh` matches the quoted literal.
    /// It is upstream's own fallback for a task name with no ASCII letters or
    /// digits in it, and it is one of the four literals that guard exempts.
    ///
    /// The cut is after the substitution on purpose: by then
    /// the string is hyphens, digits and lower case ASCII, so counting
    /// Characters in Swift and counting code points in Python are the same
    /// count. Doing it the other way round would differ on a combining mark.
    public static func slug(_ name: String) -> String {
        var out = ""
        var pendingSeparator = false
        for scalar in name.lowercased().unicodeScalars {
            let kept = (scalar.value >= 0x61 && scalar.value <= 0x7A)
                    || (scalar.value >= 0x30 && scalar.value <= 0x39)
            if kept {
                if pendingSeparator { out.append("-") }
                pendingSeparator = false
                out.unicodeScalars.append(scalar)
            } else {
                // A run of anything else is ONE hyphen, and a run before the
                // first kept character is none at all, which is their leading
                // strip arriving early rather than as a second pass.
                pendingSeparator = !out.isEmpty
            }
        }
        var capped = String(out.prefix(slugCap))
        while capped.hasSuffix("-") { capped.removeLast() }
        return capped.isEmpty ? "eval" : capped
    }

    /// The eight hex their writer takes off a fresh uuid.
    ///
    /// It is a disambiguator and nothing else: two runs of the same task on the
    /// same afternoon have to land in one directory without one overwriting the
    /// other. `runIDSaid` says so on screen, because an eight character hex
    /// beside a result looks like a hash of the result.
    public static func runID(_ uuid: UUID = UUID()) -> String {
        String(uuid.uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8))
    }

    public static func filename(task: String, runID: String) -> String {
        "\(slug(task))_\(runID).json"
    }

    /// The same stem with their viewer's extension, so a directory holding both
    /// tells them apart by content rather than by chance.
    public static func htmlFilename(task: String, runID: String) -> String {
        "\(slug(task))_\(runID).html"
    }

    public static let runIDSaid =
        "The eight characters after the task name are a fresh identifier, so two runs of the "
      + "same task can sit in one folder. They are not a digest of the result and nothing can "
      + "be checked against them."

    /// What wrote this, as a name rather than as a sentence. The sentence is
    /// `EvalRun.producerSaid`, which goes in the log.
    public static func wroteIt(version: String, build: String) -> String {
        "Microduck Studio \(version) (\(build))"
    }

    // MARK: - the timestamp

    /// `datetime.now(UTC).isoformat()`, which is what their `created`,
    /// `started_at` and `completed_at` are.
    ///
    /// SIX DIGITS OF FRACTION, AND NONE AT ALL WHEN THERE IS NO FRACTION, which
    /// is their rule rather than a preference: Python omits the microseconds
    /// when they are zero, and a log whose timestamps were spelled differently
    /// from every other log in a directory is a log a person sorts by hand.
    /// Built out of `DateComponents` in UTC rather than a `DateFormatter`,
    /// because a formatter's fractional seconds are its own business and this
    /// has to be exact.
    public static func timestamp(_ date: Date) -> String {
        let interval = date.timeIntervalSince1970
        var whole = interval.rounded(.down)
        var micros = Int(((interval - whole) * 1_000_000).rounded())
        if micros >= 1_000_000 {
            micros -= 1_000_000
            whole += 1
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                            from: Date(timeIntervalSince1970: whole))
        let stem = String(format: "%04d-%02d-%02dT%02d:%02d:%02d",
                          parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                          parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
        let fraction = micros == 0 ? "" : String(format: ".%06d", micros)
        return stem + fraction + "+00:00"
    }

    // MARK: - the log

    /// A finished run as the file.
    ///
    /// `criterion` HAS NO DEFAULT. It is the bench's own sentence about what
    /// ending standing means, read off the wire at runtime, and it is the one
    /// string in this feature this app must never author. A default would be an
    /// app written criterion sitting in a log that says the bench said it.
    public static func log(_ run: EvalRun, criterion: String,
                           refusedTerms: [(name: String, why: String)] = [],
                           appVersion: String, build: String) -> EvalLog {
        let traced = run.anyTrialTraced
        let spec = EvalLog.Spec(
            task: run.task.name,
            policy: run.policy.logName,
            embodiment: run.embodiment.identity,
            created: timestamp(run.startedAt),
            producer: EvalRun.producerSaid(version: appVersion, build: build),
            policyConfig: run.policy.config(embodiment: run.embodiment, epochs: run.task.epochs,
                                            criterion: criterion, refusedTerms: refusedTerms),
            embodimentInfo: run.embodiment.info(traced: traced),
            maxSteps: run.task.maxSteps,
            maxSeconds: run.task.maxSeconds)
        let results = EvalLog.Results(totalScenes: run.scenes.count,
                                      totalTrials: run.totalTrials,
                                      metrics: run.metrics,
                                      erroredTrials: run.erroredTrials)
        let stats = EvalLog.Stats(startedAt: timestamp(run.startedAt),
                                  completedAt: timestamp(run.completedAt),
                                  durationSeconds: run.durationSeconds,
                                  totalSteps: run.totalSteps)
        let refusedNames = refusedTerms.map(\.name)
        return EvalLog(status: run.status, eval: spec, results: results, stats: stats,
                       samples: run.scenes.map {
                           sample(for: $0, task: run.task, refusedTerms: refusedNames)
                       },
                       error: run.error)
    }

    public static func data(_ run: EvalRun, criterion: String,
                            refusedTerms: [(name: String, why: String)] = [],
                            appVersion: String, build: String) -> Data {
        log(run, criterion: criterion, refusedTerms: refusedTerms,
            appVersion: appVersion, build: build).encoded()
    }

    /// One scene, with the eight parallel arrays taken off the scene result
    /// rather than built here.
    ///
    /// THE SAMPLE'S `error` FALLS BACK TO THE FIRST TRIAL'S. Their schema has
    /// one error per scene; a scene that errored only because a trial did has
    /// none of its own, and a sample marked errored with no reason on it is a
    /// row a reader can do nothing with. Every trial's own reason is in its
    /// metadata as well, so nothing is lost by promoting the first.
    static func sample(for scene: EvalSceneResult, task: EvalTask,
                       refusedTerms: [String]) -> EvalLog.Sample {
        let firstTrialError = scene.trials.compactMap(\.error).first
        return EvalLog.Sample(
            sceneID: scene.scene.id,
            status: scene.status,
            reduced: scene.reduced,
            epochs: scene.epochValues,
            error: scene.error ?? firstTrialError,
            instruction: scene.scene.instruction,
            sceneMetadata: task.sceneMetadata(for: scene.scene, refusedTerms: refusedTerms),
            operatorJudgements: scene.operatorJudgements,
            judgementSources: scene.judgementSources,
            operatorNotes: scene.operatorNotes,
            operatorMessages: scene.operatorMessages,
            trialMetadata: scene.trialMetadata,
            terminationReasons: scene.terminationReasons,
            policyTranscripts: scene.policyTranscripts)
    }
}

/// Reading a log back, which is `EvalLog.decoded(from:)` with a door on it.
///
/// WHY A NAMED READER AT ALL. The strictness lives on `EvalLog` beside the
/// schema it is strict about; this is the name the rest of the app calls, so a
/// screen never reaches for a decoder. It also does the one thing the decoder
/// cannot: it says, in one sentence, why a file being refused is the file being
/// treated properly rather than the app being awkward.
public enum EvalLogReader {

    public static func read(_ data: Data) throws -> EvalLog {
        try EvalLog.decoded(from: data)
    }

    /// Said above a refusal, so a person who has been handed a file that will
    /// not open knows the refusal is the point.
    public static let asStrictAsTheirs =
        "This app reads an evaluation log exactly as strictly as inspect-robots does, and "
      + "refuses the same files for the same reasons. A log this app displayed and their own "
      + "tools would not open is worse than one it declines."
}

/// One log on the shelf: the bytes, where they came from, and what may be done
/// with them.
///
/// ORIGIN IS NOT A LABEL, IT IS A GATE. A log written here can be published
/// under the operator's name; a log somebody else wrote cannot, because
/// publishing it would put their measurement in a repository that says this app
/// made it. The refusal is a thrown error rather than a hidden button, so the
/// screen can say why.
///
/// AN IMPORTED FILE'S BYTES ARE NEVER REWRITTEN. `bytes` is what arrived, so a
/// log that came from a Python run and is exported again is the same file, and
/// nothing about it has been rounded through this app's own writer on the way.
public struct EvalLogFile: Equatable, Sendable, Identifiable {

    public enum Origin: String, Equatable, Sendable, CaseIterable {
        /// This app ran it.
        case written
        /// Somebody handed the file over.
        case imported
    }

    public let log: EvalLog
    /// The file, byte for byte. For a written log these are this app's writer's
    /// output; for an imported one they are what arrived.
    public let bytes: Data
    public let origin: Origin
    /// The name on the shelf, always `<slug>_<8 hex>.json`.
    public let name: String
    /// The name the file arrived under. Foreign text: it is somebody else's
    /// string and it is drawn through `EvalText.foreign`.
    public let importedName: String?
    /// `Microduck Studio 1.1 (58)` for a log this app wrote, nil for one that
    /// arrived.
    public let wroteIt: String?

    public var id: String { name }

    /// The sibling report's name, which shares the stem so a directory holding
    /// both tells them apart by extension.
    public var htmlName: String {
        name.hasSuffix(".json") ? String(name.dropLast(5)) + ".html" : name + ".html"
    }

    public var canPublish: Bool { origin == .written }

    init(log: EvalLog, bytes: Data, origin: Origin, name: String,
         importedName: String?, wroteIt: String?) {
        self.log = log
        self.bytes = bytes
        self.origin = origin
        self.name = name
        self.importedName = importedName
        self.wroteIt = wroteIt
    }

    // MARK: - building one

    /// A run this app finished.
    public static func written(_ run: EvalRun, criterion: String,
                               refusedTerms: [(name: String, why: String)] = [],
                               appVersion: String, build: String,
                               runID: String = EvalLogWriter.runID()) -> EvalLogFile {
        let log = EvalLogWriter.log(run, criterion: criterion, refusedTerms: refusedTerms,
                                    appVersion: appVersion, build: build)
        return EvalLogFile(log: log, bytes: log.encoded(), origin: .written,
                           name: EvalLogWriter.filename(task: log.eval.task, runID: runID),
                           importedName: nil,
                           wroteIt: EvalLogWriter.wroteIt(version: appVersion, build: build))
    }

    /// A log this app wrote, read back off the disk it was written to.
    ///
    /// THE THIRD CONSTRUCTOR, AND IT EXISTS BECAUSE THE OTHER TWO ANSWER
    /// DIFFERENT QUESTIONS. Coming back after a launch there is no run any
    /// more, only bytes and a filename, and reading this phone's own
    /// measurements back through `imported` would put the Imported badge on
    /// them and turn `canPublish` off, which is this type's own gate answering
    /// the wrong question.
    ///
    /// `wroteIt` COMES OUT OF THE LOG AND NOT OFF THE RUNNING BUILD.
    /// `eval.inspect_robots_version` was written by whichever build made the
    /// run, so an archived file keeps saying which one that was rather than
    /// claiming today's.
    ///
    /// THE BYTES ARE THE FILE'S AND ARE NEVER RE ENCODED. A log read back and
    /// written out again through this app's own encoder would be a different
    /// file from the one on disk, which is exactly what write once is for.
    public static func onDisk(_ data: Data, named name: String) throws -> EvalLogFile {
        let log = try EvalLogReader.read(data)
        return EvalLogFile(log: log, bytes: data, origin: .written, name: name,
                           importedName: nil,
                           wroteIt: EvalRun.wroteItSaid(from: log.eval.inspectRobotsVersion))
    }

    /// A file somebody else wrote, read as strictly as their own reader reads
    /// it. Throws `EvalLogRefusal`, which names the key and the object it sat
    /// in.
    public static func imported(_ data: Data, named: String,
                                runID: String = EvalLogWriter.runID()) throws -> EvalLogFile {
        let log = try EvalLogReader.read(data)
        return EvalLogFile(log: log, bytes: data, origin: .imported,
                           name: EvalLogWriter.filename(task: log.eval.task, runID: runID),
                           importedName: EvalText.foreign(named),
                           wroteIt: nil)
    }

    // MARK: - what a person reads

    /// C3 and C6: a field whose words came out of the file rather than out of
    /// this app, labelled as such wherever it is drawn.
    public static let fromTheFile =
        "From the file, in its own words."

    public static let importedBadge = "Imported"

    public static let importedSaid =
        "This log was written somewhere else and is shown as it arrived. Its sentences are its "
      + "own: nothing here has been reworded, and nothing missing from it has been filled in."

    public static let cannotPublishImported =
        "A log this app did not write cannot be published from here. Putting somebody else's "
      + "measurement in a repository under your account would say you made it, and the file "
      + "already names who did."

    /// L4 seen from the other side. Our own logs never carry a seed; a log that
    /// does is not wrong, it is a log from a run that had one.
    public static let foreignSeedSaid =
        "This log records a seed. It came from a run somewhere else that had one, and it is "
      + "shown as the file has it rather than explained away."

    public static let whatAnImportedLogMustBe =
        "Any evaluation log inspect-robots wrote, at schema version 1. It is read here exactly "
      + "as strictly as their own reader reads it, so a file this app opens is a file their "
      + "tools open too."

    public static let aLogIsFinished =
        "A log is finished when the run is. Changing a verdict afterwards would make the file "
      + "disagree with the run it describes, so the way to a different answer is another run."

    public static let howToRead =
        "To read this log with the tool that defines its format: pip install inspect-robots, "
      + "then inspect-robots view the json file. This app wrote the file and does not run their "
      + "tools."

    /// A4. There is no zip of the shelf in this build, and a Share button that
    /// silently did one log at a time would be a person wondering where the
    /// other nine went.
    public static let oneLogAtATimeSaid =
        "Logs are shared one at a time. Each file is a whole run on its own, and a folder of "
      + "them shared as one archive would arrive without the report that belongs beside each "
      + "one."

    // MARK: - Hugging Face

    /// Over the criterion on the card, so a reader knows the paragraph under it
    /// is quoted rather than written.
    public static let criterionLabel =
        "What the bench said ending standing means, in the bench's own words:"

    public static let plantDigestLabel = "The world these numbers were measured in, sha256:"

    public static let defaultRepositoryName = "microduck-studio-evals"
    /// The data is CC BY 4.0, the same licence the challenge submissions go
    /// under, because a log is a measurement and not a program.
    public static let publishLicense = "cc-by-4.0"

    public enum Refusal: Error, Equatable {
        case imported

        public var message: String {
            switch self {
            case .imported: return EvalLogFile.cannotPublishImported
            }
        }
    }

    /// A dataset, never a model. The kind has no default in
    /// `HuggingFacePublish` for exactly this reason: an evaluation published as
    /// a model repository is one nobody's dataset search reaches.
    public func repository(namespace: String,
                           name: String = defaultRepositoryName)
    throws -> HuggingFacePublish.Repository {
        try HuggingFacePublish.repository(namespace: namespace, name: name, kind: .dataset)
    }

    /// The log, the report beside it, and the card that says what both are.
    public func files() -> [HuggingFacePublish.File] {
        [
            HuggingFacePublish.File(path: self.name, contents: bytes, isText: true),
            HuggingFacePublish.File(path: htmlName,
                                    contents: Data(EvalReport.html(self).utf8), isText: true),
            HuggingFacePublish.File(path: "README.md", contents: Data(card().utf8), isText: true),
        ]
    }

    /// THE STATUS LEADS, ALWAYS.
    ///
    /// A commit summary is the one line of this that appears in a repository's
    /// activity feed, in a notification and in a diff header. A cancelled run
    /// whose summary opened with its best metric would read, everywhere a
    /// summary is read without its file, as a finished run.
    public func commitSummary() -> String {
        let stem = EvalLogWriter.slug(log.eval.task)
        var line = "Eval \(stem): \(log.status.rawValue)"
        switch log.status {
        case .success:
            let metrics = log.results.metrics.keys.sorted()
                .compactMap { key -> String? in
                    guard let value = log.results.metrics[key] else { return nil }
                    return "\(key) \(EvalReport.number(value))"
                }
            if !metrics.isEmpty { line += ", " + metrics.joined(separator: ", ") }
            if log.results.erroredTrials > 0 {
                line += ", \(log.results.erroredTrials) of \(log.results.totalTrials) errored"
            }
        case .cancelled:
            line += ", \(log.results.totalTrials) "
                  + "\(log.results.totalTrials == 1 ? "trial" : "trials") ran before it stopped"
        case .error:
            line += ", \(log.results.erroredTrials) of \(log.results.totalTrials) trials errored"
        case .started:
            line += ", still running when this file was written"
        }
        if let world = EvalReport.world(log) { line += ", on \(world)" }
        return line
    }

    /// The dataset card. Written here rather than on a screen because every
    /// claim on it is a claim, and every claim in this app is a string with a
    /// test on it.
    public func card() -> String {
        var lines: [String] = []
        lines.append("""
        ---
        license: \(Self.publishLicense)
        tags:
          - microduck
          - robotics
          - mujoco
          - evaluation
          - inspect-robots
        ---
        """)
        lines.append("# \(log.eval.task)")
        lines.append(commitSummary())
        lines.append(EvalReport.reproduceSaid(log))
        // The bench's own criterion, whole. A card is the one place it is not
        // capped: `EvalText.foreign` is for a row on a phone, and a measurement
        // published under somebody's account is published as it was measured.
        if let criterion = log.eval.policyConfig[EvalMeta.criterion]?.stringValue {
            lines.append(Self.criterionLabel)
            lines.append("> \(criterion)")
        }
        if let digest = log.eval.embodimentInfo[EvalMeta.plantDigest]?.stringValue {
            lines.append("\(Self.plantDigestLabel) `\(digest)`")
        }
        lines.append(EvalEpochs.noSeedSaid)
        lines.append(EvalRun.stepCountsSaid)
        lines.append(EvalTrace.firstDropOnlySaid)
        lines.append(EvalVerdict.recordedNotScoredSaid)
        // The challenge caveat belongs to a challenge grid and to nothing else:
        // it is a sentence about playing a MOVE on hardware, and pasting it
        // under a walk evaluation would be a caveat about something that did
        // not happen. A walk log gets the refusal that does fit.
        if let challenge = EvalReport.challenge(log) {
            lines.append(EvalReport.leaderboardIsTheChallengeScreen)
            lines.append(challenge.realDuckCaveat)
        } else {
            lines.append(EvalEmbodiment.realMicroduckRefusal)
        }
        lines.append(Self.howToRead)
        lines.append(Provenance.independence)
        lines.append(EvalText.notTheirRender)
        return lines.joined(separator: "\n\n") + "\n"
    }

    /// Create then commit, credential free, exactly as every other publish in
    /// this app is built.
    ///
    /// `isPrivate` HAS NO DEFAULT, for the reason `StairsSubmission` gives:
    /// whether a run is public is the whole question, and a default is how it
    /// gets answered by nobody.
    public func publishCalls(namespace: String, name: String = defaultRepositoryName,
                             isPrivate: Bool)
    throws -> (repository: HuggingFacePublish.Repository,
               create: HuggingFacePublish.Call,
               commit: HuggingFacePublish.Call) {
        guard canPublish else { throw Refusal.imported }
        let target = try repository(namespace: namespace, name: name)
        let create = HuggingFacePublish.create(target, license: Self.publishLicense,
                                               isPrivate: isPrivate)
        let commit = try HuggingFacePublish.commit(target, summary: commitSummary(),
                                                   description: EvalReport.reproduceSaid(log),
                                                   files: files())
        return (target, create, commit)
    }
}
