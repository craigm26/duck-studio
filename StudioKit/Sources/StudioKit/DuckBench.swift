import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DuckKit

/// A machine on your network that has physics, which this phone does not.
///
/// THE GAP THIS CLOSES. Duck Studio can import a policy — Pollen's, or one
/// somebody published on Hugging Face — and then do nothing with it: an iPhone
/// has no MuJoCo, so every clip in the app was recorded on a bigger machine and
/// baked in at build time. Point this at a bench (`sim/duckbench.mjs` in
/// duck-sounds) and an imported policy becomes something you can actually run:
/// record it into a clip, or measure how often it works.
///
/// IT DOES NOT TRAIN, AND THE BENCH SAYS SO ITSELF in `/health`. Training is a
/// GPU job; what a Raspberry Pi with an inference accelerator is good for is
/// running the physics it already runs.
public enum DuckBench {

    /// Where the bench is. Plain http is allowed BECAUSE this is a machine on
    /// your own network — a Pi on a desk has no certificate and never will —
    /// and refused for anything that is not obviously local, so a typo cannot
    /// send a policy request to a stranger over the open internet.
    public struct Address: Equatable, Sendable {
        public let host: String
        public let port: Int
        public var base: String { "http://\(host):\(port)" }

        public init(host: String, port: Int) { self.host = host; self.port = port }
    }

    public enum Refusal: Error, Equatable {
        case empty
        case notLocal(String)
        case malformed(String)

        public var message: String {
            switch self {
            case .empty:
                return "Give the bench's address — something like 192.168.1.20:8770, or duckbench.local."
            case .notLocal(let host):
                return "\(host) is not on your network. This talks to a machine you can see "
                     + "from here over plain http, so it only accepts a private address or a "
                     + ".local name."
            case .malformed(let text):
                return "\"\(text)\" is not an address this can reach."
            }
        }
    }

    /// Addresses on your own network, and nothing else.
    ///
    /// The rule is deliberately narrow: RFC1918 ranges, loopback, and mDNS
    /// `.local` names. A bench is a thing on a desk; anything else pasted here
    /// is a mistake, and sending unauthenticated requests to it would be the
    /// app's fault rather than the typist's.
    public static func address(_ text: String, defaultPort: Int = 8770) throws -> Address {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { throw Refusal.empty }
        if let range = trimmed.range(of: "://") { trimmed = String(trimmed[range.upperBound...]) }
        if let slash = trimmed.firstIndex(of: "/") { trimmed = String(trimmed[..<slash]) }
        var host = trimmed, port = defaultPort
        if let colon = trimmed.lastIndex(of: ":") {
            let tail = String(trimmed[trimmed.index(after: colon)...])
            if let parsed = Int(tail), parsed > 0, parsed < 65536 {
                host = String(trimmed[..<colon]); port = parsed
            }
        }
        guard !host.isEmpty, !host.contains(" ") else { throw Refusal.malformed(text) }
        guard isLocal(host) else { throw Refusal.notLocal(host) }
        return Address(host: host, port: port)
    }

    static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (127, _), (10, _): return true
        case (192, 168): return true
        case (172, 16...31): return true
        default: return false
        }
    }

    // MARK: - what to ask it

    public struct Call: Equatable, Sendable {
        public let method: String
        public let url: URL
        public let body: Data?
        public var displayURL: String { url.absoluteString }
    }

    public static func health(_ address: Address) -> Call {
        Call(method: "GET", url: URL(string: "\(address.base)/health")!, body: nil)
    }

    /// One step of a command schedule: from `at` seconds, hold this twist.
    public struct Step: Equatable, Sendable {
        public let at: Double
        public let vx: Double, vy: Double, vyaw: Double
        public init(at: Double, vx: Double = 0, vy: Double = 0, vyaw: Double = 0) {
            self.at = at; self.vx = vx; self.vy = vy; self.vyaw = vyaw
        }
        var wire: Any { [at, ["vx": vx, "vy": vy, "vyaw": vyaw]] }
    }

    public static func record(_ address: Address, policy: String, seconds: Double,
                              schedule: [Step]) throws -> Call {
        let body: [String: Any] = ["policy": policy, "seconds": seconds,
                                   "schedule": schedule.map(\.wire)]
        return Call(method: "POST", url: URL(string: "\(address.base)/record")!,
                    body: try JSONSerialization.data(withJSONObject: body))
    }

    public static func measure(_ address: Address, policy: String, seconds: Double,
                               rollouts: Int, schedule: [Step]) throws -> Call {
        let body: [String: Any] = ["policy": policy, "seconds": seconds,
                                   "rollouts": rollouts, "schedule": schedule.map(\.wire)]
        return Call(method: "POST", url: URL(string: "\(address.base)/measure")!,
                    body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Run an AUTHORED motion — keyframes, not a policy — in real physics.
    ///
    /// THE ONE CALL THAT CLOSES THE LOOP. Everything else here runs a trained
    /// network; this sends a track somebody wrote and gets back what actually
    /// happened to it. Until this existed, an authored motion could be
    /// previewed on a phone with no physics engine and published to the world
    /// without any engine ever having seen it.
    ///
    /// It runs more than once on purpose. A single rollout that stays up proves
    /// very little — the four authored stair motions in this app's corpus get
    /// up their flight 0 times in 16.
    public static func perform(_ address: Address, keys: [(at: Double, pose: [Double])],
                               seconds: Double, rollouts: Int = 8,
                               policy: String? = nil, blend: Double = 1) throws -> Call {
        var body: [String: Any] = [
            "track": keys.map { ["at": $0.at, "pose": $0.pose] },
            "seconds": seconds, "rollouts": rollouts, "blend": blend,
        ]
        if let policy { body["policy"] = policy }
        return Call(method: "POST", url: URL(string: "\(address.base)/perform")!,
                    body: try JSONSerialization.data(withJSONObject: body))
    }

    /// A `/perform` answer, as something a draft can keep.
    public static func readOutcome(_ data: Data, when: Date, plant: String) throws
        -> Pipeline.BenchOutcome {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        if let error = top["error"] as? String { throw ReadError.bench(error) }
        guard let rollouts = top["rollouts"] as? Int, let achieves = top["achieves"] as? Int else {
            throw ReadError.empty
        }
        return Pipeline.BenchOutcome(
            when: when,
            bench: top["format"] as? String ?? "duck-bench",
            plant: plant,
            policy: top["policy"] as? String ?? "unknown",
            achieves: achieves, rollouts: rollouts,
            criterion: top["criterion"] as? String ?? "stayed upright",
            medianHeight: top["medianHeight"] as? Double,
            peakJointRate: top["peakJointRate"] as? Double)
    }

    public static func urlRequest(for call: Call, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: call.url)
        request.httpMethod = call.method
        request.httpBody = call.body
        if call.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 120   // a measure of 32 rollouts is not quick
        return request
    }

    // MARK: - what it answers

    public struct Health: Equatable, Sendable {
        public let bench: String
        public let plant: String
        public let tickHz: Double
        public let cores: Int
        public let policies: [String]
        public let trains: Bool
        public let trainsWhy: String?
        /// What is in that world the duck could take hold of, with the mass
        /// the MODEL gives it — not the mass somebody typed into a scene.
        ///
        /// THIS IS HOW A PROP STOPS BEING A CLAIM. A broom in a Studio scene is
        /// a description; a broom in the bench's world is a body with a mass
        /// and a freejoint that physics will move or refuse to. When both
        /// exist, the numbers can be compared — and if they disagree, the
        /// bench's is the one that decides what happens.
        public var graspables: [Graspable] = []

        public struct Graspable: Equatable, Sendable, Identifiable {
            public let name: String
            public let kilograms: Double
            public var id: String { name }
            public var grams: Double { kilograms * 1000 }
        }
    }

    public struct Success: Equatable, Sendable {
        public let policy: String
        public let rollouts: Int
        public let achieves: Int
        public let criterion: String
        public let randomised: String?
        public let medianHeight: Double?
    }

    public enum ReadError: Error, Equatable {
        case notJSON
        case bench(String)
        case wrongRate(Double)
        case empty

        public var message: String {
            switch self {
            case .notJSON: return "That was not a bench answering."
            case .bench(let text): return "The bench said: \(text)"
            case .wrongRate(let hz):
                return "That bench records at \(Int(hz)) Hz; this robot is \(Int(DuckModel.tickHz))."
            case .empty: return "The bench recorded nothing."
            }
        }
    }

    public static func readHealth(_ data: Data) throws -> Health {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        if let error = root["error"] as? String { throw ReadError.bench(error) }
        guard let bench = root["bench"] as? String else { throw ReadError.notJSON }
        return Health(bench: bench,
                      plant: root["plant"] as? String ?? "unstated",
                      tickHz: root["tickHz"] as? Double ?? DuckModel.tickHz,
                      cores: root["cores"] as? Int ?? 0,
                      policies: root["policies"] as? [String] ?? [],
                      trains: root["trains"] as? Bool ?? false,
                      trainsWhy: root["trainsWhy"] as? String,
                      graspables: (root["graspables"] as? [[String: Any]] ?? []).compactMap {
                          guard let name = $0["name"] as? String,
                                let mass = $0["mass"] as? Double else { return nil }
                          return Health.Graspable(name: name, kilograms: mass)
                      })
    }

    /// A recording, as the clip type every screen here already draws.
    ///
    /// THE RATE IS CHECKED, NOT ASSUMED. A bench running at another rate would
    /// produce a clip that plays at the wrong speed and looks merely odd, and
    /// "merely odd" is the failure that gets shipped.
    public static func readClip(_ data: Data, named name: String) throws -> DuckIntentClip {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        if let error = root["error"] as? String { throw ReadError.bench(error) }
        let hz = root["hz"] as? Double ?? DuckModel.tickHz
        guard hz == DuckModel.tickHz else { throw ReadError.wrongRate(hz) }
        let frames = root["frames"] as? [[Double]] ?? []
        guard !frames.isEmpty else { throw ReadError.empty }
        let roots = (root["roots"] as? [[Double]] ?? []).compactMap { row -> DuckIntentClip.Root? in
            guard row.count >= 7 else { return nil }
            return DuckIntentClip.Root(x: row[0], y: row[1], z: row[2],
                                       quaternion: (row[3], row[4], row[5], row[6]))
        }
        let commands = root["commands"] as? [[Double]] ?? []
        let ends = (root["endsUpright"] as? Bool ?? true) ? DuckIntentClip.Posture.standing
                                                          : .fallen
        return DuckIntentClip(
            name: name, hz: hz, frames: frames, roots: roots,
            netYaw: 0, loops: false, startsFrom: .standing, endsIn: ends,
            policy: root["policy"] as? String ?? "unknown",
            authored: false, environment: .bareFloor,
            credit: "Recorded on a bench on your network",
            telemetry: .init(actions: [], commands: commands, twists: []))
    }

    public static func readSuccess(_ data: Data) throws -> Success {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        if let error = root["error"] as? String { throw ReadError.bench(error) }
        guard let policy = root["policy"] as? String,
              let rollouts = root["rollouts"] as? Int,
              let achieves = root["achieves"] as? Int else { throw ReadError.notJSON }
        return Success(policy: policy, rollouts: rollouts, achieves: achieves,
                       criterion: root["criterion"] as? String ?? "unstated",
                       randomised: root["randomised"] as? String,
                       medianHeight: root["medianHeight"] as? Double)
    }
}
