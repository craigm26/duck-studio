import Foundation
import DuckKit
import Crypto

/// One policy file, on its way to a robot's disk through the bridge.
///
/// THE DIGEST TRAVELS WITH THE BYTES AND THE BRIDGE CHECKS IT. A network that
/// arrived one byte short would still load and still drive the servos with
/// whatever those bytes mean, so the bridge refuses to write anything whose
/// digest is not the one claimed here — and this app claims the digest of
/// exactly the bytes it is sending, computed here, not copied from anywhere.
///
/// WHAT INSTALLING DOES AND DOES NOT DO, in the bridge's own words: the file
/// lands under `--policy-dir`; a `slot` points one `[policy]` key in
/// `robotd.toml` at it when the bridge was given the config, with a backup
/// written first; and NOTHING takes effect until robotd next starts, which the
/// bridge does not do. `Outcome.said` repeats that, because a screen that
/// printed "installed" and stopped would be claiming the duck was running it.
public struct DuckPolicyInstall: Equatable, Sendable {
    public let name: String
    public let bytes: Data
    public let sha256: String
    public let slot: String?

    public init(name: String, bytes: Data, slot: String? = nil) {
        self.name = name
        self.bytes = bytes
        self.sha256 = DuckPolicyInstall.digest(of: bytes)
        self.slot = slot
    }

    /// The stem the file gets on the robot, from whatever a policy is called
    /// here. The bridge's own rule — letters, digits, dots, dashes and
    /// underscores, up to 64, starting with a letter or digit — applied so a
    /// title like "alpha_walking, searched 09-06 07:39" arrives as a filename
    /// rather than a refusal.
    public static func fileName(for title: String) -> String {
        var out = ""
        for character in title.lowercased() {
            if character.isASCII && (character.isLetter || character.isNumber) {
                out.append(character)
            } else if character == "." || character == "_" || character == "-" {
                out.append(character)
            } else if !out.hasSuffix("-") && !out.isEmpty {
                out.append("-")
            }
        }
        if out.lowercased().hasSuffix(".onnx") { out = String(out.dropLast(5)) }
        while out.hasSuffix("-") || out.hasSuffix(".") { out.removeLast() }
        while let first = out.first, !(first.isLetter || first.isNumber) { out.removeFirst() }
        if out.count > 64 { out = String(out.prefix(64)) }
        return out.isEmpty ? "policy" : out
    }

    public static func digest(of bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// The JSON-RPC params, with the bytes base64 in a field named `bytes`.
    var wire: [String: Any] {
        var params: [String: Any] = ["name": name, "sha256": sha256,
                                     "bytes": bytes.base64EncodedString()]
        if let slot { params["slot"] = slot }
        return params
    }

    /// The instance `DuckCall.allShapes` carries: one byte, so the routing
    /// tests can send it everywhere and read the refusals.
    static let shape = DuckPolicyInstall(name: "shape", bytes: Data([0]))

    // MARK: - what came back

    public struct Outcome: Equatable, Sendable {
        public struct Slot: Equatable, Sendable {
            public let asked: String
            public let applied: Bool
            public let why: String?
            public let backup: String?
        }
        public let installed: String
        public let sha256: String
        public let bytes: Int
        public let takesEffect: String
        public let slot: Slot?

        /// The sentence the screen prints, which never stops at "installed".
        public var said: String {
            var lines = ["Installed as \(installed) (\(bytes) bytes, sha256 \(sha256.prefix(12))…)."]
            if let slot {
                if slot.applied {
                    lines.append("The [policy] \(slot.asked) key now names it"
                                 + (slot.backup.map { "; the previous robotd.toml is at \($0)." } ?? "."))
                } else {
                    lines.append("The \(slot.asked) slot was not changed: \(slot.why ?? "no reason given")")
                }
            }
            lines.append("It takes effect \(takesEffect).")
            return lines.joined(separator: " ")
        }
    }

    public enum ReadError: Error, Equatable {
        case refused(String)
        case notAnInstallAnswer
        public var message: String {
            switch self {
            case .refused(let why): return "The bridge refused: \(why)"
            case .notAnInstallAnswer:
                return "The bridge answered, but not with what policy.install answers with."
            }
        }
    }

    public static func read(_ reply: DuckReply) throws -> Outcome {
        if let failure = reply.failure { throw ReadError.refused(failure.message) }
        guard let installed: String = reply.field("installed"),
              let digest: String = reply.field("sha256"),
              let count: Int = reply.field("bytes"),
              let effect: String = reply.field("takes_effect") else {
            throw ReadError.notAnInstallAnswer
        }
        var slot: Outcome.Slot?
        if let raw: [String: Any] = reply.field("slot") {
            slot = Outcome.Slot(asked: raw["asked"] as? String ?? "",
                                applied: raw["applied"] as? Bool ?? false,
                                why: raw["why"] as? String,
                                backup: raw["backup"] as? String)
        }
        return Outcome(installed: installed, sha256: digest, bytes: count,
                       takesEffect: effect, slot: slot)
    }

    // MARK: - what the screen says before it sends

    public static let whatInstallDoes =
        "Sends the file to the bridge on the robot's computer, which writes it where robotd "
      + "loads policies from and checks the digest before it does. Nothing runs it: robotd "
      + "reads its policies when it starts, so the network is on the robot's disk and not on "
      + "its servos until robotd is restarted — which this app does not do."

    public static let bridgeCannotInstall =
        "This bridge was started without a policy directory, so it cannot install anything. "
      + "Restart it with --policy-dir pointing at the folder robotd loads policies from, and "
      + "--robotd-toml if a slot should be pointed at the file."

    public static let neverRunOnHardware =
        "A network made on this phone has never run on hardware. The first time it does is "
      + "the first time anybody finds out what it does with 15 real servos. Stand clear, keep "
      + "the pad's stop under a thumb, and expect a fall."
}
