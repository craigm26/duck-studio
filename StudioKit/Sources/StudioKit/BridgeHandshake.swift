import Foundation

/// The first line a client sends a `microduck-bridge`, and what comes back.
///
/// WHY THE KIT OWNS IT. The bridge is a program in this repo (`bridge/`) and
/// the app is its only client, so the handshake is a contract with exactly two
/// ends and both of them are ours. Written here it can be tested on Linux, and
/// the app cannot spell it differently from the program it is talking to.
///
/// WHAT THE HANDSHAKE IS FOR, AND WHAT IT IS NOT. It authorises a relay. It is
/// not authentication of a person, not encryption, and not a boundary anybody
/// should rely on: the token keeps a television out of a robot, and does not
/// stop somebody who can read the same Wi-Fi. `tokenIsNotSecurity` says so on
/// the screen that asks for it, because a person deciding where to run a robot
/// deserves to know which of those two things they have.
public enum BridgeHandshake {

    /// The version this app speaks. The bridge refuses anything else by name
    /// rather than guessing, and so does this.
    public static let version = "v1"

    /// The line to send, first, before anything else on the connection.
    public static func hello(token: String) -> Data {
        // KEY ORDER IS FIXED because the bridge reads JSON and a person reads
        // the log line; neither is helped by two spellings of one greeting.
        let body = "{\"microduck\":\"\(version)\",\"token\":\"\(escaped(token))\"}\n"
        return Data(body.utf8)
    }

    /// What the bridge says back when it has accepted the relay.
    public struct Greeting: Equatable, Sendable {
        /// The bridge's own version string, for the log and for a person
        /// reading a bug report.
        public let bridge: String
        /// How long the bridge will let this client go quiet before it sends
        /// the robot a stop. NIL WHEN THE BRIDGE DID NOT SAY: an app that
        /// assumed a default here would draw a promise nobody made.
        public let deadmanMilliseconds: Int?

        public init(bridge: String, deadmanMilliseconds: Int?) {
            self.bridge = bridge
            self.deadmanMilliseconds = deadmanMilliseconds
        }
    }

    public enum Refusal: Error, Equatable {
        case notJSON
        case wrongVersion(String)
        case refused(String)
        case noToken

        public var message: String {
            switch self {
            case .notJSON:
                return "That answered, but not with anything this app can read. It may not be a "
                     + "Microduck bridge — check the address and the port."
            case .wrongVersion(let found):
                return "That bridge speaks \(found) and this app speaks \(BridgeHandshake.version). "
                     + "Update whichever is older; the bridge is one file in the app's repo."
            case .refused(let why):
                return "The bridge refused: \(why)"
            case .noToken:
                return "A bridge needs the token it printed when it was installed. Run "
                     + "install.sh on the robot's machine again if nobody wrote it down — it "
                     + "prints the same token it already has."
            }
        }
    }

    /// Read the bridge's answer to a hello.
    ///
    /// THE ERROR SHAPE IS THE BRIDGE'S OWN. It answers a refusal as
    /// `{"error": "..."}` and an acceptance as a greeting, so this reads for
    /// the refusal first: a client that checked for its own success key first
    /// would report "not a bridge" for a bridge that answered perfectly well
    /// and said no.
    public static func read(_ line: Data) throws -> Greeting {
        guard let top = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            throw Refusal.notJSON
        }
        if let why = top["error"] as? String { throw Refusal.refused(why) }
        guard let version = top["microduck"] as? String else { throw Refusal.notJSON }
        guard version == BridgeHandshake.version else { throw Refusal.wrongVersion(version) }
        return Greeting(bridge: top["bridge"] as? String ?? "unnamed",
                        deadmanMilliseconds: top["deadman_ms"] as? Int)
    }

    /// What the bridge advertises itself as, for a Bonjour browse.
    public static let bonjourType = "_robotd._tcp"
    public static let defaultPort = 7788

    // MARK: - the sentences

    public static let tokenIsNotSecurity =
        "The token keeps a television and a housemate's laptop out of your robot. It is not a "
      + "security boundary and it does not stop anybody who can read the same Wi-Fi — the bridge "
      + "binds to your own network, and nothing about it should be port-forwarded."

    public static let whatABridgeIs =
        "A bridge is a small program on the machine your robot's software runs on. It moves bytes "
      + "between this app and robotd, which listens on a socket a phone cannot open, and it sends "
      + "the robot a stop if this app goes quiet."

    /// The deadman, named with the number the bridge reported rather than one
    /// this app assumed.
    public static func deadmanSaid(_ milliseconds: Int?) -> String {
        guard let milliseconds else {
            return "This bridge did not say whether it runs a deadman, so this app does not claim "
                 + "one. A robot that keeps walking when the link drops is the failure the "
                 + "simulator gives us for free and hardware does not."
        }
        return "If this app goes quiet for \(milliseconds) ms — a pocket, a dropped network, a "
             + "crash — the bridge sends the robot a stop. It cannot act if the bridge itself "
             + "dies, which is what robotd's own deadman is under it."
    }

    /// Every sentence, so a screen can be checked against it.
    public static let everySentence: [String] = [
        tokenIsNotSecurity, whatABridgeIs, deadmanSaid(700), deadmanSaid(nil),
    ]

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
