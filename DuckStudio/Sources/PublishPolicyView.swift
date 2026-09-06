import SwiftUI
import DuckKit
import StudioKit

/// Put a policy on Hugging Face, where the Behaviours tab's Community list
/// will read it back.
///
/// THE SAME SCREEN AS `PublishMotionView`, FOR THE OTHER KIND OF FILE. The
/// token flow, the address, the private-by-default toggle and the "every byte
/// first" section are the same shape, because the risk is the same: a write
/// token that can create repositories under somebody's name, and a publish
/// that is public and not really undoable. What differs is the kit type that
/// builds the files — `PolicyPublication`, a model repository — and the one
/// sentence it insists on, which is what a stranger reads before running this
/// on a robot.
struct PublishPolicyView: View {
    let entry: PolicyLibrary.Entry
    @ObservedObject var library: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var account: String?
    @State private var repositoryName = ""
    @State private var isPrivate = true
    @State private var whatItDoes = ""
    @State private var note = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var published: String?

    private var built: Result<PolicyPublication, Error> {
        Result {
            guard let onnx = PolicyStore.data(for: entry) else {
                throw HuggingFacePublish.Refusal.nothingToPublish
            }
            return try PolicyPublication(entry: entry, onnx: onnx,
                                         manifest: library.manifestBytes(for: entry),
                                         whatItDoes: whatItDoes,
                                         note: note.isEmpty ? nil : note)
        }
    }

    private var address: Result<HuggingFacePublish.Repository, Error> {
        Result {
            try HuggingFacePublish.repository(namespace: account ?? "",
                                              name: repositoryName,
                                              kind: PolicyPublication.repositoryKind)
        }
    }

    private static func stop(address: Result<HuggingFacePublish.Repository, Error>,
                             publication: Result<PolicyPublication, Error>) -> String? {
        if case .failure(let error) = address { return message(error) }
        if case .failure(let error) = publication { return message(error) }
        return nil
    }

    private static func message(_ error: Error) -> String {
        switch error {
        case let refusal as HuggingFacePublish.Refusal: return refusal.message
        case let refusal as PolicyManifest.WriteError: return refusal.message
        case let refusal as PolicyManifest.ReadError: return "\(refusal)"
        default: return "\(error)"
        }
    }

    var body: some View {
        let outcome = built
        let destination = address
        let stop = Self.stop(address: destination, publication: outcome)
        NavigationStack {
            Form {
                Section {
                    SecureField("hf_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Check this token") { Task { await check() } }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    if let account {
                        Label(HuggingFacePublish.publishingAs(account),
                              systemImage: "person.crop.circle.badge.checkmark")
                            .font(.footnote)
                            .foregroundStyle(Theme.success)
                    }
                } header: {
                    SectionHeading(text: "Your Hugging Face token")
                } footer: {
                    Text("A WRITE token, from huggingface.co/settings/tokens. It is kept in the Keychain on this device and sent only to huggingface.co, as a header — never in an address this app prints or logs.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.surfacePrimary)

                Section {
                    TextField("microduck-policy-name", text: $repositoryName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Private repository", isOn: $isPrivate)
                    TextField("What does it do, and when should it be loaded?",
                              text: $whatItDoes, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("A line about it (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                    if case .success(let repository) = destination {
                        Text(repository.webURL)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    SectionHeading(text: "Where it goes")
                } footer: {
                    if isPrivate {
                        Text("Private: only you can see it, and the Community list in this app will not list it until it is public. You can make it public on the website afterwards.")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Label("PUBLIC: anyone can find and download it, it appears on every phone's Community list, and anything already fetched stays fetched even if you delete it later.",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Theme.warning)
                    }
                }
                .listRowBackground(Theme.surfacePrimary)

                if let caveat = entry.origin.caveat {
                    Section {
                        Label(caveat, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } header: {
                        SectionHeading(text: "What the card will say")
                    } footer: {
                        Text(MotionPublication.trainsNothing)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                if let stop {
                    Section {
                        Label(stop, systemImage: "xmark.octagon")
                            .font(.footnote)
                            .foregroundStyle(Theme.refused)
                    } header: {
                        SectionHeading(text: "Not ready to publish")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                } else if case .success(let publication) = outcome {
                    Section {
                        ForEach(publication.files, id: \.path) { file in
                            TelemetryRow(label: file.path, value: "\(file.bytes)", unit: "bytes")
                        }
                        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                            Text("Parameter fingerprint")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            Text(publication.fingerprint)
                                .font(.caption2.monospaced()).foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                        }
                    } header: {
                        SectionHeading(text: "What gets published")
                    } footer: {
                        Text("The network exactly as this phone holds it, its manifest, and a card carrying the microduck tag the Community list filters on. The fingerprint on the card is the one thing a recipient can check.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                if let failure {
                    Section {
                        Label(failure, systemImage: "xmark.octagon")
                            .font(.footnote)
                            .foregroundStyle(Theme.refused)
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                if let published {
                    Section {
                        Link(destination: URL(string: published)!) {
                            Label("Open it on Hugging Face", systemImage: "arrow.up.right.square")
                        }
                        Text(published)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.textSecondary)
                            .textSelection(.enabled)
                    } header: {
                        SectionHeading(text: "Published")
                    }
                    .listRowBackground(Theme.surfacePrimary)
                }

                Section {
                    Button {
                        Task { await publish() }
                    } label: {
                        HStack(spacing: Theme.spacing(.tight)) {
                            Text(isPrivate ? "Create a private repository" : "Publish publicly")
                                .frame(maxWidth: .infinity)
                            if busy { ProgressView() }
                        }
                    }
                    .buttonStyle(.primaryAction)
                    .disabled(busy || published != nil || stop != nil)
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundSecondary)
            .navigationTitle("Publish this policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                token = TokenStore.load() ?? ""
                if repositoryName.isEmpty { repositoryName = PolicyPublication.slug(for: entry.title) }
                if !token.isEmpty, account == nil { Task { await check() } }
            }
        }
    }

    private func check() async {
        busy = true; failure = nil
        defer { busy = false }
        let request = HuggingFacePublish.urlRequest(for: HuggingFacePublish.whoami(), token: token)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = HuggingFacePublish.answered(http.statusCode)
                account = nil
                return
            }
            guard let name = HuggingFacePublish.parseWhoami(data) else {
                failure = "huggingface.co answered, but not with an account name."
                account = nil
                return
            }
            account = name
            TokenStore.save(token)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func publish() async {
        guard case .success(let repository) = address,
              case .success(let publication) = built else { return }
        busy = true; failure = nil
        defer { busy = false }
        do {
            let create = HuggingFacePublish.urlRequest(
                for: HuggingFacePublish.create(repository, isPrivate: isPrivate), token: token)
            let (_, createResponse) = try await URLSession.shared.data(for: create)
            if let http = createResponse as? HTTPURLResponse,
               http.statusCode != 200, http.statusCode != 409 {   // 409: it already exists
                failure = HuggingFacePublish.creating(http.statusCode)
                return
            }
            let commit = try HuggingFacePublish.commit(
                repository, summary: publication.summary, files: publication.files)
            let (data, commitResponse) = try await URLSession.shared.data(
                for: HuggingFacePublish.urlRequest(for: commit, token: token))
            if let http = commitResponse as? HTTPURLResponse, http.statusCode >= 300 {
                let detail = String(decoding: data.prefix(200), as: UTF8.self)
                failure = "Publishing answered \(http.statusCode). \(detail)"
                return
            }
            published = repository.webURL
            Haptic.finished()
        } catch let refusal as HuggingFacePublish.Refusal {
            failure = refusal.message
        } catch {
            failure = error.localizedDescription
        }
    }
}
