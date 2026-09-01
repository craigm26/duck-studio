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
    /// The one reader of `Theme.appearanceKey` had zero writers: the design
    /// run built the preference, its titles and its detail copy, and no
    /// screen offered it — so un-forcing dark made dark UNREACHABLE rather
    /// than optional. This is the writer.
    @AppStorage(Theme.appearanceKey) private var appearance = Theme.defaultAppearance.rawValue
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
                    // IN `warning`, WITH THE TRIANGLE SAYING IT AGAIN IN A
                    // SHAPE. Something a person configured could not be read
                    // back: not as it was left, and nothing broken. This is the
                    // same treatment `ModelSettingsView` gives the same note,
                    // because it is the same sentence arriving by a shorter
                    // route, and a notice that changes colour depending on
                    // which screen you found it on is a notice that teaches
                    // nobody what the colour means.
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Got it") { models.dismissUnreadableNote() }
                }
                .listRowBackground(Theme.surfacePrimary)
            }
            if let note = benches.unreadableNote {
                Section {
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Got it") { benches.dismissUnreadableNote() }
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                // THE STOCK PICKER, WEARING THE APP'S TINT. A segmented or
                // hand-drawn pair of cards here would be two more shapes to
                // keep at 44 points and to teach VoiceOver about; a `Picker` in
                // a `Form` is already a row that says its label, its value and
                // that it can be changed.
                Picker("Appearance", selection: $appearance) {
                    ForEach(Theme.Appearance.allCases) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                }
            } footer: {
                // THE DETAIL IS THE APPEARANCE'S OWN, not composed here, so the
                // sentence a person reads is the one the type documents.
                Text((Theme.Appearance(rawValue: appearance) ?? Theme.defaultAppearance).detail)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // THE GLYPH CARRIES THE ACTION COLOUR AND THE WORD DOES NOT —
                // the arrangement `CatalogueView` makes for every door that is
                // not the primary one. A navigation row is a place to go, not
                // the thing this screen is for, so it gets a coloured mark
                // rather than a coloured sentence.
                NavigationLink { ModelSettingsView(store: models) } label: {
                    Label {
                        Text("Models").foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "brain").foregroundStyle(Theme.actionSecondary)
                    }
                }
            } footer: {
                // THREE, NOT TWO. A downloaded model is neither Apple's nor
                // something speaking HTTP, and this list is the app telling
                // somebody what their options are.
                Text("What writes a draft when you describe a motion in words. Apple's "
                   + "on-device model needs no setup; a model downloaded onto this phone runs "
                   + "with nothing leaving it; and anything on your network speaking the "
                   + "OpenAI chat API works too.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                NavigationLink { BenchSettingsView(store: benches) } label: {
                    Label {
                        Text("Benches").foregroundStyle(Theme.textPrimary)
                    } icon: {
                        Image(systemName: "server.rack")
                            .foregroundStyle(Theme.actionSecondary)
                    }
                }
            } footer: {
                // NO "CONNECTED" OR "CHECKED" WORDING HERE. Settings links to
                // the screen that can ask a bench for its health; it must not
                // summarise a state nobody measured this launch.
                Text("Machines on your network with physics on them. This phone has none, so "
                   + "running a policy or a motion needs one.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            huggingFace
        }
        // THE RECESSED GROUND UNDER THE CARDS, and it is what lets any coloured
        // word be set on this screen at all: `Palette` documents
        // `backgroundSecondary` as carrying the four inks between 4.17:1 and
        // 4.27:1 — short of the 4.5:1 body text owes — so every row keeps a
        // real `surfacePrimary` card under it and nothing is set on the ground.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { token = TokenStore.load() ?? "" }
    }

    @ViewBuilder private var huggingFace: some View {
        Section {
            SecureField("hf_…", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            // THE ONE CONTROL ON THIS SCREEN THAT LEAVES THE PHONE WITH
            // SOMETHING TO PROVE, so it is the one capsule in the action colour
            // — the same rule `EndpointEditor` follows for "Check this
            // address", and the same verb. Everything else here edits a field
            // or opens another screen.
            //
            // THE WORD IS THE SPINNER. "Checking…" replaces the verb while the
            // request is out, which is the only version of that state a screen
            // reader has ever been able to read, and it says what is being
            // waited on rather than that this phone is busy.
            Button {
                Task { await check() }
            } label: {
                Label(busy ? "Checking…" : "Check this token", systemImage: "key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primaryAction)
            .disabled(token.isEmpty || busy)
            .listRowSeparator(.hidden)
            .accessibilityLabel(Text("Check this token"))
            .accessibilityValue(Text(busy ? "Checking" : ""))

            if TokenStore.load() != nil {
                // THE ROLE STAYS AND THE COLOUR COMES FROM THE PALETTE — what
                // `TrickRunView` does with the same shape of row. `.destructive`
                // is what tells VoiceOver and the system what this is, and it is
                // worth keeping on a control that deletes a write credential.
                // Its red, though, is UIKit's; `Theme.critical` is the app's
                // refusal colour and is proved at 4.5:1 on every ground this app
                // sets words on. Set on the label rather than as a tint, because
                // a tint does not reach the title of a role-coloured row.
                Button(role: .destructive) { remove() } label: {
                    Text("Remove this token").foregroundStyle(Theme.critical)
                }
            }

            // NAMED ONLY IN THE SECONDS AFTER A CHECK SOMEBODY ASKED FOR.
            // Nothing persists the account name, so printing one from a saved
            // token would assert an identity verified at an unknown time, on a
            // credential that may have been revoked on the web an hour ago.
            //
            // THREE OUTCOMES OF ONE SECTION, EACH A WORD BESIDE ITS COLOUR AND
            // EACH WITH ITS OWN GLYPH. They appear in the same place and are
            // mutually exclusive, which is exactly the situation where a reader
            // is asked to tell green from orange with nothing beside them to
            // compare against — so the tick, the bin and the triangle carry the
            // same three claims in shapes. Roughly one man in twelve cannot
            // reliably separate the pair this used to rely on.
            if let account {
                // `success` AND NOT `measured`. Teal is this app's claim that a
                // machine produced the thing you are reading; this is a check
                // that passed. The name inside it came from huggingface.co, but
                // what the line reports is the state of your setup.
                Label("Publishing as \(account)", systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(Theme.success)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if removed {
                // NOT A STATE COLOUR, because nothing is wrong and nothing was
                // proved: a credential was deleted because somebody asked. The
                // sentence is `HuggingFacePublish`'s, so a test owns the words.
                Label(HuggingFacePublish.tokenRemovedNote, systemImage: "trash")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure {
                // A HOST SAID NO, IN ITS OWN WORDS — `Theme.refused` is the
                // provenance colour for exactly that, and it is what
                // `CatalogueView` sets the same kind of sentence in. Orange was
                // the raw colour here, and orange in this app is the thing you
                // press.
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(Theme.refused)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text("Hugging Face")
        } footer: {
            Text(TokenStore.load() == nil ? HuggingFacePublish.tokenAbsentNote
                                          : HuggingFacePublish.tokenHeldNote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Theme.surfacePrimary)
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
