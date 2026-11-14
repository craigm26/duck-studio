import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession and URLError live here on Linux, where these tests run
#endif

// MARK: - which model answered

/// The exact local model a planner ran: its name, the checkpoint that pins its weights, and the
/// quantisation (brains-layer.md 7: "EvidenceRow is pinned to provider id, model version or
/// checkpoint, and date").
///
/// A NAME ALONE IS NOT A VERSION. `qwen3.5:4b` on Ollama is a tag, and a tag moves when somebody
/// pulls again. `mlx-community/Qwen3-1.7B-4bit` is a repository, and a repository gets new
/// commits. The checkpoint (Ollama's digest, a Hugging Face commit) is what a number was measured
/// on, so a version without one is "unpinned" and the offer rule keeps its card hidden.
public struct LocalModelVersion: Equatable, Hashable, Sendable {
    public let model: String
    /// Ollama's digest (first 12 hex) or a Hugging Face commit (first 12 hex). Nil when unknown.
    public let checkpoint: String?
    /// "Q4_K_M", "4bit". Recorded for reading; the checkpoint already pins it.
    public let quantisation: String?

    public init(model: String, checkpoint: String? = nil, quantisation: String? = nil) {
        self.model = model
        let c = checkpoint?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.checkpoint = (c?.isEmpty ?? true) ? nil : c
        let q = quantisation?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.quantisation = (q?.isEmpty ?? true) ? nil : q
    }

    /// "qwen3.5:4b@1a2b3c4d5e6f Q4_K_M". This is `PlannerInfo.modelVersion`.
    public var string: String {
        model + (checkpoint.map { "@" + $0 } ?? "") + (quantisation.map { " " + $0 } ?? "")
    }

    public var isPinned: Bool { checkpoint != nil }

    /// The fewest checkpoint characters that count as a pin.
    public static let minimumCheckpoint = 7

    /// Whether a `modelVersion` string carries a checkpoint after an "@".
    public static func isPinned(_ version: String) -> Bool {
        guard let at = version.lastIndex(of: "@") else { return false }
        let tail = version[version.index(after: at)...].prefix { !$0.isWhitespace }
        return tail.count >= minimumCheckpoint && tail.allSatisfy { $0.isLetter || $0.isNumber || $0 == ":" }
    }

    /// The model as Ollama's `/api/tags` lists it, with its digest and quantisation.
    /// Throws `LocalPlannerError.modelNotFound` when the server does not have it.
    public static func ollama(tags: Data, model: String) throws -> LocalModelVersion {
        guard let top = (try? JSONSerialization.jsonObject(with: tags)) as? [String: Any],
              let models = top["models"] as? [[String: Any]] else { throw LocalPlannerError.unreadable }
        let wanted = sameTag(model)
        guard let hit = models.first(where: {
            sameTag(($0["name"] as? String) ?? "") == wanted || sameTag(($0["model"] as? String) ?? "") == wanted
        }) else { throw LocalPlannerError.modelNotFound(model: KeyScrub.scrub(model)) }
        var digest = (hit["digest"] as? String) ?? ""
        if digest.hasPrefix("sha256:") { digest.removeFirst("sha256:".count) }
        let details = hit["details"] as? [String: Any]
        return LocalModelVersion(model: model, checkpoint: digest.isEmpty ? nil : String(digest.prefix(12)),
                                 quantisation: details?["quantization_level"] as? String)
    }

    /// A downloaded Hugging Face repository, pinned by the snapshot folder the hub client wrote.
    /// The folder is named by the commit. More than one snapshot, or none, leaves it unpinned:
    /// which one loaded cannot be told from the outside.
    public static func huggingFace(repository: String, snapshots: [String]) -> LocalModelVersion {
        let commits = snapshots.filter { $0.count == 40 && $0.allSatisfy(\.isHexDigit) }
        let quant = repository.split(separator: "-").last.map(String.init).flatMap { tail -> String? in
            let t = tail.lowercased()
            return t.hasSuffix("bit") && t.dropLast(3).allSatisfy(\.isNumber) && t.count > 3 ? t : nil
        }
        return LocalModelVersion(model: repository, checkpoint: commits.count == 1 ? String(commits[0].prefix(12)) : nil,
                                 quantisation: quant)
    }

    /// Ollama treats "name" and "name:latest" as the same model.
    static func sameTag(_ name: String) -> String {
        name.contains(":") ? name : name + ":latest"
    }
}

// MARK: - what went wrong

/// Why a local planner gave no decision. The duck holds still in every case.
///
/// NO KEY IN ANY OF THESE. A bearer token for a local server can be any string, so the vendor
/// patterns in `KeyScrub` are not enough: every piece of server text is also scrubbed of the
/// exact token this planner holds (`LocalBearer.scrub`) before it is stored here.
public enum LocalPlannerError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Nothing answered at that address: connection refused, no such host, or the network is off.
    case notReachable(host: String)
    case timedOut(seconds: Int)
    case modelNotFound(model: String)
    case tokenRefused(host: String)
    case serverRefused(status: Int, detail: String)
    case serverError(status: Int)
    /// The server's reply was not the JSON its kind of server sends.
    case unreadable
    /// The model wrote only its scratchpad and never answered.
    case spentItAllThinking
    /// The model answered with nothing.
    case emptyReply
    /// The model in this app failed. The text is the runtime's, scrubbed.
    case runnerFailed(String)

    public var says: String {
        switch self {
        case .notReachable(let host):
            return "Nothing answered at \(host). Check the server is running and on the same network. The duck held still."
        case .timedOut(let s):
            return "The local model took longer than \(s) s. The duck held still."
        case .modelNotFound(let m):
            return "The server does not have the model \"\(m)\". Pull or load it there, then try again."
        case .tokenRefused(let host):
            return "\(host) did not accept the access token. Check it in Settings, Models."
        case .serverRefused(let status, let detail):
            return "The server refused the request (\(status))." + (detail.isEmpty ? "" : " \(detail)")
        case .serverError(let status):
            return "The server had a problem (\(status)). The duck held still."
        case .unreadable:
            return "The server's answer could not be read. The duck held still."
        case .spentItAllThinking:
            return "The model thought until it ran out of room and never answered. The duck held still. "
                + "Turn reasoning off for it, or pick a model that does not think."
        case .emptyReply:
            return "The model answered with nothing. The duck held still."
        case .runnerFailed(let text):
            return text.isEmpty ? "The model on this device stopped. The duck held still." : text
        }
    }

    public var description: String { says }

    /// Every sentence shape, for the copy tests.
    public static var allSamples: [LocalPlannerError] {
        [.notReachable(host: "mac.local"), .timedOut(seconds: 15), .modelNotFound(model: "qwen3.5:4b"),
         .tokenRefused(host: "mac.local"), .serverRefused(status: 400, detail: "bad"), .serverError(status: 500),
         .unreadable, .spentItAllThinking, .emptyReply, .runnerFailed("")]
    }
}

// MARK: - the token

/// An optional bearer token for a local server. It prints as `DuckDream.hint`'s "…abcd", never
/// as itself, in logs, test failures, `dump` and the debugger.
public struct LocalBearer: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let value: String
    public init?(_ value: String?) {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        self.value = v
    }
    public var hint: String { DuckDream.hint(value) }
    public var description: String { "token \(hint)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["hint": hint]) }

    /// `text` with this exact token, and anything shaped like a vendor key, masked.
    public func scrub(_ text: String) -> String {
        KeyScrub.scrub(text.replacingOccurrences(of: value, with: hint))
    }

    static func scrub(_ text: String, _ bearer: LocalBearer?) -> String {
        bearer?.scrub(text) ?? KeyScrub.scrub(text)
    }
}

// MARK: - the transport

/// One HTTP exchange, injectable so the tests need no network and make no calls.
public protocol LocalPlannerHTTP: Sendable {
    func send(_ method: String, url: URL, headers: [String: String], body: Data?,
              timeout: TimeInterval) async throws -> (status: Int, body: Data)
}

public struct URLSessionLocalPlannerHTTP: LocalPlannerHTTP {
    public init() {}
    public func send(_ method: String, url: URL, headers: [String: String], body: Data?,
                     timeout: TimeInterval) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

// MARK: - how the closed set is enforced on the server

/// How a local server is asked to keep to the closed set, strongest first (3.2).
public enum LocalOutputMode: String, CaseIterable, Sendable, Codable {
    /// Ollama's own `/api/chat` with `format` set to the schema. Decoding is constrained.
    case ollamaFormat
    /// OpenAI-compatible `response_format` `json_schema` (LM Studio, llama.cpp server).
    case jsonSchema
    /// OpenAI-compatible tools, one per allowed kind.
    case toolCalls
    /// The short list in the prompt only, then strict reading (a plain `mlx_lm.server`).
    case promptOnly

    /// The next mode down when a server refuses this one's request shape.
    public var fallback: LocalOutputMode? {
        switch self {
        case .ollamaFormat: return .jsonSchema
        case .jsonSchema: return .toolCalls
        case .toolCalls: return .promptOnly
        case .promptOnly: return nil
        }
    }

    /// The mode to try first. Ollama's port, 11434, starts at its own route; everything else
    /// starts at `json_schema`, and steps down if the server refuses it.
    public static func preferred(for endpoint: ModelEndpoint) -> LocalOutputMode {
        guard let url = URL(string: endpoint.baseURL.trimmingCharacters(in: .whitespaces)) else { return .jsonSchema }
        return url.port == 11434 ? .ollamaFormat : .jsonSchema
    }
}

// MARK: - the planner for a server

/// A planner backed by an OpenAI-compatible local server: Ollama, LM Studio, llama.cpp's server,
/// or `mlx_lm.server` on a Mac (brains-layer.md 4 and section 9 item 2).
///
/// IT ASKS FOR ONE `DuckDecision` FROM THIS RUN'S CLOSED SET, AND NOTHING ELSE. The strongest
/// enforcement the server takes is used (`LocalOutputMode`), and whatever comes back is read by
/// `LocalDecisionPrompt.read` and `AllowedDecisions` anyway, because a server that says it
/// constrains decoding is not the protection. Outside the set becomes `.ask`.
///
/// THE MODEL VERSION IS WHAT THE SERVER SAYS ANSWERED. `info.modelVersion` is the pinned version
/// the app looked up (`LocalModelVersion`). If the reply names a different model, the `Decided`
/// carries that name instead, unpinned, so the offer rule reads it as an untested version.
public struct LANPlanner: Planner, CustomStringConvertible, CustomReflectable {
    public let info: PlannerInfo
    /// The endpoint with its key removed. The token lives in `bearer` only.
    public let endpoint: ModelEndpoint
    public let version: LocalModelVersion
    public let mode: LocalOutputMode
    let bearer: LocalBearer?
    let http: any LocalPlannerHTTP

    /// The longest a LAN decision may take (section 4: "under 15 s, labelled slow").
    public static let decisionDeadline: Duration = .seconds(15)

    public init(endpoint: ModelEndpoint, version: LocalModelVersion, mode: LocalOutputMode? = nil,
                evidence: EvidenceRow? = nil, terms: TermsRow? = nil,
                deadline: Duration = LANPlanner.decisionDeadline,
                http: any LocalPlannerHTTP = URLSessionLocalPlannerHTTP()) throws {
        guard endpoint.kind == .openAICompatible else {
            throw ModelEndpoint.Refusal.notAnAddress(endpoint.kind.rawValue)
        }
        try endpoint.validate()
        let transport = try ModelTransport.classify(endpoint)
        var stripped = endpoint
        stripped.apiKey = nil
        self.endpoint = stripped
        self.bearer = LocalBearer(endpoint.apiKey)
        self.version = version
        self.mode = mode ?? .preferred(for: endpoint)
        self.http = http
        self.info = PlannerInfo(
            id: LocalPlannerWords.providerId(transport: transport, model: endpoint.model),
            modelVersion: KeyScrub.scrub(version.string),
            label: LocalPlannerWords.label(transport),
            runsOn: LocalPlannerWords.runsOn(transport),
            key: LocalPlannerWords.keyNeed(transport, bearerSet: bearer != nil),
            trainedOn: [], decisionDeadline: deadline, framesSent: .none,
            evidence: evidence, terms: terms, realDuck: .off)
    }

    public var description: String { "LANPlanner(\(info.id), \(mode.rawValue), \(bearer?.description ?? "no token"))" }
    public var customMirror: Mirror {
        Mirror(self, children: ["info": info, "mode": mode, "token": bearer?.hint ?? "none"])
    }

    var host: String { URL(string: endpoint.baseURL.trimmingCharacters(in: .whitespaces))?.host ?? endpoint.baseURL }

    // MARK: the request

    /// The URL, headers and body for one ask in one mode. Internal so the tests can read them.
    func request(_ ask: PlannerAsk, mode: LocalOutputMode) throws -> (url: URL, headers: [String: String], body: Data) {
        var headers = ["Content-Type": "application/json"]
        if let bearer { headers["Authorization"] = "Bearer " + bearer.value }
        let system = LocalDecisionPrompt.instructions(for: ask.allowed, toolCalls: mode == .toolCalls)
        let messages: [[String: Any]] = [
            ["role": "system", "content": system],
            ["role": "user", "content": LocalDecisionPrompt.userText(ask)],
        ]
        var body: [String: Any] = ["model": endpoint.model, "messages": messages, "stream": false]
        let url: URL
        switch mode {
        case .ollamaFormat:
            url = try ollamaURL("api/chat")
            body["format"] = LocalDecisionPrompt.schema(for: ask.allowed)
            body["options"] = ["temperature": 0, "num_predict": LocalDecisionPrompt.maxOutputTokens] as [String: Any]
            // Ollama's own flag. Through this route it works; through `/v1` it did not (ChatWire).
            if endpoint.suppressReasoning { body["think"] = false }
        case .jsonSchema, .toolCalls, .promptOnly:
            url = try endpoint.chatURL()
            body["temperature"] = 0
            body["max_tokens"] = LocalDecisionPrompt.maxOutputTokens
            if endpoint.suppressReasoning { body["reasoning_effort"] = "none" }
            if mode == .jsonSchema {
                body["response_format"] = [
                    "type": "json_schema",
                    "json_schema": ["name": "duck_decision", "strict": true,
                                    "schema": LocalDecisionPrompt.schema(for: ask.allowed)] as [String: Any],
                ] as [String: Any]
            }
            if mode == .toolCalls {
                body["tools"] = LocalDecisionPrompt.tools(for: ask.allowed)
                body["tool_choice"] = "required"
            }
        }
        return (url, headers, try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
    }

    /// `http://mac.local:11434/v1` becomes `http://mac.local:11434/<path>`.
    func ollamaURL(_ path: String) throws -> URL {
        _ = try endpoint.chatURL()   // the same validation every request gets
        var base = endpoint.baseURL.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/v1") { base.removeLast(3) }
        guard let url = URL(string: base + "/" + path) else { throw ModelEndpoint.Refusal.notAURL(endpoint.baseURL) }
        return url
    }

    // MARK: asking

    /// One decision, with how it was reached.
    public struct Outcome: Sendable {
        public let decided: Decided
        /// The mode the server accepted, after any step down.
        public let mode: LocalOutputMode
        /// Why the decision became `.ask`, when it did.
        public let refusal: AllowedDecisions.Refusal?
        /// The model the server said answered, scrubbed. Nil when it did not say.
        public let servedModel: String?
    }

    public func decide(_ ask: PlannerAsk) async throws -> Decided {
        try await decideWithOutcome(ask).decided
    }

    public func decideWithOutcome(_ ask: PlannerAsk) async throws -> Outcome {
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = info.decisionDeadline
        return try await LocalDeadline.run(deadline) { [self] in
            var current: LocalOutputMode? = mode
            var lastRefusal: LocalPlannerError = .unreadable
            while let m = current {
                try Task.checkCancellation()
                let (url, headers, body) = try request(ask, mode: m)
                let reply: (status: Int, body: Data)
                do {
                    reply = try await http.send("POST", url: url, headers: headers, body: body,
                                                timeout: Double(deadline.components.seconds) + 1)
                } catch {
                    throw mapTransport(error, deadline: deadline)
                }
                switch try judge(status: reply.status, body: reply.body, mode: m) {
                case .stepDown(let refusal):
                    lastRefusal = refusal
                    current = m.fallback
                    continue
                case .ok:
                    let (reading, served) = try read(reply.body, mode: m, allowed: ask.allowed)
                    let latency = clock.now - start
                    let provider = Self.served(info, served: served, version: version)
                    return Outcome(decided: Decided(decision: reading.decision, why: bearerScrub(reading.why),
                                                    provider: provider, latency: latency),
                                   mode: m, refusal: reading.refusal, servedModel: served)
                }
            }
            throw lastRefusal
        }
    }

    enum Verdict { case ok, stepDown(LocalPlannerError) }

    /// What an HTTP status means for this mode.
    func judge(status: Int, body: Data, mode: LocalOutputMode) throws -> Verdict {
        let text = Self.errorText(body)
        switch status {
        case 200..<300:
            return .ok
        case 401, 403:
            throw LocalPlannerError.tokenRefused(host: host)
        case 404:
            if text.lowercased().contains("not found"), text.lowercased().contains("model") {
                throw LocalPlannerError.modelNotFound(model: bearerScrub(endpoint.model))
            }
            // Not Ollama after all: its own route is missing. Step down to `/v1`.
            if mode == .ollamaFormat { return .stepDown(.serverRefused(status: status, detail: detail(text))) }
            throw LocalPlannerError.serverRefused(status: status, detail: detail(text))
        case 400, 422, 501:
            // The server would not take this request shape (a schema, tools). Try the next one.
            let refusal = LocalPlannerError.serverRefused(status: status, detail: detail(text))
            if mode.fallback != nil { return .stepDown(refusal) }
            throw refusal
        case 500..<600:
            throw LocalPlannerError.serverError(status: status)
        default:
            throw LocalPlannerError.serverRefused(status: status, detail: detail(text))
        }
    }

    func detail(_ text: String) -> String { bearerScrub(String(text.prefix(160))) }
    func bearerScrub(_ text: String) -> String { LocalBearer.scrub(text, bearer) }

    /// The error message in a server's reply, whichever shape it uses.
    static func errorText(_ body: Data) -> String {
        guard let top = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            return String(decoding: body.prefix(400), as: UTF8.self)
        }
        if let s = top["error"] as? String { return s }
        if let e = top["error"] as? [String: Any], let m = e["message"] as? String { return m }
        if let m = top["message"] as? String { return m }
        if let d = top["detail"] as? String { return d }
        return ""
    }

    /// Read a 2xx body in this mode's shape.
    func read(_ body: Data, mode: LocalOutputMode,
              allowed: AllowedDecisions) throws -> (LocalDecisionPrompt.Reading, String?) {
        guard let top = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else {
            throw LocalPlannerError.unreadable
        }
        let served = (top["model"] as? String).map(bearerScrub)
        let message: [String: Any]
        var cutOff = false
        if mode == .ollamaFormat {
            guard let m = top["message"] as? [String: Any] else { throw LocalPlannerError.unreadable }
            message = m
            cutOff = (top["done_reason"] as? String) == "length"
        } else {
            guard let choices = top["choices"] as? [[String: Any]], let first = choices.first,
                  let m = first["message"] as? [String: Any] else { throw LocalPlannerError.unreadable }
            message = m
            cutOff = (first["finish_reason"] as? String) == "length"
        }
        if let calls = message["tool_calls"] as? [[String: Any]], !calls.isEmpty {
            let parsed: [(name: String, arguments: Data)] = calls.map { call in
                let fn = call["function"] as? [String: Any] ?? [:]
                let name = fn["name"] as? String ?? ""
                if let s = fn["arguments"] as? String { return (name, Data(s.utf8)) }
                if let o = fn["arguments"] as? [String: Any],
                   let d = try? JSONSerialization.data(withJSONObject: o) { return (name, d) }
                return (name, Data())
            }
            return (LocalDecisionPrompt.read(toolCalls: parsed, allowed: allowed), served)
        }
        let content = (message["content"] as? String) ?? ""
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // A REASONING MODEL'S SCRATCHPAD IS NOT AN ANSWER HERE. `ChatWire.content` takes JSON
            // out of the reasoning block for drafts, which a person reviews. A decision moves a
            // duck, and the scratchpad's JSON is often a rejected first try, so it is refused.
            let thinking = (message["thinking"] as? String) ?? (message["reasoning"] as? String)
                ?? (message["reasoning_content"] as? String) ?? ""
            if !thinking.isEmpty || cutOff { throw LocalPlannerError.spentItAllThinking }
            throw LocalPlannerError.emptyReply
        }
        return (try LocalDecisionPrompt.read(reply: content, allowed: allowed), served)
    }

    /// A transport failure as a sentence about this host.
    func mapTransport(_ error: Error, deadline: Duration) -> Error {
        if error is CancellationError { return error }
        if let e = error as? LocalPlannerError { return e }
        if let u = error as? URLError {
            switch u.code {
            case .timedOut: return LocalPlannerError.timedOut(seconds: Int(deadline.components.seconds))
            case .cancelled: return CancellationError()
            default: return LocalPlannerError.notReachable(host: host)
            }
        }
        return LocalPlannerError.notReachable(host: host)
    }

    /// The planner info for the `Decided`: unchanged when the server ran the model asked for, and
    /// carrying the served name (unpinned) when it says it ran another.
    static func served(_ info: PlannerInfo, served: String?, version: LocalModelVersion) -> PlannerInfo {
        guard let served, !served.isEmpty,
              LocalModelVersion.sameTag(served) != LocalModelVersion.sameTag(version.model) else { return info }
        return PlannerInfo(id: info.id, modelVersion: served, label: info.label, runsOn: info.runsOn, key: info.key,
                           trainedOn: info.trainedOn, decisionDeadline: info.decisionDeadline,
                           framesSent: info.framesSent, evidence: info.evidence, terms: info.terms,
                           realDuck: info.realDuck)
    }

    // MARK: which model is it

    /// Ask an Ollama server which build of the model it holds (`/api/tags`), for the pinned
    /// version. Other servers do not report a checkpoint, so their version stays unpinned.
    public static func identifyOllama(_ endpoint: ModelEndpoint,
                                      http: any LocalPlannerHTTP = URLSessionLocalPlannerHTTP()) async throws -> LocalModelVersion {
        let probe = try LANPlanner(endpoint: endpoint, version: LocalModelVersion(model: endpoint.model),
                                   mode: .ollamaFormat, http: http)
        let url = try probe.ollamaURL("api/tags")
        var headers: [String: String] = [:]
        if let b = probe.bearer { headers["Authorization"] = "Bearer " + b.value }
        let reply: (status: Int, body: Data)
        do {
            reply = try await http.send("GET", url: url, headers: headers, body: nil, timeout: 5)
        } catch {
            throw probe.mapTransport(error, deadline: .seconds(5))
        }
        guard (200..<300).contains(reply.status) else {
            if reply.status == 401 || reply.status == 403 { throw LocalPlannerError.tokenRefused(host: probe.host) }
            throw LocalPlannerError.serverRefused(status: reply.status, detail: probe.detail(errorText(reply.body)))
        }
        return try LocalModelVersion.ollama(tags: reply.body, model: endpoint.model)
    }
}

// MARK: - a deadline that cancels

enum LocalDeadline {
    /// Runs `body` and gives up at `deadline`, cancelling it.
    static func run<T: Sendable>(_ deadline: Duration, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(for: deadline)
                throw LocalPlannerError.timedOut(seconds: max(1, Int(deadline.components.seconds)))
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw LocalPlannerError.timedOut(seconds: Int(deadline.components.seconds))
            }
            return first
        }
    }
}

// MARK: - the words

/// Card words and ids for local planners. No number appears here: a card's number comes from its
/// EvidenceRow, and no local model has one yet.
public enum LocalPlannerWords {
    public static func providerId(transport: ModelTransport, model: String) -> String {
        let prefix: String
        switch transport {
        case .thisDevice, .otherAppOnThisDevice: prefix = "phone"
        case .ownNetworkEncrypted, .ownNetworkPlain, .tailnet: prefix = "lan"
        case .forwardsElsewhere: prefix = "relay"
        case .internetEncrypted: prefix = "remote"
        }
        return prefix + "." + KeyScrub.scrub(model)
    }

    public static func label(_ t: ModelTransport, device: DeviceWords = .current) -> String {
        switch t {
        case .thisDevice: return "Local model on \(device.this)"
        case .otherAppOnThisDevice: return "Local model in another app on \(device.this)"
        case .ownNetworkEncrypted, .ownNetworkPlain, .tailnet: return "On your own computer. Slower."
        case .forwardsElsewhere(let host, _): return "Forwarded by \(host)"
        case .internetEncrypted(let host): return "On \(host)"
        }
    }

    public static func runsOn(_ t: ModelTransport) -> RunsOn {
        switch t {
        case .thisDevice, .otherAppOnThisDevice: return .thisPhone
        case .ownNetworkEncrypted, .ownNetworkPlain, .tailnet: return .lanComputer
        case .forwardsElsewhere(let host, let to): return .hosted(vendor: to ?? host)
        case .internetEncrypted(let host): return .hosted(vendor: host)
        }
    }

    /// A token for your own server is not a vendor key, so a local planner needs none. A host
    /// that forwards or sits on the internet is somebody's service, and its token is a key.
    public static func keyNeed(_ t: ModelTransport, bearerSet: Bool) -> KeyNeed {
        switch t {
        case .thisDevice, .otherAppOnThisDevice, .ownNetworkEncrypted, .ownNetworkPlain, .tailnet: return .none
        case .forwardsElsewhere(let host, let to): return bearerSet ? .byok(provider: to ?? host) : .none
        case .internetEncrypted(let host): return bearerSet ? .byok(provider: host) : .none
        }
    }

    /// The terms line for a local model's card: there is no vendor, and the model's own licence
    /// applies.
    public static func terms(_ row: TermsRow) -> String? {
        guard let licence = row.localModelLicence else { return nil }
        return "No vendor keeps anything. The model's own licence applies: \(licence)."
    }

    public static var all: [String] {
        let ts: [ModelTransport] = [.thisDevice, .otherAppOnThisDevice, .ownNetworkPlain(host: "mac.local"),
                                    .forwardsElsewhere(host: "pi.local", to: nil), .internetEncrypted(host: "x.example.com")]
        return ts.flatMap { t in [DeviceWords.phone, .mac].map { label(t, device: $0) } }
            + [terms(.localModel("lan.x", checked: "2026-11-13", licence: "Apache-2.0", source: "x",
                                 physicalControl: .allowed, minimumAge: 0)) ?? ""]
            + LocalPlannerError.allSamples.map(\.says)
    }
}
