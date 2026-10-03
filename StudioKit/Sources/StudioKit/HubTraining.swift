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

    /// duckbatch with kp001 (kick pairs, duckbatch #17 on #16), 2026-10-03. Bump deliberately:
    /// the job runs whatever this commit says.
    ///
    /// FROM aa286e8 FOR THE KICKS. A kick recipe needs k001's `ball_lateral_speed`, the plain-PPO
    /// path (a menu with no `anchor`) and the left-foot BallKick tasks; all three arrived after
    /// aa286e8. For the walking recipe nothing changes: the bootstrap, the launcher and `sim`
    /// are byte-identical, and `finetune`'s one change is that `anchor` became optional, which
    /// a walking menu (it names one) never takes.
    ///
    /// FROM 7d8a9d3, AND IT CHANGES NOTHING THIS RECIPE RUNS. The bootstrap and the launcher are
    /// byte-identical between the two; what arrived in between is additive `finetune` keys
    /// (`dead_band`, `standing_envs`) and reward terms that only a menu naming them uses, and
    /// this menu names none of them. It moves the pin onto `main`, where every close note that
    /// judges this recipe now lives.
    public static let duckbatchCommit = "7e7e6601252c7e8b5358380e7c134773c46e5167"
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
        /// From your picks: the taste they were learned as and the reward it became. Nil is
        /// b003b's reward exactly, as before.
        public var fromPicks: FromPicks?

        public struct FromPicks: Equatable, Sendable {
            public let taste: PreferenceModel.Taste
            public let plan: PreferenceModel.RewardPlan
            public init(taste: PreferenceModel.Taste, plan: PreferenceModel.RewardPlan) {
                self.taste = taste; self.plan = plan
            }
        }

        public init(name: String, iterations: Int = 100,
                    linearProgressWeight: Double = 1.0, angularProgressWeight: Double = 1.0,
                    fromPicks: FromPicks? = nil) {
            self.name = name; self.iterations = iterations
            self.linearProgressWeight = linearProgressWeight
            self.angularProgressWeight = angularProgressWeight
            self.fromPicks = fromPicks
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

        /// The header lines that say where the reward came from, and how this run is judged.
        var picksHeader: String {
            guard let p = fromPicks else { return "" }
            let names = PreferenceFeatures.names
            let taste = zip(names, p.taste.weights).map { "\($0)=\(String(format: "%.2f", $1))" }
                .joined(separator: " ")
            let mult = PreferenceModel.groups.map {
                "\($0.name)×\(String(format: "%.2f", p.plan.multipliers[$0.name] ?? 1))"
            }.joined(separator: " ")
            let reversed = p.plan.reversed.isEmpty ? "" : "\n# Left at Pollen's weight (your picks favoured more of it): \(p.plan.reversed.joined(separator: ", "))"
            return """

            # FROM YOUR PICKS (RLHF, human feedback): \(p.taste.picks) network-vs-network picks.
            # Taste (standardised; negative = less is preferred): \(taste); side bias \(String(format: "%.2f", p.taste.sideBias))
            # Reward multipliers on Pollen's VelStand weights (bounded 0.5-2): \(mult)\(reversed)
            # Judged by you, fixed before it ran: in Compare the trained network wins at least 60%
            # of 20 fresh picks against the network it started from.
            """
        }

        /// The `rewards:` block that sets the re-weighted terms (finetune applies `weight`).
        var picksRewards: String {
            guard let p = fromPicks else { return "" }
            // Interpolated text is not de-indented with the literal around it, so these
            // carry the menu's own indentation: two under `finetune`, four for a term.
            let lines = p.plan.weights.keys.sorted().map {
                "\n    \($0): {weight: \(String(format: "%g", p.plan.weights[$0]!))}"
            }.joined()
            return "\n  rewards:\(lines)"
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
            # Standing practice is VelStand's curriculum, 25% of envs: `rel_standing_envs` below is
            # overwritten every reset (b003d close). b003g held it at 5% and the duck stopped standing.
            # \(isPilot ? "A PILOT: judged on whether it runs and the progress reward rises, not on the lines." : "Judged on the lines above.")\(picksHeader)
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
                rel_standing_envs: 0.05\(picksRewards)
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

    // MARK: - a skill, from your picks

    /// A skill network trained from a person's picks between two of that skill.
    ///
    /// k001's METHOD, WITH THE PERSON'S WEIGHTS. k001 fine-tuned Pollen's right kick with plain
    /// PPO from Pollen's own network, 1,000 iterations, and one added term against sideways ball
    /// speed. This is that menu with the reward re-weighted by the picks (`PreferenceModel`,
    /// profile per skill) and judged by the person: the trained kick must win in their own duels.
    public struct SkillRecipe: Equatable, Sendable {
        public var name: String
        public let profile: PreferenceModel.Profile
        public let fromPicks: Recipe.FromPicks
        public var iterations: Int

        public init(name: String, profile: PreferenceModel.Profile, fromPicks: Recipe.FromPicks,
                    iterations: Int = 1000) {
            self.name = name; self.profile = profile; self.fromPicks = fromPicks
            self.iterations = iterations
        }

        public var isPilot: Bool { iterations < 500 }

        public var refusal: String? {
            if iterations < 10 || iterations > 3000 {
                return "Between 10 and 3,000 iterations. k001 used 1,000."
            }
            if profile.skill == PreferenceModel.Profile.walk.skill {
                return "Walking is trained from the walking recipe, which has its own pass lines."
            }
            return nil
        }

        public func batchID(at date: Date) -> String {
            Recipe(name: name).batchID(at: date)
        }

        public func menuYAML(batchID: String) -> String {
            let g = { (v: Double) in String(format: "%g", v) }
            let p = fromPicks
            let taste = zip(profile.featureNames, p.taste.weights)
                .map { "\($0)=\(String(format: "%.2f", $1))" }.joined(separator: " ")
            let mult = profile.groups.map {
                "\($0.name)×\(String(format: "%.2f", p.plan.multipliers[$0.name] ?? 1))"
            }.joined(separator: " ")
            let reversed = p.plan.reversed.isEmpty ? ""
                : "\n# Left at its usual weight (your picks favoured more of it): \(p.plan.reversed.joined(separator: ", "))"
            // Pollen's terms are re-weighted under `rewards`; a term the task lacks is added.
            let existing = p.plan.weights.keys.filter { profile.added[$0] == nil }.sorted()
            let rewards = existing.map { "\n    \($0): {weight: \(g(p.plan.weights[$0]!))}" }.joined()
            let added = profile.added.keys.sorted().map { term in
                "\n    \(term):\n      func: \(profile.added[term]!)\n      weight: \(g(p.plan.weights[term] ?? 0))\n      params: {asset_name: ball}"
            }.joined()
            let backlash = profile.task.replacingOccurrences(of: "-Flat-", with: "-Flat-Backlash-")
            return """
            # \(name) — written in Microduck Studio, run by duckbatch \(String(HubTraining.duckbatchCommit.prefix(7))).
            # k001's method on \(profile.skill): warm start from Pollen's network, plain PPO, no anchor.
            # FROM YOUR PICKS (RLHF, human feedback): \(p.taste.picks) picks between two \(profile.plural).
            # Taste (standardised; negative = less is preferred): \(taste); side bias \(String(format: "%.2f", p.taste.sideBias))
            # Reward multipliers (bounded 0.5-2): \(mult)\(reversed)
            # Judged by you, fixed before it ran: the trained network wins at least 60% of 20 fresh
            # picks against the network it started from. Reported beside it: k001's lines.
            # \(isPilot ? "A PILOT: judged on whether it runs, not on the lines." : "Judged on the line above.")
            batch_id: \(batchID)
            task: \(profile.task)
            teacher: \(profile.teacher)
            student: \(profile.teacher)
            seed: 0
            eval_envs: 256
            eval_tasks: [\(profile.task), \(backlash)]
            final_seeds: \(isPilot ? "[2001]" : "[2001, 2002, 2003]")
            finetune:
              num_envs: 2048
              iterations: \(iterations)
              save_interval: 250
              init_std: 0.2
              learning_rate: 3.0e-4
              entropy_coef: 0.002
              rewards:\(rewards)
              add_rewards:\(added)

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
        requestBody(menuYAML: recipe.menuYAML(batchID: batchID), pilot: recipe.isPilot,
                    dataset: dataset, token: token)
    }

    public static func requestBody(skill recipe: SkillRecipe, batchID: String, dataset: String,
                                   token: String) -> [String: Any] {
        requestBody(menuYAML: recipe.menuYAML(batchID: batchID), pilot: recipe.isPilot,
                    dataset: dataset, token: token)
    }

    static func requestBody(menuYAML: String, pilot: Bool, dataset: String,
                            token: String) -> [String: Any] {
        let bootstrap = "\(duckbatchRaw)/\(duckbatchCommit)/scripts/hf_job_bootstrap.sh"
        // The image has Python and may not have curl until the bootstrap installs it.
        let fetch = "python -c \"import urllib.request;open('/tmp/boot.sh','wb')"
                  + ".write(urllib.request.urlopen('\(bootstrap)').read())\" && bash /tmp/boot.sh"
        let hours = pilot ? 1 : 3
        return [
            "dockerImage": image,
            "command": ["bash", "-c", fetch],
            "arguments": [String](),
            "environment": [
                "REPO": duckbatchRepo, "COMMIT": duckbatchCommit, "MENU": "menu-inline.yaml",
                "MENU_YAML": menuYAML, "DATASET": dataset,
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

    /// The network every run here starts from — b002's distilled student a02 — at the pin.
    /// Fetched beside the trained one, because the judge is a Compare duel between the two.
    public static var startingNetworkURL: URL? {
        URL(string: "\(duckbatchRaw)/\(duckbatchCommit)/records/b002-student-size-longer/policies/a02/policy.onnx")
    }
    public static let startingNetworkName = "b002-a02-start.onnx"
    public static let recordPath = "record.json"

    /// What PPO is, said where the screen starts, because the row used to lead with the acronym.
    public static let whatThisIs =
        "Trains a new walking network for the duck by trial and error, on a rented GPU at "
      + "Hugging Face — not on \(DeviceWords.current.this). The method is PPO (proximal policy optimisation), the "
      + "reinforcement learning Pollen trains Microduck's own networks with: the duck tries in "
      + "simulation, a reward you set scores each try, and the network is nudged toward what "
      + "scored better, with 2,048 ducks practising at once."

    /// The row and the title, in words rather than an acronym.
    public static let rowTitle = "Train a network on Hugging Face"

    public static let notClaimed =
        "Simulation only, in Pollen's mjlab. This fine-tunes Pollen's own walking network, "
      + "distilled to a smaller student; it is not a gait learned from nothing, and a pass here "
      + "is not a claim about a physical duck."
}
