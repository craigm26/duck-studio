import Foundation

/// What your picks say you care about, and the reward that follows from it.
///
/// THE MODEL IS duckbatch's, PORTED SO IT RUNS ON THE PHONE (`preference.py` `fit`):
///
///     P(a ≻ b) = σ( w · (φ_a − φ_b) + β · [a was shown on the left] )
///
/// φ are the seven `PreferenceFeatures`, standardised over the picks themselves; w is the
/// taste; β is the side bias, kept in the model because people favour a side and a model that
/// cannot see that learns it as taste. Regularised logistic regression by Newton's method,
/// L2 0.01, the same as duckbatch, and `PreferenceModelTests` holds the two to the same numbers.
///
/// THE REWARD IS POLLEN'S, RE-WEIGHTED, NOT INVENTED. Each feature belongs to reward terms
/// VelStand already trains with, and the fitted taste scales those terms' weights between half
/// and double Pollen's. Picks therefore change WHAT THE TRAINER CARES MORE ABOUT, within bounds
/// that keep it a walking task. A linear seven-feature taste is closer to re-weighting a reward
/// than to a learned reward model, and the sentences say so.
public enum PreferenceModel {

    /// One pick, as the model needs it.
    public struct Pick: Equatable, Sendable {
        public let a: [Double]          // features of the side recorded as `a`
        public let b: [Double]
        public let aWasLeft: Bool
        /// 1 if `a` was chosen, 0 if `b`, 0.5 for a tie.
        public let outcome: Double

        public init(a: [Double], b: [Double], aWasLeft: Bool, outcome: Double) {
            self.a = a; self.b = b; self.aWasLeft = aWasLeft; self.outcome = outcome
        }
    }

    public struct Taste: Equatable, Sendable {
        /// One weight per `PreferenceFeatures.names`, on standardised features.
        public let weights: [Double]
        public let sideBias: Double
        public let picks: Int

        public init(weights: [Double], sideBias: Double, picks: Int) {
            self.weights = weights; self.sideBias = sideBias; self.picks = picks
        }
    }

    /// p001 (duckbatch `notes/2026-09-24-p001-close.md`): held-out accuracy reaches the noise
    /// ceiling by about 100 choices. Below that the fitted taste is still moving.
    public static let minimumPicks = 100

    // MARK: - reading picks back

    /// Every network-vs-network pick in a feedback log that carries features.
    ///
    /// Motions and sequences are left out: PPO trains a network, and a taste learned from
    /// which keyframe track somebody liked is not a taste about a walking policy. "Both bad"
    /// says nothing about which was better and is left out too, as duckbatch leaves it out.
    public static func picks(fromLog log: String) -> [Pick] {
        picks(fromLog: log, profile: .walk)
    }

    /// Every pick in the log that teaches this profile's taste.
    ///
    /// WALKING reads Compare's `preference` records, whose features the phone measured (above).
    /// A SKILL reads `policy_preference` records from a recorded skill pack: they carry the
    /// skill's slot and the features the SIMULATOR measured, because a phone clip has no ball
    /// and cannot measure a kick. A pick is only ever read into the profile whose feature names
    /// it carries, so a kick pick never moves the walking taste and the other way round.
    public static func picks(fromLog log: String, profile: Profile) -> [Pick] {
        guard profile.skill != Profile.walk.skill else { return walkPicks(log) }
        return log.split(separator: "\n").compactMap { line -> Pick? in
            guard let root = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  root["kind"] as? String == "policy_preference",
                  let body = root["policy_preference"] as? [String: Any],
                  body["skill"] as? String == profile.skill,
                  let f = body["features"] as? [String: Any],
                  f["names"] as? [String] == profile.featureNames,
                  let a = f["a"] as? [Double], let b = f["b"] as? [Double],
                  a.count == profile.featureNames.count, b.count == a.count,
                  let choice = body["choice"] as? String,
                  let outcome = ["a": 1.0, "b": 0.0, "tie": 0.5][choice]
            else { return nil }
            let order = (body["shown"] as? [String: Any])?["order"] as? String
            return Pick(a: a, b: b, aWasLeft: order == "a_left", outcome: outcome)
        }
    }

    private static func walkPicks(_ log: String) -> [Pick] {
        log.split(separator: "\n").compactMap { line -> Pick? in
            guard let root = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  root["kind"] as? String == "preference",
                  let body = root["preference"] as? [String: Any],
                  (body["a"] as? [String: Any])?["kind"] as? String == "policy",
                  (body["b"] as? [String: Any])?["kind"] as? String == "policy",
                  let f = body["features"] as? [String: Any],
                  f["names"] as? [String] == PreferenceFeatures.names,
                  let a = f["a"] as? [Double], let b = f["b"] as? [Double],
                  a.count == PreferenceFeatures.names.count, b.count == a.count,
                  let choice = body["choice"] as? String,
                  let outcome = ["a": 1.0, "b": 0.0, "tie": 0.5][choice]
            else { return nil }
            let order = (body["shown"] as? [String: Any])?["order"] as? String
            return Pick(a: a, b: b, aWasLeft: order == "a_left", outcome: outcome)
        }
    }

    // MARK: - fitting

    /// Fit the taste. Standardisation is over every feature row the picks carry.
    public static func fit(_ picks: [Pick], l2: Double = 1e-2, iterations: Int = 50) -> Taste {
        let k = picks.first?.a.count ?? PreferenceFeatures.names.count
        let rows = picks.flatMap { [$0.a, $0.b] }
        var mean = [Double](repeating: 0, count: k), std = [Double](repeating: 0, count: k)
        if !rows.isEmpty {
            for j in 0..<k { mean[j] = rows.map { $0[j] }.reduce(0, +) / Double(rows.count) }
            for j in 0..<k {
                let v = rows.map { ($0[j] - mean[j]) * ($0[j] - mean[j]) }.reduce(0, +) / Double(rows.count)
                std[j] = v.squareRoot() + 1e-9
            }
        }
        // Design: standardised difference, then the side column.
        var x: [[Double]] = []
        for p in picks {
            var row: [Double] = []
            for j in 0..<k {
                let za: Double = (p.a[j] - mean[j]) / std[j]
                let zb: Double = (p.b[j] - mean[j]) / std[j]
                row.append(za - zb)
            }
            row.append(p.aWasLeft ? 1 : 0)
            x.append(row)
        }
        let y = picks.map(\.outcome)
        let d = k + 1
        var theta = [Double](repeating: 0, count: d)
        for _ in 0..<iterations {
            var g = [Double](repeating: 0, count: d)
            var h = [[Double]](repeating: [Double](repeating: 0, count: d), count: d)
            for (row, target) in zip(x, y) {
                let z = zip(row, theta).reduce(0) { $0 + $1.0 * $1.1 }
                let p = 1 / (1 + exp(-z))
                for i in 0..<d {
                    g[i] += row[i] * (p - target)
                    for j in 0..<d { h[i][j] += row[i] * row[j] * p * (1 - p) }
                }
            }
            for i in 0..<d { g[i] += l2 * theta[i]; h[i][i] += l2 }
            guard let step = solve(h, g) else { break }
            for i in 0..<d { theta[i] -= step[i] }
            if step.map(abs).max() ?? 0 < 1e-8 { break }
        }
        return Taste(weights: Array(theta.prefix(k)), sideBias: theta[k], picks: picks.count)
    }

    /// Gaussian elimination with partial pivoting; nil if the system is singular.
    static func solve(_ a: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var m = a, v = b
        for c in 0..<n {
            guard let p = (c..<n).max(by: { abs(m[$0][c]) < abs(m[$1][c]) }), abs(m[p][c]) > 1e-15
            else { return nil }
            m.swapAt(c, p); v.swapAt(c, p)
            for r in (c + 1)..<n {
                let f = m[r][c] / m[c][c]
                for j in c..<n { m[r][j] -= f * m[c][j] }
                v[r] -= f * v[c]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            let s = ((r + 1)..<n).reduce(0) { $0 + m[r][$1] * x[$1] }
            x[r] = (v[r] - s) / m[r][r]
        }
        return x
    }

    // MARK: - from taste to reward

    /// One group of features and the VelStand reward terms it steers, with Pollen's weights.
    public struct Group: Equatable, Sendable {
        public let name: String
        public let said: String
        public let features: [String]
        /// mjlab reward term → Pollen's weight in Mjlab-VelStand-Flat-MicroDuck
        /// (read from the task config, microduck_rl cb70b79, 2026-10-02).
        public let terms: [String: Double]
    }

    public static let groups: [Group] = [
        Group(name: "tracking", said: "going the speed you asked",
              features: ["lin_err"], terms: ["track_linear_velocity": 2.0]),
        Group(name: "turning", said: "turning the rate you asked",
              features: ["ang_err"], terms: ["track_angular_velocity": 2.0]),
        Group(name: "upright", said: "staying on its feet",
              features: ["fell", "down_frac"], terms: ["upright": 2.0]),
        Group(name: "smooth", said: "moving smoothly",
              features: ["action_rate", "jitter"], terms: ["action_rate_l2": -1.0]),
        Group(name: "steady", said: "keeping the body steady",
              features: ["wobble"], terms: ["body_ang_vel": -0.05, "angular_momentum": -0.02]),
    ]

    public struct RewardPlan: Equatable, Sendable {
        /// Group name → multiplier on Pollen's weights, in [0.5, 2].
        public let multipliers: [String: Double]
        /// Term → the weight to train with.
        public let weights: [String: Double]
        /// Groups the picks favoured the "wrong" way (more error, more falls), left at 1×.
        public let reversed: [String]
    }

    public static let multiplierRange: ClosedRange<Double> = 0.5...2.0

    /// Every feature is something less of is better, so a group's importance is how strongly
    /// the picks pushed AWAY from it: −Σ w over its features. Importances are divided by their
    /// mean, so a group your picks weighted like the average stays at Pollen's weight, and
    /// clamped to [0.5, 2].
    public static func rewardPlan(from taste: Taste) -> RewardPlan {
        rewardPlan(from: taste, profile: .walk)
    }

    public static func rewardPlan(from taste: Taste, profile: Profile) -> RewardPlan {
        let groups = profile.groups
        let index = Dictionary(uniqueKeysWithValues: profile.featureNames.enumerated().map { ($1, $0) })
        let pull = groups.map { g in -g.features.reduce(0) { $0 + taste.weights[index[$1]!] } }
        let positive = pull.filter { $0 > 0 }
        let mean = positive.isEmpty ? 1 : positive.reduce(0, +) / Double(positive.count)
        var multipliers: [String: Double] = [:], weights: [String: Double] = [:], reversed: [String] = []
        for (g, p) in zip(groups, pull) {
            let m: Double
            if p <= 0 {
                m = 1; reversed.append(g.name)
            } else {
                m = min(max(p / mean, multiplierRange.lowerBound), multiplierRange.upperBound)
            }
            multipliers[g.name] = m
            for (term, w) in g.terms { weights[term] = w * m }
        }
        return RewardPlan(multipliers: multipliers, weights: weights, reversed: reversed)
    }

    // MARK: - one taste per skill

    /// What a taste is about: the features a pick carries and the reward terms they steer.
    ///
    /// PER SKILL, BECAUSE WHAT MAKES A GOOD KICK IS NOT WHAT MAKES A GOOD WALK. A walking taste
    /// is about tracking the command; a kick has no command, and what a person watching one
    /// judges is where the ball went. Each profile has its own features, its own groups mapped
    /// onto that skill's own task, and its own pick count.
    public struct Profile: Equatable, Sendable {
        /// `walk`, or the robotd slot a skill fills (`kick_right`, `kick_left`).
        public let skill: String
        public let featureNames: [String]
        public let groups: [Group]
        /// "walkers", "right kicks": what a person chose between.
        public let plural: String
        /// The duckbatch task a recipe trains in, and the network it starts from.
        public let task: String
        public let teacher: String
        /// Terms the recipe ADDS because Pollen's task has none for what the group is about
        /// (k001's `ball_lateral_speed`), with the function duckbatch implements it as.
        public let added: [String: String]

        public static let walk = Profile(
            skill: "walk", featureNames: PreferenceFeatures.names, groups: PreferenceModel.groups,
            plural: "walkers", task: "Mjlab-VelStand-Flat-MicroDuck",
            teacher: "teachers/velstand.onnx", added: [:])

        /// duckbatch `kick_pairs.FEATURES`, in order, measured in the simulator.
        public static let kickFeatureNames = ["off_angle", "speed_err", "fell", "foot_lift",
                                              "action_rate", "jitter", "wobble"]

        /// BallKick's terms with Pollen's weights (microduck_ball_kick_env_cfg, microduck_rl
        /// 8d0db74, read 2026-10-03), plus k001's sideways-ball term.
        ///
        /// SMOOTHNESS IS FITTED AND NOT TRAINED. Pollen's kick task ramps `action_rate_l2` with
        /// a curriculum (−0.1 → −1.0 by iteration 1500) that rewrites the weight as it goes, so
        /// a multiplier set here would be overwritten within the run. The group stays in the
        /// model, so smoothness can explain a pick instead of leaking into the other groups, and
        /// it maps to no term.
        public static let kickGroups: [Group] = [
            Group(name: "straight", said: "sending the ball straight",
                  features: ["off_angle"], terms: ["ball_lateral_speed": -12.0]),
            Group(name: "tap", said: "kicking at the speed Pollen trained for",
                  features: ["speed_err"],
                  terms: ["ball_forward_velocity": 12.0, "ball_speed_overshoot": -4.0]),
            Group(name: "upright", said: "staying on its feet and its support foot",
                  features: ["fell", "foot_lift"],
                  terms: ["upright": 2.0, "support_foot_grounded": 2.0]),
            Group(name: "smooth", said: "moving smoothly (fitted, not trained: Pollen's curriculum owns it)",
                  features: ["action_rate", "jitter"], terms: [:]),
            Group(name: "steady", said: "keeping the body steady",
                  features: ["wobble"], terms: ["body_ang_vel": -0.05, "angular_momentum": -0.02]),
        ]

        public static let kickRight = Profile(
            skill: "kick_right", featureNames: kickFeatureNames, groups: kickGroups,
            plural: "right kicks", task: "Mjlab-BallKick-Flat-MicroDuck",
            teacher: "teachers/ball_kick_right.onnx",
            added: ["ball_lateral_speed": "duckbatch.rewards.ball_lateral_speed"])

        public static let kickLeft = Profile(
            skill: "kick_left", featureNames: kickFeatureNames, groups: kickGroups,
            plural: "left kicks", task: "Duckbatch-BallKick-Left-Flat-MicroDuck",
            teacher: "teachers/ball_kick_left.onnx",
            added: ["ball_lateral_speed": "duckbatch.rewards.ball_lateral_speed"])

        public static let all: [Profile] = [.walk, .kickRight, .kickLeft]

        public static func named(_ skill: String) -> Profile? { all.first { $0.skill == skill } }
    }

    // MARK: - what is said

    public static func notEnoughPicks(_ n: Int, profile: Profile) -> String {
        guard profile.skill != Profile.walk.skill else { return notEnoughPicks(n) }
        return "\(n) of \(minimumPicks) picks between two \(profile.plural). Below about "
             + "\(minimumPicks) the taste the picks describe is still moving, so training from it "
             + "would be training from noise. Keep choosing in \(profile.plural.capitalized)."
    }

    public static func notEnoughPicks(_ n: Int) -> String {
        "\(n) of \(minimumPicks) picks between two networks. Below about \(minimumPicks) the taste "
      + "the picks describe is still moving (duckbatch's sizing study, p001), so training from it "
      + "would be training from noise. Keep comparing walkers in Compare."
    }

    public static let whatThisDoes =
        "Your picks between walkers are learned as a taste over seven things the clips show, "
      + "then used to re-weight five of the reward terms Pollen trains with, between half and "
      + "double their usual weight. That is reinforcement learning from human feedback (RLHF) "
      + "in its simplest form: your choices set what the trainer cares more about. "
      + "This is not a reward model: it re-weights the reward Pollen already wrote."
}
