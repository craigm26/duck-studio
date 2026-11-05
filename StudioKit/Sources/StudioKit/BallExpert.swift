import Foundation

/// The scripted driver the first phone driver learns from: walk the simulated duck to the ball.
///
/// WHY A SCRIPT AND NOT A PERSON (Craig, 2026-11-04). It records forty varied takes with nobody at
/// the sticks, and it can label any state, which the rescue ladder's DAgger-lite round needs. The
/// cost is stated wherever the driver is: it learns this script's way of walking to a ball, not a
/// person's, and it has never seen a real floor.
///
/// THE RULE, FROM WHAT THE PICTURE SHOWS (round 2, 2026-11-04). The expert still reads the sim's
/// state (the duck's pose, the ball's position), but it only acts on what the head camera could see:
/// - ball outside the `seen` cone (it is not in the picture): SEARCH, one fixed arc turn to the
///   right (`searchTurn`, at `arcForward`), whichever side the ball is really on. Round 1 turned
///   toward a ball the picture did not show; the takes were balanced left and right, so cloning
///   averaged that turn to about zero and the driver curved slowly forever. "No ball in view means
///   turn right" is something two pictures can teach;
/// - ball inside the cone: steer toward it, hard (`Style.turnGain` 3 to 4 per radian, so the
///   cone's edge already asks the stick's full turn), and walk, slowing over the last stretch,
///   never below the speed the standing policy treats as standing (`DuckDrive.deadZone`);
/// - inside `reach`, stand still: the whole command is zero, which the walker is trained on. The
///   recorder keeps recording standing rows after arrival (`standingRows`), so stopping is learned.
///
/// VARIED BY A SEED, NOT BY CHANCE. `Style(seed:)` draws the speed, the turn gain and a small
/// weave from the SplitMix64 stream `TrickRun` already uses, so take 17 is the same take on every machine.
public enum BallExpert {
    /// Duck root to ball centre at which the duck has arrived: the ball's 50 mm radius, the
    /// body's half-depth and the 100 mm kick reach (`SoccerEngine` kickRange).
    public static let reach = 0.20
    /// Half the cone, about the duck's heading, inside which the expert treats the ball as seen: 30
    /// degrees (0.5236 rad).
    ///
    /// THE CAMERA SEES ABOUT 37 DEGREES EACH SIDE. `SimHeadCamera.fovyDegrees` is 45 vertical, and
    /// the picture is 320 by 176, so the half-width is atan(tan(22.5 deg) * 320 / 176) = 36.98 deg.
    /// The cone is 7 degrees narrower because this bearing is from the root, and the camera sits
    /// ahead of the root on a head that sways: a ball 30 degrees off the root's heading is inside
    /// the picture, not on its edge, so a search never ends on a ball the driver cannot see.
    public static let seen = 30.0 * Double.pi / 180
    /// The search turn, the same every time: right (z up, left positive, so negative).
    public static let searchTurn = -DuckDrive.maxTurn
    /// Rows of standing (the all-zero command) the recorder keeps after arrival, 1.5 s at 10 Hz,
    /// so the driver sees "ball at my feet means stand" more than once per take.
    public static let standingRows = 15
    /// The last stretch before `reach` over which it slows.
    public static let slowing = 0.35
    /// Forward speed while searching (turning with no ball in view).
    ///
    /// THE SIM'S WALKER DOES NOT TURN IN PLACE. Measured on duckbench 2026-11-04, `alpha_walking`
    /// (the policy the app's simulated duck walks with) turned 12 degrees in 3 s at vyaw 1.0 with
    /// vx 0, and 95 degrees at vx 0.25. So the expert searches by walking a circle. A constant turn
    /// has one blind spot, a ball near the circle's centre, which stays off to the right all the
    /// way round. Measured on duckbench 2026-11-04 at this search twist: 328 degrees in 8 s, a
    /// circle about 0.33 m across, so its radius (about 0.16 m) is inside `reach` and the circle
    /// passes within reach of any ball in that blind spot.
    public static let arcForward = 0.25

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
            turnGain = 3.0 + 1.0 * rng.next()
            weave = 0.03 * rng.next()
            weavePeriod = 2 + 2 * rng.next()
        }

        public static let plain = Style(speed: 1, turnGain: 3.5, weave: 0, weavePeriod: 3)
    }

    /// The command for a duck at (x, y) facing `yaw` (radians, z up, left positive) with the ball at
    /// (bx, by), `t` seconds into the take.
    public static func command(x: Double, y: Double, yaw: Double, bx: Double, by: Double,
                               t: Double, style: Style = .plain) -> DuckDrive.Twist {
        let dx = bx - x, dy = by - y
        let distance = (dx * dx + dy * dy).squareRoot()
        if distance <= reach { return .still }
        let off = remainder(atan2(dy, dx) - yaw, 2 * .pi)
        guard abs(off) < seen else {
            // Not in the picture: search, on an arc (the walker turns only while it walks), to the
            // right whichever side the ball is on, since the picture cannot say.
            return DuckDrive.Twist(vx: arcForward, vy: 0, vyaw: searchTurn)
        }
        let vyaw = min(max(style.turnGain * off, -DuckDrive.maxTurn), DuckDrive.maxTurn)
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
