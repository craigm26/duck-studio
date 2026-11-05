import Foundation

/// Dream Labs' Dream-1, reached with the person's own key, through the bridge.
///
/// WHAT DREAM-1 IS. A vision-language-action model: the duck's last few camera
/// frames, what it was last told to do, and a task in words go out, and 48
/// rows of what to do next come back. Dream Labs' public model drives two-arm
/// YAM robots; a duck runs a model fine-tuned on duck recordings, which the
/// person makes on platform.dreamlabs.ai. `Model.fits` says which of theirs a
/// duck can run.
///
/// THE KEY LIVES ON THE ROBOT'S COMPUTER, NOT IN THIS APP. `dream.key.set`
/// hands it to the bridge once (OpenCastor's `castor.microduck_bridge`, which
/// checks it with Dream Labs before keeping it), and every later request is
/// answered with the bridge's copy. Nothing here stores it, and nothing the
/// bridge answers carries it back: a key is named by its last four characters.
///
/// THE BRIDGE MOVES NOTHING. `dream.act` answers rows; `DreamPilot` plays them
/// through the same `robot.move` the sticks send, inside the same envelope,
/// past the same deadman.
public struct DuckDream: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Verb: String, CaseIterable, Sendable {
        case status = "dream.status"
        case keySet = "dream.key.set"
        case keyCheck = "dream.key.check"
        case keyClear = "dream.key.clear"
        case act = "dream.act"
        case end = "dream.end"
    }

    public let verb: Verb
    let key: String?
    public let checkpoint: String?
    public let prompt: String?
    /// Camera role to base64 JPEG frames, oldest first.
    public let frames: [String: [String]]
    /// State part to its values.
    public let state: [String: [Double]]
    public let reset: Bool

    private init(_ verb: Verb, key: String? = nil, checkpoint: String? = nil, prompt: String? = nil,
                 frames: [String: [String]] = [:], state: [String: [Double]] = [:], reset: Bool = false) {
        self.verb = verb
        self.key = key
        self.checkpoint = checkpoint
        self.prompt = prompt
        self.frames = frames
        self.state = state
        self.reset = reset
    }

    public static let status = DuckDream(.status)
    public static func keySet(_ key: String) -> DuckDream { DuckDream(.keySet, key: key) }
    public static let keyCheck = DuckDream(.keyCheck)
    public static let keyClear = DuckDream(.keyClear)
    public static let end = DuckDream(.end)
    public static func act(checkpoint: String, prompt: String, frames: [String: [String]],
                           state: [String: [Double]], reset: Bool) -> DuckDream {
        DuckDream(.act, checkpoint: checkpoint, prompt: prompt, frames: frames, state: state, reset: reset)
    }

    /// NEVER THE KEY. A call is printed in logs and test failures; the key is not.
    public var description: String {
        verb == .keySet ? "\(verb.rawValue)(key: \(DuckDream.hint(key)))" : verb.rawValue
    }
    public var debugDescription: String { description }

    public static func hint(_ key: String?) -> String {
        guard let key, !key.isEmpty else { return "none" }
        return key.count >= 8 ? "…" + key.suffix(4) : "set"
    }

    /// The JSON-RPC params. `embodiment` rides on the key verbs so the bridge
    /// can say which models fit a duck.
    var wire: [String: Any]? {
        switch verb {
        case .status, .keyClear, .end:
            return nil
        case .keySet:
            return ["key": key ?? "", "embodiment": DuckDream.microduck]
        case .keyCheck:
            return ["embodiment": DuckDream.microduck]
        case .act:
            return ["checkpoint": checkpoint ?? "", "prompt": prompt ?? "",
                    "frames": frames, "state": state, "reset": reset]
        }
    }

    /// The key as the bridge will take it, or why not. The same rule the bridge applies.
    public static func cleaned(_ typed: String) -> Result<String, ReadError> {
        let key = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return .failure(.refused(Words.emptyKey)) }
        if key.count > 256 || !key.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }) {
            return .failure(.refused(Words.badKey))
        }
        return .success(key)
    }

    static let shape = DuckDream.status

    // MARK: - the Microduck, as Dream-1 reads it

    /// OPENCASTOR'S CONVENTION FOR A DUCK (`castor.dream.MICRODUCK_EMBODIMENT`),
    /// copied, not invented here: state and action are the walk command
    /// `[vx, vy, vyaw]`, the camera is the head's. A model trained on anything
    /// else is not offered.
    public static let microduck: [String: Any] = [
        "state": ["velocity": [0, 3]],
        "action": ["velocity": [0, 3]],
        "video": ["head": "observation.images.head"],
    ]
    public static let cameraRole = "head"
    public static let part = "velocity"

    // MARK: - what came back

    public struct Model: Equatable, Sendable, Identifiable {
        public let id: String
        public let owner: String
        public let servable: Bool
        public let fits: Bool
        /// Where it runs: Dream Labs' servers, or this phone (a driver from `PhoneDrivers`).
        public var kind: Kind = .cloud
        /// For a phone driver, its own name for itself (the manifest's label).
        public var title: String? = nil
        public var label: String {
            if kind == .phone { return Words.onPhone(title ?? id) }
            return owner == "mine" ? id : "\(id) (\(owner))"
        }

        public enum Kind: Equatable, Sendable { case cloud, phone }

        public init(id: String, owner: String, servable: Bool, fits: Bool, kind: Kind = .cloud, title: String? = nil) {
            self.id = id; self.owner = owner; self.servable = servable; self.fits = fits
            self.kind = kind; self.title = title
        }
    }

    public struct KeyAnswer: Equatable, Sendable {
        /// The key's last four characters, or nil when none is saved.
        public let key: String?
        public let models: [Model]
        public var duckModels: [Model] { models.filter { $0.fits && $0.servable } }
    }

    public struct Chunk: Equatable, Sendable {
        public let rows: [DuckDrive.Twist]
        public let sessionID: String?

        public init(rows: [DuckDrive.Twist], sessionID: String?) {
            self.rows = rows; self.sessionID = sessionID
        }
    }

    public enum ReadError: Error, Equatable {
        case refused(String)
        /// The model is starting on Dream Labs' side (DA-2000 `pool_warming`): up to an hour.
        case warming(Double?)
        /// Dream Labs is busy for another reason it says may pass (DA-2000 `rate_limited`,
        /// `pool_full`, `queue_timeout`, `max_serves`): try again shortly.
        case busy(String, Double?)
        case notADreamAnswer

        public var message: String {
            switch self {
            case .refused(let why): return why
            case .warming(let wait):
                return wait.map { String(format: Words.warmingFor, $0) } ?? Words.warming
            case .busy(let reason, _): return Words.busy(reason)
            case .notADreamAnswer: return Words.notADreamAnswer
            }
        }
    }

    private static func failure(_ reply: DuckReply) -> ReadError? {
        guard let failure = reply.failure else { return nil }
        if failure.message.contains("pool_warming") || failure.message.contains("DA-2000") {
            return .warming(nil)
        }
        return .refused(failure.message)
    }

    public static func readKey(_ reply: DuckReply) throws -> KeyAnswer {
        if let failure = failure(reply) { throw failure }
        guard let raw: [[String: Any]] = reply.field("models") else { throw ReadError.notADreamAnswer }
        let models = raw.compactMap { m -> Model? in
            guard let id = m["id"] as? String else { return nil }
            return Model(id: id, owner: m["owner"] as? String ?? "", servable: m["servable"] as? Bool ?? false,
                         fits: m["fits"] as? Bool ?? false)
        }
        return KeyAnswer(key: reply.field("key"), models: models)
    }

    public static func readCleared(_ reply: DuckReply) throws -> Bool {
        if let failure = failure(reply) { throw failure }
        guard let cleared: Bool = reply.field("cleared") else { throw ReadError.notADreamAnswer }
        return cleared
    }

    /// The rows of a `dream.act` answer, as twists. A row that is not three
    /// finite numbers is not a twist, and the whole chunk is refused rather
    /// than played in part.
    public static func readChunk(_ reply: DuckReply) throws -> Chunk {
        if let failure = failure(reply) { throw failure }
        guard let actions: [String: Any] = reply.field("actions") else { throw ReadError.notADreamAnswer }
        return try chunk(fromActions: actions, sessionID: reply.field("session_id"))
    }

    /// The `actions` of a reply, from the bridge or from Dream Labs itself, as twists.
    public static func chunk(fromActions actions: [String: Any], sessionID: String?) throws -> Chunk {
        guard let perKey = actions["per_key"] as? [String: Any],
              let rows = perKey["action.\(part)"] as? [Any] else {
            throw ReadError.notADreamAnswer
        }
        var twists: [DuckDrive.Twist] = []
        for row in rows {
            guard let values = row as? [Any], values.count == 3 else { throw ReadError.notADreamAnswer }
            let numbers = values.compactMap { ($0 as? NSNumber)?.doubleValue }
            guard numbers.count == 3, numbers.allSatisfy(\.isFinite) else { throw ReadError.notADreamAnswer }
            twists.append(DuckDrive.Twist(vx: numbers[0], vy: numbers[1], vyaw: numbers[2]))
        }
        if twists.isEmpty { throw ReadError.notADreamAnswer }
        return Chunk(rows: twists, sessionID: sessionID)
    }

    // MARK: - words

    public enum Words {
        public static let heading = "Dream-1"
        public static let saveKeyInSettings =
            "To run Dream-1, save your Dream Labs key in Settings, Dream-1. Recording runs needs no key."
        public static let cannotRecord = "This device could not start a video for the run."
        public static let simChip = "Dream-1"
        public static let simSheetTitle = "Dream-1 on this duck"
        public static let simCameraLabel = "What the simulated duck's head camera sees"
        public static let simCameraNote =
            "A drawing of what this duck's head camera would see on a practice mat, from Pollen's own camera "
          + "position. It lets you record runs and try Dream-1 with no robot. A model trained only on these "
          + "pictures learns this mat, not your floor."
        public static let simCameraNeedsNewerSystem =
            "The simulated head camera needs iOS 18 or macOS 15. On a real duck, its own camera works here."
        public static let keyRefused = "Dream Labs refused that key. Check it on platform.dreamlabs.ai and paste it again."
        public static let keyOverCap =
            "Dream Labs stopped this key at the account's monthly spending limit. Raise the limit on "
          + "platform.dreamlabs.ai; requests work again about a minute later."
        public static let keyDisabled = "Dream Labs has turned this key off. Make a new one on platform.dreamlabs.ai."
        public static let keyNotEntitled = "This key's Dream Labs account may not run that model."
        public static let clientOutdated =
            "Dream Labs says this model needs a newer Dream client than this app speaks (client_outdated). "
          + "Update Microduck Studio, or tell us at microduckstudio.com if you already have."
        /// DA-1000 in the words that say what to do about it.
        public static func keyProblem(_ reason: String) -> String {
            switch reason {
            case "over_cap": return keyOverCap
            case "disabled": return keyDisabled
            case "not_entitled": return keyNotEntitled
            default: return keyRefused
            }
        }
        public static func busy(_ reason: String) -> String {
            switch reason {
            case "rate_limited": return "Dream Labs asked this app to ask less often. Trying again."
            case "pool_full", "max_serves", "queue_timeout":
                return "Dream Labs has no free seat for this model right now (\(reason)). Trying again."
            default: return "Dream Labs is busy" + (reason.isEmpty ? "" : " (\(reason))") + ". Trying again."
            }
        }
        /// While a model starts: the duck stands still, and the wait does not count against the run.
        public static func startingFor(_ waited: TimeInterval) -> String {
            let minutes = Int(waited / 60)
            return "The model is starting on Dream Labs' side. The first run of a model can wait up to an hour; "
                + "the duck stands still meanwhile, and Stop ends the wait. "
                + (minutes < 1 ? "Waiting." : "Waited \(minutes) min.")
        }
        public static let gaveUpWaiting =
            "Dream Labs' model did not start within an hour. Try again later; the duck was told to stop."
        public static let sessionRestarted =
            "Dream Labs restarted the run on its side. Start it again from where the duck is now."
        public static let whatItIsHere =
            "Dream Labs' Dream-1 drives a robot from its camera and a task in words. Use your own key from "
          + "platform.dreamlabs.ai. It is kept in this device's Keychain and sent only to Dream Labs, and "
          + "Dream Labs bills that key. Dream-1 then runs from the camera card when a duck is connected."
        public static let keepOnRobot =
            "This bridge can keep a Dream Labs key on the robot's computer instead. Use that if you would "
          + "rather this device did not hold it; a key saved on this device is used first."
        public static let removeHere = "Remove the key from this device"
        public static let checkKey = "Check the key with Dream Labs"
        public static func savedHere(_ hint: String) -> String { "This device holds key \(hint)." }
        public static let whatItIs =
            "Dream Labs' Dream-1 drives a robot from its camera and a task in words. Use your own key from "
          + "platform.dreamlabs.ai. It is saved on the robot's computer, never in this app, and Dream Labs "
          + "bills that key."
        public static let keyPlaceholder = "Your Dream Labs key (dl_live_...)"
        public static let saveKey = "Check and save the key"
        public static let clearKey = "Remove the key from the robot"
        public static let emptyKey = "Paste your Dream Labs key first."
        public static let badKey =
            "That key holds a space, a line break or a character such as a curly quote. Copy it again, whole."
        public static func saved(_ hint: String) -> String { "The robot's computer holds key \(hint)." }
        public static let noKey = "No Dream Labs key is saved on the robot's computer."
        public static let noDuckModel =
            "None of your models was trained on a duck. Dream-1's public model drives two-arm YAM robots, "
          + "so a duck needs a model fine-tuned on duck recordings: a head camera, and the walk command "
          + "vx, vy, vyaw as state and action. Make one on platform.dreamlabs.ai, then check the key again."
        public static let model = "Model"
        public static let promptPlaceholder = "What should the duck do? For example, walk to the red mat"
        public static let run = "Run Dream-1 on the duck"
        public static let stop = "Stop"
        public static let needsCamera = "Dream-1 drives from the duck's camera. Show the camera first."
        public static let bridgeHasNoDream =
            "This bridge does not answer Dream requests. Update OpenCastor on the robot's computer."
        public static let warming = "The model is starting on Dream Labs' side. Trying again."
        public static let warmingFor = "The model is starting on Dream Labs' side. Trying again in %.0f s."
        public static let notADreamAnswer = "The bridge answered, but not with what a Dream request answers with."
        public static func running(_ rows: Int, _ seconds: Double) -> String {
            String(format: "Driving: %d steps played, %.0f s.", rows, seconds)
        }
        public static let stopped = "Stopped. The duck was told to stop."
        public static let timeUp = "Stopped at the time limit."
        public static func onPhone(_ label: String) -> String { "On this phone: \(label)" }
        public static func oneJob(_ task: String) -> String {
            "This driver knows one job: \(task). It does not read what you type."
        }
        public static func drivingAs(_ task: String) -> String { "Driving as: \(task)" }
        public static func tooSlow(_ ms: Int) -> String {
            "The driver took \(ms) ms to answer, too long to steer by. The duck was told to stop."
        }
        public static let tooHot = "This phone is too hot to drive the duck. Let it cool, then try again."
        public static let simOnly =
            "Phone drivers run on the simulated duck for now: they learned from its pictures, not a real floor."
        public static let noPicture = "No picture from the head camera yet."
        public static let notThisDriver = "That is not the driver this run was started with."
        public static let driverFailed = "The driver could not read this picture or gave numbers that are not commands."
        public static func timing(p50: Int, p95: Int) -> String { "Driver answered in \(p50) ms (most within \(p95) ms)." }
        public static let howItDrives =
            "The duck walks only the way the sticks can: every step is clamped to the sticks' speeds, "
          + "sent as an ordinary move, and the bridge's deadman still stops the duck if this phone stops sending them."
    }
}

/// Plays Dream-1's rows on a duck: ask, play part of the chunk, ask again.
///
/// THE ROWS ARE CLAMPED TO THE STICKS' ENVELOPE (`DuckDrive.maxForward` and
/// friends). A model is a new driver, and a new driver gets the same limits
/// the person's thumbs get, whatever the model was trained on.
///
/// IT STOPS ON ANYTHING IT DOES NOT UNDERSTAND. An error, a cancel, a chunk
/// that is not three numbers a row, or the time limit: each ends in
/// `robot.stop` and `dream.end`, in that order, so the duck stops before the
/// seat is given back.
public struct DreamPilot: Sendable {
    /// Rows a second: the rate the duck's recordings are made at, castor's convention.
    public static let rowsPerSecond = 10.0
    /// Rows played from each chunk of 48 before asking again.
    public static let horizon = 20
    /// The longest one run drives. Time spent waiting for Dream Labs, standing still, is not counted.
    public static let defaultLimit: TimeInterval = 60
    /// The longest a run waits, standing still, for a model to start or a seat to free. Dream Labs
    /// says a model that is not running can take up to an hour to start.
    public static let waitLimit: TimeInterval = 3600
    /// How long to wait when Dream Labs says busy without saying for how long.
    public static let busyWait: TimeInterval = 2
    /// The least time between asks while waiting, whatever `retry_after_s` says (0 or less included).
    public static let shortestWait: TimeInterval = 0.5
    /// Rows of each chunk after the first that ease from the last command into the new plan. Dream
    /// Labs: "The client doesn't smooth the change from one chunk to the next. Blend from your last
    /// command into each new chunk over a few rows."
    public static let blendRows = 3

    /// A chunk's rows eased in from `last`: row i (of `blendRows`) is (i+1)/(blendRows+1) of the
    /// way from `last` to the model's row, and every row after is the model's own.
    public static func blended(_ rows: [DuckDrive.Twist], from last: DuckDrive.Twist) -> [DuckDrive.Twist] {
        rows.enumerated().map { i, row in
            guard i < blendRows else { return row }
            let w = Double(i + 1) / Double(blendRows + 1)
            return DuckDrive.Twist(vx: last.vx + (row.vx - last.vx) * w,
                                   vy: last.vy + (row.vy - last.vy) * w,
                                   vyaw: last.vyaw + (row.vyaw - last.vyaw) * w)
        }
    }
    /// Frames each camera sends, oldest first.
    public static let window = 9

    /// STOP FIRST, AND WITHOUT WAITING ON ANYTHING ELSE. What a Stop button calls before it
    /// cancels a run: `robot.stop` goes on the wire now, alongside any request still waiting
    /// for a model, instead of after the run notices it was cancelled. (A line peer carries
    /// calls concurrently, so a parked `dream.act` does not hold this one back.)
    public static func stopNow(_ peer: any DuckPeer) async {
        _ = try? await peer.call(.stop)
    }

    public static func clamped(_ t: DuckDrive.Twist) -> DuckDrive.Twist {
        DuckDrive.Twist(vx: min(max(t.vx, -DuckDrive.maxBackward), DuckDrive.maxForward),
              vy: min(max(t.vy, -DuckDrive.maxSideways), DuckDrive.maxSideways),
              vyaw: min(max(t.vyaw, -DuckDrive.maxTurn), DuckDrive.maxTurn))
    }

    public enum Event: Equatable, Sendable {
        case asked
        case played(rows: Int, seconds: Double)
        case waiting(String)
        case ended(String)
    }

    public let checkpoint: String
    public let prompt: String
    public let limit: TimeInterval

    public init(checkpoint: String, prompt: String, limit: TimeInterval = DreamPilot.defaultLimit) {
        self.checkpoint = checkpoint
        self.prompt = prompt
        self.limit = limit
    }

    /// Runs until done, cancelled or refused. `frames` returns the head camera's
    /// newest frames as base64 JPEGs, oldest first; `sleep` is injectable for tests.
    public func run(on peer: any DuckPeer,
                    rows: (any DreamRows)? = nil,
                    frames: @Sendable () async -> [String],
                    events: @Sendable (Event) async -> Void,
                    sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1e9)) },
                    now: @Sendable () -> Date = Date.init) async {
        let source: any DreamRows = rows ?? BridgeDreamRows(peer)
        let start = now()
        // Standing still while Dream Labs starts the model is not driving: it is kept apart, so a
        // first run on a new fine-tune can wait out a cold start and still drive its full limit.
        var waited: TimeInterval = 0
        func driven() -> TimeInterval { now().timeIntervalSince(start) - waited }
        var last = DuckDrive.Twist(vx: 0, vy: 0, vyaw: 0)
        var played = 0
        var first = true
        var said = DuckDream.Words.stopped
        do {
            while driven() < limit {
                try Task.checkCancellation()
                let window = Array(await frames().suffix(DreamPilot.window))
                if window.isEmpty { said = DuckDream.Words.needsCamera; break }
                // NEVER WALK BLIND WHILE THE MODEL THINKS. Between chunks the duck is told
                // zero, so a slow or hung answer leaves it standing, not still walking on
                // the last row. `last` stays the command in force before this pause, which
                // is what the recordings call state.
                if !first { try await peer.notify(.move(.still)) }
                await events(.asked)
                let chunk: DuckDream.Chunk
                let asked = now()
                do {
                    chunk = try await source.act(
                        checkpoint: checkpoint, prompt: prompt,
                        frames: [DuckDream.cameraRole: window],
                        state: [DuckDream.part: [last.vx, last.vy, last.vyaw]], reset: first)
                } catch let pause as DuckDream.ReadError {
                    // A STARTING MODEL OR A BUSY GATEWAY IS NOT A FAILURE. Hold still and ask again.
                    let wait: TimeInterval, line: String
                    switch pause {
                    case .warming(let after):
                        wait = max(after ?? 10, DreamPilot.shortestWait)
                        line = DuckDream.Words.startingFor(waited)
                    case .busy(_, let after):
                        wait = max(after ?? DreamPilot.busyWait, DreamPilot.shortestWait)
                        line = pause.message
                    default:
                        throw pause
                    }
                    if waited + wait > DreamPilot.waitLimit { said = DuckDream.Words.gaveUpWaiting; break }
                    _ = try await peer.call(.stop)
                    // The duck is standing now: the next ask says so, and the next chunk eases from still.
                    last = DuckDrive.Twist(vx: 0, vy: 0, vyaw: 0)
                    await events(.waiting(line))
                    try await sleep(wait)
                    // The refused ask, the stop and the sleep: none of it was driving.
                    waited += now().timeIntervalSince(asked)
                    continue
                }
                let rows = first ? chunk.rows : DreamPilot.blended(chunk.rows, from: last)
                first = false
                for row in rows.prefix(DreamPilot.horizon) {
                    try Task.checkCancellation()
                    if driven() >= limit { break }
                    last = DreamPilot.clamped(row)
                    try await peer.notify(.move(last))
                    played += 1
                    try await sleep(1 / DreamPilot.rowsPerSecond)
                }
                await events(.played(rows: played, seconds: driven()))
            }
            if driven() >= limit { said = DuckDream.Words.timeUp }
        } catch is CancellationError {
            said = DuckDream.Words.stopped
        } catch let refusal as DuckDream.ReadError {
            said = refusal.message
        } catch let misuse as DuckCall.Misuse {
            said = misuse.message
        } catch {
            said = error.localizedDescription
        }
        _ = try? await peer.call(.stop)
        await source.end()
        await events(.ended(said))
    }
}
