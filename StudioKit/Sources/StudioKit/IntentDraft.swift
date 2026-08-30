import Foundation
import DuckKit

/// A motion somebody is writing, rather than one that was recorded.
///
/// WHAT YOU CAN AND CANNOT AUTHOR ON A PHONE, STATED UP FRONT. Every intent in
/// this app so far was RECORDED: a trained policy drove the robot in MuJoCo and
/// the result was written down, root and all. That cannot happen here. The
/// policy needs contact to lock its gait phase, and a phone has no physics
/// engine and no floor — the app already refuses to close that loop on the
/// bench for exactly this reason.
///
/// So what a draft is, precisely: A LIST OF POSES AND THE TIMES THEY HAPPEN AT.
/// Between them the robot is interpolated with smoothstep, which is what
/// `DuckMove` does and what the shipped authored moves already are. That is a
/// real, useful, exportable thing — it is the same shape as `step_up` and
/// `wall_flip`, and the sim harness and the robot both take it — and it is NOT
/// a prediction of what the robot will do. Nothing here knows about gravity,
/// the robot's own weight, servo torque, or the floor.
///
/// THE ROOT DOES NOT MOVE, AND THAT IS NOT A BUG. A recorded clip carries where
/// the trunk went because physics put it there. A draft has no physics, so
/// there is nothing to carry: the preview stands the robot at the origin and
/// moves only its joints. A draft that guessed at root motion would be drawing
/// a robot walking across a floor it has never touched.
public struct IntentDraft: Codable, Equatable, Identifiable, Sendable {

    public struct Key: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var time: TimeInterval
        /// All 15 joints in `DuckModel.jointNames` order — the mouth included,
        /// which is the one thing a draft can drive and no policy can.
        public var pose: [Double]

        public init(id: UUID = UUID(), time: TimeInterval, pose: [Double]) {
            self.id = id; self.time = time; self.pose = pose
        }
    }

    public var id: UUID
    public var name: String
    public var keys: [Key]
    /// The scene it is being written against, so the preview is judged in the
    /// place it is meant for. Nil means bare floor.
    public var sceneID: UUID?
    /// Where the draft started, for display: written from nothing, or lifted
    /// off a recording.
    public var provenance: String
    /// The last real physics run of this motion, if there has been one.
    ///
    /// A DRAFT USED TO FORGET. You could write one, preview it on a phone with
    /// no physics engine, run it on a real one across the room, and open it a
    /// week later to find keyframes and a name — no record that anything had
    /// ever been run, and no way to tell a checked motion from an untested one.
    /// Optional, so every draft saved before this decodes with nil.
    public var bench: Pipeline.BenchOutcome?

    public init(id: UUID = UUID(), name: String, keys: [Key] = [],
                sceneID: UUID? = nil, provenance: String = "Written here") {
        self.id = id; self.name = name; self.keys = keys
        self.sceneID = sceneID; self.provenance = provenance; self.bench = nil
    }

    /// The sentence that has to appear wherever a draft is played.
    public static let disclaimer =
        "Poses and times, interpolated — no physics ran. Nothing here knows about the robot's "
      + "weight, the floor, or what a servo can actually deliver, so this shows what you asked "
      + "for and not what the robot would do. To find that out, run it."

    // MARK: - starting one

    /// A new draft: the robot standing, and one keyframe half a second later to
    /// move away from.
    ///
    /// TWO KEYFRAMES, NOT ONE. A single-keyframe move has zero duration and
    /// nothing to interpolate, so the editor would open on a timeline with no
    /// length and a scrubber that cannot move.
    public static func blank(named name: String = "New motion") -> IntentDraft {
        IntentDraft(name: name, keys: [
            Key(time: 0, pose: DuckModel.homePose),
            Key(time: 0.5, pose: DuckModel.homePose),
        ])
    }

    /// A draft started from a recording.
    ///
    /// WHAT REMIXING LOSES, AND IT IS THE IMPORTANT HALF. A recording is a
    /// trajectory that physics produced: the joint angles are what the robot
    /// ACHIEVED against its own weight and the floor, and the root is where
    /// that put it. Sampling those angles into keyframes keeps the shapes and
    /// throws away every reason they held together. The result is a starting
    /// point for authoring — it is not the recorded motion, and it carries none
    /// of the recorded motion's evidence. A remix of a clip that works is not a
    /// motion that works.
    ///
    /// Sampled rather than copied wholesale: two hundred keyframes is not a
    /// draft anybody can edit, and smoothstep between eight of them is a
    /// different curve from the one recorded at fifty hertz. Both facts are
    /// why the provenance line says "sampled".
    public static func remix(_ clip: DuckIntentClip, keyframes count: Int = 8) -> IntentDraft {
        let n = max(count, 2)
        let keys = (0..<n).map { i -> Key in
            let time = clip.duration * Double(i) / Double(n - 1)
            return Key(time: time, pose: clip.pose(at: time).jointAngles)
        }
        return IntentDraft(
            name: "\(clip.name) remixed",
            keys: keys,
            provenance: "Sampled from the recording of \(clip.name) at \(n) keyframes. "
                      + "The shapes are its; the physics that produced them is not.")
    }

    // MARK: - what is wrong with it

    public struct Problem: Equatable, Sendable, Identifiable {
        public enum Severity: String, Equatable, Sendable {
            /// It will not export or play as written.
            case broken
            /// It will play, and it is asking for something the robot cannot do.
            case impossible
            /// Worth knowing before running it.
            case caution
        }
        public let severity: Severity
        public let text: String
        public var id: String { "\(severity.rawValue):\(text)" }
    }

    /// How fast a servo can move a joint before the request stops meaning
    /// anything, radians per second.
    ///
    /// NOT A DATASHEET FIGURE, AND THE SCREEN SAYS SO. It is the fastest thing
    /// the recorded corpus actually does, rounded up — currently 12.6 rad/s,
    /// after the plant moved to training's own solver, floor friction and
    /// torque ceiling (the tighter ±0.6405 Nm limit is most of why the old
    /// 16.92 rad/s peak came down). A draft asking for more than any trained
    /// policy ever asks for is asking for something no recording in this app
    /// demonstrates — worth a warning, and NOT a proof of impossibility.
    ///
    /// `IntentDraftTests` recomputes the peak from the bundled clips and fails
    /// in BOTH directions: below the corpus peak the editor warns about
    /// shipped motions; more than 20% above it the warning stops firing on
    /// anything a servo could plausibly refuse. A first cut said 12 as a
    /// guess; a later corpus made 17 stale the other way.
    public static let observedPeakJointRate = 13.0

    public var problems: [Problem] {
        var out: [Problem] = []
        guard keys.count >= 2 else {
            out.append(.init(severity: .broken,
                             text: "A motion needs at least two keyframes — one pose is a pose, not a motion."))
            return out
        }
        let ordered = keys.sorted { $0.time < $1.time }
        for (index, key) in ordered.enumerated() {
            if key.time < 0 {
                out.append(.init(severity: .broken, text: "A keyframe happens before the motion starts."))
            }
            if index > 0, key.time <= ordered[index - 1].time {
                out.append(.init(severity: .broken,
                                 text: String(format: "Two keyframes share the time %.2f s. Move one.", key.time)))
            }
            guard key.pose.count == DuckModel.jointCount else {
                out.append(.init(severity: .broken,
                                 text: "A keyframe has \(key.pose.count) joints; the robot has \(DuckModel.jointCount)."))
                continue
            }
            for joint in 0..<DuckModel.jointCount {
                let range = DuckModel.jointRanges[joint]
                if key.pose[joint] < range.lower - 1e-6 || key.pose[joint] > range.upper + 1e-6 {
                    out.append(.init(severity: .broken,
                                     text: "\(DuckModel.jointNames[joint]) is outside its travel at "
                                         + String(format: "%.2f s.", key.time)))
                }
            }
            // How fast the interpolation asks the joint to move. Smoothstep's
            // peak rate is 1.5× the average over the span, which is where the
            // 1.5 comes from rather than a fudge.
            guard index > 0, ordered[index - 1].pose.count == DuckModel.jointCount else { continue }
            let span = key.time - ordered[index - 1].time
            guard span > 1e-6 else { continue }
            for joint in 0..<DuckModel.jointCount {
                let rate = 1.5 * abs(key.pose[joint] - ordered[index - 1].pose[joint]) / span
                if rate > Self.observedPeakJointRate {
                    out.append(.init(
                        severity: .impossible,
                        text: String(format: "%@ is asked to move at %.0f rad/s around %.2f s. Nothing in the recorded corpus exceeds %.0f.",
                                     DuckModel.jointNames[joint], rate, key.time,
                                     Self.observedPeakJointRate)))
                }
            }
        }
        if ordered.contains(where: { $0.pose.count == DuckModel.jointCount
                                  && $0.pose[DuckModel.mouthIndex] != DuckModel.homePose[DuckModel.mouthIndex] }) {
            out.append(.init(severity: .caution,
                             text: "This motion drives the mouth. No policy can — the mouth is outside every "
                                 + "alpha policy's action space — so this is yours alone and nothing trained it."))
        }
        return out
    }

    public var isPlayable: Bool { !problems.contains { $0.severity == .broken } }

    // MARK: - playing it

    public var duration: TimeInterval { keys.map(\.time).max() ?? 0 }

    /// The validated move, or the reason it is not one.
    ///
    /// Through `DuckMove`'s RAW door, never by building keyframes first:
    /// `DuckMove.Keyframe.init` traps on a bad pose, so validating after
    /// construction is validating something that already crashed.
    public func move() throws -> DuckMove {
        let ordered = keys.sorted { $0.time < $1.time }
        return try DuckMove(validating: name,
                            times: ordered.map(\.time),
                            poses: ordered.map(\.pose))
    }

    /// The pose at a time, for the preview. Falls back to the home stance while
    /// the draft is not yet valid, rather than refusing to draw anything —
    /// somebody dragging a joint past its stop should see the warning appear,
    /// not watch the robot vanish.
    public func pose(at time: TimeInterval) -> [Double] {
        guard let move = try? move() else { return DuckModel.homePose }
        return move.pose(at: time)
    }

    // MARK: - handing it over

    public static let fileExtension = "duckmove"
    public var suggestedFilename: String { "\(name).\(Self.fileExtension)" }

    /// The file the sim harness and the robot both take.
    ///
    /// DECIMAL TEXT, so it round-trips to within an ULP rather than bit-exactly
    /// — `mouthOpen` leaves as 30° in radians and comes back one unit in the
    /// last place away. That is 1e-16 rad against a 0.6 rad travel and the
    /// validating initializer's 1e-6 tolerance swallows it; what it breaks is
    /// any downstream check that assumes an exported file is byte-identical to
    /// the draft it came from.
    ///
    /// FIFTEEN JOINTS WIDE, unlike a `.duckintent`, and the difference matters:
    /// an intent is 14 because it is what a policy produced and the mouth is
    /// outside every policy's action space. A draft is 15 because a person
    /// wrote it and a person can open the beak. Narrowing it to 14 on export
    /// would silently drop the one thing authoring adds.
    public func exported() throws -> Data {
        // THROUGH THE FORMAT'S SINGLE DOOR. DuckKit's DuckMoveFile is the one
        // writer and reader of .duckmove — OpenCastor plays these files as
        // goal celebrations, and two parsers for one format is how a file
        // works in one app and silently misloads in the other. The caveat
        // travels as the note, because the file is the thing that gets shared
        // and the caveat is the thing most likely to be lost.
        try DuckMoveFile.encode(name: name, move: try move(),
                                provenance: provenance, note: Self.disclaimer)
    }

    public enum ImportError: Error, Equatable {
        case notAMove
        case unsupportedFormat(String)
        case malformed(String)

        public var message: String {
            switch self {
            case .notAMove: return "That file is not an authored motion."
            case .unsupportedFormat(let f):
                return "This motion is in format \"\(f)\", which this version does not read."
            case .malformed(let what): return what
            }
        }
    }

    /// Read a shared motion.
    ///
    /// THIS USED TO BE A SECOND PARSER, and it cost exactly what a second
    /// parser costs. `DuckMoveFile` calls itself "the format's single door";
    /// this function quietly opened another one beside it, with its own
    /// hardcoded `format == "duck-move/1"` — so the day DuckKit learned to
    /// write `duck-move/2`, every import here refused a file the kit had just
    /// produced. It now delegates, which also means a motion authored against
    /// a non-home base resolves correctly instead of being read as if it were
    /// absolute: `pose(at:)` applies the file's own base and reading mode.
    public static func decode(_ data: Data) throws -> IntentDraft {
        let contents: DuckMoveFile.Contents
        do {
            contents = try DuckMoveFile.decode(data)
        } catch let error as DuckMoveFile.ReadError {
            switch error {
            case .notAMove: throw ImportError.notAMove
            case .unsupportedFormat(let f): throw ImportError.unsupportedFormat(f)
            case .malformed(let what): throw ImportError.malformed(what)
            case .jointOrderMismatch: throw ImportError.malformed(
                "The motion lists its joints in another order, so its poses are "
              + "for a differently wired robot.")
            case .invalid(let refusal): throw ImportError.malformed(refusal.message)
            }
        }
        let move = contents.move
        return IntentDraft(
            name: contents.name,
            keys: move.keyframes.map { Key(time: $0.time, pose: move.pose(at: $0.time)) },
            provenance: contents.provenance ?? "Imported")
    }
}
