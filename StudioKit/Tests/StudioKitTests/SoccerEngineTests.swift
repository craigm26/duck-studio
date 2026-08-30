import XCTest
@testable import StudioKit

/// The match, proved on Linux before any AR view exists.
final class SoccerEngineTests: XCTestCase {

    typealias S = DuckSoccer
    let dt = 0.02   // the robot's own 50 Hz

    // MARK: - the laws

    /// Kickoff is legal: ten players, everyone in their own half, keeper
    /// deepest, and the ball on the centre spot.
    func testKickoffIsLegal() {
        let match = S.Match()
        XCTAssertEqual(match.players.count, 10)
        XCTAssertEqual(match.players.filter { $0.team == .home }.count, 5)
        for player in match.players {
            if player.team == .home {
                XCTAssertLessThanOrEqual(player.position.x, 0.01, player.id)
            } else {
                XCTAssertGreaterThanOrEqual(player.position.x, -0.01, player.id)
            }
        }
        XCTAssertEqual(match.ball.position, .zero)
        let keeper = match.player("home-0")!
        for mate in match.players where mate.team == .home {
            XCTAssertLessThanOrEqual(keeper.position.x, mate.position.x + 1e-9,
                                     "the keeper stands deepest")
        }
    }

    /// The whistle blows once, after the countdown, and play begins.
    func testTheWhistleBlowsOnce() {
        var match = S.Match()
        var whistles = 0
        for _ in 0..<200 {
            whistles += match.advance(dt: dt).filter { $0 == .whistle }.count
        }
        XCTAssertEqual(whistles, 1)
        XCTAssertEqual(match.phase, .playing)
    }

    /// Determinism is the contract that makes the engine testable at all: the
    /// same inputs produce the identical match, tick for tick.
    func testTheMatchIsDeterministic() {
        var a = S.Match(), b = S.Match()
        for tick in 0..<1500 {
            let control = S.Control(stick: S.Vec2(1, tick % 2 == 0 ? 0.3 : -0.3),
                                    kick: tick % 50 == 0)
            _ = a.advance(dt: dt, controls: ["home-3": control])
            _ = b.advance(dt: dt, controls: ["home-3": control])
        }
        XCTAssertEqual(a, b)
    }

    // MARK: - locomotion at the robot's speeds

    /// No duck exceeds the measured envelope, ever. This is the realism
    /// contract: the engine may not move a duck faster than the canon plant
    /// records the robot walking or turning.
    func testNoDuckOutrunsTheRobot() {
        var match = S.Match()
        var previous = match.players
        let caps = match.capabilities
        for tick in 0..<2000 {
            _ = match.advance(dt: dt,
                              controls: ["home-3": .init(stick: S.Vec2(1, 1))])
            if case .playing = match.phase {
                for (index, player) in match.players.enumerated() {
                    let moved = (player.position - previous[index].position).length
                    // Speed cap plus the separation shove's per-second cap.
                    XCTAssertLessThanOrEqual(
                        moved, caps.fastSpeed * dt + caps.bodyRadius * dt + 1e-9,
                        "\(player.id) at tick \(tick) moved \(moved / dt) m/s")
                    let turned = abs(S.angleDelta(from: previous[index].heading,
                                                  to: player.heading))
                    XCTAssertLessThanOrEqual(turned, caps.turnRate * dt + 1e-9,
                                             "\(player.id) out-turned the robot")
                }
            }
            previous = match.players
        }
    }

    /// A duck told to go SIDEWAYS turns first — it does not strafe. (The
    /// original version of this test commanded straight backwards and pinned a
    /// nine-second pirouette; the robot actually REVERSES under a backward
    /// command, the engine now does too, and testPullingBackBacksUp owns that
    /// direction. Sideways is where turn-then-walk is the true contract.)
    func testDucksTurnBeforeTheyWalkSideways() {
        var match = S.Match()
        while match.phase != .playing { _ = match.advance(dt: dt) }
        let start = match.player("home-3")!.position
        // home-3 faces +x at kickoff; command it straight left (+y).
        for _ in 0..<25 {
            _ = match.advance(dt: dt, controls: ["home-3": .init(stick: S.Vec2(0, 1))])
        }
        let after = match.player("home-3")!
        XCTAssertLessThan((after.position - start).length, 0.02,
                          "half a second in it is still mostly pivoting")
        XCTAssertGreaterThan(abs(S.angleDelta(from: 0, to: after.heading)), 0.1,
                             "but it has begun to turn")
    }

    /// Ducks do not stack: after a long crowded spell every pair keeps some
    /// daylight.
    func testDucksStaySolid() {
        var match = S.Match()
        for _ in 0..<3000 { _ = match.advance(dt: dt) }
        for a in match.players.indices {
            for b in (a + 1)..<match.players.count {
                let gap = (match.players[a].position - match.players[b].position).length
                XCTAssertGreaterThan(gap, match.capabilities.bodyRadius * 0.5,
                                     "\(match.players[a].id) inside \(match.players[b].id)")
            }
        }
    }

    // MARK: - the ball and the goals

    /// A shot into the mouth scores for the right team and the match resets to
    /// a kickoff by the conceding side.
    func testAGoalScoresAndPlayRestarts() {
        var match = S.Match()
        while match.phase != .playing { _ = match.advance(dt: dt) }
        // Fire the ball into the away goal's corner, fast, FROM OPEN SPACE.
        // This test has now been taught to aim twice: the first shot went
        // straight down the middle and the keeper kicked it clear; the second
        // teleported the ball within kicking reach of an away defender, who
        // intercepted on the spot and a teammate cleared upfield. Both times
        // the engine was playing defense, which is the game working. From
        // (0.65, 0.18) every defender is out of reach and out of position,
        // and 1.5 m/s crosses the remaining quarter metre before anyone turns.
        match.ball = S.Ball(position: S.Vec2(0.65, 0.18), velocity: S.Vec2(1.5, 0))
        var scored: S.Event?
        for _ in 0..<400 {
            if let goal = match.advance(dt: dt).first(where: {
                if case .goal = $0 { return true }; return false
            }) { scored = goal; break }
        }
        guard case .goal(let team, let scorer)? = scored else {
            return XCTFail("the shot never scored")
        }
        XCTAssertEqual(team, .home)
        XCTAssertTrue(scorer.hasPrefix("home-"))
        XCTAssertEqual(match.score[.home], 1)
        // The reset hands kickoff to the conceding team.
        for _ in 0..<200 {
            _ = match.advance(dt: dt)
            if case .kickoff(let by, _) = match.phase {
                XCTAssertEqual(by, .away)
                return
            }
            if case .playing = match.phase { return }
        }
        XCTFail("play never restarted")
    }

    /// A shot OUTSIDE the posts rebounds off the end board instead of scoring.
    func testWideShotsReboundRatherThanScore() {
        var match = S.Match()
        while match.phase != .playing { _ = match.advance(dt: dt) }
        match.ball = S.Ball(position: S.Vec2(0.5, match.pitch.goalHalfWidth + 0.1),
                            velocity: S.Vec2(1.2, 0))
        for _ in 0..<300 {
            let events = match.advance(dt: dt)
            XCTAssertFalse(events.contains {
                if case .goal = $0 { return true }; return false
            }, "a wide shot must not score")
        }
        XCTAssertEqual(match.score[.home], 0)
        XCTAssertLessThan(match.ball.position.x, match.pitch.halfLength,
                          "the ball came back off the board")
    }

    /// The ball slows and stops on its own — carpet, not ice. Tested on the
    /// ball physics alone: a first version ran the whole match and failed,
    /// correctly, because ten CPUs kept kicking the ball it was waiting on.
    func testTheBallCoastsToAStop() {
        var match = S.Match()
        match.ball = S.Ball(position: .zero, velocity: S.Vec2(0.4, 0))
        for _ in 0..<600 { _ = match.rollBall(dt: dt) }
        XCTAssertEqual(match.ball.velocity.length, 0)
        XCTAssertLessThan(match.ball.position.x, match.pitch.halfLength)
    }

    /// A kick only connects facing the ball, within reach, off cooldown — and
    /// sends the ball the way the DUCK is facing.
    func testAKickIsALegSwingNotATeleport() {
        var match = S.Match(controlledPlayer: "home-3")
        while match.phase != .playing { _ = match.advance(dt: dt) }
        // Park the ball just ahead of home-3, who faces +x.
        var player = match.players.first { $0.id == "home-3" }!
        match.ball = S.Ball(position: player.position + S.Vec2(0.06, 0))
        let events = match.advance(dt: dt, controls: ["home-3": .init(kick: true)])
        XCTAssertTrue(events.contains(.kick(by: "home-3")))
        XCTAssertGreaterThan(match.ball.velocity.x, 0.3, "the ball left along the facing")

        // Immediately again: the cooldown refuses.
        match.ball = S.Ball(position: match.player("home-3")!.position + S.Vec2(0.06, 0))
        let again = match.advance(dt: dt, controls: ["home-3": .init(kick: true)])
        XCTAssertFalse(again.contains(.kick(by: "home-3")), "kicks have a cooldown")

        // And a ball BEHIND the duck cannot be kicked at all.
        player = match.player("home-3")!
        match.ball = S.Ball(position: player.position - S.Vec2(0.06, 0))
        var waited = match
        for _ in 0..<200 { _ = waited.advance(dt: dt) }   // cooldown expires
        waited.ball = S.Ball(position: waited.player("home-3")!.position - S.Vec2(0.06, 0))
        let behind = waited.advance(dt: dt, controls: ["home-3": .init(kick: true)])
        XCTAssertFalse(behind.contains(.kick(by: "home-3")))
    }

    // MARK: - the CPU actually plays

    /// Left alone, ten CPUs produce a real match: the ball moves, kicks
    /// happen, and nobody leaves the pitch.
    func testCPUsPlayFootball() {
        var match = S.Match(controlledPlayer: nil)
        var kicks = 0
        var ballTravelled = 0.0
        var lastBall = match.ball.position
        for _ in 0..<9000 {   // three minutes
            let events = match.advance(dt: dt)
            kicks += events.filter { if case .kick = $0 { return true }; return false }.count
            ballTravelled += (match.ball.position - lastBall).length
            lastBall = match.ball.position
            for player in match.players {
                XCTAssertLessThanOrEqual(abs(player.position.x),
                                         match.pitch.halfLength + 1e-6)
                XCTAssertLessThanOrEqual(abs(player.position.y),
                                         match.pitch.halfWidth + 1e-6)
            }
        }
        XCTAssertGreaterThan(kicks, 5, "a three-minute match with no kicks is not football")
        XCTAssertGreaterThan(ballTravelled, 1.0, "the ball has to actually move")
    }

    /// The keeper keeps: it never strays from its goal line region.
    func testTheKeeperHoldsItsLine() {
        var match = S.Match(controlledPlayer: nil)
        for _ in 0..<6000 { _ = match.advance(dt: dt) }
        let keeper = match.player("home-0")!
        XCTAssertLessThan(keeper.position.x, -match.pitch.halfLength * 0.6,
                          "the keeper wandered upfield to \(keeper.position.x)")
    }

    /// The clock runs only during play, halves change ends of the kickoff, and
    /// the match actually ends.
    func testTwoHalvesAndAFullTimeWhistle() {
        var match = S.Match(halfLength: 5, controlledPlayer: nil)
        var sawHalfTime = false, sawFullTime = false
        for _ in 0..<(60 * 50) {
            for event in match.advance(dt: dt) {
                if event == .halfTime { sawHalfTime = true }
                if event == .fullTime { sawFullTime = true }
            }
            if sawFullTime { break }
        }
        XCTAssertTrue(sawHalfTime)
        XCTAssertTrue(sawFullTime)
        XCTAssertEqual(match.phase, .fullTime)
        XCTAssertEqual(match.half, 2)
        // Full time is terminal: nothing advances.
        let frozen = match
        _ = match.advance(dt: dt)
        XCTAssertEqual(match, frozen)
    }

    /// The envelope holds at 120 Hz too. The shove cap used to be per-tick,
    /// which made a ProMotion phone shove ducks at ten times the robot's
    /// speed and — worse — made two devices at different frame rates play
    /// different matches from identical inputs.
    func testTheEnvelopeHoldsAtProMotionRates() {
        var match = S.Match()
        var previous = match.players
        let caps = match.capabilities
        let fast = 1.0 / 120.0
        for _ in 0..<4000 {
            _ = match.advance(dt: fast,
                              controls: ["home-3": .init(stick: S.Vec2(1, 0.5))])
            if case .playing = match.phase {
                for (index, player) in match.players.enumerated() {
                    let moved = (player.position - previous[index].position).length
                    XCTAssertLessThanOrEqual(
                        moved, caps.fastSpeed * fast + caps.bodyRadius * fast + 1e-9,
                        "\(player.id) broke the envelope at 120 Hz")
                }
            }
            previous = match.players
        }
    }

    /// An idle human no longer benches the team. With a zero stick supplied
    /// every tick — a player holding the phone and doing nothing — the CPUs
    /// still chase: the ball does not sit dead for long stretches.
    func testAnIdleHumanDoesNotDeadlockTheMatch() {
        var match = S.Match(controlledPlayer: "home-3")
        var deadTicks = 0, playingTicks = 0
        for _ in 0..<9000 {   // three minutes, human AFK
            _ = match.advance(dt: dt, controls: ["home-3": S.Control()])
            if case .playing = match.phase {
                playingTicks += 1
                if match.ball.velocity.length == 0 { deadTicks += 1 }
            }
        }
        XCTAssertGreaterThan(playingTicks, 0)
        let deadFraction = Double(deadTicks) / Double(playingTicks)
        XCTAssertLessThan(deadFraction, 0.30,
                          "dead-ball fraction \(deadFraction) — the stall is back")
    }

    /// Consecutive kickoffs differ, so CPU-vs-CPU is not one predetermined
    /// film replayed after every goal. Identical inputs still produce the
    /// identical match — the variation is keyed on the kickoff count, which is
    /// part of the state.
    func testKickoffsVaryAndStayDeterministic() {
        let first = S.Match.lineup(pitch: .livingRoom, kickoffBy: .away, variation: 1)
        let second = S.Match.lineup(pitch: .livingRoom, kickoffBy: .away, variation: 2)
        XCTAssertNotEqual(first, second, "alternate kickoffs must differ")
        XCTAssertEqual(first,
                       S.Match.lineup(pitch: .livingRoom, kickoffBy: .away, variation: 1),
                       "the same variation is the same lineup")
    }

    /// The capabilities the engine ships ARE the measured ones — pinned so a
    /// gameplay tune of the measured numbers cannot slip in as a code review
    /// nit. kickBallSpeed is deliberately absent: it is labelled gameplay
    /// tuning and may move.
    func testTheMeasuredEnvelopeIsTheCanonOne() {
        let caps = S.Capabilities.measured
        XCTAssertEqual(caps.walkSpeed, 0.106, accuracy: 1e-9)
        XCTAssertEqual(caps.fastSpeed, 0.150, accuracy: 1e-9)
        XCTAssertEqual(caps.turnRate, 0.34, accuracy: 1e-9)
    }
}

// MARK: - the controller

extension SoccerEngineTests {

    /// Pulling the stick straight back BACKS THE DUCK UP at the measured
    /// reverse speed — the robot walks backwards under a negative command, and
    /// the first model turned a nine-second pirouette instead, which on a
    /// phone read as "backwards does nothing".
    func testPullingBackBacksUp() {
        var match = S.Match()
        while match.phase != .playing { _ = match.advance(dt: dt) }
        let start = match.player("home-3")!
        // home-3 faces +x; pull straight back for two seconds.
        for _ in 0..<100 {
            _ = match.advance(dt: dt, controls: ["home-3": .init(stick: S.Vec2(-1, 0))])
        }
        let after = match.player("home-3")!
        XCTAssertLessThan(after.position.x, start.position.x - 0.15,
                          "two seconds of reverse covers real ground")
        XCTAssertLessThan(abs(S.angleDelta(from: start.heading, to: after.heading)), 0.5,
                          "it backs up facing the way it was facing")
    }

    func testSprintIsFullEffortFromAHalfDeflectedStick() {
        var match = S.Match()
        while match.phase != .playing { _ = match.advance(dt: dt) }
        var walker = match, sprinter = match
        for _ in 0..<150 {
            _ = walker.advance(dt: dt, controls: ["home-3": .init(stick: S.Vec2(0.4, 0))])
            _ = sprinter.advance(dt: dt, controls: ["home-3": .init(stick: S.Vec2(0.4, 0), sprint: true)])
        }
        let walked = walker.player("home-3")!.position.x - match.player("home-3")!.position.x
        let sprinted = sprinter.player("home-3")!.position.x - match.player("home-3")!.position.x
        XCTAssertGreaterThan(sprinted, walked * 2,
                             "sprint at half deflection beats a half-effort walk")
    }

    /// A pass is a softer kick along the same facing — for feet, not fireworks.
    func testAPassIsSofterThanAShot() {
        var match = S.Match()
        while match.phase != .playing { _ = match.advance(dt: dt) }
        let player = match.player("home-3")!
        var shot = match, pass = match
        shot.ball = S.Ball(position: player.position + S.Vec2(0.06, 0))
        pass.ball = S.Ball(position: player.position + S.Vec2(0.06, 0))
        _ = shot.advance(dt: dt, controls: ["home-3": .init(kick: true)])
        _ = pass.advance(dt: dt, controls: ["home-3": .init(pass: true)])
        XCTAssertGreaterThan(shot.ball.velocity.length, 0.4)
        XCTAssertGreaterThan(pass.ball.velocity.length, 0.2)
        XCTAssertLessThan(pass.ball.velocity.length, shot.ball.velocity.length * 0.7)
    }

    /// Switching hands control to the outfielder best placed for the ball,
    /// never the keeper.
    func testSwitchingControlPicksTheNearestOutfielder() {
        var match = S.Match(controlledPlayer: "home-3")
        while match.phase != .playing { _ = match.advance(dt: dt) }
        // Park the ball beside home-1 (a defender).
        let defender = match.player("home-1")!
        match.ball = S.Ball(position: defender.position + S.Vec2(0.02, 0))
        match.switchControl()
        XCTAssertEqual(match.controlled, "home-1")

        // Beside the keeper: control goes to the nearest OUTFIELDER instead.
        let keeper = match.player("home-0")!
        match.ball = S.Ball(position: keeper.position + S.Vec2(0.01, 0))
        match.switchControl()
        XCTAssertNotEqual(match.controlled, "home-0", "never the keeper")
        XCTAssertTrue(match.controlled?.hasPrefix("home-") == true)
    }
}

// MARK: - engine v3: the roll, the pass, the mark

extension SoccerEngineTests {

    /// The roll is a measured speed burst: 0.559 m in 3.0 s, faster than
    /// walking flat out — and a commitment: no steering, no kicking, then a
    /// cooldown.
    func testTheRollCarriesTheMeasuredDistance() {
        var match = S.Match()
        while match.phase != .playing { _ = match.advance(dt: dt) }
        let start = match.player("home-3")!.position
        var events: [S.Event] = []
        // Press special once, then try to steer hard sideways mid-roll.
        events += match.advance(dt: dt, controls: ["home-3": .init(special: true)])
        for _ in 0..<160 {
            events += match.advance(dt: dt, controls: ["home-3": .init(stick: S.Vec2(0, 1))])
        }
        XCTAssertTrue(events.contains(.roll(by: "home-3")))
        let after = match.player("home-3")!
        XCTAssertEqual(after.position.x - start.x, 0.559, accuracy: 0.02,
                       "the roll carries the canon distance")
        XCTAssertLessThan(abs(after.position.y - start.y), 0.02,
                          "steering mid-roll does nothing — a roll is a commitment")
        XCTAssertNil(after.rollElapsed)

        // Immediately again: cooldown refuses.
        let again = match.advance(dt: dt, controls: ["home-3": .init(special: true)])
        XCTAssertFalse(again.contains(.roll(by: "home-3")))
    }

    /// A capability set with no measured roll cannot roll at all.
    func testNoRollOnAPlantWithoutOne() {
        let caps = S.Capabilities(
            walkSpeed: 0.2, fastSpeed: 0.3, backSpeed: 0.2, turnRate: 0.5,
            kickRange: 0.1, kickCooldown: 1, kickBallSpeed: 0.5,
            passBallSpeed: 0.3, bodyRadius: 0.11)
        XCTAssertFalse(caps.canRoll)
        var match = S.Match(capabilities: caps)
        while match.phase != .playing { _ = match.advance(dt: dt) }
        let events = match.advance(dt: dt, controls: ["home-3": .init(special: true)])
        XCTAssertFalse(events.contains { if case .roll = $0 { return true }; return false })
    }

    /// CPUs pass now. Over a long CPU-vs-CPU spell, some kicks are passes —
    /// the chaser feeding a better-placed teammate rather than always
    /// shooting from wherever it stands.
    func testCPUsPassToBetterPlacedTeammates() {
        // (A first version simulated six minutes of a four-minute match and
        // then waited for phase == .playing — full time is terminal, so the
        // wait was infinite. The match ends; the test must respect that.)
        var match = S.Match(controlledPlayer: nil)
        var kicks = 0
        for _ in 0..<11000 {   // most of the match
            let events = match.advance(dt: dt)
            kicks += events.filter { if case .kick = $0 { return true }; return false }.count
        }
        XCTAssertGreaterThan(kicks, 8, "v3 football still kicks")

        // The pass geometry, asserted directly: striker ahead with a clear
        // lane -> a pass target; lane blocked -> the goal.
        let fresh = S.Match(controlledPlayer: nil)
        var probe = fresh
        probe.ball = S.Ball(position: probe.player("home-3")!.position + S.Vec2(0.05, 0))
        // Move the striker somewhere the lane is GENUINELY clear. This stage
        // has been corrected twice, and both refusals were the lane test
        // being right: first the away striker grazed the pass line at 0.13 m
        // (inside the 0.14 m block), then the receiver stood next to away's
        // left defender — a marked receiver, which is exactly a pass the
        // chooser must refuse. At (0.5, 0.45), with the away striker staged
        // wide, every opponent clears the line by 0.26 m or more — verified
        // by hand against the kickoff lineup before writing these numbers.
        if let index = probe.players.firstIndex(where: { $0.id == "home-4" }) {
            probe.players[index].position = S.Vec2(0.5, 0.45)
        }
        if let index = probe.players.firstIndex(where: { $0.id == "away-4" }) {
            probe.players[index].position = S.Vec2(0.24, -0.5)
        }
        let clear = probe.attackTarget(for: probe.player("home-3")!,
                                       goal: S.Vec2(probe.pitch.halfLength, 0))
        XCTAssertTrue(clear.isPass, "an open striker upfield earns the pass")

        // Park an opponent on the lane: the pass dies, the shot returns.
        if let index = probe.players.firstIndex(where: { $0.id == "away-3" }) {
            probe.players[index].position = S.Vec2(0.2, 0.28)
        }
        let blocked = probe.attackTarget(for: probe.player("home-3")!,
                                         goal: S.Vec2(probe.pitch.halfLength, 0))
        XCTAssertFalse(blocked.isPass, "a marked lane is a turnover with extra steps")
    }

    /// The keeper comes off its line for a close ball — and never further than
    /// the capped advance, so a lob over a stranded keeper is not a thing.
    func testTheKeeperNarrowsTheAngleButNeverStrands() {
        var match = S.Match(controlledPlayer: nil)
        while match.phase != .playing { _ = match.advance(dt: dt) }
        // Park the ball near the home goal.
        match.ball = S.Ball(position: S.Vec2(-match.pitch.halfLength * 0.75, 0.05))
        var deepest = -match.pitch.halfLength
        for _ in 0..<600 {
            _ = match.advance(dt: dt)
            deepest = max(deepest, match.player("home-0")!.position.x)
        }
        let line = -match.pitch.halfLength * 0.94
        XCTAssertGreaterThan(deepest, line + 0.01, "it advances")
        XCTAssertLessThan(deepest, line + match.pitch.length * 0.09 + 0.03,
                          "and never strands")
    }

    /// v3 still holds every v2 contract: determinism and the envelope, now
    /// with the roll's own speed as the one sanctioned excursion.
    func testV3StaysDeterministicAndInsideTheEnvelope() {
        var a = S.Match(), b = S.Match()
        for tick in 0..<3000 {
            let control = S.Control(stick: S.Vec2(1, 0.2),
                                    kick: tick % 70 == 0,
                                    special: tick % 400 == 0)
            _ = a.advance(dt: dt, controls: ["home-3": control])
            _ = b.advance(dt: dt, controls: ["home-3": control])
        }
        XCTAssertEqual(a, b)

        var match = S.Match(controlledPlayer: nil)
        var previous = match.players
        let caps = match.capabilities
        let rollSpeed = caps.rollDistance / caps.rollDuration
        for _ in 0..<6000 {
            _ = match.advance(dt: dt)
            if case .playing = match.phase {
                for (index, player) in match.players.enumerated() {
                    let moved = (player.position - previous[index].position).length
                    let allowed = (player.motion == .rolling ? rollSpeed : caps.fastSpeed)
                        * dt + caps.bodyRadius * dt + 1e-9
                    XCTAssertLessThanOrEqual(moved, allowed,
                                             "\(player.id) at \(moved / dt) m/s in \(player.motion)")
                }
            }
            previous = match.players
        }
    }
}

extension SoccerEngineTests {

    /// Skates: much faster, no roll, and a whole match still works.
    func testSkatesPlayFasterFootballWithNoRoll() {
        XCTAssertFalse(S.Capabilities.skates.canRoll,
                       "no roll is measured on skates, so none is playable")
        XCTAssertGreaterThan(S.Capabilities.skates.walkSpeed,
                             S.Capabilities.measured.fastSpeed * 2)
        var match = S.Match(capabilities: .skates, controlledPlayer: nil)
        var kicks = 0
        for _ in 0..<6000 {
            let events = match.advance(dt: dt)
            kicks += events.filter { if case .kick = $0 { return true }; return false }.count
            for player in match.players {
                XCTAssertLessThanOrEqual(abs(player.position.x),
                                         match.pitch.halfLength + 1e-6)
            }
        }
        XCTAssertGreaterThan(kicks, 5, "skate football still kicks")
    }
}

extension SoccerEngineTests {

    /// The CPUs really do roll now — off the ball, repositioning, IN THE
    /// SCENARIO THE TRIGGER WAS VALIDATED IN: a human on the pitch stretches
    /// play (their duck is excluded from the chase, so the shape deforms),
    /// and a support duck far from its post bursts back. A pure CPU-vs-CPU
    /// match stays compact enough that the gap threshold may never be met —
    /// measured zero rolls there, one to two with an idle human — and this
    /// test pins the scenario that fires rather than pretending both do.
    func testCPUsRollWhenPlayStretchesTheShape() {
        var match = S.Match()
        var cpuRolls = 0
        for _ in 0..<11000 {
            cpuRolls += match.advance(dt: dt, controls: ["home-3": S.Control()]).filter {
                if case .roll = $0 { return true }; return false
            }.count
        }
        XCTAssertGreaterThan(cpuRolls, 0, "the anchor roll fires when the shape stretches")
        XCTAssertLessThan(cpuRolls, 40, "and does not degenerate into roll spam")
    }
}
