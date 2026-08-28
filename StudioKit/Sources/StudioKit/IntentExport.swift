import Foundation
import DuckKit

/// One intent, packaged so somebody else can open it.
///
/// WHAT A SHARED MOTION HAS TO CARRY. A bare list of joint angles is not
/// shareable in any useful sense: a recipient cannot tell what it was recorded
/// from, what it was performed against, or whether it worked. So the package
/// carries the frames, the policy it came from BY FINGERPRINT as well as by
/// filename, the props it was recorded against, and the measured postures —
/// which is where "this one falls over" lives.
///
/// THE FINGERPRINT IS THE POINT, AND IT IS ALSO THE LIMIT. Naming the source
/// policy by digest lets a recipient check whether they hold the same network,
/// which a filename cannot do — anyone can call a file `alpha_walking.onnx`.
/// What it does NOT do is establish who made the motion or whether it is safe.
/// A signature would say a key signed the bytes, and without an independent way
/// to anchor that key it would say nothing a recipient can act on. So this
/// package makes the checkable claim and declines the unverifiable one.
public struct IntentExport: Equatable, Sendable {

    /// Bumped when the shape changes in a way an older reader would misread.
    public static let format = "duck-intent/1"

    public let name: String
    public let hz: Double
    /// 14 policy joints per frame, mouth excluded — the shape every exported
    /// intent on disk already uses.
    public let frames: [[Double]]
    public let netYaw: Double
    public let loops: Bool
    public let startsFrom: String
    public let endsIn: String
    /// The file the source policy was called. A hint; the digest is the claim.
    public let policyName: String
    /// SHA-256 over the source policy's parameters, when the exporter holds it.
    public let policyFingerprint: String?
    public let authored: Bool
    public let note: String?

    public init(clip: DuckIntentClip, policyFingerprint: String?, note: String? = nil) {
        name = clip.name
        hz = clip.hz
        frames = clip.frames
        netYaw = clip.netYaw
        loops = clip.loops
        startsFrom = clip.startsFrom.rawValue
        endsIn = clip.endsIn.rawValue
        policyName = clip.policy
        self.policyFingerprint = policyFingerprint
        authored = clip.authored
        self.note = note
    }

    /// A filename a person will recognise in a Files listing or a chat.
    ///
    /// Extension is `.duckintent` rather than `.json` so the system can offer
    /// this app for it, and so a recipient can tell at a glance that it is a
    /// motion and not a network — the two are the thing this app most wants
    /// people not to confuse.
    public var suggestedFilename: String { "\(name).duckintent" }

    public func encoded() throws -> Data {
        var object: [String: Any] = [
            "format": Self.format,
            "name": name, "hz": hz, "frames": frames,
            "netYaw": netYaw, "loops": loops,
            "startsFrom": startsFrom, "endsIn": endsIn,
            "policy": policyName, "authored": authored,
        ]
        if let policyFingerprint { object["policyFingerprint"] = policyFingerprint }
        if let note { object["note"] = note }
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    public enum ImportError: Error, Equatable {
        case notAnIntent
        case unsupportedFormat(String)
        case noFrames
        case wrongJointCount(frame: Int, got: Int)

        public var message: String {
            switch self {
            case .notAnIntent:
                return "That file is not a shared intent."
            case .unsupportedFormat(let f):
                return "This intent is in format \"\(f)\", which this version does not read."
            case .noFrames:
                return "The intent has no frames, so there is no motion in it."
            case .wrongJointCount(let frame, let got):
                return "Frame \(frame) has \(got) joints; a motion carries "
                     + "\(DuckModel.policyJointCount), the policy's joints with the mouth left out."
            }
        }
    }

    /// Read one somebody sent. Throws rather than traps, because every input
    /// here arrived from outside.
    public static func decode(_ data: Data) throws -> IntentExport {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.notAnIntent
        }
        guard let format = object["format"] as? String else { throw ImportError.notAnIntent }
        guard format == Self.format else { throw ImportError.unsupportedFormat(format) }
        guard let frames = object["frames"] as? [[Double]], !frames.isEmpty else {
            throw ImportError.noFrames
        }
        for (index, frame) in frames.enumerated() where frame.count != DuckModel.policyJointCount {
            throw ImportError.wrongJointCount(frame: index, got: frame.count)
        }
        return IntentExport(
            name: object["name"] as? String ?? "shared intent",
            hz: object["hz"] as? Double ?? DuckModel.tickHz,
            frames: frames,
            netYaw: object["netYaw"] as? Double ?? 0,
            loops: object["loops"] as? Bool ?? false,
            startsFrom: object["startsFrom"] as? String ?? "standing",
            endsIn: object["endsIn"] as? String ?? "standing",
            policyName: object["policy"] as? String ?? "unknown",
            policyFingerprint: object["policyFingerprint"] as? String,
            authored: object["authored"] as? Bool ?? false,
            note: object["note"] as? String)
    }

    init(name: String, hz: Double, frames: [[Double]], netYaw: Double, loops: Bool,
         startsFrom: String, endsIn: String, policyName: String,
         policyFingerprint: String?, authored: Bool, note: String?) {
        self.name = name; self.hz = hz; self.frames = frames; self.netYaw = netYaw
        self.loops = loops; self.startsFrom = startsFrom; self.endsIn = endsIn
        self.policyName = policyName; self.policyFingerprint = policyFingerprint
        self.authored = authored; self.note = note
    }

    /// What to tell a recipient about where this came from.
    ///
    /// Deliberately says what the fingerprint DOES and DOES NOT establish. A
    /// package that only said "from alpha_walking.onnx" would invite the reader
    /// to treat a filename as provenance.
    public func provenanceSentence(recipientHoldsPolicy: Bool?) -> String {
        guard policyFingerprint != nil else {
            return "Recorded from a policy named \(policyName). No digest was included, "
                 + "so there is no way to check which network that was."
        }
        switch recipientHoldsPolicy {
        case .some(true):
            return "Recorded from \(policyName), and you have that exact network — the "
                 + "digest matches."
        case .some(false):
            return "Recorded from a network you do not have. The digest does not match any "
                 + "policy in your library, so you cannot reproduce this motion here."
        case .none:
            return "Recorded from \(policyName), identified by digest. Import that policy to "
                 + "check you have the same one."
        }
    }
}
