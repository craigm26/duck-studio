import Foundation
import DuckKit

/// The physics bench, answering the robot's own vocabulary.
///
/// WHAT THIS IS FOR. `DuckDrive` already knows how to drive `sim/duckbench.mjs`
/// — post a twist to `/intent`, post a settle to `/stop`, read the state block
/// that comes back — and every screen written against it was a screen written
/// against a bench. `DuckPeer` is the app's one vocabulary, transcribed from
/// `duck-ipc-proto`, and this is the adapter that lets the bench be spoken to in
/// it: a `DuckCall.move` in and a `POST /intent` out. Nothing about the bench
/// changes. What changes is that the screen above it stops being bench-shaped,
/// so the day a WebRTC peer or a bridge peer arrives, the driving code does not
/// have to be written a second time.
///
/// THE WORLD ONLY MOVES WHILE SOMETHING IS ASKING IT TO, AND THAT IS THE ONE
/// SAFETY PROPERTY THAT DOES NOT SURVIVE THE MOVE TO HARDWARE. The bench
/// advances physics inside a request and not otherwise — `DuckDrive`'s own
/// sentence is "miss the next intent and the duck is not still walking, it is
/// frozen mid-stride." So a dropped Wi-Fi link here cannot leave a duck walking
/// into a wall: the simulation simply stops between requests, for free, with
/// nothing armed and nothing to arm. A real Microduck is the other way round. A
/// `robot.move` there EXPIRES, on an age-based deadman — `safety.gate(command,
/// twist_age)` — which is the thing that actually stops an undriven duck, and
/// which a partition triggers rather than defeats. Anything learned about
/// letting go of the stick on this peer is therefore knowledge about a
/// simulator and not about a robot, and a driving loop that quietly relies on
/// the freeze is a loop that will keep a real duck walking until its deadman
/// fires. `theWorldOnlyMovesWhenAsked` is that paragraph in one sentence, for a
/// screen to print.
///
/// AN ACTOR, WHICH IS NOT THE SAME THING AS A SINGLE WRITER. Isolation keeps
/// this peer's own bookkeeping — the last state block, the id counter — safe
/// from two callers at once, and it is released at every `await`, so two
/// drivers sharing one `BenchPeer` still get their intents interleaved exactly
/// as `intents.rs` describes for the robot: one slot, last writer wins, "a
/// robot that obeys neither". The accepted fix there is a single-writer token,
/// which is a thing a duck hands out and therefore lives a layer above this
/// type. It is said here so that whoever wires two thumbs to one bench reads it
/// before finding it out.
///
/// IT TAKES AN ERRAND RATHER THAN A `URLSession`, for the reason `BenchSetup`
/// already gives about diagnosis: this package is tested on Linux with no phone
/// and no network worth the name, and a peer that reached for
/// `URLSession.shared` would be a peer whose refusals could only be checked by
/// hand on a device. The app target already owns its session and its bearer
/// token; what it hands here is one closure that turns a `DuckBench.Call` into
/// the bytes that came back.
public actor BenchPeer: DuckPeer {

    /// How this peer actually reaches the bench: a `DuckBench.Call` in, the
    /// answering bytes out. Whatever the caller does about timeouts,
    /// cancellation and the bearer token happens in here, where the app's own
    /// `URLSession` already lives.
    public typealias Errand = @Sendable (DuckBench.Call) async throws -> Data

    /// Which duck this is, and — the field that matters — whether it is real.
    ///
    /// `kind` IS NOT A PARAMETER, AND THAT IS THE ONE DECISION IN THIS TYPE
    /// THAT IS NOT NEGOTIABLE. Every other peer in this app could be pointed at
    /// either a robot or a simulator, which is why `DuckIdentity` carries the
    /// claim rather than inferring it from a transport. This peer cannot: what
    /// is on the other end of `/intent` is MuJoCo on somebody's machine, and
    /// there is no address anybody could type that would make it hardware. A
    /// constructor that accepted `.real` here would let one line of app code
    /// tell a person they were driving a robot.
    public nonisolated let identity: DuckIdentity

    /// Where the bench is, kept so a screen can show what it is pointed at
    /// without holding a second copy of the address.
    public nonisolated let address: DuckBench.Address

    /// What this link carries.
    ///
    /// IT IS THE ROUTING TABLE'S ANSWER, NOT A SECOND COPY OF IT. Writing the
    /// four methods out here would be a set that agrees with
    /// `DuckMethod.reach(for: .bench)` on the day it is written and drifts from
    /// it the first time somebody adds a method to the bench column. The tests
    /// assert the identity rather than the contents for the same reason.
    public nonisolated let transportKind = DuckTransportKind.bench
    public nonisolated let reach = DuckMethod.reach(for: .bench)

    /// The last state block a request came back with, whole.
    ///
    /// THIS IS WHAT `studio.state` IS READ FROM, and it is also how a view draws
    /// the duck. A `DuckReply` carries bytes, and fifteen joint angles plus a
    /// root quaternion are not something anybody reads back out with
    /// `field(_:)`; re-serialising them into the reply would be a second
    /// spelling of `DuckDrive.Live` for a drawing routine to parse again. So the
    /// reply carries the scalars a peer-shaped caller asks for, and the stance
    /// stays here in the type `DuckDrive.readLive` already returns.
    public private(set) var live: DuckDrive.Live?

    /// How much sim time one intent buys, seconds.
    ///
    /// `DuckDrive.holdSeconds` — five ticks at 50 Hz — unless the caller says
    /// otherwise. It is a parameter because the driving loop's pace is the
    /// caller's business: this peer is asked for an intent and does not own the
    /// clock that asks.
    ///
    /// `DuckDrive.intent` CLAMPS IT, AND THE CLAMP IS NOT A FINITENESS CHECK.
    /// `min(max(hold, 0.02), 2)` bounds every finite number into the window the
    /// bench accepts, and both infinities with them — measured, not assumed:
    /// `+.infinity` comes out 2 and `-.infinity` comes out 0.02. A NaN does
    /// not, because both halves are NaN-transparent in Swift: `0.02 >= .nan` is
    /// false, so `max(.nan, 0.02)` answers `.nan`, and `min` does the same. So
    /// the initialiser refuses a NaN rather than leaving it to a clamp that
    /// passes it through — see `Misuse.holdIsNotANumber`.
    private let hold: Double

    private let errand: Errand

    /// The id the next request will be stamped with.
    private var lastID = 0

    /// Point a peer at a bench.
    ///
    /// IT THROWS FOR ONE REASON, AND IT IS A CRASH RATHER THAN A WRONG NUMBER.
    /// A NaN `hold` survives `DuckDrive.intent`'s clamp, goes into the
    /// `/intent` body, and reaches `JSONSerialization` — which on Darwin raises
    /// rather than throws, the same fact `DuckCall.line`'s finiteness check
    /// exists for. Refusing here rather than at the send is deliberate: the
    /// twist arrives once per call and is checked once per call, whereas the
    /// hold arrives once, at construction, and this is the only door it comes
    /// in by. A peer that exists is then a peer that can be driven.
    public init(address: DuckBench.Address,
                name: String? = nil,
                colourway: DuckColourway = .teal,
                hold: Double = DuckDrive.holdSeconds,
                errand: @escaping Errand) throws {
        guard !hold.isNaN else { throw Misuse.holdIsNotANumber }
        self.address = address
        // THE NAME IS THE ADDRESS UNLESS SOMEBODY TYPED A BETTER ONE. `/health`
        // answers what SOFTWARE is running — "duck-bench" — which is the same
        // word for every bench on the desk, so a list of peers named from it
        // would be a list of identical rows. The host is at least the thing the
        // person typed and can find again.
        self.identity = DuckIdentity(name: name ?? address.host, colourway: colourway, kind: .sim)
        self.hold = hold
        self.errand = errand
    }

    /// Why a peer could not be built.
    ///
    /// SEPARATE FROM `Refusal` BECAUSE IT IS THE CALLER'S MISTAKE AND NOT THE
    /// BENCH'S LIMIT. Every case in `Refusal` is a fact about a simulator —
    /// something a real Microduck does that physics has no equivalent for — and
    /// a number that is not a number belongs with `DuckCall.Misuse`'s kind of
    /// error instead: the same name, because it is the same mistake one layer
    /// up.
    ///
    /// NO ASSOCIATED VALUE, AND THE REASON IS THE VALUE ITSELF. Carrying the
    /// offending `Double` would make this enum's `Equatable` conformance answer
    /// false for `.holdIsNotANumber(.nan) == .holdIsNotANumber(.nan)`, because
    /// no NaN equals any NaN — so the one case that can be thrown would be the
    /// one case nobody could assert on.
    public enum Misuse: Error, Equatable {

        /// The `hold` handed to `init` was a NaN.
        case holdIsNotANumber

        public var message: String {
            switch self {
            case .holdIsNotANumber:
                return "The hold this peer was built with is a NaN, and a NaN is not a length of "
                     + "time. It is refused at construction because nothing further down stops "
                     + "it: DuckDrive.intent clamps with min(max(hold, 0.02), 2), and both halves "
                     + "pass a NaN through — 0.02 >= .nan is false, so max answers .nan, and min "
                     + "answers .nan for the same reason — so it would go into the /intent body "
                     + "and reach JSONSerialization, which on Darwin raises rather than throws. "
                     + "That is a crash in somebody's hand instead of an error they can read. A "
                     + "hold that is merely out of range is not this: every finite number and "
                     + "both infinities come out of that clamp between 0.02 and 2 seconds."
            }
        }
    }

    // MARK: - what a bench cannot do, and why

    /// Why this bench refuses a call, or nil for the four it carries.
    ///
    /// A NAMED REASON RATHER THAN THE GENERIC DENIAL, WHICH IS THE WHOLE POINT
    /// OF THE TYPE. `DuckPeer.vet` already throws `Misuse.outOfReach`, and its
    /// sentence — "Bench does not carry robot.look" — is true and useless: it
    /// tells somebody staring at a dead control that a table said no, without
    /// saying what is missing on the other end. Each case below names the thing
    /// the bench genuinely does not have, because that is the difference
    /// between "this app is broken" and "you are driving physics".
    ///
    /// IT IS PUBLIC BECAUSE A SCREEN WANTS IT BEFORE THE TAP, not after. A view
    /// that greys out a head control has to say why beside it, and if the
    /// sentence were only thrown at call time the app would write a second
    /// version of it — which is exactly the duplication this package exists to
    /// prevent.
    ///
    /// EXHAUSTIVE OVER `DuckCall`, so a call added to the vocabulary must be
    /// given an answer here or this file stops compiling. Nil means carried,
    /// which is the only way to say "no refusal" without inventing a case for
    /// the four that work.
    public static func refusal(for call: DuckCall) -> Refusal? {
        switch call {
        case .head: return .noPlaceToPutAHeadPose(.head)
        case .look: return .noPlaceToPutAHeadPose(.look)
        case .enable: return .noMotorBus(.enable)
        case .relax: return .noMotorBus(.relax)
        case .initPose: return .resetIsNotTheInitialPose
        case .hello, .move, .stop, .state: return nil
        }
    }

    /// What a bench cannot do, in the bench's own terms.
    ///
    /// THESE ARE FACTS ABOUT A SIMULATOR, NOT COMPLAINTS ABOUT ONE. Every case
    /// here is something a real Microduck does and a physics server has no
    /// equivalent for, and a peer that quietly did nothing instead would leave
    /// somebody believing they had posed a head or powered a bus.
    public enum Refusal: Error, Equatable {

        /// `robot.head` or `robot.look`: four angles with no door to go in by.
        case noPlaceToPutAHeadPose(DuckMethod)

        /// `robot.enable` or `robot.relax`: there is no motor bus in physics.
        case noMotorBus(DuckMethod)

        /// `robot.init`. The bench has `/reset`, which is not the same thing.
        case resetIsNotTheInitialPose

        /// `studio.state` was asked before anything had been commanded.
        case nothingHasHappenedYet

        public var message: String {
            switch self {
            case .noPlaceToPutAHeadPose(let method):
                return "\(method.rawValue) asks for a head pose, and this bench has no door to "
                     + "put one through: /intent takes vx, vy, vyaw and a hold, and no other "
                     + "endpoint accepts an angle. Sending it anyway would put four numbers "
                     + "nowhere and report success. On a robot the head is deliberately kept "
                     + "apart from the twist — DuckKit's reason is that head motion must not "
                     + "make the robot think it is walking — so this gap is the bench's, and the "
                     + "call is a real one that will work over a transport that reaches robotd."
            case .noMotorBus(let method):
                return "\(method.rawValue) powers or unpowers a motor bus, and physics has "
                     + "neither. DuckPad says it in its own words: there is no power to cut and "
                     + "no motor bus to enable. A simulated duck that answered \"enabled\" would "
                     + "be teaching a habit that means something on hardware and nothing here."
            case .resetIsNotTheInitialPose:
                return "robot.init puts a robot into its initial pose. The nearest thing this "
                     + "bench has is /reset, which teleports the duck upright and starts the "
                     + "world again — and the bench is emphatic about the difference: stopping "
                     + "is a thing the policy does, and a duck that had to be teleported upright "
                     + "would be hiding the fall. Mapping one onto the other would report a pose "
                     + "where there was a collapse. /reset is still there, as DuckDrive.reset, "
                     + "and it is not this."
            case .nothingHasHappenedYet:
                return "This bench has nothing to report yet. Its world only advances inside a "
                     + "request, so the state here is whatever the last command came back with, "
                     + "and nothing has been commanded on this link. Ask it to move or to stop, "
                     + "then ask what happened. Nothing is fetched to answer this, because a "
                     + "read that advanced physics would be a measurement that changed what it "
                     + "was measuring."
            }
        }
    }

    /// The one sentence a driving screen owes somebody about this peer.
    ///
    /// IT IS HERE RATHER THAN IN A VIEW because it is a claim about what the
    /// robot does — the app-target gate is right to refuse a fact about a
    /// deadman sitting in a `Text(...)` — and because the same words have to be
    /// true of every screen that ends up driving a bench.
    ///
    /// IT IS ALSO SAID A SECOND TIME, IN `DuckDrive.thisIsNotARobot`, AND THAT
    /// IS THE PART THAT NEEDS FIXING IN THE OTHER FILE. Its third paragraph —
    /// "This world only advances while a command is in flight, so letting go
    /// stops it mid-stride. A real move expires instead, on a deadman this does
    /// not need and hardware would." — is this same claim in different words.
    /// Two public strings saying one thing can be edited apart, and `DriveView`
    /// prints `thisIsNotARobot` today, so a screen that adds this constant
    /// beside it says it twice.
    ///
    /// `DuckDrive` IS THE BETTER HOME, NOT THIS FILE, FOR A MECHANICAL REASON:
    /// this peer already depends on `DuckDrive`, so a constant there can be
    /// referenced from here, while the reverse would have the package's
    /// lowest-level bench calls reaching up into one of its peers. What is
    /// owed there, by whoever owns that file: lift the third paragraph out of
    /// `thisIsNotARobot` into a `public static let` of its own, give it this
    /// constant's stronger wording — which names the deadman as age-based,
    /// `safety.gate(command, twist_age)`, and says outright that letting go
    /// here is not a test of it, neither of which the paragraph says today —
    /// have `thisIsNotARobot` compose it as its third paragraph so `DriveView`
    /// keeps printing it unchanged, and then reduce this constant to that name.
    /// Until that lands, `BenchPeerTests` pins the two together so they cannot
    /// drift apart quietly.
    public static let theWorldOnlyMovesWhenAsked =
        "This world only advances while a request is in flight, so letting go leaves the duck "
      + "frozen mid-stride rather than walking. That is the simulator being kind: a real "
      + "robot.move expires instead, on an age-based deadman, which is what stops a duck whose "
      + "driver has gone away. Nothing you learn about letting go here is a test of that deadman."

    // MARK: - saying it

    /// Ask, and wait for the answer.
    ///
    /// THE ORDER OF THE TWO CHECKS IS DELIBERATE. The named refusal goes first,
    /// so that `robot.head` sent as a request gets told what a bench is missing
    /// rather than that it was sent the wrong way round — both are true, and
    /// only one of them is what the person needs. `vet` then runs anyway, so
    /// the direction half of the contract is the protocol's single copy of it
    /// rather than a rule this file re-implements.
    public func call(_ c: DuckCall) async throws -> DuckReply {
        if let refusal = Self.refusal(for: c) { throw refusal }
        try vet(c, asNotification: false)
        lastID += 1
        let id = lastID
        // THE LINE IS BUILT AND THROWN AWAY, ON PURPOSE — AND IT CHECKS NO
        // NUMBERS HERE, WHICH IS WHAT THIS COMMENT USED TO CLAIM IT DID. It
        // said the build was how "the package's single finiteness check gets
        // run" on the twist. It is not, not on this path: by the time this line
        // runs, `refusal(for:)` has thrown for head, look, enable, initPose and
        // relax, and `vet` has thrown for `move` as sent the wrong way round,
        // so the only calls that reach here are `hello`, `stop` and `state` —
        // none of which carries a number at all. The finiteness check that
        // matters is the identical build in `notify`, which is the one path a
        // twist travels, and the hold's is in `init` — see
        // `Misuse.holdIsNotANumber`. A comment claiming a guard that a NaN
        // never passes through is worse than no comment: it is the reason
        // somebody skips looking for the real one.
        //
        // WHAT THE BUILD STILL EARNS: every call this peer accepts is a call
        // that could have been written as a line, checked by the same builder
        // every other transport uses. When `refusal(for:)` shrinks — a bench
        // that grows a head endpoint — a twist-bearing call arrives here and is
        // already covered, rather than arriving at a path that never checked
        // anything.
        _ = try c.line(id: id)

        switch c {
        case .hello:
            return try await sayHello(id: id)
        case .stop:
            return try await advance(DuckDrive.stop(address), id: id)
        case .state:
            // READ FROM MEMORY, TOUCHING NOTHING. The bench has no state
            // endpoint, and the reason it does not is the same reason this
            // cannot invent one: every one of its endpoints advances physics to
            // answer, so a "read" would be a command.
            guard let live else { throw Refusal.nothingHasHappenedYet }
            return DuckReply(id: id, result: try Self.stateResult(live), failure: nil)
        case .move, .head, .look, .enable, .initPose, .relax:
            // UNREACHABLE, AND A THROW RATHER THAN A CRASH. `refusal(for:)`
            // has answered for five of these six — head, look, enable,
            // initPose, relax — and `vet` for the sixth, `move`, which is a
            // notification and so is refused as sent the wrong way round. So
            // nothing can arrive here today; the branch exists because the
            // switch is exhaustive with no `default`, which is what makes a
            // method added to `DuckCall` a compile error in this file. If it
            // ever does run, a refused call is a better failure than a
            // `fatalError` in somebody's hands.
            throw DuckCall.Misuse.outOfReach(c.method, .bench)
        }
    }

    /// Say, and do not wait — the continuous intent, and on this link only
    /// `robot.move`.
    ///
    /// "DO NOT WAIT" IS THE CONTRACT'S WORD AND NOT THIS TRANSPORT'S. A robot
    /// takes a notification and never answers it; the bench answers every
    /// request, because answering is how it reports the physics it just ran. So
    /// this awaits a round trip, keeps the state block out of it, and discards
    /// the rest — the caller still gets the notification's shape, which is what
    /// keeps a driving loop written here valid against a peer that really does
    /// not reply.
    public func notify(_ c: DuckCall) async throws {
        if let refusal = Self.refusal(for: c) { throw refusal }
        try vet(c, asNotification: true)
        _ = try c.line(id: nil)
        guard case .move(let twist) = c else {
            // Unreachable for the same reason as the branch in `call`, and by
            // the same two checks: `move` is the only notification this link
            // carries, `refusal(for:)` has answered the other continuous intent
            // — `head` — and `vet` has refused every request sent this way
            // round.
            throw DuckCall.Misuse.outOfReach(c.method, .bench)
        }
        let answer = try await advance(DuckDrive.intent(address, twist, hold: hold), id: nil)
        if let failure = answer.failure {
            // A NOTIFICATION HAS NOWHERE TO CARRY A REFUSAL, so this is the one
            // place a bench saying no becomes a thrown error rather than an
            // answer. The sentence is `DuckBench.ReadError`'s own, which is what
            // the drive screen already prints when `/intent` is refused.
            throw DuckBench.ReadError.bench(failure.message)
        }
    }

    // MARK: - the bench, underneath

    /// Post something that advances the world, and keep what came back.
    ///
    /// A BENCH THAT SAYS NO HAS ANSWERED, so its refusal is carried in the reply
    /// rather than thrown — the distinction `DuckReply` exists for, where a
    /// thrown error would make "unknown policy" look like a network fault. The
    /// code is 0 because the bench sends none, and 0 is already what
    /// `DuckReply.decode` records for a JSON-RPC refusal that omitted its code:
    /// choosing a real one out of Pollen's range would be inventing a number
    /// with a meaning attached.
    private func advance(_ call: DuckBench.Call, id: Int?) async throws -> DuckReply {
        let answered = try await errand(call)
        do {
            let state = try DuckDrive.readLive(answered)
            live = state
            // ONE SYNTHESISED STATE PER ROUND TRIP, AND NOT ONE MORE. The
            // bench's world only advances inside a request, so this is the only
            // moment at which anything about the duck can have changed; a timer
            // publishing between requests would be republishing the same
            // physics with a fresh timestamp, which is a stream that reports a
            // frozen duck as a live one.
            fan.publish(Self.synthesised(from: state, receivedAt: Date()))
            return DuckReply(id: id, result: try Self.stateResult(state), failure: nil)
        } catch DuckBench.ReadError.bench(let said) {
            return DuckReply(id: id, result: nil,
                             failure: DuckReply.Failure(code: benchSaidNoCode, message: said))
        }
    }

    /// Ask the bench who it is.
    ///
    /// `hello` MAPS ONTO `/health` BECAUSE THEY ASK THE SAME QUESTION — who is
    /// on the other end, and can we understand each other — and the answers are
    /// genuinely different things. A robot answers with `api_version`, and this
    /// deliberately does not: a bench has never heard of `duck-ipc-proto`, so a
    /// fabricated 16 in this result would make `DuckLink.verdict(for:)` print
    /// "the same one this app was written against" about a program that
    /// implements none of it. What a bench can honestly say is which software
    /// it runs, which world it runs, at what rate, and how many policies it
    /// holds — so that is what comes back, and a caller that wanted a version
    /// finds its absence rather than a number nobody measured.
    private func sayHello(id: Int) async throws -> DuckReply {
        let answered = try await errand(DuckBench.health(address))
        do {
            let health = try DuckBench.readHealth(answered)
            var result: [String: Any] = ["bench": health.bench,
                                         "plant": health.plant,
                                         "tickHz": health.tickHz,
                                         "policies": health.policies.count]
            // OPTIONAL BECAUSE A BENCH OLDER THAN THESE FIELDS IS SILENT RATHER
            // THAN WRONG, and `DuckBench.plantSaid` already has the three
            // sentences for what a missing world means. An empty string here
            // would be a name.
            if let name = health.plantName { result["plantName"] = name }
            if let digest = health.plantDigest { result["plantDigest"] = digest }
            return DuckReply(id: id,
                             result: try JSONSerialization.data(withJSONObject: result,
                                                                options: [.sortedKeys]),
                             failure: nil)
        } catch DuckBench.ReadError.bench(let said) {
            return DuckReply(id: id, result: nil,
                             failure: DuckReply.Failure(code: benchSaidNoCode, message: said))
        }
    }

    /// The code on a refusal the bench sent no code with. See `advance`.
    private let benchSaidNoCode = 0

    // MARK: - the state stream, and what a bench can honestly put in one

    private nonisolated let fan = DuckStateFanOut()

    /// One `DuckState` per round trip. See `benchStateIsSynthesised`.
    ///
    /// NOTHING ARRIVES BETWEEN REQUESTS, WHICH IS THE SHAPE OF THIS PEER RATHER
    /// THAN A LIMITATION OF THIS STREAM. A real duck pushes `robot.state` at the
    /// loop rate whether or not anybody is driving; a bench has nothing to say
    /// until something asks it to advance physics. So a screen holding this
    /// stream and no driving loop sees nothing at all, correctly — and
    /// `DeviceCard.Presence` is where the sentence for that lives, because a
    /// silent stream and a dead link look the same from here.
    public nonisolated func states() -> AsyncStream<DuckState> { fan.states() }

    /// The sentence that must be shown wherever one of these states is.
    ///
    /// A ROBOT'S STATE IS A MEASUREMENT AND THIS IS A TRANSLATION. `robot.state`
    /// is telemetry a daemon assembles from sensors it owns; this is one state
    /// block from `/intent` rearranged into the same struct, so anything the
    /// bench does not measure is nil rather than plausible. That is not a
    /// disclaimer about accuracy — the geometry is right — it is a statement
    /// about which fields exist at all. A screen that showed one of these beside
    /// a hardware one without this sentence would be inviting the comparison
    /// `DuckMeasurement.compare` refuses outright.
    public static let benchStateIsSynthesised =
        "This state was assembled by the app from a bench's reply, not reported by a robot. The "
      + "bench answers /intent with a pose and a height, and everything a robot's own state "
      + "carries that physics cannot measure is left empty rather than filled in: no battery, "
      + "because there is no cell; no torque reading, because there are no servos to be limp; no "
      + "loop rate or missed deadlines, because the world advances inside a request instead of on "
      + "a control loop. What is here is the fall — upright, inverted — and the twist the bench "
      + "believes it was last told."

    /// A bench's reply, as the state struct a robot fills in, with every field
    /// a bench cannot measure left nil.
    ///
    /// FIELD BY FIELD, AND EACH ABSENCE IS AN ARGUMENT:
    ///
    /// `safety.fallen` is `!upright`, which is the one honest translation in
    /// here — the bench reports whether the trunk is upright and a fall is
    /// exactly its negation. `safety.limp` is nil: torque off is a servo state,
    /// and a position-servo approximation has nothing that can go slack.
    ///
    /// `battery` is nil, and it is nil the way `DuckBattery` is nil — a
    /// percentage for a simulation is not approximate, it is INVENTED.
    ///
    /// `loop` is nil. `/health` reports a tick rate for the WORLD, which is not
    /// the robot's control loop, and `missed` is a count of deadlines a bench
    /// has no deadlines to miss. Putting the world's 50 in `loop.hz` would make
    /// a simulator look like a robot whose loop is keeping up.
    ///
    /// `odom` is nil, AND THIS IS THE ONE SOMEBODY WILL WANT TO FILL. The bench
    /// answers with the duck's true position, which is more than a robot knows:
    /// odometry is dead reckoning, and `DuckState.Odometry`'s own note is that
    /// it drifts and that nobody has measured how much. Ground truth in an
    /// odometry field would make a drift-free simulator read as a
    /// perfectly-calibrated robot, which is the single most flattering lie this
    /// file could tell.
    ///
    /// `move.requested` is the twist, because that is precisely what the bench
    /// reports — `DuckDrive.readLive` reads it out of the answer's `command`
    /// member, which is what the bench believes it was last TOLD. `applied` is
    /// nil for the same reason: nothing here measures what the policy did with
    /// it, and the gap between the two is the interesting part.
    ///
    /// `policy` travels, because the bench names the network it is running and
    /// that is the same string a robot's state carries.
    ///
    /// `receivedAt` IS A PARAMETER, NOT A `Date()` IN HERE. This package does
    /// not read clocks where a test would have to race one, and the bench's own
    /// `t` cannot stand in: it is sim seconds, `clock: sim`, and a screen that
    /// treated it as elapsed real time would be wrong by a factor nobody
    /// controls.
    public static func synthesised(from live: DuckDrive.Live, receivedAt: Date) -> DuckState {
        DuckState(
            policy: live.policy,
            safety: DuckState.Safety(fallen: !live.upright, limp: nil),
            loop: nil,
            battery: nil,
            odom: nil,
            move: DuckState.Move(requested: [live.command.vx, live.command.vy,
                                             live.command.vyaw],
                                 applied: nil, limitedBy: nil),
            receivedAt: receivedAt)
    }

    /// The state block, as the members a `DuckReply` caller can read back.
    ///
    /// `clock` IS IN HERE BECAUSE `t` IS NOT WALL TIME. The bench says
    /// `clock: sim` about it, `DuckDrive.Live` repeats the warning, and a screen
    /// that printed these seconds as elapsed real time would be wrong by a
    /// factor nobody controls — so the reply carries the warning next to the
    /// number rather than trusting the reader to remember it.
    ///
    /// The three velocities are what the bench believes it was last TOLD, not a
    /// measurement of what the duck did. `DuckDrive.readLive` reads them out of
    /// the answer's `command` member; nothing here computes them.
    private static func stateResult(_ live: DuckDrive.Live) throws -> Data {
        var result: [String: Any] = ["t": live.t,
                                     "clock": "sim",
                                     "height": live.height,
                                     "upright": live.upright,
                                     "vx": live.command.vx,
                                     "vy": live.command.vy,
                                     "vyaw": live.command.vyaw]
        if let policy = live.policy { result["policy"] = policy }
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }
}
