import SwiftUI
import DuckKit
import StudioKit

/// Put a motion you made where other people can find it.
///
/// EVERYTHING IS SHOWN BEFORE ANYTHING IS SENT: which account it would publish
/// as, the exact address, and every file with its size. Publishing is public
/// and it is not really undoable — a repository can be deleted, but anything
/// already fetched is gone — so the default is a PRIVATE repository and the
/// button says which one it is making.
struct PublishMotionView: View {
    let draft: IntentDraft
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var account: String?
    @State private var repositoryName = ""
    @State private var isPrivate = true
    @State private var note = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var published: String?

    private var publication: MotionPublication? {
        try? MotionPublication(draft: draft, note: note.isEmpty ? nil : note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("hf_…", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Check this token") { Task { await check() } }
                        .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    if let account {
                        Label("Publishing as \(account)", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.footnote)
                    }
                } header: {
                    Text("Your Hugging Face token")
                } footer: {
                    Text("A WRITE token, from huggingface.co/settings/tokens. It is kept in the Keychain on this device and sent only to huggingface.co, as a header — never in an address this app prints or logs.")
                }

                Section {
                    TextField("motion-name", text: $repositoryName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle("Private repository", isOn: $isPrivate)
                    TextField("A line about it (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                    if let account, !repositoryName.isEmpty {
                        Text("huggingface.co/\(account)/\(repositoryName)")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Where it goes")
                } footer: {
                    Text(isPrivate
                         ? "Private: only you can see it. You can make it public on the website afterwards."
                         : "PUBLIC: anyone can find and download it, and anything already fetched stays fetched even if you delete it later.")
                }

                if let publication {
                    Section {
                        ForEach(publication.files, id: \.path) { file in
                            HStack {
                                Text(file.path).font(.caption.monospaced())
                                Spacer()
                                Text("\(file.bytes) bytes").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("What gets published")
                    } footer: {
                        Text("A motion, not a policy — a list of poses with times. The card says so, and says what an authored motion does not promise: driven through a policy on the robot, leg offsets come out shallower than authored.")
                    }
                }

                if let failure {
                    Section { Text(failure).font(.footnote).foregroundStyle(.orange) }
                }
                if let published {
                    Section {
                        Link(destination: URL(string: published)!) {
                            Label("Open it on Hugging Face", systemImage: "arrow.up.right.square")
                        }
                        Text(published).font(.caption2.monospaced()).textSelection(.enabled)
                    } header: {
                        Text("Published")
                    }
                }

                Section {
                    Button {
                        Task { await publish() }
                    } label: {
                        HStack {
                            Text(isPrivate ? "Create a private repository" : "Publish publicly")
                                .frame(maxWidth: .infinity)
                            if busy { ProgressView() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(account == nil || repositoryName.isEmpty || busy || published != nil)
                }
            }
            .navigationTitle("Share this motion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                token = TokenStore.load() ?? ""
                if repositoryName.isEmpty { repositoryName = slug(draft.name) }
            }
        }
    }

    /// A repository name Hugging Face will accept, from a motion's own name.
    private func slug(_ text: String) -> String {
        let lowered = text.lowercased()
        var out = ""
        for character in lowered {
            if character.isLetter || character.isNumber { out.append(character) }
            else if !out.hasSuffix("-") { out.append("-") }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "microduck-motion" : out
    }

    private func check() async {
        busy = true; failure = nil
        defer { busy = false }
        let request = HuggingFacePublish.urlRequest(for: HuggingFacePublish.whoami(), token: token)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                failure = http.statusCode == 401
                    ? "Hugging Face did not accept that token."
                    : "huggingface.co answered \(http.statusCode)."
                return
            }
            guard let name = HuggingFacePublish.parseWhoami(data) else {
                failure = "That answer did not name an account."
                return
            }
            account = name
            TokenStore.save(token)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func publish() async {
        guard let account, let publication else { return }
        busy = true; failure = nil
        defer { busy = false }
        do {
            let repository = try HuggingFacePublish.repository(namespace: account,
                                                               name: repositoryName)
            let create = HuggingFacePublish.urlRequest(
                for: HuggingFacePublish.create(repository, isPrivate: isPrivate), token: token)
            let (_, createResponse) = try await URLSession.shared.data(for: create)
            if let http = createResponse as? HTTPURLResponse,
               http.statusCode != 200, http.statusCode != 409 {   // 409: it already exists
                failure = "Creating the repository answered \(http.statusCode)."
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
        } catch let refusal as HuggingFacePublish.Refusal {
            failure = refusal.message
        } catch {
            failure = error.localizedDescription
        }
    }
}
