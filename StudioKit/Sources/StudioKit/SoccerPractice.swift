import Foundation

/// Duck Soccer's practice mode: five skill challenges on the same engine and
/// pitch as a match, each scored out of three stars.
///
/// THE BALL MOVES ONLY WHEN IT IS STRUCK. The engine has no dribbling: a duck
/// walks through the ball, and SHOOT or PASS sends it along the duck's heading
/// (a pass rolls about 0.29 m, a shot about 0.5 m). So every drill is about
/// turning to face the right way and choosing the right strike, which is the
/// skill this game actually has.
public struct SoccerPractice: Sendable {

    public enum Drill: String, CaseIterable, Sendable, Identifiable {
        case penalties, corners, slalom, passing, oneOnOne
        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .penalties: return "Penalties"
            case .corners: return "Pick your corner"
            case .slalom: return "Slalom"
            case .passing: return "Passing"
            case .oneOnOne: return "One on one"
            }
        }

        public var blurb: String {
            switch self {
            case .penalties: return "Five from the spot against the keeper."
            case .corners: return "Score in the lit half of an empty goal, five times."
            case .slalom: return "Tap the ball through four cone gates with soft passes. Beat the clock."
            case .passing: return "Land the ball inside the ring. Passes roll short, shots roll long."
            case .oneOnOne: return "From halfway, past a defender and the keeper. Three tries."
            }
        }

        public var symbol: String {
            switch self {
            case .penalties: return "soccerball.inverse"
            case .corners: return "scope"
            case .slalom: return "point.topleft.down.to.point.bottomright.curvepath"
            case .passing: return "circle.circle"
            case .oneOnOne: return "figure.soccer"
            }
        }

        /// Tries in the drill; the slalom is one timed run.
        public var attempts: Int {
            switch self {
            case .penalties, .corners, .passing: return 5
            case .slalom: return 1
            case .oneOnOne: return 3
            }
        }

        /// Seconds each try may take.
        public var timeLimit: Double {
            switch self {
            case .penalties: return 10
            case .corners: return 20
            case .slalom: return 150
            case .passing: return 20
            case .oneOnOne: return 45
            }
        }
    }

    /// Something drawn on the pitch for a drill.
    public struct Prop: Equatable, Sendable {
        public enum Kind: String, Sendable { case cone, ring, finish }
        public let kind: Kind
        public let position: DuckSoccer.Vec2
        public let radius: Double
        /// Done with (a gate passed, a ring used): drawn dimmer.
        public var done: Bool = false
    }

    public enum Outcome: Equatable, Sendable {
        case success(String)
        case miss(String)
        case finished
    }

    public let drill: Drill
    public private(set) var match: DuckSoccer.Match
    public private(set) var attempt = 0
    public private(set) var results: [Bool] = []
    public private(set) var elapsed = 0.0
    public private(set) var totalTime = 0.0
    public private(set) var props: [Prop] = []
    /// Pick your corner: the half of the goal that counts, as a y range.
    public private(set) var litCorner: ClosedRange<Double>?
    public private(set) var isFinished = false
    private var gate = 0
    private var struck = false
    private var lastBallX = 0.0
    private let capabilities: DuckSoccer.Capabilities
    private let moves: DuckSoccer.Moves

    public init(_ drill: Drill, capabilities: DuckSoccer.Capabilities = .measured,
                moves: DuckSoccer.Moves = .standard) {
        self.drill = drill
        self.capabilities = capabilities
        self.moves = moves
        self.match = DuckSoccer.Match(capabilities: capabilities, halfLength: 100_000,
                                      controlledPlayer: "home-3")
        setUp()
    }

    public var successes: Int { results.filter { $0 }.count }

    /// Stars: from successes, or for the slalom from its time.
    public var stars: Int {
        guard isFinished else { return 0 }
        switch drill {
        case .slalom:
            guard successes > 0 else { return 0 }
            return totalTime < 60 ? 3 : totalTime < 90 ? 2 : 1
        case .oneOnOne:
            return min(successes, 3)
        default:
            return successes >= 4 ? 3 : successes >= 3 ? 2 : successes >= 2 ? 1 : 0
        }
    }

    /// The line under the drill's name while it runs.
    public var progress: String {
        switch drill {
        case .slalom: return "Gate \(min(gate + 1, 4)) of 4 · " + String(format: "%.0f s", elapsed)
        default: return "Try \(min(attempt + 1, drill.attempts)) of \(drill.attempts) · \(successes) scored"
        }
    }

    public var summary: String {
        switch drill {
        case .slalom:
            return successes > 0 ? String(format: "Through all four in %.0f s", totalTime) : "Out of time"
        default:
            return "\(successes) of \(drill.attempts)"
        }
    }

    // MARK: - the pitch for each try

    private static let corners: [(DuckSoccer.Vec2, Bool)] = [
        // Within a shot's roll (about 0.5 m) of the goal line at x = 1.2.
        (.init(0.85, 0.25), true), (.init(0.80, -0.30), false), (.init(0.80, 0.0), true),
        (.init(0.90, -0.10), false), (.init(0.82, 0.32), true),
    ]
    private static let rings: [DuckSoccer.Vec2] = [
        .init(0.29, 0), .init(0.0, 0.29), .init(0.5, 0), .init(0.35, -0.35), .init(-0.29, 0),
    ]

    private mutating func place(_ you: DuckSoccer.Vec2, heading: Double, ball: DuckSoccer.Vec2,
                                others: [DuckSoccer.Player] = []) {
        var me = DuckSoccer.Player(team: .home, number: 3, role: .striker, position: you, heading: heading)
        me.motion = .standing
        match.players = [me] + others
        match.ball = DuckSoccer.Ball(position: ball)
        match.phase = .playing
        match.moves[.home] = moves
        elapsed = 0
        struck = false
        lastBallX = ball.x
    }

    private mutating func setUp() {
        let pitch = match.pitch
        let L = pitch.halfLength
        let keeper = DuckSoccer.Player(team: .away, number: 0, role: .keeper,
                                       position: .init(L * 0.94, 0), heading: .pi)
        litCorner = nil
        switch drill {
        case .penalties:
            let spot = L - pitch.penaltySpot
            place(.init(spot - 0.08, 0), heading: 0, ball: .init(spot, 0), others: [keeper])
        case .corners:
            let (ball, top) = Self.corners[attempt % Self.corners.count]
            place(.init(ball.x - 0.08, ball.y), heading: 0, ball: ball)
            litCorner = top ? 0.06...pitch.goalHalfWidth : (-pitch.goalHalfWidth)...(-0.06)
        case .slalom:
            place(.init(-0.96, 0), heading: 0, ball: .init(-0.88, 0))
            props = []
            for (i, x) in [-0.6, -0.2, 0.2, 0.6].enumerated() {
                let y = i % 2 == 0 ? 0.25 : -0.25
                props.append(Prop(kind: .cone, position: .init(x, y + 0.13), radius: 0.02))
                props.append(Prop(kind: .cone, position: .init(x, y - 0.13), radius: 0.02))
            }
            props.append(Prop(kind: .finish, position: .init(0.95, 0), radius: pitch.halfWidth))
            gate = 0
        case .passing:
            let ring = Self.rings[attempt % Self.rings.count]
            place(.init(-0.08, 0), heading: 0, ball: .init(0, 0))
            props = [Prop(kind: .ring, position: ring, radius: 0.12)]
        case .oneOnOne:
            let defender = DuckSoccer.Player(team: .away, number: 2, role: .defender,
                                             position: .init(0.55, 0.1), heading: .pi)
            place(.init(-0.08, 0), heading: 0, ball: .init(0, 0), others: [keeper, defender])
        }
    }

    // MARK: - playing

    /// Step the drill. Returns what happened, if anything, this step.
    public mutating func advance(dt: Double, control: DuckSoccer.Control) -> Outcome? {
        guard !isFinished else { return nil }
        elapsed += dt
        totalTime += dt
        let events = match.advance(dt: dt, controls: ["home-3": control])
        if events.contains(where: { if case .kick = $0 { return true }; return false }) { struck = true }
        let ball = match.ball

        var verdict: Outcome?
        for event in events {
            guard case .goal(let team, _) = event else { continue }
            if team == .away {
                verdict = .miss("Own goal")
            } else if drill == .corners, let lit = litCorner {
                verdict = lit.contains(ball.position.y) ? .success("In the lit corner!") : .miss("Wrong half")
            } else if drill == .passing || drill == .slalom {
                verdict = .miss("Too hard: it went in the goal")
            } else {
                verdict = .success("Goal!")
            }
        }

        if verdict == nil {
            switch drill {
            case .slalom:
                verdict = slalomStep(ball)
            case .passing:
                if struck, ball.velocity.length < 0.01, let ring = props.first {
                    verdict = (ball.position - ring.position).length <= ring.radius
                        ? .success("In the ring!")
                        : .miss(String(format: "%.0f cm off", ((ball.position - ring.position).length - ring.radius) * 100))
                }
            case .penalties, .corners:
                if struck, ball.velocity.length < 0.01 { verdict = .miss(drill == .penalties ? "Saved" : "Short") }
            case .oneOnOne:
                if ball.position.x < -0.3 { verdict = .miss("They cleared it") }
            }
        }
        if verdict == nil, elapsed > drill.timeLimit { verdict = .miss("Out of time") }
        lastBallX = ball.position.x

        guard let verdict else { return nil }
        if case .success = verdict { results.append(true) } else { results.append(false) }
        attempt += 1
        if attempt >= drill.attempts {
            isFinished = true
            match.phase = .playing
            return verdict
        }
        setUp()
        return verdict
    }

    /// The slalom's gates, in order: the ball must cross each gate's line
    /// between its two cones; crossing outside does not count.
    private mutating func slalomStep(_ ball: DuckSoccer.Ball) -> Outcome? {
        let x = ball.position.x
        if gate < 4 {
            let upper = props[gate * 2].position, lower = props[gate * 2 + 1].position
            if lastBallX < upper.x, x >= upper.x {
                if ball.position.y <= upper.y && ball.position.y >= lower.y {
                    props[gate * 2].done = true; props[gate * 2 + 1].done = true
                    gate += 1
                }
            }
        } else if let finish = props.last, lastBallX < finish.position.x, x >= finish.position.x {
            return .success("Through!")
        }
        return nil
    }
}
