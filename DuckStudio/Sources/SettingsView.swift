import SwiftUI
import StudioKit

/// The machines this app connects to, and the credentials that name you to them.
///
/// THE BOUNDARY, BECAUSE IT WILL NOT SURVIVE TWO CONTRIBUTORS OTHERWISE:
/// Settings holds the things a person sets up ONCE and expects to find again —
/// the models it can draft with, the benches it can run on, the token it
/// publishes with. Nothing a person chooses WHILE DOING A TASK belongs here. A
/// venue for this match, which repository to scan, which brain writes this
/// particular draft: those are answered where the task is, and moving them here
/// would mean leaving the task to answer a question about the task.
///
/// WHY IT EXISTS. Three things you configure once lived in three unrelated
/// places: models behind the Draft tab's chat, benches behind an icon in the
/// Policies toolbar, and the Hugging Face token four taps inside one motion's
/// publish sheet — where `TokenStore.clear()` had no caller at all, so a write
/// token that can create and delete repositories under somebody's name could be
/// saved and never removed. Nothing in the app was called "Settings", which is
/// the first word anybody looks for.
///
/// IT IS ONE GEAR ON FIVE TAB ROOTS, NOT A SIXTH TAB. The tab bar is full and
/// the five names are load-bearing; a gear in the same place on every root is
/// findable without spending the one slot left.
struct SettingsView: View {
    @ObservedObject var models: EndpointStore
    @ObservedObject var benches: BenchStore

    @State private var token = ""
    @State private var account: String?
    @State private var removed = false
    @State private var busy = false
    @State private var failure: String?

    var body: some View {
        Form {
            // BOTH SALVAGE NOTICES, AT THE TOP. Each store keeps a count of
            // rows it could not read, and each used to be drawn only on its own
            // screen — so the notice that something you configured is gone was
            // behind the very screen you would not think to open. This is a
            // shorter walk, not a fix: somebody who never opens Settings still
            // learns their bench was dropped when a run fails.
            if let note = models.unreadableNote {
                Section {
                    Text(note).font(.footnote)
                    Button("Got it") { models.dismissUnreadableNote() }
                }
            }
            if let note = benches.unreadableNote {
                Section {
                    Text(note).font(.footnote)
                    Button("Got it") { benches.dismissUnreadableNote() }
                }
            }

            Section {
                NavigationLink { ModelSettingsView(store: models) } label: {
                    Label("Models", systemImage: "brain")
                }
            } footer: {
                Text("What writes a draft when you describe a motion in words. Apple's "
                   + "on-device model needs no setup; anything speaking the OpenAI chat API "
                   + "works too, including one running on your own machine.")
            }

            Section {
                NavigationLink { BenchSettingsView(store: benches) } label: {
                    Label("Benches", systemImage: "server.rack")
                }
            } footer: {
                // NO "CONNECTED" OR "CHECKED" WORDING HERE. Settings links to
                // the screen that can ask a bench for its health; it must not
                // summarise a state nobody measured this launch.
                Text("Machines on your network with physics on them. This phone has none, so "
                   + "running a policy or a motion needs one.")
            }

            huggingFace
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { token = TokenStore.load() ?? "" }
    }

    @ViewBuilder private var huggingFace: some View {
        Section {
            SecureField("hf_…", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button(busy ? "Checking…" : "Check this token") {
                Task { await check() }
            }
            .disabled(token.isEmpty || busy)

            if TokenStore.load() != nil {
                Button("Remove this token", role: .destructive) { remove() }
            }

            // NAMED ONLY IN THE SECONDS AFTER A CHECK SOMEBODY ASKED FOR.
            // Nothing persists the account name, so printing one from a saved
            // token would assert an identity verified at an unknown time, on a
            // credential that may have been revoked on the web an hour ago.
            if let account {
                Label("Publishing as \(account)", systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(.green)
            }
            if removed {
                Text(HuggingFacePublish.tokenRemovedNote)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let failure {
                Text(failure).font(.footnote).foregroundStyle(.orange)
            }
        } header: {
            Text("Hugging Face")
        } footer: {
            Text(TokenStore.load() == nil ? HuggingFacePublish.tokenAbsentNote
                                          : HuggingFacePublish.tokenHeldNote)
        }
    }

    /// DELIBERATELY THE SAME REQUEST `PublishMotionView.check()` MAKES, and
    /// deliberately not shared with it. Collapsing the two would send somebody
    /// who is halfway through publishing a motion to another tab to type a
    /// token, which is the opposite of what this screen is for: it exists so
    /// the token has a HOME, not so it has only one door.
    @MainActor private func check() async {
        busy = true; failure = nil; account = nil; removed = false
        defer { busy = false }
        let request = HuggingFacePublish.urlRequest(for: HuggingFacePublish.whoami(),
                                                    token: token)
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

    private func remove() {
        TokenStore.clear()
        token = ""
        account = nil
        failure = nil
        removed = true
    }
}
