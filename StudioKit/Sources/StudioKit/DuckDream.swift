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
        public var label: String { owner == "mine" ? id : "\(id) (\(owner))" }
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
    }

    public enum ReadError: Error, Equatable {
        case refused(String)
        case warming(Double?)
        case notADreamAnswer

        public var message: String {
            switch self {
            case .refused(let why): return why
            case .warming(let wait):
                return wait.map { String(format: Words.warmingFor, $0) } ?? Words.warming
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
        public static let keyRefused = "Dream Labs refused that key. Check it on platform.dreamlabs.ai and paste it again."
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
        public static let howItDrives =
            "The duck walks only the way the sticks can: every step is clamped to the sticks' speeds, "
          + "sent as an ordinary move, and the bridge's deadman still stops the duck if this phone goes quiet."
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
    /// The longest one run lasts.
    public static let defaultLimit: TimeInterval = 60
    /// Frames each camera sends, oldest first.
    public static let window = 9

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
        var last = DuckDrive.Twist(vx: 0, vy: 0, vyaw: 0)
        var played = 0
        var first = true
        var warmings = 0
        var said = DuckDream.Words.stopped
        do {
            while now().timeIntervalSince(start) < limit {
                try Task.checkCancellation()
                let window = Array(await frames().suffix(DreamPilot.window))
                if window.isEmpty { said = DuckDream.Words.needsCamera; break }
                await events(.asked)
                let chunk: DuckDream.Chunk
                do {
                    chunk = try await source.act(
                        checkpoint: checkpoint, prompt: prompt,
                        frames: [DuckDream.cameraRole: window],
                        state: [DuckDream.part: [last.vx, last.vy, last.vyaw]], reset: first)
                } catch DuckDream.ReadError.warming(let wait) where warmings < 6 {
                    // A STARTING MODEL IS NOT A FAILURE. Hold still while it starts.
                    warmings += 1
                    _ = try await peer.call(.stop)
                    await events(.waiting(DuckDream.ReadError.warming(wait).message))
                    try await sleep(wait ?? 10)
                    continue
                }
                first = false
                warmings = 0
                for row in chunk.rows.prefix(DreamPilot.horizon) {
                    try Task.checkCancellation()
                    if now().timeIntervalSince(start) >= limit { break }
                    last = DreamPilot.clamped(row)
                    try await peer.notify(.move(last))
                    played += 1
                    try await sleep(1 / DreamPilot.rowsPerSecond)
                }
                await events(.played(rows: played, seconds: now().timeIntervalSince(start)))
            }
            if now().timeIntervalSince(start) >= limit { said = DuckDream.Words.timeUp }
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
