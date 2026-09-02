import Foundation
import DuckKit

/// A community policy's own account of itself — Pollen's sharing format.
///
/// WHY A SHARED POLICY IS USELESS WITHOUT ONE. A `.onnx` file tells you it
/// takes 61 numbers and returns 14. It does not tell you that slot 0 of the
/// command block is a FLAG rather than a forward velocity, that slot 1 picks
/// which foot to stand on, or that pushing the robot backwards at 0.18 m/s
/// makes it fall over. `RemiFabre/microduck-flamingo-cycle` says all three in
/// its `manifest.json`, and a policy without one is a network nobody outside
/// its author can drive correctly.
///
/// The format is Pollen's (`schema_version` 2, `model_api` 1); this decodes
/// it, it does not define it. Fields this app has no use for are ignored
/// rather than rejected, because a newer writer adding a key must not stop an
/// older reader loading the policy.
public struct PolicyManifest: Equatable, Sendable {

    public struct Command: Equatable, Sendable {
        /// What each of the three twist slots MEANS, in the author's words.
        public let twist: [String]
        public let head: String?
        public let body: String?
        /// The command that means "do nothing" — the value to hold when the
        /// motion is not wanted, which is not always all zeros.
        public let idle: [Double]
    }

    public struct Training: Equatable, Sendable {
        public let taskID: String?
        public let repository: String?
        public let commit: String?
        public let run: String?
        /// True when the author says so in the commit field. A policy trained
        /// on an unmerged branch cannot be reproduced from the main line, and
        /// saying so is the difference between provenance and decoration.
        public var isUnmerged: Bool {
            (commit ?? "").lowercased().contains("not merged")
        }
    }

    public struct Evaluation: Equatable, Sendable {
        public let simProxy: String?
        public let battery: String?
        public let knownLimits: String?
        public let heldTrials: Int?
        public let fellTrials: Int?
        public let totalTrials: Int?
    }

    public let schemaVersion: Int
    public let modelAPI: Int
    public let name: String
    /// "perpetual" holds until told to stop; a one-shot has a duration.
    public let kind: String?
    public let observationLength: Int
    public let actionLength: Int
    public let actionScale: Double
    public let entryPose: String?
    public let durationSeconds: Double?
    public let summary: String?
    public let command: Command?
    public let controlHz: Double?
    public let training: Training?
    public let evaluation: Evaluation?
    /// Cautions the AUTHOR wrote into the file, as opposed to the ones
    /// `cautions` derives from the evaluation and training blocks.
    ///
    /// READ BECAUSE THIS APP NOW WRITES THEM. `PolicyManifest.encode` puts a
    /// list here — never run on hardware, what was and was not searched, which
    /// reward terms were refused — and a reader that ignored the key would
    /// throw away the most important thing in a file it had just been handed.
    /// The derived cautions stay: they are facts nobody typed, and the two
    /// kinds appear together with the author's first, because a person's own
    /// warning about their own policy outranks anything inferred from a tally.
    public let authorCautions: [String]

    public enum ReadError: Error, Equatable {
        case notJSON
        case missing(String)
        /// A schema this reader has never seen. Refused rather than guessed:
        /// the command block's meaning is exactly the thing a schema bump
        /// would change, and misreading it drives a robot wrongly.
        case unsupportedSchema(Int)
    }

    public static func decode(_ data: Data) throws -> PolicyManifest {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        let schema = root["schema_version"] as? Int ?? 1
        guard schema <= 2 else { throw ReadError.unsupportedSchema(schema) }
        guard let name = root["name"] as? String else { throw ReadError.missing("name") }
        guard let obs = root["obs_len"] as? Int else { throw ReadError.missing("obs_len") }
        guard let act = root["action_len"] as? Int else { throw ReadError.missing("action_len") }

        var command: Command?
        if let raw = root["command"] as? [String: Any] {
            command = Command(twist: raw["twist"] as? [String] ?? [],
                              head: raw["head"] as? String,
                              body: raw["body"] as? String,
                              idle: (raw["idle"] as? [Double]) ?? [])
        }
        var training: Training?
        if let raw = root["training"] as? [String: Any] {
            training = Training(taskID: raw["task_id"] as? String,
                                repository: raw["repo"] as? String,
                                commit: raw["commit"] as? String,
                                run: raw["run"] as? String)
        }
        var evaluation: Evaluation?
        if let raw = root["eval"] as? [String: Any] {
            let stress = raw["stress_24_random_trials"] as? [String: Any]
            let held = stress?["held"] as? Int
            let fell = stress?["fell"] as? Int
            let stepped = stress?["recovered_stepped_down"] as? Int
            evaluation = Evaluation(
                simProxy: raw["sim_proxy"] as? String,
                battery: raw["battery"] as? String,
                knownLimits: raw["known_limits"] as? String,
                heldTrials: held, fellTrials: fell,
                totalTrials: [held, stepped, fell].compactMap { $0 }.isEmpty
                    ? nil : [held, stepped, fell].compactMap { $0 }.reduce(0, +))
        }
        return PolicyManifest(
            schemaVersion: schema,
            modelAPI: root["model_api"] as? Int ?? 1,
            name: name,
            kind: root["kind"] as? String,
            observationLength: obs,
            actionLength: act,
            actionScale: root["action_scale"] as? Double ?? 1.0,
            entryPose: root["entry_pose"] as? String,
            durationSeconds: root["duration_s"] as? Double,
            summary: root["description"] as? String,
            command: command,
            controlHz: (root["robot"] as? [String: Any])?["control_hz"] as? Double,
            training: training,
            evaluation: evaluation,
            authorCautions: (root["cautions"] as? [String]) ?? [])
    }

    // MARK: - writing one

    /// A manifest this app is about to WRITE, which is a different shape from
    /// one it has read.
    ///
    /// WHY A SECOND TYPE AND NOT `PolicyManifest` ITSELF. `PolicyManifest` is a
    /// READER: every field is filled in, `actionScale` defaults to 1.0 because
    /// a file that omitted it still has to load, and `observationLength` and
    /// `actionLength` are whatever the author claimed. None of that is right
    /// for a writer. This app knows the observation and action widths as facts
    /// about the robot, so a writer must not take them from a caller; and it
    /// very often does NOT know the action scale, so a writer must be able to
    /// leave the key out rather than emit the reader's default as though
    /// somebody had declared it. A file that says `action_scale: 1.0` because
    /// nobody said otherwise is a file that drives a robot 10% differently than
    /// its author intended, which is the failure `PolicyLibrary.declaredScale`
    /// exists to name.
    /// NOT `Sendable`, and the `extra` bag is why. A dictionary of `Any` cannot
    /// promise anything about what is in it, and claiming otherwise to satisfy
    /// a conformance is exactly the sort of assertion this package is built to
    /// avoid. A manifest is built and encoded in one place; it does not need to
    /// cross a boundary.
    public struct Written: Equatable {
        public let name: String
        public let summary: String
        /// Nil omits the key. See above: an omission is honest and a default is
        /// a claim.
        public let actionScale: Double?
        public let kind: String?
        public let durationSeconds: Double?
        public let entryPose: String?
        public let twist: [String]
        public let idle: [Double]
        public let cautions: [String]
        /// Anything this app wants to say that Pollen's format has no field
        /// for, at the top level. A newer reader adding a key must not stop an
        /// older one loading the policy — `decode` above ignores what it does
        /// not know — so extra facts are additive by construction.
        public let extra: [String: Any]

        public init(name: String, summary: String, actionScale: Double?, kind: String?,
                    durationSeconds: Double?, entryPose: String?, twist: [String],
                    idle: [Double], cautions: [String], extra: [String: Any] = [:]) {
            self.name = name; self.summary = summary; self.actionScale = actionScale
            self.kind = kind; self.durationSeconds = durationSeconds
            self.entryPose = entryPose; self.twist = twist; self.idle = idle
            self.cautions = cautions; self.extra = extra
        }

        /// `[String: Any]` is not Equatable, and the three fields that identify
        /// a manifest are enough for a test to hold it to.
        public static func == (a: Written, b: Written) -> Bool {
            a.name == b.name && a.summary == b.summary && a.actionScale == b.actionScale
                && a.cautions == b.cautions
        }
    }

    public enum WriteError: Error, Equatable {
        case noName
        case notEncodable

        public var message: String {
            switch self {
            case .noName:
                return "A manifest with no name is a policy nobody can refer to."
            case .notEncodable:
                return "That manifest holds something JSON cannot carry."
            }
        }
    }

    /// The bytes, in the format `decode` reads.
    ///
    /// THE WIDTHS AND THE RATE ARE THIS PACKAGE'S, NOT THE CALLER'S. `obs_len`,
    /// `action_len` and `control_hz` are the three numbers `incompatibilities`
    /// checks a manifest against, so letting a caller supply them would let a
    /// caller write a manifest this app then refuses to run — a file that fails
    /// its own compatibility check. They come from `DuckObservation` and
    /// `DuckModel`, which is where the robot's truth lives.
    public static func encode(_ written: Written) throws -> Data {
        guard !written.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WriteError.noName
        }
        var body: [String: Any] = [
            "schema_version": 2,
            "model_api": 1,
            "name": written.name,
            "description": written.summary,
            "obs_len": DuckObservation.length,
            "action_len": DuckModel.policyJointCount,
            "robot": ["control_hz": DuckModel.tickHz],
            "cautions": written.cautions,
        ]
        // OMITTED, NOT DEFAULTED. Every Optional below is a fact this app may
        // not hold, and a manifest is read by things that act on it.
        if let scale = written.actionScale { body["action_scale"] = scale }
        if let kind = written.kind { body["kind"] = kind }
        if let duration = written.durationSeconds { body["duration_s"] = duration }
        if let pose = written.entryPose { body["entry_pose"] = pose }
        if !written.twist.isEmpty || !written.idle.isEmpty {
            body["command"] = ["twist": written.twist, "idle": written.idle]
        }
        for (key, value) in written.extra { body[key] = value }
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            throw WriteError.notEncodable
        }
        return data
    }

    // MARK: - can this app drive it

    public enum Incompatibility: Hashable, Sendable {
        case observationLength(Int)
        case actionLength(Int)
        case controlRate(Double)

        public var message: String {
            switch self {
            case .observationLength(let n):
                return "It reads \(n) numbers; this robot's observation is \(DuckObservation.length)."
            case .actionLength(let n):
                return "It writes \(n) joint targets; the policy joints number \(DuckModel.policyJointCount)."
            case .controlRate(let hz):
                return "It runs at \(Int(hz)) Hz; everything here is \(Int(DuckModel.tickHz)) Hz."
            }
        }
    }

    /// What stops this policy running here — empty when nothing does.
    ///
    /// CHECKED AGAINST THE ROBOT, NOT AGAINST A HOPE. The three numbers that
    /// have to agree are the observation width, the action width and the
    /// control rate; a mismatch in any of them is a network for a different
    /// machine, and running it would drive real servos from noise.
    public var incompatibilities: [Incompatibility] {
        var out: [Incompatibility] = []
        if observationLength != DuckObservation.length {
            out.append(.observationLength(observationLength))
        }
        if actionLength != DuckModel.policyJointCount {
            out.append(.actionLength(actionLength))
        }
        if let hz = controlHz, hz != DuckModel.tickHz {
            out.append(.controlRate(hz))
        }
        return out
    }

    public var isRunnableHere: Bool { incompatibilities.isEmpty }

    /// Everything the author admits to, in the order a reader should meet it.
    ///
    /// These are not warnings this app invented — every one is a field the
    /// author filled in. Showing them is the whole point of carrying a
    /// manifest around.
    public var cautions: [String] {
        var out: [String] = authorCautions
        if let limits = evaluation?.knownLimits, !limits.isEmpty {
            out.append(limits)
        }
        if let held = evaluation?.heldTrials, let fell = evaluation?.fellTrials,
           let total = evaluation?.totalTrials, total > 0 {
            out.append("Stress trials: held \(held) of \(total), fell \(fell).")
        }
        if training?.isUnmerged == true {
            out.append("Trained on a branch its author says is not merged — the training "
                     + "environment cannot be reproduced from the project's main line.")
        }
        if kind == "perpetual" && durationSeconds == nil {
            out.append("Perpetual: it holds until the command says otherwise, so it has no "
                     + "end of its own.")
        }
        return out
    }
}
