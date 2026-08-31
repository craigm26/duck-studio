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
    /// One sentence saying WHEN to play this move. Required, and the reason is
    /// in `MotionPublication`: it is what makes a library browsable and what a
    /// model choosing a move has to read.
    @State private var whenToUse = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var published: String?

    /// The publication, or whatever refused to build it.
    ///
    /// A `Result`, NOT A `try?`. The optional this replaced swallowed two
    /// unrelated refusals — a blank "when to play it" sentence
    /// (`HuggingFacePublish.Refusal.noWhenToUse`) and a draft whose keyframes
    /// are not a legal move (`DuckMove.Invalid`, thrown by `draft.exported()`)
    /// — while the blue button stayed lit over both. Tapping it returned on
    /// the first line of `publish()`: no spinner, no message, no repository,
    /// nothing on screen changed, however many times it was pressed. The second
    /// refusal is reachable in two taps — the ••• menu opens this sheet with no
    /// check on `draft.problems`, so a draft the editor is already calling
    /// broken arrives here and used to be met with silence.
    private var built: Result<MotionPublication, Error> {
        Result {
            try MotionPublication(draft: draft, whenToUse: whenToUse,
                                  note: note.isEmpty ? nil : note)
        }
    }

    /// Where this would go, or the refusal that stops it going anywhere.
    ///
    /// A DATASET, NOT A MODEL. A trajectory is data; Pollen's community moves
    /// are all datasets, and a move published as a model is one nobody's loader
    /// will look for. The address is built here rather than inside `publish()`
    /// so that the rules for a namespace and a name — which are the kit's, in
    /// one place — are checked while the button can still say so, instead of
    /// after a person has tapped it.
    ///
    /// A MISSING ACCOUNT IS A REFUSAL LIKE ANY OTHER, hence `?? ""`: an empty
    /// namespace is `Refusal.noNamespace`, whose message is "Sign in first",
    /// which is exactly what is wrong and exactly what the token Section above
    /// is for. It used to be a bare `account == nil` term in `.disabled` with
    /// nothing printed anywhere.
    private var address: Result<HuggingFacePublish.Repository, Error> {
        Result {
            try HuggingFacePublish.repository(namespace: account ?? "",
                                              name: repositoryName,
                                              kind: MotionPublication.repositoryKind)
        }
    }

    /// The first thing standing between this draft and a repository, in the
    /// kit's own words — or nil when nothing is.
    ///
    /// THE BUTTON'S ENABLED STATE AND THE SENTENCE BESIDE IT NOW COME FROM THIS
    /// ONE VALUE, so they cannot drift. They had already drifted: the screen
    /// kept its own copy of the blank-sentence rule, trimming `.whitespaces`
    /// — space and tab only — against the kit's `.whitespacesAndNewlines`, and
    /// the field is `axis: .vertical`, so a field holding one Return showed no
    /// warning at all while the initializer still refused.
    ///
    /// THE ADDRESS IS ASKED FIRST because it is answered by the Section at the
    /// top of the form, and naming one missing thing at a time is what a person
    /// can act on.
    private static func stop(address: Result<HuggingFacePublish.Repository, Error>,
                             publication: Result<MotionPublication, Error>) -> String? {
        if case .failure(let error) = address { return message(error) }
        if case .failure(let error) = publication { return message(error) }
        return nil
    }

    /// EACH REFUSAL IS ASKED FOR ITS OWN MESSAGE. Telling somebody whose
    /// keyframe is outside its travel to "say when this move should be played"
    /// is a lie, and a wrong refusal is worse in this app than a missing one.
    /// `localizedDescription` is not an option either — `DuckMove.Invalid` has
    /// no localisation and renders as "(DuckKit.DuckMove.Invalid error 3.)".
    /// The ladder is the one `IntentAuthorView.share()` already uses.
    private static func message(_ error: Error) -> String {
        switch error {
        case let refusal as HuggingFacePublish.Refusal: return refusal.message
        case let invalid as DuckMove.Invalid: return invalid.message
        default: return "\(error)"
        }
    }

    var body: some View {
        // READ ONCE PER PASS. Building a publication runs `draft.exported()`,
        // serialises the manifest and interpolates the whole README card;
        // asking for it from the file list, the refusal row and the button's
        // gate separately would do all of that three times per keystroke.
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
                    TextField("When should this be played?", text: $whenToUse, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("A line about it (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                    if case .success(let repository) = destination {
                        // THE `datasets/` PREFIX IS SHOWN BECAUSE ITS ABSENCE
                        // IS INVISIBLE: huggingface.co/<you>/<name> does not
                        // 404 for a dataset when a model of that name exists,
                        // it silently opens the model instead. This is the
                        // kit's own `webURL` for the repository the button
                        // would create — not a second copy of the rule spelled
                        // out here, which is how a preview comes to show an
                        // address that is not the one that gets made.
                        Text(repository.webURL)
                            .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Where it goes")
                } footer: {
                    Text(isPrivate
                         ? "Private: only you can see it. You can make it public on the website afterwards."
                         : "PUBLIC: anyone can find and download it, and anything already fetched stays fetched even if you delete it later.")
                }

                // WHERE THE FILE LIST WOULD HAVE BEEN. These two are the same
                // question asked once — either there is something to publish
                // and this is it, or there is not and this is why. The screen
                // used to show the first and simply omit the second, so the
                // form quietly got shorter and the button stayed blue.
                //
                // The refusal is printed verbatim from the kit rather than
                // paraphrased here, because it is the sentence the tests
                // assert and the one a person can act on.
                //
                // THE REFUSAL IS TESTED FIRST, AND THE ORDER IS THE WHOLE FIX.
                // Keying the outer branch on `outcome` looked equivalent and is
                // not: `stop` asks the ADDRESS first, so a good motion with a
                // bad repository name — "my duck bow", one space away — landed
                // in `.success` for `outcome`, drew the file list, never drew
                // the reason, and greyed the button out. Testing `stop` first
                // makes the two branches total, because `stop == nil` already
                // implies both halves succeeded. The button's gate and the
                // printed reason are then literally the same expression, which
                // is what the comment on `.disabled` below claims.
                if let stop {
                    Section {
                        Label(stop, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    } header: {
                        Text("Not ready to publish")
                    }
                } else if case .success(let publication) = outcome {
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
                        Text("A motion, not a policy — a list of poses with times. The card says so, and says what an authored motion does not promise: driven through the standing policy in simulation, leg offsets come out shallower than authored. Nobody has measured that on a robot.")
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
                    // `stop != nil` IS THE SAME EXPRESSION THAT PRINTED THE
                    // REASON ABOVE. A button cannot go dead here without the
                    // sentence explaining it appearing in the same pass, which
                    // is why the `account == nil` and `repositoryName.isEmpty`
                    // terms that used to be here are gone: both are refusals
                    // the kit already has words for, and both are inside
                    // `stop`. The two remaining terms are the two states the
                    // screen shows for itself — the spinner in this button, and
                    // the "Published" Section above it.
                    .disabled(busy || published != nil || stop != nil)
                }
            }
            .navigationTitle("Share this motion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                token = TokenStore.load() ?? ""
                // The kit's slug, not a second copy of the rule: the same
                // string names the repository AND the move's file, and the
                // move's name on the other side is that filename.
                if repositoryName.isEmpty { repositoryName = MotionPublication.slug(for: draft.name) }
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
        // NOT A SILENT EXIT ANY MORE. Both halves of this guard are the two
        // values `stop` reads, and `stop` is what disables the button and
        // prints the reason beside it — so reaching this return means the state
        // changed between the tap and the task starting, not that somebody
        // pressed a live button and was ignored.
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
