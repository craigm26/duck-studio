import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking   // URLSession lives here on Linux, where these tests run
#endif

/// Dream-1 straight from this app, with the key in this device's Keychain.
///
/// THE SAME WIRE OPENCASTOR SPEAKS (`castor/dream.py`), PORTED, NOT INVENTED.
/// `POST /v1/get_action` and `POST /v1/end_session` on the gateway,
/// `GET /v1/models` on the platform, a Bearer key on each. The shapes were read
/// off Dream Labs' live services on 2026-10-19 with a key that does not exist,
/// and the tests here hold this file to the same answers castor's tests do.
///
/// NOTHING ELSE LEAVES. Dream Labs' own Python client streams every camera tick
/// it is handed to their live service by default; this sends pictures only
/// inside the request that asks for an action, as castor does.
///
/// WHY THERE ARE TWO PATHS. `BridgeDreamRows` asks the robot's computer, which
/// holds the key (`dream.*`, OpenCastor 3.7). `DreamDirect` holds the key here and
/// needs nothing on the robot's computer but a link that drives the duck. Both
/// hand `DreamPilot` the same rows.
public protocol DreamRows: Sendable {
    func act(checkpoint: String, prompt: String, frames: [String: [String]],
             state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk
    func end() async
}

/// Rows from the robot's computer: the bridge's `dream.act`, as before.
public struct BridgeDreamRows: DreamRows {
    let peer: any DuckPeer
    public init(_ peer: any DuckPeer) { self.peer = peer }

    public func act(checkpoint: String, prompt: String, frames: [String: [String]],
                    state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
        try DuckDream.readChunk(try await peer.call(.dream(.act(
            checkpoint: checkpoint, prompt: prompt, frames: frames, state: state, reset: reset))))
    }

    public func end() async { _ = try? await peer.call(.dream(.end)) }
}

/// One HTTP exchange, injectable so the tests need no network.
public protocol DreamHTTP: Sendable {
    func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data)
}

public struct URLSessionDreamHTTP: DreamHTTP {
    public init() {}
    public func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (Int, Data) {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.httpBody = body
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}

public enum DreamWire {
    public static let gateway = URL(string: "https://api.dreamlabs.ai")!
    public static let platform = URL(string: "https://platform.dreamlabs.ai")!
    public static let ok = "DA-0000"
    public static let okNewSession = "DA-0001"
    public static let unauthorized = "DA-1000"
    public static let warming = "DA-2000"

    public static func headers(key: String, version: String) -> [String: String] {
        ["Authorization": "Bearer \(key)", "Accept": "application/json",
         "Content-Type": "application/json", "User-Agent": "microduck-studio/\(version)"]
    }

    public static func actBody(checkpoint: String, sessionID: String?, prompt: String,
                               frames: [String: [String]], state: [String: [Double]]) throws -> Data {
        var observation: [String: Any] = ["prompt": prompt]
        for (role, window) in frames { observation["video.\(role)"] = Array(window.suffix(DreamPilot.window)) }
        for (part, values) in state { observation["state.\(part)"] = values }
        let body: [String: Any] = ["checkpoint": checkpoint, "session_id": sessionID ?? NSNull(),
                                   "reset": false, "observation": observation]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// The actions and the session the gateway says this is now, or the refusal in its words.
    public static func readAct(_ data: Data, sent: String?) throws -> DuckDream.Chunk {
        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = top["status"] as? [String: Any], let code = status["code"] as? String else {
            throw DuckDream.ReadError.notADreamAnswer
        }
        let returned = (top["session_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? sent
        let reason = status["reason"] as? String ?? ""
        if code == ok || (code == okNewSession && (sent == nil || reason == "new")) {
            guard let actions = top["actions"] as? [String: Any] else { throw DuckDream.ReadError.notADreamAnswer }
            return try DuckDream.chunk(fromActions: actions, sessionID: returned)
        }
        if code == okNewSession {
            throw DuckDream.ReadError.refused(DuckDream.Words.sessionRestarted)
        }
        if code == warming, status["retryable"] as? Bool == true || reason == "pool_warming" {
            throw DuckDream.ReadError.warming((status["retry_after_s"] as? NSNumber)?.doubleValue)
        }
        if code == unauthorized { throw DuckDream.ReadError.refused(DuckDream.Words.keyRefused) }
        let name = status["name"] as? String ?? code
        throw DuckDream.ReadError.refused("Dream-1 refused the request: \(code) \(name)" + (reason.isEmpty ? "" : " (\(reason))"))
    }

    /// The platform's model list, each marked by whether a duck can run it.
    public static func readModels(_ status: Int, _ data: Data) throws -> [DuckDream.Model] {
        let top = try? JSONSerialization.jsonObject(with: data)
        if let refusal = (top as? [String: Any])?["error"] as? [String: Any] {
            if refusal["code"] as? String == "invalid_api_key" { throw DuckDream.ReadError.refused(DuckDream.Words.keyRefused) }
            throw DuckDream.ReadError.refused(refusal["message"] as? String ?? "Dream Labs refused (\(status)).")
        }
        guard let list = top as? [[String: Any]] else { throw DuckDream.ReadError.notADreamAnswer }
        return list.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            return DuckDream.Model(id: id, owner: m["owner"] as? String ?? "",
                                   servable: m["servable"] as? Bool ?? false,
                                   fits: fitsDuck(m["embodiment_config"]))
        }
    }

    /// The same test as `castor.dream.fits_embodiment` against `DuckDream.microduck`:
    /// part names and widths for state and action, and the camera roles.
    public static func fitsDuck(_ config: Any?) -> Bool {
        guard let config = config as? [String: Any] else { return false }
        func widths(_ spans: Any?) -> [String: Int] {
            var out: [String: Int] = [:]
            for (name, span) in spans as? [String: Any] ?? [:] {
                if let pair = span as? [NSNumber], pair.count == 2 { out[name] = pair[1].intValue - pair[0].intValue }
            }
            return out
        }
        let duck = DuckDream.microduck
        for side in ["state", "action"] where widths(config[side]) != widths(duck[side]) { return false }
        let roles = Set((config["video"] as? [String: Any] ?? [:]).keys)
        return roles == Set((duck["video"] as? [String: Any] ?? [:]).keys)
    }
}

/// Dream-1 from this app. One session at a time, as the gateway expects.
public actor DreamDirect: DreamRows {
    let key: String
    let http: any DreamHTTP
    let version: String
    private var sessionID: String?
    private var checkpoint: String?

    public init(key: String, version: String, http: any DreamHTTP = URLSessionDreamHTTP()) {
        self.key = key
        self.version = version
        self.http = http
    }

    /// The models this key may run; also the key's check.
    public func models() async throws -> DuckDream.KeyAnswer {
        let (status, data) = try await http.send(method: "GET", url: DreamWire.platform.appendingPathComponent("v1/models"),
                                                 headers: DreamWire.headers(key: key, version: version), body: nil)
        return DuckDream.KeyAnswer(key: DuckDream.hint(key), models: try DreamWire.readModels(status, data))
    }

    public func act(checkpoint: String, prompt: String, frames: [String: [String]],
                    state: [String: [Double]], reset: Bool) async throws -> DuckDream.Chunk {
        if reset || self.checkpoint != checkpoint { await end() }
        self.checkpoint = checkpoint
        let body = try DreamWire.actBody(checkpoint: checkpoint, sessionID: sessionID, prompt: prompt,
                                         frames: frames, state: state)
        let (_, data) = try await http.send(method: "POST", url: DreamWire.gateway.appendingPathComponent("v1/get_action"),
                                            headers: DreamWire.headers(key: key, version: version), body: body)
        let chunk = try DreamWire.readAct(data, sent: sessionID)
        sessionID = chunk.sessionID
        return chunk
    }

    /// Frees the gateway's seat now; best effort.
    public func end() async {
        guard let sid = sessionID, let checkpoint else { return }
        sessionID = nil
        let body = try? JSONSerialization.data(withJSONObject: ["checkpoint": checkpoint, "session_id": sid])
        _ = try? await http.send(method: "POST", url: DreamWire.gateway.appendingPathComponent("v1/end_session"),
                                 headers: DreamWire.headers(key: key, version: version), body: body)
    }
}
