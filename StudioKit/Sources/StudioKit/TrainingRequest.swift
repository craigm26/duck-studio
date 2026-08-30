import Foundation
import DuckKit

/// A request to train a NEW policy, written here and run somewhere else.
///
/// NOTHING IN THIS APP TRAINS ANYTHING, and nothing in this file pretends to.
/// Training is a rollout loop against a physics engine with a few thousand
/// parallel environments; a phone cannot do it, and neither can the Pi. What a
/// phone CAN do is write the request — which task to fork, what to reward, what
/// the episode looks like, what counts as success — and check it against things
/// that are already known before anybody spends GPU hours finding out.
///
/// THE CHECK IS THE POINT. "Train it to lift a two-kilo brick" is not a
/// training problem, it is an arithmetic one: the neck stalls at about 7.7 N
/// and no reward function moves that. A request like that should be refused
/// here, in a second, rather than after a day of training that was never going
/// to converge.
///
/// AND THE OLD POLICY'S TRAINING IS NOT A LIMIT ON A NEW ONE. `alpha_ground_pick`
/// was trained with 10–40 g at its mouth; that says what it was shown, not what
/// the robot can do. A new policy may well be trained on more. Only the physics
/// — torque, traction, reach — bounds what is worth asking for, and only those
/// produce refusals here.
public struct TrainingRequest: Equatable, Sendable {

    /// The upstream task this one starts from. Forking a working config is how
    /// every policy in the corpus was made, and naming the parent is what lets
    /// somebody diff the two.
    public enum Base: String, CaseIterable, Sendable {
        case groundPick = "microduck_ground_pick_env_cfg.py"
        case velocity = "microduck_velocity_env_cfg.py"
        case sitStand = "microduck_sitstand_env_cfg.py"
        case ballKick = "microduck_ball_kick_env_cfg.py"
        case rollerCrouch = "microduck_roller_crouch_env_cfg.py"

        public var summary: String {
            switch self {
            case .groundPick:
                return "Reaching the mouth to the floor and standing back up, on a phase clock"
            case .velocity:
                return "Walking at a commanded velocity"
            case .sitStand:
                return "Sitting down and getting up, on a flag"
            case .ballKick:
                return "A one-shot kick"
            case .rollerCrouch:
                return "Crouching low while rolling, on a phase clock"
            }
        }

        /// What the three command slots mean in this task. GETTING THIS WRONG
        /// IS THE CLASSIC WAY A FORK FAILS: hand a phase-clock task a velocity
        /// and the duck tries to walk through its own reward.
        public var command: String {
            switch self {
            case .groundPick, .rollerCrouch: return "[cos(2π·phase), sin(2π·phase), 0]"
            case .velocity: return "[vx, vy, vyaw] in m/s and rad/s"
            case .sitStand: return "[flag, 0, 0] — 1 sits, 0 stands"
            case .ballKick: return "all zeros; being selected is the trigger"
            }
        }
    }

    /// A reward term, named as upstream names it.
    ///
    /// ONLY FUNCTIONS THAT EXIST. Every name here was read out of
    /// `mjlab_microduck/tasks/mdp.py`; a request naming a reward somebody
    /// invented is a config that will not import, and finding that out on a
    /// training machine is a slow way to learn a typo.
    public struct Reward: Equatable, Sendable, Identifiable {
        public let function: String
        public let weight: Double
        /// Why it is in the list, in a sentence.
        public let reason: String
        public var id: String { function }

        public init(function: String, weight: Double, reason: String) {
            self.function = function; self.weight = weight; self.reason = reason
        }
    }

    /// The reward functions upstream actually ships, grouped so a drafter can
    /// be told what it may choose from.
    public static let vocabulary: [String: String] = [
        "mouth_ground_proximity": "pulls the mouth tip toward the floor",
        "mouth_perpendicular_to_ground": "points the mouth down rather than sideways",
        "pose_target_match": "holds a named pose",
        "pose_l1_penalty": "punishes drifting off a named pose",
        "height_target_gaussian": "holds the trunk at a height",
        "height_l1_penalty": "punishes drifting off a height",
        "forward_speed_reward": "rewards travelling forward",
        "wheel_glide_reward": "rewards gliding on the rollers",
        "feet_grounded_reward": "keeps both feet down",
        "feet_flat_penalty": "punishes rolling onto an edge",
        "body_impact_cost": "punishes hitting things with the body",
        "joint_torques_l2": "punishes brute force",
        "joint_torque_rate_l2": "punishes snatching",
        "neck_joint_pos_l2": "keeps the neck near its neutral",
        "joint_deviation_l1": "keeps joints near their defaults",
        "leg_action_rate_l2": "smooths the legs",
        "neck_action_rate_l2": "smooths the neck",
        "fallen_state_penalty": "punishes being over",
        "is_alive": "rewards still being up",
        "upright_progress": "rewards getting more upright",
        "body_upright_gaussian": "rewards being upright",
        "self_collision_cost": "punishes hitting itself",
    ]

    public var name: String
    public var summary: String
    public var base: Base
    public var episodeSeconds: Double
    public var rewards: [Reward]
    /// What the duck is meant to be doing it to, if anything.
    public var prop: DuckScene.Prop?
    /// How the run is judged when it is done.
    public var successCriterion: String
    /// What the author knows they are guessing at. Carried into the file,
    /// because a request that hides its assumptions gets run by somebody who
    /// does not share them.
    public var openQuestions: [String]

    public init(name: String, summary: String, base: Base,
                episodeSeconds: Double = 4.0, rewards: [Reward],
                prop: DuckScene.Prop? = nil,
                successCriterion: String,
                openQuestions: [String] = []) {
        self.name = name; self.summary = summary; self.base = base
        self.episodeSeconds = episodeSeconds; self.rewards = rewards
        self.prop = prop; self.successCriterion = successCriterion
        self.openQuestions = openQuestions
    }

    // MARK: - what is wrong with it

    public enum Refusal: Equatable, Sendable {
        /// A reward function that does not exist upstream.
        case unknownReward(String)
        case noRewards
        /// Asking for a pull no torque can produce.
        case pastTheTorque(needed: Double, ceiling: Double)
        /// Asking to grasp something the mouth never reaches.
        case pastTheReach(millimetres: Double)
        /// Asking to bite something thinner than the jaw closes.
        case underTheBite(millimetres: Double)
        case episodeTooLong(Double)

        public var message: String {
            switch self {
            case .unknownReward(let name):
                return "\(name) is not a reward function microduck_rl ships. A config naming one "
                     + "that does not exist will not import, and a training machine is a slow "
                     + "place to find a typo."
            case .noRewards:
                return "A task with no rewards is a task with no gradient. Say what it should be "
                     + "rewarded for."
            case .pastTheTorque(let needed, let ceiling):
                return String(format: "That needs about %.1f N at the beak and the neck stalls at "
                    + "%.1f N — one joint at ±%.4f N⋅m through a %.3f m lever. No reward function "
                    + "moves that; it is arithmetic, not training.",
                    needed, ceiling, Retrieval.Drag.jointTorque, Retrieval.Drag.neckLever)
            case .pastTheReach(let mm):
                return String(format: "The mouth sweeps %.0f–%.0f mm through a pick. Nothing at "
                    + "%.0f mm can be taken hold of, however it is rewarded.",
                    Retrieval.Reach.lowestDuringPick * 1000,
                    Retrieval.Reach.highestDuringPick * 1000, mm)
            case .underTheBite(let mm):
                return String(format: "The jaw shuts %.0f mm above the floor and %.0f mm passes "
                    + "underneath it. Training changes the policy, not the geometry.",
                    Retrieval.closedTipHeight * 1000, mm)
            case .episodeTooLong(let seconds):
                return String(format: "%.0f s an episode is a long time to spend on one attempt. "
                    + "Every shipped task runs 2–8 s; a longer one is mostly the duck standing "
                    + "still being rewarded for it.", seconds)
            }
        }

        /// Whether it cannot be trained, or merely should be reconsidered.
        public var isFatal: Bool {
            switch self {
            case .unknownReward, .noRewards, .pastTheTorque, .pastTheReach, .underTheBite:
                return true
            case .episodeTooLong: return false
            }
        }
    }

    /// Everything wrong with this request, cheapest check first.
    public var refusals: [Refusal] {
        var found: [Refusal] = []
        if rewards.isEmpty { found.append(.noRewards) }
        for reward in rewards where TrainingRequest.vocabulary[reward.function] == nil {
            found.append(.unknownReward(reward.function))
        }
        if episodeSeconds > 12 { found.append(.episodeTooLong(episodeSeconds)) }
        if let prop {
            // PHYSICS, NOT THE OLD POLICY'S TRAINING SET. What the previous
            // network was shown does not bound a new one; the torque and the
            // geometry do.
            let neck = Retrieval.Drag.pullBeforeNeckStalls
            let lifting = prop.grams / 1000 * 9.81
            if lifting > neck {
                found.append(.pastTheTorque(needed: lifting, ceiling: neck))
            }
            if let height = prop.graspHeightMillimetres,
               Retrieval.Reach.graspTime(forHeight: height / 1000) == nil {
                found.append(.pastTheReach(millimetres: height))
            }
            if prop.graspHeightMillimetres == nil,
               prop.thicknessMillimetres < Retrieval.closedTipHeight * 1000 {
                found.append(.underTheBite(millimetres: prop.thicknessMillimetres))
            }
        }
        return found
    }

    public var isTrainable: Bool { !refusals.contains { $0.isFatal } }
}

// MARK: - what gets handed over

extension TrainingRequest {

    /// A python identifier for this task.
    ///
    /// IT UNDOES THE FILENAME A MODEL MIGHT HAVE ECHOED BACK. Asked to name a
    /// task, a small local model handed back the base config's filename —
    /// "microduck_ground_pick_env_cfg.py" — and the naive slug turned that into
    /// `microduck_microduck_ground_pick_env_cfg_py_env_cfg.py`, which is
    /// somewhere between useless and funny. The prefix and the suffixes come
    /// off, so a name that is already a filename lands back where it started.
    public var slug: String {
        var text = name.lowercased()
        for tail in [".py", "_env_cfg", "_cfg"] where text.hasSuffix(tail) {
            text.removeLast(tail.count)
        }
        let mapped = text.map { $0.isLetter || $0.isNumber ? $0 : "_" }
        var parts = String(mapped).split(separator: "_", omittingEmptySubsequences: true)
            .map(String.init)
        // Strip the pieces of a filename shape wherever they ended up.
        while parts.first == "microduck" { parts.removeFirst() }
        while let last = parts.last, ["py", "cfg", "env"].contains(last) { parts.removeLast() }
        let slug = parts.joined(separator: "_")
        return slug.isEmpty ? "new_task" : slug
    }

    public var fileName: String { "microduck_\(slug)_env_cfg.py" }

    /// The env config, as a starting point somebody edits — not as a finished
    /// thing.
    ///
    /// IT IS A SKELETON AND IT SAYS SO IN ITS OWN HEADER. Nothing here has been
    /// imported, let alone run: this app has no Python, no mjlab and no GPU. It
    /// forks a config that works, lists rewards that exist, and leaves the
    /// weights where a person put them. Presenting it as ready to train would
    /// be the app claiming a competence it does not have.
    public func envConfig() -> String {
        let terms = rewards.map { reward in
            """
                # \(reward.reason)
                cfg.rewards["\(reward.function)"] = RewardTermCfg(
                    func=microduck_mdp.\(reward.function),
                    weight=\(String(format: "%g", reward.weight)),
                    params={},
                )
            """
        }.joined(separator: "\n")

        let propNote = prop.map { prop in
            """

            # THE OBJECT THIS IS FOR: \(prop.name) — \(String(format: "%.0f", prop.grams)) g, \
            \(String(format: "%.0f", prop.thicknessMillimetres)) mm across\
            \(prop.graspHeightMillimetres.map { String(format: ", gripped %.0f mm up", $0) } ?? ", on the floor").
            # It is NOT in this config. The training scene has a ball, blocks and
            # cones; a broom is a body somebody has to add to the scene before any
            # of these rewards can refer to it. That is the first job.
            """
        } ?? ""

        let questions = openQuestions.isEmpty ? "" : "\n" + openQuestions
            .map { "# OPEN: \($0)" }.joined(separator: "\n")

        return """
        \"\"\"\(name) — \(summary)

        A SKELETON, NOT A TRAINED TASK. Written in Duck Studio on a phone, which
        has no Python, no mjlab and no GPU: nothing here has been imported, run
        or converged. It forks \(base.rawValue), names reward functions that
        exist in mjlab_microduck/tasks/mdp.py, and leaves every weight where a
        person put it.

        Forked from: \(base.rawValue)
          which does: \(base.summary)
          command:    \(base.command)

        Episode: \(String(format: "%g", episodeSeconds)) s
        Success: \(successCriterion)
        \(propNote)\(questions)
        \"\"\"

        from copy import deepcopy

        from mjlab.envs.mdp.actions import JointPositionActionCfg
        from mjlab.managers.manager_term_config import RewardTermCfg
        from mjlab.utils.spec_config import ContactSensorCfg

        from mjlab_microduck.tasks import mdp as microduck_mdp
        from mjlab_microduck.tasks.\(base.rawValue.replacingOccurrences(of: ".py", with: "")) \\
            import make_\(base.rawValue.replacingOccurrences(of: "microduck_", with: "")
                              .replacingOccurrences(of: "_env_cfg.py", with: ""))_env_cfg


        EPISODE_SECONDS = \(String(format: "%g", episodeSeconds))


        def make_\(slug)_env_cfg(play: bool = False):
            \"\"\"\(summary)\"\"\"
            cfg = deepcopy(make_\(base.rawValue.replacingOccurrences(of: "microduck_", with: "")
                                      .replacingOccurrences(of: "_env_cfg.py", with: ""))_env_cfg(play=play))
            cfg.episode_length_s = EPISODE_SECONDS

            # Start from the parent's rewards and add this task's on top. Removing
            # the parent's stability terms is the usual way a fork learns to do
            # the job while falling over.
        \(terms)

            return cfg
        """
    }

    /// The human half: what to run, what it is for, and what nobody knows.
    public func brief() -> String {
        let refusalLines = refusals.isEmpty ? "None." : refusals
            .map { ($0.isFatal ? "- REFUSED: " : "- Worth reconsidering: ") + $0.message }
            .joined(separator: "\n")
        let rewardLines = rewards.map {
            "| `\($0.function)` | \(String(format: "%g", $0.weight)) | \($0.reason) |"
        }.joined(separator: "\n")
        let propLine = prop.map {
            String(format: "%@ — %.0f g, %.0f mm across, %.2f m away%@",
                   $0.name, $0.grams, $0.thicknessMillimetres, $0.metresAway,
                   $0.graspHeightMillimetres.map {
                       String(format: ", gripped %.0f mm up", $0) } ?? ", on the floor")
        } ?? "None — this task is about the robot alone."

        return """
        # \(name)

        \(summary)

        **Nothing here has been trained.** This was written on a phone, which has
        no Python, no mjlab and no GPU. It is a request: fork a config that works,
        reward things that exist, and hand it to a machine that can actually run
        the rollouts.

        ## What to fork

        `\(base.rawValue)` — \(base.summary).
        Its command block is `\(base.command)`, and a fork that feeds it something
        else is the classic way one of these fails.

        ## The object

        \(propLine)

        ## Rewards

        | function | weight | why |
        |---|---|---|
        \(rewardLines)

        Every function named above exists in `mjlab_microduck/tasks/mdp.py`.

        ## Episode and success

        \(String(format: "%g", episodeSeconds)) s an episode. Success: \(successCriterion)

        ## What this app checked

        \(refusalLines)

        Those checks are physics, not policy: the neck stalls at \
        \(String(format: "%.1f", Retrieval.Drag.pullBeforeNeckStalls)) N \
        (±\(String(format: "%.4f", Retrieval.Drag.jointTorque)) N⋅m through a \
        \(String(format: "%.3f", Retrieval.Drag.neckLever)) m lever), the mouth sweeps \
        \(String(format: "%.0f", Retrieval.Reach.lowestDuringPick * 1000))–\
        \(String(format: "%.0f", Retrieval.Reach.highestDuringPick * 1000)) mm through a pick, \
        and the jaw shuts \(String(format: "%.0f", Retrieval.closedTipHeight * 1000)) mm up. \
        **What the previous policy was trained on is not a limit on a new one** — \
        `alpha_ground_pick` saw 10–40 g at its mouth, which says what it was shown, \
        not what the robot can do.

        ## Open questions

        \(openQuestions.isEmpty ? "None stated." : openQuestions.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}
