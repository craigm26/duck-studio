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
    // EVERY NUMBER BELOW IS POLLEN'S, out of `padd/src/main.rs` in
    // pollen-robotics/microduck — the daemon that drives a real Microduck from
    // a gamepad. They are its clap defaults, and they are here rather than
    // invented because somebody who has driven the robot with a pad already has
    // muscle memory for exactly these, and a phone that felt different at the
    // same stick deflection would be teaching a second set of reflexes for one
    // robot. Where a number here disagrees with one measured on the bench, the
    // comment says so rather than quietly picking a winner.

    /// The fastest forward this offers, metres per second — `padd`'s
    /// `--max-linear` default.
    ///
    /// THE BENCH HAS RUN BOTH THIS AND FASTER. `alpha_walking` covers 0.681 m
    /// in six seconds at vx = 0.3 and 1.207 m at 0.5, so 0.3 is comfortably a
    /// walk rather than the 7 mm shuffle vx = 0.15 produces. Pollen drives the
    /// real robot at 0.3 and this follows them: the faster figure is a thing
    /// the bench has measured, not a speed anybody has driven a duck at.
    public static let maxForward = 0.3

    /// Backwards, same figure — `padd`'s `--max-linear-backward`. Their roller
    /// mode deliberately pushes harder than it brakes (0.6 against 0.5); the
    /// walking mode does not, and neither does this.
    public static let maxBackward = 0.3

    /// Strafing, m/s. `padd` scales `vy` by the same `--max-linear`.
    public static let maxSideways = 0.3

    /// Turning, rad/s — `padd`'s `--max-angular` default.
    ///
    /// FIVE TIMES THE FIRST GUESS MADE HERE, which was 0.5 for no reason except
    /// symmetry with the forward figure. Turning and walking are not the same
    /// units and do not share a range; a duck limited to 0.5 rad/s would have
    /// felt sluggish and wrong to anybody who had used the real pad.
    public static let maxTurn = 1.5

    /// Stick deflection below which the axis reads as centred — `padd`'s
    /// `--deadzone` default, applied per axis exactly as it does.
    ///
    /// THIS IS NOT `deadZone` BELOW. That one is the gait's, in twist units,
    /// and it is about what the ROBOT does with a small command. This one is
    /// the stick's, in stick units, and it is about a thumb that cannot hold
    /// still. Both exist; conflating them would put the wrong number in the
    /// wrong place.
    public static let stickDeadzone = 0.1

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
        return Twist(vx: leftY * (leftY >= 0 ? maxForward : maxBackward),
                     vy: -leftX * maxSideways,
                     vyaw: -rightX * maxTurn)
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

    /// Hold a command for a moment and let physics run under it.
    public static func intent(_ address: DuckBench.Address, _ twist: Twist,
                              hold: Double = holdSeconds) throws -> DuckBench.Call {
        let body: [String: Any] = ["vx": twist.vx, "vy": twist.vy, "vyaw": twist.vyaw,
                                   "hold": min(max(hold, 0.02), 2)]
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
                            settle: Double = 0.5) throws -> DuckBench.Call {
        let body: [String: Any] = ["settle": min(max(settle, 0.02), 5)]
        return DuckBench.Call(method: "POST",
                              url: URL(string: "\(address.base)/stop")!,
                              body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Swap which network is driving, without restarting the world.
    public static func load(_ address: DuckBench.Address,
                            policy: String) throws -> DuckBench.Call {
        let body: [String: Any] = ["policy": policy]
        return DuckBench.Call(method: "POST",
                              url: URL(string: "\(address.base)/policy")!,
                              body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Put the duck back where it started.
    public static func reset(_ address: DuckBench.Address) throws -> DuckBench.Call {
        DuckBench.Call(method: "POST",
                       url: URL(string: "\(address.base)/reset")!,
                       body: try JSONSerialization.data(withJSONObject: [String: Any]()))
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

        public init(t: Double, stance: DuckStance, height: Double, upright: Bool,
                    policy: String?, command: Twist) {
            self.t = t; self.stance = stance; self.height = height
            self.upright = upright; self.policy = policy; self.command = command
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
                           vyaw: command["vyaw"] as? Double ?? 0))
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
    /// "INTENT" IS ALREADY TAKEN, AND NOT BY US. This app's Intents tab holds
    /// recordings — what a network did, played back. In Pollen's contract an
    /// intent is the opposite: `robot.move`, `robot.head`, `robot.stop`,
    /// `robot.enable` — "what a client asks the robot to *do*". So the screen
    /// that drives is closer to their meaning than the tab that borrows the
    /// word. Nothing here renames anything; it is written down so that when the
    /// two vocabularies meet, somebody knows they were always different.
    public static let intentMeansSomethingElseOnTheRobot =
        "The Intents tab holds recordings — what a network did. On the robot, "
      + "an \"intent\" is a command you send it: move, head, stop, enable. Driving "
      + "is the second kind."

    public static let thisIsNotARobot =
        "You are driving MuJoCo on your bench, not a Microduck. This app cannot reach a robot at "
      + "all: robotd speaks JSON-RPC over a Unix socket on the robot itself, and there is no "
      + "network endpoint for a phone to open. The duck above is physics on another machine on "
      + "your network, running the same policy a real one would run.\n\n"
      + "The commands are the real ones. Pollen\'s robot.move takes vx, vy and vyaw in the trunk "
      + "frame, and the speeds these sticks reach are padd\'s own defaults — 0.3 m/s and "
      + "1.5 rad/s — so a stick pushed half way here asks for what it would ask for there.\n\n"
      + "One thing here is softer than a robot. This world only advances while a command is in "
      + "flight, so letting go stops it mid-stride. A real move expires instead, on a deadman "
      + "this does not need and hardware would."
}
