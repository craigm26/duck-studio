import SwiftUI
import StudioKit
import StudioMCP

/// Where the robot tool server's address is kept. Not a secret: `UserDefaults`, like a model
/// endpoint's address. Its token is in the Keychain (`MCPTokenStore`).
enum MCPServerStore {
    private static let key = "mcp.server.address"

    static func load() -> MCPServerAddress? {
        UserDefaults.standard.string(forKey: key).flatMap { try? MCPServerAddress.parse($0).get() }
    }
    static func save(_ a: MCPServerAddress) { UserDefaults.standard.set(a.url.absoluteString, forKey: key) }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Studio > Settings > Models > Robot tool servers: one MCP server, and what it lists.
///
/// READS ONLY. The screen saves an address and an optional token, lists the server's tools, and
/// shows which a planner may read and why each other one is kept out. Nothing here moves the
/// duck or calls a tool. Every sentence is a kit string (`MCPWords`).
struct MCPServerView: View {
    @State private var typedAddress = ""
    @State private var typedToken = ""
    @State private var saved: MCPServerAddress?
    @State private var tokenHint: String?
    @State private var said: String?
    @State private var problem: String?
    @State private var catalogue: MCPToolCatalogue?
    @State private var listedCount = 0
    @State private var listing = false

    var body: some View {
        List {
            Section {
                ForEach(MCPWords.about, id: \.self) { line in
                    Text(line)
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                TextField(MCPWords.addressPlaceholder, text: $typedAddress)
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
#endif
                SecureField(MCPWords.tokenPlaceholder, text: $typedToken)
                    .autocorrectionDisabled()
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                Button { save() } label: {
                    Label(MCPWords.save, systemImage: "server.rack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .disabled(typedAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if saved != nil {
                    Button { Task { await list() } } label: {
                        Label(listing ? MCPWords.listing : MCPWords.listTools, systemImage: "list.bullet")
                    }
                    .disabled(listing)
                    Button(role: .destructive) { forget() } label: {
                        Text(MCPWords.forget).foregroundStyle(Theme.critical)
                    }
                }
                if let said {
                    Text(said).font(.footnote).foregroundStyle(Theme.measured)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let saved, !saved.isEncrypted {
                    Text(MCPWords.unencrypted(host: saved.host))
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let problem {
                    Label(problem, systemImage: "xmark.octagon")
                        .font(.footnote).foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                SectionHeading(text: MCPWords.heading)
            }
            .listRowBackground(Theme.surfacePrimary)

            if let catalogue {
                Section {
                    Text(MCPWords.counted(readOnly: catalogue.plannerTools.count, total: catalogue.entries.count))
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    if listedCount > catalogue.entries.count {
                        Text(MCPWords.cut).font(.footnote).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if catalogue.plannerTools.isEmpty {
                        Text(MCPWords.noneReadOnly).font(.footnote).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(catalogue.plannerTools, id: \.name) { tool in
                        MCPToolRow(name: tool.title ?? tool.name, detail: tool.name)
                    }
                } header: {
                    SectionHeading(text: MCPWords.readOnlyHeading)
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    ForEach(catalogue.entries.filter { !$0.verdict.joinsPlanner }, id: \.tool.name) { entry in
                        if case .excluded(let why) = entry.verdict {
                            MCPToolRow(name: entry.tool.name, detail: MCPWords.why(why))
                        }
                    }
                } header: {
                    SectionHeading(text: MCPWords.excludedHeading)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(MCPWords.heading)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            saved = MCPServerStore.load()
            if let saved {
                typedAddress = saved.url.absoluteString
                tokenHint = MCPTokenStore.load()?.hint
                said = MCPWords.savedHere(host: saved.host, hint: tokenHint)
            }
        }
    }

    private func save() {
        problem = nil
        catalogue = nil
        let address: MCPServerAddress
        switch MCPServerAddress.parse(typedAddress) {
        case .failure(let why): problem = why.says; return
        case .success(let a): address = a
        }
        var bearer: MCPBearer?
        if !typedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            switch MCPBearer.cleaned(typedToken) {
            case .failure(let why): problem = why.says; return
            case .success(let b): bearer = b
            }
            if !address.isEncrypted && !address.isLocal { problem = MCPWords.tokenNeedsEncryption; return }
        } else if saved?.host == address.host && saved?.url == address.url {
            bearer = MCPTokenStore.load()      // same server, token left blank: keep the saved one
        }
        MCPServerStore.save(address)
        if let bearer { MCPTokenStore.save(bearer) } else { MCPTokenStore.clear() }
        typedToken = ""
        saved = address
        tokenHint = bearer?.hint
        said = MCPWords.savedHere(host: address.host, hint: tokenHint)
    }

    private func forget() {
        MCPServerStore.clear()
        MCPTokenStore.clear()
        saved = nil
        tokenHint = nil
        catalogue = nil
        typedAddress = ""
        said = nil
        problem = nil
    }

    private func list() async {
        guard let saved else { return }
        listing = true
        problem = nil
        defer { listing = false }
        do {
            let source = try MCPHTTPToolSource(address: saved, bearer: MCPTokenStore.load())
            let tools = try await source.listTools()
            await source.disconnect()
            listedCount = tools.count
            catalogue = MCPToolCatalogue(tools)
        } catch let f as MCPHTTPToolSource.Failure {
            problem = f.says
        } catch {
            problem = MCPWords.failedUnreachable
        }
    }
}

private struct MCPToolRow: View {
    let name: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
            Text(name).foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
