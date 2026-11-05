import Foundation
import DuckKit

/// M1, closed loop: the shipped `DreamPilot` drives a phone driver on the simulated duck, with the
/// physics on another machine stepped in lockstep.
///
/// WHAT IS SHIPPED CODE AND WHAT IS NOT. The pilot (`DreamPilot.run`: the 20-row horizon, the
/// clamp to the sticks, the 3-row easing, zero before each later ask, the 60 s limit, stop then
/// end), the driver (`LocalDreamRows`, `DriverPrep`, `DuckNetS1`, loaded and golden-checked as the
/// phone installs one), the camera window (`DreamFrameWindow`) and, in the app target, the head
/// camera (`SimHeadCameraRenderer` then `dreamJPEG`) all run unchanged. What stands in for the
/// phone: `LockstepDuck` is the duck (the bench steps only when the pilot sleeps, by exactly the
/// time it sleeps), its clock is the bench's sim clock, and the camera draws every 0.2 s of sim
/// time, as `SimHeadCameraFeed` draws every 0.2 s of wall time. An ask takes no sim time: the
/// phone's answer is under 20 ms (the plan's p50 gate), and the bench cannot step that finely.
///
/// THE WIRE. One JSON line out per request, one line back (`Wire`): `begin` (the physics machine
/// sets up the next start and answers its state, or `done`), `step` (one `/intent` with `hold`),
/// and `ask`, `stop`, `end`, `ended`, which the physics machine only logs. The other end is
/// `scripts/m1_trial.py`, which also judges each run.
public enum DriverTrial {
    public static let flag = "-driver-trial"
    /// Instead of a driver folder: the zero-twist baseline, every row still.
    public static let zero = "zero"
    /// The app's wait between Run and the first ask (`DreamRunModel.run`), the window filling.
    public static let preRoll: TimeInterval = 1.2
    /// The sim head camera's period (`SimHeadCameraFeed`: five pictures a second).
    public static let cameraPeriod: TimeInterval = 0.2
    /// The longest one bench step: a row (`DreamPilot.rowsPerSecond`).
    public static let tick: TimeInterval = 0.1
    /// What every line this side writes begins with, so the other end can skip anything else
    /// the app prints.
    public static let linePrefix = "TRIAL>"

    public struct Job: Equatable, Sendable {
        /// The driver folder (policy.json, model.safetensors, golden.json), or nil for zero twist.
        public let driver: String?
    }

    /// `-driver-trial DIR` or `-driver-trial zero`.
    public static func job(arguments: [String]) -> Job? {
        guard let at = arguments.firstIndex(of: flag), arguments.count > at + 1 else { return nil }
        let value = arguments[at + 1]
        return Job(driver: value == zero ? nil : value)
    }

    /// Request JSON out, reply JSON back.
    public typealias Wire = @Sendable ([String: Any]) async throws -> [String: Any]

    public enum Problem: Error, Equatable, Sendable {
        case wire(String), notThisDriver(String), golden(String)
        public var message: String {
            switch self {
            case .wire(let why): return "the physics machine's answer: \(why)"
            case .notThisDriver(let why): return "the driver folder: \(why)"
            case .golden(let why): return "the driver failed its golden replay: \(why)"
            }
        }
    }

    /// A driver folder, checked as the phone checks one before installing it: the manifest, both
    /// files' sizes and SHA-256, the weights' shapes, and the golden replay.
    public static func load(folder: String, decode: @escaping @Sendable (String) -> [UInt8]?) throws -> (rows: LocalDreamRows, manifest: DriverManifest, modelID: String) {
        let root = URL(fileURLWithPath: folder)
        func read(_ name: String) throws -> Data { try Data(contentsOf: root.appendingPathComponent(name)) }
        let manifest = try DriverManifest.read(try read("policy.json"))
        let weights = try read(DriverManifest.weightsFile)
        let goldenData = try read(DriverManifest.goldenFile)
        guard manifest.matches(weights, path: DriverManifest.weightsFile) else { throw Problem.notThisDriver("weights hash") }
        guard manifest.matches(goldenData, path: DriverManifest.goldenFile) else { throw Problem.notThisDriver("golden hash") }
        let net = try DuckNetS1(SafeTensors(weights))
        if let problem = try DriverGolden.check(net: net, golden: try DriverGolden.read(goldenData)) {
            throw Problem.golden(problem.message)
        }
        let modelID = "\(manifest.label)@\(String(DriverHash.hex(weights).prefix(12)))"
        return (LocalDreamRows(net: net, manifest: manifest, modelID: modelID, decode: decode), manifest, modelID)
    }

    /// The bitmap a decoded picture is drawn into before `rgb(rgba:)`: the driver's picture size, 4 bytes a pixel.
    public static let rgbaRowBytes = DriverPrep.pictureWidth * 4
    public static let rgbaCount = rgbaRowBytes * DriverPrep.pictureHeight

    /// RGBA bytes (as a bitmap context draws them, alpha last) to the RGB bytes `DriverPrep` reads.
    public static func rgb(rgba: [UInt8]) -> [UInt8] {
        var out = [UInt8](); out.reserveCapacity(rgba.count / 4 * 3)
        var i = 0
        while i + 3 < rgba.count { out.append(rgba[i]); out.append(rgba[i + 1]); out.append(rgba[i + 2]); i += 4 }
        return out
    }

    /// The wire over this process's own stdin and stdout: what `scripts/m1_trial.py` speaks over ssh.
    public static func stdioWire() -> Wire {
        let lock = NSLock()
        return { request in
            let data = try JSONSerialization.data(withJSONObject: request)
            let line: String? = lock.withLock {
                FileHandle.standardOutput.write(Data((linePrefix + String(decoding: data, as: UTF8.self) + "\n").utf8))
                return readLine()
            }
            guard let line else { throw Problem.wire("the line closed") }
            guard let reply = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                throw Problem.wire("not JSON")
            }
            return reply
        }
    }

    /// The whole job, for the app's headless entry: load the driver (or the zero baseline), then
    /// run every start. Exit status 0 when every start ran.
    public static func main(_ job: Job, wire: @escaping Wire,
                            decode: @escaping @Sendable (String) -> [UInt8]?,
                            render: @escaping @Sendable (DuckDrive.Live) async -> String?) async -> Int32 {
        func say(_ line: String) { FileHandle.standardError.write(Data((line + "\n").utf8)) }
        do {
            let rows: any DreamRows, modelID: String, task: String
            if let folder = job.driver {
                let loaded = try load(folder: folder, decode: decode)
                (rows, modelID, task) = (loaded.rows, loaded.modelID, loaded.manifest.task)
            } else {
                (rows, modelID, task) = (StillRows(), "zero twist", "walk to the ball")
            }
            say("driver trial: \(modelID)")
            let ran = try await runAll(rows: rows, modelID: modelID, task: task, wire: wire, render: render)
            say("driver trial: \(ran) runs")
            return 0
        } catch let problem as Problem {
            say("driver trial failed: \(problem.message)")
        } catch {
            say("driver trial failed: \(error)")
        }
        return 1
    }

    static func twistJSON(_ t: DuckDrive.Twist) -> [Double] { [t.vx, t.vy, t.vyaw] }

    /// Runs every start the physics machine has, one `DreamPilot` run each; how many ran.
    public static func runAll(rows: any DreamRows, modelID: String, task: String, wire: @escaping Wire,
                              render: @escaping @Sendable (DuckDrive.Live) async -> String?) async throws -> Int {
        var ran = 0
        while true {
            let begun = try await wire(["op": "begin"])
            if begun["done"] as? Bool == true { return ran }
            let duck = try LockstepDuck(start: begun, wire: wire, render: render)
            let logged = TrialRows(rows, wire: wire, clock: { duck.simTime })
            await duck.shoot()
            try await duck.advance(preRoll)
            let pilot = DreamPilot(checkpoint: modelID, prompt: task)
            await pilot.run(on: duck, rows: logged, frames: { duck.frames() },
                            events: { event in
                                if case .ended(let said) = event { _ = try? await wire(["op": "ended", "said": said]) }
                            },
                            sleep: { try await duck.advance($0) },
                            now: { Date(timeIntervalSince1970: duck.simTime) })
            ran += 1
        }
    }
}

/// The zero-twist baseline: every row still, through the same pilot.
public struct StillRows: DreamRows {
    public init() {}
    public func act(checkpoint: String, prompt: String, frames: [String: [String]],
                    state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
        DuckDream.Chunk(rows: Array(repeating: .still, count: 48), sessionID: nil)
    }
    public func end() async {}
}

/// A source of rows that tells the physics machine every chunk it answered (and every refusal)
/// and when it was ended, so the run's log holds what the driver asked for.
public final class TrialRows: DreamRows, @unchecked Sendable {
    let inner: any DreamRows
    let wire: DriverTrial.Wire
    let clock: @Sendable () -> Double

    public init(_ inner: any DreamRows, wire: @escaping DriverTrial.Wire, clock: @escaping @Sendable () -> Double) {
        self.inner = inner; self.wire = wire; self.clock = clock
    }

    public func act(checkpoint: String, prompt: String, frames: [String: [String]],
                    state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let chunk = try await inner.act(checkpoint: checkpoint, prompt: prompt, frames: frames, state: state, reset: reset)
            let ms = (ProcessInfo.processInfo.systemUptime - started) * 1000
            _ = try await wire(["op": "ask", "t": clock(), "ms": ms, "window": frames[DuckDream.cameraRole]?.count ?? 0,
                                "state": state[DuckDream.part] ?? [], "rows": chunk.rows.map(DriverTrial.twistJSON)])
            return chunk
        } catch let refusal as DuckDream.ReadError {
            _ = try? await wire(["op": "ask", "t": clock(), "refused": refusal.message])
            throw refusal
        }
    }

    public func end() async {
        await inner.end()
        _ = try? await wire(["op": "end", "t": clock()])
    }
}

/// The simulated duck as the pilot sees it, with the bench on the other end of a `Wire`: a move
/// sets the command in force, and time passes only when the pilot sleeps.
public final class LockstepDuck: DuckPeer, @unchecked Sendable {
    public let identity = DuckIdentity(name: "Lockstep bench", kind: .real)
    public let transportKind: DuckTransportKind = .bridge
    public let reach = DuckMethod.reach(for: .bridge)
    private let wire: DriverTrial.Wire
    private let render: @Sendable (DuckDrive.Live) async -> String?
    private let lock = NSLock()
    private var command = DuckDrive.Twist.still
    private var _live: DuckDrive.Live
    private var window = DreamFrameWindow()
    private var lastShot: Double?

    init(start: [String: Any], wire: @escaping DriverTrial.Wire,
         render: @escaping @Sendable (DuckDrive.Live) async -> String?) throws {
        self.wire = wire; self.render = render
        _live = try Self.live(start)
    }

    static func live(_ reply: [String: Any]) throws -> DuckDrive.Live {
        if let why = reply["error"] as? String { throw DriverTrial.Problem.wire(why) }
        guard let state = reply["state"], JSONSerialization.isValidJSONObject(state),
              let data = try? JSONSerialization.data(withJSONObject: state) else {
            throw DriverTrial.Problem.wire("no state")
        }
        return try DuckDrive.readLive(data)
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    public var live: DuckDrive.Live { locked { _live } }
    public var simTime: Double { locked { _live.t } }
    public func frames() -> [String] { locked { window.frames } }

    public func call(_ c: DuckCall) async throws -> DuckReply {
        try vet(c, asNotification: false)
        if c == .stop {
            locked { command = .still }
            _ = try await wire(["op": "stop", "t": simTime])
        }
        return DuckReply(id: 1, result: Data(#"{"accepted":true}"#.utf8), failure: nil)
    }

    public func notify(_ c: DuckCall) async throws {
        try vet(c, asNotification: true)
        if case .move(let t) = c { locked { command = t } }
    }

    public nonisolated func states() -> AsyncStream<DuckState> { AsyncStream { $0.finish() } }

    public func lastCommand() async -> DuckDrive.Twist? { locked { command } }

    /// Draws the head camera's picture of now into the window, timed by the sim clock.
    public func shoot() async {
        let now = live
        locked { lastShot = now.t }
        guard let jpeg = await render(now) else { return }
        locked { _ = window.add(jpeg, at: now.t) }
    }

    /// Steps the bench `seconds` with the command in force, a tick at a time, drawing the camera
    /// whenever its period has passed.
    public func advance(_ seconds: TimeInterval) async throws {
        var left = seconds
        while left > 1e-6 {
            let hold = min(left, DriverTrial.tick)
            let c = locked { command }
            let next = try Self.live(try await wire(["op": "step", "vx": c.vx, "vy": c.vy, "vyaw": c.vyaw, "hold": hold]))
            let due = locked { () -> Bool in
                _live = next
                return lastShot.map { next.t - $0 >= DriverTrial.cameraPeriod - 1e-6 } ?? true
            }
            if due { await shoot() }
            left -= hold
        }
    }
}
