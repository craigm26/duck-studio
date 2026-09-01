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

        public init(name: String, rssi: Int?, address: Address) {
            self.name = name
            self.rssi = rssi
            self.address = address
        }
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
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": "hello",
                                   "params": ["api_version": apiVersion]]
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

    /// Read a `hello` answer off one NDJSON line.
    public static func hello(fromLine line: Data) throws -> Hello {
        guard let top = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw LinkError.notJSON
        }
        if let error = top["error"] as? [String: Any] {
            throw LinkError.robot(code: error["code"] as? Int ?? 0,
                                  message: error["message"] as? String ?? "no reason given")
        }
        guard let result = top["result"] as? [String: Any],
              let version = result["api_version"] as? UInt32
                         ?? (result["api_version"] as? Int).map(UInt32.init) else {
            throw LinkError.unexpected("A reply with no api_version in it.")
        }
        return Hello(apiVersion: version,
                     daemonVersion: result["daemon_version"] as? String,
                     revision: result["revision"] as? String)
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
