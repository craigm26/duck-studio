import Foundation
import DuckKit

/// Train a duck to shoot: walk to a ball, line up, kick it at a goal. In physics.
///
/// THE ANSWER TO A QUESTION PEOPLE ACTUALLY ASK. "What's the best way to get the
/// duck to walk to a soccer ball and kick it towards a net?" Pollen ships a
/// walker that cannot kick and two kick networks that cannot walk, trained on a
/// ball 90 mm in front of the toe. The shot is the join between them: a small
/// controller on the bench (duckbench `shoot_score.mjs`, route `POST /shoot`)
/// that drives Pollen's networks closed-loop at 50 Hz through six phases:
/// approach, align, dribble, creep, kick, recover. Every number it decides by
/// is a parameter, and training a shooter here means SEARCHING THOSE NUMBERS
/// against goals scored in physics on this phone. The networks are Pollen's and
/// never change; nothing here is reinforcement learning, and the screens say so.
///
/// THE GOAL IS A SCORED LINE. The canon plant is a 3 x 3 m room with no goal,
/// and changing it would move the digest every published challenge is pinned to.
/// A goal is the ball's centre crossing `goalX` between the posts and under the
/// bar. The posts are drawn, not collided with.
public enum Shoot {

    // MARK: - the pitch

    /// The pitch in the canon plant's world frame. Mirrors `PITCH` in
    /// duckbench's `shoot_score.mjs`; `ShootTests` pins the numbers.
    public struct Pitch: Equatable, Sendable {
        public let goalX: Double
        public let goalHalfWidth: Double
        public let goalHeight: Double
        public let goalDepth: Double
        public let walls: Double
        public let duckStart: (x: Double, y: Double)

        public static func == (a: Pitch, b: Pitch) -> Bool {
            a.goalX == b.goalX && a.goalHalfWidth == b.goalHalfWidth && a.goalHeight == b.goalHeight
                && a.walls == b.walls && a.duckStart.x == b.duckStart.x && a.duckStart.y == b.duckStart.y
        }

        public static let canon = Pitch(goalX: 1.30, goalHalfWidth: 0.30, goalHeight: 0.25,
                                        goalDepth: 0.12, walls: 1.5, duckStart: (-0.70, 0))
    }

    /// Where a ball is put down. Nine core spots in front of the duck, and two
    /// harder angles.
    public struct Cell: Equatable, Hashable, Sendable {
        public let x: Double, y: Double
        public let core: Bool
        public init(x: Double, y: Double, core: Bool = true) { self.x = x; self.y = y; self.core = core }
    }

    public static let cells: [Cell] = {
        var out: [Cell] = []
        for x in [-0.30, 0.0, 0.30] { for y in [-0.30, 0.0, 0.30] { out.append(Cell(x: x, y: y)) } }
        out.append(Cell(x: 0.10, y: 0.55, core: false))
        out.append(Cell(x: 0.10, y: -0.55, core: false))
        return out
    }()

    public static var coreCells: [Cell] { cells.filter(\.core) }

    // MARK: - the controller's numbers

    /// Every number the shooter decides by. Names and ranges are the bench's.
    public struct Params: Equatable, Sendable {
        public var values: [String: Double]
        public var foot: String

        public static let limits: [(key: String, low: Double, high: Double, title: String)] = [
            ("shootRange", 0.25, 1.5, "Dribble until this close (m)"),
            ("standoff", 0.10, 0.45, "Set up this far behind the ball (m)"),
            ("footSide", 0.0, 0.08, "Kicking foot offset (m)"),
            ("arriveTol", 0.03, 0.15, "Close enough to the spot (m)"),
            ("alignTol", 3, 30, "Aim tolerance (degrees)"),
            ("kickDist", 0.08, 0.30, "Kick when the ball is this far ahead (m)"),
            ("approachSpeed", 0.25, 0.30, "Walking speed (m/s)"),
            ("turnGain", 0.5, 3.0, "Steering gain"),
            ("kickTicks", 20, 120, "Kick length (ticks)"),
            ("dribbleAim", 0.0, 0.40, "Dribble aim past the ball (m)"),
            ("minTurn", 0.2, 1.0, "Slowest turn (rad/s)"),
        ]

        /// The hand-written first guess the bench starts from.
        public static let defaults = Params(values: [
            "shootRange": 0.55, "standoff": 0.22, "footSide": 0.05, "arriveTol": 0.07,
            "alignTol": 10, "kickDist": 0.10, "approachSpeed": 0.30, "turnGain": 1.6,
            "kickTicks": 60, "dribbleAim": 0.10, "minTurn": 0.5,
        ], foot: "auto")

        /// A HEAD START, SAID FOR WHAT IT IS: the numbers this same search
        /// found on a Raspberry Pi 5 desk bench on 2026-09-28, rounded to three
        /// decimals. MEASURED AS SHIPPED on all nine core spots: 4 of 9 (the
        /// hand-written defaults: 1 of 9; with the head camera only: 4 of 9).
        /// Unrounded they scored 6 of 9 in the search: a shot is sensitive
        /// enough that the fourth decimal moves goals, which is the reason a
        /// shooter is scored over many spots and never on one.
        public static let headStart = Params(values: [
            "shootRange": 0.25, "standoff": 0.10, "footSide": 0.028, "arriveTol": 0.062,
            "alignTol": 17.372, "kickDist": 0.08, "approachSpeed": 0.30, "turnGain": 0.916,
            "kickTicks": 70.308, "dribbleAim": 0.10, "minTurn": 0.5,
        ], foot: "auto")
        public static let headStartSaid =
            "Found by this same search on a Raspberry Pi's bench. Measured on all nine spots: "
          + "4 of 9 goals, against 1 of 9 for the hand-written numbers."

        public init(values: [String: Double], foot: String = "auto") {
            self.values = values; self.foot = foot
        }

        public func value(_ key: String) -> Double {
            values[key] ?? Params.defaults.values[key] ?? 0
        }

        /// Clamped into the bench's ranges.
        public var clamped: Params {
            var out = self
            for l in Params.limits { out.values[l.key] = min(max(value(l.key), l.low), l.high) }
            return out
        }

        /// A neighbour: each number moved with probability one half, by a
        /// Gaussian step of `scale` times its range.
        public func mutated<G: RandomNumberGenerator>(scale: Double, using rng: inout G) -> Params {
            var out = self
            for l in Params.limits where Bool.random(using: &rng) {
                let u1 = max(Double.random(in: 0..<1, using: &rng), 1e-9)
                let u2 = Double.random(in: 0..<1, using: &rng)
                let g = (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
                out.values[l.key] = value(l.key) + g * scale * (l.high - l.low)
            }
            return out.clamped
        }

        /// What Compare identifies a shooter by: its numbers.
        public var digest: String {
            let text = Params.limits.map { $0.key + String(format: "=%.4f", clamped.value($0.key)) }
                .joined(separator: ";") + ";foot=" + foot
            return Compare.digest(of: Data(text.utf8))
        }

        var wire: [String: Any] {
            var out: [String: Any] = ["foot": foot]
            for (k, v) in clamped.values { out[k] = v }
            return out
        }
    }

    // MARK: - one shot, on the wire

    public enum Sensing: String, Sendable, CaseIterable {
        /// The ball's position from the simulator: perfect perception.
        case state
        /// Only what the head camera could see: bearing and range inside a 26°
        /// field of view, with noise; outside it, the duck turns to look.
        case camera

        public var title: String {
            switch self {
            case .state: return "Knows where the ball is"
            case .camera: return "Head camera only"
            }
        }
    }

    public static func call(_ address: DuckBench.Address, cell: Cell, params: Params,
                            sensing: Sensing = .state, seed: Int = 1,
                            seconds: Double = 30) throws -> DuckBench.Call {
        let body: [String: Any] = ["cell": ["ball": ["x": cell.x, "y": cell.y]],
                                   "params": params.wire, "sensing": sensing.rawValue,
                                   "seed": seed, "seconds": seconds]
        return DuckBench.Call(method: "POST", url: URL(string: "\(address.base)/shoot")!,
                              body: try JSONSerialization.data(withJSONObject: body))
    }

    /// What one shot came to.
    public struct Shot: Sendable {
        public enum Outcome: String, Sendable {
            case goal, wide, short, fell
            case neverKicked = "never kicked"

            public var said: String {
                switch self {
                case .goal: return "Goal"
                case .wide: return "Wide"
                case .short: return "Short"
                case .fell: return "Fell"
                case .neverKicked: return "Never kicked"
                }
            }
        }
        public let cell: Cell
        public let outcome: Outcome
        public let missMetres: Double
        public let foot: String?
        public let phases: [(phase: String, at: Double)]
        public let clip: DuckIntentClip
        /// The ball, one [x, y, z] per clip frame.
        public let ball: [[Double]]

        public var goal: Bool { outcome == .goal }

        /// Where the ball is at `time` seconds into the clip.
        public func ball(at time: TimeInterval) -> SIMD2<Double>? {
            guard !ball.isEmpty else { return nil }
            let i = min(max(Int((time * clip.hz).rounded(.down)), 0), ball.count - 1)
            return SIMD2(ball[i][0], ball[i][1])
        }

        /// The phase the controller was in at `time`.
        public func phase(at time: TimeInterval) -> String {
            phases.last { $0.at <= time }?.phase ?? "approach"
        }
    }

    public static func read(_ data: Data, cell: Cell, named name: String) throws -> Shot {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DuckBench.ReadError.notJSON
        }
        if let error = top["error"] as? String { throw DuckBench.ReadError.bench(error) }
        let clip = try DuckBench.readClip(data, named: name)
        let outcome = Shot.Outcome(rawValue: top["outcome"] as? String ?? "") ?? .neverKicked
        let phases = (top["phases"] as? [[String: Any]] ?? []).compactMap { p -> (String, Double)? in
            guard let name = p["phase"] as? String, let t = p["t"] as? Double else { return nil }
            return (name, t)
        }
        return Shot(cell: cell, outcome: outcome, missMetres: top["miss_m"] as? Double ?? 0,
                    foot: top["foot"] as? String, phases: phases.map { (phase: $0.0, at: $0.1) },
                    clip: clip, ball: top["ball"] as? [[Double]] ?? [])
    }

    // MARK: - scoring and searching

    /// A shooter's mark on a set of cells: goals first, then how near the
    /// misses were, so a search can climb before it ever scores.
    public struct Score: Equatable, Sendable, Comparable {
        public let goals: Int
        public let shots: Int
        public let meanMissMetres: Double
        public var value: Double { Double(goals) - 0.5 * meanMissMetres }
        public static func < (a: Score, b: Score) -> Bool { a.value < b.value }

        public init(_ shots: [Shot]) {
            goals = shots.filter(\.goal).count
            self.shots = shots.count
            meanMissMetres = shots.isEmpty ? 0 : shots.map(\.missMetres).reduce(0, +) / Double(shots.count)
        }
        public init(goals: Int, shots: Int, meanMissMetres: Double) {
            self.goals = goals; self.shots = shots; self.meanMissMetres = meanMissMetres
        }
    }

    /// (1 + λ) search over the controller's numbers: keep the best, try λ
    /// neighbours, keep any that scores higher. The step shrinks when a
    /// generation finds nothing better.
    public struct Search: Sendable {
        public private(set) var best: Params
        public private(set) var bestScore: Score?
        public private(set) var generation = 0
        public private(set) var history: [Score] = []
        public private(set) var scale = 0.2
        public let children: Int

        public init(start: Params = .defaults, children: Int = 4) {
            best = start; self.children = children
        }

        public mutating func seed(_ score: Score) {
            bestScore = score; history = [score]
        }

        public func proposals<G: RandomNumberGenerator>(using rng: inout G) -> [Params] {
            (0..<children).map { _ in best.mutated(scale: scale, using: &rng) }
        }

        public mutating func finish(_ tried: [(Params, Score)]) {
            generation += 1
            if let top = tried.max(by: { $0.1 < $1.1 }), bestScore.map({ top.1 > $0 }) ?? true {
                best = top.0; bestScore = top.1
            } else {
                scale = max(scale * 0.7, 0.03)
            }
            if let bestScore { history.append(bestScore) }
        }
    }
}

/// Every sentence the shooting screens say.
public enum ShootWords {
    public static let title = "Train a duck to shoot"
    public static let studioRow = "Train a duck to shoot"
    public static let studioRowSymbol = "soccerball"

    public static let intro =
        "Walk to the ball, line up, kick it into the goal. Pollen trained a walker and two "
      + "kicks, but not the join between them. You will build that join and train it, in real "
      + "physics on \(DeviceWords.current.this)."

    public struct Step: Sendable {
        public let title: String
        public let body: String
    }

    public static let steps: [Step] = [
        .init(title: "1. The pitch",
              body: "A 3 by 3 metre room, a ball and a goal line 1.3 m ahead. The goal is scored "
                  + "where the ball crosses the line between the posts."),
        .init(title: "2. A kick alone",
              body: "Pollen's kick was trained with the ball 9 cm in front of the toe, and it "
                  + "sends a ball about half a metre at best. From here a kick alone never scores."),
        .init(title: "3. A hand-written shooter",
              body: "Six phases: approach a spot behind the ball, turn to face the goal, dribble "
                  + "it closer, creep in, swap to the kick network, recover. Every number is a guess."),
        .init(title: "4. Train it",
              body: "Search the shooter's numbers against goals scored on five ball spots, then "
                  + "test on all nine. Each round tries three variations and keeps the best. Physics "
                  + "is sensitive: a tiny change moves goals, so only many spots make a score. This "
                  + "is search, not reinforcement learning: Pollen's networks are never changed."),
        .init(title: "5. Judge the style",
              body: "Goals are not everything. Compare two shooters' shots and pick the one "
                  + "that looks better: RLHF's human feedback, with training done off the phone."),
        .init(title: "6. Test it with a camera",
              body: "Now let the duck see only what its head camera could: a 26° field of view, "
                  + "with noise. A shooter that needed perfect knowledge of the ball will show it."),
    ]

    public static func score(_ s: Shoot.Score) -> String {
        "\(s.goals) of \(s.shots) goals"
    }

    public static let searchNote =
        "Each round plays every ball spot for each variation. On a phone that is a few "
      + "minutes a round; keep the app open."

    public static let noBench =
        "Shooting runs on a bench. This iPhone is one: pick it in Settings → Benches."
}
