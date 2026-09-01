import SwiftUI
import StudioKit
import DuckKit

/// Browse policies other people have published, and bring one home.
///
/// THE APP COULD NOT SEE THIS COMMUNITY AT ALL. People publish trained
/// Microduck policies to the Hub tagged `microduck-policy`, with a manifest
/// beside the weights saying what they trained and what they did not test.
/// Until now the only way one of those reached this app was somebody AirDropping
/// the `.onnx`, which arrives with none of that.
///
/// WHAT MAKES IT WORTH A SCREEN RATHER THAN A LINK. The manifest carries the
/// action scale — the number this app otherwise GUESSES from the file name, and
/// guesses wrong for anything Pollen did not ship. Importing through here keeps
/// the author's own numbers and their own caveats attached to the file.
struct PolicyHubView: View {
    @ObservedObject var model: LibraryModel

    @State private var search = ""
    @State private var found: [PolicyHub.Listing] = []
    @State private var busy = false
    @State private var failure: String?
    /// The manifest of whichever policy is open, once fetched.
    @State private var opened: [String: DuckPolicyManifest] = [:]
    @State private var importing: String?
    @State private var imported: Set<String> = []

    var body: some View {
        List {
            Section {
                Text(PolicyHub.provenanceNote)
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    TextField("Search published policies", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await load() } }
                    Button { Task { await load() } } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .disabled(busy)
                }
            }

            if busy && found.isEmpty {
                Section { HStack { ProgressView(); Text("Looking…").font(.footnote) } }
            }

            ForEach(found) { listing in
                Section {
                    row(listing)
                    if let manifest = opened[listing.repository] {
                        details(manifest, for: listing)
                    } else {
                        Button { Task { await open(listing) } } label: {
                            Label("Read its manifest", systemImage: "doc.text.magnifyingglass")
                                .font(.footnote)
                        }
                        .disabled(busy)
                    }
                }
            }
        }
        .navigationTitle("Published policies")
        .navigationBarTitleDisplayMode(.inline)
        .task { if found.isEmpty { await load() } }
        .alert("The Hub", isPresented: Binding(
            get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(failure ?? "") }
    }

    private func row(_ listing: PolicyHub.Listing) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(listing.name).font(.body)
            Text("by \(listing.author)" + (listing.updated.map { " · \($0.prefix(10))" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func details(_ manifest: DuckPolicyManifest,
                         for listing: PolicyHub.Listing) -> some View {
        if let summary = manifest.summary {
            Text(summary).font(.footnote)
        }
        // THE WIDTHS FIRST, because a manifest that claims the wrong shape is
        // the one case where nothing else on this card is worth reading.
        if let complaint = manifest.shapeComplaint {
            Label(complaint, systemImage: "xmark.octagon")
                .font(.caption).foregroundStyle(.orange)
        } else {
            LabeledContent("Shape",
                           value: "\(manifest.obsLength) → \(manifest.actionLength)")
                .font(.caption)
        }
        // THE NUMBER THIS APP WOULD OTHERWISE INVENT, and StudioKit says how it
        // compares to the guess — see `DuckPolicyManifest.scaleLine`.
        if let line = manifest.scaleLine {
            LabeledContent(line.title, value: line.value).font(.caption)
        }
        if let duration = manifest.durationSeconds {
            LabeledContent("One shot", value: String(format: "%g s", duration))
                .font(.caption)
        }
        Text(manifest.honesty)
            .font(.caption).foregroundStyle(.secondary)

        if imported.contains(listing.repository) {
            Label("In your Policies", systemImage: "checkmark.circle")
                .font(.footnote).foregroundStyle(.green)
        } else {
            Button { Task { await bring(listing, manifest) } } label: {
                Label(importing == listing.repository ? "Downloading…" : "Add to my policies",
                      systemImage: "square.and.arrow.down")
            }
            .disabled(busy || !manifest.claimsTheRightShape)
        }
    }

    // MARK: - fetching

    private func get(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw NSError(domain: "hub", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "The Hub answered \(http.statusCode) for \(url.lastPathComponent)."])
        }
        return data
    }

    @MainActor private func load() async {
        busy = true; defer { busy = false }
        do {
            found = try PolicyHub.read(await get(PolicyHub.searchURL(matching: search)),
                                       matching: search)
        } catch let error as PolicyHub.ReadError {
            failure = error.message; found = []
        } catch {
            failure = error.localizedDescription
        }
    }

    @MainActor private func open(_ listing: PolicyHub.Listing) async {
        busy = true; defer { busy = false }
        guard let url = PolicyHub.fileURL(repository: listing.repository,
                                          path: PolicyHub.manifestPath) else { return }
        do {
            opened[listing.repository] = try DuckPolicyManifest.read(await get(url))
        } catch let error as DuckPolicyManifest.ReadError {
            failure = "\(listing.name): \(error.message)"
        } catch {
            failure = "\(listing.name): \(error.localizedDescription)"
        }
    }

    @MainActor private func bring(_ listing: PolicyHub.Listing,
                                  _ manifest: DuckPolicyManifest) async {
        importing = listing.repository
        busy = true
        defer { busy = false; importing = nil }
        guard let url = PolicyHub.fileURL(repository: listing.repository,
                                          path: PolicyHub.policyPath) else { return }
        do {
            let bytes = try await get(url)
            // THROUGH THE SAME DOOR AS EVERY OTHER POLICY, so a download gets
            // exactly the checks an AirDropped file gets — including this app's
            // own read of the graph, which is what would catch a manifest that
            // is wrong about its own weights.
            // NAMED FOR THE REPOSITORY IT CAME FROM, not `policy.onnx` — every
            // one of these repositories calls its weights the same thing, and
            // `accept` stores by identity precisely so two of them cannot
            // overwrite each other, but a library full of rows all reading
            // "policy" is its own kind of lost.
            model.accept(bytes, named: "\(listing.name).onnx",
                         origin: "huggingface.co/\(listing.repository)")
            imported.insert(listing.repository)
        } catch {
            failure = "\(listing.name): \(error.localizedDescription)"
        }
    }
}
