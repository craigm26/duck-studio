// The app as an MCP client, over Streamable HTTP (brains-layer.md 5.3).
//
// THE ONLY FILE THAT IMPORTS THE SDK. `modelcontextprotocol/swift-sdk` 0.12.1, pinned exactly in
// Package.swift (Apache-2.0, with older contributions still MIT). Everything this file decides is
// decided in the kit (`MCPToolPolicy.swift`), where it is tested on Linux. This file only turns
// SDK types into kit types and back.
//
// WHAT IT CAN DO: connect, list tools, and read one tool with no arguments. WHAT IT CANNOT DO:
// call a tool with arguments, call a tool the kit has not classified read-only, answer a
// server's sampling, elicitation or roots requests (it declares none of those capabilities),
// or log anything (its logger is a no-op, and it never prints). It is not on the stop path:
// StopPath is in StudioKit, which does not import this module (`MCPBoundaryTests`).

#if canImport(MCP)
import Foundation
import Logging
import MCP
import StudioKit

public actor MCPHTTPToolSource: MCPToolSource {
    public nonisolated let address: MCPServerAddress
    private let bearer: MCPBearer?
    private let makeTransport: @Sendable () -> any Transport
    private var client: Client?
    /// The verdicts from the last listing. A tool not classified read-only here is never called.
    private var catalogue = MCPToolCatalogue([])

    /// How long one request may take.
    public static let timeout: TimeInterval = 10
    /// The most pages of tools read from one server.
    public static let maxPages = 10

    public enum Failure: Error, Equatable, Sendable {
        case tokenNeedsEncryption
        case unauthorized
        case unreachable
        case other(String)

        public var says: String {
            switch self {
            case .tokenNeedsEncryption: return MCPWords.tokenNeedsEncryption
            case .unauthorized: return MCPWords.failedUnauthorized
            case .unreachable: return MCPWords.failedUnreachable
            case .other(let detail): return MCPWords.failed(detail)
            }
        }
    }

    /// The real one: Streamable HTTP to `address`, with the token on every request when there is
    /// one. A token is sent over plain http only to a local address (6.6). `configuration` is
    /// for tests, which put a stub protocol in it.
    public init(address: MCPServerAddress, bearer: MCPBearer?,
                configuration: URLSessionConfiguration = .ephemeral, logger: Logger? = nil) throws {
        if bearer != nil, !address.isEncrypted, !address.isLocal { throw Failure.tokenNeedsEncryption }
        configuration.timeoutIntervalForRequest = Self.timeout
        // No cookies, no cache: nothing from a server outlives the request on disk.
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let header = bearer?.header
        let log = logger ?? Self.silent
        self.address = address
        self.bearer = bearer
        self.makeTransport = {
            HTTPClientTransport(endpoint: address.url, configuration: configuration, streaming: false,
                                requestModifier: { request in
                                    var r = request
                                    if let header { r.setValue(header, forHTTPHeaderField: "Authorization") }
                                    return r
                                },
                                logger: log)
        }
    }

    /// Any transport, for tests (`InMemoryTransport` with an in-process server).
    public init(address: MCPServerAddress, bearer: MCPBearer? = nil,
                transport: @escaping @Sendable () -> any Transport) {
        self.address = address
        self.bearer = bearer
        self.makeTransport = transport
    }

    static let silent = Logger(label: "studio.mcp", factory: { _ in SwiftLogNoOpLogHandler() })

    /// The client the app is: no sampling, no elicitation, no roots. A server cannot ask the app
    /// to run a model, to ask the person anything, or to show it files.
    static let capabilities = Client.Capabilities()

    private func connected() async throws -> Client {
        if let client { return client }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let c = Client(name: "Microduck Studio", version: version, capabilities: Self.capabilities)
        do {
            try await c.connect(transport: makeTransport())
        } catch {
            throw failure(error)
        }
        client = c
        return c
    }

    public func listTools() async throws -> [MCPToolInfo] {
        let c = try await connected()
        var out: [MCPToolInfo] = []
        var cursor: String?
        var pages = 0
        repeat {
            let page: (tools: [Tool], nextCursor: String?)
            do { page = try await c.listTools(cursor: cursor) } catch { throw failure(error) }
            out += page.tools.map(Self.info)
            cursor = page.nextCursor
            pages += 1
        } while cursor != nil && pages < Self.maxPages && out.count < MCPToolCatalogue.maxTools
        catalogue = MCPToolCatalogue(out)
        return out
    }

    public func readTool(_ name: String) async throws -> MCPToolReading {
        // A second lock behind `MCPReader`: this source calls only tools its own last listing
        // classified read-only and needing no arguments.
        guard let entry = catalogue.entries.first(where: { $0.tool.name == name }) else { throw MCPRefusal.notListed(name) }
        if case .excluded(let why) = entry.verdict { throw MCPRefusal.excluded(name, why) }
        guard entry.tool.requiredArguments.isEmpty else { throw MCPRefusal.needsArguments(name) }
        let c = try await connected()
        let result: (content: [Tool.Content], isError: Bool?)
        do { result = try await c.callTool(name: name, arguments: nil) } catch { throw failure(error) }
        let texts: [String] = result.content.compactMap {
            if case .text(let text, _, _) = $0 { return redact(text) }
            return nil
        }
        return MCPToolReading(tool: name, texts: texts, isError: result.isError ?? false)
    }

    public func disconnect() async {
        await client?.disconnect()
        client = nil
    }

    // MARK: - SDK to kit

    static func info(_ t: Tool) -> MCPToolInfo {
        let required = t.inputSchema.objectValue?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        return MCPToolInfo(name: t.name, title: t.title ?? t.annotations.title, description: t.description,
                           readOnlyHint: t.annotations.readOnlyHint, destructiveHint: t.annotations.destructiveHint,
                           idempotentHint: t.annotations.idempotentHint, openWorldHint: t.annotations.openWorldHint,
                           requiredArguments: required)
    }

    private func redact(_ s: String) -> String { bearer?.redact(s) ?? KeyScrub.scrub(s) }

    /// An SDK or network error in the kit's words, with the token and any key-shaped text gone.
    private func failure(_ error: Error) -> Failure {
        if let f = error as? Failure { return f }
        if let e = error as? MCPError {
            let text = redact(String(describing: e))
            let lower = text.lowercased()
            if ["401", "403", "unauthorized", "authentication required", "access forbidden"].contains(where: lower.contains) {
                return .unauthorized
            }
            return .other(String(text.prefix(200)))
        }
        if error is URLError { return .unreachable }
        return .other(String(redact(String(describing: error)).prefix(200)))
    }
}
#endif
