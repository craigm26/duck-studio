import Foundation

/// Duck golf: kick the ball into a target across the room, in as few as you can.
///
/// WHY THIS IS A SKILL GAME AND NOT A LUCK ONE. Both kicks land 16 of 16 —
/// `ball_kick_left` and `ball_kick_right` are the most reliable things the duck
/// does — so nothing here is decided by whether the kick works. It is decided
/// by where the duck is standing when it takes it, which is hard for exactly
/// the reasons everything else is: it cannot turn on the spot, so lining up is
/// an arc, and the kick only connects inside a narrow cone.
///
/// THE KICK NUMBERS ARE THE PITCH'S. `DuckSoccer.Capabilities.measured` already
/// carries the reach, the cone and the ball speed that the soccer engine plays
/// with, and this uses those rather than a second set that could drift.
public struct DuckGolf: Equatable, Sendable {

    public struct Hole: Equatable, Sendable {
        /// Where the ball starts and where it has to end up.
        public let tee: DuckSoccer.Vec2
        public let cup: DuckSoccer.Vec2
        /// How close counts as holed.
        public let cupRadius: Double
        public let par: Int

        public init(tee: DuckSoccer.Vec2, cup: DuckSoccer.Vec2,
                    cupRadius: Double = 0.16, par: Int = 3) {
            self.tee = tee; self.cup = cup; self.cupRadius = cupRadius; self.par = par
        }

        public var length: Double {
            (cup - tee).length
        }
    }

    /// Three holes across a living-room floor, at duck scale.
    public static let course: [Hole] = [
        .init(tee: .init(0, 0), cup: .init(1.1, 0.25), par: 2),
        .init(tee: .init(0, 0), cup: .init(1.6, -0.9), par: 3),
        .init(tee: .init(0, 0), cup: .init(2.2, 0.7), par: 4),
    ]

    public enum Stroke: Equatable, Sendable {
        /// The kick connected and the ball ran on.
        case struck(distance: Double)
        /// Out of reach, or outside the cone: a swing at nothing.
        case missed(why: String)
        case holed(strokes: Int)
    }

    public let hole: Hole
    public let capabilities: DuckSoccer.Capabilities
    public private(set) var ball: DuckSoccer.Vec2
    public private(set) var strokes = 0
    public private(set) var holed = false

    public init(hole: Hole, capabilities: DuckSoccer.Capabilities = .measured) {
        self.hole = hole
        self.capabilities = capabilities
        self.ball = hole.tee
    }

    /// Take a kick from where the duck is standing and facing.
    ///
    /// The ball runs along the duck's heading and stops — this is a putt, not
    /// a rolling simulation, because a duck kick on carpet is nearer a putt
    /// than a drive and modelling a roll nobody measured would be inventing
    /// physics to lose it in.
    public mutating func kick(from duck: DuckSoccer.Vec2, heading: Double,
                              power: Double) -> Stroke {
        guard !holed else { return .holed(strokes: strokes) }
        let toBall = ball - duck
        guard toBall.length <= capabilities.kickRange else {
            return .missed(why: "too far from the ball")
        }
        // Inside the cone, the same test the pitch uses before it lets a duck
        // shoot: the ball has to be roughly in front of the foot.
        let bearing = atan2(toBall.y, toBall.x) - heading
        let wrapped = atan2(sin(bearing), cos(bearing))
        guard abs(wrapped) < .pi / 4 else {
            return .missed(why: "the ball is not in front of it")
        }
        strokes += 1
        let run = capabilities.kickBallSpeed * max(0.1, min(power, 1.0)) * 1.6
        ball = ball + DuckSoccer.Vec2(cos(heading), sin(heading)) * run
        if (ball - hole.cup).length <= hole.cupRadius {
            holed = true
            return .holed(strokes: strokes)
        }
        return .struck(distance: run)
    }

    public var toCup: Double { (hole.cup - ball).length }

    public var summary: String {
        guard holed else {
            return String(format: "%d strokes, %.2f m to the cup", strokes, toCup)
        }
        let versus = strokes - hole.par
        let word = versus < 0 ? "\(-versus) under" : versus == 0 ? "par" : "\(versus) over"
        return "Holed in \(strokes) — \(word)."
    }
}
