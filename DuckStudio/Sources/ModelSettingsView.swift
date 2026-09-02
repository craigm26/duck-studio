import Foundation
import SwiftUI
import StudioKit

/// Where drafts come from. Apple's on-device model, a machine on your network,
/// or another app on this phone.
///
/// BEGINNER AT THE TOP, EXPERT AT THE BOTTOM, one screen. A preset fills in the
/// address shape so nobody has to know that Ollama serves `/v1` on 11434; the
/// model list is fetched so nobody types `gemma4:e4b-it-qat` from memory; and
/// the test says how many tokens a second it managed, so a ninety-second wait
/// reads as a slow board rather than a broken app. Underneath that sit the
/// timeout, the bearer token and the raw URL, for somebody who already knows
/// what they are pointing at.
///
/// NOTHING ON THIS SCREEN IS ORANGE. Every row here picks a model, opens a
/// form, or navigates — the action colour belongs to the two questions the
/// EDITOR puts to an address, because those are the only controls in this part
/// of the app that leave the phone. A list of things to choose between with a
/// coloured capsule in it is a list with one row shouting.
struct ModelSettingsView: View {
    @ObservedObject var store: EndpointStore
    @State private var editing: ModelEndpoint?
    /// Held for the confirmation, because removing a downloaded model frees
    /// gigabytes and the sentence should name how many first.
    @State private var removing: ModelEndpoint?

    /// Names the MEASURED bytes for a downloaded model, and stays a plain
    /// question for anything else — an address costs nothing to retype.
    private func confirmationText(_ endpoint: ModelEndpoint) -> String {
        guard endpoint.kind == .downloadedMLX else {
            return "Remove \(endpoint.name)?"
        }
        return PhoneModelInstall.deleteConfirmation(
            named: endpoint.name, bytes: PhoneModelFiles.bytesOnDisk(endpoint.model))
    }

    private func subtitle(for endpoint: ModelEndpoint) -> String {
        switch endpoint.kind {
        case .appleOnDevice:
            return "On this phone, no setup"
        case .downloadedMLX:
            return "\(endpoint.model) · on this phone"
        case .openAICompatible:
            return "\(endpoint.model) · "
                 + "\(URL(string: endpoint.baseURL)?.host ?? endpoint.baseURL)"
        }
    }

    var body: some View {
        List {
            // A ROW THAT IS USUALLY NOT THERE, and the whole point of it is the
            // day it is: something a person configured could not be read back,
            // and this is their only notice. It sits above "Draft with" rather
            // than in a footer because a footer under a list is where notices
            // go to die.
            //
            // IT STAYS UNTIL IT IS TAPPED. The store keeps it across launches,
            // so a notice raised on a launch where nobody opened this screen is
            // still here on the one where they do; "Got it" is the only thing
            // that ends it. A notice that quietly expires is the silent failure
            // wearing the costume of a fix.
            if let note = store.unreadableNote {
                Section {
                    // IN `warning`, WHICH IS WHAT THIS IS: something is not as
                    // it was left, and nothing is broken. The triangle carries
                    // the same claim in a shape, so the notice does not depend
                    // on anybody separating yellow from grey.
                    Label(note, systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Got it") { store.dismissUnreadableNote() }
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                ForEach(store.endpoints) { endpoint in
                    Button {
                        // A DOWNLOADED MODEL MUST NOT OPEN THE HTTP EDITOR.
                        // That form has an address, a `/v1` check, a bearer
                        // token, a timeout — all inert here — and a RELAY
                        // TOGGLE, which is the one control that could make this
                        // kind's privacy note lie in the most alarming
                        // direction available. Selecting is all a row of this
                        // kind does; managing it happens where it was
                        // downloaded.
                        switch endpoint.kind {
                        case .appleOnDevice, .downloadedMLX:
                            store.selectedID = endpoint.id
                        case .openAICompatible:
                            editing = store.armed(endpoint)
                        }
                    } label: {
                        HStack(spacing: Theme.spacing(.tight)) {
                            VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                                Text(endpoint.name).foregroundStyle(Theme.textPrimary)
                                // A KIND WITH NO ADDRESS NEEDS ITS OWN
                                // SUBTITLE: the host branch renders
                                // "Qwen3-0.6B-4bit · " with nothing after the
                                // separator when baseURL is empty.
                                Text(subtitle(for: endpoint))
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: Theme.spacing(.tight))
                            if store.selectedID == endpoint.id {
                                // The tick is the ONLY thing on this screen
                                // that says which model the Ask panel will
                                // use, and an unlabelled glyph says it to
                                // nobody who cannot see it.
                                //
                                // IN `brandPrimary` RATHER THAN IN THE TINT.
                                // The tint is the orange ink every borderless
                                // control inherits, and a selection mark is not
                                // a control — teal is what this app draws a
                                // thing that is simply true.
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.brandPrimary)
                                    .accessibilityLabel(Text("Selected"))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // NO FULL SWIPE. The default is true, so an unintended
                    // flick deleted an endpoint — and, for a downloaded model,
                    // up to two gigabytes of weights — without a single tap.
                    .swipeActions(allowsFullSwipe: false) {
                        if endpoint.kind != .appleOnDevice {
                            Button("Remove", role: .destructive) { removing = endpoint }
                                // THE DESTRUCTIVE ROLE, IN THIS APP'S RED. The
                                // role is what makes it destructive; the tint
                                // is what makes it look like the rest of the
                                // app rather than like the system's default.
                                .tint(Theme.critical)
                        }
                    }
                }
            } header: {
                SectionHeading(text: "Draft with")
            } footer: {
                Text(store.selected.privacyNote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                // ABOVE THE PRESETS, because it is a different act: a preset
                // fills in a form, this downloads two gigabytes and has to say
                // what fits first.
                NavigationLink { PhoneModelPickerView(store: store) } label: {
                    VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                        Label("Download a model to this phone", systemImage: "arrow.down.circle")
                        Text("Runs on the phone itself, with nothing you type leaving it. "
                           + "Needs the space — the smallest is 351 MB.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ForEach(Preset.all, id: \.name) { preset in
                    Button {
                        editing = preset.endpoint()
                    } label: {
                        VStack(alignment: .leading, spacing: Theme.spacing(.hairline)) {
                            Label(preset.name, systemImage: preset.symbol)
                                .foregroundStyle(Theme.textPrimary)
                            Text(preset.detail)
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                SectionHeading(text: "Add one")
            } footer: {
                Text("Claude needs a bridge, because a subscription is a CLI on a computer rather than an HTTP endpoint and a phone cannot shell out. tools/claudebridge.mjs in this repo is that bridge: run it on a machine signed in to Claude Code and point this at it. Measured on a Raspberry Pi 5: a motion draft in 8.8 s and a training request in 26.5 s, against 766 s for a 7.5B model running locally on the same board.\n\nAnything speaking the OpenAI chat API works — Ollama, LM Studio, llama.cpp's server, vLLM. It does not have to be a big model: the app checks every number that comes back, so a small one that gets a joint name wrong is refused rather than believed.\n\nMeasured on a Raspberry Pi 5, CPU only: a 7.5B Gemma took 766 s to draft one motion; a 2B model with reasoning suppressed answered a fetch in 37 s. Small and quick beats large and correct here, because the checking is done afterwards either way.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        // THE RECESSED GROUND UNDER THE CARDS, which is the one arrangement
        // that lets a coloured word be set anywhere on this screen: `Palette`
        // documents `backgroundSecondary` as carrying the inks at 4.17:1 to
        // 4.27:1, short of what body text owes, so every word that is not grey
        // sits on a `surfacePrimary` row.
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(removing.map(confirmationText) ?? "",
                            isPresented: Binding(get: { removing != nil },
                                                 set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let removing { store.delete(removing) }
                removing = nil
            }
            Button("Keep it", role: .cancel) { removing = nil }
        }
        .sheet(item: $editing) { endpoint in
            NavigationStack { EndpointEditor(store: store, endpoint: endpoint) }
        }
    }

    struct Preset {
        let name: String
        let detail: String
        let symbol: String
        let makeEndpoint: () -> ModelEndpoint
        func endpoint() -> ModelEndpoint { makeEndpoint() }

        static let all: [Preset] = [
            Preset(name: "Ollama on my network",
                   detail: "A Mac, a PC or a Raspberry Pi running ollama serve",
                   symbol: "network") {
                       ModelEndpoint(name: "Ollama", kind: .openAICompatible,
                                     baseURL: "http://192.168.1.10:11434/v1", model: "")
                   },
            Preset(name: "LM Studio on my Mac",
                   detail: "Its local server tab, usually port 1234",
                   symbol: "desktopcomputer") {
                       ModelEndpoint(name: "LM Studio", kind: .openAICompatible,
                                     baseURL: "http://192.168.1.10:1234/v1", model: "")
                   },
            // llama.cpp's own server, on the port its README documents as the
            // default. THE 192.168 SHAPE IS NOT AN ACCIDENT: 8080 is also what
            // "A model on this phone" fills in, and the two would read as the
            // same address if this one said localhost. One is another app on
            // the phone, this one is a machine you can walk over to.
            Preset(name: "llama.cpp on my network",
                   detail: "llama-server on a machine of yours, default port 8080",
                   symbol: "server.rack") {
                       ModelEndpoint(name: "llama.cpp", kind: .openAICompatible,
                                     baseURL: "http://192.168.1.10:8080/v1", model: "")
                   },
            Preset(name: "A model on this phone",
                   detail: "Another app serving a model on localhost",
                   symbol: "iphone") {
                       ModelEndpoint(name: "On this phone", kind: .openAICompatible,
                                     baseURL: "http://localhost:8080/v1", model: "")
                   },
            Preset(name: "Claude, through my subscription",
                   detail: "A machine on your network running claudebridge.mjs",
                   symbol: "sparkles") {
                       // THE ONLY PLACE A RELAY DESTINATION IS NAMED, and it is
                       // named here because this preset is the one thing in the
                       // app that knows what claudebridge.mjs forwards to. A
                       // relay ticked by hand on any other endpoint stays
                       // unnamed, and its privacy note says so rather than
                       // naming a company nobody told the app about.
                       ModelEndpoint(name: "Claude", kind: .openAICompatible,
                                     baseURL: "http://192.168.1.10:8780/v1", model: "sonnet",
                                     timeout: 300, relay: true, relayNote: "Anthropic")
                   },
            // GOOGLE, WITH THE THREE FIELDS THAT MAKE IT WORK AND ONE THAT
            // MAKES IT HONEST. Verified against Google's live documentation:
            // the OpenAI-compat base is /v1beta/openai (which passes this app's
            // "/v1" check), reasoning CANNOT be turned off for its 3-series
            // models — Google says so verbatim — and its reasoning_effort table
            // offers minimal/low/medium/high and no "none". So suppressReasoning
            // must be false here or the app asks for something the counterparty
            // has documented as impossible.
            //
            // NO PRICE ON SCREEN. A hardcoded dollar figure is a claim with an
            // expiry date and nothing here can notice when it passes. "Free key"
            // is the only money claim and it is true.
            Preset(name: "Google AI Studio",
                   detail: "Gemini over the internet, with a key you get free from Google",
                   symbol: "cloud") {
                       var endpoint = ModelEndpoint(
                           name: "Gemini", kind: .openAICompatible,
                           baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                           model: "gemini-3.5-flash-lite",
                           timeout: 120,
                           suppressReasoning: false)
                       // Thinking tokens come out of this same budget, and this
                       // model thinks at minimum. Headroom, not a measurement.
                       endpoint.maxTokens = 4000
                       endpoint.hostNote = ModelEndpoint.googleUnpaidTierNote
                       return endpoint
                   },
            Preset(name: "A service over the internet",
                   detail: "Any OpenAI-compatible endpoint, with a key",
                   symbol: "cloud") {
                       ModelEndpoint(name: "Service", kind: .openAICompatible,
                                     baseURL: "https://api.example.com/v1", model: "",
                                     timeout: 120)   // a hosted model is not the slow case
                   },
        ]
    }
}

/// One endpoint, with the parts a beginner needs first and the parts an expert
/// wants last.
///
/// TWO CONTROLS WEAR THE ACTION COLOUR AND THEY ARE THE TWO THAT LEAVE THE
/// PHONE WITH SOMETHING TO PROVE. "Check this address" asks whether there is an
/// API there at all; "Try a draft" asks whether it can do the one job this app
/// wants. Everything else on the form edits a field — including "Ask what
/// models it has", which sends a request and then fills a text box in, which is
/// help rather than a verdict.
///
/// THE VERDICT IS A WORD BEFORE IT IS A SENTENCE. It used to be a paragraph
/// tinted green or orange, so the one-glance answer to "did that work" was a
/// hue. `StateBadge` makes the word structural — it is the component's whole
/// reason to exist — and the sentence under it, which is `Reachability`'s and
/// which a test asserts, says which of sixteen causes it actually was.
struct EndpointEditor: View {
    @ObservedObject var store: EndpointStore
    @State var endpoint: ModelEndpoint
    @Environment(\.dismiss) private var dismiss

    @State private var available: [String] = []
    @State private var busy = false
    @State private var report: String?
    @State private var failure: String?
    @State private var verdict: Reachability.Verdict?

    /// How long "Check this address" waits, and deliberately NOT the timeout
    /// on the slider below.
    ///
    /// THE TIMEOUT IS FOR DRAFTING, WHICH IS ALLOWED TO TAKE 766 SECONDS. A
    /// check that hung for a quarter of an hour would tell somebody nothing
    /// they could act on, and the one thing being asked for here is a list the
    /// server holds on disk. If fifteen seconds is not enough to hand that
    /// over, that IS the finding, and `Reachability` says so in both readings.
    private static let checkAllowance: Double = 15

    private var addressIsEmpty: Bool {
        endpoint.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Printed and spoken from one expression, so the two cannot round apart.
    private var timeoutSeconds: String { "\(Int(endpoint.timeout)) s" }

    /// The one spinner on this form, wherever it turns.
    ///
    /// ONE TREATMENT, IN ONE PLACE. This screen drew three `ProgressView`s and
    /// each carried its own `.tint`, which is one edit away from two colours
    /// for the same waiting — the drift is invisible until somebody sees two of
    /// them at once, and on this screen `busy` guarantees they do.
    ///
    /// AND NONE OF THE THREE CARRIED A WORD. An unlabelled `ProgressView` has
    /// no accessibility label, so it is not an element and VoiceOver never
    /// stops on it — while the button that was just pressed goes dim in the
    /// same frame. A dimmed control with nothing beside it does not sound like
    /// waiting, it sounds like a refusal, which is the opposite of what
    /// happened.
    ///
    /// THE WORD IS GENERAL BECAUSE THE FLAG IS. `busy` is one boolean, set by
    /// "Ask what models it has", by "Check this address" and by "Try a draft"
    /// alike, so every spinner on the form turns while any one of them runs.
    /// "Checking" would be wrong two times in three — and a wrong verb read
    /// aloud is worse than a plain one, because it tells somebody who cannot
    /// see the screen which button they pressed and names the wrong one.
    /// "Working" is the whole of what this state actually knows.
    private var waiting: some View {
        ProgressView()
            .tint(Theme.brandPrimary)
            .accessibilityLabel(Text("Working"))
    }

    var body: some View {
        List {
            Section {
                TextField("What you will call it", text: $endpoint.name)
            } header: {
                SectionHeading(text: "Name")
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                TextField("http://192.168.1.10:11434/v1", text: $endpoint.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    // MONO BECAUSE IT IS TRANSCRIBED, NOT BECAUSE IT MOVES. A
                    // base URL is copied character by character off another
                    // machine, and proportional figures make 1 and l, and 0 and
                    // O, the same shape on the one field where that is fatal.
                    .font(.body.monospaced())
                Button {
                    Task { await list() }
                } label: {
                    HStack {
                        Label("Ask what models it has", systemImage: "list.bullet")
                        // INSIDE THE LABEL HERE AND NOWHERE ELSE, because this
                        // one is a plain row rather than a filled capsule:
                        // there is no orange for the spinner to be drawn on and
                        // no shape for it to stretch. Being inside the label is
                        // also why its word lands on the BUTTON rather than
                        // beside it — a button's label is composed from its
                        // subtree, so this row reads "Ask what models it has,
                        // Working" while the request is out, which is the
                        // sentence somebody who cannot see the spinner needs.
                        if busy { Spacer(); waiting }
                    }
                }
                .disabled(busy)
            } header: {
                SectionHeading(text: "Address")
            } footer: {
                Text("Ends in /v1. Ollama, LM Studio and llama.cpp all serve their OpenAI-compatible API there, and without it the request lands on the wrong route.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            if available.isEmpty {
                Section {
                    TextField("gemma4:e4b-it-qat", text: $endpoint.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    SectionHeading(text: "Model")
                }
                .listRowBackground(Theme.surfacePrimary)
            } else {
                Section {
                    Picker("Model", selection: $endpoint.model) {
                        ForEach(available, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                } header: {
                    SectionHeading(text: "Model")
                }
                .listRowBackground(Theme.surfacePrimary)
            }

            Section {
                Button {
                    Task { await check() }
                } label: {
                    Label("Check this address",
                          systemImage: "antenna.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .disabled(busy || addressIsEmpty)
                // THE SPINNER SITS OUTSIDE THE CAPSULE. Inside it, it would be
                // drawn in the app's tint against Duck Orange — two accents on
                // one shape — and it would stretch the control as it appeared,
                // moving a button under a thumb that is already on it.
                if busy {
                    waiting.frame(maxWidth: .infinity)
                }
                // A DISABLED CONTROL WITH NOTHING BESIDE IT IS A SILENT
                // REFUSAL. The sentence comes from StudioKit so a test owns it.
                if addressIsEmpty {
                    Text(Reachability.nothingToCheck)
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let verdict {
                    VStack(alignment: .leading, spacing: Theme.spacing(.tight)) {
                        StateBadge(text: standing(verdict).text,
                                   state: standing(verdict).state)
                        Text(verdict.sentence)
                            .font(.footnote).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Theme.spacing(.hairline))
                }
            } header: {
                SectionHeading(text: "Check")
            } footer: {
                Text("Asks the address for its list of models — the one thing a server answers without running anything, so this works before a model is named. It waits \(Int(Self.checkAllowance)) seconds rather than the timeout below, and says which of the several very different reasons an address can fail it hit: nothing listening, nothing serving an API there, a name that did not resolve, a key it wanted, a connection iOS would not make, or a machine that is simply slow.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                Button {
                    Task { await test() }
                } label: {
                    Label("Try a draft", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
                .disabled(busy || endpoint.model.isEmpty)
                // Outside the capsule, for the reason given above.
                if busy {
                    waiting.frame(maxWidth: .infinity)
                }
                // The other disabled control on this screen, with its reason.
                // The refusal already exists and is already tested — it is what
                // Save would say — so this says the same words rather than
                // inventing a second set.
                if endpoint.model.isEmpty {
                    Text(ModelEndpoint.Refusal.emptyModel.message)
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let report {
                    // A DRAFT THAT CAME BACK AND PASSED THE CHECKER IS A
                    // MEASUREMENT — of this machine, at this moment, in tokens
                    // a second. Teal is this app's claim that a machine
                    // produced what you are reading.
                    Text(report).font(.footnote).foregroundStyle(Theme.measured)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(Theme.refused)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text("Asks it for a real motion and puts the answer through the same checker a typed draft goes through. A small model on a small board is SLOW — the result says how slow, in tokens a second, so the wait makes sense.")
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)

            Section {
                DisclosureGroup("Advanced") {
                    // Hidden, and carried by the slider instead: a Slider is
                    // its own element with the adjustable trait and never
                    // reads the row above it, so this said the number to
                    // somebody who then met an anonymous "50 percent". The
                    // seconds matter — the default allows for a board that
                    // takes 766 s to write one motion, and somebody who trims
                    // it blind gets a timeout they will read as a broken app.
                    //
                    // A TELEMETRY ROW BECAUSE THE NUMBER MOVES UNDER A THUMB.
                    // Tabular figures are what stop "1800 s" collapsing to
                    // "30 s" and shifting the row while it is being dragged.
                    TelemetryRow(label: "Timeout",
                                 value: "\(Int(endpoint.timeout))", unit: "s")
                        .accessibilityHidden(true)
                    Slider(value: $endpoint.timeout, in: 30...1800, step: 30)
                        .accessibilityLabel(Text("Timeout"))
                        .accessibilityValue(Text(timeoutSeconds))
                    Toggle("Forwards to a model elsewhere", isOn: $endpoint.relay)
                    Text("On for a bridge — a machine on your network that answers by asking something else, like a Claude subscription. It changes nothing about the request and everything about where your words end up, which is why the note below has to know.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle("Suppress reasoning", isOn: $endpoint.suppressReasoning)
                    Text("A thinking model asked for a motion can spend its whole budget reasoning and answer with nothing — measured at 725 seconds and an empty reply. This sends reasoning_effort: none, which local servers honour. Turn it off only if a hosted service rejects it.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SecureField("Bearer token, if it needs one", text: Binding(
                        get: { endpoint.apiKey ?? "" },
                        set: { endpoint.apiKey = $0.isEmpty ? nil : $0 }))
                    Text("Measured on a Raspberry Pi 5, CPU only: a 7.5B Gemma at Q4 took 766 seconds to write one motion — about a quarter of a token a second. A 2B model on the same board is several times quicker. The default timeout allows for the slow case on purpose; the fix for the wait is a smaller model, not a shorter timeout.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } footer: {
                Text(endpoint.privacyNote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(Theme.surfacePrimary)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundSecondary)
        .navigationTitle(endpoint.name.isEmpty ? "New model" : endpoint.name)
        .navigationBarTitleDisplayMode(.inline)
        // A VERDICT IS ABOUT ONE ADDRESS, AND DIES WITH IT. `check()` cleared
        // this only on its way in, so a green "192.168.1.10 port 11434
        // answered … The address is right." survived being edited into a
        // different address entirely — the reassurance outliving the thing it
        // was about, which is the class of stale claim this app is built
        // against. Anything that changes what would be probed clears it.
        .onChange(of: endpoint.baseURL) { _, _ in verdict = nil }
        .onChange(of: endpoint.model) { _, _ in verdict = nil }
        .onChange(of: endpoint.relay) { _, _ in verdict = nil }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
    }

    /// The verdict as a word and a dot.
    ///
    /// THE COLOUR SPLITS ON `isReady`, WHICH IS THE PREDICATE THIS SCREEN HAS
    /// ALWAYS USED. Before the badge existed the sentence was tinted green when
    /// `verdict.isReady` and orange otherwise; restyling it moved the test to
    /// `foundAnAPI`, and that is a wider set — `Reachability.Verdict` documents
    /// `isReady` as "`foundAnAPI` minus the empty shelf", so `noModelsLoaded`
    /// and `modelNamesUnreadable` crossed over into the success reading. Both
    /// are addresses that cannot draft anything: one has no model on it, the
    /// other answered with a list this app could not read a name out of. A
    /// badge saying "Answered" above a sentence saying to go and load a model
    /// on that machine is the badge contradicting the paragraph it sits on, and
    /// the badge is what a glance takes.
    ///
    /// SO THE COLOUR HAS TWO STATES AND THE WORD HAS THREE. Everything that is
    /// not ready takes the same non-success state, which is the split the
    /// original made; the word then separates the two very different ways of
    /// not being ready, because "Unreachable" is false of a machine that
    /// answered and "Not ready" is true of both. The word is the information
    /// and the colour is the hint — `CatalogueOriginPill` makes the same
    /// argument for the same reason — and `verdict.sentence`, which is
    /// StudioKit's and which a test asserts, says which of the sixteen causes
    /// it actually was.
    ///
    /// `idle` FOR ONE THAT IS READY: powered, and standing still, which is what
    /// a model server is between requests. It is also the teal, which is this
    /// app's colour for something a machine said.
    private func standing(_ verdict: Reachability.Verdict)
        -> (text: String, state: RobotState) {
        if verdict.isReady { return ("Answered", .idle) }
        return (verdict.foundAnAPI ? "Not ready" : "Unreachable", .offline)
    }

    private func save() {
        do {
            try endpoint.validate()
            store.save(endpoint)
            store.selectedID = endpoint.id
            dismiss()
        } catch let refusal as ModelEndpoint.Refusal {
            failure = refusal.message
        } catch {
            failure = "\(error)"
        }
    }

    private func list() async {
        busy = true; failure = nil
        defer { busy = false }
        do {
            available = try await DraftEngine.models(at: endpoint)
            // NOT "IT LISTED NO MODELS", WHICH THIS CANNOT KNOW. The list comes
            // back as the names that could be read, so an empty one means
            // either an empty shelf or a reply this app could not read names
            // out of — and it cannot tell which from here. Check this address
            // can, because it keeps both counts.
            if available.isEmpty {
                failure = "It answered, and no model names could be read out of the reply. "
                        + "Check this address says which of the two that was. Either way you "
                        + "can type the name that machine uses into Model."
            }
            else if endpoint.model.isEmpty { endpoint.model = available[0] }
        } catch let refusal as ModelEndpoint.Refusal {
            failure = refusal.message
        } catch {
            failure = "\(error.localizedDescription)"
        }
    }

    /// Ask the address for its model list, write down exactly what came back,
    /// and let StudioKit say what it means.
    ///
    /// THE VIEW OBSERVES AND STUDIOKIT JUDGES, and the split is the whole
    /// design: everything below writes into an `Observation` — a code, a
    /// status, a body, a clock — and not one sentence is composed here. That is
    /// what lets every branch of the answer be asserted by `swift test` on a
    /// machine with no phone, no iOS and no Ollama on it.
    ///
    /// NOTE WHAT IS NOT WRITTEN DOWN: whether Local Network permission was
    /// granted. Nothing in this app reads that switch, so nothing here claims
    /// to — `Reachability` offers it as the shape of two failures that cannot
    /// be anything else, and says in the same breath that it is not a reading.
    private func check() async {
        busy = true; failure = nil; report = nil; verdict = nil
        defer { busy = false }

        // The address is refused before anything is sent, by the same rule Save
        // uses — so a plaintext address off your own network never leaves here.
        let url: URL
        do {
            url = try endpoint.modelsURL()
        } catch let refusal as ModelEndpoint.Refusal {
            failure = refusal.message
            return
        } catch {
            failure = error.localizedDescription
            return
        }

        var seen = Reachability.Observation(host: url.host ?? endpoint.baseURL,
                                            port: url.port,
                                            scheme: url.scheme ?? "http",
                                            path: url.path,
                                            allowance: Self.checkAllowance)
        var request = URLRequest(url: url)
        request.timeoutInterval = Self.checkAllowance
        if let key = endpoint.apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            seen.seconds = Date().timeIntervalSince(started)
            seen.status = (response as? HTTPURLResponse)?.statusCode
            // Decoded rather than initialised from Data so a body cut mid
            // character still quotes; a nil here would read as "no body at all".
            seen.body = String(decoding: data.prefix(400), as: UTF8.self)
            // nil and 0 MEAN DIFFERENT THINGS DOWNSTREAM: nil is "that was not
            // a model list", 0 is "a model list that named nothing".
            //
            // AND TWO COUNTS, NOT ONE, BECAUSE ONE OF THEM OVERCLAIMED. Only
            // the names this app can read were counted, so a 200 carrying three
            // entries with no String id read as zero — and the person was told
            // "the shelf is empty, load a model on that machine" about a
            // machine that had three. The entry count is what tells an empty
            // shelf from a list this app cannot read; StudioKit decides which
            // it was.
            if let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let listed = top["data"] as? [[String: Any]] {
                seen.listedEntries = listed.count
                seen.modelsFound = listed.compactMap { $0["id"] as? String }.count
            }
        } catch {
            seen.seconds = Date().timeIntervalSince(started)
            seen.urlErrorCode = (error as NSError).code
            seen.systemText = error.localizedDescription
        }
        verdict = Reachability.explain(seen)
    }

    private func test() async {
        busy = true; failure = nil; report = nil
        defer { busy = false }
        do {
            let answer = try await DraftEngine.ask(endpoint, kind: .motion,
                                                   prompt: "take a small bow",
                                                   knownIntents: [])
            let proposal = try ChatDraft.motion(fromJSON: answer.json)
            let draft = try proposal.resolve()
            var line = String(format: "Drafted \"%@\" — %d keyframes, in %.0f s",
                              draft.name, draft.keys.count, answer.seconds)
            if let rate = answer.tokensPerSecond {
                line += String(format: " (%.1f tokens/s)", rate)
            }
            report = line + ". It passed the checker."
        } catch let refusal as ModelEndpoint.Refusal {
            failure = refusal.message
        } catch let wire as ChatWire.WireError {
            failure = wire.message
        } catch let draft as ChatDraft.DraftError {
            failure = draft.message
        } catch let unresolvable as MotionProposal.Unresolvable {
            failure = "It answered, but the draft was refused: \(unresolvable.message)"
        } catch {
            failure = error.localizedDescription
        }
    }
}
