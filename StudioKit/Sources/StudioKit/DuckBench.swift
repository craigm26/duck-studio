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

    /// THE SAME RULE THE MODEL ENDPOINT USES, because it is the same question.
    ///
    /// This used to be a second, narrower copy: no 100.64/10, so a tailnet host
    /// was refused here while `ModelEndpoint` accepted it with a comment
    /// explaining why Tailscale counts. The result was that a person could
    /// point the app's language model at their own machine across a tailnet and
    /// not the physics bench — the same host, the same privacy, two answers.
    /// It also blocked the arrangement this family is for: a phone, a bench and
    /// a GPU box on one tailnet and three different Wi-Fis.
    static func isLocal(_ host: String) -> Bool {
        ModelEndpoint.isLocalHost(host)
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

    /// Put a policy this phone made ONTO the bench.
    ///
    /// THE MISSING HALF OF A BENCH. Every other call here names a policy the
    /// bench already had, which meant a network blended or edited on the phone
    /// could be written to a file and never run by anything — the app could
    /// produce a policy and could not find out a single thing about it. This is
    /// the door.
    ///
    /// Base64 rather than multipart because the whole client is one
    /// `JSONSerialization` call and a bench is a thing on your desk, not an
    /// upload service. It costs a third more bytes on a LAN.
    public static func upload(_ address: Address, onnx: Data) throws -> Call {
        let body: [String: Any] = ["onnx": onnx.base64EncodedString()]
        return Call(method: "POST", url: URL(string: "\(address.base)/upload")!,
                    body: try JSONSerialization.data(withJSONObject: body))
    }

    /// What the bench called the file it just took.
    public static func readUploaded(_ data: Data) throws -> String {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        if let error = top["error"] as? String { throw ReadError.bench(error) }
        guard let name = top["policy"] as? String, !name.isEmpty else { throw ReadError.empty }
        return name
    }

    /// How far the duck actually got, out of a `/record` answer.
    ///
    /// WHY THIS EXISTS ALONGSIDE A SUCCESS RATE. The bench's criterion is "ends
    /// standing, trunk at least 100 mm up", and a duck that stands still passes
    /// it perfectly. Measured on this bench: `alpha_walking` averaged 75/25 with
    /// `BEST_alpha_stand` scores 16 of 16 while travelling two millimetres,
    /// where the walking policy it came from covers 1.207 m. Without a distance
    /// beside it, that rate reports a collapse as a triumph.
    ///
    /// BOTH NUMBERS, BECAUSE THE GAP BETWEEN THEM IS ALSO A FACT. `travelled`
    /// is start to finish; `path` is every step added up. A duck that thrashes
    /// in place has a long path and no travel, and a duck that topples has some
    /// of both — the pair tells them apart where either alone does not.
    public static func readTravel(_ data: Data) throws -> Travel {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        if let error = top["error"] as? String { throw ReadError.bench(error) }
        guard let roots = top["roots"] as? [[Double]], let first = roots.first,
              let last = roots.last, first.count >= 3, last.count >= 3 else {
            throw ReadError.empty
        }
        var path = 0.0
        for i in 1..<max(roots.count, 1) where roots[i].count >= 2 && roots[i - 1].count >= 2 {
            path += hypot(roots[i][0] - roots[i - 1][0], roots[i][1] - roots[i - 1][1])
        }
        return Travel(travelled: hypot(last[0] - first[0], last[1] - first[1]),
                      path: path, endHeight: last[2],
                      endsUpright: top["endsUpright"] as? Bool ?? false,
                      plantName: top["plantName"] as? String,
                      plantDigest: top["plantDigest"] as? String)
    }

    public struct Travel: Equatable, Sendable {
        public let travelled: Double
        public let path: Double
        public let endHeight: Double
        public let endsUpright: Bool
        public let plantName: String?
        public let plantDigest: String?

        public init(travelled: Double, path: Double, endHeight: Double, endsUpright: Bool,
                    plantName: String?, plantDigest: String?) {
            self.travelled = travelled; self.path = path; self.endHeight = endHeight
            self.endsUpright = endsUpright
            self.plantName = plantName; self.plantDigest = plantDigest
        }
    }

    /// A command that makes a walking policy actually walk.
    ///
    /// MEASURED, NOT CHOSEN. `alpha_walking` on this bench travels 7 mm in six
    /// seconds at vx = 0.15 — below the gait's threshold, so it just stands,
    /// which looks exactly like a broken policy and is not one. At 0.3 it
    /// covers 0.681 m and at 0.5, 1.207 m. Anything comparing two policies by
    /// distance has to command them past that threshold or it is comparing two
    /// ducks standing still.
    ///
    /// The half-second of nothing at the start is the settle: the bench drops
    /// the duck from about 123 mm and the bounce has to die before a command
    /// means anything.
    public static let walkingCommand: [Step] = [
        Step(at: 0), Step(at: 0.5, vx: 0.5),
    ]

    /// A `/perform` answer, as something a draft can keep.
    ///
    /// THE PLANT COMES OUT OF THE ANSWER AND NOWHERE ELSE. This used to take a
    /// `plant:` parameter, and the only caller passed
    /// `try? readHealth(performBody)?.plant ?? "the bench's own plant"` — a
    /// `readHealth` that always threw, because a `/perform` body has no `bench`
    /// key, so the literal fallback won every single time and was then printed
    /// as a fact about a world nobody had read. A reader is the wrong place to
    /// invent a value; a reader that cannot find a fact must return its
    /// absence, which is what the Optionals below are for.
    public static func readOutcome(_ data: Data, when: Date) throws
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
            plantName: top["plantName"] as? String,
            plantDigest: top["plantDigest"] as? String,
            policy: top["policy"] as? String ?? "unknown",
            achieves: achieves, rollouts: rollouts,
            criterion: top["criterion"] as? String ?? "stayed upright",
            medianHeight: top["medianHeight"] as? Double,
            peakJointRate: top["peakJointRate"] as? Double)
    }

    /// How long a plant digest is shown. Twelve hex characters — enough that
    /// two hand-built scenes will not collide by accident, short enough to sit
    /// in a caption. The whole digest is kept; only the printing is shortened.
    static let digestShown = 12

    /// Which world a run happened in, in one sentence — or plainly that
    /// nothing recorded it.
    ///
    /// IT LIVES IN ONE PLACE ON PURPOSE. Two screens print this and a future
    /// receipt will want it too, and the bug this replaces was exactly a
    /// second version of the sentence written at a call site: a placeholder
    /// that no bench ever produced, indistinguishable on screen from a
    /// measurement. There is no fallback string here. The three cases below
    /// are all the cases there are, and each says what it knows and stops.
    public static func plantSaid(name: String?, digest: String?) -> String {
        guard let name, !name.isEmpty else {
            // SAY WHAT IS KNOWN AND STOP. The first version of this sentence
            // read "This run predates the app recording which world it ran in",
            // which is a CAUSE, and the app cannot tell which cause it is: an
            // outcome stored before the bench reported a plant, a bench running
            // an older build that still does not, and a bench that simply did
            // not answer this time all arrive here identically. Naming one of
            // the three is exactly the move that produced the placeholder this
            // whole change exists to delete — a plausible sentence nothing
            // measured.
            return "Nothing recorded which world this ran in, so nothing here can tell you. "
                 + "A result with no world beside it cannot be compared with one that has "
                 + "another."
        }
        guard let digest, !digest.isEmpty else {
            return "On \(name). This bench will not say which bytes that was, and two benches "
                 + "can call different worlds by that name — so a result from this one cannot "
                 + "be matched to a result from another."
        }
        return "On \(name), sha256 \(digest.prefix(digestShown))."
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
        /// The bench's own prose description of its world.
        public let plant: String
        /// The plant file's bare name, if the bench says one.
        public let plantName: String?
        /// sha256 of that file's bytes, hex, if the bench says one. A bench
        /// older than this field is silent rather than wrong, so it is
        /// Optional and its absence gets its own sentence.
        public let plantDigest: String?
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

        /// Whether a result from this bench could be attributed to a world
        /// later, said in the present tense because this bench is answering
        /// now. A bench that will not identify its plant is still usable; it
        /// just cannot have its results compared with anyone else's, and the
        /// person pressing Run deserves to know that before they press it.
        public var plantSentence: String {
            guard let plantName, !plantName.isEmpty else {
                return "This bench does not say which world it runs, so a result from it "
                     + "cannot be matched to a result from another bench."
            }
            guard let plantDigest, !plantDigest.isEmpty else {
                return "Running \(plantName). It will not say which bytes that is, and two "
                     + "benches can call different worlds by that name."
            }
            return "Running \(plantName), sha256 \(plantDigest.prefix(DuckBench.digestShown))."
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
                      plantName: root["plantName"] as? String,
                      plantDigest: root["plantDigest"] as? String,
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
            credit: recordedCredit(plantName: root["plantName"] as? String,
                                   plantDigest: root["plantDigest"] as? String),
            telemetry: .init(actions: [], commands: commands, twists: []))
    }

    /// What a bench recording says about itself, WITH THE WORLD IT WAS MADE IN.
    ///
    /// WHY THE WORLD RIDES IN THE CREDIT LINE. `DuckIntentClip` is DuckKit's
    /// and has no field for a plant, so a recording used to arrive here, be
    /// filed as "Recorded on a bench on your network", and lose the two keys
    /// `/record` sends — the same attribution hole that `/perform` results had
    /// until `plantSaid` closed it. The credit is the one line that travels
    /// with a clip off this phone: `IntentExport` writes it out as the file's
    /// `note` and reads it back, so a recording shared with somebody else
    /// still names the world it came from.
    ///
    /// It has no case of its own for a missing world. `plantSaid` already has
    /// all three, and a second set of sentences here would be the duplicate
    /// that let a placeholder ship the first time.
    public static func recordedCredit(plantName: String?, plantDigest: String?) -> String {
        recordedHerePrefix + plantSaid(name: plantName, digest: plantDigest)
    }

    /// The opening of every credit this app writes for a clip recorded on a
    /// bench the person owns.
    static let recordedHerePrefix = "Recorded on a bench on your network. "

    /// Whether a credit line is one THIS app wrote, rather than one that
    /// arrived with somebody else's motion.
    ///
    /// IT EXISTS BECAUSE A CREDIT USED TO MEAN ONE THING AND NOW MEANS TWO.
    /// `ClipNote.provenance` captioned anything with a credit as "Contributed",
    /// which was right while the only credited clips came from strangers. Once
    /// a bench recording started carrying the world it ran in, that caption
    /// began telling people their own recording was somebody else's.
    public static func wasRecordedHere(_ credit: String) -> Bool {
        credit.hasPrefix(recordedHerePrefix)
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
