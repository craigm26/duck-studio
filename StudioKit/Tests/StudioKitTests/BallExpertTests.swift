import XCTest
import DuckKit
@testable import StudioKit

/// The scripted driver, checked on a kinematic duck: the command integrated as a unicycle at
/// 10 Hz. This proves the steering, not the walking; whether the physics duck follows it is the
/// Mac step's check (the plan's T8), with the same seeds.
final class BallExpertTests: XCTestCase {
    /// Seeded starts across the practice mat, ball where the practice world puts it.
    private func run(seed: UInt64, limit: Double = 30) -> (arrived: Bool, seconds: Double) {
        var rng = SplitMix64(seed: seed &* 7919 &+ 1)
        let style = BallExpert.Style(seed: seed)
        let (bx, by) = (0.90, -0.45)
        var x = -0.6 + 1.2 * rng.next(), y = -0.9 + 1.8 * rng.next(), yaw = 2 * .pi * rng.next()
        // Never start on top of the ball.
        if hypot(bx - x, by - y) < 0.4 { x -= 0.6 }
        var t = 0.0
        while t < limit {
            let c = BallExpert.command(x: x, y: y, yaw: yaw, bx: bx, by: by, t: t, style: style)
            if c == .still { return (true, t) }
            XCTAssertLessThanOrEqual(c.vx, DuckDrive.maxForward + 1e-12)
            XCTAssertLessThanOrEqual(abs(c.vyaw), DuckDrive.maxTurn + 1e-12)
            XCTAssertFalse(c.standsStill, "a moving command the walker would read as standing")
            XCTAssertGreaterThanOrEqual(c.vx, BallExpert.walkStart, "a forward the walker does not start for")
            x += 0.1 * (c.vx * cos(yaw) - c.vy * sin(yaw))
            y += 0.1 * (c.vx * sin(yaw) + c.vy * cos(yaw))
            yaw += 0.1 * c.vyaw
            t += 0.1
        }
        return (false, t)
    }

    func testItReachesTheBallFrom95PercentOf200SeededStarts() {
        let results = (0..<200).map { run(seed: UInt64($0)) }
        let arrived = results.filter(\.arrived).count
        XCTAssertGreaterThanOrEqual(arrived, 190, "\(arrived)/200")
        let mean = results.filter(\.arrived).map(\.seconds).reduce(0, +) / Double(max(arrived, 1))
        XCTAssertLessThan(mean, 15, "takes should be seconds long, not minutes")
    }

    func testInsideReachItStandsStillAndOtherwiseItMoves() {
        XCTAssertEqual(BallExpert.command(x: 0, y: 0, yaw: 0, bx: 0.15, by: 0, t: 0), .still)
        XCTAssertEqual(BallExpert.command(x: 0, y: 0, yaw: 0, bx: 0.34, by: 0, t: 0), .still)
        XCTAssertNotEqual(BallExpert.command(x: 0, y: 0, yaw: 0, bx: 0.36, by: 0, t: 0), .still)
        // Within reach but out of the picture: it does not stand on a picture with no ball, it searches.
        let beside = BallExpert.command(x: 0, y: 0, yaw: 0, bx: 0, by: 0.3, t: 0)
        XCTAssertEqual(beside, DuckDrive.Twist(vx: BallExpert.arcForward, vy: 0, vyaw: BallExpert.searchTurn))
        let ahead = BallExpert.command(x: 0, y: 0, yaw: 0, bx: 1, by: 0, t: 0)
        XCTAssertEqual(ahead.vx, DuckDrive.maxForward, accuracy: 1e-9)
        XCTAssertEqual(ahead.vyaw, 0, accuracy: 1e-9)
        let behind = BallExpert.command(x: 0, y: 0, yaw: 0, bx: -1, by: 0.01, t: 0)
        XCTAssertEqual(behind.vx, BallExpert.arcForward, "searches on an arc: the sim's walker cannot turn in place")
        XCTAssertEqual(behind.vyaw, BallExpert.searchTurn)
    }

    /// ROUND 2: THE EXPERT ACTS ONLY ON WHAT THE PICTURE SHOWS. Round 1 turned toward a ball outside
    /// the camera's view, left or right, using sim state no picture holds; the driver cloned the
    /// average of the two, about no turn at all, and curved slowly forever (M1 2/10).
    func testWithNoBallInViewItSearchesTheSameWayWhicheverSideTheBallIsOn() {
        XCTAssertLessThan(BallExpert.seen, 36.98 * .pi / 180, "inside the head camera's half-width")
        XCTAssertLessThan(BallExpert.searchTurn, 0, "turns right (z up, left positive)")
        for degrees in stride(from: 31.0, through: 180.0, by: 7.0) {
            for side in [1.0, -1.0] {
                let a = side * degrees * .pi / 180
                let c = BallExpert.command(x: 0, y: 0, yaw: 0, bx: cos(a), by: sin(a), t: 1.3,
                                           style: BallExpert.Style(seed: 9))
                XCTAssertEqual(c, DuckDrive.Twist(vx: BallExpert.arcForward, vy: 0, vyaw: BallExpert.searchTurn),
                               "ball \(side * degrees) degrees off")
            }
        }
    }

    /// In view it steers toward the ball, decisively: at the cone's edge every style already asks
    /// the stick's full turn, toward the ball's side.
    func testInViewItSteersTowardTheBallHard() {
        for seed in UInt64(1)...50 {
            let style = BallExpert.Style(seed: seed)
            XCTAssertGreaterThanOrEqual(style.turnGain * BallExpert.seen, DuckDrive.maxTurn)
            let a = BallExpert.seen - 0.01
            let left = BallExpert.command(x: 0, y: 0, yaw: 0, bx: cos(a), by: sin(a), t: 0, style: style)
            let right = BallExpert.command(x: 0, y: 0, yaw: 0, bx: cos(a), by: -sin(a), t: 0, style: style)
            XCTAssertEqual(left.vyaw, DuckDrive.maxTurn, accuracy: 1e-12)
            XCTAssertEqual(right.vyaw, -DuckDrive.maxTurn, accuracy: 1e-12)
            XCTAssertGreaterThan(left.vx, DuckDrive.maxForward * 0.5, "walks while it steers")
        }
        let small = BallExpert.command(x: 0, y: 0, yaw: 0, bx: cos(0.1), by: sin(0.1), t: 0)
        XCTAssertEqual(small.vyaw, BallExpert.Style.plain.turnGain * 0.1, accuracy: 1e-9)
    }

    /// ROUND 3: NO COMMAND IN THE WALKER'S DEAD BAND. `alpha_walking` does not start from rest below
    /// about 0.22 m/s forward and barely turns on the spot; round 2's easing taught a driver to ask
    /// exactly those commands, and the duck froze. Forward is 0 (and then everything is 0) or at least
    /// `walkStart`; a turn is 0 or at least `minTurn`; nothing goes sideways.
    func testNoCommandFallsInTheWalkersDeadBand() {
        var rng = SplitMix64(seed: 31)
        var stands = 0, searches = 0, steers = 0
        for i in 0..<5000 {
            let x = -1 + 2 * rng.next(), y = -1 + 2 * rng.next(), yaw = -Double.pi + 2 * .pi * rng.next()
            // Half the balls near and in view, so the stand and the close approach are exercised.
            let near = i % 2 == 0
            let a = near ? yaw + BallExpert.seen * (-1 + 2 * rng.next()) : 2 * .pi * rng.next()
            let r = near ? 0.1 + 0.6 * rng.next() : 0.1 + 1.5 * rng.next()
            let c = BallExpert.command(x: x, y: y, yaw: yaw, bx: x + r * cos(a), by: y + r * sin(a),
                                       t: rng.next() * 10, style: BallExpert.Style(seed: UInt64(i % 13)))
            XCTAssertEqual(c.vy, 0)
            if c.vx == 0 {
                XCTAssertEqual(c, .still, "a turn with no forward: the walker barely turns on the spot")
                stands += 1
            } else {
                XCTAssertGreaterThanOrEqual(c.vx, BallExpert.walkStart)
                XCTAssertLessThanOrEqual(c.vx, DuckDrive.maxForward)
                XCTAssertTrue(c.vyaw == 0 || abs(c.vyaw) >= BallExpert.minTurn, "a turn too small to show: \(c.vyaw)")
                if c.vyaw == BallExpert.searchTurn && c.vx == BallExpert.arcForward { searches += 1 } else { steers += 1 }
            }
        }
        XCTAssertGreaterThan(stands, 200); XCTAssertGreaterThan(searches, 500); XCTAssertGreaterThan(steers, 500)
        // A ball a hair off dead ahead: no turn, not a 0.05 the gait's own drift swamps.
        XCTAssertEqual(BallExpert.command(x: 0, y: 0, yaw: 0, bx: 1, by: 0.004, t: 0).vyaw, 0)
    }

    /// ROUND 3: THE STOP LINE IS INSIDE THE PICTURE. The ball, at `reach` dead ahead of a standing duck
    /// (a real standing state from the round-2 takes), projected through the head camera the renderer
    /// uses: its upper half is in the picture at the reach, and at round 2's 0.20 m it is not in the
    /// picture at all (that is why round 2's standing rows showed bare floor). The full measurement,
    /// over 6,388 recorded rows and checked against the Mac's rendered frames, is on `reach`.
    func testTheBallIsInThePictureAtTheStopLine() throws {
        func ballTopAndCentre(at distance: Double) throws -> (top: Double, centre: Double, across: Double) {
            let (px, py) = (-0.3611, -0.3682)
            var bench: [String: Any] = [
                "duck": "duck", "t": 13.5, "position": [px, py, 0.1166], "height": 0.1166, "upright": true,
                "quaternion": [-0.0917, 0.0038, 0.002, -0.9958],
                "joints": [0.0125, -0.083, -0.4313, 0.0101, 0.4374, 0.208, 0.3951, -0.02, -0.0161, 0.0119,
                           0.0878, 0.4677, -0.0019, -0.4654],
                "policy": "alpha_walking.onnx", "command": ["vx": 0, "vy": 0, "vyaw": 0], "ballRadius": 0.05]
            let heading = RunMetrics.yaw((-0.0917, 0.0038, 0.002, -0.9958))
            bench["ball"] = [px + distance * cos(heading), py + distance * sin(heading), 0.05]
            let live = try DuckDrive.readLive(JSONSerialization.data(withJSONObject: bench))
            let p = SimHeadCamera.pose(live), b = DreamPracticeWorld.ball(in: live)
            let right = DuckVector(p.forward.y * p.up.z - p.forward.z * p.up.y,
                                   p.forward.z * p.up.x - p.forward.x * p.up.z,
                                   p.forward.x * p.up.y - p.forward.y * p.up.x)
            let d = DuckVector(b.x - p.position.x, b.y - p.position.y, b.z - p.position.z)
            let tanHalf = tan(SimHeadCamera.fovyDegrees / 2 * .pi / 180), z = d.dot(p.forward)
            // Picture coordinates: -1 is the bottom edge, +1 the top.
            let centre = d.dot(p.up) / (z * tanHalf)
            let aspect = Double(DriverPrep.pictureWidth) / Double(DriverPrep.pictureHeight)
            return (centre + b.radius / (z * tanHalf), centre, d.dot(right) / (z * tanHalf * aspect))
        }
        let atReach = try ballTopAndCentre(at: BallExpert.reach)
        XCTAssertGreaterThan(atReach.top, -0.95, "the ball's top is well inside the bottom edge at the reach")
        XCTAssertLessThan(abs(atReach.across), 0.2, "dead ahead is mid-picture")
        XCTAssertLessThan(try ballTopAndCentre(at: 0.20).top, -1, "round 2's line: the ball is under the picture")
        XCTAssertGreaterThan(try ballTopAndCentre(at: 0.45).centre, -1, "further off, the whole ball is in")
    }

    func testASeedIsTheSameTakeEverywhere() {
        XCTAssertEqual(BallExpert.Style(seed: 17), BallExpert.Style(seed: 17))
        XCTAssertNotEqual(BallExpert.Style(seed: 17), BallExpert.Style(seed: 18))
        var a = SplitMix64(seed: 0)
        XCTAssertEqual(a.next(), Double(UInt64(0xE220_A839_7B1D_CDAF) >> 11) / 9007199254740992.0,
                       "SplitMix64's published first output for seed 0")
    }

    /// The Pi-side recorder (scripts/record_ball_takes.py) carries a port of this expert. The
    /// recorded takes are only this expert's if the two decide identically.
    func testThePythonPortDecidesExactlyAsThisDoes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/ball-expert-vectors", withExtension: "json"))
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let styles = try XCTUnwrap(file["styles"] as? [String: [String: Double]])
        // The rule's numbers, including the recorder's standing tail (1.5 s after arrival, so a
        // driver learns to stop), are the same on both sides.
        let k = try XCTUnwrap(file["constants"] as? [String: Double])
        XCTAssertEqual(k["reach"], BallExpert.reach)
        XCTAssertEqual(k["seen"]!, BallExpert.seen, accuracy: 1e-15)
        XCTAssertEqual(k["searchTurn"], BallExpert.searchTurn)
        XCTAssertEqual(k["arcForward"], BallExpert.arcForward)
        XCTAssertEqual(k["walkStart"], BallExpert.walkStart)
        XCTAssertEqual(k["minTurn"], BallExpert.minTurn)
        XCTAssertEqual(k["standingRows"], Double(BallExpert.standingRows))
        XCTAssertGreaterThanOrEqual(BallExpert.standingRows, 15)
        for (key, s) in styles {
            let mine = BallExpert.Style(seed: UInt64(key)!)
            XCTAssertEqual(mine.speed, s["speed"]!, accuracy: 1e-12)
            XCTAssertEqual(mine.turnGain, s["turnGain"]!, accuracy: 1e-12)
        }
        let cases = try XCTUnwrap(file["cases"] as? [[String: Any]])
        XCTAssertGreaterThan(cases.count, 90)
        for c in cases {
            func d(_ k: String) -> Double { (c[k] as? NSNumber)?.doubleValue ?? .nan }
            let seed = (c["styleSeed"] as? NSNumber)?.uint64Value ?? 0
            let style = seed == 0 ? BallExpert.Style.plain : BallExpert.Style(seed: seed)
            let got = BallExpert.command(x: d("x"), y: d("y"), yaw: d("yaw"), bx: d("bx"), by: d("by"), t: d("t"), style: style)
            let want = (c["command"] as? [NSNumber])!.map(\.doubleValue)
            XCTAssertEqual(got.vx, want[0], accuracy: 1e-12)
            XCTAssertEqual(got.vy, want[1], accuracy: 1e-12)
            XCTAssertEqual(got.vyaw, want[2], accuracy: 1e-12)
        }
    }
}
