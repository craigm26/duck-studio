import Foundation

/// A phone driver as a source of rows: the same `DreamRows` Dream-1 and the bridge are, so
/// `DreamPilot` drives with it unchanged (the stick limits, the easing, stop then end).
///
/// IT REFUSES RATHER THAN GUESSES, in this order: a checkpoint that is not this driver, a phone
/// too hot to keep computing, no picture (or one that will not decode), an answer slower than
/// `deadline` (steering by a stale picture is worse than stopping), and numbers that are not
/// commands. Each refusal ends the run through the pilot's own stop.
///
/// The prompt is not read: a driver knows one task, and the panel shows which.
public actor LocalDreamRows: DreamRows {
    let net: any DriverNet
    let manifest: DriverManifest
    let modelID: String
    let decode: @Sendable (String) -> [UInt8]?
    let now: @Sendable () -> Double
    let deadline: Double
    let tooHot: @Sendable () -> Bool
    private var took: [Double] = []

    public init(net: any DriverNet, manifest: DriverManifest, modelID: String,
                decode: @escaping @Sendable (String) -> [UInt8]?,
                now: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime },
                deadline: Double = 1.0,
                tooHot: @escaping @Sendable () -> Bool = { false }) {
        self.net = net; self.manifest = manifest; self.modelID = modelID
        self.decode = decode; self.now = now; self.deadline = deadline; self.tooHot = tooHot
    }

    public func act(checkpoint: String, prompt: String, frames: [String: [String]],
                    state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
        guard checkpoint == modelID else { throw DuckDream.ReadError.refused(DuckDream.Words.notThisDriver) }
        guard !tooHot() else { throw DuckDream.ReadError.refused(DuckDream.Words.tooHot) }
        let window = frames[DuckDream.cameraRole] ?? []
        let pictures = window.compactMap(decode)
        guard !window.isEmpty, pictures.count == window.count else {
            throw DuckDream.ReadError.refused(DuckDream.Words.noPicture)
        }
        let started = now()
        let rows: [DuckDrive.Twist]
        do {
            let input = try DriverPrep.input(pictures: pictures, manifest: manifest)
            rows = try DriverPrep.rows(try net.infer(input), rows: manifest.chunk, manifest: manifest)
        } catch {
            throw DuckDream.ReadError.refused(DuckDream.Words.driverFailed)
        }
        let elapsed = now() - started
        took.append(elapsed)
        guard elapsed <= deadline else {
            throw DuckDream.ReadError.refused(DuckDream.Words.tooSlow(Int((elapsed * 1000).rounded())))
        }
        return DuckDream.Chunk(rows: rows, sessionID: nil)
    }

    public func end() async {}

    /// Median and 95th-percentile answer time, in milliseconds, for the run so far.
    public func timings() -> (p50: Int, p95: Int)? {
        guard !took.isEmpty else { return nil }
        let sorted = took.sorted()
        func at(_ q: Double) -> Int { Int((sorted[min(Int(q * Double(sorted.count - 1) + 0.5), sorted.count - 1)] * 1000).rounded()) }
        return (at(0.5), at(0.95))
    }
}

/// Which source a Dream-1 panel run uses, and which models it offers. Pure, so it is tested here.
public enum DreamSourceChoice: Equatable, Sendable {
    case phone, direct, bridge, none

    /// In the Dream-1 panel, phone drivers first and only on the simulated duck (a real duck's walk
    /// starts from Tell, with its own framing and ending); the cloud models after. No key no longer means an empty list: a phone driver needs none.
    public static func merge(cloud: [DuckDream.Model], phone: [DuckDream.Model], isSimDuck: Bool) -> [DuckDream.Model] {
        (isSimDuck ? phone : []) + cloud
    }

    public static func pick(chosen: DuckDream.Model?, hasKey: Bool, bridgeAnswersDream: Bool, isSimDuck: Bool) -> DreamSourceChoice {
        guard let chosen else { return .none }
        if chosen.kind == .phone { return isSimDuck ? .phone : .none }
        if hasKey { return .direct }
        return bridgeAnswersDream ? .bridge : .none
    }
}
