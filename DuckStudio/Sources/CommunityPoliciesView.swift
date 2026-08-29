import SwiftUI
import DuckKit
import StudioKit

/// What other people have trained for this robot.
///
/// A POLICY WITHOUT ITS MANIFEST IS A NETWORK NOBODY CAN DRIVE. The `.onnx`
/// states its input and output widths and nothing else; it does not say that
/// command slot 0 is a flag rather than a forward velocity, which is exactly
/// the difference between `flamingo-cycle` standing on one foot and it trying
/// to walk. So this screen leads with the manifest: what the slots mean, what
/// the author measured, and what the author says breaks it.
///
/// NOTHING LEAVES THE DEVICE UNTIL ASKED, the same as the Pollen catalogue —
/// the address is printed first and the scan is a button.
struct CommunityPoliciesView: View {
    @ObservedObject var model: LibraryModel

    @State private var entries: [PolicyCatalogue.CommunityEntry] = []
    @State private var manifests: [String: PolicyManifest] = [:]
    @State private var noManifest: Set<String> = []
    @State private var busy = false
    @State private var working: String?
    @State private var failure: String?

    private var listing: PolicySource.Request { PolicyCatalogue.communityListing() }

    var body: some View {
        List {
            Section {
                Text("Anyone can train a Microduck policy and publish it. These are the ones on Hugging Face tagged for this robot.")
                    .font(.footnote)
                Text(listing.displayURL)
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Where to look")
            }

            Section {
                Button {
                    Task { await scan() }
                } label: {
                    HStack {
                        Label("Scan for shared policies", systemImage: "arrow.down.circle")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy)
            }

            if let failure {
                Section { Text(failure).font(.footnote).foregroundStyle(.orange) }
            }

            ForEach(entries) { entry in
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.subheadline.weight(.medium))
                            Text("by \(entry.author)\(entry.updated.map { " · \($0)" } ?? "")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if working == entry.id {
                            ProgressView()
                        } else if manifests[entry.id] == nil && !noManifest.contains(entry.id) {
                            Button("Read") { Task { await readManifest(entry) } }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    if let manifest = manifests[entry.id] {
                        card(manifest, entry: entry)
                    } else if noManifest.contains(entry.id) {
                        // The honest version of "we could not import this".
                        Label("No Microduck manifest in this repository, so what its command "
                              + "block means is not written down anywhere. It may still be a "
                              + "fine policy — it cannot be driven correctly from here.",
                              systemImage: "questionmark.circle")
                            .font(.caption).foregroundStyle(.secondary)
                        Link("Open it on Hugging Face", destination: URL(string: entry.webURL)!)
                            .font(.caption)
                    }
                } header: {
                    HStack {
                        Text(entry.id).font(.caption2.monospaced())
                        if entry.declaresPolicyTag {
                            Image(systemName: "checkmark.seal").foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Text("The tag is a courtesy, not a proof. What decides whether a shared network can be driven here is its manifest — Pollen's sharing format, the same one their own policies carry.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Community policies")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func card(_ manifest: PolicyManifest, entry: PolicyCatalogue.CommunityEntry) -> some View {
        if let summary = manifest.summary {
            Text(summary).font(.footnote)
        }
        if let command = manifest.command, !command.twist.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("What you send it").font(.caption.weight(.medium))
                ForEach(Array(command.twist.enumerated()), id: \.offset) { index, meaning in
                    Text("twist[\(index)] — \(meaning)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        HStack(spacing: 10) {
            Label("\(manifest.observationLength) → \(manifest.actionLength)", systemImage: "arrow.left.arrow.right")
            if let hz = manifest.controlHz { Text("\(Int(hz)) Hz") }
            if let kind = manifest.kind { Text(kind) }
        }
        .font(.caption2).foregroundStyle(.secondary)

        if manifest.isRunnableHere {
            Button {
                Task { await install(entry, manifest: manifest) }
            } label: {
                Label("Add to my policies", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(working == entry.id)
        } else {
            ForEach(manifest.incompatibilities, id: \.self) { problem in
                Label(problem.message, systemImage: "xmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        ForEach(manifest.cautions, id: \.self) { caution in
            Label(caution, systemImage: "exclamationmark.triangle")
                .font(.caption2).foregroundStyle(.secondary)
        }
        if let training = manifest.training, let task = training.taskID {
            Text("Trained as \(task)\(training.run.map { " · run \($0)" } ?? "")")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - the network

    private func scan() async {
        busy = true; failure = nil; entries = []
        defer { busy = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: listing.url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "\(listing.host) answered \(http.statusCode)."
                return
            }
            entries = try PolicyCatalogue.parseCommunity(data)
            if entries.isEmpty { failure = "Nobody has published one yet." }
        } catch {
            failure = "\(error.localizedDescription)"
        }
    }

    private func readManifest(_ entry: PolicyCatalogue.CommunityEntry) async {
        working = entry.id; failure = nil
        defer { working = nil }
        do {
            let request = try PolicySource.huggingFaceManifest(repository: entry.id)
            let (data, response) = try await URLSession.shared.data(from: request.url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                noManifest.insert(entry.id)
                return
            }
            manifests[entry.id] = try PolicyManifest.decode(data)
        } catch let error as PolicyManifest.ReadError {
            if case .unsupportedSchema(let version) = error {
                failure = "\(entry.name) is written in sharing format \(version), which this "
                        + "version of the app has not been taught to read."
            } else {
                noManifest.insert(entry.id)
            }
        } catch {
            failure = "\(error.localizedDescription)"
        }
    }

    private func install(_ entry: PolicyCatalogue.CommunityEntry, manifest: PolicyManifest) async {
        working = entry.id; failure = nil
        defer { working = nil }
        do {
            let request = try PolicySource.huggingFace(repository: entry.id, file: "policy.onnx")
            let (data, response) = try await URLSession.shared.data(from: request.url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "\(request.host) answered \(http.statusCode)."
                return
            }
            guard data.count <= PolicySource.byteCap else {
                failure = "That file is larger than this app will load."
                return
            }
            model.accept(data, named: "\(manifest.name).onnx",
                         origin: "huggingface.co/\(entry.id)")
        } catch {
            failure = "\(error)"
        }
    }
}
