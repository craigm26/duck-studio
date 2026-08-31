import Foundation
import DuckKit

/// A trained policy, described the way quackd's `learned_verbs:` block asks for it.
///
/// WHAT A LEARNED VERB WOULD BE. quackd's LLM picks verbs — `kick`, `walk_to`, `stop`. A
/// learned verb is an ONNX policy that registers alongside them, so the model could call
/// `moonwalk` exactly as it calls `kick` and the vocabulary would grow without the loop
/// changing.
///
/// AND NOTHING ON THE OTHER END RUNS IT, IN QUACKD'S OWN WORDS. `quackd/verbs/learned.py`
/// says of itself that it ships no policy, no training, and no ONNX runtime.
/// `docs/learned-verbs.md` opens "Learned verbs (v2) — this is the shape; nothing here
/// runs yet". And the note beside the runner says that on hardware this would ship the
/// ONNX to robotd's policy slot — an upstream feature that does not exist yet, because
/// robotd's `[policy]` paths are static today. So writing this block into a `.duck`
/// describes a policy to quackd and puts nothing on a robot. This type builds the
/// description; it does not claim anything executes, and the exported metadata says so
/// too, because the person reading a `.duck` is the one who has to know.
///
/// The fields mirror `quackd.verbs.learned.LearnedVerbSpec` (repository `rokbenko/quackd`,
/// commit 56d752a, 2026-08-28), including the defaults, so that what this exports can be
/// pasted into a `LearnedVerbSpec(...)` unchanged.
///
/// ## Two limits, stated rather than papered over
///
/// **The safety class is always `confirm`.** `register_learned_verb` passes
/// `safety_class="confirm"` as a literal with the comment "a new policy is unproven by
/// definition". There is no argument for it and no way to raise it from a `.duck` file. A
/// learned verb asks a human first, every time, and this type exposes that as a constant
/// rather than a field, because a field implies a choice nobody has.
///
/// **A learned verb takes NO call-time arguments.** `register_learned_verb` registers its
/// executor with `NoParams` — hard-coded, not derived from the spec — so the LLM calls the
/// verb with an empty parameter object. THAT IS THE ONE THAT BITES US. Our `PolicyManifest`
/// carries a command block: flamingo-cycle's three twist slots are `[flag, side, 0]`, and
/// standing on the left foot rather than the right is `side = -1`. None of that can be
/// passed at call time. A learned verb can only ever run the policy under one fixed
/// command, and the only command a runner can honestly assume is the policy's own idle.
/// So `export` refuses a policy whose idle command is not all zeros, and flags one whose
/// twist slots mean something, rather than exporting a verb that silently does the wrong
/// thing on a real robot.
public struct LearnedVerbSpec: Equatable, Sendable {

    public let name: String
    public let description: String
    /// ONNX file. `obs[1,61] -> actions[1,14]` on upstream, in quackd's own words.
    public let policyPath: String
    public let observationDimension: Int
    public let actionDimension: Int
    public let controlHz: Double
    public let timeoutSeconds: Double
    /// Provenance for a `.duck` author, who is deciding whether to allow this verb.
    public let metadata: [String: DuckValue]
    /// What the author admitted to, plus what the no-arguments limit costs this policy.
    public let cautions: [String]

    /// Always "confirm". See the type's note: `register_learned_verb` writes it as a
    /// literal, so there is nothing here to choose.
    public static let safetyClass = "confirm"

    /// False, always. `register_learned_verb` binds `NoParams` as the executor's parameter
    /// type, so nothing can be handed to a learned verb when the LLM calls it.
    public static let acceptsCallTimeArguments = false

    /// quackd's own default, from `LearnedVerbSpec.timeout_s`.
    public static let defaultTimeoutSeconds = 10.0

    /// The contract every upstream policy meets, per `docs/learned-verbs.md`: 61 in, 14
    /// out, 50 Hz. These are also DuckKit's numbers, which is asserted rather than assumed
    /// — if the two ever disagree, a policy this app can drive is not one quackd can
    /// register, and that is worth a red test rather than a surprise.
    public static let upstreamObservationDimension = DuckObservation.length
    public static let upstreamActionDimension = DuckModel.policyJointCount
    public static let upstreamControlHz = DuckModel.tickHz

    public init(name: String,
                description: String,
                policyPath: String,
                observationDimension: Int = 61,
                actionDimension: Int = 14,
                controlHz: Double = 50.0,
                timeoutSeconds: Double = LearnedVerbSpec.defaultTimeoutSeconds,
                metadata: [String: DuckValue] = [:],
                cautions: [String] = []) {
        self.name = name
        self.description = description
        self.policyPath = policyPath
        self.observationDimension = observationDimension
        self.actionDimension = actionDimension
        self.controlHz = controlHz
        self.timeoutSeconds = timeoutSeconds
        self.metadata = metadata
        self.cautions = cautions
    }

    // MARK: - refusals

    public enum ExportRefusal: Error, Equatable, Sendable {
        case unusableVerbName(String)
        case wrongContract([PolicyManifest.Incompatibility])
        case idleCommandNotStated
        case idleCommandIsNotNeutral([Double])

        public var message: String {
            switch self {
            case .unusableVerbName(let found):
                return "\"\(found)\" cannot be a verb name. quackd verb names are lowercase "
                     + "letters, digits, hyphens and underscores, starting with a letter or "
                     + "digit, and the policy's own name is what the verb would be called."
            case .wrongContract(let problems):
                return "This policy does not meet the contract a learned verb has to meet — "
                     + problems.map(\.message).joined(separator: " ")
                     + " quackd registers policies that are 61 in, 14 out, at 50 Hz."
            case .idleCommandNotStated:
                return "The manifest does not say what this policy's idle command is, so "
                     + "there is no way to know what it will do when it is sent nothing. A "
                     + "learned verb is called with no arguments, so the idle command is the "
                     + "only thing it can send — and an unstated one cannot be trusted."
            case .idleCommandIsNotNeutral(let idle):
                let written = idle.map { DuckYAML.number($0) }.joined(separator: ", ")
                return "This policy's idle command is [\(written)], not all zeros. A learned "
                     + "verb is registered with NoParams — the LLM calls it with nothing — so "
                     + "a runner can only ever send a fixed command, and the only fixed "
                     + "command it can defend is zeros. Sending zeros to this policy would "
                     + "mean something its author did not intend, so it cannot be exported "
                     + "as a learned verb until quackd can pass a command."
            }
        }
    }

    // MARK: - building one from a manifest

    /// Turn a community policy's manifest into a learned-verb declaration.
    ///
    /// Every metadata key below comes from a field the policy's author filled in — quackd's
    /// `docs/learned-verbs.md` asks that `metadata` "carry the reward text, the training
    /// run, and the eval numbers, so a `.duck` author knows what they are allowing", and
    /// the training block and eval battery are exactly that. THE REWARD TEXT IS ABSENT, AND
    /// IS LEFT ABSENT. Pollen's manifest format has no reward field; inventing a key and
    /// filling it with a guess would put a fabricated provenance line in front of the one
    /// person the metadata exists to inform.
    ///
    /// - Parameter timeoutSeconds: overrides the derived timeout. The manifest carries no
    ///   timeout of its own, so the default is quackd's 10 s, widened to the policy's own
    ///   stated duration when that is longer — a one-shot that runs for 12 s cannot be
    ///   given 10 s to finish.
    public static func export(_ manifest: PolicyManifest,
                              policyPath: String,
                              timeoutSeconds override: Double? = nil) throws -> LearnedVerbSpec {
        guard DuckTask.isVerbName(manifest.name) else {
            throw ExportRefusal.unusableVerbName(manifest.name)
        }
        guard manifest.incompatibilities.isEmpty else {
            throw ExportRefusal.wrongContract(manifest.incompatibilities)
        }

        // THE COMMAND BLOCK IS THE WHOLE PROBLEM. A learned verb is called with no
        // arguments, so whatever command the runner sends is a constant it did not get from
        // the caller, and the only constant it can justify is zeros. A policy whose own idle
        // is not zeros reads zeros as some other instruction — so zeros would command a
        // motion nobody asked for, on a real robot.
        if let command = manifest.command {
            guard !command.idle.isEmpty else { throw ExportRefusal.idleCommandNotStated }
            guard command.idle.allSatisfy({ $0 == 0 }) else {
                throw ExportRefusal.idleCommandIsNotNeutral(command.idle)
            }
        }

        var cautions = manifest.cautions
        // Refusing this would be too strong — flamingo-cycle's idle IS zeros, so a runner
        // can drive it safely; it just cannot ever make it lift a foot, because that needs
        // twist [1, side, 0] and there is no way to say so. An author allowing this verb
        // deserves to read that before they allow it.
        if let command = manifest.command, !command.twist.isEmpty {
            let meaningful = command.twist.filter { !$0.lowercased().hasPrefix("unused") }
            if !meaningful.isEmpty {
                cautions.append(
                    "This policy is driven by a command — \(meaningful.joined(separator: "; ")) "
                  + "— and a learned verb is called with no arguments, so it can only ever run "
                  + "the idle command. Whatever the command block selects cannot be selected.")
            }
        }

        var metadata: [String: DuckValue] = [
            "policy_name": .string(manifest.name),
            "policy_summary": .string(manifest.summary ?? ""),
            "manifest_schema_version": .integer(manifest.schemaVersion),
            "manifest_model_api": .integer(manifest.modelAPI),
            "observation_len": .integer(manifest.observationLength),
            "action_len": .integer(manifest.actionLength),
            "action_scale": .double(manifest.actionScale),
            // Restated in the metadata because a `.duck` author reads this file, not
            // quackd's source, and the two limits above are the ones that change what they
            // are agreeing to.
            "safety_class": .string(safetyClass),
            "command_at_call_time": .string(
                "none — register_learned_verb binds NoParams, so the LLM calls this verb "
              + "with no arguments"),
            // WHAT THE OTHER END ACTUALLY DOES WITH THIS, written into the file and not
            // only into a comment nobody downstream reads. A `.duck` author is deciding
            // whether to ALLOW a verb, and "allow" reads like "deploy" unless the file
            // says otherwise. It does not deploy: quackd executes nothing here.
            "quackd_runner": .string(
                "none — quackd ships no ONNX runtime, by its own learned-verb module's "
              + "account, and its note on the runner says shipping the ONNX to robotd's "
              + "policy slot is an upstream feature that does not exist yet, because "
              + "robotd's policy paths are static today. Declaring this verb describes "
              + "the policy to quackd; it does not put it on a robot."),
        ]
        if let kind = manifest.kind { metadata["policy_kind"] = .string(kind) }
        if let pose = manifest.entryPose { metadata["entry_pose"] = .string(pose) }
        if let duration = manifest.durationSeconds { metadata["duration_s"] = .double(duration) }
        if let hz = manifest.controlHz { metadata["control_hz"] = .double(hz) }

        if let training = manifest.training {
            if let id = training.taskID { metadata["training_task_id"] = .string(id) }
            if let repo = training.repository { metadata["training_repo"] = .string(repo) }
            if let commit = training.commit { metadata["training_commit"] = .string(commit) }
            if let run = training.run { metadata["training_run"] = .string(run) }
            metadata["training_unmerged"] = .boolean(training.isUnmerged)
        }
        if let evaluation = manifest.evaluation {
            if let proxy = evaluation.simProxy { metadata["eval_sim_proxy"] = .string(proxy) }
            if let battery = evaluation.battery { metadata["eval_battery"] = .string(battery) }
            if let limits = evaluation.knownLimits {
                metadata["eval_known_limits"] = .string(limits)
            }
            if let held = evaluation.heldTrials { metadata["eval_stress_held"] = .integer(held) }
            if let fell = evaluation.fellTrials { metadata["eval_stress_fell"] = .integer(fell) }
            if let total = evaluation.totalTrials {
                metadata["eval_stress_trials"] = .integer(total)
            }
        }
        if let command = manifest.command {
            if !command.twist.isEmpty {
                metadata["command_twist"] = .list(command.twist.map { .string($0) })
            }
            if let head = command.head { metadata["command_head"] = .string(head) }
            if let body = command.body { metadata["command_body"] = .string(body) }
            metadata["command_idle"] = .list(command.idle.map { .double($0) })
        }
        if !cautions.isEmpty {
            metadata["cautions"] = .list(cautions.map { .string($0) })
        }

        let timeout = override ?? max(defaultTimeoutSeconds, manifest.durationSeconds ?? 0)
        return LearnedVerbSpec(
            name: manifest.name,
            // The author's own one-liner is what the LLM will read when it decides whether
            // to call this verb, so it is used verbatim rather than dressed up.
            description: manifest.summary ?? manifest.name,
            policyPath: policyPath,
            observationDimension: manifest.observationLength,
            actionDimension: manifest.actionLength,
            controlHz: manifest.controlHz ?? upstreamControlHz,
            timeoutSeconds: timeout,
            metadata: metadata,
            cautions: cautions)
    }

    /// The same verb, in the shape a `.duck` file declares it under `learned_verbs:`.
    ///
    /// The timeout does NOT survive the trip: quackd's `LearnedVerbRef` — the thing a
    /// `.duck` can write — has no `timeout_s`, only the Python-side spec does. Anything
    /// registering this verb picks the timeout itself, so it is carried into the metadata
    /// where an author can at least read the number this app derived.
    public var duckDeclaration: DuckTask.LearnedVerb {
        var declared = metadata
        declared["timeout_s"] = .double(timeoutSeconds)
        return DuckTask.LearnedVerb(name: name, policy: policyPath,
                                    description: description, metadata: declared)
    }
}
