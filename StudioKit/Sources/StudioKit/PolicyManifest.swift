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
            evaluation: evaluation)
    }

    // MARK: - can this app drive it

    public enum Incompatibility: Equatable, Sendable {
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
        var out: [String] = []
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
