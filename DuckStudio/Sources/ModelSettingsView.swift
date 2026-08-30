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
struct ModelSettingsView: View {
    @ObservedObject var store: EndpointStore
    @State private var editing: ModelEndpoint?

    var body: some View {
        List {
            Section {
                ForEach(store.endpoints) { endpoint in
                    Button {
                        if endpoint.kind == .appleOnDevice {
                            store.selectedID = endpoint.id
                        } else {
                            editing = store.armed(endpoint)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(endpoint.name).foregroundStyle(.primary)
                                Text(endpoint.kind == .appleOnDevice
                                     ? "On this phone, no setup"
                                     : "\(endpoint.model) · \(URL(string: endpoint.baseURL)?.host ?? endpoint.baseURL)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.selectedID == endpoint.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .swipeActions {
                        if endpoint.kind != .appleOnDevice {
                            Button("Remove", role: .destructive) { store.delete(endpoint) }
                        }
                    }
                }
            } header: {
                Text("Draft with")
            } footer: {
                Text(store.selected.privacyNote)
            }

            Section {
                ForEach(Preset.all, id: \.name) { preset in
                    Button {
                        editing = preset.endpoint()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(preset.name, systemImage: preset.symbol)
                            Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Add one")
            } footer: {
                Text("Claude needs a bridge, because a subscription is a CLI on a computer rather than an HTTP endpoint and a phone cannot shell out. tools/claudebridge.mjs in this repo is that bridge: run it on a machine signed in to Claude Code and point this at it. Measured on a Raspberry Pi 5: a motion draft in 8.8 s and a training request in 26.5 s, against 766 s for a 7.5B model running locally on the same board.\n\nAnything speaking the OpenAI chat API works — Ollama, LM Studio, llama.cpp's server, vLLM. It does not have to be a big model: the app checks every number that comes back, so a small one that gets a joint name wrong is refused rather than believed.\n\nMeasured on a Raspberry Pi 5, CPU only: a 7.5B Gemma took 766 s to draft one motion; a 2B model with reasoning suppressed answered a fetch in 37 s. Small and quick beats large and correct here, because the checking is done afterwards either way.")
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.inline)
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
            Preset(name: "A model on this phone",
                   detail: "Another app serving a model on localhost",
                   symbol: "iphone") {
                       ModelEndpoint(name: "On this phone", kind: .openAICompatible,
                                     baseURL: "http://localhost:8080/v1", model: "")
                   },
            Preset(name: "Claude, through my subscription",
                   detail: "A machine on your network running claudebridge.mjs",
                   symbol: "sparkles") {
                       ModelEndpoint(name: "Claude", kind: .openAICompatible,
                                     baseURL: "http://192.168.1.10:8780/v1", model: "sonnet",
                                     timeout: 300, relay: true)
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
struct EndpointEditor: View {
    @ObservedObject var store: EndpointStore
    @State var endpoint: ModelEndpoint
    @Environment(\.dismiss) private var dismiss

    @State private var available: [String] = []
    @State private var busy = false
    @State private var report: String?
    @State private var failure: String?

    var body: some View {
        List {
            Section("Name") {
                TextField("What you will call it", text: $endpoint.name)
            }

            Section {
                TextField("http://192.168.1.10:11434/v1", text: $endpoint.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    Task { await list() }
                } label: {
                    HStack {
                        Label("Ask what models it has", systemImage: "list.bullet")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy)
            } header: {
                Text("Address")
            } footer: {
                Text("Ends in /v1. Ollama, LM Studio and llama.cpp all serve their OpenAI-compatible API there, and without it the request lands on the wrong route.")
            }

            if available.isEmpty {
                Section("Model") {
                    TextField("gemma4:e4b-it-qat", text: $endpoint.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } else {
                Section("Model") {
                    Picker("Model", selection: $endpoint.model) {
                        ForEach(available, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
            }

            Section {
                Button {
                    Task { await test() }
                } label: {
                    HStack {
                        Label("Try a draft", systemImage: "play.circle")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(busy || endpoint.model.isEmpty)
                if let report {
                    Text(report).font(.footnote).foregroundStyle(.green)
                }
                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("Asks it for a real motion and puts the answer through the same checker a typed draft goes through. A small model on a small board is SLOW — the result says how slow, in tokens a second, so the wait makes sense.")
            }

            Section {
                DisclosureGroup("Advanced") {
                    HStack {
                        Text("Timeout")
                        Spacer()
                        Text("\(Int(endpoint.timeout)) s").foregroundStyle(.secondary)
                    }
                    Slider(value: $endpoint.timeout, in: 30...1800, step: 30)
                    Toggle("Forwards to a model elsewhere", isOn: $endpoint.relay)
                    Text("On for a bridge — a machine on your network that answers by asking something else, like a Claude subscription. It changes nothing about the request and everything about where your words end up, which is why the note below has to know.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Suppress reasoning", isOn: $endpoint.suppressReasoning)
                    Text("A thinking model asked for a motion can spend its whole budget reasoning and answer with nothing — measured at 725 seconds and an empty reply. This sends reasoning_effort: none, which local servers honour. Turn it off only if a hosted service rejects it.")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("Bearer token, if it needs one", text: Binding(
                        get: { endpoint.apiKey ?? "" },
                        set: { endpoint.apiKey = $0.isEmpty ? nil : $0 }))
                    Text("Measured on a Raspberry Pi 5, CPU only: a 7.5B Gemma at Q4 took 766 seconds to write one motion — about a quarter of a token a second. A 2B model on the same board is several times quicker. The default timeout allows for the slow case on purpose; the fix for the wait is a smaller model, not a shorter timeout.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } footer: {
                Text(endpoint.privacyNote)
            }
        }
        .navigationTitle(endpoint.name.isEmpty ? "New model" : endpoint.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
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
            if available.isEmpty { failure = "It answered, but listed no models." }
            else if endpoint.model.isEmpty { endpoint.model = available[0] }
        } catch let refusal as ModelEndpoint.Refusal {
            failure = refusal.message
        } catch {
            failure = "\(error.localizedDescription)"
        }
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

