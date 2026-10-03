import Foundation

/// The duck's own camera, read straight from the robot's media daemon.
///
/// WHAT THE ROBOT SERVES. Pollen's `mediad` serves its console on port 8080 and, beside it,
/// `GET /frame`: one PNG of what the head camera sees, upright (the mount's quarter turn already
/// undone), uncached, with a 503 and a plain sentence when capture is not running
/// (`mediad/src/web.rs`, pollen-robotics/microduck ded2f7c). A phone that asks for it a few times a
/// second has a live-enough picture with no WebRTC client at all, and the full-rate video stays
/// one tap away in the console.
///
/// THE SAME PAGE ON A SIMULATED DUCK. Pollen's `scripts/duck-sim` gives each duck with a camera
/// its own `mediad` (`DUCK_SIM_CAMERAS=a`), console on 8080, 8081, ... by index, rendering what the
/// MuJoCo duck's head would see. So one address field covers a robot on the floor and a duck in
/// a simulator on a laptop: the host, and the port when it is not 8080.
public enum DuckCamera {

    public static let defaultPort = 8080

    /// Where a camera is: a host and a port.
    public struct Address: Equatable, Sendable {
        public let host: String
        public let port: Int

        /// `duck.local`, `192.168.1.40`, `192.168.1.40:8081`. Nil for anything that is not a host
        /// and an optional port: a path, a scheme, spaces, a port out of range.
        public init?(_ typed: String) {
            var text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            for scheme in ["http://", "https://"] where text.lowercased().hasPrefix(scheme) {
                text = String(text.dropFirst(scheme.count))
            }
            if text.hasSuffix("/") { text.removeLast() }
            guard !text.isEmpty, !text.contains("/"), !text.contains(" ") else { return nil }
            var host = text, port = DuckCamera.defaultPort
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { return nil }
            if parts.count == 2 {
                guard let p = Int(parts[1]), (1...65535).contains(p) else { return nil }
                host = String(parts[0]); port = p
            }
            guard !host.isEmpty, host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." })
            else { return nil }
            self.host = host
            self.port = port
        }

        public init(host: String, port: Int = DuckCamera.defaultPort) {
            self.host = host; self.port = port
        }

        private var authority: String { "\(host):\(port)" }

        /// The still: one PNG per request.
        public var frameURL: URL? { URL(string: "http://\(authority)/frame") }
        /// The robot's own console: full-rate video and its control channel, in a browser.
        public var consoleURL: URL? { URL(string: "http://\(authority)/") }
        public var said: String { "\(host):\(port)" }
    }

    /// What one request for a frame came to.
    public enum Frame: Equatable, Sendable {
        case picture(Data)
        /// The robot answered and has no picture: capture is not running yet.
        case notCapturing(String)
        /// Something answered that is not a duck's camera.
        case notACamera(Int)
    }

    /// PNG's eight-byte signature.
    static let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// Read one answer to `GET /frame`.
    public static func read(status: Int, body: Data) -> Frame {
        switch status {
        case 200 where body.starts(with: png):
            return .picture(body)
        case 503:
            let said = String(decoding: body.prefix(200), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .notCapturing(said.isEmpty ? Words.notCapturing : said)
        default:
            return .notACamera(status)
        }
    }

    /// How often a still is asked for. A frame is a PNG encoded on the robot, and `mediad` holds
    /// four encoders at once; four a second is a live-enough picture that leaves three of them
    /// for anybody else watching.
    public static let interval: TimeInterval = 0.25
    /// A request slower than this is a camera that is not there.
    public static let timeout: TimeInterval = 3

    public enum Words {
        public static let heading = "Camera"
        public static let addressPlaceholder = "duck.local or 192.168.1.40:8080"
        public static let footer =
            "What your duck's head camera sees, a few frames a second. A duck in Pollen's "
          + "simulator works the same way: use the computer's address and the port duck-sim "
          + "printed (8080 for the first duck)."
        public static let notCapturing =
            "The duck answered, but its camera is not capturing yet. Try again in a moment."
        public static func notACamera(_ status: Int) -> String {
            "Something answered at that address (HTTP \(status)), but it is not a duck's camera. "
          + "Check the address and the port."
        }
        public static func unreachable(_ address: String) -> String {
            "Nothing answered at \(address). Check the duck is on and on this network."
        }
        public static let notAnAddress = "That is not an address. Type a host, and a port if it is not 8080."
        public static let start = "Show the camera"
        public static let stop = "Stop the camera"
        public static let liveVideo = "Open live video in Safari"
        public static func rate(_ fps: Double) -> String { String(format: "%.1f frames a second", fps) }
    }
}
