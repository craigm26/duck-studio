import Foundation
import DuckKit

// MARK: - the vocabulary

/// Every word this app can say to a duck, and the one place the wire spelling
/// of each is written down.
///
/// THE APP CURRENTLY SPEAKS TWO UNRELATED DIALECTS, AND THAT IS THE PROBLEM
/// THIS FILE EXISTS FOR. `DuckDrive` posts `/intent` and `/policy` to a physics
/// bench over HTTP; `DuckLink` writes `hello` as JSON-RPC over a BLE
/// characteristic. They are the same three ideas — say who you are, send a
/// twist, stop — expressed twice, so a screen written against the bench is a
/// screen that has to be written again against a robot, and nothing a person
/// learns driving the simulator is knowledge about driving hardware. Pollen's
/// own architecture note is "one API definition, many transports"
/// (`architecture.md` §4.1 names four of them: BLE, unix socket, WebSocket,
/// WebRTC). This is that one definition on the app's side of the wire.
///
/// THE RAW VALUES ARE THE WIRE NAMES, so a grep for `robot.move` finds this
/// enum and nothing else in the app has to know how the method is spelled.
/// They are transcribed from `duck-ipc-proto/src/lib.rs` — not from a summary
/// of it — for the reason `DuckLink` already paid for once: a name copied from
/// a web mirror produces a call the robot refuses by name, and a refusal by
/// name looks exactly like a feature the robot does not have.
///
/// TWO ENTRIES HERE ARE NOT CALLS THIS APP CAN MAKE, AND THEY ARE HERE ANYWAY.
/// `system.pairingPin`, `system.setPairingPin` and the `update.` family are in
/// the vocabulary because `reach(for:)` has to make a decision about them —
/// specifically the decision to carry them on Bluetooth and nowhere else. A
/// method that is not in this enum is a method no routing table can deny, and
/// the whole point of the table is that every method has been thought about
/// once, in writing.
public enum DuckMethod: String, CaseIterable, Sendable {

    /// Who are you. The only call in this vocabulary that every transport
    /// carries, and the only one this app has ever actually sent.
    case hello = "hello"

    /// A velocity twist, in the trunk frame. A CONTINUOUS intent: sent as a
    /// notification at 20–50 Hz, last-writer-wins, and it EXPIRES.
    case move = "robot.move"

    /// A head pose, four angles in radians. Continuous, like `move`.
    case head = "robot.head"

    /// Point the head somewhere and answer when it is done. Discrete.
    case look = "robot.look"

    /// Zero the command. Discrete, because the caller needs to know it landed.
    case stop = "robot.stop"

    /// Power the motor bus. Discrete.
    case enable = "robot.enable"

    /// Go to the initial pose. Discrete.
    ///
    /// SPELLED `initPose` IN SWIFT BECAUSE `init` IS A KEYWORD, and a
    /// backticked case name would put backticks in every call site in the app.
    /// The wire name is unchanged; the raw value is what travels.
    case initPose = "robot.init"

    /// Let the joints go slack. Discrete.
    case relax = "robot.relax"

    /// What is the duck doing right now.
    ///
    /// THIS ONE IS OURS AND THE PREFIX SAYS SO. `duck-ipc-proto` has no state
    /// method: a robot's state arrives as telemetry rather than by being asked,
    /// and `robotd` never offered a way to ask. The bench does — every one of
    /// its endpoints answers with the same state block, which is what
    /// `DuckDrive.readLive` reads — and so will a studio-to-studio bridge,
    /// because a phone showing another phone's duck has nothing else to show.
    /// It is namespaced `studio.` rather than `robot.` so that nobody reading a
    /// packet capture, or grepping this repo, can mistake it for a method
    /// Pollen defined. `reach(for:)` accordingly denies it on both of the
    /// transports a real `robotd` answers.
    case state = "studio.state"

    /// Read the pairing PIN. BLUETOOTH ONLY — see `mutatesTheRecoveryPath`.
    case pairingPin = "system.pairingPin"

    /// Rewrite the pairing PIN. BLUETOOTH ONLY.
    case setPairingPin = "system.setPairingPin"

    /// The whole `update.` family, as a family.
    ///
    /// THE RAW VALUE IS A GLOB, NOT A METHOD, AND THAT IS ON PURPOSE. The
    /// contract names `update.*` without this app having transcribed the
    /// individual method names, so writing one here would be inventing it.
    /// `update.*` cannot be sent by accident — it is not a method any daemon
    /// has — while still occupying a row in the routing table, which is the job
    /// it is here to do.
    case update = "update.*"

    /// Whether getting this method wrong locks somebody out of their robot.
    ///
    /// THE PIN AND THE UPDATER ARE THE RECOVERY PATH, so they must never be
    /// reachable from a network transport. A peer that can rewrite the pairing
    /// PIN can lock a phone out of BLE, and BLE is how a robot with no working
    /// network is recovered — so a compromised or merely buggy network peer
    /// would take away the exact tool needed to undo it. The same argument
    /// covers the updater: a stranger who can trigger a firmware write owns the
    /// robot. Both are answered on Bluetooth, where the caller has already
    /// bonded and is standing next to the duck.
    public var mutatesTheRecoveryPath: Bool {
        switch self {
        case .pairingPin, .setPairingPin, .update: return true
        case .hello, .move, .head, .look, .stop, .enable, .initPose, .relax, .state: return false
        }
    }

    // MARK: - routing

    /// Which methods a transport carries.
    ///
    /// EXHAUSTIVE ON BOTH AXES, WITH NO `default` ANYWHERE, AND THAT IS
    /// COPIED DELIBERATELY. Pollen's `btd/src/route.rs` matches every call
    /// variant with no wildcard, and says why: "`_ => None` would deny new
    /// methods silently, and the first symptom would be an app that cannot see
    /// a feature nobody remembered to route." So adding a case to
    /// `DuckMethod` breaks the build in four places below, and adding a case to
    /// `DuckTransportKind` breaks it here — in both directions the compiler
    /// asks the question rather than a tester discovering the answer months
    /// later, holding a robot that will not do something it can do.
    ///
    /// DENYING IS NOT AN INSULT TO THE TRANSPORT. Several entries below are
    /// "no" because the thing on the other end genuinely has no such concept —
    /// a physics server has no motor bus to enable — and one whole column is
    /// "no" for safety. A refusal from this table is a fact about the link,
    /// which is exactly what a person staring at a dead button needs told.
    public static func reach(for transport: DuckTransportKind) -> Set<DuckMethod> {
        switch transport {
        case .ble: return Set(allCases.filter(\.overBluetooth))
        case .webRTC: return Set(allCases.filter(\.overWebRTC))
        case .bench: return Set(allCases.filter(\.overBench))
        case .bridge: return Set(allCases.filter(\.overBridge))
        }
    }

    /// BLE CARRIES A DELIBERATE SUBSET AND DRIVING IS NOT IN IT. Pollen's own
    /// note, already transcribed in `DuckLink`: BLE is "too slow and too
    /// constrained for the full surface, and payloads never traverse it" — what
    /// it serves is provisioning, status, and update trigger/progress. A 50 Hz
    /// stream of twists over a link that renegotiates its MTU to 20 bytes is
    /// the thing that sentence exists to prevent.
    ///
    /// THE TEMPTING WRONG ANSWER IS `stop`. A stop button that works over
    /// Bluetooth sounds like the safest possible addition to this row, and it
    /// is not offered by `btd`, so putting it here would produce a control that
    /// looks like an emergency stop and is refused by name. What actually stops
    /// a duck that has lost its driver is the robot's own deadman —
    /// `safety.gate(command, twist_age)` — which is age-based, so a partition
    /// stops that duck without anybody pressing anything.
    private var overBluetooth: Bool {
        switch self {
        case .hello, .pairingPin, .setPairingPin, .update: return true
        case .move, .head, .look, .stop, .enable, .initPose, .relax, .state: return false
        }
    }

    /// WebRTC is where the contract says continuous intents will travel, so
    /// this column is the whole robot surface and none of the recovery path.
    private var overWebRTC: Bool {
        switch self {
        case .hello, .move, .head, .look, .stop, .enable, .initPose, .relax: return true
        // `state` is not a method `robotd` answers, and `reach` is not the
        // place to wish that it were.
        case .state, .pairingPin, .setPairingPin, .update: return false
        }
    }

    /// THE BENCH IS PHYSICS, NOT A ROBOT, AND THE GAPS ARE THE INTERESTING
    /// PART. `DuckDrive.intent` posts exactly `{vx, vy, vyaw, hold}` — there is
    /// no head in that body and no endpoint that takes one, so `head` and
    /// `look` are denied rather than silently dropped on the floor. `enable`
    /// and `relax` have no meaning at all against a simulator, which `DuckPad`
    /// already says in its own words: "there is no power to cut and no motor
    /// bus to enable". `initPose` is denied for a subtler reason — the bench's
    /// `/reset` teleports the duck upright, which is not what `robot.init`
    /// does, and mapping one onto the other would hide a fall behind a pose.
    private var overBench: Bool {
        switch self {
        case .hello, .move, .stop, .state: return true
        case .head, .look, .enable, .initPose, .relax: return false
        case .pairingPin, .setPairingPin, .update: return false
        }
    }

    /// A bridge is another copy of this app relaying to a duck it can reach.
    ///
    /// IT GETS THE ROBOT SURFACE AND NOT ONE BYTE OF THE RECOVERY PATH. The
    /// peer on the far end is a program on somebody else's phone, and the
    /// question to ask about it is not whether they are friendly but what the
    /// worst case costs: a relayed twist costs a duck walking into a chair,
    /// while a relayed `system.setPairingPin` costs the owner their only way
    /// back in.
    private var overBridge: Bool {
        switch self {
        case .hello, .move, .head, .look, .stop, .enable, .initPose, .relax, .state: return true
        case .pairingPin, .setPairingPin, .update: return false
        }
    }
}

/// The four things that can be on the other end of this vocabulary.
///
/// NAMED AFTER THE LINK, NOT AFTER THE DUCK. Whether the duck is real is a
/// property of the duck — `DuckIdentity.Kind` — and it is genuinely
/// independent: a bridge can relay to hardware, and WebRTC to a simulator on a
/// desk. Conflating the two is how a screen ends up telling somebody they are
/// driving a robot because the transport looked serious.
public enum DuckTransportKind: String, CaseIterable, Sendable {
    /// Bluetooth Low Energy, per `DuckLink` — the only transport this app has
    /// working code for today.
    case ble
    /// Where `duck-ipc-proto` says continuous intents will travel. No app-side
    /// implementation exists yet.
    case webRTC
    /// HTTP to `sim/duckbench.mjs`, per `DuckDrive` and `DuckBench`.
    case bench
    /// Another copy of this app, relaying to a duck it can reach and this one
    /// cannot.
    case bridge

    public var label: String {
        switch self {
        case .ble: return "Bluetooth"
        case .webRTC: return "WebRTC"
        case .bench: return "Bench"
        case .bridge: return "Bridge"
        }
    }
}

// MARK: - the head, as four numbers

/// A head pose: `robot.head`'s parameters, in the proto's own order.
///
/// A SEPARATE TYPE FROM THE TWIST BECAUSE THE ROBOT KEEPS THEM SEPARATE, and
/// `DuckKit`'s `DuckCommand` keeps them separate for a stated reason — the
/// twist alone decides walking versus standing, so "head and body motion must
/// not make the robot think it is walking". `padd`'s comment is the same worry
/// from the other side: "a robot that keeps walking because you started moving
/// its head is a bad enough surprise".
///
/// NOT REUSING `DuckCommand.head` EVEN THOUGH IT IS THE SAME FOUR NUMBERS.
/// That one is a bare tuple inside an observation vector, which cannot be the
/// payload of an `Equatable` enum case and carries no field names a serialiser
/// can use. The twist, which does have a named type, IS reused — this file
/// defines no second twist.
public struct DuckHead: Equatable, Sendable {
    /// Radians, all four. `duck-ipc-proto`'s `HeadParams` is
    /// `{neck_pitch, head_pitch, head_yaw, head_roll}` and `DuckKit` documents
    /// the same four as radians in the trunk frame.
    public let neckPitch: Double
    public let headPitch: Double
    public let headYaw: Double
    public let headRoll: Double

    public init(neckPitch: Double = 0, headPitch: Double = 0,
                headYaw: Double = 0, headRoll: Double = 0) {
        self.neckPitch = neckPitch
        self.headPitch = headPitch
        self.headYaw = headYaw
        self.headRoll = headRoll
    }

    /// Head up, facing forward — every angle zero.
    public static let level = DuckHead()

    /// The four names as the wire spells them. SNAKE CASE, because that is what
    /// `HeadParams` derives; a Swift-cased `neckPitch` on the wire is a
    /// parameter the robot will not recognise.
    var wire: [String: Any] {
        ["neck_pitch": neckPitch, "head_pitch": headPitch,
         "head_yaw": headYaw, "head_roll": headRoll]
    }

    var isFinite: Bool {
        neckPitch.isFinite && headPitch.isFinite && headYaw.isFinite && headRoll.isFinite
    }
}

// MARK: - a call

/// One thing to say, complete enough to serialise.
///
/// THE RECOVERY-PATH METHODS ARE NOT REPRESENTABLE HERE, WHICH IS THE STRONGEST
/// FORM OF THE RULE. There is no `DuckCall` case for `system.setPairingPin` or
/// for anything in `update.`, so no amount of care or carelessness in a
/// transport can produce that line: it is not that the app refuses to send it,
/// it is that there is nothing to send. `DuckMethod` still names them so the
/// routing table has to decide about them, and `DuckPeer.vet` still checks
/// reach — belt and braces, on the one hand where the cost of a mistake is
/// somebody's robot.
///
/// REQUESTS AND NOTIFICATIONS ARE ONE TYPE ON PURPOSE. The split between them
/// is a property of the method, not of the call site, so `isNotification` is
/// derived and cannot disagree with itself; a caller that had to remember which
/// was which would eventually send a twist as a request and wait for a reply
/// that the contract says is never coming.
public enum DuckCall: Equatable, Sendable {
    case hello
    /// The twist is `DuckDrive.Twist`: one twist type in this package, with
    /// `padd`'s speeds and Pollen's signs already applied by
    /// `DuckDrive.twist(for:)`.
    case move(DuckDrive.Twist)
    case head(DuckHead)
    /// `robot.look`, the answered counterpart of the continuous head intent.
    ///
    /// ITS PARAMETERS ARE THE ONE SHAPE IN THIS FILE THAT IS NOT TRANSCRIBED.
    /// `duck-ipc-proto` names `robot.look` in its method list, and this app has
    /// read the list without reading `LookParams`. The four head angles are
    /// carried here because they are the only head vocabulary the proto
    /// defines, and because a discrete "point the head there and tell me when"
    /// wants the same numbers the continuous one does. If that guess is wrong,
    /// the robot answers with a refusal naming the parameter, and
    /// `DuckReply.failure` carries it to the screen — which is how the first
    /// person to point this at a duck will find out, and is why it is written
    /// down here rather than assumed.
    case look(DuckHead)
    case stop
    case enable
    /// `robot.init`. See `DuckMethod.initPose` for why the Swift name differs
    /// from the wire name.
    case initPose
    case relax
    /// `studio.state` — ours, not Pollen's. See `DuckMethod.state`.
    case state

    /// What this is called on the wire.
    public var method: DuckMethod {
        switch self {
        case .hello: return .hello
        case .move: return .move
        case .head: return .head
        case .look: return .look
        case .stop: return .stop
        case .enable: return .enable
        case .initPose: return .initPose
        case .relax: return .relax
        case .state: return .state
        }
    }

    /// Whether this goes out as a JSON-RPC notification — no id, no reply, ever.
    ///
    /// TWO METHODS, AND THE REASON IS THE ROBOT'S RATHER THAN A PREFERENCE.
    /// `duck-ipc-proto` sends the continuous intents — `robot.move` and
    /// `robot.head` — as notifications at 20–50 Hz, last-writer-wins and
    /// expiring, precisely because a reply per frame is a queue nobody wants
    /// and a stale frame is worse than a missing one. Everything else is a
    /// request: the caller needs to know whether a stop was accepted, and "I
    /// asked it to stop" is not the same claim as "it stopped".
    public var isNotification: Bool {
        switch self {
        case .move, .head: return true
        case .hello, .look, .stop, .enable, .initPose, .relax, .state: return false
        }
    }

    /// Why a call could not be turned into a line, or could not be sent.
    ///
    /// EVERY CASE CARRIES THE METHOD, because these are the errors somebody
    /// reads at three in the morning wondering why the duck is ignoring them,
    /// and "a notification cannot carry an id" without saying which one is a
    /// sentence that costs an hour.
    public enum Misuse: Error, Equatable {
        /// A continuous intent was given an id. The contract says these are
        /// never answered, so an id is a reply somebody is waiting for forever.
        case notificationCarriedAnID(DuckMethod)
        /// A request was built without an id, which makes it a notification the
        /// robot will not answer.
        case requestHadNoID(DuckMethod)
        /// A NaN or an infinity reached the serialiser.
        case notANumber(DuckMethod)
        /// The transport does not carry this method — see `DuckMethod.reach`.
        case outOfReach(DuckMethod, DuckTransportKind)
        /// `notify` was handed a request, or `call` a notification.
        case wrongDirection(DuckMethod)

        public var message: String {
            switch self {
            case .notificationCarriedAnID(let method):
                return "\(method.rawValue) is a continuous intent: it is sent as a notification "
                     + "and is never answered, so giving it an id would leave somebody waiting "
                     + "for a reply the robot has no obligation to send."
            case .requestHadNoID(let method):
                return "\(method.rawValue) is answered, so it needs an id. Without one it is a "
                     + "notification, and the answer this call exists to get would never arrive."
            case .notANumber(let method):
                return "\(method.rawValue) was given a value that is not a number. JSON has no "
                     + "way to write NaN or infinity, so this was stopped here rather than "
                     + "becoming a line the duck cannot parse."
            case .outOfReach(let method, let transport):
                return "\(transport.label) does not carry \(method.rawValue). That is a fact "
                     + "about the link, not a fault: each transport carries a decided subset."
            case .wrongDirection(let method):
                return "\(method.rawValue) was sent the wrong way round — a continuous intent "
                     + "must be notified and an answered call must be called."
            }
        }
    }

    /// One NDJSON line, newline-terminated, ready to hand to a transport.
    ///
    /// - Parameter id: The JSON-RPC id. It must be present for a request and
    ///   absent for a notification, and this throws either way round rather
    ///   than quietly fixing it — a silently-dropped id is a caller awaiting a
    ///   reply that was never asked for, and a silently-added one is a robot
    ///   answering 50 times a second.
    ///
    /// THE NEWLINE IS THE FRAME AND THERE IS NO HEADER. `framing.rs`: "The
    /// newline that already separates messages is the frame delimiter, in both
    /// directions. That is safe rather than lucky: `serde_json` escapes a
    /// newline inside a string as `\n`, so a raw `0x0A` never appears inside a
    /// serialised JSON object." Nothing in this vocabulary carries a string
    /// payload at all, so the only newline any line of ours can contain is the
    /// one appended at the end — which the tests assert by counting.
    public func line(id: Int?) throws -> Data {
        if isNotification, id != nil { throw Misuse.notificationCarriedAnID(method) }
        if !isNotification, id == nil { throw Misuse.requestHadNoID(method) }

        // ONE HELLO IN THE APP, NOT TWO. `DuckLink.helloRequest` is the line a
        // real robot has been written against; duplicating its body here would
        // give the app two spellings of its only working call, and the day one
        // of them gained a field would be the day they disagreed.
        if case .hello = self { return try DuckLink.helloRequest(id: id!) }

        var body: [String: Any] = ["jsonrpc": "2.0", "method": method.rawValue]
        if let id { body["id"] = id }
        if let params = try parameters() { body["params"] = params }
        var data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }

    /// The `params` member, or nil for a call that takes none.
    ///
    /// OMITTED RATHER THAN SENT EMPTY. JSON-RPC 2.0 says `params` MAY be left
    /// out, and an empty object is a claim that the method takes parameters and
    /// got none — which is a different thing to say to a strict deserialiser.
    private func parameters() throws -> [String: Any]? {
        switch self {
        case .hello:
            // Handled above by DuckLink.helloRequest; unreachable.
            return nil
        case .move(let twist):
            // POLLEN'S EXACT FIELD NAMES AND POLLEN'S SIGNS. `MoveParams` is
            // `{vx, vy, vyaw}` in the trunk frame — x forward, y LEFT, z up,
            // positive vyaw turning LEFT. Their contract records that the
            // prototype grew five separate sign flags "precisely because the
            // convention was never written down, so every new consumer
            // determined it empirically and disagreed". This is the writing
            // down; `DuckDrive.twist(for:)` is where the stick's signs are
            // turned into these.
            guard twist.vx.isFinite, twist.vy.isFinite, twist.vyaw.isFinite else {
                throw Misuse.notANumber(.move)
            }
            return ["vx": twist.vx, "vy": twist.vy, "vyaw": twist.vyaw]
        case .head(let pose):
            guard pose.isFinite else { throw Misuse.notANumber(.head) }
            return pose.wire
        case .look(let pose):
            guard pose.isFinite else { throw Misuse.notANumber(.look) }
            return pose.wire
        case .stop, .enable, .initPose, .relax, .state:
            return nil
        }
    }

    /// One of every call this app can build, with placeholder payloads.
    ///
    /// DERIVED FROM `DuckMethod.allCases` THROUGH AN EXHAUSTIVE SWITCH, so a
    /// method added to the vocabulary must be given a shape here or the file
    /// does not compile — which is what keeps a test that sweeps "every call"
    /// from quietly sweeping an out-of-date list. The methods that map to nil
    /// are the recovery path, and their absence is the rule stated at the top
    /// of this type, enforced by the compiler and asserted by a test.
    public static let allShapes: [DuckCall] = DuckMethod.allCases.compactMap(shape(of:))

    static func shape(of method: DuckMethod) -> DuckCall? {
        switch method {
        case .hello: return .hello
        case .move: return .move(.still)
        case .head: return .head(.level)
        case .look: return .look(.level)
        case .stop: return .stop
        case .enable: return .enable
        case .initPose: return .initPose
        case .relax: return .relax
        case .state: return .state
        case .pairingPin, .setPairingPin, .update: return nil
        }
    }
}

// MARK: - what came back

/// A JSON-RPC reply, decoded far enough to be shown to somebody.
///
/// IT CARRIES A REFUSAL RATHER THAN THROWING ONE. A robot that answers "no" has
/// answered, and the difference between "the duck refused" and "the link
/// broke" is the whole diagnosis; collapsing both into a thrown error makes
/// every failure look like a network problem. Decoding only throws when what
/// came back is not a JSON-RPC reply at all.
public struct DuckReply: Equatable, Sendable {

    /// What the robot said no with.
    public struct Failure: Equatable, Sendable {
        public let code: Int
        public let message: String

        public init(code: Int, message: String) {
            self.code = code
            self.message = message
        }

        /// PHRASED HERE RATHER THAN IN A VIEW, like every other sentence in
        /// this package, and phrased the same way `DuckLink.LinkError` phrases
        /// it so one app does not have two voices for one event.
        public var says: String { "The duck refused: \(message) (\(code))" }
    }

    /// The id this answers. Nil when the reply carried none — which is itself
    /// worth seeing, since a notification should never have produced a reply.
    public let id: Int?

    /// The `result` member, re-serialised. Nil on a refusal.
    ///
    /// KEPT AS BYTES RATHER THAN AS A DICTIONARY so this type can be `Sendable`
    /// and `Equatable` without pretending JSON is a fixed shape. Results differ
    /// per method and this vocabulary is not the place to enumerate them; the
    /// caller that knows which method it sent pulls what it knows is there with
    /// `field(_:)`.
    public let result: Data?

    /// Present exactly when the robot refused.
    public let failure: Failure?

    public init(id: Int?, result: Data?, failure: Failure?) {
        self.id = id
        self.result = result
        self.failure = failure
    }

    public var succeeded: Bool { failure == nil }

    /// One member of the result, if it is there and is the type asked for.
    public func field<T>(_ key: String) -> T? {
        guard let result,
              let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any]
        else { return nil }
        return object[key] as? T
    }

    /// Read one NDJSON reply line.
    ///
    /// REUSES `DuckLink.LinkError` FOR THE MALFORMED CASES because they are the
    /// same two malformed cases, with the same two sentences already written
    /// for them. A second error type here would be a second wording of "that
    /// was not JSON-RPC coming back" for a person to be confused by.
    public static func decode(_ line: Data) throws -> DuckReply {
        guard let top = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw DuckLink.LinkError.notJSON
        }
        let id = top["id"] as? Int
        if let error = top["error"] as? [String: Any] {
            return DuckReply(id: id, result: nil,
                             failure: Failure(code: error["code"] as? Int ?? 0,
                                              message: error["message"] as? String
                                                    ?? "no reason given"))
        }
        guard let result = top["result"] else {
            throw DuckLink.LinkError.unexpected("A reply with neither a result nor an error in it.")
        }
        // `.fragmentsAllowed` because a result is allowed to be a bare `true`
        // or `null` — `robot.stop` has no reason to answer with an object, and
        // a decoder that required one would refuse a perfectly good yes.
        let data = try JSONSerialization.data(withJSONObject: result,
                                              options: [.sortedKeys, .fragmentsAllowed])
        return DuckReply(id: id, result: data, failure: nil)
    }
}

// MARK: - who is on the other end

/// How the app draws a duck so two of them in one room are not the same duck.
///
/// THESE ARE THE APP'S COLOURS AND NOT POLLEN'S CATALOGUE. Nothing in this
/// repository has transcribed what colours a Microduck is actually sold in, so
/// naming one here as a product option would be a claim about hardware nobody
/// working on this app has seen. What these are for is telling peers apart on
/// screen: the moment a second duck appears, "the duck" stops being a
/// noun-phrase that identifies anything, and a colour is what a person reaches
/// for before a name.
///
/// THE RGB LIVES HERE RATHER THAN IN THE VIEW because a view that parsed a hex
/// string would be doing arithmetic about a robot, which this package exists to
/// keep out of the app target.
public enum DuckColourway: String, CaseIterable, Sendable {
    /// The default, and the colour the app has drawn a duck in since its first
    /// stance was rendered.
    case yellow
    case white
    case charcoal
    case teal
    case coral
    case lilac

    public var label: String {
        switch self {
        case .yellow: return "Yellow"
        case .white: return "White"
        case .charcoal: return "Charcoal"
        case .teal: return "Teal"
        case .coral: return "Coral"
        case .lilac: return "Lilac"
        }
    }

    /// Each channel 0...1.
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .yellow: return (0.98, 0.78, 0.13)
        case .white: return (0.95, 0.95, 0.93)
        case .charcoal: return (0.24, 0.25, 0.28)
        case .teal: return (0.11, 0.63, 0.60)
        case .coral: return (0.95, 0.45, 0.38)
        case .lilac: return (0.68, 0.56, 0.87)
        }
    }
}

/// Which duck this is, in the terms a person uses about it.
///
/// THE KIND IS A CLAIM AND IT IS THE MOST IMPORTANT FIELD HERE. This app has
/// spent its whole life driving a simulator while saying so on every screen —
/// `DuckDrive.thisIsNotARobot` is a paragraph about exactly this — and the day
/// two ducks appear in one list is the day that admission has to survive being
/// one word in a row rather than a paragraph on a page. So `kind` travels with
/// the name, always, rather than being inferred from the transport: a bridge
/// can relay to hardware and WebRTC can reach a simulator, and a screen that
/// guessed from the link would eventually tell somebody they were driving a
/// robot because the connection looked serious.
public struct DuckIdentity: Equatable, Sendable {

    /// Real or not. There is no third case and no "unknown": a peer that cannot
    /// say what it is has not finished saying hello.
    public enum Kind: String, CaseIterable, Sendable {
        /// Hardware. Something in a room can fall over.
        case real
        /// Physics on a machine somewhere. Nothing can be broken by getting
        /// this wrong.
        case sim

        public var label: String {
            switch self {
            case .real: return "Robot"
            case .sim: return "Simulated"
            }
        }
    }

    /// What the duck calls itself — its hostname over BLE, or whatever a bench
    /// or a bridge was named by the person running it.
    public let name: String
    public let colourway: DuckColourway
    public let kind: Kind

    public init(name: String, colourway: DuckColourway = .yellow, kind: Kind) {
        self.name = name
        self.colourway = colourway
        self.kind = kind
    }

    /// One line for a row in a list: who, and whether it can hurt itself.
    public var says: String { "\(name) — \(kind.label.lowercased()), \(colourway.label.lowercased())" }
}

// MARK: - the peer

/// Something this app can say the vocabulary to.
///
/// FIVE MEMBERS, AND THE SMALLNESS IS THE FEATURE. Every transport in this app
/// — the BLE link that exists, the bench that exists over HTTP, the WebRTC and
/// bridge links that do not exist yet — is the same five questions: who are
/// you, what do you carry, ask this and wait, say this and do not wait, and
/// tell me what you are doing without being asked. A screen written against
/// this protocol is a screen that does not know or care which of them it got,
/// which is the entire reason for the file: what somebody learns driving the
/// simulator becomes knowledge about driving the robot.
///
/// THE FIFTH ONE IS `states()`, AND IT IS REQUIRED RATHER THAN DEFAULTED. A
/// robot's state is telemetry: `robotd` pushes `robot.state` as a notification
/// at the loop rate and answers no method that asks for one, which is why
/// `DuckMethod.state` is namespaced `studio.` and denied on both transports a
/// real daemon speaks. So the shape a screen has to be written against is a
/// stream, not a poll — and a stream every transport must produce, because the
/// alternative was a default implementation returning an empty one. That
/// default is the dangerous version: a transport whose author forgot this
/// member would compile, publish nothing forever, and present as a duck that
/// never falls over. A missing conformance is a build error somebody fixes in
/// an afternoon; a silent empty stream is a diary that says the duck was fine.
/// A peer with genuinely nothing to publish finishes its stream immediately and
/// says so in a sentence — which is a decision, written down, rather than an
/// omission.
///
/// `AnyObject` BECAUSE A TRANSPORT IS A CONNECTION, not a value: it owns a
/// socket or a peripheral, it is the same peer before and after a reconnection,
/// and two references to it must be two references to one link rather than two
/// copies of a struct that both think they hold the write handle.
///
/// ONE WRITER PER DUCK, AND THIS PROTOCOL DOES NOT ENFORCE IT. `intents.rs` is
/// last-writer-wins on a single slot, so two clients pushing 50 Hz twists
/// "interleave into one slot, producing a robot that obeys neither" — the
/// accepted fix is a single-writer token, which is a thing a duck hands out and
/// therefore lives a layer above this. It is written here so that whoever
/// implements the second transport reads it before discovering it with a duck.
public protocol DuckPeer: AnyObject, Sendable {
    /// Which link this peer is. NOT A LABEL A CALLER PASSES IN — the refusal
    /// `vet` throws is a claim ABOUT this link ("robot.move is not carried over
    /// Bluetooth"), and a caller-supplied argument lets a peer name a transport
    /// it is not. Requiring it here ties the sentence to the same value the
    /// reach set was derived from, so the two cannot disagree.
    var transportKind: DuckTransportKind { get }


    /// Who this is, and whether it is real.
    var identity: DuckIdentity { get }

    /// What this link carries — normally `DuckMethod.reach(for:)` for its own
    /// transport, and never wider than that. A peer may narrow it (a robot on
    /// an older API version, a bench that has not loaded a policy); a peer that
    /// widened it would be claiming a route the routing table has denied.
    var reach: Set<DuckMethod> { get }

    /// Ask, and wait for the answer.
    func call(_ c: DuckCall) async throws -> DuckReply

    /// Say, and do not wait. For the continuous intents only.
    func notify(_ c: DuckCall) async throws

    /// What the duck is doing, as it says so, for as long as somebody is
    /// listening.
    ///
    /// EVERY READER GETS ITS OWN STREAM AND THEY ALL GET EVERY STATE. Three
    /// screens can be interested in one duck at once — the card at the front
    /// door, a driving loop, a recorder — and a single stream shared between
    /// them would hand each state to whichever one happened to be waiting.
    /// `DuckStateFanOut` is the piece that does this so each transport does not
    /// have to; a reader that goes away removes itself, and the ones that
    /// stayed do not notice.
    ///
    /// NOT `async`, SO AN ACTOR IMPLEMENTS IT `nonisolated`. A caller must be
    /// able to take the stream and then start the thing that fills it, in that
    /// order; a member that had to be awaited would make "start listening
    /// before you start driving" a race rather than a sequence.
    func states() -> AsyncStream<DuckState>
}

extension DuckPeer {

    /// The check every implementation runs before it writes a byte.
    ///
    /// IT IS AN EXTENSION RATHER THAN A COMMENT ASKING NICELY. There will be
    /// several transports and only one of them is written by whoever reads this
    /// sentence; a rule that each of them has to re-implement is a rule that
    /// three of them implement and the fourth forgets, and the forgetful one is
    /// the one that sends `robot.move` down a Bluetooth link at 50 Hz. Both
    /// halves are here: the method must be carried by this link at all, and it
    /// must be going the direction the contract says it goes.
    /// - Note: The transport is read off the peer rather than taken as an
    ///   argument. It used to be a parameter, and nothing tied it to `reach` —
    ///   so a bench peer could refuse `robot.head` in a sentence blaming
    ///   Bluetooth, which is a false statement about a link in a package whose
    ///   product is accurate refusals.
    public func vet(_ c: DuckCall, asNotification: Bool) throws {
        guard reach.contains(c.method) else {
            throw DuckCall.Misuse.outOfReach(c.method, transportKind)
        }
        guard asNotification == c.isNotification else {
            throw DuckCall.Misuse.wrongDirection(c.method)
        }
    }
}

// MARK: - one state, several readers

/// Hands one `DuckState` to every reader that is listening, and forgets the
/// ones that stopped.
///
/// WHY A TRANSPORT CANNOT JUST KEEP A CONTINUATION. `AsyncStream` has exactly
/// one consumer: whichever task calls `next()` gets the element and nobody else
/// does. Three things in this app want the same duck's states at the same time
/// — the front-door card, a driving loop, a recorder writing a diary — and with
/// one shared stream they would race for each value, so two of the three would
/// show a duck that fell over one state in three. Every transport would
/// otherwise solve that itself, four times, and one of the four would get the
/// removal wrong.
///
/// THE REMOVAL IS THE PART WORTH WRITING ONCE. A reader that goes away — a view
/// dismissed, a task cancelled, an iterator dropped mid-loop — must stop costing
/// anything, and `onTermination` is the only hook that fires for all three of
/// those. Without it a screen opened and closed forty times leaves forty
/// continuations being yielded to at 50 Hz, which is a leak that presents as the
/// app getting slower the longer it is used and never as an error.
///
/// A LOCK RATHER THAN AN ACTOR, AND THAT IS FORCED BY THE PROTOCOL. `states()`
/// is not `async` — deliberately, so a caller can take the stream and then start
/// the thing that fills it — and registering a reader has to happen inside
/// `AsyncStream`'s builder closure, which is synchronous. An actor cannot be
/// touched from there without a `Task`, and a `Task` is exactly the gap in which
/// the first states go to nobody. `NSLock` is held only across a dictionary
/// insert or removal; nothing awaits inside it.
///
/// YIELDING HAPPENS OUTSIDE THE LOCK. `yield` runs a buffering policy and can
/// call into a consumer's continuation, so holding the lock across it would let
/// a reader's own `onTermination` deadlock against the publisher. The snapshot
/// is taken under the lock; the yields are not.
///
/// THE BUFFER IS UNBOUNDED, WHICH IS A REAL CHOICE WITH A REAL COST. A reader
/// that stops consuming grows a queue instead of dropping states, because for
/// the two things this stream is for — a diary and a fall — a dropped state is
/// evidence destroyed silently, and this package's whole argument is that a
/// silent zero is worse than a visible cost. A stream that must not grow is a
/// stream whose owner stops iterating it, which removes it from here entirely.
public final class DuckStateFanOut: @unchecked Sendable {

    /// What identifies a reader while it is listening. An integer that only
    /// counts up: a token is never reused, so a late `onTermination` from a
    /// reader that has already gone cannot remove a reader that arrived after
    /// it and happened to be handed the same slot.
    public typealias Token = Int

    private let lock = NSLock()
    private var readers: [Token: AsyncStream<DuckState>.Continuation] = [:]
    private var nextToken: Token = 1
    private var finished = false

    public init() {}

    /// How many readers are listening right now. FOR TESTS AND FOR A DIAGNOSTIC
    /// LINE, not for a decision: a transport that stopped publishing because
    /// nobody was listening would be a transport whose behaviour depends on who
    /// is watching it.
    public var readerCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return readers.count
    }

    /// A stream of every state published from now on.
    ///
    /// STATES PUBLISHED BEFORE THIS CALL ARE NOT REPLAYED. There is no
    /// last-value cache here on purpose: a card that opened and immediately
    /// showed a state from four minutes ago would be showing a duck that has
    /// since fallen over, and `DuckState.isStale(now:after:)` exists because
    /// that distinction is the value's own business rather than this type's.
    public func states() -> AsyncStream<DuckState> {
        AsyncStream(DuckState.self, bufferingPolicy: .unbounded) { continuation in
            let token = register(continuation)
            continuation.onTermination = { [weak self] _ in
                self?.remove(token)
            }
        }
    }

    /// Hand a state to everyone listening.
    public func publish(_ state: DuckState) {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        let listening = Array(readers.values)
        lock.unlock()
        for continuation in listening { continuation.yield(state) }
    }

    /// End every stream, and refuse to start another.
    ///
    /// WHAT A CLOSED LINK MEANS FOR A READER. A `for await` that simply stops
    /// producing looks exactly like a duck standing still; one that ends tells
    /// the loop the link is gone and lets the screen say so. So a transport
    /// that knows its connection died calls this rather than going quiet, and
    /// once called this fan-out stays closed — a stream handed out after the
    /// link died would be a stream that never yields and never ends.
    public func finish() {
        lock.lock()
        let listening = Array(readers.values)
        readers.removeAll()
        finished = true
        lock.unlock()
        for continuation in listening { continuation.finish() }
    }

    /// True once `finish()` has been called.
    public var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    private func register(_ continuation: AsyncStream<DuckState>.Continuation) -> Token {
        lock.lock()
        let token = nextToken
        nextToken += 1
        if finished {
            lock.unlock()
            // A stream taken after the link ended ends immediately rather than
            // hanging: the reader finds out, in the only way a stream can say
            // anything.
            continuation.finish()
            return token
        }
        readers[token] = continuation
        lock.unlock()
        return token
    }

    private func remove(_ token: Token) {
        lock.lock()
        readers.removeValue(forKey: token)
        lock.unlock()
    }
}
