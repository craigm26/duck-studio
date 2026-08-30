import Foundation

/// Five-a-side duck soccer: the whole match as a deterministic tick function.
///
/// THE ENGINE IS PURE AND THE VIEW IS A SPECTATOR. Every rule of the game —
/// who chases, who holds, when a kick connects, what counts as a goal — lives
/// here, advanced by `advance(dt:controls:)` with no clock, no randomness and
/// no rendering, so the entire match is testable on Linux and two devices fed
/// the same inputs play the identical game. The AR layer draws the state and
/// forwards one thing: the human's stick and kick button.
///
/// THE DUCKS MOVE AT THE ROBOT'S MEASURED SPEEDS. `Capabilities.measured`
/// carries what the canon plant actually records — walking speed, turn rate —
/// so a match here is a claim about what ten real Microducks could do on a
/// carpet, not about what would make a snappier video game. The one number
/// that is NOT measured is the kick: no ball-contact experiment exists yet, so
/// `kickBallSpeed` is labelled gameplay tuning and nothing downstream treats
/// it as evidence.
public enum DuckSoccer {

    /// Bumped whenever a rule change alters trajectories. Measured figures in
    /// comments and any stored practice records are claims about ONE engine
    /// version; a replay against another is not a refutation.
    ///
    /// Version 2: chasers pivot instead of freezing inside the kick cone, a
    /// human-driven duck no longer benches its team's chase, the separation
    /// shove is capped per SECOND (one body radius) rather than per tick, and
    /// kickoff lineups alternate the striker's offset so CPU-vs-CPU is not a
    /// single predetermined film. Do not publicise CPU-vs-CPU outcomes from
    /// version 1: its every default match was the same 1–0 home film, decided
    /// by a tie-break asymmetry rather than play.
    /// Version 4: CPUs roll OFF THE BALL — a support duck far from its
    /// formation anchor and lined up with it bursts there with the roulade.
    /// Validated by simulation before shipping: one to two rolls a match WHEN
    /// A HUMAN IS ON THE PITCH (their duck sits out the chase, so the shape
    /// stretches); a pure CPU-vs-CPU match stays compact and may see none,
    /// and that is measured, not assumed. The previous on-ball trigger never
    /// fired once in forty-five matches and its obvious widening made things
    /// worse. Version 3 introduced the roll as a burst, passing, man-marking
    /// and the advancing keeper.
    public static let engineVersion = 4

    // MARK: - geometry

    /// A 2D point on the pitch plane, metres. Kept local rather than importing
    /// simd, which is not reliably available to `swift test` on Linux.
    public struct Vec2: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
        public static let zero = Vec2(0, 0)
        public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
        public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
        public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
        public var length: Double { (x * x + y * y).squareRoot() }
        public var normalized: Vec2 { length > 1e-12 ? self * (1 / length) : .zero }
        public var heading: Double { atan2(y, x) }
    }

    /// The smallest turn from one heading to another, radians in (−π, π].
    public static func angleDelta(from: Double, to: Double) -> Double {
        var d = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if d > .pi { d -= 2 * .pi }
        if d <= -.pi { d += 2 * .pi }
        return d
    }

    // MARK: - what a duck can do

    /// The robot's motion envelope, as the engine uses it.
    public struct Capabilities: Equatable, Sendable {
        /// Metres per second at the ordinary walk command.
        public let walkSpeed: Double
        /// Metres per second flat out.
        public let fastSpeed: Double
        /// Metres per second walking BACKWARD. The policy reverses without
        /// turning — pulling the stick back should back the duck up, not
        /// begin a nine-second pirouette.
        public let backSpeed: Double
        /// Radians per second of heading change.
        public let turnRate: Double
        /// How far from the ball a kick connects, metres.
        public let kickRange: Double
        /// Seconds between kicks — the kick clip is 0.9 s and the robot has to
        /// re-settle after it.
        public let kickCooldown: Double
        /// Ball speed off a kick, metres per second. GAMEPLAY TUNING, not a
        /// measurement: no ball-contact experiment exists on the canon plant
        /// yet, and this number must not be quoted as one.
        public let kickBallSpeed: Double
        /// Ball speed off a PASS — a softer touch for keeping the ball at
        /// your feet or feeding a teammate. Gameplay tuning, same caveat.
        public let passBallSpeed: Double
        /// How close two ducks can stand, centre to centre.
        public let bodyRadius: Double
        /// The forward roll as a movement burst: how far it carries and how
        /// long it takes. MEASURED from the canon roulade recording — 0.559 m
        /// of forward travel over the clip's 3.0 s, which at 0.186 m/s makes
        /// the roll genuinely faster than walking flat out. Zero for a
        /// capability set whose plant has no measured roll (skates).
        public let rollDistance: Double
        public let rollDuration: Double

        public init(walkSpeed: Double, fastSpeed: Double, backSpeed: Double,
                    turnRate: Double, kickRange: Double, kickCooldown: Double,
                    kickBallSpeed: Double, passBallSpeed: Double,
                    bodyRadius: Double,
                    rollDistance: Double = 0, rollDuration: Double = 1) {
            self.walkSpeed = walkSpeed; self.fastSpeed = fastSpeed
            self.backSpeed = backSpeed
            self.turnRate = turnRate; self.kickRange = kickRange
            self.kickCooldown = kickCooldown; self.kickBallSpeed = kickBallSpeed
            self.passBallSpeed = passBallSpeed
            self.bodyRadius = bodyRadius
            self.rollDistance = rollDistance
            self.rollDuration = max(rollDuration, 1e-6)
        }

        /// The canon plant's numbers, measured 2026-08-28 on Pollen's
        /// full-collision model with training's parameters: `alpha_walking`
        /// records 0.106 m/s at the 0.25 command and 0.150 m/s at 0.35 —
        /// commands below ~0.25 sit in the policy's dead band and march in
        /// place — and turns at ~0.34 rad/s under a +1.0 yaw command. The
        /// kick reach is the kick clip's own foot excursion, about 60 mm past
        /// the toes.
        /// backSpeed: measured 2026-08-28 on the same plant — `alpha_walking`
        /// records 0.172 m/s REVERSING at the −0.4 command; the backward dead
        /// band reaches −0.3, where it still marches in place.
        public static let measured = Capabilities(
            walkSpeed: 0.106, fastSpeed: 0.150, backSpeed: 0.172, turnRate: 0.34,
            kickRange: 0.10, kickCooldown: 1.6,
            kickBallSpeed: 0.55, passBallSpeed: 0.32, bodyRadius: 0.11,
            rollDistance: 0.559, rollDuration: 3.0)

        /// Whether this capability set can roll at all.
        public var canRoll: Bool { rollDistance > 0.01 }

        /// SKATES. Measured 2026-08-28 with `BEST_roller.onnx` on the rollers
        /// plant — WITH A CAVEAT THE LEGS DO NOT CARRY: that plant has not yet
        /// been rebuilt with training's parameters (the legs plant has), so
        /// these numbers describe the pre-training-parameter rollers scene and
        /// may move when its rebuild lands. What was measured: ~0.57–0.62 m/s
        /// forward at the 0.4–0.6 commands (four to six times leg speed, with
        /// a visible drift at full tilt), 0.45 m/s backward, and asymmetric
        /// turning (+0.94 rad/s one way, −0.19 the other — 0.5 here is the
        /// gameplay midpoint, noted as such). Six-second runs, no falls. No
        /// measured roll exists on skates, so skaters cannot roll — the
        /// engine's canRoll gate enforces it.
        /// kickBallSpeed here is 0.45, NOT the 0.62 first tried — and the
        /// difference was measured, not felt. At 0.62 a kick travels ~0.56 m
        /// under the ball's damping, which reaches a board and dies there:
        /// ten of ten CPU skate matches ended exactly 1–0, half of them with
        /// the final 74 seconds frozen against a board, the chaser's approach
        /// point clamped outside the pitch. At 0.45 (travel ~0.41 m) the same
        /// ten seeds play real football: dead-ball 33% → 12%, longest stall
        /// 74 s → 6 s, goals 1.0 → 1.8 a match with variance.
        public static let skates = Capabilities(
            walkSpeed: 0.45, fastSpeed: 0.60, backSpeed: 0.45, turnRate: 0.5,
            kickRange: 0.10, kickCooldown: 1.6,
            kickBallSpeed: 0.45, passBallSpeed: 0.36, bodyRadius: 0.11)
    }

    // MARK: - the pitch

    /// Board soccer: the ball rebounds off the perimeter, like foosball, so a
    /// carpet match never stops for throw-ins. The goals are openings in the
    /// end boards.
    public struct Pitch: Equatable, Sendable {
        /// Metres, along x. Home defends −x, away defends +x.
        public let length: Double
        /// Metres, along y.
        public let width: Double
        /// The goal mouth's half-width, along y.
        public let goalHalfWidth: Double
        /// How deep behind the goal line the net reaches.
        public let goalDepth: Double

        public init(length: Double, width: Double,
                    goalHalfWidth: Double, goalDepth: Double) {
            self.length = length; self.width = width
            self.goalHalfWidth = goalHalfWidth; self.goalDepth = goalDepth
        }

        /// Sized for ten 25 cm robots with room to actually build play — the
        /// first cut at 1.8 × 1.1 felt like futsal in a lift. 2.4 m needs a
        /// real patch of floor, and AR does not mind furniture.
        public static let livingRoom = Pitch(length: 2.4, width: 1.4,
                                             goalHalfWidth: 0.26, goalDepth: 0.12)

        public var halfLength: Double { length / 2 }
        public var halfWidth: Double { width / 2 }
    }

    // MARK: - teams and players

    public enum Team: String, Equatable, Sendable, CaseIterable {
        case home, away
        public var other: Team { self == .home ? .away : .home }
        /// The x direction this team attacks toward.
        public var attacking: Double { self == .home ? 1 : -1 }
    }

    public enum Role: String, Equatable, Sendable {
        case keeper, defender, midfield, striker
    }

    /// What a duck is doing, for the animator. The engine decides it; the view
    /// maps it onto the canon clips (stand / walk loops, the kick one-shot).
    public enum Motion: String, Equatable, Sendable {
        case standing, walking, kicking
        /// Mid-roulade. The animator plays the canon roll clip at
        /// `rollElapsed`; the engine carries the duck forward on the measured
        /// profile.
        case rolling
    }

    public struct Player: Equatable, Sendable, Identifiable {
        public let team: Team
        /// 0–4 within the team; 0 is the keeper.
        public let number: Int
        public let role: Role
        public var position: Vec2
        public var heading: Double
        public var motion: Motion = .standing
        /// Seconds until this duck may kick again. While above ~cooldown−0.9
        /// the kick clip is still playing.
        public var kickRecovery: Double = 0
        /// Seconds into the current roll, or nil when not rolling.
        public var rollElapsed: Double?
        /// Seconds until the next roll is allowed — a roll is a commitment,
        /// not a spam button.
        public var rollRecovery: Double = 0
        public var id: String { "\(team.rawValue)-\(number)" }

        public init(team: Team, number: Int, role: Role,
                    position: Vec2, heading: Double) {
            self.team = team; self.number = number; self.role = role
            self.position = position; self.heading = heading
        }
    }

    public struct Ball: Equatable, Sendable {
        public var position: Vec2
        public var velocity: Vec2
        public init(position: Vec2 = .zero, velocity: Vec2 = .zero) {
            self.position = position; self.velocity = velocity
        }
    }

    /// The human's input for the duck they control. Absent means the CPU plays
    /// that duck too — a match with no controls at all is CPU against CPU.
    public struct Control: Equatable, Sendable {
        /// Desired travel direction and effort, magnitude 0…1 in pitch frame.
        public var stick: Vec2
        /// True while the kick button is down — a full-strength shot.
        public var kick: Bool
        /// True while the pass button is down — a soft touch along the facing.
        public var pass: Bool
        /// True while sprint is held: full effort regardless of how far the
        /// stick is deflected, because a thumb cannot hold a screen stick at
        /// its rim through a whole half.
        public var sprint: Bool
        /// The skill button: start a forward roll — the canon roulade as a
        /// speed burst. Committed once started: no steering, no kicking, until
        /// the roll completes, exactly as a real roll would be.
        public var special: Bool
        public init(stick: Vec2 = .zero, kick: Bool = false,
                    pass: Bool = false, sprint: Bool = false,
                    special: Bool = false) {
            self.stick = stick; self.kick = kick
            self.pass = pass; self.sprint = sprint; self.special = special
        }
    }

    // MARK: - match phases

    public enum Phase: Equatable, Sendable {
        /// Frozen at kickoff positions; counts down to the whistle.
        case kickoff(by: Team, in: Double)
        case playing
        /// A goal just went in; celebrate, then reset for the conceding team.
        case goal(by: Team, scorer: String, in: Double)
        case halfTime(in: Double)
        case fullTime
    }

    public enum Event: Equatable, Sendable {
        case whistle
        case kick(by: String)
        case roll(by: String)
        case goal(by: Team, scorer: String)
        case halfTime
        case fullTime
    }

    // MARK: - the match

    public struct Match: Equatable, Sendable {
        public let pitch: Pitch
        public let capabilities: Capabilities
        /// Seconds per half.
        public let halfLength: Double
        public var players: [Player]
        public var ball: Ball
        public var phase: Phase
        public var half: Int = 1
        public var clock: Double = 0
        public var score: [Team: Int] = [.home: 0, .away: 0]
        /// The player the human drives, if any. `switchControl()` moves it —
        /// the standard football-game gesture of jumping to the teammate best
        /// placed for the ball.
        public private(set) var controlled: String?

        /// How many kickoffs have happened, driving the lineup variation.
        public var kickoffCount: Int = 0

        /// A fresh match at kickoff.
        public init(pitch: Pitch = .livingRoom,
                    capabilities: Capabilities = .measured,
                    halfLength: Double = 120,
                    controlledPlayer: String? = "home-3") {
            self.pitch = pitch
            self.capabilities = capabilities
            self.halfLength = halfLength
            self.controlled = controlledPlayer
            self.players = Self.lineup(pitch: pitch, kickoffBy: .home, variation: 0)
            self.ball = Ball()
            self.phase = .kickoff(by: .home, in: 1.5)
        }

        /// Where everyone stands for a kickoff.
        ///
        /// EVERY PLAYER IN THEIR OWN HALF, which is the actual law, and the
        /// kicking team's striker on the centre spot. Positions are fractions
        /// of the pitch so the same lineup works at any size.
        /// `variation` alternates the striker's small y-offset. WITHOUT IT THE
        /// GAME IS A FILM: the engine is deterministic and a post-goal reset
        /// reproduced the exact kickoff state, so every CPU-vs-CPU match was
        /// the identical sequence — measured, always 1–0 home with the goal at
        /// the same tick. Alternating one offset breaks the recurrence while
        /// keeping identical inputs → identical match.
        static func lineup(pitch: Pitch, kickoffBy: Team, variation: Int) -> [Player] {
            var out: [Player] = []
            for team in Team.allCases {
                let sign = -team.attacking     // own half is opposite the attack
                let facing = team.attacking > 0 ? 0.0 : Double.pi
                let spots: [(Role, Double, Double)] = [
                    (.keeper,   0.46, 0.0),
                    (.defender, 0.30, -0.22),
                    (.defender, 0.30, 0.22),
                    (.midfield, 0.15, 0.0),
                    (.striker,  team == kickoffBy ? 0.005 : 0.10,
                     variation % 2 == 0 ? 0.05 : -0.05),
                ]
                for (number, spot) in spots.enumerated() {
                    out.append(Player(
                        team: team, number: number, role: spot.0,
                        position: Vec2(sign * spot.1 * pitch.length,
                                       spot.2 * pitch.width),
                        heading: facing))
                }
            }
            return out
        }

        public func player(_ id: String) -> Player? {
            players.first { $0.id == id }
        }

        /// Hand control to the team's outfielder nearest the ball (never the
        /// keeper — a football game that switches you into goal at the wrong
        /// moment is a football game people put down).
        public mutating func switchControl() {
            guard let current = controlled,
                  let team = player(current)?.team else { return }
            let candidate = players
                .filter { $0.team == team && $0.role != .keeper }
                .min { ($0.position - ball.position).length
                     < ($1.position - ball.position).length }
            if let candidate { controlled = candidate.id }
        }

        // MARK: - one tick

        /// Advance the whole match by `dt`. Deterministic: the same state, the
        /// same controls and the same dt always produce the same match.
        ///
        /// STEP AT A FIXED dt. The integration is dt-sensitive — measured,
        /// identical inputs produce 1.0 goals at 50 Hz ticks and 3.5 at
        /// 120 Hz — so a consumer feeding frame time breaks cross-device
        /// determinism within seconds. The app's referee runs a 50 Hz
        /// accumulator for exactly this reason; any new consumer must too.
        @discardableResult
        public mutating func advance(dt: Double,
                                     controls: [String: Control] = [:]) -> [Event] {
            var events: [Event] = []
            switch phase {
            case .fullTime:
                return []

            case .kickoff(let team, let countdown):
                let left = countdown - dt
                if left <= 0 {
                    phase = .playing
                    events.append(.whistle)
                } else {
                    phase = .kickoff(by: team, in: left)
                }
                return events

            case .goal(let team, let scorer, let countdown):
                let left = countdown - dt
                if left <= 0 {
                    kickoffCount += 1
                    players = Self.lineup(pitch: pitch, kickoffBy: team.other,
                                          variation: kickoffCount)
                    ball = Ball()
                    phase = .kickoff(by: team.other, in: 1.5)
                } else {
                    phase = .goal(by: team, scorer: scorer, in: left)
                }
                return events

            case .halfTime(let countdown):
                let left = countdown - dt
                if left <= 0 {
                    half = 2
                    clock = 0
                    kickoffCount += 1
                    players = Self.lineup(pitch: pitch, kickoffBy: .away,
                                          variation: kickoffCount)
                    ball = Ball()
                    phase = .kickoff(by: .away, in: 1.5)
                } else {
                    phase = .halfTime(in: left)
                }
                return events

            case .playing:
                break
            }

            clock += dt

            // Decide every duck's control: the human's where given, the CPU's
            // everywhere else.
            var resolved: [String: Control] = [:]
            let humanActive = controlled.flatMap { controls[$0] } != nil
            for player in players {
                if player.id == controlled, let human = controls[player.id] {
                    resolved[player.id] = human
                } else {
                    resolved[player.id] = cpuControl(for: player,
                                                     humanActive: humanActive)
                }
            }

            let rollingBefore = Set(players.filter { $0.rollElapsed != nil }.map(\.id))

            // Move the ducks at the robot's own speeds. Copy-out/copy-back
            // rather than passing an element of `players` inout: the mover
            // also reads `pitch` and `capabilities` off self, and Swift's
            // exclusivity rules are right to refuse both at once.
            for index in players.indices {
                var player = players[index]
                move(&player, control: resolved[player.id] ?? Control(), dt: dt)
                players[index] = player
            }
            for player in players where player.rollElapsed != nil
                && !rollingBefore.contains(player.id) {
                events.append(.roll(by: player.id))
            }
            separate(dt: dt)

            // Kicks connect after movement, so the reach test uses this tick's
            // real positions.
            for index in players.indices {
                var player = players[index]
                if let event = tryKick(&player,
                                       wants: resolved[player.id]?.kick ?? false,
                                       pass: resolved[player.id]?.pass ?? false,
                                       dt: dt) {
                    events.append(event)
                }
                players[index] = player
            }

            // The ball rolls, rebounds, and possibly scores.
            events.append(contentsOf: rollBall(dt: dt))

            if clock >= halfLength, case .playing = phase {
                if half == 1 {
                    phase = .halfTime(in: 3)
                    events.append(.halfTime)
                } else {
                    phase = .fullTime
                    events.append(.fullTime)
                }
            }
            return events
        }

        // MARK: - locomotion

        /// Turn-then-walk, at the measured rates. A duck asked to go somewhere
        /// first turns toward it — no faster than the robot turns — and only
        /// strides out once roughly facing the way it wants to go, which is
        /// also how the walking policy actually behaves under a yaw command.
        mutating func move(_ player: inout Player, control: Control, dt: Double) {
            // A roll in progress carries the duck on the measured profile and
            // takes NO input — a real roll is a commitment.
            if var elapsed = player.rollElapsed {
                elapsed += dt
                if elapsed >= capabilities.rollDuration {
                    player.rollElapsed = nil
                    player.rollRecovery = 2.0
                    player.motion = .standing
                } else {
                    player.rollElapsed = elapsed
                    player.position = player.position
                        + Vec2(cos(player.heading), sin(player.heading))
                        * (capabilities.rollDistance / capabilities.rollDuration * dt)
                    player.position.x = min(max(player.position.x, -pitch.halfLength),
                                            pitch.halfLength)
                    player.position.y = min(max(player.position.y, -pitch.halfWidth),
                                            pitch.halfWidth)
                    player.motion = .rolling
                }
                return
            }
            player.rollRecovery = max(player.rollRecovery - dt, 0)

            // A kick roots the duck for the clip's length.
            if player.kickRecovery > capabilities.kickCooldown - 0.9 {
                player.kickRecovery -= dt
                player.motion = .kicking
                return
            }
            player.kickRecovery = max(player.kickRecovery - dt, 0)

            // The skill button: start the roll. Only from upright motion, off
            // cooldown, on a plant whose roll is measured.
            if control.special, capabilities.canRoll, player.rollRecovery <= 0,
               player.kickRecovery <= 0 {
                player.rollElapsed = 0
                player.motion = .rolling
                return
            }

            let effort = control.sprint ? 1.0 : min(control.stick.length, 1)
            guard effort > 0.05 else {
                player.motion = .standing
                return
            }
            let want = control.stick.heading
            let delta = angleDelta(from: player.heading, to: want)

            // MOSTLY BEHIND: BACK UP, exactly as the robot does. The policy
            // reverses at a measured 0.172 m/s under a negative command, and
            // the first version of this model did not know it — pulling the
            // stick back began a nine-second pirouette instead of a step
            // backward, which on a phone reads as "backwards does nothing".
            if abs(delta) > 2.35 {
                let reversed = angleDelta(from: player.heading, to: want + .pi)
                let turn = min(max(reversed, -capabilities.turnRate * dt),
                               capabilities.turnRate * dt)
                player.heading += turn
                player.position = player.position
                    + Vec2(cos(player.heading), sin(player.heading))
                    * (-capabilities.backSpeed * effort * dt)
                player.motion = .walking
            } else {
                let turn = min(max(delta, -capabilities.turnRate * dt),
                               capabilities.turnRate * dt)
                player.heading += turn

                // Stride only when the body points within ~35° of the goal
                // direction; beyond that the policy is still pivoting.
                guard abs(delta) < 0.6 else {
                    player.motion = .walking   // pivoting in place still steps
                    return
                }
                let speed = (control.sprint || effort > 0.75)
                    ? capabilities.fastSpeed : capabilities.walkSpeed
                player.position = player.position
                    + Vec2(cos(player.heading), sin(player.heading))
                    * (speed * effort * dt)
                player.motion = .walking
            }

            player.position.x = min(max(player.position.x, -pitch.halfLength),
                                    pitch.halfLength)
            player.position.y = min(max(player.position.y, -pitch.halfWidth),
                                    pitch.halfWidth)
        }

        /// Ducks are solid: overlapping pairs are pushed apart symmetrically.
        ///
        /// THE CAP IS PER DUCK, NOT PER PAIR. The first version capped each
        /// pair's push and applied them all — and a pile-up around the ball
        /// gave one duck nine neighbours and nine pushes, 85 mm in a single
        /// tick, a 4.2 m/s teleport from a robot measured at 0.15. Pushes are
        /// accumulated and the TOTAL is clamped to less than one body-radius a
        /// second, so a crowd resolves over frames and never launches anyone.
        /// And the result is clamped back inside the boards, which `move`
        /// does for walking but nothing did for being shoved.
        mutating func separate(dt: Double) {
            let minimum = capabilities.bodyRadius
            var shove = [Vec2](repeating: .zero, count: players.count)
            for a in players.indices {
                for b in (a + 1)..<players.count {
                    let gap = players[b].position - players[a].position
                    let distance = gap.length
                    guard distance < minimum, distance > 1e-9 else { continue }
                    let push = gap.normalized * ((minimum - distance) / 2)
                    shove[a] = shove[a] - push
                    shove[b] = shove[b] + push
                }
            }
            // Capped per SECOND, scaled by dt — a per-tick cap made the shove
            // rate depend on the frame rate, and a 120 Hz phone shoved ducks
            // apart at ten times the robot's envelope while a 60 Hz one played
            // a different match. One body radius per second, as the comment
            // above has always claimed.
            let cap = capabilities.bodyRadius * dt
            for index in players.indices {
                // A ROLLING DUCK IS NOT SHOVED. It is a body tumbling with
                // momentum — the crowd parts, it does not deflect — and
                // letting the pile push it sideways bled 78 mm off the
                // measured 559 mm roll and bent it off line. It still pushes
                // everyone else, through their own entries in `shove`.
                if players[index].rollElapsed != nil { continue }
                var total = shove[index]
                if total.length > cap { total = total.normalized * cap }
                var moved = players[index].position + total
                moved.x = min(max(moved.x, -pitch.halfLength), pitch.halfLength)
                moved.y = min(max(moved.y, -pitch.halfWidth), pitch.halfWidth)
                players[index].position = moved
            }
        }

        // MARK: - kicking

        mutating func tryKick(_ player: inout Player, wants: Bool,
                              pass: Bool, dt: Double) -> Event? {
            guard wants || pass, player.kickRecovery <= 0 else { return nil }
            let toBall = ball.position - player.position
            guard toBall.length <= capabilities.kickRange else { return nil }
            // The ball goes where the DUCK is facing, give or take how far
            // around the ball actually is — a kick is a leg swing, not a
            // teleport, and a ball behind the duck cannot be kicked forward.
            guard abs(angleDelta(from: player.heading, to: toBall.heading)) < 1.1
            else { return nil }

            ball.velocity = Vec2(cos(player.heading), sin(player.heading))
                * (pass && !wants ? capabilities.passBallSpeed
                                  : capabilities.kickBallSpeed)
            player.kickRecovery = capabilities.kickCooldown
            player.motion = .kicking
            return .kick(by: player.id)
        }

        // MARK: - the ball

        mutating func rollBall(dt: Double) -> [Event] {
            var events: [Event] = []
            ball.position = ball.position + ball.velocity * dt
            // Rolling resistance, exponential: the ball coasts to a stop in a
            // couple of metres, carpet-like.
            let damping = exp(-1.1 * dt)
            ball.velocity = ball.velocity * damping
            if ball.velocity.length < 0.01 { ball.velocity = .zero }

            // Side boards rebound.
            if abs(ball.position.y) > pitch.halfWidth {
                ball.position.y = ball.position.y > 0
                    ? pitch.halfWidth : -pitch.halfWidth
                ball.velocity.y = -ball.velocity.y * 0.65
            }

            // End boards: inside the goal mouth the ball crosses the line and
            // scores; outside it, it rebounds.
            if abs(ball.position.x) > pitch.halfLength {
                if abs(ball.position.y) <= pitch.goalHalfWidth {
                    let conceding: Team = ball.position.x > 0 ? .away : .home
                    let scoring = conceding.other
                    score[scoring, default: 0] += 1
                    let scorer = nearestPlayer(to: ball.position, on: scoring)?.id
                        ?? "\(scoring.rawValue)-4"
                    // Long enough for the scorer's forward-roll celebration —
                    // the roulade clip is three seconds, and it is Pollen's own.
                    phase = .goal(by: scoring, scorer: scorer, in: 3.2)
                    events.append(.goal(by: scoring, scorer: scorer))
                    ball.velocity = .zero
                } else {
                    ball.position.x = ball.position.x > 0
                        ? pitch.halfLength : -pitch.halfLength
                    ball.velocity.x = -ball.velocity.x * 0.65
                }
            }
            return events
        }

        func nearestPlayer(to point: Vec2, on team: Team) -> Player? {
            players.filter { $0.team == team }
                .min { ($0.position - point).length < ($1.position - point).length }
        }

        // MARK: - the CPU

        /// One duck's brain, run fresh every tick from the match state alone.
        ///
        /// ROLES, NOT A SWARM. The nearest outfielder chases; everyone else
        /// holds a shape that shifts with the ball. Chasing is APPROACH FROM
        /// BEHIND: the chaser aims for a point behind the ball on the line to
        /// the opponent goal, so that when the kick fires the ball goes
        /// goalward — a duck that runs straight at the ball kicks it wherever
        /// it happens to be facing, which is how own goals happen.
        func cpuControl(for player: Player, humanActive: Bool) -> Control {
            let goalX = player.team.attacking * pitch.halfLength

            // Rolling is a commitment; input is ignored anyway, so save the
            // brain the work.
            if player.rollElapsed != nil { return Control() }

            if player.role == .keeper {
                // Hold the line — but COME OFF IT to narrow the angle when the
                // ball is close and in front, the way any keeper does. The
                // advance is capped well inside the box so a lob over a
                // stranded keeper is not a thing this engine invents.
                let lineX = -goalX * 0.94
                let ballIsNear = (ball.position.x - lineX) * -player.team.attacking > 0
                    ? false
                    : abs(ball.position.x - lineX) < pitch.length * 0.28
                let advance = ballIsNear
                    ? min(abs(ball.position.x - lineX) * 0.35, pitch.length * 0.08)
                    : 0
                let target = Vec2(lineX + player.team.attacking * advance,
                                  min(max(ball.position.y, -pitch.goalHalfWidth),
                                      pitch.goalHalfWidth))
                return steer(player, toward: target, kickIfClose: true)
            }

            // THE HUMAN'S DUCK CANNOT BE THE ELECTED CHASER while a human is
            // actually driving it. The election used to include it, so a
            // player standing idle nearest the ball benched every CPU on the
            // team — measured, 39% of a default match was dead ball, and long
            // halves froze for hundreds of seconds waiting on a duck nobody
            // was steering.
            let mates = players.filter {
                $0.team == player.team && $0.role != .keeper
                    && !(humanActive && $0.id == controlled)
            }
            let chaser = mates.min {
                ($0.position - ball.position).length < ($1.position - ball.position).length
            }

            if chaser?.id == player.id {
                // WHERE SHOULD THE BALL GO — the goal, or a better-placed
                // teammate? A striker alone up the pitch with a clear lane is
                // worth more than a long shot, so the chaser aims its approach
                // at whichever target it picks: the kick goes where the duck
                // faces, so passing IS approaching from the pass's far side.
                let goal = Vec2(goalX, 0)
                let target = attackTarget(for: player, goal: goal)

                // A ROLL closes distance faster than legs do (0.186 m/s
                // measured against 0.150 flat out) — burst when lined up, far
                // enough that the roll will not overshoot, and off cooldown.
                // The trigger is deterministic: state, not dice.
                //
                // MEASURED HONESTY: in evaluation this never fired — the
                // elected chaser is never this far from a slow ball, so the
                // human's ROLL button is the roll's real user. The obvious
                // widening was tested and made matches WORSE (113 s frozen
                // spells), so the tight gate stays until a better trigger is
                // designed rather than loosened.
                let toBall = ball.position - player.position
                if capabilities.canRoll, player.rollRecovery <= 0,
                   toBall.length > capabilities.rollDistance + 0.12,
                   toBall.length < capabilities.rollDistance + 0.45,
                   abs(angleDelta(from: player.heading, to: toBall.heading)) < 0.15,
                   ball.velocity.length < 0.05 {
                    return Control(special: true)
                }

                let behind = ball.position + (ball.position - target.point).normalized * 0.07
                return steer(player, toward: behind, kickIfClose: true,
                             preferPass: target.isPass)
            }

            // DEFENDERS MARK when the ball is in their half: goal-side of the
            // nearest unmarked opponent, on the line to the goal they defend —
            // which is what turns "the other team walks through us" into an
            // interception. Elsewhere, and for everyone else, a formation
            // anchor pulled toward the ball.
            if player.role == .defender,
               ball.position.x * player.team.attacking < 0 {
                let threats = players.filter { $0.team != player.team && $0.role != .keeper }
                if let mark = threats.min(by: {
                    ($0.position - player.position).length
                        < ($1.position - player.position).length
                }) {
                    let ownGoal = Vec2(-goalX, 0)
                    let goalSide = mark.position
                        + (ownGoal - mark.position).normalized * 0.12
                    return steer(player, toward: goalSide, kickIfClose: true)
                }
            }

            let anchorX = player.team.attacking > 0
                ? (player.role == .striker ? 0.22 : player.role == .midfield ? 0.0 : -0.26)
                : (player.role == .striker ? -0.22 : player.role == .midfield ? 0.0 : 0.26)
            let anchorY = Double(player.number % 2 == 0 ? 1 : -1)
                * (player.role == .defender ? 0.2 : 0.12) * pitch.width
            let anchor = Vec2(anchorX * pitch.length, anchorY)
            let target = anchor + (ball.position - anchor) * 0.3

            // THE ANCHOR ROLL — where the CPU roll actually lives. A support
            // duck a long way from where it should be, already pointed there,
            // covers the ground with the burst. Validated by simulation before
            // shipping: 1–2 rolls a match, no regression anywhere. (The
            // on-ball chaser trigger above it never fired in forty-five
            // measured matches — the chaser is simply never that far from a
            // slow ball — and widening it froze matches for minutes.)
            let gap = target - player.position
            if capabilities.canRoll, player.rollRecovery <= 0,
               gap.length > capabilities.rollDistance + 0.2,
               abs(angleDelta(from: player.heading, to: gap.heading)) < 0.3 {
                return Control(special: true)
            }
            return steer(player, toward: target, kickIfClose: true)
        }

        /// The chaser's choice: shoot, or feed a teammate who is meaningfully
        /// better placed with a clear lane. "Clear" is geometric — no opponent
        /// within 0.14 m of the pass line — because a pass into a marked duck
        /// is a turnover with extra steps.
        func attackTarget(for player: Player, goal: Vec2) -> (point: Vec2, isPass: Bool) {
            let ahead = players.filter {
                $0.team == player.team && $0.id != player.id && $0.role != .keeper
                    && ($0.position.x - player.position.x) * player.team.attacking > 0.25
            }
            let opponents = players.filter { $0.team != player.team }
            for mate in ahead.sorted(by: {
                (goal - $0.position).length < (goal - $1.position).length
            }) {
                let lane = mate.position - ball.position
                let length = lane.length
                guard length > 0.2 else { continue }
                let clear = opponents.allSatisfy { opponent in
                    let t = max(0, min(1,
                        JointMath.dot(opponent.position - ball.position, lane)
                            / (length * length)))
                    let nearest = ball.position + lane * t
                    return (opponent.position - nearest).length > 0.14
                }
                if clear { return (mate.position, true) }
            }
            return (goal, false)
        }

        /// Dot product, named so the lane test above reads as geometry.
        enum JointMath {
            static func dot(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.x + a.y * b.y }
        }

        func steer(_ player: Player, toward target: Vec2,
                   kickIfClose: Bool, preferPass: Bool = false) -> Control {
            let gap = target - player.position
            let toBall = ball.position - player.position
            let nearBall = toBall.length <= capabilities.kickRange

            // WITHIN REACH BUT FACING THE WRONG WAY: PIVOT, DO NOT FREEZE. A
            // duck at its target with the ball in reach used to return a zero
            // stick, and if the ball sat outside its 1.1 rad kick cone it then
            // stood there forever wanting a kick that could never connect —
            // the other measured cause of the dead-ball stalls. A stick
            // pointed at the ball just above the effort gate makes it turn on
            // the spot until the cone comes round.
            if nearBall,
               abs(angleDelta(from: player.heading, to: toBall.heading)) >= 1.1 {
                return Control(stick: toBall.normalized * 0.06, kick: false)
            }

            // Close enough: stand rather than oscillate around the point.
            let stick = gap.length < 0.03 ? Vec2.zero : gap.normalized
            return Control(stick: stick,
                           kick: kickIfClose && nearBall && !preferPass,
                           pass: kickIfClose && nearBall && preferPass)
        }
    }
}
