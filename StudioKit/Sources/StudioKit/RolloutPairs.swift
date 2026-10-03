import Foundation
import DuckKit

/// Two trained networks doing the same thing in the same simulated world,
/// recorded, for a person to watch side by side and say which looks better —
/// `duck-preference-pairs/0`, which craigm26/duckbatch's
/// `scripts/export_pairs_for_app.py` writes from its p001 rollouts.
///
/// WHY RECORDED AND NOT RUN HERE. `PreferenceSearchView` says it plainly: a
/// walking network cannot be rolled out on a phone, because it times its gait
/// against contact and a phone has no floor. p001 ran every network in MuJoCo
/// from one seed, under one command, in one env per pair, so the only
/// difference between the two ducks on screen is the network. The frames are
/// the simulator's; nothing here computes a step.
///
/// THE SAME WORLD ON BOTH SIDES. A pair is (command, env): both clips start
/// from that env's reset under the same seed. Showing policy A in env 0 against
/// policy B in env 2 would be comparing starting conditions as well as gaits.
///
/// CLOSE PAIRS FIRST, and the numbers that made them close are NOT shown.
/// p001 found a person's choice teaches most when the two are hard to tell
/// apart, so the deck takes each command's closest pairs before its obvious
/// ones. The behaviour features behind that order stay in duckbatch: a rater
/// shown "fell: 3%" is rating the number, not the duck.
public struct RolloutPairs: Sendable {

    public static let format = "duck-preference-pairs/0"
    public static let readableFormats: Set<String> = [format]

    /// One frame: x, y, z, qw, qx, qy, qz, then all 15 joints in
    /// `DuckModel.jointNames` order.
    public static let frameWidth = 7 + DuckModel.jointCount

    public let batch: String
    public let seed: Int
    public let hz: Double
    public let seconds: Double
    public let envs: Int
    public let policies: [String: DuckFeedback.Policy]
    /// Twist commands by name, `[vx, vy, wz]`.
    public let commands: [String: [Double]]
    /// Command names, in a stable order.
    public let commandNames: [String]
    /// Per command, the policy pairs closest first.
    public let closeFirst: [String: [(a: String, b: String)]]
    /// Per command, the envs worth showing. The exporter drops a slot where no
    /// policy stepped under a moving command — the command never reached that
    /// env, and two motionless ducks under "walk forward" ask a person nothing.
    /// A file without the field is read as every env usable.
    public let usableEnvs: [String: [Int]]
    private let clips: [String: [[[Double]]]]
    /// The robotd slot a skill pack's networks fill (`kick_right`); nil for walkers.
    public let skill: String?
    /// The ball, per clip key and env, one [x, y, z] per frame. Empty for walkers.
    private let balls: [String: [[[Double]]]]
    /// Features the simulator measured, per clip key and env (`features.names` order).
    public let featureNames: [String]
    private let featureValues: [String: [[Double]]]

    // MARK: - reading

    public enum ReadError: Error, Equatable {
        case notJSON
        case wrongFormat(String)
        case missing(String)
        case badFrame(String)

        public var message: String {
            switch self {
            case .notJSON: return "The recorded pairs are not JSON."
            case .wrongFormat(let f): return "The recorded pairs are in format \"\(f)\", which this version does not read."
            case .missing(let what): return "The recorded pairs are missing \(what)."
            case .badFrame(let clip): return "A frame in \(clip) is not the width the stage draws, so the pairs were not loaded."
            }
        }
    }

    public static func read(_ data: Data) throws -> RolloutPairs {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        guard let format = top["format"] as? String else { throw ReadError.missing("a format") }
        guard readableFormats.contains(format) else { throw ReadError.wrongFormat(format) }
        guard let hz = top["hz"] as? Double, hz > 0 else { throw ReadError.missing("a frame rate") }
        guard let envs = top["envs"] as? Int, envs > 0 else { throw ReadError.missing("an env count") }
        let source = top["source"] as? [String: Any] ?? [:]

        guard let rawPolicies = top["policies"] as? [String: [String: String]] else {
            throw ReadError.missing("its policies")
        }
        var policies: [String: DuckFeedback.Policy] = [:]
        for (name, p) in rawPolicies {
            guard let repo = p["repo"], let print = p["fingerprint"], print.hasPrefix("sha256:") else {
                throw ReadError.missing("a repository and fingerprint for \(name)")
            }
            policies[name] = DuckFeedback.Policy(repo: repo, file: p["file"], fingerprint: print)
        }
        guard let commands = top["commands"] as? [String: [Double]] else {
            throw ReadError.missing("its commands")
        }
        guard let rawClose = top["close_first"] as? [String: [[String: Any]]] else {
            throw ReadError.missing("its pair order")
        }
        var closeFirst: [String: [(a: String, b: String)]] = [:]
        for (command, rows) in rawClose {
            closeFirst[command] = rows.compactMap { row in
                guard let a = row["a"] as? String, let b = row["b"] as? String,
                      policies[a] != nil, policies[b] != nil else { return nil }
                return (a, b)
            }
        }
        guard let rawClips = top["clips"] as? [String: [[[Double]]]] else {
            throw ReadError.missing("its clips")
        }
        for (key, perEnv) in rawClips {
            guard perEnv.count == envs, perEnv.allSatisfy({ !$0.isEmpty }) else {
                throw ReadError.missing("\(envs) envs in \(key)")
            }
            guard perEnv.allSatisfy({ $0.allSatisfy { $0.count == frameWidth } }) else {
                throw ReadError.badFrame(key)
            }
        }
        for name in policies.keys {
            for command in commands.keys where rawClips["\(name)__\(command)"] == nil {
                throw ReadError.missing("the clip of \(name) under \(command)")
            }
        }
        var usableEnvs: [String: [Int]] = [:]
        let rawUsable = top["usable_envs"] as? [String: [Int]]
        for command in commands.keys {
            usableEnvs[command] = (rawUsable?[command] ?? Array(0..<envs)).filter { (0..<envs).contains($0) }
        }
        // A SKILL PACK MUST CARRY ITS FEATURES. A phone cannot measure a kick (a clip has no
        // ball), so a skill pick without the simulator's numbers would teach nothing.
        let skill = top["skill"] as? String
        let rawBalls = top["ball"] as? [String: [[[Double]]]] ?? [:]
        let rawFeatures = top["features"] as? [String: Any]
        let names = rawFeatures?["names"] as? [String] ?? []
        let values = rawFeatures?["values"] as? [String: [[Double]]] ?? [:]
        if skill != nil {
            guard !names.isEmpty else { throw ReadError.missing("the features its skill picks are fitted over") }
            for key in rawClips.keys {
                guard let v = values[key], v.count == envs, v.allSatisfy({ $0.count == names.count }) else {
                    throw ReadError.missing("features for every env of \(key)")
                }
            }
        }
        return RolloutPairs(
            batch: source["batch"] as? String ?? "p001",
            seed: source["seed"] as? Int ?? 0,
            hz: hz, seconds: top["seconds"] as? Double ?? 0, envs: envs,
            policies: policies, commands: commands, commandNames: commands.keys.sorted(),
            closeFirst: closeFirst, usableEnvs: usableEnvs, clips: rawClips,
            skill: skill, balls: rawBalls, featureNames: names, featureValues: values)
    }

    // MARK: - drawing

    /// How long one clip lasts.
    public func duration(_ policy: String, _ command: String, env: Int) -> TimeInterval {
        Double(max((clips["\(policy)__\(command)"]?[env].count ?? 1) - 1, 1)) / hz
    }

    /// The pose at a time, between recorded frames. Holds the last frame past
    /// the end rather than looping: a rollout is one attempt, and a duck that
    /// fell at 7 s should stay fallen rather than stand up again at 8.
    public func stance(_ policy: String, _ command: String, env: Int,
                       at time: TimeInterval) -> DuckStance {
        guard let frames = clips["\(policy)__\(command)"]?[env], let first = frames.first else {
            return .home
        }
        let exact = max(0, time) * hz
        let i = min(Int(exact.rounded(.down)), frames.count - 1)
        let j = min(i + 1, frames.count - 1)
        let f = i == j ? 0 : exact - Double(i)
        let a = frames[i], b = frames[j]
        func mix(_ k: Int) -> Double { a[k] + (b[k] - a[k]) * f }
        // THE QUATERNION IS NORMALISED AFTER MIXING and flipped onto a's
        // hemisphere first, so a sign change between frames (q and -q are the
        // same turn) interpolates through the short way rather than spinning.
        let dot = (3...6).map { a[$0] * b[$0] }.reduce(0, +)
        let s = dot < 0 ? -1.0 : 1.0
        var q = (3...6).map { a[$0] + (s * b[$0] - a[$0]) * f }
        let n = sqrt(q.map { $0 * $0 }.reduce(0, +))
        q = n > 0 ? q.map { $0 / n } : [first[3], first[4], first[5], first[6]]
        return DuckStance(jointAngles: (7..<RolloutPairs.frameWidth).map(mix),
                          root: DuckIntentClip.Root(x: mix(0), y: mix(1), z: mix(2),
                                                    quaternion: (q[0], q[1], q[2], q[3])))
    }

    /// Where the ball is at a time, between recorded frames; nil for a pack without one. Holds
    /// the last frame past the end, as `stance` does.
    public func ball(_ policy: String, _ command: String, env: Int,
                     at time: TimeInterval) -> (x: Double, y: Double, z: Double)? {
        guard let frames = balls["\(policy)__\(command)"]?[env], !frames.isEmpty else { return nil }
        let exact = max(0, time) * hz
        let i = min(Int(exact.rounded(.down)), frames.count - 1)
        let j = min(i + 1, frames.count - 1)
        let f = i == j ? 0 : exact - Double(i)
        func mix(_ k: Int) -> Double { frames[i][k] + (frames[j][k] - frames[i][k]) * f }
        return (mix(0), mix(1), mix(2))
    }

    public var hasBall: Bool { !balls.isEmpty }

    /// The simulator's features for one clip, in `featureNames` order.
    public func features(_ policy: String, _ command: String, env: Int) -> [Double]? {
        featureValues["\(policy)__\(command)"]?[env]
    }

    // MARK: - one showing

    /// One pair on screen: which two, under what, and which side each is on.
    public struct Showing: Equatable, Sendable {
        public let command: String
        public let env: Int
        /// The pair as duckbatch lists it. `a` and `b` are the record's names;
        /// which of them is on the left is `order`.
        public let a: String
        public let b: String
        public let order: DuckFeedback.Order

        public var left: String { order == .aLeft ? a : b }
        public var right: String { order == .aLeft ? b : a }
        /// duckbatch's pair id, so the trajectory a person saw can be looked up.
        public func pairID(batch: String) -> String { "\(batch)/\(command)/\(env)" }
    }

    /// What the person pressed, in screen terms.
    public enum Pick: Sendable, CaseIterable { case left, right, tie, bothBad }

    /// Their press as a `duck-feedback/0` preference. Left and right are turned
    /// back into a and b here, through `order`, so the record says which
    /// NETWORK was chosen and separately which side it was on.
    public func record(_ pick: Pick, reasons: [DuckFeedback.Reason], for showing: Showing,
                       share: DuckFeedback.Share, client: String,
                       at when: Date = Date()) throws -> DuckFeedback {
        let choice: DuckFeedback.Choice
        switch pick {
        case .left: choice = showing.order == .aLeft ? .a : .b
        case .right: choice = showing.order == .aLeft ? .b : .a
        case .tie: choice = .tie
        case .bothBad: choice = .bothBad
        }
        guard let a = policies[showing.a], let b = policies[showing.b] else {
            throw ReadError.missing("the networks in that pair")
        }
        var sim: DuckFeedback.SimFeatures?
        if let fa = features(showing.a, showing.command, env: showing.env),
           let fb = features(showing.b, showing.command, env: showing.env) {
            sim = .init(names: featureNames, a: fa, b: fb)
        }
        return try DuckFeedback.policyPreference(
            a: a, b: b, choice: choice, reasons: reasons, where: .sim, order: showing.order,
            command: commands[showing.command], seconds: seconds, seed: seed,
            pairID: showing.pairID(batch: batch), skill: skill, features: sim,
            share: share, client: client, created: when)
    }
}

/// The order pairs are shown in: every command's closest pair before any
/// command's second-closest, envs taken in turn, sides drawn at random.
///
/// THE SIDE IS RANDOM AND RECORDED. People favour a side, and p001 measured
/// that a model needs about 800 choices to see that bias at all — so it has to
/// be drawn fairly and written into every record, not inferred afterwards.
/// The generator is passed in so a test can pin it.
public struct PreferenceDeck: Sendable {
    public let pairs: RolloutPairs
    public private(set) var shown = 0

    public init(_ pairs: RolloutPairs, startingAt shown: Int = 0) {
        self.pairs = pairs
        self.shown = shown
    }

    /// The (command, env, pair) at a position in the deck, before the side is drawn.
    public func slot(_ n: Int) -> (command: String, env: Int, a: String, b: String)? {
        let commands = pairs.commandNames.filter { !(pairs.usableEnvs[$0] ?? []).isEmpty }
        guard !commands.isEmpty else { return nil }
        let perRank = commands.count
        let rank = n / perRank
        let command = commands[n % perRank]
        guard let order = pairs.closeFirst[command], !order.isEmpty else { return nil }
        let pair = order[rank % order.count]
        // ENVS ROTATE WITH EACH PASS OVER THE PAIRS, so the second time a pair
        // comes round it is in a different world rather than the same clip.
        let usable = pairs.usableEnvs[command] ?? []
        let env = usable[(rank / order.count + n) % usable.count]
        return (command, env, pair.a, pair.b)
    }

    public mutating func next<G: RandomNumberGenerator>(using rng: inout G) -> RolloutPairs.Showing? {
        guard let s = slot(shown) else { return nil }
        shown += 1
        let order: DuckFeedback.Order = Bool.random(using: &rng) ? .aLeft : .bLeft
        return RolloutPairs.Showing(command: s.command, env: s.env, a: s.a, b: s.b, order: order)
    }

    public mutating func next() -> RolloutPairs.Showing? {
        var rng = SystemRandomNumberGenerator()
        return next(using: &rng)
    }
}

/// Every sentence the pair screen shows.
///
/// THE TWO DUCKS ARE NOT NAMED ON SCREEN. A person who can see "teacher" and
/// "student" is judging the labels; the record carries the networks, and the
/// screen carries only Left and Right. What IS said is the command both were
/// given and that the frames are simulated, because a person should know what
/// they are looking at even when they are not told whose it is.
public enum RolloutPreferenceWords {

    public static let title = "Which duck walks better?"
    public static let studioRow = "Compare two walkers"
    public static let studioRowSymbol = "rectangle.split.1x2"

    public static let intro =
        "Two trained walkers, given the same command in the same simulated world. They are not "
      + "named, so you judge the walking and not the name. Pick the one that looks better, or "
      + "say they are too close to call."

    public static func asked(_ command: [Double]) -> String {
        guard command.count == 3 else { return "Both were given the same command." }
        let (vx, wz) = (command[0], command[2])
        switch (vx, wz) {
        case (0, 0): return "Both were asked to stand still."
        case (_, 0): return String(format: "Both were asked to walk forward at %.2f m/s.", vx)
        case (0, _): return String(format: "Both were asked to turn on the spot at %.1f rad/s.", wz)
        default: return String(format: "Both were asked to walk an arc: %.2f m/s forward while "
                             + "turning at %.1f rad/s.", vx, wz)
        }
    }
    public static let simulated =
        "Recorded in MuJoCo, not on a robot. Both start from the same moment of the same run."

    public static let left = "Left is better"
    public static let right = "Right is better"
    public static let tie = "Too close to call"
    public static let bothBad = "Neither walks well"
    public static let reasonsHeading = "Why? (optional)"

    public static func reason(_ reason: DuckFeedback.Reason) -> String {
        switch reason {
        case .steadier: return "Steadier"
        case .moreNatural: return "More natural"
        case .faster: return "Faster"
        case .followsTheCommand: return "Follows the command"
        case .fell: return "The other fell"
        case .jittery: return "The other is jittery"
        case .other: return "Something else"
        }
    }

    /// How many choices this phone holds, and what that is enough for.
    ///
    /// THE NUMBER IS p001's, AND IT IS A SIZING, NOT A PROMISE. With simulated
    /// raters a ranking of these four walkers settled at about 800 choices, so
    /// the screen says a few hundred are needed before anything is ranked —
    /// and does not rank anything itself.
    public static func tally(_ n: Int) -> String {
        let choices = n == 1 ? "choice" : "choices"
        return "\(n) \(choices) on this phone. Ranking walkers from choices like these takes a "
             + "few hundred of them; this screen only collects them and ranks nothing."
    }
    public static let finished =
        "That is every pair in this set. Thank you — each choice is in the feedback log."
    public static let unreadable =
        "The recorded walkers that ship with the app could not be read, so there is nothing to "
      + "compare."

    // MARK: - a skill pack

    /// The screen's title for a pack: walkers, or the skill the pack is about.
    public static func title(skill: String?) -> String {
        switch skill {
        case "kick_right": return "Which duck kicks better?"
        case "kick_left": return "Which duck kicks better?"
        default: return title
        }
    }

    public static func askedSkill(_ skill: String, condition: String) -> String {
        let foot = skill == "kick_left" ? "left" : "right"
        let servos = condition == "backlash" ? " Both have the play in their gears a real servo has." : ""
        return "Both kick the same ball with the \(foot) foot, from the same start.\(servos) Pick "
             + "the kick you would rather see on your duck."
    }

    public static func skillTally(_ n: Int, skill: String) -> String {
        let choices = n == 1 ? "choice" : "choices"
        return "\(n) \(choices) between kicks on this phone. About \(PreferenceModel.minimumPicks) "
             + "teach a taste you can train a kick from, in Train on Hugging Face."
    }

    public static let kickRow = "Kick duels"
    public static let kickRowDetail =
        "Pollen's kick beside a fine-tune, recorded with the ball. Your picks can train a kick."
    public static let kickRight = "Right kicks"
    public static let kickLeft = "Left kicks"
}
