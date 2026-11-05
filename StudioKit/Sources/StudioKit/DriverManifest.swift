import Foundation

/// `policy.json`: what a phone driver says about itself, read before its weights are trusted.
///
/// NOT POLLEN'S `manifest.json`. That file describes a joint policy the robot runs (61 inputs,
/// 14 outputs, `robotctl policy add`). A driver sits one layer above: camera in, a walk command
/// out, which the robot's own walker turns into steps. So a driver lives in a `duck-driver-*`
/// repo under its own file name, and a robot never mistakes one for a policy it should load.
///
/// ABSENT IS NOT WRONG, PRESENT AND WRONG IS REFUSED, except for the fields this app cannot run
/// without: the architecture, the format, the shapes, the files and their hashes.
public struct DriverManifest: Decodable, Equatable, Sendable {
    public struct FileEntry: Decodable, Equatable, Sendable {
        public let sha256: String
        public let bytes: Int
    }

    public struct Dataset: Decodable, Equatable, Sendable {
        public let repo: String
        public let commit: String
    }

    public let arch: String
    public let format: String
    public let task: String
    public let label: String
    /// Channels, height, width of the network's input: [6, 88, 160] for two RGB frames.
    public let input: [Int]
    /// Which recorded frames the input stacks, in frames at the dataset's 10 fps, newest first:
    /// [0, -4] is now and 0.4 s ago.
    public let frameOffsets: [Int]
    public let chunk: Int
    public let usesState: Bool
    public let trainedOn: String
    public let imgMean: [Float]
    public let imgStd: [Float]
    public let actMean: [Float]
    public let actStd: [Float]
    public let files: [String: FileEntry]
    public let dataset: Dataset?
    public let valL1: Double?
    public let baselineZeroL1: Double?
    public let baselineRepeatL1: Double?
    /// How its answers are put onto the expert's commands (`DriverSnap`), when it says.
    public let snap: DriverSnap?
    /// The M1 harness's unsnapped arm: this driver played exactly as it answers. Never from a file.
    public var playsRaw = false

    enum CodingKeys: String, CodingKey {
        case arch, format, task, label, input, chunk, files, dataset, snap
        case frameOffsets = "frame_offsets", usesState = "uses_state", trainedOn = "trained_on"
        case imgMean = "img_mean", imgStd = "img_std", actMean = "act_mean", actStd = "act_std"
        case valL1 = "val_l1", baselineZeroL1 = "baseline_zero_l1", baselineRepeatL1 = "baseline_repeat_l1"
    }

    public static let knownArchs: Set<String> = ["ducknet-s1"]
    public static let policyFile = "policy.json"
    public static let weightsFile = "model.safetensors"
    public static let goldenFile = "golden.json"
    /// No driver file this app takes is larger: S1's weights are about 4.4 MB.
    public static let maxFileBytes = 16 << 20

    public enum Problem: Error, Equatable, Sendable {
        case notJSON, arch(String), format(String), shape, chunk(Int), usesState, notSim(String)
        case stats, path(String), tooBig(String), missing(String), hash(String), task(String), snap

        public var message: String {
            switch self {
            case .notJSON: return "This driver's policy.json is not one this app can read."
            case .arch(let a): return "This driver is a \(a) network; this app runs ducknet-s1."
            case .format(let f): return "This driver's weights are \(f); this app reads safetensors."
            case .shape: return "This driver's input is not two head-camera pictures at 160 by 88."
            case .chunk(let n): return "This driver answers \(n) steps at a time; the pilot plays chunks of 48."
            case .usesState: return "This driver reads the duck's last command, which this app does not feed a driver."
            case .notSim(let s):
                return "This driver was trained on \(s), and phone drivers run only on the simulated duck for now."
            case .stats: return "This driver's normalising numbers are missing or not finite."
            case .path(let p): return "This driver names a file outside its own folder (\(p))."
            case .tooBig(let p): return "This driver's file \(p) is larger than any driver needs."
            case .missing(let p): return "This driver's policy.json does not list \(p)."
            case .hash(let p): return "This driver's file \(p) does not match the hash its policy.json gives."
            case .task(let why): return why
            case .snap: return "This driver's snap numbers are not commands the sticks can give."
            }
        }
    }

    public static func read(_ data: Data) throws -> DriverManifest {
        guard let m = try? JSONDecoder().decode(DriverManifest.self, from: data) else { throw Problem.notJSON }
        if let problem = m.problem { throw problem }
        return m
    }

    /// The first thing wrong with this manifest, or nil.
    public var problem: Problem? {
        if !Self.knownArchs.contains(arch) { return .arch(arch) }
        if format != "safetensors" { return .format(format) }
        if input != [6, 88, 160] || frameOffsets.count != 2 || frameOffsets.first != 0
            || frameOffsets.contains(where: { $0 > 0 || $0 % 2 != 0 }) { return .shape }
        if chunk != 48 { return .chunk(chunk) }
        if usesState { return .usesState }
        if trainedOn != "sim" { return .notSim(trainedOn) }
        let stats = [imgMean, imgStd, actMean, actStd]
        if imgMean.count != 3 || imgStd.count != 3 || actMean.count != 3 || actStd.count != 3
            || stats.joined().contains(where: { !$0.isFinite })
            || (imgStd + actStd).contains(where: { $0 <= 0 }) { return .stats }
        for (path, entry) in files.sorted(by: { $0.key < $1.key }) {
            if path.hasPrefix("/") || path.split(separator: "/").contains("..") || path.contains("\\") { return .path(path) }
            if entry.bytes < 0 || entry.bytes > Self.maxFileBytes { return .tooBig(path) }
            if entry.sha256.count != 64 || !entry.sha256.allSatisfy(\.isHexDigit) { return .hash(path) }
        }
        for needed in [Self.weightsFile, Self.goldenFile] where files[needed] == nil { return .missing(needed) }
        if let refusal = DreamDataset.taskProblem(task) { return .task(refusal.message) }
        if let snap, !snap.isValid { return .snap }
        return nil
    }

    /// The snap its rows get: its own `snap` block, else the one pinned for its weights, else none.
    public var outputSnap: DriverSnap? {
        if playsRaw { return nil }
        return snap ?? files[Self.weightsFile].flatMap { DriverSnap.known[$0.sha256.lowercased()] }
    }

    /// Whether `data` is the file `path` this manifest describes, by size and SHA-256.
    public func matches(_ data: Data, path: String) -> Bool {
        guard let entry = files[path], entry.bytes == data.count else { return false }
        return DriverHash.hex(data) == entry.sha256.lowercased()
    }
}
