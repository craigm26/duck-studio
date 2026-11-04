import Foundation

/// The scripted driver the first phone driver learns from: walk the simulated duck to the ball.
///
/// WHY A SCRIPT AND NOT A PERSON (Craig, 2026-11-04). It records forty varied takes with nobody at
/// the sticks, and it can label any state, which the rescue ladder's DAgger-lite round needs. The
/// cost is stated wherever the driver is: it learns this script's way of walking to a ball, not a
/// person's, and it has never seen a real floor.
///
/// THE RULE, FROM WHAT THE SIM KNOWS (the duck's pose, the ball's position):
/// - turn toward the ball, harder the further off it is, up to the stick's turn limit;
/// - walk only when roughly facing it, slowing over the last stretch, never below the speed
///   the standing policy treats as standing (`DuckDrive.deadZone`), so "walking" always walks;
/// - inside `reach`, stand still: the whole command is zero, which the walker is trained on.
///
/// VARIED BY A SEED, NOT BY CHANCE. `Style(seed:)` draws the speed, the turn gain and a small
/// weave from the SplitMix64 stream `TrickRun` already uses, so take 17 is the same take on every machine.
public enum BallExpert {
    /// Duck root to ball centre at which the duck has arrived: the ball's 50 mm radius, the
    /// body's half-depth and the 100 mm kick reach (`SoccerEngine` kickRange).
    public static let reach = 0.20
    /// Off the ball by more than this, the duck turns in place before it walks.
    public static let facing = 0.6
    /// The last stretch before `reach` over which it slows.
    public static let slowing = 0.35

    public struct Style: Equatable, Sendable {
        public let speed: Double      // share of the stick's forward limit
        public let turnGain: Double   // vyaw per radian off the ball
        public let weave: Double      // vy amplitude, m/s
        public let weavePeriod: Double

        public init(speed: Double, turnGain: Double, weave: Double, weavePeriod: Double) {
            self.speed = speed; self.turnGain = turnGain; self.weave = weave; self.weavePeriod = weavePeriod
        }

        public init(seed: UInt64) {
            var rng = SplitMix64(seed: seed)
            speed = 0.7 + 0.3 * rng.next()
            turnGain = 1.5 + 1.0 * rng.next()
            weave = 0.03 * rng.next()
            weavePeriod = 2 + 2 * rng.next()
        }

        public static let plain = Style(speed: 1, turnGain: 2, weave: 0, weavePeriod: 3)
    }

    /// The command for a duck at (x, y) facing `yaw` (radians, z up, left positive) with the ball at
    /// (bx, by), `t` seconds into the take.
    public static func command(x: Double, y: Double, yaw: Double, bx: Double, by: Double,
                               t: Double, style: Style = .plain) -> DuckDrive.Twist {
        let dx = bx - x, dy = by - y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance <= reach { return .still }
        let off = remainder(atan2(dy, dx) - yaw, 2 * .pi)
        let vyaw = min(max(style.turnGain * off, -DuckDrive.maxTurn), DuckDrive.maxTurn)
        guard abs(off) < facing else {
            // Turning in place: never a turn so slow the walker reads it as standing.
            let turn = vyaw < 0 ? min(vyaw, -2 * DuckDrive.deadZone) : max(vyaw, 2 * DuckDrive.deadZone)
            return DuckDrive.Twist(vx: 0, vy: 0, vyaw: turn)
        }
        let ease = min(1, (distance - reach) / slowing)
        let floor = 2 * DuckDrive.deadZone
        let vx = max(DuckDrive.maxForward * style.speed * ease * cos(off), floor)
        let vy = style.weave * sin(2 * .pi * t / style.weavePeriod)
        return DuckDrive.Twist(vx: min(vx, DuckDrive.maxForward), vy: vy, vyaw: vyaw)
    }

    /// The same command from the simulator's own state, or nil when the bench has no ball.
    public static func command(live: DuckDrive.Live, style: Style = .plain) -> DuckDrive.Twist? {
        guard let ball = live.ball else { return nil }
        let root = live.stance.root
        return command(x: root.x, y: root.y, yaw: RunMetrics.yaw(root.quaternion),
                       bx: ball.x, by: ball.y, t: live.t, style: style)
    }
}
