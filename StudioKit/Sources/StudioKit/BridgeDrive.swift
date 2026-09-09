import Foundation

/// Driving a real duck over the bridge: how fast to send, what stops it, and
/// what this app must not draw while it does.
///
/// THE THREE DEADMEN, IN ORDER, BECAUSE THEY ARE NOT ALTERNATIVES. A robot
/// walking under this app is held up by three separate timers and each one
/// covers a failure the others cannot:
///
/// 1. **robotd's own**, `safety.deadman_ms`, default **500 ms**
///    (`robotd-params/src/lib.rs`, `deadman_ms: 500`; read at
///    `robotd/src/main.rs` as `Duration::from_millis(params.safety.deadman_ms)`
///    and applied as `safety.gate(command, twist_age)`). It is AGE-BASED on the
///    last twist, which is why a network partition triggers it rather than
///    defeating it. It is the only one still standing if everything else on the
///    robot's computer dies.
/// 2. **the bridge's**, `--deadman`, default **700 ms**, which sends
///    `robot.stop` once after that much client silence and re-arms on any byte.
///    It covers the case robotd's cannot see as different from a slow driver:
///    an app that stopped driving but left the socket open.
/// 3. **this loop's**, which is not a timer at all — it is the obligation to
///    keep sending. A driving loop that pauses longer than either number above
///    has already handed the duck to a deadman, and the person holding the
///    phone will read that as the app dropping their command.
///
/// SO THE CADENCE IS DERIVED FROM THE SMALLEST OF THEM AND NOT PICKED. See
/// `interval(bridgeDeadmanMilliseconds:)`. `padd` — Pollen's own gamepad daemon,
/// the closest thing to a reference driver — runs its loop at 50 Hz with a
/// 100 ms heartbeat, so the shape of the answer here is the same shape.
///
/// AND THE BENCH TAUGHT THE OPPOSITE HABIT, WHICH IS WHY THIS FILE SAYS SO.
/// `BenchPeer.theWorldOnlyMovesWhenAsked` is the standing warning: a bench
/// advances physics inside a request and freezes between them, so letting go of
/// the stick there stops the duck for free. Nothing learnt about letting go on
/// a bench is knowledge about a robot. On this link, letting go means the
/// twist stales out and a deadman fires — which is a stop, but a stop that
/// arrives up to half a second late.
public enum BridgeDrive {

    // MARK: - the numbers

    /// robotd's own twist deadman, seconds. Transcribed from
    /// `robotd-params`' default of 500 ms.
    ///
    /// A CONSTANT AND NOT A READING. Nothing in this app asks a robot what its
    /// deadman is set to — `robot.health` is not in this vocabulary — so this is
    /// the SHIPPED DEFAULT and a robot configured differently is not described
    /// by it. It is used only to make this app's own cadence safe by a margin,
    /// never to promise a person a number, which is why the sentence a screen
    /// prints (`deadmanChainSaid`) names the bridge's reported value and calls
    /// this one the default it is.
    public static let robotdDeadmanSeconds: TimeInterval = 0.5

    /// The bridge's shipped default, seconds — `DEFAULT_DEADMAN_MS = 700` in
    /// `bridge/microduck-bridge.py`. Used only when a bridge did not say.
    public static let bridgeDeadmanSecondsDefault: TimeInterval = 0.7

    /// How often this app wants to send a twist, hertz.
    ///
    /// TWENTY, THE BOTTOM OF THE CONTRACT'S OWN RANGE. `duck-ipc-proto` sends
    /// the continuous intents "at 20–50 Hz"; `padd` sits at the top of it
    /// because it is a native daemon on the robot's own machine with a wire
    /// that cannot congest. This is a phone, over Wi-Fi, through a relay, and
    /// every frame it sends is one the send slot may have to supersede — so the
    /// bottom of the range is the honest place to start, and it is still ten
    /// times faster than the fastest deadman needs.
    public static let cadenceHz: Double = 20

    /// How many sends must fit inside the shortest deadman before this app
    /// considers itself safe. THREE, so two frames can be lost in a row and the
    /// duck still never sees a stale twist.
    public static let framesPerDeadman: Double = 3

    /// Seconds between twists, given what this particular bridge said about
    /// itself.
    ///
    /// THE SLOWER OF TWO ANSWERS, WHICH IS THE POINT. The preferred cadence is
    /// `cadenceHz`; the ceiling is a third of the shortest deadman in the
    /// chain. Normally the preference wins by a wide margin — 50 ms against a
    /// 167 ms ceiling — and the ceiling only bites if somebody runs a bridge
    /// with `--deadman 100`, in which case this app speeds up rather than
    /// letting a deadman fire under a hand that is still driving.
    ///
    /// A BRIDGE THAT DID NOT SAY IS TREATED AS THE SHIPPED DEFAULT and not as
    /// "no deadman". The optimistic reading of silence is the one that gets a
    /// duck stopped mid-stride by a bridge this app decided to ignore.
    public static func interval(bridgeDeadmanMilliseconds: Int?) -> TimeInterval {
        let bridge = bridgeDeadmanMilliseconds.map { Double($0) / 1000 }
            ?? bridgeDeadmanSecondsDefault
        let shortest = min(max(bridge, 0.001), robotdDeadmanSeconds)
        return min(1 / cadenceHz, shortest / framesPerDeadman)
    }

    /// The cadence as a rate, for a readout that wants to say "20 Hz".
    public static func hz(bridgeDeadmanMilliseconds: Int?) -> Double {
        1 / interval(bridgeDeadmanMilliseconds: bridgeDeadmanMilliseconds)
    }

    // MARK: - what a screen may say

    /// The three-timer chain, named with the bridge's own reported number.
    public static func deadmanChainSaid(bridgeDeadmanMilliseconds: Int?) -> String {
        let cadence = String(format: "%.0f", hz(bridgeDeadmanMilliseconds: bridgeDeadmanMilliseconds))
        let bridgePart: String
        if let bridgeDeadmanMilliseconds {
            bridgePart = "the bridge sends a stop after \(bridgeDeadmanMilliseconds) ms of "
                       + "silence from this app"
        } else {
            bridgePart = "this bridge did not say what its own deadman is, so this app assumes "
                       + "the shipped 700 ms rather than assuming none"
        }
        return "Driving sends a twist \(cadence) times a second. If it stops, two things stop the "
             + "duck: \(bridgePart), and robotd zeroes a twist that is older than its own deadman "
             + "— 500 ms as shipped — which is the one that still works if the bridge is what "
             + "died."
    }

    /// What the Control tab is NOT drawing on this link, said where the picture
    /// would have been.
    ///
    /// THE ABSENCE HAS TO BE EXPLAINED OR IT READS AS A BUG. Every other venue
    /// on this tab draws a duck; this one draws none, and the reason is not
    /// that hardware is hard — it is that `robot.state` carries fifteen
    /// measured joint angles which this app's `DuckState` does not decode, so
    /// there is nothing to pose a drawing from. Drawing the home stance instead
    /// would be a picture of a duck standing still while the real one walks,
    /// which is the worst possible thing for a screen whose entire subject is
    /// what the robot is doing.
    public static let noPictureHere =
        "There is no duck drawn here, and that is deliberate. The picture on the other venues is "
      + "posed from fifteen joint angles the bench sends back with every command; a real robot "
      + "sends its own, and this app does not read them yet. A drawing that was not the robot's "
      + "pose would be a duck standing still on the screen while the real one walks."

    /// Why the world picker, the scene editor and the Reset button are not
    /// here.
    public static let noWorldNoScene =
        "No world, no scene and no Reset on this link. Those are the bench's: a world is a box a "
      + "simulator can be told to build, and Reset teleports a duck upright, which is not "
      + "something a robot on your floor can be asked to do. What is here is the room the robot "
      + "is actually in, which nothing in this app can see."

    /// Why the face buttons do not swap a network here.
    public static let noPolicySwapHere =
        "The face buttons do not load a network on this link. Loading one into a slot is the "
      + "bench's POST /policy; on a robot, robotd owns its slots and names them once when this "
      + "app subscribes. Putting a file on the robot's disk is a different door — Robot, Bridge, "
      + "Install a policy — and it takes effect when robotd next starts."

    /// The one thing about a robot that this app cannot enforce.
    ///
    /// LAST-WRITER-WINS IS A PROPERTY OF THE ROBOT, NOT OF THIS LINK.
    /// `intents.rs` keeps one command slot, so two clients pushing twists
    /// "interleave into one slot, producing a robot that obeys neither". The
    /// accepted fix is a single-writer token, and `duck-ipc-proto` has no
    /// method to claim one — so the only honest thing to do is say it.
    public static let oneWriterOnly =
        "One driver at a time. The robot keeps a single command slot and takes the newest twist "
      + "that arrives, so a gamepad paired to the duck, a browser on its own console and this app "
      + "all driving at once produce a robot that obeys none of them. Nothing on either end "
      + "enforces that — there is no method to claim the robot — so it is worth knowing rather "
      + "than being surprised by."

    /// The line above the sticks on a real robot, which is not the line above
    /// the sticks on a bench.
    public static let theseCommandsAreReal =
        "These sticks move a robot in a room. There is no reset here and nothing catches it: what "
      + "leaves this screen is robot.move, at the same speeds a gamepad would send, and the duck "
      + "walks until you stop or let go."

    /// A link that was asked to talk and has not yet said anything.
    ///
    /// A DIFFERENT SENTENCE FROM `DuckSubscription.notAskedYet`, and the
    /// difference is the whole diagnosis. "Not asked" is this app not having
    /// sent `robot.subscribe`; this is the robot having accepted one and
    /// published nothing, which is a specific, findable fault — a daemon whose
    /// loop is not running, or a schema this build cannot decode. Printing one
    /// sentence for both would collapse the two states a person needs told
    /// apart into a single shrug.
    public static let subscribedButSilent =
        "Subscribed, and nothing has arrived yet. States are pushed at the loop rate, so one "
      + "should land within a tick or two; a link that stays empty means the robot accepted the "
      + "subscription and is publishing nothing, which is worth looking at on the robot rather "
      + "than here."

    /// The door from the screen that opens the link to the screen that uses it.
    ///
    /// A PERSON WHO HAS JUST CONNECTED A ROBOT IS ONE TAP FROM DRIVING IT, and
    /// the alternative — find the Control tab, notice it has a venue switch,
    /// switch it to Robot — is a route nobody would guess from here.
    public static let driveOnControl =
        "This link is what the Control tab drives. Switch that tab to Robot and the sticks send "
      + "robot.move down this connection."

    /// What Disconnect actually costs, said on the button's own row.
    public static let disconnectEndsDriving =
        "There is one link, so disconnecting here ends driving on the Control tab as well. The "
      + "robot stops: the bridge sends robot.stop when this app goes quiet, and robotd zeroes a "
      + "twist older than its own deadman."

    // MARK: - the headings on the venue's own list

    /// THE FOUR SECTION HEADINGS, IN THE KIT LIKE EVERY OTHER WORD ON THIS
    /// SCREEN. `scripts/check_stage_sentences.sh` is why they are here rather
    /// than typed into the view, and its argument holds for a heading exactly
    /// as it does for a paragraph: "What is not here" is a promise about the
    /// section under it, and a promise nothing can read is a promise that goes
    /// on being made after it stops being true.
    public static let drivingHeading = "Driving a robot"
    public static let runningHeading = "What it is running"
    public static let sticksHeading = "The sticks"
    public static let absencesHeading = "What is not here"
    /// The toggle that turns the sticks into a head. NAMED FOR WHAT IT DOES TO
    /// THE STICKS, not for the joint: somebody who flips it and then pushes
    /// forward has to already know the duck will not walk.
    public static let headModeLabel = "Sticks pose the head"

    /// What a person has to do before any of this works.
    public static let connectFirst =
        "Connect to the bridge on the robot's own machine first — Robot, then Bridge — and this "
      + "tab drives whatever that link reaches. Nothing here dials anything by itself."
}
