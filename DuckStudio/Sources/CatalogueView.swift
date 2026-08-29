import SwiftUI
import DuckKit
import DuckEvidence
import StudioKit

/// Go and see what Pollen currently publish.
///
/// THE APP'S OWN LIST IS FROZEN AT BUILD TIME and Pollen keep training, so a
/// release newer than this build shows up in the library as "unrecognised" —
/// honest, and unhelpful. This is the difference between "I have not heard of
/// this" and "here is what exists".
///
/// NOTHING IS FETCHED UNTIL SOMEBODY ASKS. The address is printed first, whole,
/// and the scan button sits under it: a request leaving the device because a
/// screen appeared is the shape of an accident.
struct CatalogueView: View {
    @ObservedObject var model: LibraryModel

    @State private var source = PolicyCatalogue.officialPolicies
    @State private var entries: [PolicyCatalogue.Entry] = []
    @State private var headline: String?
    @State private var failure: String?
    @State private var busy = false
    @State private var fetching: String?

    var body: some View {
        List {
            Section {
                Picker("Repository", selection: $source) {
                    ForEach(PolicyCatalogue.sources) { s in
                        Text(s.name).tag(s)
                    }
                }
                .pickerStyle(.menu)
                Text(source.holds).font(.caption).foregroundStyle(.secondary)
                Text(source.webURL)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            } header: {
                Text("Where to look")
            } footer: {
                Text("Public repositories only. This app holds no account and there is nowhere to paste a token — a private repository fails with a plain 401, and the way round it is to download the file in a browser and open it here.")
            }

            Section {
                Button {
                    Task { await scan() }
                } label: {
                    HStack {
                        Label("Scan for what is published", systemImage: "arrow.down.circle")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy)
            }

            if let failure {
                Section { Text(failure).font(.footnote).foregroundStyle(.orange) }
            }

            if let headline {
                Section {
                    Text(headline).font(.footnote)
                } header: {
                    Text("What is there")
                }
            }

            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                } footer: {
                    Text(isPolicySource
                         ? "Opening one downloads it and fingerprints its weights. That is the only thing that decides whether a file is a policy you already hold — upstream ships two of these under names this app carries differently."
                         : "These are the training environments. Every reward weight and tolerance in an intent's Reward panel is read out of these files.")
                }
            }

            Section {
                NavigationLink {
                    CommunityPoliciesView(model: model)
                } label: {
                    Label("Community policies", systemImage: "person.2")
                }
                Text("Pollen are not the only people training this robot any more. Other authors publish policies on Hugging Face, each with a manifest saying what its command block means.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("And everyone else")
            }

            Section {
                Text(PolicyCatalogue.intentsNote)
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("And motions?")
            }
        }
        .navigationTitle("Pollen Robotics")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isPolicySource: Bool { source.id == PolicyCatalogue.officialPolicies.id }

    private func row(_ entry: PolicyCatalogue.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.filename).font(.subheadline.monospaced()).lineLimit(1)
                Spacer()
                if fetching == entry.path {
                    ProgressView()
                } else if isPolicySource {
                    Button("Open") { Task { await fetch(entry) } }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Text(isPolicySource
                 ? PolicyCatalogue.summary(of: entry)
                 : "\(entry.bytes / 1024) KB")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - the network

    private func scan() async {
        busy = true; failure = nil; headline = nil; entries = []
        defer { busy = false }
        let request = PolicyCatalogue.listing(source)
        do {
            var urlRequest = URLRequest(url: request.url)
            // GitHub answers HTML to a request with no Accept header often
            // enough that asking explicitly is worth one line.
            urlRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "\(request.host) answered \(http.statusCode)."
                return
            }
            let found = try PolicyCatalogue.parse(
                data, source: source,
                extensions: isPolicySource ? ["onnx"] : ["py"])
            entries = found
            headline = isPolicySource
                ? PolicyCatalogue.headline(found)
                : "\(found.count) training environments."
        } catch let error as PolicyCatalogue.ScanError {
            failure = {
                switch error {
                case .refused(let message): return "\(request.host) said: \(message)"
                case .notJSON: return "That address did not answer with JSON."
                case .noTree: return "The answer had no file list in it."
                }
            }()
        } catch {
            failure = "\(error.localizedDescription)"
        }
    }

    /// Download one policy and hand it to the library, which fingerprints it.
    private func fetch(_ entry: PolicyCatalogue.Entry) async {
        fetching = entry.path; failure = nil
        defer { fetching = nil }
        do {
            let request = try PolicyCatalogue.download(entry, from: source)
            let (data, response) = try await URLSession.shared.data(from: request.url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = "\(request.host) answered \(http.statusCode)."
                return
            }
            guard data.count <= PolicySource.byteCap else {
                failure = "That file is larger than this app will load."
                return
            }
            model.accept(data, named: request.suggestedName,
                         origin: "github.com/\(source.owner)/\(source.repository)")
        } catch {
            failure = "\(error)"
        }
    }
}
