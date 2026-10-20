import Foundation

/// A duck's recordings as Dream Labs fine-tunes on them: one LeRobot v2.1 dataset.
///
/// THE DUCK'S CONVENTION, `DuckDream.microduck` and OpenCastor's `MICRODUCK_EMBODIMENT`: each frame
/// of data is the walk command that was in force (`observation.state`, `[vx, vy, vyaw]`), the walk
/// command sent next (`action`, the same three), and the head camera's picture
/// (`observation.images.head`, 320 by 176, the size `DreamPilot` sends), at 10 frames a second, the
/// rate `DreamPilot` plays rows at. So a model trained on these answers rows the pilot can play.
///
/// HELD TO DREAM LABS' OWN CHECKS, not to a reading of LeRobot: the tests here write a dataset, and
/// `dream.datasets.validate_dataset` (dreamlabs-client 1.0.1) is what has to pass it. That is the
/// check the Upload page runs in a browser before it sends anything.
///
/// THIS FILE WRITES EVERYTHING BUT THE VIDEOS, which need the platform's encoder (`AVAssetWriter`,
/// in the app). `videoPath(_:)` says where each goes and `videoFrames(_:)` how many it must hold.
public enum DreamDataset {
    public static let fps = 10
    public static let width = 320
    public static let height = 176
    public static let videoKey = "observation.images.head"
    public static let chunk = "chunk-000"
    /// The fewest frames Dream Labs takes for an episode at 10 fps: one training sample, 48 frames at
    /// 30 fps (1.6 s), and the one after.
    public static let minimumRows = 48 * fps / 30 + 1
    /// LeRobot's episodes per chunk folder.
    public static let chunksSize = 1000

    public struct Row: Equatable, Sendable {
        public let state: DuckDrive.Twist
        public let action: DuckDrive.Twist
        public init(state: DuckDrive.Twist, action: DuckDrive.Twist) { self.state = state; self.action = action }
    }

    public struct Episode: Equatable, Sendable {
        public let task: String
        public let rows: [Row]
        public init(task: String, rows: [Row]) { self.task = task; self.rows = rows }
    }

    public enum Refusal: Error, Equatable {
        case noEpisodes, emptyTask(Int), tooShort(Int, Int), tooMany

        public var message: String {
            switch self {
            case .noEpisodes: return "Record at least one run first."
            case .emptyTask(let i): return "Run \(i + 1) has no task. Say what the duck was doing, in words."
            case .tooShort(let i, let n):
                return "Run \(i + 1) is \(n) steps; Dream Labs takes runs of at least \(DreamDataset.minimumRows) "
                    + "(about \(DreamDataset.minimumRows / DreamDataset.fps + 1) seconds). Delete it or record it again."
            case .tooMany: return "A dataset here holds at most \(DreamDataset.chunksSize) runs."
            }
        }
    }

    public static func dataPath(_ episode: Int) -> String {
        "data/\(chunk)/episode_\(String(format: "%06d", episode)).parquet"
    }
    public static func videoPath(_ episode: Int) -> String {
        "videos/\(chunk)/\(videoKey)/episode_\(String(format: "%06d", episode)).mp4"
    }
    /// One picture per frame of data, at `fps`, evenly spaced: what Dream Labs pairs rows with.
    public static func videoFrames(_ episode: Episode) -> Int { episode.rows.count }

    /// The tasks in first-seen order; an episode's task index is its place here.
    public static func tasks(_ episodes: [Episode]) -> [String] {
        var seen: [String] = []
        for e in episodes where !seen.contains(e.task) { seen.append(e.task) }
        return seen
    }

    public static func check(_ episodes: [Episode]) throws {
        if episodes.isEmpty { throw Refusal.noEpisodes }
        if episodes.count > chunksSize { throw Refusal.tooMany }
        for (i, e) in episodes.enumerated() {
            if e.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw Refusal.emptyTask(i) }
            if e.rows.count < minimumRows { throw Refusal.tooShort(i, e.rows.count) }
        }
    }

    /// Every file of the dataset but the videos, by path inside the dataset's folder.
    public static func files(_ episodes: [Episode]) throws -> [String: Data] {
        try check(episodes)
        let taskList = tasks(episodes)
        var out: [String: Data] = [:]
        var index: Int64 = 0
        var episodeLines: [String] = []
        for (i, e) in episodes.enumerated() {
            let n = e.rows.count
            let task = Int64(taskList.firstIndex(of: e.task)!)
            out[dataPath(i)] = try ParquetWriter.write([
                .floatList("action", e.rows.map { vector($0.action) }),
                .floatList("observation.state", e.rows.map { vector($0.state) }),
                .float("timestamp", (0..<n).map { Float($0) / Float(fps) }),
                .int64("frame_index", (0..<n).map(Int64.init)),
                .int64("episode_index", Array(repeating: Int64(i), count: n)),
                .int64("index", (0..<n).map { index + Int64($0) }),
                .int64("task_index", Array(repeating: task, count: n)),
            ])
            index += Int64(n)
            episodeLines.append(try json(["episode_index": i, "tasks": [e.task], "length": n]))
        }
        out["meta/episodes.jsonl"] = Data((episodeLines.joined(separator: "\n") + "\n").utf8)
        let taskLines = try taskList.enumerated().map { try json(["task_index": $0.offset, "task": $0.element]) }
        out["meta/tasks.jsonl"] = Data((taskLines.joined(separator: "\n") + "\n").utf8)
        out["meta/info.json"] = try info(episodes: episodes.count, frames: Int(index), tasks: taskList.count)
        return out
    }

    static func vector(_ t: DuckDrive.Twist) -> [Float] { [Float(t.vx), Float(t.vy), Float(t.vyaw)] }

    static func json(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }

    static func info(episodes: Int, frames: Int, tasks: Int) throws -> Data {
        let vector: [String: Any] = ["dtype": "float32", "shape": [3], "names": ["vx", "vy", "vyaw"]]
        let scalar: (String) -> [String: Any] = { ["dtype": $0, "shape": [1], "names": NSNull()] }
        let info: [String: Any] = [
            "codebase_version": "v2.1",
            "robot_type": "microduck",
            "total_episodes": episodes,
            "total_frames": frames,
            "total_tasks": tasks,
            "total_videos": episodes,
            "total_chunks": 1,
            "chunks_size": chunksSize,
            "fps": fps,
            "splits": ["train": "0:\(episodes)"],
            "data_path": "data/chunk-{episode_chunk:03d}/episode_{episode_index:06d}.parquet",
            "video_path": "videos/chunk-{episode_chunk:03d}/{video_key}/episode_{episode_index:06d}.mp4",
            "features": [
                "action": vector,
                "observation.state": vector,
                videoKey: ["dtype": "video", "shape": [height, width, 3], "names": ["height", "width", "channels"],
                           "info": ["video.fps": fps, "video.height": height, "video.width": width,
                                    "video.channels": 3, "video.codec": "h264", "video.pix_fmt": "yuv420p",
                                    "video.is_depth_map": false, "has_audio": false]],
                "timestamp": scalar("float32"),
                "frame_index": scalar("int64"),
                "episode_index": scalar("int64"),
                "index": scalar("int64"),
                "task_index": scalar("int64"),
            ],
        ]
        return try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys, .prettyPrinted])
    }

    /// A folder name Dream Labs takes for a session: letters, digits, dot, dash, underscore, up to 64.
    public static func folderName(date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "microduck-\(f.string(from: date))"
    }

    // MARK: - recording

    /// One run being recorded: a frame of data every tenth of a second, from the command in force.
    ///
    /// STATE IS WHAT WAS COMMANDED LAST, ACTION WHAT IS COMMANDED NOW, which is what `DreamPilot` sends
    /// and then plays: a model learns "given what the duck was told and what it sees, tell it this".
    public struct Take: Sendable {
        public let task: String
        public private(set) var rows: [Row] = []
        private var previous = DuckDrive.Twist.still
        public init(task: String) { self.task = task }

        /// One tick: the command in force now (nil when nothing has been sent, which is standing still).
        public mutating func tick(command: DuckDrive.Twist?) {
            let now = command ?? .still
            rows.append(Row(state: previous, action: now))
            previous = now
        }

        public var episode: Episode { Episode(task: task, rows: rows) }
        public var seconds: Double { Double(rows.count) / Double(DreamDataset.fps) }
        public var longEnough: Bool { rows.count >= DreamDataset.minimumRows }
    }

    // MARK: - words

    public enum Words {
        public static let heading = "Record for Dream-1"
        public static let whatItIs =
            "Drive the duck while it records what it sees and what you tell it to do, ten times a second. "
          + "Each run is one example of the task. Upload the folder on platform.dreamlabs.ai to fine-tune "
          + "a Dream-1 model on your duck. Nothing leaves this device until you send it."
        public static let taskPlaceholder = "What are you showing it? For example, walk to the red mat"
        public static let start = "Start a run"
        public static let stop = "End the run"
        public static let discard = "Delete the last run"
        public static let export = "Export for Dream Labs"
        public static func runs(_ n: Int, _ seconds: Double) -> String {
            String(format: "%d run%@, %.0f s recorded.", n, n == 1 ? "" : "s", seconds)
        }
        public static func recording(_ seconds: Double) -> String { String(format: "Recording, %.1f s.", seconds) }
        public static let howToUpload =
            "On a computer, open platform.dreamlabs.ai, Fine-tuning. Under New configuration, choose this "
          + "folder, then name the state part and the action part velocity (3 values each) and give the "
          + "camera the role head. Then Upload data with the same folder, and start a job. Your fine-tuned "
          + "model then appears in Dream-1 here."
    }
}
