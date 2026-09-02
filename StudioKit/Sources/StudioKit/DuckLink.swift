import Foundation

/// Talking to a real Microduck over Bluetooth Low Energy.
///
/// THE ONLY WAY A PHONE CAN REACH A DUCK. `robotd` speaks JSON-RPC over a unix
/// socket on the robot itself, and `architecture.md` §4.1 names four transports
/// over one API definition — BLE, unix socket, WebSocket, WebRTC — of which
/// exactly one is reachable from an iPhone today. BLE carries a deliberate
/// SUBSET: "provisioning, status, update trigger/progress — it's too slow and
/// too constrained for the full surface, and payloads never traverse it." So
/// this can find a duck, pair with it, and ask it who it is. It cannot drive
/// one, and nothing in this file pretends otherwise.
///
/// EVERY CONSTANT HERE IS TRANSCRIBED FROM `btd`'s SOURCE, not from a summary
/// of it. `gatt.rs` says the UUIDs "must not change once an app has shipped
/// against them" and writes them out in full "so that grepping for a value
/// finds this comment" — this is the other end of that grep. The lesson is one
/// this project has already paid for elsewhere: BLE UUIDs copied from a web
/// mirror are how an app ships a scanner that finds nothing.
public enum DuckLink {

    /// The robot's service. What a client scans for.
    public static let serviceUUID = "6F5D2A10-3B47-4C8E-9A1F-2D7E8C4B6019"

    /// The RPC pipe — **one** characteristic, read + write + notify.
    ///
    /// ONE, NOT TWO, AND THAT IS DELIBERATE ON THEIR SIDE. `gatt.rs` explains:
    /// BlueZ reports a write and a subscription as separate events, so with a
    /// write characteristic and a notify characteristic the robot has to pair
    /// the two halves by device address, guessing the association. With one,
    /// both events belong to it by construction. The cost is that it "reads
    /// slightly oddly in a generic browser like nRF Connect, where the same row
    /// is both" — so a tester poking at this with nRF Connect should expect
    /// exactly that and not conclude anything is wrong.
    public static let rpcUUID = "6F5D2A11-3B47-4C8E-9A1F-2D7E8C4B6019"

    /// The API version this app was written against.
    ///
    /// `duck_ipc_proto::API_VERSION` was 16 when this was transcribed. A robot
    /// reports its own, and the two are allowed to differ — see `verdict(for:)`,
    /// which says so rather than refusing.
    public static let apiVersion: UInt32 = 16

    /// The manufacturer-data company id the address is filed under.
    ///
    /// `0xFFFF` is the id the Bluetooth SIG reserves for internal and
    /// interoperability testing, and `adv.rs` is explicit that using it is
    /// correct for a project with none assigned — and that **it is not an
    /// identity check**: "anyone else may use it too". The service UUID is the
    /// discriminator. Only ask this of a device that already advertised
    /// `serviceUUID`.
    public static let companyID: UInt16 = 0xFFFF

    /// Longest line to reassemble before giving up on a peer — `framing.rs`'s
    /// `MAX_LINE`. A robot that never sends a newline would otherwise grow a
    /// buffer without bound.
    public static let maxLine = 8 * 1024

    // MARK: - what a scan can see without connecting

    /// A duck as it appears in a scan, before anything is connected.
    ///
    /// SCANNING CONNECTS TO NOTHING, and that is the whole value of it. Their
    /// `duckctl scan` is built the same way and `adv.rs` says why: reading the
    /// address over RPC "costs a connection, a bond and the PIN — per robot",
    /// so a listing that connected would be useless for the case a listing is
    /// most needed in, which is a robot that is not answering.
    public struct Sighting: Equatable, Sendable {
        /// The Local Name, which BlueZ puts in the scan response.
        public let name: String
        /// Signal strength, dBm. Nil when the platform withheld it.
        public let rssi: Int?
        /// What the advertisement said about the robot's address.
        public let address: Address
        /// Which of the three tiers of evidence got this device onto the list.
        public let tier: Tier
        /// Whether the radio heard this device in the window, or iOS handed it
        /// back from memory by identifier.
        ///
        /// RETRIEVED IS NOT SEEN. `retrievePeripherals(withIdentifiers:)`
        /// returns a peripheral for every identifier it is given — switched off,
        /// out of range, in another building — with no advertisement behind
        /// it. A report that listed those under "seen in the scan window" would
        /// be describing a radio event that never happened, and a scan step
        /// that turned green on one would be a forty-second silence written up
        /// as a success. So a sighting says which it is, and the report keeps
        /// the two apart.
        public let heard: Bool

        public init(name: String, rssi: Int?, address: Address, tier: Tier, heard: Bool = true) {
            self.name = name
            self.rssi = rssi
            self.address = address
            self.tier = tier
            self.heard = heard
        }

        /// The one line the report prints for a sighting.
        ///
        /// SIGNAL IS PRINTED OR ITS ABSENCE IS, never a zero. iOS withholds RSSI
        /// often enough that a report reading "0 dBm" would be read as a very
        /// close duck by somebody who has never seen this app.
        public var line: String {
            let signal = rssi.map { "\($0) dBm" } ?? "no signal reading"
            let base = "\(name), \(signal) — \(tier.evidence)"
            return heard ? base
                : base + "; offered from this phone's memory and NOT heard in this window"
        }
    }

    /// How strong the evidence is that a sighting is a duck.
    ///
    /// THREE TIERS, NONE OF THEM PROOF, AND THE APP HAS TO RANK THEM SOMEWHERE.
    /// `app-path-design.md` is precise about the two facts that force this: the
    /// advertised service UUID is the best hint a scan can carry, and a BONDED
    /// peripheral "frequently advertises with an empty service list" — so the
    /// duck somebody has already paired with, the one they most want back, is
    /// exactly the one that hint goes missing for. A filtered scan drops it
    /// entirely, so the scan runs unfiltered and the ranking happens here, in
    /// software, on whatever each advertisement actually carried.
    ///
    /// NONE OF THESE IS THE IDENTITY TEST. "Serves our characteristic" is "the
    /// only authoritative identity test — it is knowable solely after
    /// connecting", so every tier below describes a CANDIDATE and the handshake
    /// is what settles it.
    public enum Tier: Int, CaseIterable, Sendable {
        /// The advertisement named the robot's service. The strongest thing a
        /// scan can see without connecting.
        case advertisedService
        /// This phone has completed a handshake with this peripheral before, so
        /// its identifier is stored — which is how a bonded duck advertising
        /// nothing is still found.
        case knownBefore
        /// Nothing but a duck-ish Local Name. Deliberately generous: the cost of
        /// a wrong guess is one refused connection and the cost of a miss is a
        /// duck that cannot be found.
        case nameOnly

        /// What got it onto the list, for the report.
        public var evidence: String {
            switch self {
            case .advertisedService: return "advertises the robot's service UUID"
            case .knownBefore: return "this phone has handshaked with it before"
            case .nameOnly: return "a duck-ish name and nothing else"
            }
        }

        /// Whether this is evidence enough to stop listening.
        ///
        /// ONLY THE FIRST TIER IS. A name match may be somebody's headphones and
        /// a stored identifier may be a duck that has since changed address, so
        /// a scan that stopped at either would routinely test the wrong device;
        /// a scan that stops at an advertised service UUID has the best evidence
        /// the radio can carry and nothing is gained by listening longer.
        public var endsTheScan: Bool { self == .advertisedService }
    }

    /// Rank one advertisement, or reject it.
    ///
    /// THE FILTER THAT IS NOT ON THE SCAN CALL. `scanForPeripherals` is given no
    /// service list — see `Tier` for why — so every device in radio range is
    /// reported to the app, and this is what decides which of them are
    /// candidates. Written here rather than in the scanner because a rule about
    /// what counts as a duck is a claim about Pollen's protocol, and a claim
    /// like that in the app target is one no `swift test` can see.
    ///
    /// - Returns: The tier, or `nil` for a device that is not a candidate at
    ///   all — somebody's headphones, a laptop, a car.
    public static func tier(advertisesService: Bool,
                            knownBefore: Bool,
                            name: String?) -> Tier? {
        if advertisesService { return .advertisedService }
        if knownBefore { return .knownBefore }
        if let name, looksLikeADuck(name) { return .nameOnly }
        return nil
    }

    /// What an advertisement said about where the robot is on the network.
    ///
    /// THREE CASES, NOT TWO, AND `adv.rs` INSISTS ON THE DIFFERENCE. "A robot
    /// with no wifi advertises `Ipv4Addr::UNSPECIFIED` rather than dropping the
    /// field. The field is then evidence in itself: absent means a robot on a
    /// release that predates this, present and zero means a robot that has no
    /// address, and those two want different next moves. Dropping the field
    /// would collapse them into one blank column." So this enum has three cases
    /// and no optional.
    public enum Address: Equatable, Sendable {
        /// A real address. Where you would ssh.
        case at(String)
        /// The field was present and said `0.0.0.0` — the robot has no wifi.
        case none
        /// No field at all — an older release that predates the broadcast.
        case notBroadcast
    }

    /// Decode the address a scan reported.
    ///
    /// - Parameter manufacturerData: The raw value iOS hands over, INCLUDING
    ///   its two leading company-id bytes, little-endian. CoreBluetooth does not
    ///   split them out the way BlueZ's map does, so the split happens here.
    public static func address(fromManufacturerData data: Data) -> Address {
        // COMPANY ID FIRST, LITTLE-ENDIAN, THEN FOUR OCTETS. Six bytes exactly:
        // `adv.rs` budgets "6 bytes to live in and this one uses 4", and a
        // shorter or longer field is not this field.
        guard data.count >= 2 else { return .notBroadcast }
        let bytes = [UInt8](data)
        let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        guard company == companyID else { return .notBroadcast }
        let octets = bytes.dropFirst(2)
        guard octets.count == 4 else { return .notBroadcast }
        let quad = Array(octets)
        if quad == [0, 0, 0, 0] { return .none }
        return .at(quad.map(String.init).joined(separator: "."))
    }

    /// Whether an advertised name is worth connecting to when the service list
    /// came back empty.
    ///
    /// A NAME IS THE WEAKEST TIER AND IT IS STILL NEEDED. Pollen measured that a
    /// BONDED peripheral frequently advertises no services at all — so the duck
    /// somebody has already paired with, the one they most want to find, is
    /// exactly the one the strongest evidence goes missing for. The robot's own
    /// advertised name is its hostname, which `app-path-design.md` §8.2 records
    /// as being given a duck-ish default.
    ///
    /// DELIBERATELY GENEROUS, because the cost of a wrong guess is one refused
    /// connection and the cost of a miss is a duck that cannot be found. The
    /// handshake settles it either way.
    public static func looksLikeADuck(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("duck") || lower.hasPrefix("microduck")
    }

    /// Why a stored peripheral identifier is not an identity.
    ///
    /// POLLEN SAY THIS ABOUT OUR EXACT SHORTCUT. `SystemInfoResult.serial` is
    /// documented as "the durable handle a client should key on. It outlives a
    /// rename, and it outlives a change of Bluetooth address — which is not
    /// hypothetical, so **an app that remembers a robot by its peripheral
    /// identifier alone will lose it** (`app-path-design.md` §8.6)."
    ///
    /// This app remembers peripheral identifiers, and should: it is what lets
    /// `retrievePeripherals(withIdentifiers:)` reconnect with no fresh
    /// sighting. The word doing the work in their sentence is ALONE. The
    /// identifier is a fast path and the serial is the identity, so a duck
    /// whose address has changed reads as new until it has been asked who it
    /// is — and the answer only arrives after a successful `system.info`,
    /// which is a call this app does not yet make outside the spike.
    ///
    /// Written down rather than fixed, because fixing it properly means
    /// carrying `system.info` on the ordinary path and keying the fleet on the
    /// serial — real work, and work that would be untestable here until
    /// somebody has two ducks and a router that reassigns.
    public static let identifierIsNotAnIdentity =
        "This app remembers a duck by the identifier iOS gives its Bluetooth peripheral. That "
      + "survives a rename and does not survive a change of Bluetooth address, so a duck can "
      + "come back looking like one this app has never seen. The robot's own durable handle is "
      + "the SoC serial that system.info returns, which this app does not yet ask for outside "
      + "the pairing spike."

    // MARK: - the handshake, in the order it has to happen

    /// What a client must do, in order, and why the order is not negotiable.
    ///
    /// THE READ COMES FIRST OR NOTHING WORKS, AND IT FAILS SILENTLY ON iOS.
    /// `gatt.rs` states it outright: "The read is part of the contract, not an
    /// optional nicety. It requires an authenticated encrypted link, so it is
    /// what makes a central pair *before* it writes — a subscribe needs no
    /// encryption, so without the read a client subscribes, has its first write
    /// silently refused, and (on macOS) sees neither a prompt nor an error."
    ///
    /// That is an iOS bug report waiting to happen — a scanner that finds the
    /// duck, connects, subscribes, writes, and then sits there forever with no
    /// error to show anybody. The read is what raises the pairing prompt.
    public enum Step: Int, CaseIterable, Sendable {
        case scan, connect, discover, readVersion, subscribe, hello

        public var title: String {
            switch self {
            case .scan: return "Find it"
            case .connect: return "Connect"
            case .discover: return "Find the RPC pipe"
            case .readVersion: return "Read the API version"
            case .subscribe: return "Subscribe for answers"
            case .hello: return "Say hello"
            }
        }

        public var detail: String {
            switch self {
            case .scan:
                return "Listen for the robot's service. Nothing is connected to, which is what "
                     + "makes this the thing to try when a duck is not answering."
            case .connect:
                return "Open a link to the one you picked."
            case .discover:
                return "One characteristic carries both directions — write requests to it, and "
                     + "subscribe to the same one for the answers."
            case .readVersion:
                return "Reading it needs a bond, so THIS is what raises the pairing prompt. It "
                     + "must happen before any write: a subscription needs no encryption, so a "
                     + "client that skips this has its first write refused with no error at all."
            case .subscribe:
                return "Answers arrive as notifications on the same characteristic."
            case .hello:
                return "One JSON-RPC call. The robot answers with its API version, daemon "
                     + "version and the revision it was built from."
            }
        }
    }

    /// The one byte a version read returns.
    ///
    /// `btd` answers the read with `vec![API_VERSION as u8]` — a single byte,
    /// not a string and not four bytes. Anything else is not a Microduck
    /// answering, and saying so beats showing a tester a silent failure.
    public static func apiVersion(fromRead data: Data) -> UInt8? {
        data.count == 1 ? data[data.startIndex] : nil
    }

    /// A `hello` request, framed and ready to write.
    ///
    /// NDJSON, NEWLINE-TERMINATED. `framing.rs`: "There is no framing header.
    /// The newline that already separates messages is the frame delimiter, in
    /// both directions. That is safe rather than lucky: `serde_json` escapes a
    /// newline inside a string as `\n`, so a raw `0x0A` never appears inside a
    /// serialised JSON object."
    public static func helloRequest(id: Int = 1) throws -> Data {
        try framed(["jsonrpc": "2.0", "id": id, "method": "hello",
                    "params": ["api_version": apiVersion]])
    }

    /// `system.authenticate`, framed and ready to write.
    ///
    /// THE PIN METHOD, AND THE ONE CALL IN THIS FILE THAT CARRIES A SECRET. Its
    /// params are a single `pin` member and the value is a STRING, not a number:
    /// a factory PIN of `000000` read as an integer is `0`, and a client that
    /// sent `{"pin": 0}` would be refused by a robot that is working perfectly.
    /// That is precisely the kind of invention this used to be — built inline in
    /// the app target where no test could see it — and it is here so the exact
    /// bytes are pinned by `swift test` instead.
    public static func authenticateRequest(pin: String, id: Int) throws -> Data {
        try framed(["jsonrpc": "2.0", "id": id,
                    "method": "system.authenticate", "params": ["pin": pin]])
    }

    /// `system.info`, framed and ready to write.
    ///
    /// NO `params` MEMBER AT ALL, WHICH IS NOT THE SAME AS AN EMPTY ONE. JSON-RPC
    /// 2.0 says `params` MAY be omitted, and `DuckCall.parameters()` already
    /// states this project's rule in as many words: "an empty object is a claim
    /// that the method takes parameters and got none — which is a different thing
    /// to say to a strict deserialiser". This call takes none, so it sends none.
    public static func systemInfoRequest(id: Int) throws -> Data {
        try framed(["jsonrpc": "2.0", "id": id, "method": "system.info"])
    }

    /// One JSON object, sorted, with the newline that frames it.
    ///
    /// SORTED KEYS SO THE BYTES ARE A CONSTANT. A dictionary has no order, so
    /// without `.sortedKeys` the same request would serialise differently from
    /// run to run and a test could only ever check it by parsing it back —
    /// which would pass on a line the robot rejects.
    private static func framed(_ body: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }

    /// Split a line into writes the link will actually carry.
    ///
    /// - Parameter mtu: What CoreBluetooth reports for
    ///   `.withoutResponse`/`.withResponse`, which is already the usable
    ///   payload — do NOT subtract three again.
    ///
    /// `framing.rs`: "usable payload is `ATT_MTU - 3`, which on a phone that
    /// never renegotiates is 20 bytes, and on a good link is a few hundred. So a
    /// line arrives in pieces and leaves in pieces."
    public static func chunks(_ line: Data, mtu: Int) -> [Data] {
        let size = max(mtu, 1)
        return stride(from: 0, to: line.count, by: size).map { start in
            line.subdata(in: start..<min(start + size, line.count))
        }
    }

    /// Reassembles inbound notification chunks into whole NDJSON lines.
    public struct Reassembler {
        private var buffer = Data()

        public init() {}

        /// Why a robot's bytes were rejected.
        public enum Failure: Error, Equatable {
            case lineTooLong
            public var message: String {
                "The duck sent \(DuckLink.maxLine) bytes with no newline in them. That is not "
                + "this protocol, so the link was dropped rather than buffered forever."
            }
        }

        /// Feed one chunk; get back every complete line it completed.
        public mutating func feed(_ chunk: Data) throws -> [Data] {
            buffer.append(chunk)
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                lines.append(buffer.subdata(in: buffer.startIndex..<newline))
                buffer = buffer.subdata(in: buffer.index(after: newline)..<buffer.endIndex)
            }
            // CHECKED AFTER THE SPLIT, NOT BEFORE. A buffer holding several
            // complete lines is not a peer that cannot frame.
            if buffer.count > DuckLink.maxLine {
                buffer.removeAll()
                throw Failure.lineTooLong
            }
            return lines
        }
    }

    // MARK: - who answered

    /// What a duck said about itself.
    public struct Hello: Equatable, Sendable {
        public let apiVersion: UInt32
        /// Absent on a build that predates the field.
        public let daemonVersion: String?
        /// Source revision of the RUNNING binary, or nil "for a build that did
        /// not come from CI (someone's laptop)". Always on the wire, including
        /// as null, so its absence and its nullness are the same thing here.
        public let revision: String?

        public init(apiVersion: UInt32, daemonVersion: String?, revision: String?) {
            self.apiVersion = apiVersion
            self.daemonVersion = daemonVersion
            self.revision = revision
        }
    }

    public enum LinkError: Error, Equatable {
        case notJSON
        /// The robot answered, and it answered with a refusal.
        case robot(code: Int, message: String)
        case unexpected(String)

        public var message: String {
            switch self {
            case .notJSON: return "That was not JSON-RPC coming back."
            case .robot(let code, let text): return "The duck refused: \(text) (\(code))"
            case .unexpected(let what): return what
            }
        }
    }

    /// The `result` member of one NDJSON line, or the refusal it carried.
    ///
    /// ONE PLACE THAT KNOWS WHAT A JSON-RPC ANSWER LOOKS LIKE, so every reader
    /// below treats a refusal the same way. A robot's `error` is not an absence
    /// of data — it is the most useful thing on the line — and a reader that
    /// checked for `result` first would report "nothing came back" about a duck
    /// that said exactly why it was saying no.
    private static func result(ofLine line: Data) throws -> [String: Any] {
        guard let top = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw LinkError.notJSON
        }
        if let error = top["error"] as? [String: Any] {
            throw LinkError.robot(code: error["code"] as? Int ?? 0,
                                  message: error["message"] as? String ?? "no reason given")
        }
        guard let result = top["result"] as? [String: Any] else {
            throw LinkError.unexpected("A JSON-RPC line with neither a result nor an error in it.")
        }
        return result
    }

    /// Read a `hello` answer off one NDJSON line.
    public static func hello(fromLine line: Data) throws -> Hello {
        let result = try result(ofLine: line)
        guard let version = result["api_version"] as? UInt32
                         ?? (result["api_version"] as? Int).map(UInt32.init) else {
            throw LinkError.unexpected("A reply with no api_version in it.")
        }
        return Hello(apiVersion: version,
                     daemonVersion: result["daemon_version"] as? String,
                     revision: result["revision"] as? String)
    }

    // MARK: - who the robot is

    /// What `system.info` said the robot is.
    ///
    /// THE SERIAL IS THE ONLY DURABLE IDENTITY A DUCK HAS, and this is where it
    /// arrives. `app-path-design.md` §8.6 calls it "the durable handle a client
    /// should key on. It outlives a rename, and it outlives a change of
    /// Bluetooth address" — and warns, about this app's exact shortcut, that "an
    /// app that remembers a robot by its peripheral identifier alone will lose
    /// it". See `identifierIsNotAnIdentity`, which says the same thing to a
    /// person.
    public struct SystemInfo: Equatable, Sendable {
        /// The hostname, which is what a rename changes and the serial does not.
        public let name: String
        /// The SoC serial. The identity.
        public let serial: String
        /// How long the robot has been up. Seconds, as the field is spelled.
        public let uptimeSeconds: Int

        public init(name: String, serial: String, uptimeSeconds: Int) {
            self.name = name
            self.serial = serial
            self.uptimeSeconds = uptimeSeconds
        }
    }

    /// Read a `system.info` answer off one NDJSON line.
    ///
    /// EVERY FIELD IS REQUIRED, AND A MISSING ONE IS AN ERROR RATHER THAN A
    /// BLANK. The spike's report says what the robot answered; a `SystemInfo`
    /// with an empty serial in it would print as a robot that named itself and
    /// then be read as one. If the line is not the shape `SystemInfoResult`
    /// describes, this says so and the step is reported as a refusal with those
    /// words in it — which is a finding about this app, and belongs in the
    /// report as one.
    public static func systemInfo(fromLine line: Data) throws -> SystemInfo {
        let result = try result(ofLine: line)
        guard let name = result["name"] as? String,
              let serial = result["serial"] as? String else {
            throw LinkError.unexpected(
                "A system.info result with no name and serial in it. Those two are the answer.")
        }
        // AN INT OR A JSON NUMBER THAT HAPPENS TO CARRY A POINT. `serde_json`
        // serialises a `u64` without one, but a robot that ever grew a
        // fractional uptime would otherwise read as a robot with no uptime at
        // all — which would be reported as a malformed answer from a duck that
        // answered perfectly well.
        let raw = result["uptime_seconds"]
        guard let uptime = raw as? Int ?? (raw as? Double).map(Int.init) else {
            throw LinkError.unexpected("A system.info result with no uptime_seconds in it.")
        }
        return SystemInfo(name: name, serial: serial, uptimeSeconds: uptime)
    }

    // MARK: - filing an answer against the request that asked for it

    /// What a robot's answer was for, and whether it was a refusal.
    ///
    /// BY ID, NOT BY "WHATEVER IS IN FLIGHT". They are the same thing right up
    /// until a request times out, and then they are the difference between a
    /// true report and a fabricated one: a `hello` answer arriving while
    /// `system.authenticate` is in flight would, under dispatch-by-whatever-is-
    /// running, be recorded as an authenticate that succeeded.
    public struct Reply: Equatable, Sendable {
        public let id: Int
        /// The refusal in words, or `nil` for an answer. A robot that says no
        /// has told you the single most useful thing on the line, so it is
        /// carried rather than collapsed into a bool.
        public let trouble: String?

        public init(id: Int, trouble: String?) {
            self.id = id
            self.trouble = trouble
        }
    }

    /// Read the id and any refusal off one NDJSON line.
    ///
    /// - Returns: `nil` for a line this app cannot read at all, which a caller
    ///   must report rather than discard: a line that ARRIVED is not silence,
    ///   and dropping it lets a step run out its budget and be written up as
    ///   "no answer and no error" about a robot that answered.
    public static func reply(fromLine line: Data) -> Reply? {
        guard let top = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = top["id"] as? Int else { return nil }
        guard let error = top["error"] as? [String: Any] else { return Reply(id: id, trouble: nil) }
        let refusal = LinkError.robot(code: error["code"] as? Int ?? 0,
                                      message: error["message"] as? String ?? "no reason given")
        return Reply(id: id, trouble: refusal.message)
    }

    /// The method of a JSON-RPC NOTIFICATION, or `nil` for anything else.
    ///
    /// NOT GARBAGE, AND NOT AN ANSWER TO ANYTHING. JSON-RPC 2.0 defines a
    /// well-formed object with a `method` and no `id` as a notification: the
    /// sender owes no reply and expects none. `reply(fromLine:)` returns `nil`
    /// for it because it carries no id, and the spike used to report that `nil`
    /// as "the duck answered and this app could not read the answer" and refuse
    /// whichever step happened to be in flight — a fabricated refusal about a
    /// robot doing exactly what the protocol allows, filed by whatever was
    /// running, which is the dispatch rule `route` condemns. The BLE subset
    /// Pollen document includes update progress, which is exactly the shape
    /// that arrives this way. A caller asks this first; only a line that is
    /// neither a notification nor a reply is unreadable.
    public static func notificationMethod(fromLine line: Data) -> String? {
        guard let top = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              top["id"] == nil,
              let method = top["method"] as? String else { return nil }
        return method
    }

    /// What to tell somebody about a version difference.
    ///
    /// A MISMATCH IS NEWS, NOT A FAILURE. `architecture.md` §4.2 asks for "one
    /// integer, refuse with a clear message on mismatch" — but that is the
    /// daemon's rule for calls it will not serve, and this app is making one
    /// call that has existed since v1. A tester whose duck is newer than this
    /// build should be told which way round it is, not stopped.
    public static func verdict(for robot: UInt32) -> String {
        if robot == apiVersion {
            return "API version \(robot) — the same one this app was written against."
        }
        if robot > apiVersion {
            return "API version \(robot); this app was written against \(apiVersion). The duck is "
                 + "newer. Hello is answered the same way in both, so this worked — but anything "
                 + "this app has not learned about yet lives on that difference."
        }
        return "API version \(robot); this app was written against \(apiVersion). The duck is "
             + "older, so calls this app might make that arrived after \(robot) would be refused "
             + "by name."
    }

    /// What this screen is for, and what it deliberately is not.
    public static let whatThisCanDo =
        "This finds a real Microduck over Bluetooth and completes the handshake its own daemon "
      + "defines: pair, read the API version, and ask it who it is.\n\n"
      + "It does not drive. BLE carries a deliberate subset — provisioning, status, update "
      + "trigger and progress — and Pollen's architecture notes say outright that it is \"too "
      + "slow and too constrained for the full surface\", with payloads never crossing it. "
      + "Driving a duck waits on the network transports their contract names for later.\n\n"
      + "Nothing here has been run against a robot. Every UUID, byte layout and step order is "
      + "transcribed from btd's source, and the first person to point this at a duck is the "
      + "first person to find out whether that was enough."
}
