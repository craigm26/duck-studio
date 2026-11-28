import Foundation
import DuckKit

/// One pose, kept by name so it can be used again.
///
/// THE FOURTH WORD, BESIDE POLICY, MOTION AND SEQUENCE. A **pose** is one
/// moment: every joint at an angle, and nothing about time. A motion is a
/// track of poses; a pose is what a person builds by grabbing joints on the
/// picture and wants to keep without committing to a track. Before this type a
/// built pose could only be held on the bench or turned into a two-keyframe
/// motion, so the same "wing up" got rebuilt by hand every time.
///
/// WHY POSES ARE NAMED: THEY ARE THE CHAT'S VOCABULARY. A language model is a
/// poor author of fourteen joint angles and a good picker from a list. Saved
/// poses with a one-line description turn "wave at the dog" into a choice
/// between "wing up" and "wing down", which `MotionProposal` resolves against
/// this library and clamps exactly as it does a typed angle.
///
/// THE FILE KEYS ANGLES BY JOINT NAME, NOT BY POSITION. The same file is read
/// by the iPhone app and by the desktop app, which is not Swift. A bare array
/// is an off-by-one waiting for the second reader; `"left_knee": -0.4` is not.
public struct DuckPose: Equatable, Sendable, Identifiable {

    public static let format = "duck-pose/1"
    public static let readableFormats: Set<String> = ["duck-pose/1"]
    public static let fileExtension = "duckpose"

    /// How the pose came to exist. Shown, never a time base or a judgement.
    public enum Source: Equatable, Sendable {
        /// Built by hand on the picture.
        case posed
        /// Taken from one moment of a motion.
        case motionFrame(motion: String, atSeconds: Double)
        /// Made from another pose: mirrored, or between two.
        case derived(String)
    }

    public let id: UUID
    public var name: String
    /// One line, for people and for the chat: "right wing raised, for greetings".
    public var about: String
    /// Radians, `DuckModel.jointNames` order, always `jointCount` long and
    /// always inside `DuckModel.jointRanges`.
    public let angles: [Double]
    public let madeAt: Date
    public let source: Source

    /// CLAMPED AND PADDED ON THE WAY IN, so no pose in a library can hold an
    /// angle the robot cannot reach, whichever reader or writer made it. A
    /// short array is filled from the home pose rather than refused: a file
    /// written by a reader that forgot the mouth is still a real pose.
    public init(id: UUID = UUID(), name: String, about: String = "", angles: [Double],
                madeAt: Date = Date(), source: Source = .posed) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.about = about.trimmingCharacters(in: .whitespacesAndNewlines)
        self.angles = Self.clamped(angles)
        self.madeAt = madeAt
        self.source = source
    }

    static func clamped(_ raw: [Double]) -> [Double] {
        (0..<DuckModel.jointCount).map { index in
            let value = index < raw.count && raw[index].isFinite ? raw[index] : DuckModel.homePose[index]
            let range = DuckModel.jointRanges[index]
            return min(max(value, range.lower), range.upper)
        }
    }

    // MARK: - making one pose from another

    /// The same pose with left and right swapped.
    ///
    /// THE RIGHT LEG IS THE LEFT WITH EVERY SIGN FLIPPED — the home pose says so
    /// joint for joint — so a mirrored leg is the other leg's angle negated. The
    /// head turns and tilts the other way; the neck, nod and beak are on the
    /// centre line and stay put. Clamped again, because the two hip-yaw ranges
    /// are not quite mirror images.
    public func mirrored(named: String? = nil) -> DuckPose {
        var out = angles
        for offset in 0..<5 {
            out[offset] = -angles[10 + offset]
            out[10 + offset] = -angles[offset]
        }
        out[7] = -angles[7]   // head_yaw
        out[8] = -angles[8]   // head_roll
        return DuckPose(name: named ?? "\(name) mirrored", about: about, angles: out,
                        source: .derived("mirror of \(name)"))
    }

    /// A pose part of the way from `a` to `b`. `t` is clamped to 0…1.
    public static func between(_ a: DuckPose, _ b: DuckPose, t: Double,
                               named: String? = nil) -> DuckPose {
        let k = min(max(t, 0), 1)
        let angles = zip(a.angles, b.angles).map { $0 + ($1 - $0) * k }
        let percent = Int((k * 100).rounded())
        return DuckPose(name: named ?? "\(a.name) to \(b.name) \(percent)%",
                        angles: angles,
                        source: .derived("\(percent)% of the way from \(a.name) to \(b.name)"))
    }

    /// One moment of a motion, kept as a pose.
    public static func frame(of draft: IntentDraft, at seconds: Double,
                             named: String) -> DuckPose? {
        let keys = draft.keys.sorted { $0.time < $1.time }
        guard let first = keys.first else { return nil }
        var pose = first.pose
        if seconds >= (keys.last?.time ?? 0) {
            pose = keys.last!.pose
        } else if let next = keys.firstIndex(where: { $0.time > seconds }), next > 0 {
            let a = keys[next - 1], b = keys[next]
            let span = b.time - a.time
            let k = span > 0 ? (seconds - a.time) / span : 0
            pose = zip(a.pose, b.pose).map { $0 + ($1 - $0) * k }
        }
        return DuckPose(name: named, angles: pose,
                        source: .motionFrame(motion: draft.name, atSeconds: seconds))
    }

    // MARK: - saying what it is

    /// The joints that are away from standing, in the chat's own words:
    /// "neck +20°, left knee -35°". "Standing" when nothing is.
    public var summary: String {
        let moved = MotionProposal.jointVocabulary.compactMap { entry -> String? in
            guard let index = DuckModel.jointIndex(of: entry.joint) else { return nil }
            let degrees = (angles[index] - DuckModel.homePose[index]) * 180 / .pi
            let rounded = Int(degrees.rounded())
            guard abs(rounded) >= 2 else { return nil }
            return "\(entry.word) \(rounded > 0 ? "+" : "")\(rounded)°"
        }
        return moved.isEmpty ? "standing" : moved.joined(separator: ", ")
    }

    public var sourceSentence: String {
        switch source {
        case .posed: return "Posed by hand."
        case .motionFrame(let motion, let at):
            return String(format: "Taken from \"%@\" at %.1f s.", motion, at)
        case .derived(let how): return "Made as the \(how)."
        }
    }

    // MARK: - the file

    public var fileName: String { "\(id.uuidString).\(Self.fileExtension)" }

    public func encoded() throws -> Data {
        var named: [String: Double] = [:]
        for (index, joint) in DuckModel.jointNames.enumerated() { named[joint] = angles[index] }
        var object: [String: Any] = [
            "format": Self.format,
            "id": id.uuidString,
            "name": name,
            "about": about,
            "units": "radians",
            "angles": named,
            "madeAt": madeAt.timeIntervalSince1970,
        ]
        switch source {
        case .posed:
            object["source"] = ["kind": "posed"]
        case .motionFrame(let motion, let at):
            object["source"] = ["kind": "motionFrame", "motion": motion, "atSeconds": at]
        case .derived(let how):
            object["source"] = ["kind": "derived", "how": how]
        }
        return try JSONSerialization.data(withJSONObject: object,
                                          options: [.prettyPrinted, .sortedKeys])
    }

    public enum ReadError: Error, Equatable {
        case notJSON
        case missing(String)
        case wrongFormat(String)
        case unknownJoint(String)

        public var message: String {
            switch self {
            case .notJSON: return "This file is not a pose: it is not JSON."
            case .missing(let what): return "This pose file has no \(what)."
            case .wrongFormat(let format):
                return "This pose file is \(format), which this version cannot read."
            case .unknownJoint(let joint):
                return "This pose names \"\(joint)\", which is not a joint this robot has."
            }
        }
    }

    /// A joint the file leaves out stays at standing. A joint it names that
    /// does not exist is refused: that file was written for some other robot.
    public static func decode(_ data: Data) throws -> DuckPose {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        guard let format = top["format"] as? String else { throw ReadError.missing("format") }
        guard readableFormats.contains(format) else { throw ReadError.wrongFormat(format) }
        guard let name = top["name"] as? String else { throw ReadError.missing("name") }
        guard let named = top["angles"] as? [String: Any] else { throw ReadError.missing("angles") }
        var angles = DuckModel.homePose
        for (joint, value) in named {
            guard let index = DuckModel.jointIndex(of: joint) else {
                throw ReadError.unknownJoint(joint)
            }
            if let number = value as? Double { angles[index] = number }
            else if let number = value as? Int { angles[index] = Double(number) }
        }
        let told = top["source"] as? [String: Any] ?? [:]
        let source: Source
        switch told["kind"] as? String {
        case "motionFrame":
            source = .motionFrame(motion: told["motion"] as? String ?? "a motion",
                                  atSeconds: told["atSeconds"] as? Double ?? 0)
        case "derived":
            source = .derived(told["how"] as? String ?? "another pose")
        default:
            source = .posed
        }
        return DuckPose(
            id: (top["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID(),
            name: name,
            about: top["about"] as? String ?? "",
            angles: angles,
            madeAt: Date(timeIntervalSince1970: top["madeAt"] as? Double ?? 0),
            source: source)
    }
}

/// What a set of saved poses can do together: be found by name, be offered to
/// the chat, and be strung into a motion.
public enum PoseLibrary {

    /// How many poses the chat is told about. A small on-device model's context
    /// is short and a long list crowds out the joints; the newest are offered.
    public static let offeredToTheChat = 24

    /// Case, underscores, hyphens and doubled spaces do not make a different
    /// name: "Wing_Up" is "wing up".
    public static func normalised(_ raw: String) -> String {
        var word = raw.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while word.contains("  ") { word = word.replacingOccurrences(of: "  ", with: " ") }
        return word
    }

    public static func find(_ name: String, in poses: [DuckPose]) -> DuckPose? {
        let wanted = normalised(name)
        guard !wanted.isEmpty else { return nil }
        return poses.first { normalised($0.name) == wanted }
    }

    /// The nearest saved name, for a refusal — or nil when nothing is near,
    /// because a wrong hint is worse than none.
    public static func closest(to name: String, in poses: [DuckPose]) -> String? {
        let wanted = normalised(name)
        guard !wanted.isEmpty else { return nil }
        if let contains = poses.first(where: {
            let have = normalised($0.name)
            return have.contains(wanted) || wanted.contains(have)
        }) { return contains.name }
        let allowed = max(2, wanted.count / 3)
        let best = poses.min {
            MotionProposal.editDistance(normalised($0.name), wanted)
                < MotionProposal.editDistance(normalised($1.name), wanted)
        }
        if let best, MotionProposal.editDistance(normalised(best.name), wanted) <= allowed {
            return best.name
        }
        return nil
    }

    /// "Pose 3" when "Pose 1" and "Pose 2" are taken. Names are how the chat
    /// and a person both refer to a pose, so two with one name would make one
    /// of them unreachable.
    public static func uniqueName(_ base: String, in poses: [DuckPose]) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? "Pose" : trimmed
        let taken = Set(poses.map { normalised($0.name) })
        if !taken.contains(normalised(root)) { return root }
        var n = 2
        while taken.contains(normalised("\(root) \(n)")) { n += 1 }
        return "\(root) \(n)"
    }

    /// The poses the chat is told about, newest first, at most `offeredToTheChat`.
    public static func offered(_ poses: [DuckPose]) -> [DuckPose] {
        Array(poses.sorted { $0.madeAt > $1.madeAt }.prefix(offeredToTheChat))
    }

    /// The paragraph that teaches a model the saved poses. Empty when there
    /// are none, so a library nobody has started changes nothing about the
    /// prompt everybody else gets.
    public static func grounding(_ poses: [DuckPose]) -> String {
        let list = offered(poses)
        guard !list.isEmpty else { return "" }
        let lines = list.map { pose -> String in
            let about = pose.about.isEmpty ? "" : " (\(pose.about))"
            return "- \(pose.name)\(about): \(pose.summary)"
        }.joined(separator: "\n")
        return """
        The person has saved these poses. Prefer them: a keyframe may name one in \
        its "pose" field, and the robot takes that whole pose. Any moves on the \
        same keyframe are then offsets from the pose, not from standing. Use a \
        name exactly as written; never invent a pose name.
        \(lines)
        """
    }

    /// One stop on the way through a string of poses.
    public struct Step: Equatable, Sendable {
        public let pose: String
        /// Seconds to get here from the previous stop.
        public let moveSeconds: Double
        /// Seconds to stay here before moving on.
        public let holdSeconds: Double

        public init(pose: String, moveSeconds: Double = 0.8, holdSeconds: Double = 0) {
            self.pose = pose; self.moveSeconds = moveSeconds; self.holdSeconds = holdSeconds
        }
    }

    public enum Refusal: Error, Equatable {
        case noSteps
        case unknownPose(String, closest: String?)

        public var message: String {
            switch self {
            case .noSteps: return "Pick at least one pose to make a motion from."
            case .unknownPose(let name, let closest):
                let hint = closest.map { " The nearest saved pose is \"\($0)\"." } ?? ""
                return "There is no saved pose called \"\(name)\".\(hint)"
            }
        }
    }

    /// Poses strung into a motion: from standing, through each pose in order,
    /// and back to standing. A move shorter than a fifth of a second is
    /// lengthened to one, because a servo cannot honour a jump and the
    /// editor would flag it anyway. The result is an ordinary draft that faces
    /// `IntentDraft.problems` like any other.
    public static func motion(named: String, steps: [Step],
                              from poses: [DuckPose]) throws -> IntentDraft {
        guard !steps.isEmpty else { throw Refusal.noSteps }
        var keys: [IntentDraft.Key] = [.init(time: 0, pose: DuckModel.homePose)]
        var clock = 0.0
        for step in steps {
            guard let pose = find(step.pose, in: poses) else {
                throw Refusal.unknownPose(step.pose, closest: closest(to: step.pose, in: poses))
            }
            clock += max(step.moveSeconds, 0.2)
            keys.append(.init(time: clock, pose: pose.angles))
            if step.holdSeconds > 0.01 {
                clock += step.holdSeconds
                keys.append(.init(time: clock, pose: pose.angles))
            }
        }
        clock += 0.6
        keys.append(.init(time: clock, pose: DuckModel.homePose))
        let names = steps.map(\.pose).joined(separator: ", ")
        return IntentDraft(
            name: named.isEmpty ? "From poses" : named,
            keys: keys,
            provenance: "Made from saved poses: \(names). Starts and ends standing.")
    }
}

extension PoseLibrary {

    /// Every sentence the pose screens show, here so `swift test` reads them.
    public enum Words {
        public static let heading = "My poses"
        public static let none =
            "No poses yet. On Play, choose Pose, move the joints, then Keep it as a pose."
        public static func row(_ count: Int) -> String {
            count == 1 ? "1 pose" : "\(count) poses"
        }
        public static let rowLine =
            "Named poses you can reuse, string into a motion, and ask the chat for by name."
        public static let name = "Name"
        public static let about = "What it is for"
        public static let aboutPrompt = "right wing raised, for greetings"
        public static let aboutSaid =
            "One line. The chat reads it, so \"for greetings\" lets \"say hello\" find this pose."
        public static let mirror = "Keep a mirrored copy"
        public static let share = "Share the pose file"
        public static let delete = "Delete"
        public static let makeMotion = "Make a motion from poses"
        public static let composerSaid =
            "Tap poses in the order the duck should take them. It starts and ends standing."
        public static let pickPoses = "Poses"
        public static let order = "In this order"
        public static let nothingPicked = "Nothing picked yet."
        public static let secondsBetween = "Seconds between poses"
        public static let holdEach = "Hold each pose"
        public static let motionName = "Motion name"
        public static let keepMotion = "Keep the motion"
        public static func keptMotion(_ name: String) -> String {
            "Kept as \(name). It is in Studio with the other motions; run it on the practice duck first."
        }
        public static let chatSaid =
            "The chat knows your newest \(PoseLibrary.offeredToTheChat) poses by name and "
          + "description. Ask for \"wing up, then wing down, twice\" and it builds the motion from them."

        public static let everySentence: [String] = [
            heading, none, row(1), row(2), rowLine, name, about, aboutPrompt, aboutSaid, mirror,
            share, delete, makeMotion, composerSaid, pickPoses, order, nothingPicked,
            secondsBetween, holdEach, motionName, keepMotion, keptMotion("x"), chatSaid,
        ]
    }
}
