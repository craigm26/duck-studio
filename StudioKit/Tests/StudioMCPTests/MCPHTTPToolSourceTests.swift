// The MCP client against servers: an in-process one over the SDK's in-memory transport, a stub
// HTTP server inside URLSession, and, when DUCK_MCP_URL is set, a real one (brains-layer.md 5.3).
//
// Apple platforms only, like the client. Every rule the client follows is also tested on Linux in
// StudioKitTests (`MCPToolPolicyTests`, `MCPBoundaryTests`, `GateKeyExportTests`).

#if canImport(MCP)
import Foundation
import Logging
import MCP
import XCTest
@testable import StudioKit
@testable import StudioMCP

final class MCPHTTPToolSourceTests: XCTestCase {

    static let local = try! MCPServerAddress.parse("http://127.0.0.1:8811/mcp").get()
    static let token = "q7Lm2Xv9" + String(repeating: "Rt4w", count: 6)

    // MARK: - an in-process server

    /// What the fake server was asked, and what the client said it could do.
    actor Seen {
        var calls: [String] = []
        var capabilities: Client.Capabilities?
        func call(_ n: String) { calls.append(n) }
        func client(_ c: Client.Capabilities) { capabilities = c }
    }

    static let fakeTools: [Tool] = [
        Tool(name: "duck_state", description: "Standing, odometry and its age.",
             inputSchema: .object(["type": .string("object")]),
             annotations: .init(readOnlyHint: true, openWorldHint: false)),
        Tool(name: "duck_skills", description: "The duck's moves.", inputSchema: .object(["type": .string("object")]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "walk", description: "Walks.", inputSchema: .object(["type": .string("object")]),
             annotations: .init(readOnlyHint: false, destructiveHint: false)),
        Tool(name: "render", description: "No hints at all.", inputSchema: .object(["type": .string("object")])),
        Tool(name: "find_card", description: "Needs a code.",
             inputSchema: .object(["type": .string("object"), "required": .array([.string("code")])]),
             annotations: .init(readOnlyHint: true)),
        Tool(name: "echo_header", description: "Says back what it was sent.",
             inputSchema: .object(["type": .string("object")]), annotations: .init(readOnlyHint: true)),
    ]

    func source(seen: Seen) async throws -> MCPHTTPToolSource {
        let (clientSide, serverSide) = await InMemoryTransport.createConnectedPair()
        let server = Server(name: "fake-duck", version: "0", capabilities: .init(tools: .init()))
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: Self.fakeTools) }
        await server.withMethodHandler(CallTool.self) { params in
            await seen.call(params.name)
            switch params.name {
            case "duck_state": return .init(content: [.text("standing, odometry 40 ms old")])
            case "echo_header": return .init(content: [.text("you sent Bearer \(Self.token) and \(Self.token)")])
            default: return .init(content: [.text("moved")])
            }
        }
        try await server.start(transport: serverSide) { _, caps in await seen.client(caps) }
        let bearer = try MCPBearer.cleaned(Self.token).get()
        return MCPHTTPToolSource(address: Self.local, bearer: bearer, transport: { clientSide })
    }

    func testItListsAndClassifiesTools() async throws {
        let seen = Seen()
        let source = try await source(seen: seen)
        let catalogue = MCPToolCatalogue(try await source.listTools())
        XCTAssertEqual(catalogue.entries.map(\.verdict), [.readOnly, .excluded(.motion), .excluded(.notReadOnly),
                                                          .excluded(.noHints), .readOnly, .readOnly])
        XCTAssertEqual(catalogue.plannerTools.map(\.name), ["duck_state", "find_card", "echo_header"])
        XCTAssertEqual(catalogue.readable.map(\.name), ["duck_state", "echo_header"])
        XCTAssertEqual(catalogue.entries.first { $0.tool.name == "find_card" }?.tool.requiredArguments, ["code"])
        await source.disconnect()
    }

    /// The client says it can do nothing for the server: no sampling, no elicitation, no roots.
    /// A server cannot get the app to run a model or ask the person anything (Q3: the app is
    /// never the place a server gets consent for motion).
    func testTheClientOffersTheServerNothing() async throws {
        let seen = Seen()
        let source = try await source(seen: seen)
        _ = try await source.listTools()
        let caps = await seen.capabilities
        XCTAssertNotNil(caps)
        XCTAssertNil(caps?.sampling)
        XCTAssertNil(caps?.elicitation)
        XCTAssertNil(caps?.roots)
        await source.disconnect()
    }

    /// Rule: the source itself refuses an excluded tool, even when called directly and not
    /// through `MCPReader`. The server never hears the call.
    func testTheSourceNeverCallsAnExcludedTool() async throws {
        let seen = Seen()
        let source = try await source(seen: seen)
        do { _ = try await source.readTool("walk"); XCTFail("walk was called before any listing") } catch {}
        _ = try await source.listTools()
        for name in ["walk", "duck_skills", "render", "find_card", "duck_stop"] {
            do {
                _ = try await source.readTool(name)
                XCTFail("\(name) was called")
            } catch is MCPRefusal {}
        }
        let got1 = await seen.calls
        XCTAssertEqual(got1, [], "the server heard no call")

        let reading = try await source.readTool("duck_state")
        XCTAssertEqual(reading.texts, ["standing, odometry 40 ms old"])
        let got2 = await seen.calls
        XCTAssertEqual(got2, ["duck_state"])
        await source.disconnect()
    }

    func testAToolAnswerComesBackWithoutTheToken() async throws {
        let seen = Seen()
        let source = try await source(seen: seen)
        let catalogue = MCPToolCatalogue(try await source.listTools())
        let reader = MCPReader(source: source, catalogue: catalogue, host: Self.local.host)
        let notes = await reader.notes()
        XCTAssertEqual(notes.map(\.source), ["127.0.0.1 duck_state", "127.0.0.1 echo_header"])
        for note in notes {
            XCTAssertFalse(note.text.contains(Self.token), note.text)
            XCTAssertFalse(note.text.contains(String(Self.token.dropFirst(6))), note.text)
        }
        XCTAssertTrue(notes[1].text.contains(DuckDream.hint(Self.token)), "the echo is there, masked")
        await source.disconnect()
    }

    // MARK: - over HTTP, inside URLSession

    /// A token is never sent over plain http to an address off the home network.
    func testNoTokenOverPlainHTTPToTheInternet() throws {
        let remote = try MCPServerAddress.parse("http://8.8.8.8/mcp").get()
        let bearer = try MCPBearer.cleaned(Self.token).get()
        XCTAssertThrowsError(try MCPHTTPToolSource(address: remote, bearer: bearer)) {
            XCTAssertEqual($0 as? MCPHTTPToolSource.Failure, .tokenNeedsEncryption)
        }
        XCTAssertNoThrow(try MCPHTTPToolSource(address: remote, bearer: nil))
        XCTAssertNoThrow(try MCPHTTPToolSource(address: try MCPServerAddress.parse("https://duck.example/mcp").get(),
                                               bearer: bearer))
    }

    /// Over Streamable HTTP: the token goes in the Authorization header of every request and
    /// nowhere else; the SDK's log, at trace level, never holds it; an answer that echoes it
    /// comes back masked.
    func testTheTokenGoesOnlyInTheHeaderAndNeverInALog() async throws {
        StubMCPServer.reset(status: 200)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubMCPServer.self]
        let logs = LogCapture()
        var logger = Logger(label: "test.mcp", factory: { _ in CapturingLogHandler(capture: logs) })
        logger.logLevel = .trace
        let bearer = try MCPBearer.cleaned(Self.token).get()
        let source = try MCPHTTPToolSource(address: Self.local, bearer: bearer, configuration: config, logger: logger)

        let tools = try await source.listTools()
        XCTAssertEqual(tools.map(\.name), ["duck_state", "walk"])
        let reading = try await source.readTool("duck_state")
        do { _ = try await source.readTool("walk"); XCTFail("walk was called") } catch is MCPRefusal {}
        await source.disconnect()

        let requests = StubMCPServer.requests
        XCTAssertGreaterThanOrEqual(requests.count, 3, "initialize, initialized, tools/list, tools/call")
        XCTAssertFalse(requests.contains { $0.method == "tools/call" && $0.tool == "walk" }, "walk never went out")
        for r in requests {
            XCTAssertEqual(r.authorization, "Bearer " + Self.token, "every request carries the token in its header")
            XCTAssertFalse(r.url.contains(String(Self.token.dropFirst(6))), "never in the URL")
            XCTAssertFalse(r.body.contains(String(Self.token.dropFirst(6))), "never in a body")
        }
        let logged = logs.lines.joined(separator: "\n")
        XCTAssertFalse(logs.lines.isEmpty, "the capture saw the SDK's log lines, so the check below can fail")
        XCTAssertFalse(logged.contains(String(Self.token.dropFirst(6))), "the token is in the log:\n\(logged)")
        XCTAssertFalse(reading.texts.joined().contains(String(Self.token.dropFirst(6))), "the echo is masked")
        XCTAssertTrue(reading.texts.joined().contains(DuckDream.hint(Self.token)))
    }

    func testARefusedTokenSaysSoWithoutTheToken() async throws {
        StubMCPServer.reset(status: 401)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubMCPServer.self]
        let source = try MCPHTTPToolSource(address: Self.local, bearer: try MCPBearer.cleaned(Self.token).get(),
                                           configuration: config)
        do {
            _ = try await source.listTools()
            XCTFail("listed with a refused token")
        } catch let f as MCPHTTPToolSource.Failure {
            XCTAssertEqual(f, .unauthorized)
            XCTAssertFalse(f.says.contains(String(Self.token.dropFirst(6))))
        }
    }

    // MARK: - a real server, when one is running

    /// Set DUCK_MCP_URL (and DUCK_MCP_TOKEN if it needs one) to list a real server's tools. Run on
    /// the Mac against `robot-md mcp` with the Microduck preset, behind a stdio-to-HTTP proxy,
    /// because robot-md 2.0.0 speaks stdio only.
    func testARealServerListsTools() async throws {
        guard let url = ProcessInfo.processInfo.environment["DUCK_MCP_URL"] else {
            throw XCTSkip("DUCK_MCP_URL is not set")
        }
        let address = try MCPServerAddress.parse(url).get()
        let bearer = ProcessInfo.processInfo.environment["DUCK_MCP_TOKEN"].flatMap { try? MCPBearer.cleaned($0).get() }
        let source = try MCPHTTPToolSource(address: address, bearer: bearer)
        let tools = try await source.listTools()
        await source.disconnect()
        let catalogue = MCPToolCatalogue(tools)
        for e in catalogue.entries {
            let verdict: String
            switch e.verdict {
            case .readOnly: verdict = "READ-ONLY"
            case .excluded(let why): verdict = "out: \(why.rawValue)"
            }
            print("MCP-REAL \(e.tool.name) [\(verdict)]")
        }
        print("MCP-REAL " + MCPWords.counted(readOnly: catalogue.plannerTools.count, total: catalogue.entries.count))
        XCTAssertGreaterThan(tools.count, 0)
    }
}

// MARK: - a stub Streamable HTTP server inside URLSession

final class StubMCPServer: URLProtocol, @unchecked Sendable {
    struct Seen: Sendable {
        let method: String
        let tool: String?
        let authorization: String?
        let url: String
        let body: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _requests: [Seen] = []
    nonisolated(unsafe) private static var status = 200

    static var requests: [Seen] { lock.lock(); defer { lock.unlock() }; return _requests }
    static func reset(status s: Int) { lock.lock(); _requests = []; status = s; lock.unlock() }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = Self.body(of: request)
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let method = json["method"] as? String ?? ""
        let tool = (json["params"] as? [String: Any])?["name"] as? String
        Self.lock.lock()
        Self._requests.append(Seen(method: method, tool: tool,
                                   authorization: request.value(forHTTPHeaderField: "Authorization"),
                                   url: request.url?.absoluteString ?? "", body: String(decoding: body, as: UTF8.self)))
        let status = Self.status
        Self.lock.unlock()

        let url = request.url!
        if status != 200 || json["id"] == nil {
            let code = status != 200 ? status : 202
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: [:])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let result: Any
        switch method {
        case "initialize":
            result = ["protocolVersion": (json["params"] as? [String: Any])?["protocolVersion"] ?? "2025-11-25",
                      "capabilities": ["tools": [:]], "serverInfo": ["name": "stub", "version": "0"]]
        case "tools/list":
            result = ["tools": [
                ["name": "duck_state", "inputSchema": ["type": "object"], "annotations": ["readOnlyHint": true]],
                ["name": "walk", "inputSchema": ["type": "object"], "annotations": ["readOnlyHint": false]],
            ]]
        case "tools/call":
            let token = MCPHTTPToolSourceTests.token
            result = ["content": [["type": "text", "text": "standing; your header was Bearer \(token), bare \(token)"]]]
        default:
            result = [:]
        }
        let reply = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": json["id"]!, "result": result])
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json", "Mcp-Session-Id": "s1"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply)
        client?.urlProtocolDidFinishLoading(self)
    }

    static func body(of request: URLRequest) -> Data {
        if let b = request.httpBody { return b }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            out.append(buffer, count: n)
        }
        return out
    }
}

// MARK: - a log handler that keeps every line, metadata included

final class LogCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _lines: [String] = []
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return _lines }
    func add(_ s: String) { lock.lock(); _lines.append(s); lock.unlock() }
}

struct CapturingLogHandler: LogHandler {
    let capture: LogCapture
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?, source: String,
             file: String, function: String, line: UInt) {
        capture.add("\(level) \(message) \(self.metadata.merging(metadata ?? [:]) { $1 })")
    }
}
#endif
