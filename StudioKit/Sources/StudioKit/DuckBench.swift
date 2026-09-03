import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DuckKit

/// A machine on your network that has physics, which this phone does not.
///
/// THE GAP THIS CLOSES. Microduck Studio can import a policy — Pollen's, or one
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

    public enum Refusal: Error, Equatable, Sendable {
        case empty
        case notLocal(String)
        case malformed(String)
        /// `/perform` clamps a track's blend into [0, 1]. A move authored at
        /// 2.1153 would be PLAYED at 1.0 and REPORTED as 2.1153, so it is not
        /// sent: a result carrying a blend the bench never ran is worse than
        /// no result.
        case blendWouldBeClamped(Double)

        public var message: String {
            switch self {
            case .blendWouldBeClamped(let blend):
                return DuckBench.blendWouldBeClamped(blend)
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
    ///
    /// IT CAN NOW CARRY A WORLD, AND THE TWO NEW KEYS ARE ABSENT RATHER THAN
    /// NULL WHEN IT DOES NOT. A request with neither is byte-identical to the
    /// one this call has always made — four keys and an optional policy — so
    /// an older bench receives exactly what it has always received and the
    /// bench's own parity fixture does not move. `world` is the `POST /world`
    /// body verbatim, spelled by the one function both routes call; `spawn` is
    /// where the duck is put down, because THE BANK CANNOT MOVE TO THE DUCK.
    public static func perform(_ address: Address, keys: [(at: Double, pose: [Double])],
                               seconds: Double, rollouts: Int = 8,
                               policy: String? = nil, blend: Double = 1,
                               world: DuckWorld.Plan? = nil,
                               spawn: DuckWorld.Point? = nil) throws -> Call {
        // REFUSED BEFORE A `URLRequest` EXISTS, the gate `setWorld` already
        // has: the bench would answer with the same reason, and a round trip
        // to be told what was already known is a round trip that makes a
        // person wait to be refused.
        if let refusal = world?.refusals.first { throw refusal }
        if blend > 1 || blend < 0 { throw Refusal.blendWouldBeClamped(blend) }
        var body: [String: Any] = [
            "track": keys.map { ["at": $0.at, "pose": $0.pose] },
            "seconds": seconds, "rollouts": rollouts, "blend": blend,
        ]
        if let policy { body["policy"] = policy }
        if let world { body["world"] = worldBody(world) }
        if let spawn { body["spawn"] = spawnBody(spawn) }
        return Call(method: "POST", url: URL(string: "\(address.base)/perform")!,
                    body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Where the duck is put down, as the three numbers the wire takes.
    ///
    /// A FLOOR POINT'S `z` IS ZERO AND A SPAWN'S IS A HEIGHT, so a point built
    /// without one is sent at the harness's own 0.120 m — the same default the
    /// bench applies to an absent `spawn.z`, and the height `/perform` has
    /// always started its first rollout at. Sending a literal 0 would put the
    /// trunk on the floor with the legs through it, which is not what "no
    /// height was given" means.
    static func spawnBody(_ point: DuckWorld.Point) -> [String: Any] {
        ["x": point.x, "y": point.y,
         "z": point.z == 0 ? DuckWorld.spawnHeight : point.z]
    }

    /// THE ONE SPELLER OF A WORLD BODY. `setWorld` and `perform` both call it,
    /// so the two routes can never drift apart — and they must not, because
    /// the bench validates both with the same function and a client that
    /// spelled them differently would be refused on one route and obeyed on
    /// the other for the same drawing.
    static func worldBody(_ plan: DuckWorld.Plan) -> [String: Any] {
        var body: [String: Any] = [
            "props": plan.props.map { ["name": $0.name, "x": $0.x, "y": $0.y] },
        ]
        if plan.clear {
            body["clear"] = true
        } else if let steps = plan.steps {
            body["steps"] = steps.map { ["x": $0.x, "top": $0.top] }
        }
        if !plan.walls.isEmpty {
            body["walls"] = plan.walls.map { ["name": $0] }
        }
        if let name = plan.name { body["name"] = name }
        if let ball = plan.ball { body["ball"] = ["x": ball.x, "y": ball.y] }
        return body
    }

    /// What a blend outside the box costs, said with both numbers.
    public static func blendWouldBeClamped(_ blend: Double) -> String {
        String(format: "This move's blend is %.4f, and the perform route runs a track at a "
                     + "blend between 0 and 1 — it would clamp it to 1.0 and report it as "
                     + "%.4f. It is not sent.", blend, blend)
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
    /// `parameters` are the canonical parameter bytes of the SAME network,
    /// sent beside the file so a desk bench — which loads the file through
    /// onnxruntime and can score it, but has nothing that dumps its
    /// parameters — can fold a gain into its last layer for `/tune`. Absent,
    /// the bench keeps the file only, and `/tune` on that name is refused with
    /// the reason.
    public static func upload(_ address: Address, onnx: Data, parameters: Data? = nil) throws -> Call {
        var body: [String: Any] = ["onnx": onnx.base64EncodedString()]
        if let parameters { body["parameters"] = parameters.base64EncodedString() }
        return Call(method: "POST", url: URL(string: "\(address.base)/upload")!,
                    body: try JSONSerialization.data(withJSONObject: body))
    }

    /// Put a network on a bench that has NO ONNX READER, by sending the
    /// canonical parameter bytes instead of a file.
    ///
    /// THIS IS A MEASURED FACT ABOUT THE PHONE BENCH AND IT CORRECTS A
    /// SENTENCE THIS APP WAS SHIPPING. `PhoneBenchReport.uploadNotWired` said
    /// "this bench cannot be handed a network", which is true of an `.onnx` and
    /// false of what the browser shell actually accepts. Its `makeSession`
    /// refuses anything that is not exactly `FLOAT_COUNT * 4` bytes and hands
    /// everything else to `policyforward.mjs` — which reads
    /// `DuckPolicy.canonicalParameterBytes`, the same layout `DuckEvidence`
    /// fingerprints a policy by and the same layout the app already exports to
    /// serve the nine bundled networks to that shell. So `/upload` was never
    /// closed; it was closed to ONNX.
    ///
    /// Verified against the shipped `site/phonebench` build under Node: a
    /// 791,584-byte canonical-bytes body came back
    /// `{"policy":"uploaded-27b1f53d1f26","bytes":791584}`, `/policy` swapped
    /// to it, and `/measure` ran three six-second rollouts on it in 1.8 s. An
    /// ONNX body to the same endpoint came back refused, with the shell's own
    /// sentence about not having a reader.
    ///
    /// THE WIRE FIELD IS STILL `onnx`, WHICH IS THE BENCH'S NAME AND NOT A
    /// DESCRIPTION. Renaming it here would mean a client that no bench
    /// understands; naming this function for what it sends is what keeps a
    /// caller from believing it is shipping a file.
    ///
    /// A DESK BENCH REFUSES THIS, and that is correct rather than a gap: it
    /// loads through onnxruntime, which wants a file. Send `upload(_:onnx:)`
    /// there. `DuckBench.Health.host.kind` is how a caller tells them apart.
    public static func uploadParameters(_ address: Address,
                                        canonicalBytes: Data) throws -> Call {
        let body: [String: Any] = ["onnx": canonicalBytes.base64EncodedString()]
        return Call(method: "POST", url: URL(string: "\(address.base)/upload")!,
                    body: try JSONSerialization.data(withJSONObject: body))
    }

    // MARK: - /tune — scoring a candidate where the trace is

    /// Run one candidate and weigh it, on the bench, against Pollen's own
    /// reward terms.
    ///
    /// WHY THE BENCH HAS TO DO THE WEIGHING AND THE PHONE CANNOT. Four of the
    /// six evaluable terms of `microduck_velocity_env_cfg` need something no
    /// bench answer carries. `track_linear_velocity`, `track_angular_velocity`
    /// and `body_ang_vel` all read the trunk's twist; `action_rate_l2` reads
    /// the network's own output. `/state` and `/intent` answer with a position,
    /// a quaternion and fourteen joint angles, and `/record` adds the commands
    /// — none of them carry a velocity or an action. So a client that scored a
    /// search from those answers would be scoring `upright` and `pose` alone,
    /// and `DuckTuner.notYet` has the measurement that says what that does: on
    /// those two terms the standing policy beats the walking policy by 18%
    /// while travelling one millimetre against 1231. The bench has the trace in
    /// front of it. Nothing else does.
    ///
    /// IT TAKES THE RESIDUAL RATHER THAN A FILE, and that is the design. The
    /// alternative is uploading a folded `.onnx` per candidate — 791,584 bytes
    /// through base64 for every one of 276 episodes — where the residual is 28
    /// numbers and the bench already holds the base network. It also keeps the
    /// FOLD in one implementation: the bench folds it the way
    /// `DuckPolicyWriter.folding` does, and `duckkit`'s own tests are what
    /// prove that arithmetic exact.
    ///
    /// THE REQUEST NAMES THE TERMS IT WANTS. A bench that cannot compute one of
    /// them must say so by name in `refused` rather than omit it from `terms`:
    /// two of the six weights are negative, so a silently missing term reads as
    /// the best possible value of the thing it punishes, and
    /// `DuckTuner.reward(_:)` throws rather than let that happen.
    ///
    /// ```
    /// POST /tune
    /// {
    ///   "policy":   "alpha_walking.onnx",   // the base, by the bench's own name
    ///   "gain":     [14 doubles],           // policy slots, mouth excluded
    ///   "offset":   [14 doubles],           // radians of RAW action, same order
    ///   "seconds":  6,                      // per episode
    ///   "drops":    [0.121, 0.125, 0.129],  // metres; one episode each
    ///   "schedule": [[0, {"vx":0,"vy":0,"vyaw":0}], [0.5, {"vx":0.5,"vy":0,"vyaw":0}]],
    ///   "terms":    ["upright", "track_linear_velocity", "track_angular_velocity",
    ///                "pose", "body_ang_vel", "action_rate_l2"]
    /// }
    ///
    /// 200
    /// {
    ///   "policy":   "alpha_walking.onnx",
    ///   "episodes": 3,
    ///   "standing": 3,                      // episodes ending upright, trunk >= 100 mm
    ///   "criterion": "ends standing, trunk at least 100 mm up",
    ///   "travelled": 1.207,                 // metres, MEDIAN over the episodes
    ///   "terms":    {"upright": 0.9467, "pose": 0.6353, ...},   // per-tick means, over ALL episodes
    ///   "perDrop":  [ {"drop": 0.121, "travelled": 1.19, "standing": true,
    ///                  "terms": {"upright": 0.9471, ...}},        // one entry per drop, in order
    ///                 …],
    ///   "refused":  [{"name": "air_time", "why": "no foot-contact sensor in scene.mjb"}],
    ///   "plantName": "scene.mjb",
    ///   "plantDigest": "3f8c9ab9b409…",
    ///   "seconds": 6
    /// }
    /// ```
    ///
    /// `perDrop` IS NOT DECORATION, IT IS THE NOISE FLOOR. The only question
    /// that matters at the end of a search is whether a gain survived drop
    /// heights the search never saw, and that has to be read against how much
    /// the UNCHANGED network's own reward wobbles across those same drops. That
    /// wobble is a spread over episodes, and an aggregate mean cannot produce
    /// it: a client handed only the mean would have to invent a floor, which is
    /// the one number that decides whether the whole run meant anything. One
    /// setting's travel has been measured to vary by up to 273 mm across this
    /// drop range, so the spread is large and assuming it away is not
    /// available.
    ///
    /// A bench that has no `/tune` answers `{"error": "no /tune here"}`, which
    /// is what the browser shell already returns for an unknown path, and the
    /// screen reads that as "this bench cannot score a search" rather than as a
    /// failure.
    public static func tune(_ address: Address, policy: String,
                            gain: [Double], offset: [Double],
                            seconds: Double, drops: [Double],
                            schedule: [Step], terms: [String]) throws -> Call {
        let body: [String: Any] = [
            "policy": policy, "gain": gain, "offset": offset,
            "seconds": seconds, "drops": drops,
            "schedule": schedule.map(\.wire), "terms": terms,
        ]
        return Call(method: "POST", url: URL(string: "\(address.base)/tune")!,
                    body: try JSONSerialization.data(withJSONObject: body))
    }

    // MARK: - /world — changing what the duck is standing in

    /// Ask what world the bench is standing in.
    ///
    /// IT IS A READ AND IT IS THE ONLY HONEST SOURCE. A screen that drew the
    /// scene it had just sent would draw a staircase at y = 0 that is really
    /// 1.305 m to the duck's left, at whatever height the scene asked for
    /// rather than the 200 mm every block in the bank actually is. So this is
    /// called after every write, on connecting, and whenever the peer changes.
    ///
    /// A BENCH WITHOUT THE ROUTE IS NOT AN ERROR. Every shell in this family
    /// answers an unknown path with `{"error": "no /world here"}`, which
    /// arrives as `ReadError.bench` carrying the bench's own words — and the
    /// screen prints `DuckWorld.noWorldRoute` beside a picker it disables,
    /// exactly as `/tune` already does.
    public static func world(_ address: Address) -> Call {
        Call(method: "GET", url: URL(string: "\(address.base)/world")!, body: nil)
    }

    /// Stand the bench in a world somebody chose.
    ///
    /// IT REFUSES BEFORE IT SENDS. `DuckWorld.plan(for:on:)` has already worked
    /// out whether the bank can hold this scene, and a plan carrying a refusal
    /// is not a request — the bench would answer 400 with the same reason, and
    /// a round trip to be told what was already known is a round trip that
    /// makes a person wait to be refused.
    ///
    /// `clear` AND `steps` ARE NEVER BOTH SENT. The bench refuses a body
    /// carrying both — "say one or the other: `clear: true` for a bare floor,
    /// or `steps` to lay them" — because clearing and laying in one request is
    /// two intentions with no order between them. A scene always says what its
    /// steps are, even when the answer is none; `clear` is the spelling for the
    /// picker entry that is only about parking the bank.
    ///
    /// THE BALL IS ABSENT RATHER THAN NULL WHEN IT IS NOT BEING MOVED. `null`
    /// is a real request on this route and it means "take the ball out", which
    /// the bench answers with an `unexpressed` row rather than an empty world:
    /// the ball is a permanent body on a freejoint. Absent means "leave it
    /// where it is", which is what a scene that simply did not mention it
    /// wants.
    public static func setWorld(_ address: Address, _ plan: DuckWorld.Plan) throws -> Call {
        if let refusal = plan.refusals.first { throw refusal }
        return Call(method: "POST", url: URL(string: "\(address.base)/world")!,
                    body: try JSONSerialization.data(withJSONObject: worldBody(plan)))
    }

    /// What world the bench says it is standing in. `GET /world` and the answer
    /// to `POST /world` are the same block, deliberately: a write that had a
    /// different shape from a read would be two things to keep in step.
    ///
    /// LENIENT ABOUT THE BANK AND THE ARENA, STRICT ABOUT NOTHING. A bench that
    /// omits either is answered from `DuckWorld.Bank.pinned` — the
    /// transcription `WorldConstantsFixtureTests` holds against
    /// `duck-sounds/site/stairs.js` — because those numbers are compiled into
    /// the plant and a bench that does not repeat them has not changed them.
    /// Where the bench DOES say, the bench wins.
    public static func readWorld(_ data: Data) throws -> DuckWorld {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        return try readWorld(top)
    }

    /// THE ONE READER, over a dictionary rather than bytes.
    ///
    /// `/perform` NESTS THE WHOLE READBACK UNDER `stood`, and it has to: this
    /// reader takes `top["world"]` as the `{set, name}` pair, so a `/perform`
    /// answer that spelled its world at the top level would collide with that.
    /// Nesting the block whole means both routes are parsed by this function
    /// and there is no second reader to keep in step — which is what
    /// `testTheStoodBlockIsParsedByTheSameReaderAsTheWorldRoute` holds.
    static func readWorld(_ top: [String: Any]) throws -> DuckWorld {
        if let error = top["error"] as? String { throw ReadError.bench(error) }

        let block = top["world"] as? [String: Any] ?? [:]
        let bankBlock = top["bank"] as? [String: Any] ?? [:]
        let pinned = DuckWorld.Bank.pinned
        let bank = DuckWorld.Bank(
            count: bankBlock["count"] as? Int ?? pinned.count,
            y: bankBlock["y"] as? Double ?? pinned.y,
            halfDepth: bankBlock["halfDepth"] as? Double ?? pinned.halfDepth,
            halfWidth: bankBlock["halfWidth"] as? Double ?? pinned.halfWidth,
            halfHeight: bankBlock["halfHeight"] as? Double ?? pinned.halfHeight,
            arenaInner: (top["arena"] as? [String: Any])?["innerX_m"] as? Double
                ?? pinned.arenaInner,
            wallHeight: pinned.wallHeight)

        let arenaBlock = top["arena"] as? [String: Any]
        let walls = (arenaBlock?["walls"] as? [[String: Any]] ?? []).compactMap {
            row -> DuckWorld.Wall? in
            guard let name = row["name"] as? String else { return nil }
            return DuckWorld.Wall(name: name,
                                  x: row["x"] as? Double ?? 0,
                                  y: row["y"] as? Double ?? 0,
                                  halfThickness: row["halfThickness"] as? Double ?? 0,
                                  height: row["height"] as? Double ?? pinned.wallHeight,
                                  halfLength: row["halfLength"] as? Double ?? 0,
                                  along: row["along"] as? String ?? "")
        }
        let arena = walls.isEmpty && arenaBlock == nil
            ? DuckWorld.Arena.pinned
            : DuckWorld.Arena(
                walls: walls.isEmpty ? DuckWorld.Arena.pinned.walls : walls,
                innerX: arenaBlock?["innerX_m"] as? Double ?? pinned.arenaInner,
                innerY: arenaBlock?["innerY_m"] as? Double ?? pinned.arenaInner,
                why: arenaBlock?["why"] as? String)

        let steps = (top["steps"] as? [[String: Any]] ?? []).compactMap {
            row -> DuckIntentClip.Environment.Step? in
            guard let x = row["x"] as? Double,
                  let upper = row["top"] as? Double else { return nil }
            return DuckIntentClip.Environment.Step(
                x: x,
                y: row["y"] as? Double ?? bank.y,
                top: upper,
                halfDepth: row["halfDepth"] as? Double ?? bank.halfDepth,
                halfWidth: row["halfWidth"] as? Double ?? bank.halfWidth,
                halfHeight: row["halfHeight"] as? Double ?? bank.halfHeight)
        }

        let props = (top["props"] as? [[String: Any]] ?? []).compactMap {
            row -> DuckWorld.Seated? in
            guard let name = row["name"] as? String else { return nil }
            guard let at = readPoint(row["at"]) else { return nil }
            return DuckWorld.Seated(name: name, x: at.x, y: at.y,
                                    kilograms: row["mass"] as? Double)
        }

        return DuckWorld(
            isSet: block["set"] as? Bool ?? false,
            name: block["name"] as? String,
            steps: steps,
            ball: readPoint(top["ball"]),
            ballRadius: top["ballRadius"] as? Double,
            props: props,
            unexpressed: (top["unexpressed"] as? [[String: Any]] ?? []).compactMap {
                row -> DuckWorld.Unexpressed? in
                guard let what = row["what"] as? String else { return nil }
                return DuckWorld.Unexpressed(what: what,
                                             index: row["index"] as? Int,
                                             field: row["field"] as? String,
                                             asked: readSaid(row["asked"]),
                                             got: readSaid(row["got"]),
                                             why: row["why"] as? String ?? "")
            },
            bank: bank, arena: arena,
            // HOW MANY BLOCKS THIS RUN LEFT BELOW THE FLOOR is a fact about
            // the run, not about the transcription, which is why it is here
            // and not on `Bank`.
            parked: bankBlock["parked"] as? Int,
            plantName: top["plantName"] as? String,
            plantDigest: top["plantDigest"] as? String)
    }

    /// A place, however the bench spells it.
    ///
    /// TWO SPELLINGS BECAUSE THE BENCH ALREADY HAS TWO. `/state` answers the
    /// ball as `[x, y, z]` — the shape `measure_success.mjs` scores against —
    /// and the world block answers it as an object, which is what a readback
    /// with named fields wants. Accepting both here is three lines; a reader
    /// per spelling is two readers to keep in step.
    static func readPoint(_ raw: Any?) -> DuckWorld.Point? {
        if let row = raw as? [Double], row.count >= 2 {
            return DuckWorld.Point(x: row[0], y: row[1], z: row.count >= 3 ? row[2] : 0)
        }
        if let box = raw as? [String: Any],
           let x = box["x"] as? Double, let y = box["y"] as? Double {
            return DuckWorld.Point(x: x, y: y, z: box["z"] as? Double ?? 0)
        }
        return nil
    }

    /// `asked` and `got` are for a person to read, and the bench sends whatever
    /// the value actually was.
    ///
    /// FOUR SHAPES, ALL OF THEM REAL. The live `/world` answer carries
    /// `"asked": 0` and `"got": 1.305` as bare numbers, `"asked": "broom"` as a
    /// string, and `"got": ["block_a", "block_b", …]` as a list — because "what
    /// this plant has instead" is a list. A reader that took only strings would
    /// drop the two rows that matter most, and one that formatted numbers with
    /// a unit would be inventing metres for a field that might be a count.
    static func readSaid(_ raw: Any?) -> String? {
        if let text = raw as? String { return text }
        if let list = raw as? [Any] {
            let parts = list.compactMap { readSaid($0) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        if let number = raw as? Double { return String(format: "%g", number) }
        if let number = raw as? Int { return String(number) }
        return nil
    }

    /// EVERY PATH A `Call` FROM THIS TYPE CAN NAME. The phone's own loopback
    /// server forwards exactly this set to the page and 404s the rest, so a
    /// new endpoint added to the bench and to a factory here but not to this
    /// list would ship with its Start button dead on the bench the app
    /// carries — which is how `/tune` shipped, once. A test builds one call
    /// from every factory and checks it against this list.
    public static let routes: Set<String> = [
        "/health", "/state", "/reset", "/intent", "/stop",
        "/policy", "/record", "/measure", "/perform", "/upload", "/tune",
        // The stairs challenge. `/climb` scores ONE grid cell of one intent;
        // `/climb/grid` answers the cell list so a client never retypes it.
        // See `DuckBenchClimb.swift`.
        "/climb", "/climb/grid",
        // The ball challenge. `/chase` scores ONE grid cell of one entrant;
        // `/chase/grid` answers the cell list so a client never retypes it.
        // See `DuckBenchChase.swift`.
        "/chase", "/chase/grid",
        // Changing what the duck is standing in, and reading back what the
        // bank could actually express. See `DuckWorld.swift`.
        "/world",
    ]

    /// What a `/tune` answer says.
    public struct Tuned: Equatable, Sendable {
        public let policy: String
        public let episodes: Int
        public let standing: Int
        public let criterion: String
        /// Metres, median over the episodes. THE NUMBER THAT KEEPS THE REWARD
        /// HONEST — see `PolicyBlend.Behaviour`.
        public let travelled: Double
        /// Each requested term's per-tick mean. Weighting is the client's job
        /// and `DuckTuner.terms` holds the weights, so a bench cannot quietly
        /// change what a reward means.
        public let terms: [String: Double]
        /// One entry per drop height, in the order they were asked for. Empty
        /// from a bench that reports only the aggregate — which is a bench a
        /// noise floor cannot be measured from, and `DuckTuner.noiseFloor`
        /// refuses rather than invents one.
        public let perDrop: [Episode]
        /// What this bench would not compute, by name and with the reason.
        public let refused: [(name: String, why: String)]

        public struct Episode: Equatable, Sendable {
            public let drop: Double
            public let travelled: Double
            public let standing: Bool
            public let terms: [String: Double]
            /// The plain net displacement, beside the commanded projection:
            /// far apart, the duck walked but not where it was told.
            public let netDisplacement: Double
            public let diverged: Bool
            public init(drop: Double, travelled: Double, standing: Bool, terms: [String: Double],
                        netDisplacement: Double = 0, diverged: Bool = false) {
                self.drop = drop; self.travelled = travelled; self.standing = standing
                self.terms = terms; self.netDisplacement = netDisplacement; self.diverged = diverged
            }
        }
        public let plantName: String?
        public let plantDigest: String?
        /// Episodes that were actually scored, and the ones that diverged —
        /// a state or action that stopped being a duck — which the bench
        /// names in `perDrop`, counts here, and leaves OUT of `terms`. A
        /// candidate with any is a failed candidate, never a scored one.
        public let scored: Int
        public let diverged: Int
        /// The LEAST any drop travelled, for a guard that must not let one
        /// dead episode hide behind two live ones (the median can).
        public let minTravelled: Double
        /// The reward config the bench scored under, when it says.
        public let config: String?

        public static func == (a: Tuned, b: Tuned) -> Bool {
            a.policy == b.policy && a.episodes == b.episodes && a.standing == b.standing
                && a.criterion == b.criterion && a.travelled == b.travelled
                && a.terms == b.terms && a.perDrop == b.perDrop && a.plantName == b.plantName
                && a.plantDigest == b.plantDigest
                && a.refused.map(\.name) == b.refused.map(\.name)
                && a.refused.map(\.why) == b.refused.map(\.why)
                && a.scored == b.scored && a.diverged == b.diverged
                && a.minTravelled == b.minTravelled && a.config == b.config
        }
    }

    /// Read one, or say which bench cannot do this.
    ///
    /// A BENCH WITHOUT `/tune` IS NOT AN ERROR STATE. Every shell in this
    /// family answers an unknown path with `{"error": "no /tune here"}`, and
    /// that is a fact about the bench rather than a fault — so it comes back as
    /// `ReadError.bench`, carrying the bench's own words, and the screen says
    /// what it means instead of showing a failure.
    public static func readTuned(_ data: Data) throws -> Tuned {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ReadError.notJSON
        }
        if let error = top["error"] as? String { throw ReadError.bench(error) }
        guard let episodes = top["episodes"] as? Int, episodes > 0,
              let terms = top["terms"] as? [String: Double] else {
            throw ReadError.empty
        }
        return Tuned(
            policy: top["policy"] as? String ?? "unknown",
            episodes: episodes,
            standing: top["standing"] as? Int ?? 0,
            criterion: top["criterion"] as? String ?? "unstated",
            travelled: top["travelled"] as? Double ?? 0,
            terms: terms,
            perDrop: (top["perDrop"] as? [[String: Any]] ?? []).compactMap {
                guard let drop = $0["drop"] as? Double,
                      let each = $0["terms"] as? [String: Double] else { return nil }
                return Tuned.Episode(drop: drop,
                                     travelled: $0["travelled"] as? Double ?? 0,
                                     standing: $0["standing"] as? Bool ?? false,
                                     terms: each,
                                     netDisplacement: $0["netDisplacement"] as? Double ?? 0,
                                     diverged: $0["diverged"] as? Bool ?? false)
            },
            refused: (top["refused"] as? [[String: Any]] ?? []).compactMap {
                guard let name = $0["name"] as? String else { return nil }
                return (name, $0["why"] as? String ?? "unstated")
            },
            plantName: top["plantName"] as? String,
            plantDigest: top["plantDigest"] as? String,
            scored: top["scored"] as? Int ?? episodes,
            diverged: top["diverged"] as? Int ?? 0,
            // An older bench reports only the median; the least is then
            // unknown and the median stands in, which is the looser guard
            // rather than a false one.
            minTravelled: top["minTravelled"] as? Double ?? (top["travelled"] as? Double ?? 0),
            config: top["config"] as? String)
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
    /// `alpha_stand` scores 16 of 16 while travelling two millimetres,
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
    /// THE HALF-SECOND OF NOTHING AT THE START IS NOT THE SETTLE. The bench
    /// settles on its own — 25 ticks under the standing policy before the
    /// schedule's t = 0 — so this step is an extra neutral half-second INSIDE
    /// the measured window, under the candidate. `/tune` scores it: at six
    /// seconds that is 25 of 300 ticks commanded (0, 0, 0), under the pose
    /// term's tighter standing tolerances. It is kept deliberately, because a
    /// candidate that cannot stand for half a second before walking is not
    /// one anybody wants folded, and the fixtures behind the parity gate were
    /// recorded with it.
    public static let walkingCommand: [Step] = [
        Step(at: 0), Step(at: 0.5, vx: 0.5),
    ]

    /// A SECOND COMMAND, AND IT IS A DEFECT FIX RATHER THAN A PRECAUTION.
    ///
    /// The search runs under `walkingCommand` and the held-out check ran under
    /// it too, so a winner was only ever asked to keep the walk in the one
    /// direction it was tuned in. Measured over eight seeds of the shipped
    /// schedule: four of the eight winners collapsed SIDEWAYS travel to
    /// 1.6-2.0% of the unchanged network's while gaining +0.92 to +0.98 of
    /// reward, and every one of the eight passed every gate this app has. The
    /// other four kept 82-86%. There is no middle, and nothing looked — so
    /// whether somebody's tuned policy could still step sideways was a coin
    /// flip that no screen mentioned.
    ///
    /// The same asymmetry is what the objective's `kept` factor exists to
    /// refuse; it was simply never evaluated anywhere but forwards.
    public static let sidewaysCommand: [Step] = [
        Step(at: 0), Step(at: 0.5, vy: 0.3),
    ]

    /// And a turning one, for the same reason: a yaw-suppression win is
    /// exactly what collapses under a command that asks for yaw. Measured on
    /// the seed-A winner: 0.261 m -> 0.018 m, a 93% loss, while the reward
    /// went UP by 0.406.
    public static let turningCommand: [Step] = [
        Step(at: 0), Step(at: 0.5, vx: 0.3, vyaw: 0.6),
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
    /// `askedForWorld` RECORDS WHAT THE CALLER SENT, and there is no field on
    /// the wire for it. `stood` is deliberately absent from a no-world answer
    /// — that is what keeps the bench's own parity fixture frozen — so "no
    /// world was sent" and "a world was sent to a bench too old to answer with
    /// one" arrive as the same bytes. Only the caller can tell them apart, and
    /// `BenchOutcome.worldStanding` is where the difference becomes a
    /// sentence.
    public static func readOutcome(_ data: Data, when: Date,
                                   askedForWorld: Bool = false) throws
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
            peakJointRate: top["peakJointRate"] as? Double,
            laid: try readStood(top),
            askedForWorld: askedForWorld)
    }

    /// The `stood` block, narrowed to the shape a draft can hold, or nil when
    /// the answer carried none.
    ///
    /// THE FOUR KEYS ONLY THIS ROUTE HAS live beside the readback rather than
    /// inside it: `spawn` is where the duck was put down, `sag_mm` is how far
    /// the lowest-sitting block had fallen by the end of the same tick the
    /// positions were read on. Both are facts about a run, and neither exists
    /// on `GET /world`.
    static func readStood(_ top: [String: Any]) throws -> Pipeline.LaidWorld? {
        guard let block = top["stood"] as? [String: Any] else { return nil }
        let world = try readWorld(block)
        // A BLOCK THAT SAYS NO WORLD STOOD IS NOT A LAID WORLD. A spawn-only
        // /perform answers with a `stood` whose world.set is false, every
        // block listed where it booted and nothing pinned; reading that as
        // "laid" captioned the bench's own scattered blocks as a flight the
        // bench re-pinned every tick. Nothing stood, so nothing is returned,
        // and the outcome says the bench's own world in its own words.
        guard world.isSet else { return nil }
        let spawn = readPoint(block["spawn"]).map {
            Pipeline.LaidWorld.Point(x: $0.x, y: $0.y, z: $0.z)
        }
        return world.laid(spawn: spawn, sagMillimetres: block["sag_mm"] as? Double)
    }

    /// A `/perform` answer as a picture, IN THE WORLD IT WAS READ BACK IN.
    ///
    /// `/perform` has always answered with frames, roots and commands, and
    /// this kit has always thrown them away: nothing in the app had ever drawn
    /// an authored run. This is the first reader of them, and the environment
    /// it hands the stage is the READBACK's — not the scene that was sent, and
    /// not a hardcoded bare floor. A run with no world read back gets the bare
    /// floor, which is what a bench with no `stood` block actually ran on
    /// except for the fourteen blocks stacked off to one side that
    /// `DuckWorld.worldSaid(.benchsOwn)` names.
    public static func readPerformedClip(_ data: Data, named name: String,
                                         laid: Pipeline.LaidWorld?) throws -> DuckIntentClip {
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
            // THE MOTION WAS AUTHORED AND THAT IS ALL THIS FLAG MEANS. It says
            // nothing about where the environment came from, which is why no
            // caption in this app is keyed on it — see `StageCaption.RunWorld`.
            authored: root["authored"] as? Bool ?? true,
            environment: laid?.asEnvironment ?? .bareFloor,
            credit: recordedCredit(plantName: root["plantName"] as? String,
                                   plantDigest: root["plantDigest"] as? String),
            telemetry: .init(actions: [], commands: commands, twists: []))
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

        /// WHERE THE PHYSICS ACTUALLY RAN, when the bench is new enough to say.
        ///
        /// `duck-bench/5` added this and nothing older has it, so it is
        /// Optional and its absence is silence rather than a guess: a saved
        /// measurement from a `duck-bench/4` names no machine, and inventing
        /// "a bench on your network" for it would be writing down something
        /// nobody measured. That distinction is the whole point — this phone
        /// now answers the same ten endpoints from a WebView on a loopback
        /// port, so "which bench" is no longer answered by the address.
        public var host: Host? = nil

        public struct Host: Equatable, Sendable {

            /// The only field a caller may branch on.
            ///
            /// OPTIONAL BECAUSE THE BENCH IS ALLOWED TO SAY A THIRD WORD. A
            /// bench built later on hardware neither of these describes should
            /// come through as "this app does not know that word" rather than
            /// be rounded to whichever case is nearer — `kindSaid` keeps what
            /// it actually said so a reader is never shown a machine the bench
            /// did not claim.
            public enum Where: String, Sendable { case desk, phone }

            public let kind: Where?
            /// The word the bench used, verbatim, even when it is not one of
            /// the two above.
            public let kindSaid: String
            /// For a person reading a saved result, never for a branch.
            public let device: String
            public let engine: String
            /// What one control tick cost here, measured at boot by the bench
            /// rather than claimed. Nil when the bench did not measure it.
            public let tickMillis: Double?

            public init(kind: Where?, kindSaid: String, device: String,
                        engine: String, tickMillis: Double?) {
                self.kind = kind; self.kindSaid = kindSaid
                self.device = device; self.engine = engine; self.tickMillis = tickMillis
            }
        }

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
                      },
                      host: readHost(root["host"]))
    }

    /// The `host` block, or nil when the bench did not send one.
    ///
    /// LENIENT ABOUT THE FIELDS AND STRICT ABOUT THE BLOCK. A bench that sends
    /// `host` has said which machine it is, and that is worth keeping even if
    /// one string inside is missing — but a bench that sends nothing must come
    /// through as nothing, because "unstated" and "empty" are the two answers
    /// this Optional exists to keep apart. `tickMillis` is explicitly allowed
    /// to be JSON null, which arrives as `NSNull` and casts to nil here.
    static func readHost(_ raw: Any?) -> Health.Host? {
        guard let block = raw as? [String: Any] else { return nil }
        let said = block["kind"] as? String ?? ""
        return Health.Host(kind: Health.Host.Where(rawValue: said),
                           kindSaid: said,
                           device: block["device"] as? String ?? "",
                           engine: block["engine"] as? String ?? "",
                           tickMillis: block["tickMillis"] as? Double)
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
