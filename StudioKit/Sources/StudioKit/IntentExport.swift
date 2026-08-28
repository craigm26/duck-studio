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
    ///
    /// FORMAT 2 ADDED THE WORLD AND THE PATH. Format 1's own documentation said
    /// it carried "the props it was recorded against" and it did not: it
    /// packaged joint angles, so a recipient opening a shared stair climb saw a
    /// duck marching on the spot in an empty room, with the staircase and every
    /// millimetre of travel left behind on the sender's phone. A motion without
    /// its root is not a motion anybody can judge.
    public static let format = "duck-intent/2"

    /// Still read. A format-1 file is a real motion, and refusing it to keep
    /// the reader tidy would break every intent already shared.
    public static let readableFormats: Set<String> = ["duck-intent/1", "duck-intent/2"]

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
    /// Where the trunk was and how it was oriented, per frame:
    /// `[x, y, z, qw, qx, qy, qz]`. Empty in a format-1 file.
    public let roots: [[Double]]
    /// The props the motion was performed against, in the clip's own frame.
    public let environment: DuckIntentClip.Environment?
    /// What the policy emitted and was asked for, when the sender had it.
    /// Carried because it is what makes the reward panel work on the receiving
    /// phone as well as the sending one.
    public let telemetry: DuckIntentClip.Telemetry

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
        roots = clip.roots.map { [$0.x, $0.y, $0.z, $0.quaternion.0,
                                  $0.quaternion.1, $0.quaternion.2, $0.quaternion.3] }
        environment = clip.environment
        telemetry = clip.telemetry
    }

    /// The motion, ready to play.
    ///
    /// A FORMAT-1 FILE GETS A STANDING ROOT AND SAYS SO. There is nowhere to
    /// recover the path from, so every frame is placed at the origin at
    /// standing height — which is what the sender's app drew anyway. What it
    /// must never do is look like a robot that chose to stand still, so
    /// `hasRecordedPath` is what a screen checks before drawing a trail.
    public var clip: DuckIntentClip {
        let standing = DuckIntentClip.Root(x: 0, y: 0, z: 0.11622, quaternion: (1, 0, 0, 0))
        let path: [DuckIntentClip.Root] = roots.isEmpty
            ? Array(repeating: standing, count: frames.count)
            : roots.map { r in
                DuckIntentClip.Root(
                    x: r.count > 0 ? r[0] : 0, y: r.count > 1 ? r[1] : 0,
                    z: r.count > 2 ? r[2] : 0.11622,
                    quaternion: (r.count > 3 ? r[3] : 1, r.count > 4 ? r[4] : 0,
                                 r.count > 5 ? r[5] : 0, r.count > 6 ? r[6] : 0))
            }
        return DuckIntentClip(
            name: name, hz: hz, frames: frames, roots: path,
            netYaw: netYaw, loops: loops,
            startsFrom: DuckIntentClip.Posture(rawValue: startsFrom) ?? .standing,
            endsIn: DuckIntentClip.Posture(rawValue: endsIn) ?? .standing,
            policy: policyName, authored: authored,
            environment: environment ?? .bareFloor,
            credit: note, telemetry: telemetry)
    }

    /// Whether the sender's file actually said where the robot went.
    public var hasRecordedPath: Bool { roots.count == frames.count && !roots.isEmpty }

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
        if !roots.isEmpty { object["roots"] = roots }
        if let environment {
            object["environment"] = [
                "ground": environment.ground, "yaw": environment.yaw,
                "steps": environment.steps.map {
                    ["x": $0.x, "y": $0.y, "top": $0.top, "halfDepth": $0.halfDepth,
                     "halfWidth": $0.halfWidth, "halfHeight": $0.halfHeight]
                },
                "walls": environment.walls.map {
                    ["x": $0.x, "y": $0.y, "halfThickness": $0.halfThickness,
                     "height": $0.height, "halfLength": $0.halfLength]
                },
            ]
        }
        if !telemetry.isEmpty {
            object["actions"] = telemetry.actions
            object["commands"] = telemetry.commands
            object["twists"] = telemetry.twists
        }
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
        guard Self.readableFormats.contains(format) else {
            throw ImportError.unsupportedFormat(format)
        }
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
            note: object["note"] as? String,
            // A root array of the wrong length is DROPPED rather than padded.
            // Padding would place the tail of the motion at the origin, which
            // draws a robot that walks and then snaps back — a plausible-looking
            // lie about where it ended up.
            roots: {
                let raw = object["roots"] as? [[Double]] ?? []
                return raw.count == frames.count ? raw : []
            }(),
            environment: decodeEnvironment(object["environment"] as? [String: Any]),
            telemetry: {
                let actions = object["actions"] as? [[Double]] ?? []
                let commands = object["commands"] as? [[Double]] ?? []
                let twists = object["twists"] as? [[Double]] ?? []
                guard actions.count == frames.count else { return .none }
                return .init(actions: actions, commands: commands, twists: twists)
            }())
    }

    init(name: String, hz: Double, frames: [[Double]], netYaw: Double, loops: Bool,
         startsFrom: String, endsIn: String, policyName: String,
         policyFingerprint: String?, authored: Bool, note: String?,
         roots: [[Double]] = [], environment: DuckIntentClip.Environment? = nil,
         telemetry: DuckIntentClip.Telemetry = .none) {
        self.name = name; self.hz = hz; self.frames = frames; self.netYaw = netYaw
        self.loops = loops; self.startsFrom = startsFrom; self.endsIn = endsIn
        self.policyName = policyName; self.policyFingerprint = policyFingerprint
        self.authored = authored; self.note = note
        self.roots = roots; self.environment = environment; self.telemetry = telemetry
    }

    /// The props, read back out of a shared file.
    ///
    /// A LOCAL DECODER RATHER THAN DUCKKIT'S. DuckKit's own is internal to the
    /// clip decoder, and reaching for it would mean widening that package's
    /// surface so this one can read a slightly different file. Sizes fall back
    /// to the recorder's own defaults, which is what a prop written by an older
    /// exporter omits.
    static func decodeEnvironment(_ raw: [String: Any]?) -> DuckIntentClip.Environment? {
        guard let raw else { return nil }
        let steps = (raw["steps"] as? [[String: Any]] ?? []).compactMap {
            s -> DuckIntentClip.Environment.Step? in
            guard let x = s["x"] as? Double, let y = s["y"] as? Double,
                  let top = s["top"] as? Double else { return nil }
            return .init(x: x, y: y, top: top,
                         halfDepth: s["halfDepth"] as? Double ?? 0.17,
                         halfWidth: s["halfWidth"] as? Double ?? 0.17,
                         halfHeight: s["halfHeight"] as? Double ?? 0.10)
        }
        let walls = (raw["walls"] as? [[String: Any]] ?? []).compactMap {
            w -> DuckIntentClip.Environment.Wall? in
            guard let x = w["x"] as? Double, let y = w["y"] as? Double else { return nil }
            return .init(x: x, y: y,
                         halfThickness: w["halfThickness"] as? Double ?? 0.025,
                         height: w["height"] as? Double ?? 0.6,
                         halfLength: w["halfLength"] as? Double ?? 1.5)
        }
        return .init(ground: raw["ground"] as? Bool ?? true,
                     yaw: raw["yaw"] as? Double ?? 0, steps: steps, walls: walls)
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
