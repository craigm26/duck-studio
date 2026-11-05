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
///   cone's edge already asks the stick's full turn), and walk at a speed the walker steps for;
/// - inside `reach` AND in the cone, stand still: the whole command is zero, which the walker is
///   trained on. The recorder keeps recording standing rows after arrival (`standingRows`), so
///   stopping is learned.
///
/// ROUND 3: EVERY COMMAND IS ONE THE WALKER ACTS ON, AND THE STOP IS ONE THE PICTURE SHOWS
/// (2026-11-04). Round 2's driver reached 10 of 20 balls and stopped at none. Two reasons, both the
/// expert's:
/// - the ball left the bottom of the head picture at about 0.29 m, before the 0.20 m stop line, so
///   every standing row showed bare floor, the same picture as a search. `reach` is now 0.35 m, where
///   the top half of the ball is still in the picture (measured, see `reach`), and the duck stands
///   only with the ball in the `seen` cone, so no standing row is a picture without a ball;
/// - `alpha_walking` does not start walking from rest below about 0.22 m/s forward, and turns almost
///   nothing on the spot (measured, see `walkStart`). Round 2 eased to 0.1 m/s over the last stretch
///   and the driver averaged that easing into commands that froze the duck. Now forward is either 0
///   (standing) or at least `walkStart`, never between, there is no slowing and no sideways weave, and
///   a turn too small to show (`minTurn`) is no turn.
///
/// VARIED BY A SEED, NOT BY CHANCE. `Style(seed:)` draws the speed and the turn gain from the
/// SplitMix64 stream `TrickRun` already uses, so take 17 is the same take on every machine.
public enum BallExpert {
    /// Duck root to ball centre at which the duck has arrived and stands: 0.35 m.
    ///
    /// INSIDE THE PICTURE, MEASURED (2026-11-04). The head camera looks down about 8 degrees from
    /// 0.236 m up, so a near ball leaves the BOTTOM of the picture. Projecting the ball through
    /// `SimHeadCamera.pose` for every row of 40 round-2 takes (6,388 rows, checked against the Mac's
    /// rendered frames: the ball's centre row agrees within 0.3 px on average, 1.3 px at worst), the
    /// ball's last pixels vanish at 0.29 to 0.30 m; at 0.32 m half the picture's ball is gone (median
    /// 328 yellow pixels of 320 by 176, against about 1,650 for the whole ball at 0.45 m); at 0.34 to
    /// 0.36 m the ball's centre is just under the bottom edge, its top half shows (median 715 to 996
    /// pixels) and 98 to 100% of rows hold at least 50. Stopping costs a few millimetres more (round
    /// 2's stops closed at most 5 mm), so 0.35 m keeps the ball in every standing picture with about
    /// 0.05 m to spare. Closer than about 0.40 m some of the ball is always cut off.
    /// It is no longer the kick reach (`SoccerEngine`'s 0.20 m): this driver walks to the ball and
    /// stops where it can still see it; kicking is another task.
    public static let reach = 0.35
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
    /// so the driver sees "ball at my feet means stand" more than once per take (16 per take).
    public static let standingRows = 15
    /// The least forward command the expert ever gives while it walks: 0.25 m/s. Below it, forward
    /// is 0.
    ///
    /// THE WALKER HAS A DEAD BAND FROM REST. Measured on duckbench 2026-11-04, 3 s from standing
    /// with `alpha_walking`: vx 0.20 moved 0.003 m/s, 0.22 moved 0.038, 0.25 moved 0.086 to 0.092,
    /// 0.30 moved 0.12. Once walking it keeps stepping lower (round 2's M1 logs), but a driver that
    /// stops and asks again starts from rest, so the expert never teaches a speed that only works
    /// while already moving.
    public static let walkStart = 0.25
    /// Forward speed while searching (turning with no ball in view): `walkStart`.
    ///
    /// THE SIM'S WALKER DOES NOT TURN IN PLACE. Measured on duckbench 2026-11-04, 3 s from standing:
    /// vx 0 turned 12 to 14 degrees at vyaw 1.0 and 6 at vyaw 0.5; vx 0.25 turned 122 degrees at vyaw
    /// -1.0. So the expert never asks a turn with no forward, and searches by walking a circle
    /// (about 0.33 m across). A ball outside that circle sweeps the whole picture once per lap, and
    /// every start puts the ball at least 0.5 m away.
    public static let arcForward = walkStart
    /// The least turn the expert asks while it walks toward a ball in view: 0.1 rad/s. A smaller
    /// steer (the ball within about 1.6 degrees of dead ahead) is 0.
    ///
    /// WHY A FLOOR. At vx 0.25 from rest, vyaw 0.1 turned 7.5 degrees in 3 s and vyaw 0 drifted 3
    /// (duckbench, 2026-11-04): below 0.1 a turn is lost in the gait's own drift, and a label the
    /// duck cannot act on only teaches a driver to hedge.
    public static let minTurn = 0.1

    public struct Style: Equatable, Sendable {
        public let speed: Double      // share of the stick's forward limit, floored at walkStart
        public let turnGain: Double   // vyaw per radian off the ball

        public init(speed: Double, turnGain: Double) {
            self.speed = speed; self.turnGain = turnGain
        }

        public init(seed: UInt64) {
            var rng = SplitMix64(seed: seed)
            speed = 0.7 + 0.3 * rng.next()
            turnGain = 3.0 + 1.0 * rng.next()
        }

        public static let plain = Style(speed: 1, turnGain: 3.5)
    }

    /// The command for a duck at (x, y) facing `yaw` (radians, z up, left positive) with the ball at
    /// (bx, by), `t` seconds into the take. `t` is unused since round 3 dropped the weave; it stays so
    /// a caller's take clock still fits.
    public static func command(x: Double, y: Double, yaw: Double, bx: Double, by: Double,
                               t: Double, style: Style = .plain) -> DuckDrive.Twist {
        let dx = bx - x, dy = by - y
        let distance = (dx * dx + dy * dy).squareRoot()
        let off = remainder(atan2(dy, dx) - yaw, 2 * .pi)
        guard abs(off) < seen else {
            // Not in the picture: search, on an arc (the walker turns only while it walks), to the
            // right whichever side the ball is on, since the picture cannot say. Also when the ball
            // is within reach but out of view: standing there would be a picture with no ball.
            return DuckDrive.Twist(vx: arcForward, vy: 0, vyaw: searchTurn)
        }
        if distance <= reach { return .still }
        var vyaw = min(max(style.turnGain * off, -DuckDrive.maxTurn), DuckDrive.maxTurn)
        if abs(vyaw) < minTurn { vyaw = 0 }
        let vx = min(max(DuckDrive.maxForward * style.speed * cos(off), walkStart), DuckDrive.maxForward)
        return DuckDrive.Twist(vx: vx, vy: 0, vyaw: vyaw)
    }

    /// The same command from the simulator's own state, or nil when the bench has no ball.
    public static func command(live: DuckDrive.Live, style: Style = .plain) -> DuckDrive.Twist? {
        guard let ball = live.ball else { return nil }
        let root = live.stance.root
        return command(x: root.x, y: root.y, yaw: RunMetrics.yaw(root.quaternion),
                       bx: ball.x, by: ball.y, t: live.t, style: style)
    }
}
