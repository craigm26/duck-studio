import Foundation

/// The scripted ball expert's takes (`scripts/record_ball_takes.py`) as the dataset the phone driver
/// trains on, with the pictures still to be drawn.
///
/// THE SPLIT. Physics ran on duckbench and saved, for every tick, the bench's own state block beside
/// the command in force before (state) and the command sent now (action): `DreamDataset.Take`'s
/// convention. The pictures are drawn afterwards by the app's own head-camera renderer, from those
/// saved states, so a training picture is the picture the phone draws for the same pose at run time.
///
/// ONE PICTURE PER ROW, AND THE ROW'S OWN STATE. Row n's state block is what the bench answered
/// BEFORE row n's action was sent, which is the moment the driver looks and decides. So video frame n
/// is drawn from row n's state block: the picture the driver would have seen when it chose action n.
///
/// THIS FILE DECIDES EVERYTHING BUT THE PIXELS: reading the takes, the episodes, the dataset's
/// files, which state draws which frame, and the launch arguments. The app only draws and encodes.
public enum BallTakes {
    /// One take: its rows, and the bench state each row's picture is drawn from.
    public struct Take: Equatable, Sendable {
        public let seed: Int
        public let task: String
        public let rows: [DreamDataset.Row]
        /// One per row, in order: what the duck's head camera is drawn from for that row.
        public let states: [DuckDrive.Live]
        public var episode: DreamDataset.Episode { DreamDataset.Episode(task: task, rows: rows) }
    }

    public enum Refusal: Error, Equatable {
        /// `line` counts from 1, as an editor does.
        case notJSON(line: Int)
        case noRows(line: Int)
        case badTwist(line: Int, row: Int)
        case badState(line: Int, row: Int)
        case noTakes

        public var message: String {
            switch self {
            case .notJSON(let l): return "Line \(l) of the takes is not a JSON object with a task."
            case .noRows(let l): return "Take on line \(l) has no rows."
            case .badTwist(let l, let r):
                return "Take on line \(l), row \(r + 1): state and action must each be three numbers."
            case .badState(let l, let r):
                return "Take on line \(l), row \(r + 1): the bench state does not read as a duck's state."
            case .noTakes: return "The takes file holds no takes."
            }
        }
    }

    /// Every take in a JSONL file, in file order. Blank lines are skipped.
    public static func read(jsonl: Data) throws -> [Take] {
        var takes: [Take] = []
        for (i, line) in String(decoding: jsonl, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            takes.append(try read(line: Data(line.utf8), number: i + 1))
        }
        if takes.isEmpty { throw Refusal.noTakes }
        return takes
    }

    /// One line of the takes file.
    public static func read(line: Data, number: Int) throws -> Take {
        guard let top = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let task = top["task"] as? String else { throw Refusal.notJSON(line: number) }
        guard let raw = top["rows"] as? [[String: Any]], !raw.isEmpty else { throw Refusal.noRows(line: number) }
        var rows: [DreamDataset.Row] = []
        var states: [DuckDrive.Live] = []
        for (r, row) in raw.enumerated() {
            guard let state = twist(row["state"]), let action = twist(row["action"]) else {
                throw Refusal.badTwist(line: number, row: r)
            }
            guard let bench = row["bench"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: bench),
                  let live = try? DuckDrive.readLive(data) else {
                throw Refusal.badState(line: number, row: r)
            }
            rows.append(DreamDataset.Row(state: state, action: action))
            states.append(live)
        }
        return Take(seed: top["seed"] as? Int ?? 0, task: task, rows: rows, states: states)
    }

    static func twist(_ raw: Any?) -> DuckDrive.Twist? {
        guard let v = raw as? [Any], v.count == 3 else { return nil }
        let n = v.compactMap { ($0 as? NSNumber)?.doubleValue }
        guard n.count == 3, n.allSatisfy(\.isFinite) else { return nil }
        return DuckDrive.Twist(vx: n[0], vy: n[1], vyaw: n[2])
    }

    // MARK: - the render job

    /// What the app is asked to draw: `-render-takes IN.jsonl OUTDIR`, optionally with
    /// `-render-png 0:0,0:40,12:10` (episode:frame pairs) for pictures to look at.
    public struct Job: Equatable, Sendable {
        public let input: String
        public let output: String
        public let pictures: [Picture]
    }

    /// One frame to also write as a PNG, for a person to look at.
    public struct Picture: Equatable, Sendable {
        public let episode: Int, frame: Int
        public init(episode: Int, frame: Int) { self.episode = episode; self.frame = frame }
        public var fileName: String { "episode\(episode)-frame\(frame).png" }
    }

    public static let flag = "-render-takes"
    public static let pictureFlag = "-render-png"

    /// The job in a process's arguments, or nil when the app was launched as an app.
    public static func job(arguments: [String]) -> Job? {
        guard let at = arguments.firstIndex(of: flag), arguments.count > at + 2 else { return nil }
        var pictures: [Picture] = []
        if let p = arguments.firstIndex(of: pictureFlag), arguments.count > p + 1 {
            for pair in arguments[p + 1].split(separator: ",") {
                let parts = pair.split(separator: ":")
                if parts.count == 2, let e = Int(parts[0]), let f = Int(parts[1]), e >= 0, f >= 0 {
                    pictures.append(Picture(episode: e, frame: f))
                }
            }
        }
        return Job(input: arguments[at + 1], output: arguments[at + 2], pictures: pictures)
    }

    /// Everything the app needs to write the dataset: the files StudioKit writes, and for each video
    /// the states to draw, one per frame, in frame order.
    public struct Plan {
        /// By path inside the dataset folder: meta and parquet, everything but the videos.
        public let files: [String: Data]
        public let videos: [Video]
        /// The PNGs asked for, each with the state it is drawn from.
        public let pictures: [(Picture, DuckDrive.Live)]
        public var frames: Int { videos.reduce(0) { $0 + $1.states.count } }
    }

    public struct Video: Sendable {
        public let path: String
        public let states: [DuckDrive.Live]
    }

    public enum PlanRefusal: Error, Equatable {
        case pictureOutOfRange(Picture)
        public var message: String {
            switch self {
            case .pictureOutOfRange(let p): return "There is no frame \(p.frame) in episode \(p.episode)."
            }
        }
    }

    public static func plan(_ takes: [Take], pictures: [Picture] = []) throws -> Plan {
        let files = try DreamDataset.files(takes.map(\.episode))
        let videos = takes.enumerated().map { Video(path: DreamDataset.videoPath($0.offset), states: $0.element.states) }
        var drawn: [(Picture, DuckDrive.Live)] = []
        for p in pictures {
            guard p.episode < takes.count, p.frame < takes[p.episode].states.count else {
                throw PlanRefusal.pictureOutOfRange(p)
            }
            drawn.append((p, takes[p.episode].states[p.frame]))
        }
        return Plan(files: files, videos: videos, pictures: drawn)
    }

    // MARK: - what the render prints (a terminal, not a screen)

    public enum Words {
        public static func read(_ takes: Int, _ rows: Int) -> String { "read \(takes) takes, \(rows) rows" }
        public static func video(_ i: Int, of n: Int, frames: Int) -> String {
            "episode \(i + 1) of \(n): \(frames) frames"
        }
        public static func done(_ episodes: Int, _ frames: Int, _ folder: String) -> String {
            "wrote \(episodes) episodes, \(frames) frames to \(folder)"
        }
        public static func failed(_ why: String) -> String { "render failed: \(why)" }
        public static let noRenderer = "the head camera renderer could not start (no Metal device, or macOS before 15)"
        public static func frameFailed(_ episode: Int, _ frame: Int) -> String {
            "episode \(episode), frame \(frame): the picture could not be drawn or encoded"
        }
    }
}
