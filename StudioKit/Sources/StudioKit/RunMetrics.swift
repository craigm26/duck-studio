import Foundation
import DuckKit

/// Everything measurable about one recorded run, and every reward term from
/// Pollen's own training config that the recording can actually answer.
///
/// TWO KINDS OF NUMBER, KEPT APART ON PURPOSE.
///
/// The first kind is MEASURED: how far the robot went, how far it leaned, which
/// joints did the work. Those come out of the recording by arithmetic and are
/// exact, whatever policy produced them.
///
/// The second kind is a REWARD TERM, and it belongs to a training config rather
/// than to the robot. `upright` is `exp(-|projected gravity xy|² / std²)` with
/// std² = 0.05 and weight 2.0 — but only in `microduck_velocity_env_cfg`; the
/// same term is weight 0.2 at mjlab's default std² = 0.2 in the ground-pick
/// config, and −0.002 is what `body_ang_vel` is worth in the roulade config
/// because there the roll IS the objective. So a term is only ever evaluated
/// against the config that trained the policy the clip was recorded from, and
/// when that config is not known this reports the measurement and NO reward.
///
/// AND MOST TERMS ARE NOT EVALUABLE FROM A RECORDING AT ALL. `air_time`,
/// `foot_clearance`, `foot_slip` and `soft_landing` all read a foot-contact
/// sensor; `angular_momentum` reads a subtree-momentum sensor; `self_collisions`
/// reads a collision sensor. None of those are in a clip and none of them can
/// be inferred from joint angles. They are listed by name with the reason,
/// because "this app does not measure that" is information and a quietly
/// shorter list is not.
public struct RunMetrics: Equatable, Sendable {

    /// One number to put on screen: what it is, what it came to, and — where it
    /// helps — what it means.
    public struct Reading: Equatable, Sendable, Identifiable {
        public let label: String
        public let value: String
        public let detail: String?
        public var id: String { label }

        public init(_ label: String, _ value: String, _ detail: String? = nil) {
            self.label = label; self.value = value; self.detail = detail
        }
    }

    // MARK: - Pollen's training configs

    /// Which `microduck_rl` environment trained a policy.
    ///
    /// Resolved from the FILENAME, which is the only handle a recording gives —
    /// and deliberately incomplete. `BEST_alpha_stand.onnx` is not listed:
    /// standing appears both as a curriculum inside the velocity config and as
    /// its own `velstand` config, and picking one would attach a weight table to
    /// a policy that may not have been trained with it. An unknown task costs a
    /// reward panel; a wrong one costs the trust in every number on it.
    public enum Task: String, Equatable, Sendable {
        case velocity, ballKick, roulade, sitstand, groundPick, rollerCrouch

        public var configFile: String {
            switch self {
            case .velocity:     return "microduck_velocity_env_cfg.py"
            case .ballKick:     return "microduck_ball_kick_env_cfg.py"
            case .roulade:      return "microduck_roulade_env_cfg.py"
            case .sitstand:     return "microduck_sitstand_env_cfg.py"
            case .groundPick:   return "microduck_ground_pick_env_cfg.py"
            case .rollerCrouch: return "microduck_roller_crouch_env_cfg.py"
            }
        }

        public static func forPolicy(_ filename: String) -> Task? {
            switch filename {
            case "alpha_walking.onnx":        return .velocity
            case "ball_kick_left.onnx",
                 "ball_kick_right.onnx":      return .ballKick
            case "roulade.onnx":              return .roulade
            case "BEST_alpha_sitstand.onnx":  return .sitstand
            case "alpha_ground_pick.onnx":    return .groundPick
            case "BEST_roller_crouch.onnx":   return .rollerCrouch
            default:                          return nil
            }
        }

        /// `upright`'s weight and variance in this config. Every one of these
        /// is read from the config file named above, not inferred.
        var upright: (weight: Double, variance: Double) {
            switch self {
            case .velocity, .ballKick: return (2.0, 0.05)
            case .groundPick:          return (0.2, 0.2)   // weight overridden; std left at mjlab's default
            // sitstand replaces `upright` with `upright_linear` and
            // `upright_while_tall`, and roulade with `roulade_upright_after_roll`
            // — different functions, so the shared term is not theirs to claim.
            case .sitstand, .roulade, .rollerCrouch: return (0, 0)
            }
        }

        var hasSharedUpright: Bool { upright.weight != 0 }

        /// `body_ang_vel`'s weight. Roulade's is nearly zero ON PURPOSE: the
        /// roll is angular velocity, so penalising it would penalise the task.
        var bodyAngularVelocityWeight: Double {
            switch self {
            case .velocity, .ballKick, .sitstand, .groundPick: return -0.05
            case .roulade:       return -0.002
            case .rollerCrouch:  return -0.05
            }
        }

        /// `action_rate_l2`'s weight. The velocity config starts at −0.1 and a
        /// curriculum ramps it to −1.0 by iteration 1500, so the trained policy
        /// lived under −1.0 and that is the figure worth showing.
        var actionRateWeight: Double {
            self == .velocity ? -1.0 : -0.1
        }

        /// Whether the command block is a velocity at all. It is a phase clock
        /// for ground-pick and a flag for sit/stand, so tracking a "commanded
        /// velocity" there would be arithmetic on a number that is not one.
        var commandIsATwist: Bool {
            self == .velocity || self == .rollerCrouch
        }

        /// Terms this config carries that a recording cannot answer, with the
        /// reason. Names are the config's own.
        var unevaluable: [(String, String)] {
            var shared: [(String, String)] = [
                ("angular_momentum", "reads a subtree angular-momentum sensor"),
                ("self_collisions", "reads a collision sensor"),
            ]
            switch self {
            case .velocity:
                shared += [
                    ("air_time", "reads the foot-contact sensor"),
                    ("foot_clearance", "reads the foot sites and the contact sensor"),
                    ("foot_swing_height", "reads the foot sites and the contact sensor"),
                    ("foot_slip", "reads the foot-contact sensor"),
                    ("dof_pos_limits", "scores against soft limits, which are a fraction of the model's travel that this app does not ship"),
                ]
            case .ballKick:
                shared += [
                    ("ball_forward_velocity", "reads the ball, which is not in the recording"),
                    ("ball_speed_overshoot", "reads the ball"),
                    ("support_foot_grounded", "reads the foot-contact sensor"),
                    ("height_stand", "measured, but its weight is not read from the config"),
                ]
            case .roulade:
                shared += [
                    ("roulade_progress", "scores the roll against a phase the recording does not carry"),
                    ("roulade_landing_composite", "reads the foot-contact sensor"),
                    ("gentle_landing", "reads contact impulses"),
                ]
            case .sitstand:
                shared += [
                    ("posture_composite", "scores against the commanded posture flag"),
                    ("head_pose_tracking", "scores against a head-pose command"),
                ]
            case .groundPick:
                shared += [
                    ("mouth_ground_proximity", "reads the mouth site against the floor"),
                    ("mouth_payload_force", "reads contact force at the mouth"),
                    ("feet_grounded", "reads the foot-contact sensor"),
                    ("head_impact_penalty", "reads contact impulses"),
                ]
            case .rollerCrouch:
                shared += [("wheel terms", "read the roller contacts")]
            }
            return shared
        }
    }

    /// What one joint did over the run.
    ///
    /// THE AGGREGATE HIDES THE ANSWER. "Total joint travel 41 rad" says the
    /// motion was busy; it does not say that the left ankle did a quarter of it
    /// while the head never moved, which is what tells you whether a motion is
    /// a gait, a reach, or a fall. And "3 joints reached a stop" is a count
    /// where the useful thing is WHICH, and for how long — a joint held against
    /// its stop is one the policy is still asking to move and cannot.
    public struct JointReading: Equatable, Sendable, Identifiable {
        public let name: String
        /// Summed absolute change over the run, radians.
        public let travel: Double
        /// Fastest single tick, radians per second.
        public let peakRate: Double
        /// Furthest from the home pose, radians, and when.
        public let peakDeviation: Double
        public let peakDeviationAt: TimeInterval
        /// Fraction of ticks spent within a milliradian of a travel stop.
        public let atStopFraction: Double
        /// Where the joint's travel actually is, so a deviation can be read
        /// against the room it had.
        public let travelSpan: Double
        public var id: String { name }

        /// How much of its available travel the joint used. A joint at 0.95 is
        /// working against its limits; one at 0.02 is along for the ride.
        public var usedFraction: Double {
            travelSpan > 0 ? min(peakDeviation / travelSpan, 1) : 0
        }
    }

    /// One reward term, and what this recording could say about it.
    public struct RewardTerm: Equatable, Sendable, Identifiable {
        public enum Standing: Equatable, Sendable {
            /// The term's own value, averaged over the run, and that value
            /// times the config's weight.
            case evaluated(mean: Double, weighted: Double)
            /// What the recording does not carry.
            case missing(String)
        }
        public let name: String
        public let weight: Double
        /// What the term rewards, in one line.
        public let purpose: String
        public let standing: Standing
        public var id: String { name }

        public var isEvaluated: Bool {
            if case .evaluated = standing { return true }
            return false
        }
    }

    // MARK: - the run

    public let clipName: String
    public let policy: String
    public let task: Task?
    /// True for a recording made before format 3, which stored joint angles and
    /// nothing else. Everything derived from actions, commands or the base
    /// twist is absent rather than zero.
    public let telemetryMissing: Bool

    public let travel: [Reading]
    public let attitude: [Reading]
    public let joints: [Reading]
    public let control: [Reading]
    public let rewards: [RewardTerm]
    /// Terms the config carries that no recording can answer.
    public let unevaluated: [Reading]
    /// How often the motion works when it is run again under varied
    /// conditions. Absent for a clip nobody has rolled out — an imported
    /// motion, for instance, whose sender ran it once.
    public let success: [Reading]
    /// The two rates as fractions, for anything that wants to draw them.
    public let achievedFraction: Double?
    public let repeatedFraction: Double?
    /// Joint by joint, sorted by how much work each did.
    public let perJoint: [JointReading]

    /// The single sentence to put above the panel.
    public var provenance: String {
        guard let task else {
            return "The training config for \(policy) is not one this build can name, so the "
                 + "measurements below stand alone and no reward is scored against them."
        }
        return "Reward weights and tolerances below are read from \(task.configFile) in "
             + "pollen-robotics/microduck_rl, the config that trained \(policy)."
    }

    // MARK: - building

    public init(clip: DuckIntentClip,
                success outcomes: DuckIntentSuccess? = nil) {
        clipName = clip.name
        policy = clip.policy
        task = Task.forPolicy(clip.policy)
        telemetryMissing = clip.telemetry.isEmpty

        let dt = 1.0 / clip.hz
        let roots = clip.roots
        let frames = clip.frames

        // ── travel ────────────────────────────────────────────────────────
        var path = 0.0, peakSpeed = 0.0
        for i in 1..<max(roots.count, 1) {
            let dx = roots[i].x - roots[i - 1].x
            let dy = roots[i].y - roots[i - 1].y
            let step = (dx * dx + dy * dy).squareRoot()
            path += step
            peakSpeed = max(peakSpeed, step / dt)
        }
        let first = roots.first, last = roots.last
        let netX = (last?.x ?? 0) - (first?.x ?? 0)
        let netY = (last?.y ?? 0) - (first?.y ?? 0)
        let net = (netX * netX + netY * netY).squareRoot()
        let heights = roots.map(\.z)

        travel = [
            Reading("Forward", Self.mm(netX),
                    "Along the heading it started on. Negative is backwards."),
            Reading("Sideways", Self.mm(netY)),
            Reading("Net displacement", Self.mm(net)),
            Reading("Path length", Self.mm(path),
                    path > net * 1.5 && net > 0.005
                        ? "Much longer than the net displacement — the robot did not travel in a straight line."
                        : nil),
            Reading("Mean speed", Self.speed(path / max(clip.duration, 1e-9))),
            Reading("Peak speed", Self.speed(peakSpeed)),
            Reading("Trunk height", "\(Self.mm(heights.min() ?? 0)) – \(Self.mm(heights.max() ?? 0))",
                    "The standing policy settles at 116 mm; sitting settles at 59 mm."),
            Reading("Net climb", Self.mm((last?.z ?? 0) - (first?.z ?? 0))),
        ]

        // ── attitude ──────────────────────────────────────────────────────
        var peakTilt = 0.0, tiltSum = 0.0, beyond45 = 0
        for root in roots {
            let tilt = Self.tilt(root.quaternion)
            peakTilt = max(peakTilt, tilt)
            tiltSum += tilt
            if tilt > .pi / 4 { beyond45 += 1 }
        }
        var peakYawRate = 0.0
        for i in 1..<max(roots.count, 1) {
            let a = Self.yaw(roots[i - 1].quaternion), b = Self.yaw(roots[i].quaternion)
            var d = b - a
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            peakYawRate = max(peakYawRate, abs(d) / dt)
        }
        attitude = [
            Reading("Starts / ends", "\(clip.startsFrom.rawValue) → \(clip.endsIn.rawValue)",
                    "Measured from trunk height and gravity over a ten-tick window, not from the clip's name."),
            Reading("Peak tilt", Self.degrees(peakTilt),
                    "Angle between the trunk's up and the world's."),
            Reading("Mean tilt", Self.degrees(tiltSum / Double(max(roots.count, 1)))),
            Reading("Past 45°", String(format: "%.2f s", Double(beyond45) * dt),
                    beyond45 > 0 ? "In the velocity and kick configs this is where `fell_over` ends an episode; sit/stand and roulade delete that termination, because falling is part of the task." : nil),
            Reading("Net rotation", String(format: "%+.2f rad", clip.netYaw),
                    "Unwrapped by summing per-tick deltas — a single angle cannot express more than half a turn."),
            Reading("Peak turn rate", String(format: "%.2f rad/s", peakYawRate)),
        ]

        // ── joints ────────────────────────────────────────────────────────
        var travelPerJoint = [Double](repeating: 0, count: DuckModel.policyJointCount)
        var peakJointSpeed = [Double](repeating: 0, count: DuckModel.policyJointCount)
        var atStop = [Int](repeating: 0, count: DuckModel.policyJointCount)
        for i in 0..<frames.count {
            for slot in 0..<min(frames[i].count, DuckModel.policyJointCount) {
                if i > 0, slot < frames[i - 1].count {
                    let d = abs(frames[i][slot] - frames[i - 1][slot])
                    travelPerJoint[slot] += d
                    peakJointSpeed[slot] = max(peakJointSpeed[slot], d / dt)
                }
                let range = DuckModel.jointRanges[DuckModel.jointOfPolicySlot(slot)]
                // Within a milliradian of the model's own travel: the joint is
                // against its stop, and everything the policy asked for beyond
                // that was thrown away by the clamp.
                if frames[i][slot] <= range.lower + 1e-3 || frames[i][slot] >= range.upper - 1e-3 {
                    atStop[slot] += 1
                }
            }
        }
        // Per joint, and the deviation measured separately because a joint can
        // travel a long way without ever going far from home — a gait does
        // exactly that — and the two numbers answer different questions.
        var peakDeviation = [Double](repeating: 0, count: DuckModel.policyJointCount)
        var peakDeviationAt = [TimeInterval](repeating: 0, count: DuckModel.policyJointCount)
        for (index, frame) in frames.enumerated() {
            for slot in 0..<min(frame.count, DuckModel.policyJointCount) {
                let joint = DuckModel.jointOfPolicySlot(slot)
                let deviation = abs(frame[slot] - DuckModel.homePose[joint])
                if deviation > peakDeviation[slot] {
                    peakDeviation[slot] = deviation
                    peakDeviationAt[slot] = Double(index) * dt
                }
            }
        }
        perJoint = (0..<DuckModel.policyJointCount).map { slot in
            let joint = DuckModel.jointOfPolicySlot(slot)
            let range = DuckModel.jointRanges[joint]
            return JointReading(
                name: DuckModel.jointNames[joint],
                travel: travelPerJoint[slot],
                peakRate: peakJointSpeed[slot],
                peakDeviation: peakDeviation[slot],
                peakDeviationAt: peakDeviationAt[slot],
                atStopFraction: frames.isEmpty ? 0
                    : Double(atStop[slot]) / Double(frames.count),
                travelSpan: max(abs(range.upper - DuckModel.homePose[joint]),
                                abs(DuckModel.homePose[joint] - range.lower)))
        }
        .sorted { $0.travel > $1.travel }

        let busiest = travelPerJoint.enumerated().max { $0.element < $1.element }
        let stopped = atStop.enumerated().filter { $0.element > 0 }
            .sorted { $0.element > $1.element }
        joints = [
            Reading("Busiest joint",
                    busiest.map { DuckModel.jointNames[DuckModel.jointOfPolicySlot($0.offset)] } ?? "—",
                    busiest.map { String(format: "%.2f rad of travel over the run", $0.element) }),
            Reading("Total joint travel", String(format: "%.1f rad", travelPerJoint.reduce(0, +)),
                    "Summed over all fourteen. A proxy for how much work the motion asks for, not for energy."),
            Reading("Peak joint speed", String(format: "%.1f rad/s", peakJointSpeed.max() ?? 0)),
            Reading("At a travel stop",
                    stopped.isEmpty ? "none" : "\(stopped.count) joint\(stopped.count == 1 ? "" : "s")",
                    stopped.isEmpty
                        ? "No joint reached the end of its range."
                        : stopped.prefix(4).map {
                            "\(DuckModel.jointNames[DuckModel.jointOfPolicySlot($0.offset)]) "
                            + "\(Int((Double($0.element) / Double(max(frames.count, 1)) * 100).rounded()))%"
                          }.joined(separator: ", ")
                          + ". A joint held against its stop is a joint the policy is still asking to move."),
        ]

        // ── what the policy emitted ───────────────────────────────────────
        let actions = clip.telemetry.actions
        if actions.isEmpty {
            control = [Reading("Actions", "not recorded",
                               "This clip predates format 3. Joint angles were stored; the network's own output was not.")]
        } else {
            var peakAction = 0.0, rateSum = 0.0
            for (i, a) in actions.enumerated() {
                for v in a { peakAction = max(peakAction, abs(v)) }
                guard i > 0 else { continue }
                var square = 0.0
                for slot in 0..<min(a.count, actions[i - 1].count) {
                    let d = a[slot] - actions[i - 1][slot]
                    square += d * d
                }
                rateSum += square
            }
            let meanRate = rateSum / Double(max(actions.count - 1, 1))
            control = [
                Reading("Peak action", String(format: "%.2f", peakAction),
                        "One raw output of the network, before the gait scales it by \(DuckModel.actionScale) and before the travel stops clamp it."),
                Reading("Action rate", String(format: "%.4f", meanRate),
                        "Mean squared change between consecutive decisions — the quantity `action_rate_l2` penalises."),
                Reading("Decisions", "\(actions.count)",
                        "One per tick at \(Int(clip.hz)) Hz."),
            ]
        }

        // ── Pollen's reward terms ─────────────────────────────────────────
        rewards = Self.rewardTerms(clip: clip, task: task, dt: dt)
        unevaluated = (task?.unevaluable ?? []).map { Reading($0.0, "not in a recording", $0.1) }

        // ── how often it works ────────────────────────────────────────────
        if let outcome = outcomes?[clip.name] {
            success = Self.successReadings(outcome, randomisation: outcomes?.randomisation)
            achievedFraction = outcome.achievedFraction
            repeatedFraction = outcome.repeatedFraction
        } else {
            success = []
            achievedFraction = nil
            repeatedFraction = nil
        }
    }

    /// TWO RATES, NEVER ONE. `achieves` asks whether the move did what it is
    /// FOR; `repeats` asks only whether it did again what it did the day it was
    /// recorded. They come apart on exactly the clips that matter — a stair
    /// move that reliably ends upright on the floor repeats perfectly and
    /// achieves nothing — and a single "success rate" would have to pick one of
    /// them silently.
    private static func successReadings(_ o: DuckIntentSuccess.Outcome,
                                        randomisation: DuckIntentSuccess.Randomisation?) -> [Reading] {
        var out: [Reading] = [
            Reading("Does what it is for", "\(o.achieves) of \(o.rollouts)", o.criterion),
            Reading("Ends as it was recorded", "\(o.repeats) of \(o.rollouts)",
                    o.recordedEnding.map { "The recording ended \($0)." }),
        ]
        if o.unstable > 0 {
            out.append(Reading("Physics gave up", "\(o.unstable) of \(o.rollouts)",
                               "The state went to NaN on a contact impulse. Neither a success "
                             + "nor a failure of the move — Pollen's config terminates on it too."))
        }
        if let median = o.medianHeight {
            out.append(Reading("Median finish height", mm(median),
                               o.worstHeight.map { "Worst run finished at \(mm($0))." }))
        }
        if !o.endings.isEmpty {
            let tally = o.endings.sorted { $0.value > $1.value }
                .map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")
            out.append(Reading("How the runs ended", "", tally))
        }
        if let randomisation {
            out.append(Reading("Varied between runs", "",
                               randomisation.lines.joined(separator: " · ")
                             + ". Read from \(randomisation.source)."))
        }
        return out
    }

    // MARK: - reward evaluation

    private static func rewardTerms(clip: DuckIntentClip, task: Task?, dt: Double) -> [RewardTerm] {
        guard let task else { return [] }
        var out: [RewardTerm] = []
        let roots = clip.roots
        let telemetry = clip.telemetry

        // upright = exp(-|projected gravity xy|² / std²)
        if task.hasSharedUpright, !roots.isEmpty {
            let (weight, variance) = task.upright
            let mean = roots.reduce(0.0) { $0 + exp(-gravityXYSquared($1.quaternion) / variance) }
                     / Double(roots.count)
            out.append(RewardTerm(
                name: "upright", weight: weight,
                purpose: "Holds the trunk level. Gravity projected into the body frame has no horizontal part when the robot is upright.",
                standing: .evaluated(mean: mean, weighted: mean * weight)))
        }

        // body_ang_vel = sum(ω_xy²), world frame.
        if !telemetry.twists.isEmpty, telemetry.twists.count == roots.count {
            let weight = task.bodyAngularVelocityWeight
            var sum = 0.0
            for (i, twist) in telemetry.twists.enumerated() where twist.count >= 6 {
                // The recording stores the trunk's angular velocity in its OWN
                // frame, which is where a free joint's angular velocity lives in
                // MuJoCo. mjlab reads the world-frame one, so it is rotated
                // here rather than compared across frames.
                let w = rotate(roots[i].quaternion, (twist[3], twist[4], twist[5]))
                sum += w.0 * w.0 + w.1 * w.1
            }
            let mean = sum / Double(max(telemetry.twists.count, 1))
            out.append(RewardTerm(
                name: "body_ang_vel", weight: weight,
                purpose: task == .roulade
                    ? "Penalises trunk pitch and roll rate — and is worth almost nothing here, because in a roll that rate is the point."
                    : "Penalises trunk pitch and roll rate. Yaw is deliberately not penalised.",
                standing: .evaluated(mean: mean, weighted: mean * weight)))
        } else {
            out.append(RewardTerm(
                name: "body_ang_vel", weight: task.bodyAngularVelocityWeight,
                purpose: "Penalises trunk pitch and roll rate.",
                standing: .missing("the trunk's twist was not recorded")))
        }

        // action_rate_l2 = sum((aₜ − aₜ₋₁)²)
        if telemetry.actions.count > 1 {
            var sum = 0.0
            for i in 1..<telemetry.actions.count {
                let a = telemetry.actions[i], b = telemetry.actions[i - 1]
                for slot in 0..<min(a.count, b.count) {
                    let d = a[slot] - b[slot]
                    sum += d * d
                }
            }
            let mean = sum / Double(telemetry.actions.count - 1)
            out.append(RewardTerm(
                name: "action_rate_l2", weight: task.actionRateWeight,
                purpose: task == .velocity
                    ? "Penalises jerky commands. The velocity config starts this at −0.1 and a curriculum ramps it to −1.0 by iteration 1500, so −1.0 is what the trained policy lived under."
                    : "Penalises jerky commands.",
                standing: .evaluated(mean: mean, weighted: mean * task.actionRateWeight)))
        } else {
            out.append(RewardTerm(
                name: "action_rate_l2", weight: task.actionRateWeight,
                purpose: "Penalises jerky commands.",
                standing: .missing("the network's own output was not recorded")))
        }

        // The two velocity-tracking terms, and `pose`, belong to the velocity
        // family. Elsewhere the command block is a clock or a flag, and reading
        // it as a twist would be arithmetic on a number that is not one.
        if task.commandIsATwist {
            let commands = telemetry.commands, twists = telemetry.twists
            if commands.count == twists.count, !commands.isEmpty {
                var linear = 0.0, angular = 0.0, pose = 0.0
                for i in 0..<commands.count {
                    let c = commands[i], t = twists[i]
                    guard c.count >= 3, t.count >= 6 else { continue }
                    let ex = c[0] - t[0], ey = c[1] - t[1]
                    linear += exp(-(ex * ex + ey * ey + t[2] * t[2]) / 0.1)
                    let ez = c[2] - t[5]
                    angular += exp(-(ez * ez + t[3] * t[3] + t[4] * t[4]) / 0.5)
                    pose += posture(frame: i < clip.frames.count ? clip.frames[i] : [],
                                    command: c)
                }
                let n = Double(commands.count)
                out.append(RewardTerm(
                    name: "track_linear_velocity", weight: 2.0,
                    purpose: "Rewards matching the commanded forward and sideways velocity, and staying level. std² = 0.1.",
                    standing: .evaluated(mean: linear / n, weighted: linear / n * 2.0)))
                out.append(RewardTerm(
                    name: "track_angular_velocity", weight: 2.0,
                    purpose: "Rewards matching the commanded turn rate while not pitching or rolling. std² = 0.5.",
                    standing: .evaluated(mean: angular / n, weighted: angular / n * 2.0)))
                out.append(RewardTerm(
                    name: "pose", weight: 1.0,
                    purpose: "Holds the legs near the home stance, with a per-joint tolerance that loosens once a velocity is commanded.",
                    standing: .evaluated(mean: pose / n, weighted: pose / n)))
            } else {
                for name in ["track_linear_velocity", "track_angular_velocity", "pose"] {
                    out.append(RewardTerm(
                        name: name, weight: name == "pose" ? 1.0 : 2.0,
                        purpose: "Scored against the command the policy was given.",
                        standing: .missing("the command and the trunk's twist were not recorded")))
                }
            }
        }
        return out
    }

    /// `variable_posture`: `exp(-mean((q − q_home)² / std²))` over the LEG
    /// joints, with the tolerance chosen by how fast the robot was told to go.
    /// Both dictionaries are `microduck_velocity_env_cfg`'s own.
    private static func posture(frame: [Double], command: [Double]) -> Double {
        guard frame.count >= DuckModel.policyJointCount, command.count >= 3 else { return 0 }
        let speed = (command[0] * command[0] + command[1] * command[1]).squareRoot()
                  + abs(command[2])
        // walking_threshold = 0.01, and the running std is set to the walking
        // one, so there are two regimes rather than three.
        let standing = speed < 0.01
        var sum = 0.0, count = 0
        for slot in 0..<DuckModel.policyJointCount {
            let joint = DuckModel.jointOfPolicySlot(slot)
            let name = DuckModel.jointNames[joint]
            guard let std = legStd(name, standing: standing) else { continue }
            let d = frame[slot] - DuckModel.homePose[joint]
            sum += (d * d) / (std * std)
            count += 1
        }
        guard count > 0 else { return 0 }
        return exp(-sum / Double(count))
    }

    /// Per-joint tolerance, radians. `nil` for anything the term excludes —
    /// the config's regex drops the neck and head, because those are driven by
    /// a pose command and pulling them home too would teach the policy to
    /// ignore it.
    private static func legStd(_ name: String, standing: Bool) -> Double? {
        if name.contains("hip_yaw")   { return standing ? 0.1  : 0.3  }
        if name.contains("hip_roll")  { return 0.05 }
        if name.contains("hip_pitch") { return standing ? 0.15 : 0.4  }
        if name.contains("knee")      { return standing ? 0.15 : 0.4  }
        if name.contains("ankle")     { return standing ? 0.1  : 0.25 }
        return nil
    }

    // MARK: - geometry

    /// `|projected gravity xy|²`: gravity is (0, 0, −1) in the world, and this
    /// is the squared length of its horizontal part once rotated into the
    /// trunk's frame. Zero when upright, 1 when the trunk is on its side.
    static func gravityXYSquared(_ q: (Double, Double, Double, Double)) -> Double {
        let (w, x, y, z) = q
        let gx = -2 * (x * z + w * y)
        let gy = -2 * (y * z - w * x)
        return gx * gx + gy * gy
    }

    /// Angle between the trunk's up and the world's, radians.
    static func tilt(_ q: (Double, Double, Double, Double)) -> Double {
        let (_, x, y, _) = q
        // The trunk's own +z, expressed in the world, has z-component
        // 1 − 2(x² + y²). The angle to the world's up is its arccosine.
        let up = 1 - 2 * (x * x + y * y)
        return acos(min(max(up, -1), 1))
    }

    static func yaw(_ q: (Double, Double, Double, Double)) -> Double {
        let (w, x, y, z) = q
        return atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
    }

    /// Rotate a body-frame vector into the world.
    static func rotate(_ q: (Double, Double, Double, Double),
                       _ v: (Double, Double, Double)) -> (Double, Double, Double) {
        let (w, x, y, z) = q
        let tx = 2 * (y * v.2 - z * v.1)
        let ty = 2 * (z * v.0 - x * v.2)
        let tz = 2 * (x * v.1 - y * v.0)
        return (v.0 + w * tx + (y * tz - z * ty),
                v.1 + w * ty + (z * tx - x * tz),
                v.2 + w * tz + (x * ty - y * tx))
    }

    // MARK: - formatting

    static func mm(_ metres: Double) -> String {
        String(format: "%+.0f mm", metres * 1000)
    }
    static func speed(_ metresPerSecond: Double) -> String {
        String(format: "%.0f mm/s", metresPerSecond * 1000)
    }
    static func degrees(_ radians: Double) -> String {
        String(format: "%.0f°", radians * 180 / .pi)
    }
}
