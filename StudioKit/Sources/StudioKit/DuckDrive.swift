import Foundation
import DuckKit

/// Driving a policy live, rather than recording one and watching it back.
///
/// WHAT THIS IS FOR. Everything else in this app is past tense: a clip is what
/// a network already did, a measurement is how often it already worked. This is
/// the present tense — a policy loaded, a stick under your thumb, the duck
/// answering while you steer it. It is the screen somebody wants when they ask
/// "can I drive it", and it is the screen that will be pointed at a real
/// Microduck the day robotd's interface is pinned down, unchanged in shape.
///
/// IT DRIVES A BENCH, AND IT IS NOT A ROBOT. Nobody has hardware yet, and this
/// app talks to no robot at all — `robotd` appears in this package only as a
/// source of constants, cited by file and symbol. What is on the other end of
/// these calls is `sim/duckbench.mjs`: MuJoCo on a machine on your network. The
/// screen says so; so does this comment, because the day a real transport
/// arrives, the difference must be a thing somebody chose rather than a thing
/// that quietly stopped being written down.
///
/// THE SHAPE IS POLLEN'S, AND THAT IS DELIBERATE. Their own contract
/// (`duck-ipc-proto/src/lib.rs`) splits what a client may ask for into
/// continuous intents — `robot.move`, `robot.head`, sent as JSON-RPC
/// notifications at 20–50 Hz, last-writer-wins and EXPIRING — and discrete ones
/// — `robot.stop`, `robot.enable`, sent as requests because the caller needs to
/// know whether it was accepted. `robot.move`'s parameters are `{vx, vy, vyaw}`,
/// the same three names the bench takes, in the trunk frame: x forward, y left,
/// z up, positive vyaw turns left. A stick repeatedly sending a twist is not a
/// shape invented here; it is the shape the robot already has.
///
/// WHERE THE BENCH AND THE ROBOT GENUINELY DIFFER: the deadman. On the robot a
/// `move` expires, and `padd`'s own comment turns on it — "The deadman would
/// catch it eventually; a robot that keeps walking because you started moving
/// its head is a bad enough surprise". Here there is nothing to arm, because the
/// bench only advances physics inside a request: "miss the next intent and the
/// duck is not still walking, it is frozen mid-stride." A dropped link cannot
/// leave this walking into a wall. It is the one safety property of this screen
/// that comes free from the simulator and would have to be BUILT against
/// hardware, so it is written down here rather than discovered by a robot.
///
/// AND THE TRANSPORT IS NOT REACHABLE FROM A PHONE TODAY. `robotd` speaks
/// JSON-RPC over Unix sockets — `/run/robotd.sock` — with WebRTC named in the
/// contract as where continuous intents will travel "later". There is no network
/// endpoint for an iPhone to open, which is why this drives a bench and why no
/// amount of care in this file would make it drive a duck.
public enum DuckDrive {

    // MARK: - what the stick can ask for
    //
    // THE STICKS ARE POLLEN'S PAD, NUMBER FOR NUMBER. `Pad` below is
    // `robotd-params` in pollen-robotics/microduck at 094d4bb4 (release 0.21.1),
    // the defaults `padd` and `netpadd` drive a real Microduck with when
    // `robotd.toml` says nothing. Somebody who has driven the robot with a pad
    // has muscle memory for exactly these, and a phone that felt different at
    // the same stick deflection would be teaching a second set of reflexes for
    // one robot. `DuckPadDefaultsTests` pins every one against its source line.

    /// Pollen's default pad envelope and shaping, cited by file and line at
    /// pollen-robotics/microduck 094d4bb4.
    public enum Pad {
        /// Full stick forward, m/s: `PadDriveParams::default()` `vx_max`
        /// (robotd-params/src/lib.rs:291). 0.4 since the v8 velstand.
        public static let forward = 0.4
        /// Full stick back, m/s: `vx_min` = -0.3 (robotd-params/src/lib.rs:292,
        /// "default vx_min is -0.3", 145e91b2).
        public static let backward = 0.3
        /// Full stick sideways, m/s: `vy_max` / `vy_min` (robotd-params/src/lib.rs:293-294).
        public static let sideways = 0.3
        /// Full right stick, rad/s: `vyaw_max` / `vyaw_min` (robotd-params/src/lib.rs:295-296).
        public static let turn = 1.0
        /// Deflection below this counts as centre, per axis, with no rescale of
        /// what is left: `PadAxesParams` `deadzone` (robotd-params/src/pad_axes.rs:220,
        /// applied at pad_axes.rs:56).
        public static let deadzone = 0.1
        /// Full-deflection head travel, radians, every joint: `PadHeadParams::default()`
        /// (robotd-params/src/pad_axes.rs:266).
        public static let headTravel = 2.5
        /// The head sticks' response curve, `(1 - e)·x + e·x³`: `DEFAULT_EXPO`
        /// (robotd-params/src/pad_axes.rs:271, shape at :287-290). The drive sticks
        /// are linear (`PadDriveParams::scale`, lib.rs:313-319).
        public static let headExpo = 0.6
        /// The fastest a stick moves the head target, rad/s per joint:
        /// `DEFAULT_MAX_SPEED` (robotd-params/src/pad_axes.rs:272).
        public static let headMaxSpeed = 10.0
        /// The longest step the head cap allows for, seconds: `HEAD_SLEW_MAX_DT`
        /// (pad-map/src/mapper.rs:557), so a late frame is not a second's worth of head.
        public static let headMaxStep = 0.1

        /// `[pad_roller]` on wheels: forward 0.6, back 0.5, no strafe, 0.3 rad/s
        /// (robotd-params/src/pad_axes.rs:330-341). Not used by `twist(for:)`: this app cannot
        /// read a duck's drive mode yet (`DuckPadMap.modeIsAnAssumption`).
        public static let rollerForward = 0.6
        public static let rollerBackward = 0.5
        public static let rollerSideways = 0.0
        public static let rollerTurn = 0.3

        /// The head curve, odd and fixed at 0 and ±1, exactly as `PadHeadParams::shape`.
        public static func shape(_ x: Double) -> Double {
            (1 - headExpo) * x + headExpo * x * x * x
        }
    }

    /// The fastest a PLANNED forward walk goes, m/s: typed moves, Tell, plans,
    /// replayed decisions and every brain's envelope (`DuckEnvelopeGate`).
    ///
    /// NOT THE STICK. The stick reaches Pollen's `Pad.forward`, 0.4. This
    /// stays at 0.3, the speed duckbench measured (`alpha_walking` covers
    /// 0.681 m in six seconds at vx = 0.3 and 1.207 m at 0.5) and the one every
    /// planner and its golden cases were written against. Pollen publishes a
    /// pad default and nothing for a client that is not a pad; robotd does not
    /// clamp `robot.move`, so a planner's ceiling is this app's to choose, and
    /// a thumb on a stick is not.
    public static let maxForward = 0.3

    /// Backwards, m/s: Pollen's pad back speed, `Pad.backward`.
    public static let maxBackward = Pad.backward

    /// Strafing, m/s: `Pad.sideways`.
    public static let maxSideways = Pad.sideways

    /// Turning, rad/s: `Pad.turn`, Pollen's 1.0 since the v8 velstand. robotd
    /// does not clamp a `robot.move` to it, so this side does: the sticks,
    /// typed moves and every plan's turn top out here.
    public static let maxTurn = Pad.turn

    /// Stick deflection below which the axis reads as centred: `Pad.deadzone`.
    ///
    /// THIS IS NOT `deadZone` BELOW. That one is the gait's, in twist units,
    /// and it is about what the ROBOT does with a small command. This one is
    /// the stick's, in stick units, and it is about a thumb that cannot hold
    /// still. Both exist; conflating them would put the wrong number in the
    /// wrong place.
    public static let stickDeadzone = Pad.deadzone

    /// How long one `/intent` holds its command, seconds.
    ///
    /// THE BENCH'S OWN DEFAULT — five ticks at 50 Hz. `padd` sends `robot.move`
    /// at 50 Hz flat, polling the sticks so the last known value keeps going
    /// out whether or not the pad reported anything new. This cannot do that:
    /// each call to the bench advances physics and answers, so the loop is
    /// paced by the round trip rather than by a timer.
    public static let holdSeconds = 0.1

    /// Below this twist magnitude the standing policy takes over — so a stick
    /// nudged this gently produces a duck that stands there, correctly.
    ///
    /// IT IS ON SCREEN BECAUSE IT LOOKS LIKE A FAULT. `DuckModel`'s threshold
    /// is 0.05, and a person easing the stick off centre and seeing nothing
    /// happen concludes the link is dead or the policy is broken. It is
    /// neither: it is the gait doing what it was trained to do.
    public static let deadZone = DuckModel.standingThreshold

    /// Where one stick is, as the two numbers a thumb produces: each -1...1,
    /// centre is rest.
    public struct Stick: Equatable, Sendable {
        /// Right positive.
        public let x: Double
        /// Forward positive. NOTE this is already flipped from a view's
        /// coordinates, where down the screen is positive y — the flip belongs
        /// with the gesture that knows about screens, not here.
        public let y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        public static let centred = Stick(x: 0, y: 0)

        /// The axis, with `padd`'s per-axis deadzone applied and the value
        /// clamped. Non-finite reads as centred rather than propagating.
        func axis(_ v: Double) -> Double {
            guard v.isFinite else { return 0 }
            return abs(v) < stickDeadzone ? 0 : min(max(v, -1), 1)
        }
    }

    /// Both thumbs, in `padd`'s layout.
    ///
    /// TWO STICKS RATHER THAN ONE, AND THE REASON IS THE ROBOT'S. A first pass
    /// here used a single pad with turning on its x axis, which is a reasonable
    /// phone idiom and is NOT how a Microduck is driven: `padd` puts translation
    /// on the left stick — forward on its y, strafe on its x — and yaw on the
    /// RIGHT stick's x, so a driver can walk sideways and turn independently.
    /// Somebody who has driven the real robot would have found one pad missing
    /// half of what they can do, and would have had `vy` silently pinned to
    /// zero while the wire carried a field for it.
    public struct Sticks: Equatable, Sendable {
        /// Translation: y forward, x strafe.
        ///
        /// `var` SO A PAD CAN BIND TO IT. Two thumbs move independently and
        /// each pad owns one; `let` would make the pair writable only as a
        /// whole, which is not how fingers work.
        public var left: Stick
        /// Heading: x turns. Its y is unused here — `padd` spends it on head
        /// pose in a separate mode, which this screen does not offer.
        public var right: Stick

        public init(left: Stick, right: Stick) {
            self.left = left
            self.right = right
        }

        public static let centred = Sticks(left: .centred, right: .centred)
    }

    /// A command to send, and whether it will do anything.
    public struct Twist: Equatable, Sendable {
        public let vx: Double, vy: Double, vyaw: Double

        /// Whether this lands inside the dead zone, where the standing policy
        /// takes over and the duck simply stands.
        public var standsStill: Bool { magnitude <= deadZone }

        public var magnitude: Double {
            (vx * vx + vy * vy + vyaw * vyaw).squareRoot()
        }

        public init(vx: Double, vy: Double, vyaw: Double) {
            self.vx = vx; self.vy = vy; self.vyaw = vyaw
        }

        public static let still = Twist(vx: 0, vy: 0, vyaw: 0)
    }

    /// What the sticks mean, in the units the policy reads.
    ///
    /// TRANSCRIBED FROM `padd/src/main.rs`, SIGNS INCLUDED. Their Drive branch
    /// is `vx: left_y * max_linear` (or `max_linear_backward` when pushed back),
    /// `vy: -left_x * max_linear`, `vyaw: -right_x * max_angular`. Both
    /// negations are load-bearing and neither is obvious: the protocol fixes
    /// `vy` positive to the LEFT and `vyaw` positive turning LEFT, while a stick
    /// pushed left reads negative. Get either wrong and the duck mirrors you.
    ///
    /// Pollen's contract is emphatic about why these conventions are written
    /// down rather than rediscovered: the prototype grew five separate sign
    /// flags "precisely because the convention was never written down, so every
    /// new consumer determined it empirically and disagreed."
    public static func twist(for sticks: Sticks) -> Twist {
        let leftX = sticks.left.axis(sticks.left.x)
        let leftY = sticks.left.axis(sticks.left.y)
        let rightX = sticks.right.axis(sticks.right.x)
        return Twist(vx: leftY * (leftY >= 0 ? Pad.forward : Pad.backward),
                     vy: -leftX * Pad.sideways,
                     vyaw: -rightX * Pad.turn)
    }

    /// Full-deflection head travel, radians: `Pad.headTravel`.
    ///
    /// GENEROUS ON PURPOSE AND NOT A SERVO LIMIT. `padd`'s own note: "the head
    /// command feeds the policy's observation rather than a servo directly, so
    /// this is the prototype's generous 2.5 — the network itself decides how
    /// far the head actually goes." Clamping it here would be this app deciding
    /// something the policy is trained to decide.
    public static let maxHead = Pad.headTravel

    /// The head pose the sticks mean, in `padd`'s Head mode.
    ///
    /// A MODE AND NOT A FIFTH AXIS, WHICH IS THE PART WORTH TRANSCRIBING.
    /// `padd` does not steal one stick for the head while the other drives: in
    /// `Mode::Head` BOTH sticks pose the head and the body twist is zeroed in
    /// the same frame, with a comment saying exactly why — "a robot that keeps
    /// walking because you started moving its head is a bad enough surprise to
    /// be explicit about". `DuckKit` makes the same argument from the other
    /// side: the twist alone decides walking versus standing, so head motion
    /// must not make the robot think it is walking. So a caller that sends this
    /// sends a still twist beside it, and `DuckDrive.stillWhilePosingTheHead`
    /// is that rule in a sentence.
    ///
    /// THE SIGNS ARE THEIRS, INCLUDING THE TWO INVERSIONS. `head_pitch` and
    /// `head_yaw` are negated relative to stick direction; `padd` marks that
    /// mapping "verified on hardware there, kept verbatim here", which is
    /// exactly the kind of thing this app must copy rather than reason about.
    ///
    /// AND THE CURVE IS THEIRS: each axis goes through `Pad.shape` (expo 0.6)
    /// before the travel, as `stick_frame`'s `look` does (pad-map/src/mapper.rs),
    /// so half a stick is 28% of the travel and small corrections are possible.
    /// The speed cap is `HeadGlide`'s, because it needs the last pose sent.
    public static func head(for sticks: Sticks) -> DuckHead {
        let leftX = Pad.shape(sticks.left.axis(sticks.left.x))
        let leftY = Pad.shape(sticks.left.axis(sticks.left.y))
        let rightX = Pad.shape(sticks.right.axis(sticks.right.x))
        let rightY = Pad.shape(sticks.right.axis(sticks.right.y))
        return DuckHead(neckPitch: rightY * maxHead,
                        headPitch: -leftY * maxHead,
                        headYaw: -leftX * maxHead,
                        headRoll: rightX * maxHead)
    }

    /// Pollen's `HeadSlew` (pad-map/src/mapper.rs): the stick-driven head target
    /// moves at most `Pad.headMaxSpeed` rad/s per joint, so a full snap glides
    /// instead of jumping. A small move stays under the cap and is untouched.
    /// The first pose after `reset()` goes out as asked, as theirs does.
    public struct HeadGlide: Sendable {
        private var sent: DuckHead?
        private var at: Date?

        public init() {}

        /// Forget the last pose: the sticks stopped posing the head.
        public mutating func reset() { sent = nil; at = nil }

        /// The pose to send now, given what the sticks ask for.
        public mutating func next(_ target: DuckHead, at now: Date) -> DuckHead {
            let dt = at.map { min(max(now.timeIntervalSince($0), 0), Pad.headMaxStep) } ?? 0
            at = now
            guard let from = sent else { sent = target; return target }
            let step = Pad.headMaxSpeed * dt
            func toward(_ a: Double, _ b: Double) -> Double { a + min(max(b - a, -step), step) }
            let out = DuckHead(neckPitch: toward(from.neckPitch, target.neckPitch),
                               headPitch: toward(from.headPitch, target.headPitch),
                               headYaw: toward(from.headYaw, target.headYaw),
                               headRoll: toward(from.headRoll, target.headRoll))
            sent = out
            return out
        }
    }

    /// Why a head pose travels beside a zero twist and never beside a live one.
    public static let stillWhilePosingTheHead =
        "While the sticks are posing the head they are not driving: the twist goes out as zero "
      + "in the same breath. That is the gamepad's own rule and the reason for it is the policy's "
      + "— the twist alone decides whether the robot is walking, so a head that moved the body "
      + "would be a duck that walked off because somebody looked around."

    /// What to say under the stick while it is posing a head.
    ///
    /// FOUR ANGLES IN DEGREES, BECAUSE NOBODY READS RADIANS OFF A STICK. The
    /// wire carries radians and this is the only place they are turned into
    /// anything else — a readout, never a command.
    public static func headSays(_ head: DuckHead) -> String {
        if head == .level { return "Head level — nothing commanded." }
        let d = { (r: Double) in r * 180 / Double.pi }
        return String(format: "neck %.0f°  pitch %.0f°  yaw %.0f°  roll %.0f°",
                      d(head.neckPitch), d(head.headPitch), d(head.headYaw), d(head.headRoll))
    }

    /// What to say under the stick about the command it is producing.
    ///
    /// PINNED HERE RATHER THAN COMPOSED IN THE VIEW because it makes claims
    /// about what the robot will do — the dead zone especially, which is the
    /// difference between "your bench is broken" and "the gait is working".
    public static func says(_ twist: Twist) -> String {
        if twist == .still { return "Centred — nothing commanded." }
        if twist.standsStill {
            return String(format: "%.2f m/s, %.2f rad/s — under the %.2f the gait "
                          + "needs, so the standing policy takes over and it stays put. "
                          + "That is the gait working, not a stall.",
                          twist.vx, twist.vyaw, deadZone)
        }
        var parts = [String(format: "%.2f m/s forward", twist.vx)]
        if twist.vy != 0 {
            parts.append(String(format: "%.2f m/s %@", abs(twist.vy),
                                twist.vy > 0 ? "left" : "right"))
        }
        parts.append(String(format: "%.2f rad/s turning", twist.vyaw))
        return parts.joined(separator: ", ") + "."
    }

    // MARK: - the calls

    /// Why a call could not be built.
    public enum Refusal: Error, Equatable {
        /// A hold that is not a number at all.
        case holdIsNotASecond(Double)

        public var message: String {
            switch self {
            case .holdIsNotASecond:
                return "That hold is not a number of seconds. A duration divided by zero, or a "
                     + "frame interval taken before the first frame, arrives here as NaN."
            }
        }
    }

    /// Hold a command for a moment and let physics run under it.
    ///
    /// THE CLAMP DOES NOT CATCH A NaN, WHICH IS THE WHOLE REASON FOR THE GUARD.
    /// `min(max(hold, 0.02), 2)` looks total and is not: `0.02 >= .nan` is
    /// false, so `max` returns the NaN, and `min` returns it again for the same
    /// reason. The NaN then reaches `JSONSerialization`, which on Darwin
    /// **raises an Objective-C exception Swift cannot catch** — so the failure
    /// is a dead app rather than a thrown error, and it arrives from a hold
    /// computed by dividing by a frame count that was zero on the first frame.
    /// Refusing here rather than at each caller's door is what makes the whole
    /// package safe instead of one path through it.
    public static func intent(_ address: DuckBench.Address, _ twist: Twist,
                              hold: Double = holdSeconds, duck: String? = nil) throws -> DuckBench.Call {
        // NaN ONLY, NOT `!isFinite`. An infinity clamps correctly —
        // `min(max(.infinity, 0.02), 2)` is 2 — and the bench is happy to be
        // told a thousand and bound it. Refusing everything out of range would
        // refuse what the bench itself accepts; refusing a NaN refuses the one
        // value the clamp lets through.
        guard !hold.isNaN else { throw Refusal.holdIsNotASecond(hold) }
        var body: [String: Any] = ["vx": twist.vx, "vy": twist.vy, "vyaw": twist.vyaw,
                                   "hold": min(max(hold, 0.02), 2)]
        // A NAMED DUCK, ON A BENCH WITH MORE THAN ONE. Absent means the first
        // duck, which is what every single-duck caller has always meant.
        if let duck { body["duck"] = duck }
        return DuckBench.Call(method: "POST",
                              url: URL(string: "\(address.base)/intent")!,
                              body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Zero the command and let the duck settle under it.
    ///
    /// NOT A RESET, and the bench is emphatic about the difference: "stopping
    /// is a thing the policy does, and a duck that had to be teleported upright
    /// to stop would be hiding the fall." If a policy cannot stop without
    /// falling over, that is a fact about the policy and this is how you find
    /// it out.
    public static func stop(_ address: DuckBench.Address,
                            settle: Double = 0.5, duck: String? = nil) throws -> DuckBench.Call {
        var body: [String: Any] = ["settle": min(max(settle, 0.02), 5)]
        if let duck { body["duck"] = duck }
        return DuckBench.Call(method: "POST",
                              url: URL(string: "\(address.base)/stop")!,
                              body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Swap which network is driving, without restarting the world.
    public static func load(_ address: DuckBench.Address,
                            policy: String, duck: String? = nil) throws -> DuckBench.Call {
        var body: [String: Any] = ["policy": policy]
        if let duck { body["duck"] = duck }
        return DuckBench.Call(method: "POST",
                              url: URL(string: "\(address.base)/policy")!,
                              body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Put the duck back where it started.
    public static func reset(_ address: DuckBench.Address, duck: String? = nil) throws -> DuckBench.Call {
        var body: [String: Any] = [:]
        if let duck { body["duck"] = duck }
        return DuckBench.Call(method: "POST",
                              url: URL(string: "\(address.base)/reset")!,
                              body: try JSONSerialization.data(withJSONObject: body))
    }

    // MARK: - what comes back

    /// The duck, right now.
    public struct Live: Equatable, Sendable {
        /// Sim seconds since the world started. NOT wall-clock: the bench says
        /// `clock: sim` about this for a reason, and a screen that printed it
        /// as elapsed real time would be lying by a factor nobody controls.
        public let t: Double
        public let stance: DuckStance
        public let height: Double
        public let upright: Bool
        /// Which network is driving, as the bench names it.
        public let policy: String?
        /// What the bench believes it was last told.
        public let command: Twist

        /// Where the ball is, now — the one other thing in this world that
        /// moves while you drive.
        ///
        /// NIL IS A REAL ANSWER AND NOT A FAILURE. A bench whose plant has no
        /// ball says `null` here and an older bench says nothing at all, so
        /// this is Optional and a stage that finds nil draws no ball rather
        /// than one at the origin. `DuckDrive.readLive` never invents a
        /// position; if the field is missing, the ball a screen last read from
        /// `/world` is the newest thing anybody knows.
        ///
        /// IT IS DEFAULTED IN THE INITIALIZER so every existing caller and
        /// fixture still compiles — there are a lot of them, and a required
        /// parameter would have meant touching each one to write `nil`.
        public let ball: DuckWorld.Point?
        /// The ball's radius in metres, as the bench reports it beside `ball`; nil when it says
        /// nothing. The head camera draws the ball this size (`DreamPracticeWorld.ball(in:)`).
        public let ballRadius: Double?

        public init(t: Double, stance: DuckStance, height: Double, upright: Bool,
                    policy: String?, command: Twist,
                    ball: DuckWorld.Point? = nil, ballRadius: Double? = nil) {
            self.t = t; self.stance = stance; self.height = height
            self.upright = upright; self.policy = policy; self.command = command
            self.ball = ball; self.ballRadius = ballRadius
        }
    }

    /// Read `/intent`, `/stop`, `/policy` or `/reset` — they all answer with
    /// the same state block.
    public static func readLive(_ data: Data) throws -> Live {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DuckBench.ReadError.notJSON
        }
        if let error = top["error"] as? String { throw DuckBench.ReadError.bench(error) }
        guard let joints = top["joints"] as? [Double],
              joints.count == DuckModel.policyJointCount,
              let position = top["position"] as? [Double], position.count >= 3,
              let quaternion = top["quaternion"] as? [Double], quaternion.count >= 4 else {
            throw DuckBench.ReadError.empty
        }
        // THE FOURTEEN POLICY JOINTS ARE NOT THE FIFTEEN A STANCE DRAWS. The
        // mouth is driven by no network — the bench does not report it and
        // could not — so it is filled from the home pose rather than left at
        // zero, which would draw the beak hanging open on every frame.
        var all = DuckModel.homePose
        for slot in 0..<DuckModel.policyJointCount {
            all[DuckModel.jointOfPolicySlot(slot)] = joints[slot]
        }
        let command = top["command"] as? [String: Any] ?? [:]
        return Live(
            t: top["t"] as? Double ?? 0,
            stance: DuckStance(jointAngles: all,
                               root: .init(x: position[0], y: position[1], z: position[2],
                                           quaternion: (quaternion[0], quaternion[1],
                                                        quaternion[2], quaternion[3]))),
            height: top["height"] as? Double ?? position[2],
            upright: top["upright"] as? Bool ?? false,
            policy: top["policy"] as? String,
            command: Twist(vx: command["vx"] as? Double ?? 0,
                           vy: command["vy"] as? Double ?? 0,
                           vyaw: command["vyaw"] as? Double ?? 0),
            // `[x, y, z]` FROM `/state`, AND NOTHING WHEN THE WORLD HAS NO
            // BALL. The bench sends JSON null there, which arrives as `NSNull`
            // and reads as nil — the same discipline `readHost` uses, and the
            // reason a screen can tell "no ball in this world" apart from "a
            // ball at the origin".
            ball: DuckBench.readPoint(top["ball"]),
            ballRadius: top["ballRadius"] as? Double)
    }

    /// What the screen has to admit about what it is driving.
    ///
    /// IT IS NOT A ROBOT, AND THE PERSON READING IT MAY BE HOPING IT IS. This
    /// is the one screen in the app where somebody's thumb moves and a duck
    /// moves, which is exactly the arrangement that reads as a robot being
    /// driven. Nobody has hardware until deliveries start, and this app has no
    /// robot transport at all.
    /// Why swapping the policy mid-drive means anything.
    ///
    /// THE WIDTH IS A FACT ABOUT THE ROBOT, so it is stated here and not in the
    /// view that prints it — the app-target gate caught it sitting in a
    /// `Text(...)`, correctly. `DuckObservation.length` is the number, and
    /// Pollen's own training repo gives the same one with its parts: 61 =
    /// 48 proprioception + commands [twist(3), head_pose(4), body_pose(6)],
    /// described there as the shared contract that "enables runtime policy
    /// hot-swapping". The hot swap is a designed property of the fleet, not a
    /// trick this bench happens to allow.
    public static var hotSwapWorksBecause: String {
        "Changing the policy swaps the network without restarting the world — the duck keeps "
      + "whatever pose it is in. Every Microduck policy reads the same "
      + "\(DuckObservation.length) numbers, which is what makes a hot swap mean anything: "
      + "48 about the robot's own body, the rest the command you are sending it."
    }

    /// What the app calls a thing, against what the ROBOT calls it.
    ///
    /// "INTENT" WAS TAKEN, AND NOT BY US — SO THE TAB GAVE IT BACK.
    ///
    /// The tab that holds recordings is called Motions now. In Pollen's
    /// contract an intent is the opposite of a recording: `robot.move`,
    /// `robot.head`, `robot.stop`, `robot.enable` — "what a client asks the
    /// robot to *do*". One word for opposite ends of the same pipeline gets
    /// worse with every screen, and THIS is the screen that genuinely sends
    /// intents, so it is the one that would have collided hardest.
    public static let intentMeansACommandHere =
        "Motions are recordings — what a network did. An intent is the other "
      + "direction: a command you send the robot. Pollen\'s are move, head, "
      + "look, stop, enable. Driving sends the first."

    public static let thisIsNotARobot =
        "You are driving MuJoCo on your bench, not a Microduck. The duck above is physics on "
      + "another machine on your network, running the same policy a real one would run.\n\n"
      + "This app has not driven a robot. It can find one over Bluetooth and ask it what it is, "
      + "and Pollen have a WebRTC path working on their own hardware that would carry these same "
      + "commands — but nothing here has spoken to a duck, and until something has, every number "
      + "on this screen came out of a simulator.\n\n"
      + "The commands are the real ones. Pollen\'s robot.move takes vx, vy and vyaw in the trunk "
      + "frame, and these sticks reach Pollen's own pad defaults: "
      + String(format: "%.1f m/s forward, %.1f m/s back and sideways, %.1f rad/s turning. ",
               Pad.forward, Pad.backward, Pad.turn)
      + "So a stick pushed half way here asks for what it would there.\n\n"
      + "One thing here is softer than a robot. This world only advances while a command is in "
      + "flight, so letting go stops it mid-stride. A real move expires instead, on a deadman "
      + "this does not need and hardware would."
}
