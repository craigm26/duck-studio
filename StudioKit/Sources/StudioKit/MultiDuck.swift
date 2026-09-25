import Foundation
import DuckKit

/// A crossed A/B between two walkers on two ducks: stage 2 of
/// `docs/MULTI-DUCK.md`, on a bench whose world holds two ducks.
///
/// CROSSED, BECAUSE TWO DUCKS ARE NEVER THE SAME DUCK. A pair run once — walker
/// A on the first duck, B on the second — compares duck-and-walker against
/// duck-and-walker. So every pair runs twice with the walkers swapped between
/// the ducks, and the person answers after each run without being told which
/// walker is where. In one simulated world the ducks are identical apart from
/// where they stand, and that is exactly why this is the place to rehearse the
/// crossing: when the hardware arrives, the only new thing is the hardware.
///
/// RECORDED, THEN SHOWN. One request to one duck advances the whole world, so a
/// run is driven to the end first — every tick's stance kept for both ducks —
/// and then played back to the person on one clock, the way the recorded p001
/// pairs are. What they watch happened on their bench a moment ago.
///
/// THE RECORD NAMES NETWORKS, NOT DUCKS. `shown.order` says whether walker `a`
/// was on the first (top) duck; `pair_id` is `multi/<uuid>/run1|run2`, so the
/// two halves of a cross can be joined without a new field in
/// `duck-feedback/0`. No duck's name goes into a record.
public enum MultiDuck {

    /// A walker the person chose: the name the bench answers to, and the
    /// identity a preference is about.
    public struct Walker: Equatable, Sendable {
        public let benchName: String
        public let title: String
        public let identity: DuckFeedback.Policy
        public init(benchName: String, title: String, identity: DuckFeedback.Policy) {
            self.benchName = benchName; self.title = title; self.identity = identity
        }
    }

    /// A command both ducks are given, with how long it lasts.
    public struct Command: Equatable, Sendable {
        public let name: String
        public let twist: DuckDrive.Twist
        public let seconds: Double
        public init(name: String, twist: DuckDrive.Twist, seconds: Double) {
            self.name = name; self.twist = twist; self.seconds = seconds
        }
        public var asRecorded: [Double] { [twist.vx, twist.vy, twist.vyaw] }
    }

    /// p001's commands, which are all above `alpha_walking`'s low-command dead
    /// band except `stand`. Measured on the two-duck bench 2026-09-24:
    /// alpha_walking at vx 0.20 moved 1.5 cm in 8 s, and at 0.25 covered
    /// ~0.11 m/s. A pair inside the band is two ducks standing still.
    public static let commands: [Command] = [
        Command(name: "Walk forward", twist: .init(vx: 0.25, vy: 0, vyaw: 0), seconds: 6),
        Command(name: "Turn on the spot", twist: .init(vx: 0, vy: 0, vyaw: 0.6), seconds: 6),
        Command(name: "Walk an arc", twist: .init(vx: 0.25, vy: 0, vyaw: 0.4), seconds: 6),
        Command(name: "Stand still", twist: .still, seconds: 6),
    ]

    public enum Refusal: Error, Equatable {
        case needTwoDucks(Int)
        case sameWalker
        case tooLong(Double)

        public var message: String {
            switch self {
            case .needTwoDucks(let n):
                return "This bench's world has \(n) duck\(n == 1 ? "" : "s"). Comparing on two "
                     + "ducks needs a bench started with two — duckbench's scene_multiduck.mjb "
                     + "(DUCKBENCH_SCENE=scene_multiduck.mjb)."
            case .sameWalker:
                return "Both sides are the same network. Choose two different walkers."
            case .tooLong(let s):
                return String(format: "%.0f s is longer than a pair is worth watching; at most %.0f s.",
                              s, maxSeconds)
            }
        }
    }

    public static let maxSeconds = 8.0

    /// One crossed pair, set up.
    public struct Pair: Equatable, Sendable {
        public let id: UUID
        public let ducks: (first: String, second: String)
        public let a: Walker
        public let b: Walker
        public let command: Command

        public static func == (l: Pair, r: Pair) -> Bool {
            l.id == r.id && l.ducks == r.ducks && l.a == r.a && l.b == r.b && l.command == r.command
        }

        public init(ducks: [String], a: Walker, b: Walker, command: Command,
                    id: UUID = UUID()) throws {
            guard ducks.count >= 2 else { throw Refusal.needTwoDucks(ducks.count) }
            guard a.identity.fingerprint != b.identity.fingerprint else { throw Refusal.sameWalker }
            guard command.seconds <= MultiDuck.maxSeconds else { throw Refusal.tooLong(command.seconds) }
            self.id = id; self.ducks = (ducks[0], ducks[1])
            self.a = a; self.b = b; self.command = command
        }

        /// Which walker each duck runs in each half of the cross.
        public func assignment(run: Int) -> (first: Walker, second: Walker) {
            run == 1 ? (a, b) : (b, a)
        }
    }

    /// A Library network as a walker's recorded identity, or nil when the app
    /// has only a file digest for it: a preference is about a NETWORK, and a
    /// file that would not load has no parameters to name.
    public static func identity(of entry: PolicyLibrary.Entry) -> DuckFeedback.Policy? {
        guard case .parameters(let digest) = entry.identity else { return nil }
        let repo: String
        switch entry.origin {
        case .bundled: repo = "pollen-robotics/microduck-policies"
        case .fetched(let host): repo = host
        default: repo = "this-phone"
        }
        return DuckFeedback.Policy(repo: repo, file: entry.fileName,
                                   fingerprint: digest.hasPrefix("sha256:") ? digest : "sha256:\(digest)")
    }

    // MARK: - driving one run

    /// How long each request holds the command. Short enough that playback
    /// has frames to draw between, long enough that a run is a few hundred
    /// requests rather than thousands.
    public static let hold = 0.04

    /// The requests that set a run up: both walkers loaded, both ducks reset.
    public static func setUp(_ pair: Pair, run: Int, at address: DuckBench.Address) throws -> [DuckBench.Call] {
        let who = pair.assignment(run: run)
        return [
            try DuckDrive.load(address, policy: who.first.benchName, duck: pair.ducks.first),
            try DuckDrive.load(address, policy: who.second.benchName, duck: pair.ducks.second),
            try DuckDrive.reset(address, duck: pair.ducks.first),
            try DuckDrive.reset(address, duck: pair.ducks.second),
        ]
    }

    /// One tick: the same command to each duck, first then second. Each call
    /// advances the shared world by `hold`, so a tick is `2 * hold` of sim.
    public static func tick(_ pair: Pair, at address: DuckBench.Address) throws -> [DuckBench.Call] {
        [try DuckDrive.intent(address, pair.command.twist, hold: hold, duck: pair.ducks.first),
         try DuckDrive.intent(address, pair.command.twist, hold: hold, duck: pair.ducks.second)]
    }

    public static func ticks(for command: Command) -> Int {
        max(1, Int((command.seconds / (2 * hold)).rounded()))
    }

    /// Both ducks' stances over one run, for playback on one clock.
    public struct Recording: Equatable, Sendable {
        public private(set) var first: [DuckStance] = []
        public private(set) var second: [DuckStance] = []
        public init() {}
        public mutating func append(first f: DuckStance, second s: DuckStance) {
            first.append(f); second.append(s)
        }
        /// Seconds of sim between recorded frames.
        public static let frameSeconds = 2 * MultiDuck.hold
        public var duration: TimeInterval { Double(max(first.count - 1, 0)) * Self.frameSeconds }

        /// The frame at a time, holding the last one: a duck that fell stays down.
        public func stances(at time: TimeInterval) -> (first: DuckStance, second: DuckStance) {
            guard !first.isEmpty, !second.isEmpty else { return (.home, .home) }
            let i = min(max(0, Int((time / Self.frameSeconds).rounded(.down))), first.count - 1)
            return (first[i], second[min(i, second.count - 1)])
        }
    }

    // MARK: - the answer

    /// The person's answer to one run, as a `policy_preference`.
    ///
    /// Top is the first duck. `order` is `a_left` when walker `a` was on it —
    /// "left" in duck-feedback/0 is the first side shown, and on a phone the
    /// two ducks are stacked, so the first is the top one.
    public static func record(_ pick: RolloutPairs.Pick, reasons: [DuckFeedback.Reason],
                              pair: Pair, run: Int, share: DuckFeedback.Share, client: String,
                              at when: Date = Date()) throws -> DuckFeedback {
        let aOnTop = run == 1
        let choice: DuckFeedback.Choice
        switch pick {
        case .left: choice = aOnTop ? .a : .b
        case .right: choice = aOnTop ? .b : .a
        case .tie: choice = .tie
        case .bothBad: choice = .bothBad
        }
        return try DuckFeedback.policyPreference(
            a: pair.a.identity, b: pair.b.identity, choice: choice, reasons: reasons,
            where: .sim, order: aOnTop ? .aLeft : .bLeft,
            command: pair.command.asRecorded, seconds: pair.command.seconds,
            pairID: "multi/\(pair.id.uuidString.lowercased())/run\(run)",
            share: share, client: client, created: when)
    }

    /// Did the person pick the same walker on both halves of the cross? The
    /// number `docs/MULTI-DUCK.md` pre-registers (keep live A/B at >= 65%).
    /// Nil when either half was a tie or both-bad, which says nothing either way.
    public static func consistent(run1: RolloutPairs.Pick, run2: RolloutPairs.Pick) -> Bool? {
        switch (run1, run2) {
        case (.left, .right), (.right, .left): return true    // a on top, then b on top: same walker
        case (.left, .left), (.right, .right): return false
        default: return nil
        }
    }

    // MARK: - the words

    public static let title = "Two ducks, one command"
    public static let studioRow = "Compare on two ducks"
    public static let studioRowSymbol = "person.2"
    public static let intro =
        "Two ducks in one simulated world get the same command, one on each walker you choose. "
      + "Each pair runs twice with the walkers swapped between the ducks, so you judge the "
      + "walker and not the duck. You're not told which is which."
    public static let top = "Top duck is better"
    public static let bottom = "Bottom duck is better"
    public static let running = "Running it on the bench…"
    public static func runOf(_ run: Int) -> String { "Run \(run) of 2" }
    public static let stopBoth = "Stop both"
    public static let start = "Run the pair"
    public static let walkerA = "Walker A"
    public static let walkerB = "Walker B"
    public static let command = "Command"
    public static let noBench =
        "Choose a bench started with two ducks (duckbench's scene_multiduck.mjb) in Control first."
    public static let needWalkers =
        "Put at least two walkers in your Library. A preference names each network by its "
      + "fingerprint, so only networks this app has weighed can be compared."
    public static func consistency(_ same: Int, of total: Int) -> String {
        "Same walker chosen on both halves of the swap: \(same) of \(total)."
    }
}
