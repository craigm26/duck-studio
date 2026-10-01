import Foundation

/// PPO on Pollen's simulator, launched from this app, run on a Hugging Face GPU.
///
/// WHAT RUNS IS NOT WRITTEN HERE. duckbatch (github.com/craigm26/duckbatch) holds the recipe:
/// it clones Pollen's microduck_rl at a locked commit, warm-starts a distilled student, runs
/// rsl_rl PPO in mjlab with a teacher anchor, exports the ONNX, measures it, and uploads the
/// records. This file writes the MENU — the part a person decides — and the HTTP request that
/// starts the job. The job fetches duckbatch's own `scripts/hf_job_bootstrap.sh` at the pinned
/// commit, so there is one recipe and not a Swift copy of it that drifts.
///
/// WHAT IS DECIDED HERE IS THE REWARD. The recipe is b003b's (duckbatch
/// `notes/2026-09-30-b003b-design.md`): mjlab's tracking terms at their own widths, plus the
/// two progress terms that pay for going and nothing for standing. A person chooses how much
/// each progress term weighs and how long to train; the pass lines are written into the menu
/// BEFORE it runs, so a result cannot move the line it is judged against.
///
/// HONEST ABOUT WHAT IT IS. Simulation only. Fine-tuning of Pollen's work and duckbatch's
/// distillation, not a gait from nothing. The sentences below say so.
public enum HubTraining {

    // MARK: - the pin

    /// duckbatch at the first commit with both the progress terms (`duckbatch.rewards`) and a
    /// bootstrap that takes the menu as text (`MENU_YAML`). Bump deliberately: the job runs
    /// whatever this commit says.
    public static let duckbatchCommit = "7d8a9d35807992643ad2bcb011068f335bfb9d0a"
    public static let duckbatchRepo = "https://github.com/craigm26/duckbatch.git"
    static let duckbatchRaw = "https://raw.githubusercontent.com/craigm26/duckbatch"
    /// duckbatch `hf_job.IMAGE` and `hf_job.UV_VERSION`, the two values its bootstrap reads
    /// from the environment rather than carrying.
    public static let image = "pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime"
    public static let uvVersion = "0.12.18"
    /// The cheapest CUDA flavor; b003 ran 1,500 iterations × 2,048 envs on it in 54.6 min.
    public static let flavor = "l4x1"

    // MARK: - the menu a person writes

    public struct Recipe: Equatable, Sendable {
        /// Shown in the list and folded into the batch id.
        public var name: String
        /// 100 is a pilot (does it run, does the progress reward rise); 1,500 is b003's budget.
        public var iterations: Int
        public var linearProgressWeight: Double
        public var angularProgressWeight: Double

        public init(name: String, iterations: Int = 100,
                    linearProgressWeight: Double = 1.0, angularProgressWeight: Double = 1.0) {
            self.name = name; self.iterations = iterations
            self.linearProgressWeight = linearProgressWeight
            self.angularProgressWeight = angularProgressWeight
        }

        public var isPilot: Bool { iterations < 500 }

        /// `app-<slug>-<yyyyMMdd-HHmm>`: unique per launch, readable in the dataset.
        public func batchID(at date: Date) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyyMMdd-HHmm"
            let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
                .reduce(into: "") { text, c in if !(c == "-" && text.hasSuffix("-")) { text.append(c) } }
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            return "app-\(slug.isEmpty ? "run" : String(slug.prefix(32)))-\(formatter.string(from: date))"
        }

        /// What it is refused for, before any money is spent.
        public var refusal: String? {
            if iterations < 10 || iterations > 3000 {
                return "Between 10 and 3,000 iterations. 100 is a pilot; b003 used 1,500."
            }
            for w in [linearProgressWeight, angularProgressWeight] where w < 0 || w > 4 {
                return "A progress weight between 0 and 4. The tracking terms it sits beside weigh "
                     + "2.0 each; a progress term much heavier than that pays for lunging."
            }
            if linearProgressWeight == 0 && angularProgressWeight == 0 {
                return "With both progress weights at 0 this is b003 again, which failed because "
                     + "standing paid as well as walking. Give at least one some weight."
            }
            return nil
        }

        /// The duckbatch menu, with its pass lines in the header.
        ///
        /// b003's pass lines, unchanged, so every run here is comparable with b003 and b003b.
        public func menuYAML(batchID: String) -> String {
            let w = { (v: Double) in String(format: "%g", v) }
            return """
            # \(name) — written in Microduck Studio, run by duckbatch \(String(HubTraining.duckbatchCommit.prefix(7))).
            # b003b's recipe: mjlab's tracking widths, plus progress terms that pay for going.
            # Pass lines, fixed before this ran (b003's, unchanged):
            #   1. cmd 0.10 m/s -> >= 0.05 m/s; cmd 0.05 -> >= 0.02
            #   2. wz 1.0 rad/s in place -> >= 0.5 rad/s
            #   3. falls/min <= 0.71; recovery within 10 points of the teacher; planar error <= 0.179
            #   4. cmd 0.30 m/s -> >= 0.12 m/s
            # \(isPilot ? "A PILOT: judged on whether it runs and the progress reward rises, not on the lines." : "Judged on the lines above.")
            batch_id: \(batchID)
            task: Mjlab-VelStand-Flat-MicroDuck
            teacher: teachers/velstand.onnx
            student: records/b002-student-size-longer/policies/a02/policy.onnx
            seed: 0
            eval_envs: 512
            final_seeds: \(isPilot ? "[2001]" : "[2001, 2002, 2003]")
            finetune:
              num_envs: 2048
              iterations: \(iterations)
              save_interval: 250
              init_std: 0.25
              learning_rate: 3.0e-4
              entropy_coef: 0.002
              command:
                rel_turn_in_place_envs: 0.25
                rel_standing_envs: 0.05
              add_rewards:
                command_progress_linear:
                  func: duckbatch.rewards.command_progress_linear
                  weight: \(w(linearProgressWeight))
                  params: {command_name: twist, min_command: 0.02}
                command_progress_angular:
                  func: duckbatch.rewards.command_progress_angular
                  weight: \(w(angularProgressWeight))
                  params: {command_name: twist, min_command: 0.1}
              anchor:
                gate_tilt_deg: 35.0
                coef_fallen: 1.0
                walk_min_speed: 0.35
                coef_walk: 0.2
                learning_rate: 3.0e-4
                epochs: 1
                mini_batches: 4

            """
        }
    }

    // MARK: - the request

    /// `POST https://huggingface.co/api/jobs/<namespace>` — the call `HfApi.run_job` makes
    /// (huggingface_hub 2.0.0, `_jobs_api._create_job_spec`).
    public static func jobsURL(namespace: String) -> URL? {
        URL(string: "https://huggingface.co/api/jobs/\(namespace)")
    }

    /// The JSON body. The token goes in `secrets`, which Hugging Face does not echo back.
    public static func requestBody(recipe: Recipe, batchID: String, dataset: String,
                                   token: String) -> [String: Any] {
        let bootstrap = "\(duckbatchRaw)/\(duckbatchCommit)/scripts/hf_job_bootstrap.sh"
        // The image has Python and may not have curl until the bootstrap installs it.
        let fetch = "python -c \"import urllib.request;open('/tmp/boot.sh','wb')"
                  + ".write(urllib.request.urlopen('\(bootstrap)').read())\" && bash /tmp/boot.sh"
        let hours = recipe.isPilot ? 1 : 3
        return [
            "dockerImage": image,
            "command": ["bash", "-c", fetch],
            "arguments": [String](),
            "environment": [
                "REPO": duckbatchRepo, "COMMIT": duckbatchCommit, "MENU": "menu-inline.yaml",
                "MENU_YAML": recipe.menuYAML(batchID: batchID), "DATASET": dataset,
                "UV_VERSION": uvVersion, "RUN": "finetune", "JUDGE_FLAG": "",
            ],
            "secrets": ["HF_TOKEN": token],
            "flavor": flavor,
            "timeoutSeconds": hours * 3600,
        ]
    }

    // MARK: - watching it

    public enum Stage: String, Equatable, Sendable {
        case scheduling = "SCHEDULING", running = "RUNNING", completed = "COMPLETED"
        case error = "ERROR", canceled = "CANCELED", deleted = "DELETED"

        public var isFinal: Bool { ![.scheduling, .running].contains(self) }

        public var said: String {
            switch self {
            case .scheduling: return "Waiting for a GPU."
            case .running: return "Training. A pilot takes about a quarter of an hour, a full run about an hour and a half, setup and measuring included."
            case .completed: return "Finished. The records are on Hugging Face."
            case .error: return "The job stopped with an error. Its log on Hugging Face says where."
            case .canceled: return "Cancelled."
            case .deleted: return "Deleted on Hugging Face."
            }
        }
    }

    public struct JobState: Equatable, Sendable {
        public let id: String
        public let stage: Stage
        public let message: String?
    }

    /// Reads the job JSON the Jobs API returns for a launch or an inspect.
    public static func jobState(from data: Data) -> JobState? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String,
              let status = json["status"] as? [String: Any],
              let raw = status["stage"] as? String, let stage = Stage(rawValue: raw)
        else { return nil }
        return JobState(id: id, stage: stage, message: status["message"] as? String)
    }

    // MARK: - where the result lands

    /// duckbatch uploads `records/<batch_id>/` to `jobs/<job-id>/<batch_id>/` in the dataset.
    public static func fileURL(dataset: String, jobID: String, batchID: String,
                               path: String) -> URL? {
        URL(string: "https://huggingface.co/datasets/\(dataset)/resolve/main/jobs/\(jobID)/\(batchID)/\(path)")
    }

    public static let policyPath = "policies/finetuned/policy.onnx"
    public static let recordPath = "record.json"

    public static let notClaimed =
        "Simulation only, in Pollen's mjlab. This fine-tunes Pollen's own walking network, "
      + "distilled to a smaller student; it is not a gait learned from nothing, and a pass here "
      + "is not a claim about a physical duck."
}
